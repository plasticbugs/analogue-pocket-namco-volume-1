// Thin wrapper for the YGV608 frozen-state bench: exposes the raster
// position and the renderer's line-time statistics alongside the chip's own
// ports so the C++ driver needs no access to internal signals.
`default_nettype none

module tb_video_top (
    input  logic        clk,
    input  logic        reset,
    input  logic        cen_pix,
    input  logic  [2:0] port_sel,
    input  logic        port_wr,
    input  logic        port_rd,
    input  logic  [7:0] port_wdata,
    output logic  [7:0] port_q,
    input  logic  [1:0] gfxbank,
    output logic        pat_req,
    output logic [20:0] pat_addr,
    input  logic        pat_ack,
    input  logic [31:0] pat_q,
    output logic        hsync, vsync, hblank, vblank, de,
    output logic  [7:0] r, g, b,
    output logic        irq_vblank,
    output logic        irq_raster,
    output logic        unsupported,
    output logic  [3:0] unsup_src,
    output logic  [8:0] dot,
    output logic  [8:0] line,
    output logic [15:0] max_clocks,
    output logic [15:0] line_clocks,
    output logic        overrun
);
    ygv608 u_vdp (.*);
    assign dot         = u_vdp.dot;
    assign line        = u_vdp.line;
    assign max_clocks  = u_vdp.rend_max_clocks;
    assign line_clocks = u_vdp.rend_line_clocks;
    assign overrun     = u_vdp.rend_overrun;
endmodule
