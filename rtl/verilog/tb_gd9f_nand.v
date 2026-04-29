`timescale 1ns / 1ps

module tb_gd9f_nand;

    reg clk;
    reg rst;
    reg erase_en;
    reg [28:0] erase_addr;
    wire erase_fail, erase_done;

    reg wr_en;
    reg [28:0] wr_addr;
    reg [10:0] wr_len;
    reg [15:0] wr_data;
    reg wr_dv;
    wire wr_err, wr_done;

    reg rd_en;
    reg [28:0] rd_addr;
    reg [10:0] rd_len;
    wire rd_err, rd_ready;
    reg rd_fifo_en;
    wire [15:0] rd_data;

    wire rb_n;
    wire wp_n;
    wire ce_n, cle, we_n, ale, re_n;
    wire nand_busy;
    wire [7:0] nand_io;

    gd9f_nand_ctrl dut (
        .i_clk_in(clk),
        .i_rst(rst),
        .i_erase_en(erase_en),
        .i_erase_addr(erase_addr),
        .o_erase_fail(erase_fail),
        .o_erase_done(erase_done),
        .i_wr_en(wr_en),
        .i_wr_addr(wr_addr),
        .i_wr_len(wr_len),
        .i_clk_wr_fifo(clk),
        .i_wr_data(wr_data),
        .i_wr_dv(wr_dv),
        .o_wr_err(wr_err),
        .o_wr_done(wr_done),
        .i_rd_en(rd_en),
        .i_rd_addr(rd_addr),
        .i_rd_len(rd_len),
        .o_rd_err(rd_err),
        .o_rd_ready(rd_ready),
        .i_clk_rd_fifo(clk),
        .i_rd_fifo_en(rd_fifo_en),
        .o_rd_data(rd_data),
        .i_rb_n(rb_n),
        .o_wp_n(wp_n),
        .o_ce_n(ce_n),
        .o_cle(cle),
        .o_we_n(we_n),
        .o_ale(ale),
        .o_re_n(re_n),
        .o_nand_busy(nand_busy),
        .io_nand_data(nand_io)
    );

    nand_flash_model_gd9f #(.BUSY_NS(500)) nand_m (
        .io_data(nand_io),
        .i_ce_n(ce_n),
        .i_cle(cle),
        .i_ale(ale),
        .i_we_n(we_n),
        .i_re_n(re_n),
        .o_rb_n(rb_n)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst = 1;
        erase_en = 0;
        wr_en = 0;
        rd_en = 0;
        wr_dv = 0;
        rd_fifo_en = 0;
        erase_addr = 0;
        wr_addr = 0;
        rd_addr = 0;
        wr_len = 0;
        rd_len = 0;
        #40 rst = 0;
        #40;
        erase_addr = 29'h1000;
        erase_en = 1;
        #10 erase_en = 0;
        @(posedge clk);
        while (!erase_done) @(posedge clk);
        #200 $finish;
    end

endmodule
