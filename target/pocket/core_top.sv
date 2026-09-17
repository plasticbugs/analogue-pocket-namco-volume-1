//------------------------------------------------------------------------------
// Analogue Pocket top for the Namco ND-1 core (Namco Classic Collection Vol.1).
// Structure follows the Gaiapolis core's core_top.sv: APF bridge, data slots
// (0 = ROM image into SDRAM through ncv1_mem, 1 = the 2 KB EEPROM save),
// interact menu, video and audio hand-off, and a diagnostic overlay.
//------------------------------------------------------------------------------
`default_nettype none

module core_top
    #(
         parameter BPP_R        = 8,
         parameter BPP_G        = 8,
         parameter BPP_B        = 8,
         parameter AUDIO_DW     = 16,
         parameter AUDIO_S      = 1,
         parameter STEREO       = 1,
         parameter AUDIO_MIX    = 0,
         parameter JOY_PADS     = 2,
         parameter JOY_ALT      = 0,
         parameter DIO_MASK     = 4'h0,
         parameter DIO_AW       = 27,
         parameter DIO_DW       = 8,
         parameter DIO_DELAY    = 7,
         parameter DIO_HOLD     = 4
     ) (
         input wire          clk_74a,
         input wire          clk_74b,
         inout  wire   [7:0] cart_tran_bank2,
         output wire         cart_tran_bank2_dir,
         inout  wire   [7:0] cart_tran_bank3,
         output wire         cart_tran_bank3_dir,
         inout  wire   [7:0] cart_tran_bank1,
         output wire         cart_tran_bank1_dir,
         inout  wire   [7:4] cart_tran_bank0,
         output wire         cart_tran_bank0_dir,
         inout  wire         cart_tran_pin30,
         output wire         cart_tran_pin30_dir,
         output wire         cart_pin30_pwroff_reset,
         inout  wire         cart_tran_pin31,
         output wire         cart_tran_pin31_dir,
         input  wire         port_ir_rx,
         output wire         port_ir_tx,
         output wire         port_ir_rx_disable,
         inout  wire         port_tran_si,
         output wire         port_tran_si_dir,
         inout  wire         port_tran_so,
         output wire         port_tran_so_dir,
         inout  wire         port_tran_sck,
         output wire         port_tran_sck_dir,
         inout  wire         port_tran_sd,
         output wire         port_tran_sd_dir,
         output wire [21:16] cram0_a,
         inout  wire  [15:0] cram0_dq,
         input  wire         cram0_wait,
         output wire         cram0_clk,
         output wire         cram0_adv_n,
         output wire         cram0_cre,
         output wire         cram0_ce0_n,
         output wire         cram0_ce1_n,
         output wire         cram0_oe_n,
         output wire         cram0_we_n,
         output wire         cram0_ub_n,
         output wire         cram0_lb_n,
         output wire [21:16] cram1_a,
         inout  wire  [15:0] cram1_dq,
         input  wire         cram1_wait,
         output wire         cram1_clk,
         output wire         cram1_adv_n,
         output wire         cram1_cre,
         output wire         cram1_ce0_n,
         output wire         cram1_ce1_n,
         output wire         cram1_oe_n,
         output wire         cram1_we_n,
         output wire         cram1_ub_n,
         output wire         cram1_lb_n,
         output wire  [12:0] dram_a,
         output wire   [1:0] dram_ba,
         inout  wire  [15:0] dram_dq,
         output wire   [1:0] dram_dqm,
         output wire         dram_clk,
         output wire         dram_cke,
         output wire         dram_ras_n,
         output wire         dram_cas_n,
         output wire         dram_we_n,
         output wire  [16:0] sram_a,
         inout  wire  [15:0] sram_dq,
         output wire         sram_oe_n,
         output wire         sram_we_n,
         output wire         sram_ub_n,
         output wire         sram_lb_n,
         input  wire         vblank,
         output wire         dbg_tx,
         input  wire         dbg_rx,
         output wire         user1,
         input  wire         user2,
         inout  wire         aux_sda,
         output wire         aux_scl,
         output wire         vpll_feed,
         output wire  [23:0] video_rgb,
         output wire         video_rgb_clock,
         output wire         video_rgb_clock_90,
         output wire         video_hs,
         output wire         video_vs,
         output wire         video_de,
         output wire         video_skip,
         output wire         audio_mclk,
         output wire         audio_lrck,
         output wire         audio_dac,
         input  wire         audio_adc,
         output wire         bridge_endian_little,
         input  wire  [31:0] bridge_addr,
         input  wire         bridge_rd,
         output reg   [31:0] bridge_rd_data,
         input  wire         bridge_wr,
         input  wire  [31:0] bridge_wr_data,
         input  wire  [31:0] cont1_key,
         input  wire  [31:0] cont2_key,
         input  wire  [31:0] cont3_key,
         input  wire  [31:0] cont4_key,
         input  wire  [31:0] cont1_joy,
         input  wire  [31:0] cont2_joy,
         input  wire  [31:0] cont3_joy,
         input  wire  [31:0] cont4_joy,
         input  wire  [15:0] cont1_trig,
         input  wire  [15:0] cont2_trig,
         input  wire  [15:0] cont3_trig,
         input  wire  [15:0] cont4_trig
     );
    // ---------------------------------------------------------- unused pins
    assign port_ir_tx = 0;
    assign port_ir_rx_disable = 1;
    assign bridge_endian_little = 0;
    assign cart_tran_bank3 = 8'hzz; assign cart_tran_bank3_dir = 1'b0;
    assign cart_tran_bank2 = 8'hzz; assign cart_tran_bank2_dir = 1'b0;
    assign cart_tran_bank1 = 8'hzz; assign cart_tran_bank1_dir = 1'b0;
    assign cart_tran_bank0 = 4'hf;  assign cart_tran_bank0_dir = 1'b1;
    assign cart_tran_pin30 = 1'b0;  assign cart_tran_pin30_dir = 1'bz;
    assign cart_pin30_pwroff_reset = 1'b0;
    assign cart_tran_pin31 = 1'bz;  assign cart_tran_pin31_dir = 1'b0;
    assign port_tran_so = 1'bz;  assign port_tran_so_dir = 1'b0;
    assign port_tran_si = 1'bz;  assign port_tran_si_dir = 1'b0;
    assign port_tran_sck = 1'bz; assign port_tran_sck_dir = 1'b0;
    assign port_tran_sd = 1'bz;  assign port_tran_sd_dir = 1'b0;
    assign video_skip = 1'b0;
    assign dbg_tx = 1'bZ; assign user1 = 1'bZ; assign aux_scl = 1'bZ; assign vpll_feed = 1'bZ;
    // PSRAM and SRAM are not used
    assign cram0_a = 'h0; assign cram0_dq = {16{1'bZ}}; assign cram0_clk = 0; assign cram0_adv_n = 1; assign cram0_cre = 0;
    assign cram0_ce0_n = 1; assign cram0_ce1_n = 1; assign cram0_oe_n = 1; assign cram0_we_n = 1; assign cram0_ub_n = 1; assign cram0_lb_n = 1;
    assign cram1_a = 'h0; assign cram1_dq = {16{1'bZ}}; assign cram1_clk = 0; assign cram1_adv_n = 1; assign cram1_cre = 0;
    assign cram1_ce0_n = 1; assign cram1_ce1_n = 1; assign cram1_oe_n = 1; assign cram1_we_n = 1; assign cram1_ub_n = 1; assign cram1_lb_n = 1;
    assign sram_a = 'h0; assign sram_dq = {16{1'bZ}}; assign sram_oe_n = 1; assign sram_we_n = 1; assign sram_ub_n = 1; assign sram_lb_n = 1;

    // ---------------------------------------------------------- APF bridge
    wire        reset_n;
    wire [31:0] cmd_bridge_rd_data;
    wire        status_boot_done  = pll_core_locked_s;
    wire        status_setup_done = pll_core_locked_s;
    wire        status_running    = reset_n;
    wire        dataslot_requestread;
    wire [15:0] dataslot_requestread_id;
    wire        dataslot_requestread_ack = 1;
    wire        dataslot_requestread_ok  = 1;
    wire        dataslot_requestwrite;
    wire [15:0] dataslot_requestwrite_id;
    wire [31:0] dataslot_requestwrite_size;
    wire        dataslot_requestwrite_ack = 1;
    wire        dataslot_requestwrite_ok  = 1;
    wire        dataslot_update;
    wire [15:0] dataslot_update_id;
    wire [31:0] dataslot_update_size;
    wire        dataslot_allcomplete;
    wire [31:0] rtc_epoch_seconds, rtc_date_bcd, rtc_time_bcd;
    wire        rtc_valid;
    wire        savestate_supported;
    wire [31:0] savestate_addr, savestate_size, savestate_maxloadsize;
    wire        savestate_start, savestate_start_ack, savestate_start_busy, savestate_start_ok, savestate_start_err;
    wire        savestate_load, savestate_load_ack, savestate_load_busy, savestate_load_ok, savestate_load_err;
    wire        osnotify_inmenu;
    reg         target_dataslot_read, target_dataslot_write, target_dataslot_getfile, target_dataslot_openfile;
    wire        target_dataslot_ack, target_dataslot_done;
    wire  [2:0] target_dataslot_err;
    reg  [15:0] target_dataslot_id;
    reg  [31:0] target_dataslot_slotoffset, target_dataslot_bridgeaddr, target_dataslot_length;
    wire [31:0] target_buffer_param_struct, target_buffer_resp_struct;
    logic  [9:0] datatable_addr;
    logic        datatable_wren;
    logic [31:0] datatable_data;
    wire  [31:0] datatable_q;
    localparam [31:0] NV_BYTES = 32'h800;      // the AT28C16
    always_ff @(posedge clk_74a) begin
        datatable_wren <= 1'b1;
        datatable_addr <= 10'd3;                // slot 1 size entry
        datatable_data <= NV_BYTES;
    end

    core_bridge_cmd icb (
        .clk(clk_74a), .reset_n(reset_n),
        .bridge_endian_little(bridge_endian_little), .bridge_addr(bridge_addr), .bridge_rd(bridge_rd),
        .bridge_rd_data(cmd_bridge_rd_data), .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data),
        .status_boot_done(status_boot_done), .status_setup_done(status_setup_done), .status_running(status_running),
        .dataslot_requestread(dataslot_requestread), .dataslot_requestread_id(dataslot_requestread_id),
        .dataslot_requestread_ack(dataslot_requestread_ack), .dataslot_requestread_ok(dataslot_requestread_ok),
        .dataslot_requestwrite(dataslot_requestwrite), .dataslot_requestwrite_id(dataslot_requestwrite_id),
        .dataslot_requestwrite_size(dataslot_requestwrite_size), .dataslot_requestwrite_ack(dataslot_requestwrite_ack),
        .dataslot_requestwrite_ok(dataslot_requestwrite_ok), .dataslot_update(dataslot_update),
        .dataslot_update_id(dataslot_update_id), .dataslot_update_size(dataslot_update_size),
        .dataslot_allcomplete(dataslot_allcomplete),
        .rtc_epoch_seconds(rtc_epoch_seconds), .rtc_date_bcd(rtc_date_bcd), .rtc_time_bcd(rtc_time_bcd), .rtc_valid(rtc_valid),
        .savestate_supported(savestate_supported), .savestate_addr(savestate_addr), .savestate_size(savestate_size),
        .savestate_maxloadsize(savestate_maxloadsize), .savestate_start(savestate_start), .savestate_start_ack(savestate_start_ack),
        .savestate_start_busy(savestate_start_busy), .savestate_start_ok(savestate_start_ok), .savestate_start_err(savestate_start_err),
        .savestate_load(savestate_load), .savestate_load_ack(savestate_load_ack), .savestate_load_busy(savestate_load_busy),
        .savestate_load_ok(savestate_load_ok), .savestate_load_err(savestate_load_err),
        .osnotify_inmenu(osnotify_inmenu),
        .target_dataslot_read(target_dataslot_read), .target_dataslot_write(target_dataslot_write),
        .target_dataslot_getfile(target_dataslot_getfile), .target_dataslot_openfile(target_dataslot_openfile),
        .target_dataslot_ack(target_dataslot_ack), .target_dataslot_done(target_dataslot_done), .target_dataslot_err(target_dataslot_err),
        .target_dataslot_id(target_dataslot_id), .target_dataslot_slotoffset(target_dataslot_slotoffset),
        .target_dataslot_bridgeaddr(target_dataslot_bridgeaddr), .target_dataslot_length(target_dataslot_length),
        .target_buffer_param_struct(target_buffer_param_struct), .target_buffer_resp_struct(target_buffer_resp_struct),
        .datatable_addr(datatable_addr), .datatable_wren(datatable_wren), .datatable_data(datatable_data), .datatable_q(datatable_q)
    );

    // ---------------------------------------------------------- save slot (EEPROM), as gaia
    wire [31:0] int_bridge_rd_data;
    wire [31:0] nvm_bridge_rd_data_s;
    wire        nv_dl_download, nv_dl_wr;
    wire [10:0] nv_dl_addr;
    wire  [7:0] nv_dl_data;
    wire [15:0] nv_dl_index;
    data_io #(.MASK(4'h2), .AW(11), .DW(8), .DELAY(DIO_DELAY), .HOLD(DIO_HOLD)) pocket_nv_io (
        .clk_74a(clk_74a), .clk_memory(clk_sys),
        .dataslot_requestwrite(dataslot_requestwrite), .dataslot_requestwrite_id(dataslot_requestwrite_id),
        .dataslot_allcomplete(dataslot_allcomplete),
        .bridge_endian_little(bridge_endian_little), .bridge_addr(bridge_addr),
        .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data),
        .ioctl_download(nv_dl_download), .ioctl_index(nv_dl_index), .ioctl_wr(nv_dl_wr),
        .ioctl_addr(nv_dl_addr), .ioctl_data(nv_dl_data)
    );
    wire        nv_rd_en;
    wire [10:0] nv_rd_addr;
    wire  [7:0] nv_rd_data;
    data_unloader #(.ADDRESS_MASK_UPPER_4(4'h2), .ADDRESS_SIZE(11), .READ_MEM_CLOCK_DELAY(4), .INPUT_WORD_SIZE(1)) pocket_nv_unload (
        .clk_74a(clk_74a), .clk_memory(clk_sys),
        .bridge_rd(bridge_rd), .bridge_endian_little(bridge_endian_little), .bridge_addr(bridge_addr),
        .bridge_rd_data(nvm_bridge_rd_data_s),
        .read_en(nv_rd_en), .read_addr(nv_rd_addr), .read_data(nv_rd_data)
    );
    wire        po_nv_dirty;
    wire        nv_dirty_s, inmenu_s;
    synch_3 sync_nvd(po_nv_dirty, nv_dirty_s, clk_74a);
    synch_3 sync_inmenu(osnotify_inmenu, inmenu_s, clk_74a);
    reg         nv_dirty_d = 1'b0, inmenu_d = 1'b0, nv_pending = 1'b0, nv_loaded = 1'b0;
    reg  [27:0] nv_timer = 28'd0;
    reg  [1:0]  nv_state = 2'd0;
    reg  [28:0] boot_timer = 29'd0;
    localparam  NV_SETTLE = 28'd148_500_000;   // 2 s
    localparam  NV_BOOT   = 29'd371_250_000;   // 5 s
    always_ff @(posedge clk_74a) begin
        nv_dirty_d <= nv_dirty_s; inmenu_d <= inmenu_s;
        target_dataslot_read <= 1'b0; target_dataslot_getfile <= 1'b0; target_dataslot_openfile <= 1'b0;
        target_dataslot_id <= 16'd1; target_dataslot_slotoffset <= 32'd0;
        target_dataslot_bridgeaddr <= 32'h2000_0000; target_dataslot_length <= NV_BYTES;
        if (dataslot_allcomplete) nv_loaded <= 1'b1;
        if (nv_loaded && boot_timer != NV_BOOT) boot_timer <= boot_timer + 29'd1;
        if (nv_dirty_s != nv_dirty_d) begin nv_pending <= 1'b1; nv_timer <= 28'd0; end
        else if (nv_timer != NV_SETTLE) nv_timer <= nv_timer + 28'd1;
        case (nv_state)
            2'd0: begin
                target_dataslot_write <= 1'b0;
                if ((nv_pending && nv_loaded && (nv_timer == NV_SETTLE || (inmenu_s && !inmenu_d))) || (boot_timer == NV_BOOT - 29'd1)) begin
                    target_dataslot_write <= 1'b1; nv_pending <= 1'b0; nv_state <= 2'd1;
                end
            end
            2'd1: if (target_dataslot_ack)  begin target_dataslot_write <= 1'b0; nv_state <= 2'd2; end
            2'd2: if (target_dataslot_done) nv_state <= 2'd0;
            default: nv_state <= 2'd0;
        endcase
    end

    always_comb begin
        casex (bridge_addr)
            32'h2xxxxxxx: bridge_rd_data = nvm_bridge_rd_data_s;
            32'hF0000000, 32'hF0000010, 32'hF1000000, 32'hF2000000, 32'hF3000000, 32'hF4000000,
            32'hFA000000, 32'hFB000000: bridge_rd_data = int_bridge_rd_data;
            32'hF8xxxxxx: bridge_rd_data = cmd_bridge_rd_data;
            default:      bridge_rd_data = 32'd0;
        endcase
    end

    wire pause_core, pause_req;
    pause_crtl core_pause (.clk_sys(clk_sys), .os_inmenu(osnotify_inmenu), .pause_req(pause_req), .pause_core(pause_core));

    wire  [7:0] dip_sw0, dip_sw1, dip_sw2, dip_sw3, ext_sw0, ext_sw1, ext_sw2, ext_sw3, mod_sw0, mod_sw1, mod_sw2, mod_sw3;
    wire  [3:0] scnl_sw, smask_sw, afilter_sw, vol_att;
    wire [63:0] status;
    wire        reset_sw, svc_sw, nvclear_sw;
    interact pocket_interact (
        .clk_74a(clk_74a), .clk_sync(clk_sys), .reset_n(reset_n),
        .bridge_addr(bridge_addr), .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data), .bridge_rd(bridge_rd), .bridge_rd_data(int_bridge_rd_data),
        .svc_sw(svc_sw), .dip_sw0(dip_sw0), .dip_sw1(dip_sw1), .dip_sw2(dip_sw2), .dip_sw3(dip_sw3),
        .ext_sw0(ext_sw0), .ext_sw1(ext_sw1), .ext_sw2(ext_sw2), .ext_sw3(ext_sw3),
        .mod_sw0(mod_sw0), .mod_sw1(mod_sw1), .mod_sw2(mod_sw2), .mod_sw3(mod_sw3),
        .status(status), .scnl_sw(scnl_sw), .smask_sw(smask_sw), .afilter_sw(afilter_sw), .vol_att(vol_att),
        .reset_sw(reset_sw), .nvclear_sw(nvclear_sw)
    );

    // ---------------------------------------------------------- audio out
    wire [AUDIO_DW-1:0] core_snd_l, core_snd_r;
    audio_mixer #(.DW(AUDIO_DW), .STEREO(STEREO), .IIR(0)) pocket_audio_mixer (
        .clk_74b(clk_74b), .reset(reset_sw), .afilter_sw(afilter_sw), .vol_att(vol_att), .mix(AUDIO_MIX),
        .pause_core(pause_core), .is_signed(AUDIO_S), .core_l(core_snd_l), .core_r(core_snd_r),
        .audio_mclk(audio_mclk), .audio_lrck(audio_lrck), .audio_dac(audio_dac)
    );

    // ---------------------------------------------------------- video out
    wire       [2:0] video_preset;
    wire [BPP_R-1:0] core_r; wire [BPP_G-1:0] core_g; wire [BPP_B-1:0] core_b;
    wire             core_hs, core_vs, core_de;
    video_mixer #(.RW(BPP_R), .GW(BPP_G), .BW(BPP_B)) pocket_video_mixer (
        .clk_74a(clk_74a), .clk_sys(clk_sys), .clk_vid(clk_vid), .clk_vid_90deg(clk_vid_90deg),
        .video_preset(video_preset), .scnl_sw(scnl_sw), .smask_sw(smask_sw),
        .core_r(core_r), .core_g(core_g), .core_b(core_b), .core_vs(core_vs), .core_hs(core_hs), .core_de(core_de),
        .video_rgb(video_rgb), .video_vs(video_vs), .video_hs(video_hs), .video_de(video_de),
        .video_rgb_clock(video_rgb_clock), .video_rgb_clock_90(video_rgb_clock_90),
        .dataslot_requestwrite(dataslot_requestwrite), .dataslot_requestwrite_id(dataslot_requestwrite_id),
        .dataslot_allcomplete(dataslot_allcomplete), .bridge_endian_little(bridge_endian_little),
        .bridge_addr(bridge_addr), .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data)
    );

    // ---------------------------------------------------------- ROM image loader
    wire              ioctl_download;
    wire       [15:0] ioctl_index;
    wire              ioctl_wr;
    wire [DIO_AW-1:0] ioctl_addr;
    wire [DIO_DW-1:0] ioctl_data;
    data_io #(.MASK(DIO_MASK), .AW(DIO_AW), .DW(DIO_DW), .DELAY(DIO_DELAY), .HOLD(DIO_HOLD)) pocket_data_io (
        .clk_74a(clk_74a), .clk_memory(clk_sys),
        .dataslot_requestwrite(dataslot_requestwrite), .dataslot_requestwrite_id(dataslot_requestwrite_id),
        .dataslot_allcomplete(dataslot_allcomplete), .bridge_endian_little(bridge_endian_little),
        .bridge_addr(bridge_addr), .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data),
        .ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_data(ioctl_data)
    );

    // ---------------------------------------------------------- gamepads
    wire p1_up, p1_down, p1_left, p1_right, p1_btn_y, p1_btn_x, p1_btn_b, p1_btn_a;
    wire p1_btn_l1, p1_btn_l2, p1_btn_l3, p1_btn_r1, p1_btn_r2, p1_btn_r3, p1_select, p1_start;
    wire j1_up, j1_down, j1_left, j1_right; wire [7:0] j1_lx, j1_ly, j1_rx, j1_ry;
    wire p2_up, p2_down, p2_left, p2_right, p2_btn_y, p2_btn_x, p2_btn_b, p2_btn_a;
    wire p2_btn_l1, p2_btn_l2, p2_btn_l3, p2_btn_r1, p2_btn_r2, p2_btn_r3, p2_select, p2_start;
    wire j2_up, j2_down, j2_left, j2_right; wire [7:0] j2_lx, j2_ly, j2_rx, j2_ry;
    wire m_start1, m_start2, m_coin1, m_coin2, m_coin, m_up, m_down, m_left, m_right;
    wire m_btn1, m_btn2, m_btn3, m_btn4, m_btn5, m_btn6, m_btn7, m_btn8;
    gamepad #(.JOY_PADS(JOY_PADS), .JOY_ALT(JOY_ALT)) pocket_gamepad (
        .clk_sys(clk_sys),
        .cont1_key(cont1_key), .cont1_joy(cont1_joy), .cont2_key(cont2_key), .cont2_joy(cont2_joy),
        .cont3_key(cont3_key), .cont3_joy(cont3_joy), .cont4_key(cont4_key), .cont4_joy(cont4_joy),
        .p1_up(p1_up), .p1_down(p1_down), .p1_left(p1_left), .p1_right(p1_right),
        .p1_y(p1_btn_y), .p1_x(p1_btn_x), .p1_b(p1_btn_b), .p1_a(p1_btn_a),
        .p1_l1(p1_btn_l1), .p1_r1(p1_btn_r1), .p1_l2(p1_btn_l2), .p1_r2(p1_btn_r2), .p1_l3(p1_btn_l3), .p1_r3(p1_btn_r3),
        .p1_se(p1_select), .p1_st(p1_start),
        .j1_up(j1_up), .j1_down(j1_down), .j1_left(j1_left), .j1_right(j1_right), .j1_lx(j1_lx), .j1_ly(j1_ly), .j1_rx(j1_rx), .j1_ry(j1_ry),
        .p2_up(p2_up), .p2_down(p2_down), .p2_left(p2_left), .p2_right(p2_right),
        .p2_y(p2_btn_y), .p2_x(p2_btn_x), .p2_b(p2_btn_b), .p2_a(p2_btn_a),
        .p2_l1(p2_btn_l1), .p2_r1(p2_btn_r1), .p2_l2(p2_btn_l2), .p2_r2(p2_btn_r2), .p2_l3(p2_btn_l3), .p2_r3(p2_btn_r3),
        .p2_se(p2_select), .p2_st(p2_start),
        .j2_up(j2_up), .j2_down(j2_down), .j2_left(j2_left), .j2_right(j2_right), .j2_lx(j2_lx), .j2_ly(j2_ly), .j2_rx(j2_rx), .j2_ry(j2_ry),
        .m_coin(m_coin), .m_up(m_up), .m_down(m_down), .m_left(m_left), .m_right(m_right),
        .m_btn1(m_btn1), .m_btn4(m_btn4), .m_btn2(m_btn2), .m_btn3(m_btn3), .m_btn5(m_btn5), .m_btn6(m_btn6), .m_btn7(m_btn7), .m_btn8(m_btn8),
        .m_coin1(m_coin1), .m_coin2(m_coin2), .m_start1(m_start1), .m_start2(m_start2)
    );

    // ---------------------------------------------------------- clocks
    wire pll_core_locked, pll_core_locked_s;
    wire clk_sys;        // 96 MHz
    wire clk_vid;        // 6.4 MHz dot clock, clk_sys / 15
    wire clk_vid_90deg;
    wire clk_sdram;      // 96 MHz phase-shifted
    wire clk_unused1;
    core_pll core_pll (
        .refclk(clk_74a), .rst(0),
        .outclk_0(clk_sys), .outclk_1(clk_vid), .outclk_2(clk_vid_90deg), .outclk_3(clk_sdram), .outclk_4(clk_unused1),
        .locked(pll_core_locked)
    );
    synch_3 sync_lck(pll_core_locked, pll_core_locked_s, clk_74a);
    wire reset_sw_s, pll_locked_sys, loaded_s;
    synch_3 sync_rst(reset_sw, reset_sw_s, clk_sys);
    synch_3 sync_lck2(pll_core_locked, pll_locked_sys, clk_sys);
    synch_3 sync_loaded(nv_loaded, loaded_s, clk_sys);

    // ---------------------------------------------------------- memory
    wire        mem_init = ~pll_locked_sys;
    wire        mem_ready, dl_busy;
    wire        ioctl_isROM = ioctl_download && ioctl_index == 16'h0;
    wire        dl_we    = ioctl_isROM && ioctl_wr;
    wire [24:0] dl_addr  = ioctl_addr[24:0];
    wire  [7:0] dl_data  = ioctl_data;
    wire        prog_req, prog_ack, sub_req, sub_ack, pat_req, pat_ack, pcm_req, pcm_ack;
    wire [19:1] prog_addr; wire [18:1] sub_addr; wire [20:0] pat_addr; wire [23:0] pcm_addr;
    wire  [6:0] pat_len; wire pat_wr; wire [5:0] pat_idx;
    wire [15:0] prog_q, sub_q; wire [31:0] pat_q; wire [7:0] pcm_q;
    ncv1_mem u_mem (
        .clk(clk_sys), .clk_sdram(clk_sdram), .init(mem_init), .ready(mem_ready),
        .rd_late(~mod_sw0[4]), .burst_slow(mod_sw0[5]),
        .dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data), .dl_busy(dl_busy),
        .prog_addr(prog_addr), .prog_req(prog_req), .prog_ack(prog_ack), .prog_q(prog_q),
        .sub_addr(sub_addr), .sub_req(sub_req), .sub_ack(sub_ack), .sub_q(sub_q),
        .pat_addr(pat_addr), .pat_req(pat_req), .pat_ack(pat_ack), .pat_q(pat_q),
        .pat_len(pat_len), .pat_wr(pat_wr), .pat_idx(pat_idx),
        .pcm_addr(pcm_addr), .pcm_req(pcm_req), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
        .dram_dq(dram_dq), .dram_a(dram_a), .dram_ba(dram_ba), .dram_dqm(dram_dqm),
        .dram_clk(dram_clk), .dram_cke(dram_cke), .dram_ras_n(dram_ras_n), .dram_cas_n(dram_cas_n), .dram_we_n(dram_we_n)
    );

    // ---------------------------------------------------------- the machine
    // held in reset until the image and the save slot are loaded and SDRAM is ready
    // registered twice: it fans out to every register in the machine and nothing needs it fast
    wire        core_reset_c = reset_sw_s | ~loaded_s | ~mem_ready | dl_busy | ioctl_download;
    reg         core_reset_q = 1'b1, core_reset = 1'b1;
    always @(posedge clk_sys) begin core_reset_q <= core_reset_c; core_reset <= core_reset_q; end
    // EEPROM load from the save slot (slot 1); read-out for the save
    wire        nv_load_we = nv_dl_download && nv_dl_index == 16'h1 && nv_dl_wr;
    // inputs: active low. DSW: bit 8 freeze, 9 test, 12 coin1, 13 coin2, 14 service, 15 service1
    wire        test_sw = mod_sw1[0] | svc_sw;
    wire        p1_b1 = p1_btn_a | j1_up & 1'b0, p1_b2 = p1_btn_b, p1_b3 = p1_btn_x | p1_btn_y;
    wire        p2_b1 = p2_btn_a, p2_b2 = p2_btn_b, p2_b3 = p2_btn_x | p2_btn_y;
    wire [15:0] p1p2 = ~{p2_start, p2_b3, p2_b2, p2_b1, p2_up | j2_up, p2_down | j2_down, p2_left | j2_left, p2_right | j2_right,
                         p1_start, p1_b3, p1_b2, p1_b1, p1_up | j1_up, p1_down | j1_down, p1_left | j1_left, p1_right | j1_right};
    wire [15:0] dsw  = ~{mod_sw1[1], 1'b0, p2_select, p1_select, 2'b00, test_sw, 1'b0, 8'h00};

    wire        ga_cen_pix, ga_hs, ga_vs, ga_hb, ga_vb, ga_de;
    wire [23:0] ga_rgb;
    wire [15:0] ga_snd_l, ga_snd_r;
    wire        ga_snd_valid;
    wire        dbg_68k_halted, dbg_h8_run, dbg_h8_istart, dbg_h8_irq, dbg_vunsup;
    wire  [3:0] dbg_vunsup_src;
    wire        dbg_c352_ovr;
    wire [23:1] dbg_68k_addr; wire [23:0] dbg_h8_pc; wire [1:0] dbg_gfxbank;
    // the clock after clk_vid's edge is seen in the clk_sys domain
    reg vt = 1'b0, vt_s, vt_d;
    always @(posedge clk_vid) vt <= ~vt;
    always @(posedge clk_sys) begin vt_s <= vt; vt_d <= vt_s; end
    wire pix_sync = vt_s ^ vt_d;
    ncv1_core #(.HEXDIR("../rtl/data")) ga (
        .clk(clk_sys), .reset(core_reset), .pix_sync(pix_sync),
        .prog_addr(prog_addr), .prog_req(prog_req), .prog_ack(prog_ack), .prog_q(prog_q),
        .sub_addr(sub_addr), .sub_req(sub_req), .sub_ack(sub_ack), .sub_q(sub_q),
        .pat_addr(pat_addr), .pat_req(pat_req), .pat_ack(pat_ack), .pat_q(pat_q),
        .pat_len(pat_len), .pat_wr(pat_wr), .pat_idx(pat_idx),
        .pcm_addr(pcm_addr), .pcm_req(pcm_req), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
        .eep_ld_we(nv_load_we), .eep_ld_addr(nv_dl_addr), .eep_ld_data(nv_dl_data),
        .eep_rd_addr(nv_rd_addr), .eep_rd_q(nv_rd_data), .eep_dirty(po_nv_dirty),
        .dsw(dsw), .p1p2(p1p2),
        .cen_pix(ga_cen_pix), .hsync(ga_hs), .vsync(ga_vs), .hblank(ga_hb), .vblank(ga_vb), .de(ga_de), .rgb(ga_rgb),
        .snd_l(ga_snd_l), .snd_r(ga_snd_r), .snd_valid(ga_snd_valid),
        .dbg_68k_halted(dbg_68k_halted), .dbg_68k_addr(dbg_68k_addr), .dbg_h8_run(dbg_h8_run), .dbg_h8_pc(dbg_h8_pc),
        .dbg_h8_istart(dbg_h8_istart), .dbg_h8_irq(dbg_h8_irq), .dbg_video_unsupported(dbg_vunsup), .dbg_video_unsup_src(dbg_vunsup_src), .dbg_gfxbank(dbg_gfxbank), .dbg_c352_overrun(dbg_c352_ovr)
    );
    wire _unused_top = &{1'b0, nv_rd_en, ga_hb, ga_vb, dbg_h8_pc, pause_req, nvclear_sw, ext_sw0, ext_sw1, ext_sw2, ext_sw3,
                         dip_sw0, dip_sw1, dip_sw2, dip_sw3, mod_sw2, mod_sw3, status, clk_unused1, dataslot_requestread,
                         dataslot_requestread_id, dataslot_requestwrite_size, dataslot_update, dataslot_update_id,
                         dataslot_update_size, target_dataslot_err, cont1_trig, cont2_trig, cont3_trig, cont4_trig,
                         port_ir_rx, dbg_rx, user2, audio_adc, vblank, cram0_wait, cram1_wait, aux_sda, sram_dq,
                         j1_lx, j1_ly, j1_rx, j1_ry, j2_lx, j2_ly, j2_rx, j2_ry, p1_btn_l1, p1_btn_l2, p1_btn_l3, p1_btn_r1,
                         p1_btn_r2, p1_btn_r3, p2_btn_l1, p2_btn_l2, p2_btn_l3, p2_btn_r1, p2_btn_r2, p2_btn_r3,
                         m_start1, m_start2, m_coin1, m_coin2, m_coin, m_up, m_down, m_left, m_right, m_btn1, m_btn2, m_btn3,
                         m_btn4, m_btn5, m_btn6, m_btn7, m_btn8, rtc_epoch_seconds, rtc_date_bcd, rtc_time_bcd, rtc_valid,
                         savestate_supported, savestate_addr, savestate_size, savestate_maxloadsize, savestate_start,
                         savestate_start_ack, savestate_start_busy, savestate_start_ok, savestate_start_err, savestate_load,
                         savestate_load_ack, savestate_load_busy, savestate_load_ok, savestate_load_err,
                         target_buffer_param_struct, target_buffer_resp_struct, datatable_q, dbg_68k_addr, dbg_gfxbank};

    // Screen shape: mod_sw0[2:1] = 1 selects the square-pixel scaler mode. Both
    // video.json modes rotate the native 288x224 raster 90 degrees clockwise;
    // their aspect values describe the raster BEFORE rotation (measured on
    // hardware by the Time Pilot core), so the 3:4 cabinet shape is written 4:3.
    assign video_preset = (mod_sw0[2:1] == 2'd1) ? 3'd1 : 3'd0;

    // ---------------------------------------------------------- diagnostic overlay
    wire        ovl_en = mod_sw0[3];
    logic [7:0] ovl_frames;
    logic       ovl_vs_d, ovl_seen_h8, ovl_seen_irq, ovl_seen_snd, ovl_unsup, ovl_unsup_l;
    logic       allc_s;
    synch_3 sync_allc(dataslot_allcomplete, allc_s, clk_sys);
    always_ff @(posedge clk_sys) begin
        ovl_vs_d <= ga_vs;
        if (ga_vs && !ovl_vs_d) begin
            ovl_frames <= ovl_frames + 8'd1;
            ovl_seen_h8 <= 1'b0; ovl_seen_irq <= 1'b0; ovl_seen_snd <= 1'b0;
            ovl_unsup_l <= ovl_unsup; ovl_unsup <= 1'b0;
        end
        if (dbg_h8_istart) ovl_seen_h8 <= 1'b1;
        if (dbg_h8_irq) ovl_seen_irq <= 1'b1;
        if (dbg_vunsup) ovl_unsup <= 1'b1;
        if (ga_snd_valid && ga_snd_l != 16'd0) ovl_seen_snd <= 1'b1;
    end
    wire [95:0] ovl_status = {
        ovl_frames, pll_locked_sys, mem_ready, ioctl_download, allc_s, loaded_s, core_reset, dl_busy, 1'b0,
        dbg_68k_halted, dbg_h8_run, ovl_seen_h8, ovl_seen_irq, ovl_seen_snd, ovl_unsup_l, 2'b00,
        dbg_vunsup_src, dbg_c352_ovr, 3'd0,
        dbg_68k_addr[23:8], 8'd0,
        dbg_h8_pc[23:8], 16'd0
    };
    wire [7:0] ovl_r, ovl_g, ovl_b;
    dbg_overlay ovl (
        .clk(clk_sys), .cen_pix(ga_cen_pix), .enable(ovl_en), .de(ga_de), .vsync(ga_vs),
        .r_in(ga_rgb[23:16]), .g_in(ga_rgb[15:8]), .b_in(ga_rgb[7:0]),
        .status(ovl_status), .r_out(ovl_r), .g_out(ovl_g), .b_out(ovl_b)
    );

    // hand the raster to the 6.4 MHz video clock domain: the core's pixel enable is
    // a fixed /15 of clk_sys and clk_vid is the PLL's clk_sys/15, so a registered
    // copy on clk_vid samples a stable pixel (the pixel changes once per 15 clocks)
    reg [7:0] vr_q, vg_q, vb_q;
    reg       vhs_q, vvs_q, vde_q;
    always @(posedge clk_vid) begin
        vr_q <= ovl_r; vg_q <= ovl_g; vb_q <= ovl_b;
        vhs_q <= ga_hs; vvs_q <= ga_vs; vde_q <= ga_de;
    end
    assign core_r = vr_q; assign core_g = vg_q; assign core_b = vb_q;
    assign core_hs = vhs_q; assign core_vs = vvs_q; assign core_de = vde_q;

    // audio CDC (METHODOLOGY §5.4): hold per sample, hand over with a toggle
    logic signed [15:0] snd_hold_l = 16'sd0, snd_hold_r = 16'sd0;
    logic               snd_tog = 1'b0;
    always_ff @(posedge clk_sys) begin
        if (ga_snd_valid) begin snd_hold_l <= ga_snd_l; snd_hold_r <= ga_snd_r; snd_tog <= ~snd_tog; end
    end
    logic        [2:0]  snd_tog_s = 3'd0;
    logic signed [15:0] snd_xfer_l = 16'sd0, snd_xfer_r = 16'sd0;
    always_ff @(posedge clk_74b) begin
        snd_tog_s <= {snd_tog_s[1:0], snd_tog};
        if (snd_tog_s[2] != snd_tog_s[1]) begin snd_xfer_l <= snd_hold_l; snd_xfer_r <= snd_hold_r; end
    end
    assign core_snd_l = snd_xfer_l;
    assign core_snd_r = snd_xfer_r;
endmodule
