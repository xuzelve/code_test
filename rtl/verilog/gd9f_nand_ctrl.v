// GD9Fx1GxF2A NAND x8 controller — §5.3 ports. FIFOs sync to i_clk_in (tie fifo clocks to i_clk_in).
// i_wr_len / i_rd_len: 16-bit word count.

`timescale 1ns / 1ps

module gd9f_nand_ctrl #(
    parameter int unsigned TWC_DIV = 4,
    parameter int unsigned FIFO_AW = 9,
    parameter int unsigned TIMEOUT_TICKS = 24'd500000
)(
    input  wire        i_clk_in,
    input  wire        i_rst,

    input  wire        i_erase_en,
    input  wire [28:0] i_erase_addr,
    output reg         o_erase_fail,
    output reg         o_erase_done,

    input  wire        i_wr_en,
    input  wire [28:0] i_wr_addr,
    input  wire [10:0] i_wr_len,
    input  wire        i_clk_wr_fifo,
    input  wire [15:0] i_wr_data,
    input  wire        i_wr_dv,
    output reg         o_wr_err,
    output reg         o_wr_done,

    input  wire        i_rd_en,
    input  wire [28:0] i_rd_addr,
    input  wire [10:0] i_rd_len,
    output reg         o_rd_err,
    output reg         o_rd_ready,
    input  wire        i_clk_rd_fifo,
    input  wire        i_rd_fifo_en,
    output wire [15:0] o_rd_data,

    input  wire        i_rb_n,
    output wire        o_wp_n,
    output reg         o_ce_n,
    output reg         o_cle,
    output reg         o_ale,
    output reg         o_we_n,
    output reg         o_re_n,
    output reg         o_nand_busy,
    inout  wire [7:0]  io_nand_data
);

    localparam [1:0] OP_ER = 2'd0, OP_WR = 2'd1, OP_RD = 2'd2;

    reg nand_oe;
    reg [7:0] nand_dout;
    assign io_nand_data = nand_oe ? nand_dout : 8'hZZ;
    assign o_wp_n = 1'b1;

    reg [$clog2(TWC_DIV)-1:0] div_cnt;
    reg tick;
    always @(posedge i_clk_in or posedge i_rst) begin
        if (i_rst) begin
            div_cnt <= '0;
            tick <= 1'b0;
        end else begin
            tick <= 1'b0;
            if (div_cnt == TWC_DIV - 1) begin
                div_cnt <= '0;
                tick <= 1'b1;
            end else
                div_cnt <= div_cnt + 1'b1;
        end
    end

    wire wf_full;
    wire wf_empty;
    wire [15:0] wf_rd_data;
    reg wf_rd_en;
    sync_fifo_16 #(.AW(FIFO_AW)) u_wfifo (
        .clk(i_clk_in), .rst(i_rst),
        .wr_data(i_wr_data), .wr_en(i_wr_dv), .full(wf_full),
        .rd_data(wf_rd_data), .rd_en(wf_rd_en), .empty(wf_empty)
    );

    wire rf_full;
    wire rf_empty;
    reg rf_wr_en;
    reg [15:0] rf_wr_data;
    sync_fifo_16 #(.AW(FIFO_AW)) u_rfifo (
        .clk(i_clk_in), .rst(i_rst),
        .wr_data(rf_wr_data), .wr_en(rf_wr_en), .full(rf_full),
        .rd_data(o_rd_data), .rd_en(i_rd_fifo_en), .empty(rf_empty)
    );
    assign o_rd_ready = !rf_empty;

    reg i_erase_en_d, i_erase_en_dd;
    reg i_wr_en_d, i_wr_en_dd;
    reg i_rd_en_d, i_rd_en_dd;
    always @(posedge i_clk_in or posedge i_rst) begin
        if (i_rst) begin
            i_erase_en_d <= 0; i_erase_en_dd <= 0;
            i_wr_en_d <= 0; i_wr_en_dd <= 0;
            i_rd_en_d <= 0; i_rd_en_dd <= 0;
        end else begin
            i_erase_en_d <= i_erase_en; i_erase_en_dd <= i_erase_en_d;
            i_wr_en_d <= i_wr_en; i_wr_en_dd <= i_wr_en_d;
            i_rd_en_d <= i_rd_en; i_rd_en_dd <= i_rd_en_d;
        end
    end
    wire pe = i_erase_en_d & ~i_erase_en_dd;
    wire pw = i_wr_en_d & ~i_wr_en_dd;
    wire pr = i_rd_en_d & ~i_rd_en_dd;

    reg busy;
    reg [1:0] op;
    reg [28:0] addr_r;
    reg [10:0] len_r;
    reg [10:0] wcnt;
    reg op_fail;
    reg [15:0] cur_w;
    reg wr_hi;

    wire [7:0] col1 = addr_r[7:0];
    wire [7:0] col2 = {4'd0, addr_r[11:8]};
    wire [7:0] row1 = addr_r[20:13];
    wire [7:0] row2 = addr_r[28:21];

    localparam int unsigned
        S_IDLE = 0,
        S_WE0 = 1, S_WE1 = 2, S_WE2 = 3, S_WE3 = 4,
        S_RB = 5,
        S_ST0 = 6, S_ST1 = 7, S_ST2 = 8,
        S_RDL0 = 9, S_RDL1 = 10,
        S_RDP = 11,
        S_WPOP = 12,
        S_WPOP_WAIT = 13,
        S_DONE = 14;

    reg [4:0] st;
    reg [3:0] seq;
    reg [7:0] wbyte;
    reg wcle, wale;
    reg [23:0] to_ctr;

    always @(posedge i_clk_in or posedge i_rst) begin
        if (i_rst) begin
            busy <= 0;
            o_nand_busy <= 0;
            op <= OP_ER;
            addr_r <= 0;
            len_r <= 0;
            wcnt <= 0;
            op_fail <= 0;
            o_erase_fail <= 0;
            o_erase_done <= 0;
            o_wr_err <= 0;
            o_wr_done <= 0;
            o_rd_err <= 0;
            o_ce_n <= 1'b1;
            o_cle <= 0;
            o_ale <= 0;
            o_we_n <= 1'b1;
            o_re_n <= 1'b1;
            nand_oe <= 0;
            nand_dout <= 0;
            st <= S_IDLE;
            seq <= 0;
            wbyte <= 0;
            wcle <= 0;
            wale <= 0;
            to_ctr <= 0;
            wf_rd_en <= 0;
            rf_wr_en <= 0;
            rf_wr_data <= 0;
            cur_w <= 0;
            wr_hi <= 0;
        end else begin
            o_erase_done <= 0;
            o_wr_done <= 0;
            wf_rd_en <= 0;
            rf_wr_en <= 0;

            case (st)
                S_IDLE: begin
                    o_ce_n <= 1'b1;
                    if (!busy && ((pe?1:0)+(pw?1:0)+(pr?1:0) == 1)) begin
                        busy <= 1;
                        o_nand_busy <= 1;
                        o_ce_n <= 0;
                        op_fail <= 0;
                        seq <= 0;
                        if (pe) begin op <= OP_ER; addr_r <= i_erase_addr; end
                        else if (pw) begin op <= OP_WR; addr_r <= i_wr_addr; len_r <= i_wr_len; wcnt <= 0; wr_hi <= 0; end
                        else begin op <= OP_RD; addr_r <= i_rd_addr; len_r <= i_rd_len; wcnt <= 0; wr_hi <= 0; end
                        st <= S_WE0;
                    end
                end
                S_WE0: begin
                    if (op == OP_ER) begin
                        case (seq)
                            0: begin wbyte <= 8'h60; wcle <= 1; wale <= 0; end
                            1: begin wbyte <= col1; wcle <= 0; wale <= 1; end
                            2: begin wbyte <= col2; wcle <= 0; wale <= 1; end
                            3: begin wbyte <= row1; wcle <= 0; wale <= 1; end
                            4: begin wbyte <= row2; wcle <= 0; wale <= 1; end
                            5: begin wbyte <= 8'hd0; wcle <= 1; wale <= 0; end
                            default: begin st <= S_RB; to_ctr <= 0; end
                        endcase
                    end else if (op == OP_WR) begin
                        if (seq <= 4) begin
                            case (seq)
                                0: begin wbyte <= 8'h80; wcle <= 1; wale <= 0; end
                                1: begin wbyte <= col1; wcle <= 0; wale <= 1; end
                                2: begin wbyte <= col2; wcle <= 0; wale <= 1; end
                                3: begin wbyte <= row1; wcle <= 0; wale <= 1; end
                                4: begin wbyte <= row2; wcle <= 0; wale <= 1; end
                            endcase
                        end else if (seq == 5) begin
                            wbyte <= wr_hi ? cur_w[15:8] : cur_w[7:0];
                            wcle <= 0;
                            wale <= 0;
                        end else if (seq == 6) begin
                            wbyte <= 8'h10;
                            wcle <= 1;
                            wale <= 0;
                        end else begin
                            st <= S_RB;
                            to_ctr <= 0;
                        end
                    end else begin
                        case (seq)
                            0: begin wbyte <= 8'h00; wcle <= 1; wale <= 0; end
                            1: begin wbyte <= col1; wcle <= 0; wale <= 1; end
                            2: begin wbyte <= col2; wcle <= 0; wale <= 1; end
                            3: begin wbyte <= row1; wcle <= 0; wale <= 1; end
                            4: begin wbyte <= row2; wcle <= 0; wale <= 1; end
                            5: begin wbyte <= 8'h30; wcle <= 1; wale <= 0; end
                            default: begin st <= S_RB; to_ctr <= 0; end
                        endcase
                    end
                    if (!((op==OP_ER && seq>5) || (op==OP_RD && seq>5) || (op==OP_WR && seq>6))) begin
                        nand_oe <= 1;
                        nand_dout <= wbyte;
                        o_cle <= wcle;
                        o_ale <= wale;
                        if (tick) st <= S_WE1;
                    end else begin
                        st <= S_RB;
                        to_ctr <= 0;
                    end
                end
                S_WE1: begin
                    if (tick) begin o_we_n <= 0; st <= S_WE2; end
                end
                S_WE2: begin
                    if (tick) begin o_we_n <= 1; st <= S_WE3; end
                end
                S_WE3: begin
                    o_cle <= 0;
                    o_ale <= 0;
                    nand_oe <= 0;
                    if (tick) begin
                        if (op == OP_ER) begin
                            if (seq < 5) begin seq <= seq + 1; st <= S_WE0; end
                            else begin st <= S_RB; to_ctr <= 0; end
                        end else if (op == OP_WR) begin
                            if (seq < 4) begin seq <= seq + 1; st <= S_WE0; end
                            else if (seq == 4) begin seq <= 5; st <= S_WPOP; end
                            else if (seq == 5) begin
                                if (!wr_hi) begin wr_hi <= 1; st <= S_WE0; end
                                else begin
                                    wr_hi <= 0;
                                    wcnt <= wcnt + 1;
                                    if (wcnt + 1 < len_r) st <= S_WPOP;
                                    else begin seq <= 6; st <= S_WE0; end
                                end
                            end else begin
                                st <= S_RB;
                                to_ctr <= 0;
                            end
                        end else begin
                            if (seq < 5) begin seq <= seq + 1; st <= S_WE0; end
                            else begin st <= S_RB; to_ctr <= 0; end
                        end
                    end
                end
                S_RB: begin
                    if (i_rb_n == 1'b1) begin
                        if (op == OP_RD) st <= S_RDL0;
                        else st <= S_ST0;
                    end else if (tick) begin
                        to_ctr <= to_ctr + 1'b1;
                        if (to_ctr >= TIMEOUT_TICKS) begin op_fail <= 1; st <= S_DONE; end
                    end
                end
                S_ST0: begin
                    nand_oe <= 1;
                    nand_dout <= 8'h70;
                    o_cle <= 1;
                    o_ale <= 0;
                    if (tick) st <= S_ST1;
                end
                S_ST1: begin
                    nand_oe <= 0;
                    if (tick) begin o_re_n <= 0; st <= S_ST2; end
                end
                S_ST2: begin
                    if (tick) begin
                        o_re_n <= 1;
                        if (io_nand_data[0]) op_fail <= 1;
                        st <= S_DONE;
                    end
                end
                S_RDL0: begin
                    nand_oe <= 0;
                    if (tick) begin o_re_n <= 0; st <= S_RDL1; end
                end
                S_RDL1: begin
                    if (tick) begin
                        o_re_n <= 1;
                        if (!wr_hi) begin cur_w[7:0] <= io_nand_data; wr_hi <= 1; st <= S_RDL0; end
                        else begin cur_w[15:8] <= io_nand_data; wr_hi <= 0; st <= S_RDP; end
                    end
                end
                S_RDP: begin
                    if (!rf_full) begin
                        rf_wr_en <= 1;
                        rf_wr_data <= cur_w;
                        if (wcnt + 1 >= len_r) st <= S_DONE;
                        else begin wcnt <= wcnt + 1; st <= S_RDL0; end
                    end
                end
                S_WPOP: begin
                    if (!wf_empty) begin
                        wf_rd_en <= 1;
                        st <= S_WPOP_WAIT;
                    end
                end
                S_WPOP_WAIT: begin
                    cur_w <= wf_rd_data;
                    seq <= 5;
                    st <= S_WE0;
                end
                S_DONE: begin
                    busy <= 0;
                    o_nand_busy <= 0;
                    o_ce_n <= 1'b1;
                    if (op == OP_ER) begin o_erase_fail <= op_fail; o_erase_done <= 1; end
                    else if (op == OP_WR) begin o_wr_err <= op_fail; o_wr_done <= 1; end
                    else o_rd_err <= op_fail;
                    st <= S_IDLE;
                    seq <= 0;
                end
                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
