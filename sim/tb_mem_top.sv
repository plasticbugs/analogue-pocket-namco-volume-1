// Bench wrapper for target/pocket/ncv1_mem.sv with the behavioural SDRAM chip
// behind it (sim/tb_mem.cpp loads the image through the download port and
// reads it back through every core port).
`default_nettype none
module tb_mem_top (
    input  logic        clk,
    input  logic        init,
    output logic        ready,
    input  logic        dl_we, input logic [24:0] dl_addr, input logic [7:0] dl_data, output logic dl_busy,
    input  logic [19:1] prog_addr, input logic prog_req, output logic prog_ack, output logic [15:0] prog_q,
    input  logic [18:1] sub_addr,  input logic sub_req,  output logic sub_ack,  output logic [15:0] sub_q,
    input  logic [20:0] pat_addr,  input logic pat_req,  output logic pat_ack,  output logic [31:0] pat_q,
    input  logic  [6:0] pat_len,   output logic pat_wr,  output logic  [5:0] pat_idx,
    input  logic [23:0] pcm_addr,  input logic pcm_req,  output logic pcm_ack,  output logic  [7:0] pcm_q
);
    wire  [15:0] dram_dq; wire [12:0] dram_a; wire [1:0] dram_ba, dram_dqm;
    wire         dram_clk, dram_cke, dram_ras_n, dram_cas_n, dram_we_n;
    ncv1_mem dut (
        .clk(clk), .clk_sdram(clk), .init(init), .ready(ready), .rd_late(1'b1), .burst_slow(1'b0),
        .dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data), .dl_busy(dl_busy),
        .prog_addr(prog_addr), .prog_req(prog_req), .prog_ack(prog_ack), .prog_q(prog_q),
        .sub_addr(sub_addr), .sub_req(sub_req), .sub_ack(sub_ack), .sub_q(sub_q),
        .pat_addr(pat_addr), .pat_req(pat_req), .pat_ack(pat_ack), .pat_q(pat_q),
        .pat_len(pat_len), .pat_wr(pat_wr), .pat_idx(pat_idx),
        .pcm_addr(pcm_addr), .pcm_req(pcm_req), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
        .dram_dq(dram_dq), .dram_a(dram_a), .dram_ba(dram_ba), .dram_dqm(dram_dqm),
        .dram_clk(dram_clk), .dram_cke(dram_cke), .dram_ras_n(dram_ras_n), .dram_cas_n(dram_cas_n), .dram_we_n(dram_we_n)
    );
    sdram_model #(.AW(22)) chip (
        .clk(clk), .dq(dram_dq), .a(dram_a), .ba(dram_ba), .dqml(dram_dqm[0]), .dqmh(dram_dqm[1]),
        .cs_n(1'b0), .ras_n(dram_ras_n), .cas_n(dram_cas_n), .we_n(dram_we_n), .cke(dram_cke)
    );
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused = dram_clk;
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
