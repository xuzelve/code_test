// Single-clock synchronous FIFO, 16-bit. rst: synchronous high-active.

`timescale 1ns / 1ps

module sync_fifo_16 #(
    parameter int unsigned AW = 9
)(
    input  wire clk,
    input  wire rst,
    input  wire [15:0] wr_data,
    input  wire wr_en,
    output wire full,
    output reg [15:0] rd_data,
    input  wire rd_en,
    output wire empty
);

    localparam int unsigned DEPTH = 1 << AW;
    reg [15:0] mem [0:DEPTH-1];
    reg [AW-1:0] waddr, raddr;
    reg [AW:0] cnt;

    assign full  = (cnt == DEPTH[AW:0]);
    assign empty = (cnt == 0);

    wire do_wr = wr_en && !full;
    wire do_rd = rd_en && !empty;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            waddr <= '0;
            raddr <= '0;
            cnt <= '0;
            rd_data <= '0;
        end else begin
            if (do_wr)
                mem[waddr] <= wr_data;
            if (do_rd)
                rd_data <= mem[raddr];
            if (do_wr && !do_rd)
                cnt <= cnt + 1'b1;
            else if (!do_wr && do_rd)
                cnt <= cnt - 1'b1;
            if (do_wr)
                waddr <= waddr + 1'b1;
            if (do_rd)
                raddr <= raddr + 1'b1;
        end
    end

endmodule
