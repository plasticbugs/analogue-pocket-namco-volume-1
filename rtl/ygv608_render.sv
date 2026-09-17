//------------------------------------------------------------------------------
// YGV608 line renderer: composes one 288-pixel line of palette indices into a
// double line buffer exactly as MAME's ygv608_device::screen_update does
// (docs/ygv608.md sections 2-7): plane B, then plane A and the sprites in
// PRM order, with MAME's transparency rules. One pixel is written per clock;
// pattern rows come through the 32-bit pattern port (one fetch per 8 pixels
// of 4bpp or 4 pixels of 8bpp).
//
// Tables are read through registered ports owned by ygv608.sv: the data for
// an address set at edge t is usable at edge t+2. `start` (one clock, with
// line_y) begins a line into bank line_y[0]; `busy` holds until it is done.
// A start while busy sets the sticky `overrun` flag. `line_clocks` is the
// length of the last line and `max_clocks` the longest seen.
//------------------------------------------------------------------------------
`default_nettype none

module ygv608_render (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic  [7:0] line_y,
    output logic        busy,
    output logic        overrun,
    output logic [15:0] line_clocks,
    output logic [15:0] max_clocks,

    // mode (decoded registers, static during a line)
    input  logic  [1:0] md,             // R#7 MD
    input  logic        page_size,      // R#8 PGS
    input  logic        pts16,          // R#9 PTS == 16x16
    input  logic  [2:0] slh, slv,       // R#9
    input  logic  [3:0] col_shift,
    input  logic        flip,           // R#7 FLIP
    input  logic        dspe,           // R#7 DSPE
    input  logic        spas,           // R#10
    input  logic  [1:0] spa,
    input  logic        sprd,
    input  logic  [1:0] prm,            // R#11
    input  logic        ctpb, ctpa,
    input  logic  [2:0] apf, bpf,       // R#12
    input  logic  [1:0] spf,
    input  logic  [7:0] border,         // R#13
    input  logic  [7:0] sprite_bank,    // R#6
    input  logic  [1:0] gfxbank,
    input  logic [47:0] base_addr,      // bit plane*24 + entry*3, 3 bits each

    // table read ports
    output logic [10:0] pnt_addr,       // word address of the 4 KB name table
    input  logic [15:0] pnt_q,          // [15:8] = even byte, [7:0] = odd byte
    output logic  [8:0] sdt_addr,       // scroll tables, plane B at +256
    input  logic  [7:0] sdt_q,
    output logic  [5:0] sat_addr,       // sprite entry
    input  logic [31:0] sat_q,          // [7:0] sy, [15:8] sx, [23:16] attr, [31:24] name

    // pattern ROM port
    output logic        pat_req,
    output logic [20:0] pat_addr,
    input  logic        pat_ack,
    input  logic [31:0] pat_q,

    // line buffer read port (registered): [9] bank, [8:0] x
    input  logic  [9:0] lb_raddr,
    output logic  [7:0] lb_q
);
    // ------------------------------------------------------------ line buffer
    (* ramstyle = "no_rw_check" *) logic [7:0] lbuf [1024];
    logic        lb_we;
    logic  [9:0] lb_waddr;
    logic  [7:0] lb_wdata;
    always_ff @(posedge clk) begin
        if (lb_we) lbuf[lb_waddr] <= lb_wdata;
        lb_q <= lbuf[lb_raddr];
    end

    // ------------------------------------------------------------ derived mode
    wire        two_planes   = ~md[1];
    wire        bits16       = (md != 2'd0);
    wire        plane_a_8bpp = (md == 2'd3);
    wire  [6:0] page_x = (md == 2'd1) ? 7'd32 : (page_size ? 7'd32 : 7'd64);
    wire  [6:0] page_y = (md == 2'd1) ? 7'd32 : (page_size ? 7'd64 : 7'd32);
    wire  [2:0] pny_shift = (page_x == 7'd32) ? 3'd5 : 3'd6;
    wire        base_y_shift3 = (page_y != 7'd32);          // base_y_shift: 2 or 3
    wire  [3:0] na8_mask = flip ? 4'h3 : 4'hf;
    wire  [3:0] log2ts = pts16 ? 4'd4 : 4'd3;
    wire        row_scroll_mode = (slh != 3'd0);
    // tilemap size in pixels (power of two) minus one: tw = page_x * ts, th = page_y * ts
    wire  [9:0] tw_m1 = ({3'b000, page_x} << log2ts) - 10'd1;
    wire  [9:0] th_m1 = ({3'b000, page_y} << log2ts) - 10'd1;
    wire  [4:0] ts_m1 = pts16 ? 5'd15 : 5'd7;
    wire  [6:0] page_x_m1 = page_x - 7'd1;
    wire  [6:0] page_y_m1 = page_y - 7'd1;

    // ------------------------------------------------------------ state
    typedef enum logic [5:0] {
        S_IDLE, S_PHASE, S_FILL,
        S_PL_INIT, S_PL_RS0, S_PL_RS1, S_PL_CS0, S_PL_CS1, S_PL_SETUP, S_PL_ROWRS0, S_PL_ROWRS1, S_PL_ROWRS2,
        S_T_COL, S_T_CS0, S_T_CS1, S_T_PNT, S_T_PNT1, S_T_PAGE0, S_T_PAGE1, S_T_CODE, S_T_FETCH, S_T_WAIT, S_T_WRITE, S_T_NEXT,
        S_SP_INIT, S_SP_READ, S_SP_READ1, S_SP_DECODE, S_SP_FETCH, S_SP_WAIT, S_SP_WRITE, S_SP_NEXT,
        S_DONE
    } st_t;
    st_t         st;
    logic  [2:0] phase;          // 0 fill, 1 plane B, 2 sprites under A, 3 plane A, 4 sprites on top, 5 done
    logic        bank;
    logic  [7:0] y;
    logic        plane;          // 0 = A, 1 = B
    logic [15:0] rs16, cs16;     // whole-screen row/column scroll of the plane (16-bit)
    logic [11:0] psx, psy;       // page-select scroll (12-bit)
    logic  [9:0] xr;             // rowscroll used for the line (masked to the tilemap width)
    logic  [6:0] col;
    logic  [5:0] k, ntiles;
    logic  [6:0] row;
    logic  [4:0] py;
    logic  [7:0] cs_lo;
    logic [15:0] pnt_word;
    logic [19:0] code;
    logic  [3:0] colour;
    logic        tflipx, tflipy;
    logic  [2:0] nfetch, fidx;
    logic [127:0] rowbuf;        // pattern words of the current row, first fetch highest
    logic  [4:0] xx;
    logic  [9:0] xpos;           // screen x of the first pixel (two's complement)
    logic  [6:0] npix_m1;
    logic        cur_8bpp;
    logic  [7:0] cur_fill;
    logic  [8:0] fill_x;
    // sprites
    logic  [5:0] si;
    logic [31:0] sat_word;
    logic  [1:0] ssize;
    logic  [5:0] syy;            // row within the sprite (already flipped)
    logic [15:0] clk_count;
    wire _unused_ok = &{1'b0, prm[1], page_y_m1[0], rs16[15:12], cs16[15:8]};

    // ------------------------------------------------------------ helpers
    // 8x8 block index inside a larger 4bpp tile (Morton, x bits in even positions)
    function automatic logic [5:0] morton(input logic [2:0] bx, input logic [2:0] by);
        morton = {by[2], bx[2], by[1], bx[1], by[0], bx[0]};
    endfunction

    // name table index: i = pn_base + ((row << pny_shift) + col) << bits16
    function automatic logic [12:0] pnt_index(input logic [6:0] rw, input logic [6:0] c, input logic pl);
        logic [12:0] i;
        i = ({6'd0, rw} << pny_shift) + {6'd0, c};
        if (pl) i = i + ({6'd0, page_y} << pny_shift);
        if (bits16) i = {i[11:0], 1'b0};
        pnt_index = i;
    endfunction

    // base_addr entry for the row
    wire  [2:0] be_idx = base_y_shift3 ? row[5:3] : row[4:2];
    logic [5:0] ba_off;
    always_comb ba_off = (plane ? 6'd24 : 6'd0) + {3'b000, be_idx} + {2'b00, be_idx, 1'b0};
    wire  [2:0] ba_val = base_addr[ba_off +: 3];

    // The block-local temporaries from here on are deliberately wider than the
    // slices used (MAME's integer maths truncated to the register widths).
    /* verilator lint_off UNUSEDSIGNAL */
    // get_col_division(col): ((col >> col_shift) * 2) & 0x7f
    logic [6:0] col_div;
    always_comb begin
        logic [6:0] t;
        t = col >> col_shift;
        col_div = slv[2] ? {t[5:0], 1'b0} : 7'd0;
    end

    // page select (only used when slv == 0)
    logic [4:0] page_calc;
    always_comb begin
        logic [12:0] px, pyv;
        logic  [5:0] p;
        px  = {1'b0, psx} + ({6'd0, col} << log2ts);
        pyv = {1'b0, psy} + ({6'd0, row} << log2ts);
        if (!pts16) begin
            if (md == 2'd1)     p = {4'd0, px[9:8]}   + {1'b0, pyv[10:8], 2'b00};
            else if (page_size) p = {4'd0, px[10:9]}  + {1'b0, pyv[10:8], 2'b00};
            else                p = {3'd0, px[10:8]}  + {1'b0, pyv[10:9], 3'b000};
        end else begin
            if (md == 2'd1)     p = {4'd0, px[10:9]}  + {pyv[12:9], 2'b00};
            else if (page_size) p = {2'd0, px[12:9]}  + {pyv[12:10], 3'b000};
            else                p = {3'd0, px[12:10]} + {pyv[12:9], 2'b00};
        end
        page_calc = p[4:0];
    end

    // ------------------------------------------------------------ main FSM
    always_ff @(posedge clk) begin
        lb_we <= 1'b0;
        if (reset) begin
            st <= S_IDLE; busy <= 1'b0; overrun <= 1'b0; pat_req <= 1'b0; pat_addr <= 21'd0;
            line_clocks <= 16'd0; max_clocks <= 16'd0; clk_count <= 16'd0;
            pnt_addr <= 11'd0; sdt_addr <= 9'd0; sat_addr <= 6'd0;
            lb_waddr <= 10'd0; lb_wdata <= 8'd0; phase <= 3'd0;
        end else begin
            if (busy) clk_count <= clk_count + 16'd1;
            if (start) begin
                if (busy) overrun <= 1'b1;
                else begin
                    busy <= 1'b1; y <= line_y; bank <= line_y[0]; clk_count <= 16'd0;
                    phase <= 3'd0; st <= S_PHASE;
                end
            end
            case (st)
            S_IDLE: ;
            // ---------------- phase dispatcher
            S_PHASE: begin
                phase <= phase + 3'd1;
                case (phase)
                3'd0: begin
                    // border fill unless plane B will overwrite every pixel
                    if (two_planes && dspe && !ctpb) st <= S_PHASE;
                    else begin st <= S_FILL; cur_fill <= border; fill_x <= 9'd0; end
                end
                3'd1: begin
                    if (two_planes && dspe) begin st <= S_PL_INIT; plane <= 1'b1; end
                    else st <= S_PHASE;
                end
                3'd2: st <= prm[0] ? S_SP_INIT : S_PHASE;
                3'd3: begin
                    if (dspe) begin st <= S_PL_INIT; plane <= 1'b0; end
                    else if (!ctpa) begin st <= S_FILL; cur_fill <= 8'd0; fill_x <= 9'd0; end   // zeroed work bitmap copied opaque
                    else st <= S_PHASE;
                end
                3'd4: st <= prm[0] ? S_PHASE : S_SP_INIT;
                default: st <= S_DONE;
                endcase
            end
            // ---------------- fill the line with cur_fill
            S_FILL: begin
                lb_we <= 1'b1; lb_waddr <= {bank, fill_x}; lb_wdata <= cur_fill;
                if (fill_x == 9'd287) st <= S_PHASE; else fill_x <= fill_x + 9'd1;
            end
            // ---------------- plane setup: whole-screen scrolls (0x80/0x81 then 0x00/0x01)
            S_PL_INIT: begin sdt_addr <= {plane, 8'h80}; st <= S_PL_RS0; end
            S_PL_RS0:  begin sdt_addr <= {plane, 8'h81}; st <= S_PL_RS1; end
            S_PL_RS1:  begin rs16[7:0] <= sdt_q; sdt_addr <= {plane, 8'h00}; st <= S_PL_CS0; end
            S_PL_CS0:  begin rs16[15:8] <= sdt_q; sdt_addr <= {plane, 8'h01}; st <= S_PL_CS1; end
            S_PL_CS1:  begin cs16[7:0] <= sdt_q; st <= S_PL_SETUP; end
            S_PL_SETUP: begin
                logic [15:0] cs_now;
                logic  [9:0] ty_now;
                logic  [6:0] row_now;
                logic  [6:0] rd;
                logic  [9:0] rsh;
                cs_now = {sdt_q, cs16[7:0]};
                cs16 <= cs_now;
                psx <= rs16[11:0];
                psy <= cs_now[11:0];
                k <= 6'd0;
                ntiles <= pts16 ? 6'd19 : 6'd37;
                if (row_scroll_mode) begin
                    // ty = (y + colscroll[0]) mod th; the row's own x scroll
                    ty_now  = ({2'b00, y} + cs_now[9:0]) & th_m1;
                    rsh     = ty_now >> log2ts;
                    row_now = rsh[6:0];
                    row <= row_now;
                    py  <= ty_now[4:0] & ts_m1;
                    rd  = {(row_now[5:0] & page_y_m1[6:1]), 1'b0};
                    sdt_addr <= {plane, 1'b1, rd};
                    st <= S_PL_ROWRS0;
                end else begin
                    xr <= rs16[9:0] & tw_m1;
                    st <= S_T_COL;
                end
            end
            S_PL_ROWRS0: begin sdt_addr <= sdt_addr + 9'd1; st <= S_PL_ROWRS1; end
            S_PL_ROWRS1: begin xr[7:0] <= sdt_q; st <= S_PL_ROWRS2; end
            S_PL_ROWRS2: begin xr <= {sdt_q[1:0], xr[7:0]} & tw_m1; st <= S_T_COL; end
            // ---------------- per tile
            S_T_COL: begin
                logic [6:0] col0; logic [9:0] csh0;
                csh0 = xr >> log2ts;
                col0 = csh0[6:0];
                col  <= (col0 + {1'b0, k}) & page_x_m1;
                xpos <= ({4'd0, k} << log2ts) - {5'd0, xr[4:0] & ts_m1};
                st <= row_scroll_mode ? S_T_PNT : S_T_CS0;
            end
            S_T_CS0: begin sdt_addr <= {plane, 1'b0, col_div}; st <= S_T_CS1; end
            S_T_CS1: begin sdt_addr <= sdt_addr + 9'd1; st <= S_T_PNT; end
            S_T_PNT: begin
                if (!row_scroll_mode) begin
                    cs_lo <= sdt_q;
                    st <= S_T_PNT1;
                end else begin
                    logic [12:0] pnt_idx_v;
                    pnt_idx_v = pnt_index(row, col, plane);
                    pnt_addr <= pnt_idx_v[11:1];
                    st <= S_T_PAGE0;
                end
            end
            S_T_PNT1: begin
                logic [15:0] csn; logic [9:0] tyn, tsh; logic [6:0] rown; logic [12:0] pnt_idx_v;
                csn  = {sdt_q, cs_lo};
                tyn  = ({2'b00, y} + csn[9:0]) & th_m1;
                tsh  = tyn >> log2ts;
                rown = tsh[6:0];
                row <= rown;
                py  <= tyn[4:0] & ts_m1;
                pnt_idx_v = pnt_index(rown, col, plane);
                pnt_addr <= pnt_idx_v[11:1];
                st <= S_T_PAGE0;
            end
            S_T_PAGE0: begin
                sdt_addr <= {plane, 2'b11, 1'b0, (slv == 3'd0) ? page_calc : 5'd0};
                st <= S_T_PAGE1;
            end
            S_T_PAGE1: begin
                pnt_word <= pnt_q;
                st <= S_T_CODE;
            end
            S_T_CODE: begin
                logic [19:0] j, jb, jsh; logic [7:0] name_lo, pg; logic [3:0] name_hi, attr, col_out, cf;
                logic [19:0] elems; logic is8; logic [12:0] idx;
                is8 = (plane == 1'b0) && plane_a_8bpp;
                pg  = sdt_q;
                idx = pnt_index(row, col, plane);
                if (bits16) begin
                    name_lo = pnt_word[15:8]; name_hi = pnt_word[3:0] & na8_mask; attr = pnt_word[7:4];
                end else begin
                    name_lo = idx[0] ? pnt_word[7:0] : pnt_word[15:8]; name_hi = 4'd0; attr = 4'd0;
                end
                if (is8) attr = 4'd0;
                j = {8'd0, name_hi, name_lo} + (pts16 ? {4'd0, pg, 8'd0} : {2'd0, pg, 10'd0}) + {9'd0, ba_val, 8'd0};
                elems = is8 ? (pts16 ? 20'h08000 : 20'h20000) : (pts16 ? 20'h10000 : 20'h40000);
                if (j >= elems) j = 20'd0;
                cf = plane ? {1'b0, bpf} : {1'b0, apf};
                col_out = attr;
                if (cf != 4'd0 && !is8) begin
                    jsh = pts16 ? (j >> {cf[2:0], 1'b0}) : (j >> {cf[2:0] - 3'd1, 1'b0});
                    col_out = jsh[3:0];
                end
                if (is8) jb = j + (pts16 ? {5'd0, gfxbank, 13'd0} : {3'd0, gfxbank, 15'd0});
                else     jb = j + (pts16 ? {4'd0, gfxbank, 14'd0} : {2'd0, gfxbank, 16'd0});
                code <= jb;
                colour <= col_out;
                tflipx <= flip & bits16 & pnt_word[3];
                tflipy <= flip & bits16 & pnt_word[2];
                cur_8bpp <= is8;
                nfetch <= is8 ? (pts16 ? 3'd4 : 3'd2) : (pts16 ? 3'd2 : 3'd1);
                fidx <= 3'd0;
                // cells outside the page are MAME's blank tileinfo (code 0, colour 0, no flip)
                if (col >= page_x || row >= page_y) begin
                    code <= 20'd0; colour <= 4'd0; tflipx <= 1'b0; tflipy <= 1'b0;
                end
                st <= S_T_FETCH;
            end
            S_T_FETCH: begin
                logic [4:0] pyf; logic [26:0] wa; logic [5:0] blk;
                pyf = tflipy ? (ts_m1 - py) : py;
                blk = morton({2'b00, fidx[0]}, {2'b00, pyf[3]});
                if (!cur_8bpp) begin
                    if (!pts16) wa = ({7'd0, code} << 3) + {22'd0, pyf};                                  // code*8 + py
                    else        wa = ({7'd0, code} << 5) + {18'd0, blk, 3'b000} + {24'd0, pyf[2:0]};      // code*32 + blk*8 + py
                end else begin
                    if (!pts16) wa = ({7'd0, code} << 4) + {23'd0, pyf[2:0], 1'b0} + {26'd0, fidx[0]};   // code*16 + py*2 + h
                    else        wa = ({7'd0, code} << 6) + {21'd0, pyf[3], fidx[1], 4'd0} + {23'd0, pyf[2:0], 1'b0} + {26'd0, fidx[0]};
                end
                pat_addr <= wa[20:0];
                pat_req <= 1'b1;
                st <= S_T_WAIT;
            end
            S_T_WAIT: begin
                if (pat_ack) begin
                    pat_req <= 1'b0;
                    rowbuf <= {rowbuf[95:0], pat_q};
                    if (fidx + 3'd1 == nfetch) begin
                        st <= S_T_WRITE; xx <= 5'd0;
                        npix_m1 <= pts16 ? 7'd15 : 7'd7;
                    end else begin
                        fidx <= fidx + 3'd1;
                        st <= S_T_FETCH;
                    end
                end
            end
            S_T_WRITE: begin
                logic [9:0] dx; logic [7:0] pen, idx; logic transp; logic [4:0] pidx;
                logic [127:0] rb; logic [7:0] shl;
                // rowbuf holds nfetch words in its low bits; move the first pixel to bit 127
                shl = 8'd128 - {nfetch, 5'b00000};
                rb  = rowbuf << shl;
                pidx = tflipx ? (npix_m1[4:0] - xx) : xx;
                if (cur_8bpp) pen = rb[127 - {pidx, 3'b000} -: 8];
                else          pen = {4'd0, rb[127 - {1'b0, pidx, 2'b00} -: 4]};
                dx  = xpos + {5'd0, xx};
                idx = cur_8bpp ? pen : {colour, pen[3:0]};
                if (plane) begin
                    // plane B is drawn opaque; CTPB copies it with palette index 0 transparent
                    transp = ctpb && (idx == 8'd0);
                end else begin
                    // plane A: a raw pen equal to the border register stays 0 in the work
                    // bitmap; CTPA copies index 0 transparent, else the copy is opaque
                    if (pen == border) idx = 8'd0;
                    transp = ctpa && (idx == 8'd0);
                end
                if (!dx[9] && dx < 10'd288 && !transp) begin
                    lb_we <= 1'b1; lb_waddr <= {bank, dx[8:0]}; lb_wdata <= idx;
                end
                if (xx == npix_m1[4:0]) st <= S_T_NEXT; else xx <= xx + 5'd1;
            end
            S_T_NEXT: begin
                if (k + 6'd1 == ntiles) st <= S_PHASE;
                else begin k <= k + 6'd1; st <= S_T_COL; end
            end
            // ---------------- sprites, entry 63 first
            S_SP_INIT: begin
                if (!dspe || sprd) st <= S_PHASE;
                else begin si <= 6'd63; sat_addr <= 6'd63; st <= S_SP_READ; end
            end
            S_SP_READ:  st <= S_SP_READ1;
            S_SP_READ1: begin sat_word <= sat_q; st <= S_SP_DECODE; end
            S_SP_DECODE: begin
                logic [8:0] sx, sy; logic [1:0] a2, size; logic fx, fy; logic [6:0] n, n_m1; logic [8:0] dy0; logic [9:0] dyw;
                logic [9:0] limit; logic hit; logic [5:0] yy; logic [15:0] c, csh; logic [3:0] scol, shift;
                sx = {sat_word[17], sat_word[15:8]};
                sy = {sat_word[16], sat_word[7:0]} + 9'd1;
                a2 = sat_word[19:18];
                if (!spas) begin size = spa; fx = a2[1]; fy = a2[0]; end
                else begin size = a2; fx = spa[1]; fy = spa[0]; end
                n = 7'd8 << size;
                n_m1 = n - 7'd1;
                limit = 10'd512 - {3'b000, n};
                dy0 = {1'b0, y} - sy;
                dyw = {2'b00, y} + 10'd512 - {1'b0, sy};
                hit = 1'b0; yy = 6'd0;
                if ({1'b0, y} >= sy && dy0 < {2'b00, n}) begin hit = 1'b1; yy = dy0[5:0]; end
                else if ({1'b0, sy} > limit && dyw < {3'b000, n}) begin hit = 1'b1; yy = dyw[5:0]; end
                ssize <= size;
                syy <= fy ? (n_m1[5:0] - yy) : yy;
                tflipx <= fx;
                case (size)
                2'd0: c = {sprite_bank, sat_word[31:24]};
                2'd1: c = {2'b00, sprite_bank[7:2], 8'd0} | {8'd0, sat_word[31:24]};
                2'd2: c = {4'd0, sprite_bank[7:4], 8'd0} | {8'd0, sat_word[31:24]};
                default: c = {6'd0, sprite_bank[7:6], 8'd0} | {8'd0, sat_word[31:24]};
                endcase
                scol = sat_word[23:20];
                if (spf != 2'd0) begin
                    shift = {2'b00, spf} + {2'b00, size} - 4'd1;
                    csh = c >> {shift[2:0], 1'b0};
                    scol = csh[3:0];
                end
                colour <= scol;
                case (size)
                2'd0: code <= {4'd0, c} + {2'd0, gfxbank, 16'd0};
                2'd1: code <= {4'd0, c} + {4'd0, gfxbank, 14'd0};
                2'd2: code <= {4'd0, c} + {6'd0, gfxbank, 12'd0};
                default: code <= {4'd0, c} + {8'd0, gfxbank, 10'd0};
                endcase
                // only the copy at sx-512 can be on screen when sx > limit (the screen is 288 wide)
                xpos <= ({1'b0, sx} > limit) ? ({1'b0, sx} - 10'd512) : {1'b0, sx};
                nfetch <= 3'd1 << size;
                fidx <= 3'd0;
                npix_m1 <= n_m1;
                st <= hit ? S_SP_FETCH : S_SP_NEXT;
            end
            S_SP_FETCH: begin
                logic [26:0] wa; logic [5:0] blk;
                blk = morton(fidx, syy[5:3]);
                case (ssize)
                2'd0:    wa = ({7'd0, code} << 3) + {24'd0, syy[2:0]};
                2'd1:    wa = ({7'd0, code} << 5) + {18'd0, blk, 3'b000} + {24'd0, syy[2:0]};
                2'd2:    wa = ({7'd0, code} << 7) + {18'd0, blk, 3'b000} + {24'd0, syy[2:0]};
                default: wa = ({7'd0, code} << 9) + {18'd0, blk, 3'b000} + {24'd0, syy[2:0]};
                endcase
                pat_addr <= wa[20:0];
                pat_req <= 1'b1;
                st <= S_SP_WAIT;
            end
            S_SP_WAIT: begin
                if (pat_ack) begin
                    pat_req <= 1'b0;
                    rowbuf[127:96] <= pat_q;     // 8 pixels, written right away
                    st <= S_SP_WRITE; xx <= 5'd0;
                end
            end
            S_SP_WRITE: begin
                logic [9:0] dx; logic [3:0] pen; logic [6:0] pix, pixf;
                pix  = {1'b0, fidx, xx[2:0]};
                pixf = tflipx ? (npix_m1 - pix) : pix;
                pen  = rowbuf[127 - {2'b00, xx[2:0], 2'b00} -: 4];
                dx   = xpos + {3'b000, pixf};
                if (!dx[9] && dx < 10'd288 && pen != 4'd0) begin
                    lb_we <= 1'b1; lb_waddr <= {bank, dx[8:0]}; lb_wdata <= {colour, pen};
                end
                if (xx[2:0] == 3'd7) begin
                    if (fidx + 3'd1 == nfetch) st <= S_SP_NEXT;
                    else begin fidx <= fidx + 3'd1; st <= S_SP_FETCH; end
                end else xx <= xx + 5'd1;
            end
            S_SP_NEXT: begin
                if (si == 6'd0) st <= S_PHASE;
                else begin si <= si - 6'd1; sat_addr <= si - 6'd1; st <= S_SP_READ; end
            end
            S_DONE: begin
                busy <= 1'b0; st <= S_IDLE;
                line_clocks <= clk_count;
                if (clk_count > max_clocks) max_clocks <= clk_count;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
