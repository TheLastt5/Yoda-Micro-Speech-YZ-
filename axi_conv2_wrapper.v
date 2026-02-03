`timescale 1ns / 1ps

module axi_conv_wrapper # (
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 4
)(
    // --- 1. AXI4-Lite Arayüzü (Islemciyle Konusan Kisim) ---
    input wire  s_axi_aclk,
    input wire  s_axi_aresetn,
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] s_axi_awaddr,
    input wire [2 : 0] s_axi_awprot,
    input wire  s_axi_awvalid,
    output wire s_axi_awready,
    input wire [C_S_AXI_DATA_WIDTH-1 : 0] s_axi_wdata,
    input wire [C_S_AXI_DATA_WIDTH/8-1 : 0] s_axi_wstrb,
    input wire  s_axi_wvalid,
    output wire s_axi_wready,
    output wire [1 : 0] s_axi_bresp,
    output wire  s_axi_bvalid,
    input wire  s_axi_bready,
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] s_axi_araddr,
    input wire [2 : 0] s_axi_arprot,
    input wire  s_axi_arvalid,
    output wire s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] s_axi_rdata,
    output wire [1 : 0] s_axi_rresp,
    output wire  s_axi_rvalid,
    input wire  s_axi_rready,

    //BRAM Portlari
    // 1. Okuma Portu
    output wire [10:0] bram_img_addr,
    input  wire [7:0]  bram_img_rdata, // Disaridan veri gelecek!
    output wire        bram_img_en,    // RAM'i aktif etme sinyali

    //2. Yazma Portu
    output wire [12:0] bram_out_addr,
    output wire [7:0]  bram_out_wdata,
    output wire        bram_out_wen,   // Yazma izni
    output wire        bram_out_en     // RAM'i aktif etme sinyali
);

    //Ic Sinyaller
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_awaddr;
    reg  axi_awready;
    reg  axi_wready;
    reg [1 : 0] axi_bresp;
    reg  axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_araddr;
    reg  axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1 : 0] axi_rdata;
    reg [1 : 0] axi_rresp;
    reg  axi_rvalid;

    // Kullanici Registerlari
    reg [31:0] slv_reg0; // CTRL_REG
    reg [31:0] slv_reg1; // STATUS_REG
    
    // AXI Cikis Atamalari
    assign s_axi_awready = axi_awready;
    assign s_axi_wready  = axi_wready;
    assign s_axi_bresp   = axi_bresp;
    assign s_axi_bvalid  = axi_bvalid;
    assign s_axi_arready = axi_arready;
    assign s_axi_rdata   = axi_rdata;
    assign s_axi_rresp   = axi_rresp;
    assign s_axi_rvalid  = axi_rvalid;

    // Hizlandirici Baglantilari
    wire accel_done;
    wire accel_busy;
    reg  accel_start;
    
    //RAM ENABLE SINYALLERI

    assign bram_img_en = 1'b1; 
    assign bram_out_en = 1'b1;

    //Hizlandirici Modülünü Cagir
    conv_accelerator my_engine (
        .clk(s_axi_aclk),
        .rst_n(s_axi_aresetn),
        .start(accel_start),
        .done(accel_done),
        .busy(accel_busy),
        
        // RAM Baglantilari
        .ram_addr(bram_img_addr),
        .ram_rdata(bram_img_rdata),
        
        .out_ram_addr(bram_out_addr),
        .out_ram_wen(bram_out_wen),
        .out_ram_wdata(bram_out_wdata)
    );

    //AXI Yazma Mantigi
    always @( posedge s_axi_aclk ) begin
        if ( s_axi_aresetn == 1'b0 ) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_bvalid  <= 1'b0;
            slv_reg0    <= 0;
            accel_start <= 0;
        end else begin
            if (~axi_awready && s_axi_awvalid && s_axi_wvalid) begin
                axi_awready <= 1'b1;
                axi_wready <= 1'b1;
                if (s_axi_awaddr[3:2] == 2'b00) begin
                    slv_reg0 <= s_axi_wdata;
                    if (s_axi_wdata[0] == 1'b1) 
                        accel_start <= 1'b1;
                    else
                        accel_start <= 1'b0;
                end
            end else begin
                axi_awready <= 1'b0;
                axi_wready <= 1'b0;
                accel_start <= 1'b0;
            end

            if (axi_awready && s_axi_awvalid && ~axi_bvalid && axi_wready && s_axi_wvalid)
                axi_bvalid <= 1'b1;
            else if (s_axi_bready && axi_bvalid)
                axi_bvalid <= 1'b0;
        end
    end

    //AXI Okuma Mantigi
    always @( posedge s_axi_aclk ) begin
        if ( s_axi_aresetn == 1'b0 ) begin
            axi_arready <= 1'b0;
            axi_rvalid <= 1'b0;
            axi_rdata <= 0;
        end else begin
            if (~axi_arready && s_axi_arvalid) begin
                axi_arready <= 1'b1;
                axi_araddr  <= s_axi_araddr;
            end else begin
                axi_arready <= 1'b0;
            end

            if (axi_arready && s_axi_arvalid && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                case (axi_araddr[3:2])
                    2'b00: axi_rdata <= slv_reg0;
                    2'b01: axi_rdata <= {30'b0, accel_busy, accel_done};
                    default: axi_rdata <= 0;
                endcase
            end else if (axi_rvalid && s_axi_rready) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

endmodule