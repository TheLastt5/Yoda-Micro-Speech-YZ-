module conv_accelerator (
    input wire clk,             
    input wire rst_n,           
    
    // --- Kontrol Arayüzü (İşlemciden gelen emirler) ---
    input wire start,           
    output reg done,            
    output reg busy,            
    
    // --- Hafıza Arayüzü (SRAM ile konuşmak için) ---
    // Giriş verisini okumak için:
    output reg [10:0] ram_addr, 
    input wire signed [7:0] ram_rdata, 
    
    // Sonucu yazmak için (Hızlandırıcının kendi çıkış belleği):
    output reg [12:0] out_ram_addr, 
    output reg out_ram_wen,         
    output reg signed [7:0] out_ram_wdata 
);

    // --- Parametreler (Analizden elde ettiğimiz sayılar) ---
    localparam INPUT_H = 49;
    localparam INPUT_W = 40;
    localparam FILTER_H = 10;
    localparam FILTER_W = 8;
    localparam STRIDE = 2;
    localparam PAD_TOP = 4;  
    localparam PAD_LEFT = 3; 
    
    localparam INPUT_ZERO_POINT = -128; 

    // --- İçerde Kullanılacak Ağırlıklar (ROM) ---
    reg signed [7:0] weights [0:639];
    
    // 8 adet 32-bitlik bias
    reg signed [31:0] biases [0:7];

    // Başlangıçta ağırlıkları dosyadan yüklemek için (Simülasyon için)
    initial begin
        $readmemh("weights.hex", weights); 
        $readmemh("biases.hex", biases);   
    end

// --- 1. Değişkenler (Registers & Counters) ---
    // Durum Makinesi için durumlar
    localparam IDLE  = 2'b00; // Bekleme modu
    localparam CALC  = 2'b01; // Hesaplama modu (Çarpma/Toplama)
    localparam WRITE = 2'b10; // Sonucu kaydetme modu
    localparam DONE  = 2'b11; // Bitiş modu

    reg [1:0] state; // Şu an hangi durumdayız?

    // Döngü Sayaçları (Nested Loops)
    reg [4:0] out_y;      // Çıktı Satırı (0-24)
    reg [4:0] out_x;      // Çıktı Sütunu (0-19)
    reg [3:0] filter_ch;  // Hangi filtre? (0-7)
    reg [3:0] k_y;        // Filtre Yüksekliği (0-9)
    reg [3:0] k_x;        // Filtre Genişliği (0-7)

    // Matematiksel Değişkenler
    reg signed [31:0] acc; // Toplam (Accumulator) - Büyük seçtik taşmasın diye
    reg signed [31:0] mult_result; // Çarpma sonucu
    
    // Anlık hesaplanan koordinatlar
    reg signed [10:0] cur_row; // O an okunan giriş satırı
    reg signed [10:0] cur_col; // O an okunan giriş sütunu
    reg signed [11:0] input_idx; // RAM adresi

    // --- 2. Ana Mantık (Sequential Logic) ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;
            busy <= 0;
            out_ram_wen <= 0;
            // Tüm sayaçları sıfırla
            out_y <= 0; out_x <= 0; filter_ch <= 0; k_y <= 0; k_x <= 0;
            acc <= 0;
        end else begin
            case (state)
                // --- DURUM 1: IDLE (Bekleme) ---
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        state <= CALC; // Start gelince hesaplamaya geç
                        busy <= 1;
                        // Sayaçları ve toplamı sıfırla
                        out_y <= 0; out_x <= 0; filter_ch <= 0; 
                        k_y <= 0; k_x <= 0;
                        acc <= biases[0]; // Toplamaya Bias ile başla!
                    end
                end

                // --- DURUM 2: CALC (Hesaplama / Convolution) ---
                CALC: begin
                    out_ram_wen <= 0; // Henüz yazma yapma

                    // 1. Koordinatları Hesapla (Padding Mantığı)
                    // Formül: (ÇıkışY * Stride) + KernelY - PadTop
                    cur_row = (out_y * STRIDE) + k_y - PAD_TOP;
                    cur_col = (out_x * STRIDE) + k_x - PAD_LEFT;

                    // 2. Sınır Kontrolü (Boundary Check)
                    if (cur_row >= 0 && cur_row < INPUT_H && cur_col >= 0 && cur_col < INPUT_W) begin
                        // RAM Adresini hesapla: Satır * Genişlik + Sütun
                        input_idx = (cur_row * INPUT_W) + cur_col;
                        ram_addr <= input_idx; // RAM'e adresi gönder
                        

                        acc <= acc + ($signed(ram_rdata) + 128) * weights[filter_ch * 80 + k_y * 8 + k_x];
                    end 
                    // else: Padding bölgesindeyiz, acc değişmez (0 eklenir).

                    // 3. Sayaçları İlerlet (Kernel Döngüsü)
                    if (k_x < FILTER_W - 1) begin
                        k_x <= k_x + 1;
                    end else begin
                        k_x <= 0;
                        if (k_y < FILTER_H - 1) begin
                            k_y <= k_y + 1;
                        end else begin
                            // Kernel bitti, bir sonraki duruma geç
                            state <= WRITE; 
                        end
                    end
                end

                // --- DURUM 3: WRITE (Sonucu Kaydet) ---
                WRITE: begin
                    // ReLU Aktivasyonu (Negatifse 0 yap)
                    if (acc < 0) 
                        out_ram_wdata <= 0;
                    else if (acc > 127) // 8-bit tavan kontrolü (Clipping)
                        out_ram_wdata <= 127;
                    else 
                        out_ram_wdata <= acc[7:0];


                    out_ram_addr <= (out_y * 20 * 8) + (out_x * 8) + filter_ch;
                    out_ram_wen <= 1; // Yaz!

                    // --- Ana Döngüleri İlerlet ---
                    // Sıra: Channel -> X -> Y
                    state <= CALC; // Varsayılan olarak hesaplamaya dön
                    
                    // Kernel sayaçlarını sıfırla
                    k_y <= 0; k_x <= 0; 
                    
                    // Bir sonraki filtreye geç
                    if (filter_ch < 7) begin
                        filter_ch <= filter_ch + 1;
                        acc <= biases[filter_ch + 1]; // Yeni bias'ı yükle
                    end else begin
                        filter_ch <= 0;
                        acc <= biases[0]; // Reset bias
                        
                        // Bir sonraki sütuna (X) geç
                        if (out_x < 19) begin // 20 sütun var (0-19)
                            out_x <= out_x + 1;
                        end else begin
                            out_x <= 0;
                            
                            // Bir sonraki satıra (Y) geç
                            if (out_y < 24) begin // 25 satır var (0-24)
                                out_y <= out_y + 1;
                            end else begin
                                // TÜM RESİM BİTTİ!
                                state <= DONE;
                            end
                        end
                    end
                end

                // --- DURUM 4: DONE (Bitiş) ---
                DONE: begin
                    done <= 1;
                    busy <= 0;
                    out_ram_wen <= 0;
                    state <= IDLE; // Başa dön
                end
            endcase
        end
    end

endmodule