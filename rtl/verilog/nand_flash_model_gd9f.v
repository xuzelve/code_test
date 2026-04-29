// Minimal NAND model for tb: WE# latches cmd; D0/10/30 assert busy then release.
`timescale 1ns / 1ps

module nand_flash_model_gd9f #(
    parameter int unsigned BUSY_NS = 2000
)(
    inout  wire [7:0] io_data,
    input  wire       i_ce_n,
    input  wire       i_cle,
    input  wire       i_ale,
    input  wire       i_we_n,
    input  wire       i_re_n,
    output reg        o_rb_n
);

    reg [7:0] cmd;
    reg busy_until_set;
    integer busy_until;

    assign io_data = (!i_ce_n && !i_cle && !i_ale && !i_re_n) ? 8'hC0 : 8'hZZ;

    initial begin
        o_rb_n = 1'b1;
        busy_until_set = 0;
    end

    always @(posedge i_we_n) begin
        if (!i_ce_n && i_cle && !i_ale) begin
            cmd = io_data;
            if (io_data == 8'hd0 || io_data == 8'h10 || io_data == 8'h30) begin
                o_rb_n = 1'b0;
                busy_until = $time + BUSY_NS;
                busy_until_set = 1;
            end
        end
    end

    always #100 begin
        if (busy_until_set && $time >= busy_until) begin
            o_rb_n = 1'b1;
            busy_until_set = 0;
        end
    end

endmodule
