`timescale 1ns / 1ps

module tb_conv_accelerator();

    // --- 1. Sinyal Tanımları ---
    reg clk;
    reg rst_n;
    reg start;
    wire done;
    wire busy;

    // RAM Arayüzü
    wire [10:0] ram_addr;
    reg signed [7:0] ram_rdata;
    
    // Çıkışlar
    wire [12:0] out_ram_addr;
    wire out_ram_wen;
    wire signed [7:0] out_ram_wdata;

    // --- 2. Hızlandırıcı Modülünü Çağır (Instantiate) ---
    conv_accelerator uut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .busy(busy),
        .ram_addr(ram_addr),
        .ram_rdata(ram_rdata),
        .out_ram_addr(out_ram_addr),
        .out_ram_wen(out_ram_wen),
        .out_ram_wdata(out_ram_wdata)
    );

    // --- 3. Saat Sinyali Oluştur (100 MHz) ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // Her 5ns'de bir tersle (Toplam periyot 10ns)
    end

    // --- 4. Sahte RAM Davranışı ---
    always @(posedge clk) begin
        ram_rdata <= ram_addr[7:0]; 
    end

    // --- 5. Test Senaryosu ---
    initial begin
        // Simülasyon dosya ayarları (Waveform görmek için)
        $dumpfile("test.vcd");
        $dumpvars(0, tb_conv_accelerator);

        // A. Başlangıç: Reset at
        rst_n = 0;
        start = 0;
        #100; // 100ns bekle
        
        // B. Reset'i bırak
        rst_n = 1;
        #20;

        // C. BAŞLAT KOMUTU VER
        $display("--- SIMULASYON BASLIYOR ---");
        $display("Hizlandiriciya Start veriliyor...");
        start = 1;
        #10; // Bir clock boyu 1 tut
        start = 0;

        // D. İşlem bitene kadar bekle (Done sinyali 1 olana kadar)
        wait(done == 1);
        
        $display("--- ISLEM TAMAMLANDI! ---");
        $display("Tebrikler, done sinyali alindi.");
        
        #100;
        $finish; // Simülasyonu bitir
    end

endmodule