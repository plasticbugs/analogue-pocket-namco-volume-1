# ==============================================================================
# Gaiapolis on the Pocket: timing constraints beyond the BSP's sys_constr.sdc.
# The 96 MHz system clock, its 8 MHz video pair and the shifted SDRAM clock
# all come from core_pll and are timed as one related group; the two 74.25 MHz
# inputs and the audio PLL are asynchronous to it.
# ==============================================================================
set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|core_pll|core_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|pocket_audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|pocket_audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk }

# SDRAM: the chip is clocked by the phase-shifted PLL output (the S.T.U.N.
# Runner core's proven arrangement, same controller). The shift is 6.51 ns
# (50 eighths of the 960 MHz VCO period; legal values are multiples of
# 130.2 ps), 0.26 ns later than there: it was 6.90 while the address
# registers sat in core logic, and with them in the IO cells (3 ns of slack)
# the data inputs, which missed the cold corner by 14 ps, get 0.39 ns back.
create_generated_clock -name dram_clk -source \
    [get_pins {ic|core_pll|core_pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    [get_ports {dram_clk}]
set_input_delay -max -clock dram_clk 7.0 [get_ports {dram_dq[*]}]
set_input_delay -min -clock dram_clk 2.5 [get_ports {dram_dq[*]}]
set SDRAM_OUT [get_ports {dram_a[*] dram_ba[*] dram_cke dram_dqm[*] dram_dq[*] dram_ras_n dram_cas_n dram_we_n}]
set_output_delay -max -clock dram_clk  1.5 $SDRAM_OUT
set_output_delay -min -clock dram_clk -0.8 $SDRAM_OUT
set_multicycle_path -setup 2 -from [get_clocks {dram_clk}] -to [get_registers {*|sdram_ctrl:*|dq_in[*]}]
set_multicycle_path -setup 3 -from [get_registers {*|sdram_ctrl:*|last[*]}] -to [get_registers {*|sdram_ctrl:*|*}]
set_multicycle_path -hold  2 -from [get_registers {*|sdram_ctrl:*|last[*]}] -to [get_registers {*|sdram_ctrl:*|*}]

# The pixel hand-over to the 8 MHz video clock: the colour and sync
# registers are launched two system clocks before the clk_vid edge that
# samples them (core_top.sv, clk_enables.sv), so the setup check starts
# from that launch edge; the toggle the other way (vt -> vt_s) is a plain
# flop-to-flop path checked at the 5.2 ns edge relationship as it stands.
set VID_OUT [get_registers {ic|vr_q[*] ic|vg_q[*] ic|vb_q[*] ic|vhs_q ic|vvs_q ic|vde_q}]
set_multicycle_path -setup 3 -start -from [get_clocks {ic|core_pll|core_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -to $VID_OUT
set_multicycle_path -hold  2 -start -from [get_clocks {ic|core_pll|core_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -to $VID_OUT

# PSRAM: an asynchronous interface driven by a state machine that holds every
# pin for whole system cycles with tens of nanoseconds of margin
# (target/pocket/psram.sv), so the pins are not timed against a clock.
set_false_path -to   [get_ports {cram0_* cram1_*}]
set_false_path -from [get_ports {cram0_dq[*] cram1_dq[*] cram0_wait cram1_wait}]

# TG68K: the kernel steps on a clock enable, at most one step every 4 cycles
set_multicycle_path -setup 4 -from [get_registers {*|TG68KdotC_Kernel:*|*}] -to [get_registers {*|TG68KdotC_Kernel:*|*}]
set_multicycle_path -hold  3 -from [get_registers {*|TG68KdotC_Kernel:*|*}] -to [get_registers {*|TG68KdotC_Kernel:*|*}]

# SRAM: the same treatment -- registered pins held for whole cycles, a read
# sampled three cycles after the address (target/pocket/gaia_mem.sv sram_port)
set_false_path -to   [get_ports {sram_*}]
set_false_path -from [get_ports {sram_dq[*]}]

# The scan-out pipeline -- the line-buffer reads, the K055555 priority
# encoder, the palette read and the RGB stage -- re-evaluates once per 8 MHz
# pixel, twelve clocks apart, and its registers latch only at fixed phases
# inside the pixel (k055555_mixer.sv: the address at phase 5, the colour at
# 9), so a path really has those clocks. Registers that clock every cycle
# must never be given a multicycle on that reasoning alone: the first
# Pocket build did and showed noise.
set MIX [get_registers {*|k055555_mixer:*|*}]
set_multicycle_path -setup 4 -to $MIX
set_multicycle_path -hold  3 -to $MIX
set PAL [get_registers {*|gaia_main:*|pal_rd_q*}]
set_multicycle_path -setup 4 -to $PAL
set_multicycle_path -hold  3 -to $PAL

# TG68K to the board: the kernel's address, data and bus-state outputs settle
# after a clkena step and are sampled only after gaia_main's three-clock gap
# (step_gap), so the decode and the block-RAM write ports have three cycles
# (keepers, not registers: the kernel's register file and the board's RAMs
# are M10K cells, which get_registers does not match)
set_multicycle_path -setup 3 -from [get_keepers {*|TG68KdotC_Kernel:*|*}] -to [get_keepers {*|gaia_main:*|*}]
set_multicycle_path -hold  2 -from [get_keepers {*|TG68KdotC_Kernel:*|*}] -to [get_keepers {*|gaia_main:*|*}]

# The Z80 (tv80) steps on cen_8m, one clock in twelve: its registers, and
# the sound board's registers and RAM ports it drives, change only at those
# steps, and what the board hands back (data, wait) is sampled only there
set Z80 [get_keepers {*|tv80s_cen:*|*}]
set SND [get_keepers {*|gaia_sound:*|*}]
set_multicycle_path -setup 4 -from $Z80 -to $SND
set_multicycle_path -hold  3 -from $Z80 -to $SND
set_multicycle_path -setup 4 -from $SND -to $Z80
set_multicycle_path -hold  3 -from $SND -to $Z80
