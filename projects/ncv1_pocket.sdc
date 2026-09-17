# ==============================================================================
# Namco ND-1 on the Pocket: timing constraints beyond the BSP's sys_constr.sdc.
# The 96 MHz system clock, its 6.4 MHz video pair and the shifted SDRAM clock
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
# Runner core's proven arrangement, same controller). This core uses 5.99 ns
# (four VCO steps of 130 ps earlier than Gaiapolis's 6.51): its first fit missed
# the data inputs by 0.27 ns with 3 ns spare on the outputs, and 6.12 ns left
# them only 0.11 ns. Gaiapolis's history: 6.51 ns
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

# The pixel hand-over to the 6.4 MHz video clock. clk_vid is clk_sys / 15 with
# its edges half a system period after a clk_sys edge. core_top's pix_sync
# reloads the pixel divider two clocks after each clk_vid edge is seen, so
# cen_pix is high in the fifth system cycle after the edge and the VDP's
# colour and sync registers (rtl/ygv608.sv output stage, the only logic ahead
# of the overlay mux) change at the sixth system edge, 9.5 system periods
# before the next clk_vid edge. The launch is therefore 9 system edges before
# the default one; 8 is taken, keeping a clock of margin.
set CLK_SYS [get_clocks {ic|core_pll|core_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
set VID_OUT [get_registers {ic|vr_q[*] ic|vg_q[*] ic|vb_q[*] ic|vhs_q ic|vvs_q ic|vde_q}]
set_multicycle_path -setup 8 -start -from $CLK_SYS -to $VID_OUT
set_multicycle_path -hold  7 -start -from $CLK_SYS -to $VID_OUT

# PSRAM and SRAM are not used; their pins are constants.
set_false_path -to   [get_ports {cram0_* cram1_* sram_*}]
set_false_path -from [get_ports {cram0_dq[*] cram1_dq[*] cram0_wait cram1_wait sram_dq[*]}]

# H8/300H core (rtl/h8300h.sv, h8300h_core): every register it holds is written
# only on cen_h8, which rtl/clk_enables.sv makes with a 64/375 accumulator, so
# consecutive enables are 5 or 6 system clocks apart. Its inputs from the
# per-clock side are sampled on the enable and used from the next one. The
# divider results it reads (h8300h div_q/div_rem) settle 34 clocks after a
# start and are read at least a dozen H8 states later.
set H8CORE [get_registers {*|h8300h_core:*|*}]
set_multicycle_path -setup 5 -from $H8CORE -to $H8CORE
set_multicycle_path -hold  4 -from $H8CORE -to $H8CORE
set H8DIV [get_registers {*|h8300h:*|div_q[*] *|h8300h:*|div_rem[*]}]
# the on-chip peripherals into the core: the core samples them on its enable
set H8PERIPH [get_registers {*|h83002:*|*}]
set_multicycle_path -setup 5 -from $H8PERIPH -to $H8CORE
set_multicycle_path -hold  4 -from $H8PERIPH -to $H8CORE
set_multicycle_path -setup 5 -from $H8DIV -to $H8CORE
set_multicycle_path -hold  4 -from $H8DIV -to $H8CORE

# fx68k: both phases advance only on cen_phi1/cen_phi2, which rtl/clk_enables.sv
# makes with a 32/125 accumulator, so successive phase pulses are 3 or 4 system
# clocks apart. Registers only (the microcode ROM reads stay single-cycle), as
# the Xenophobe core does at 2 cycles.
set FX [get_registers {*|fx68k:*|*}]
set_multicycle_path -setup 3 -from $FX -to $FX
set_multicycle_path -hold  2 -from $FX -to $FX
