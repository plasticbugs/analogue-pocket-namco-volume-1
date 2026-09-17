-- H8/3002 trace-replay capture for the CPU bench (sim/run_h8.sh).
-- At frame NCV1_T0: dump the H8 registers, its internal RAM and the shared
-- RAM, then trace every instruction with its registers for NCV1_FRAMES
-- frames, logging every non-ROM read/write (address, data) in order so the
-- bench can replay reads and check writes without modelling the 68000.
-- Run with -debug -debugger none -log. Outputs (in NCV1_OUT):
--   h8_regs.txt, h8_iram.txt, shared.txt, h8trace.log, and error.log lines
--   "H8R cycles addr data" / "H8W cycles addr data".
local out = os.getenv("NCV1_OUT") or "artifacts/h8"
local t0  = tonumber(os.getenv("NCV1_T0") or "120")
local nfr = tonumber(os.getenv("NCV1_FRAMES") or "2")
local machine = manager.machine
local dbg = machine.debugger
local mcu = machine.devices[":mcu"]
local msp = mcu.spaces["program"]
local frames = 0
local presses = {}
for p in string.gmatch(os.getenv("NCV1_INPUTS") or "", "[^,]+") do
  local f, name, len = string.match(p, "^(%d+):([^:]+):(%d+)$")
  if f then table.insert(presses, {f = tonumber(f), name = name, len = tonumber(len)}) end
end
local fields = {}
for _, pname in ipairs({":P1_P2", ":DSW"}) do
  for n, f in pairs(machine.ioport.ports[pname].fields) do fields[n] = f end
end
local function dump_range(path, base, len, width)
  local f = io.open(path, "w")
  for a = 0, len - 1, width do
    if width == 2 then f:write(string.format("%04x\n", msp:read_u16(base + a)))
    else f:write(string.format("%02x\n", msp:read_u8(base + a))) end
  end
  f:close()
end
dbg:command("go")
emu.register_frame_done(function()
  frames = frames + 1
  for _, p in ipairs(presses) do
    if frames == p.f then fields[p.name]:set_value(0) end
    if frames == p.f + p.len then fields[p.name]:set_value(1) end
  end
  if frames == t0 then
    local f = io.open(out .. "/h8_regs.txt", "w")
    for _, r in ipairs({"PC","CCR","ER0","ER1","ER2","ER3","ER4","ER5","ER6","ER7"}) do
      f:write(string.format("%s %x\n", r, mcu.state[r].value))
    end
    f:close()
    dump_range(out .. "/h8_iram.txt", 0xfffd10, 0x200, 2)
    dump_range(out .. "/shared.txt", 0x200000, 0x10000, 2)
    dump_range(out .. "/h8_io.txt", 0xffff20, 0xe0, 1)
    dbg:command("wpset 200000:mcu,10000,r,,{logerror \"H8R %d %06X %04X\\n\",cycles,wpaddr,wpdata; g}")
    dbg:command("wpset 200000:mcu,10000,w,,{logerror \"H8W %d %06X %04X\\n\",cycles,wpaddr,wpdata; g}")
    dbg:command("wpset a00000:mcu,8000,r,,{logerror \"H8R %d %06X %04X\\n\",cycles,wpaddr,wpdata; g}")
    dbg:command("wpset a00000:mcu,8000,w,,{logerror \"H8W %d %06X %04X\\n\",cycles,wpaddr,wpdata; g}")
    dbg:command("wpset c00000:mcu,100,r,,{logerror \"H8R %d %06X %04X\\n\",cycles,wpaddr,wpdata; g}")
    dbg:command("wpset c00000:mcu,100,w,,{logerror \"H8W %d %06X %04X\\n\",cycles,wpaddr,wpdata; g}")
    dbg:command("wpset fffd10:mcu,2f0,r,,{logerror \"H8R %d %06X %04X\\n\",cycles,wpaddr,wpdata; g}")
    dbg:command("wpset fffd10:mcu,2f0,w,,{logerror \"H8W %d %06X %04X\\n\",cycles,wpaddr,wpdata; g}")
    dbg:command("trace " .. out .. "/h8trace.log,mcu,noloop,{tracelog \"%d %06X %02X %08X %08X %08X %08X %08X %08X %08X %08X | \",cycles,pc,ccr,er0,er1,er2,er3,er4,er5,er6,er7}")
    dbg:command("go")
  end
  if frames == t0 + nfr then
    dbg:command("trace off,mcu")
    dbg:command("wpclear")
    machine:exit()
  end
end)
