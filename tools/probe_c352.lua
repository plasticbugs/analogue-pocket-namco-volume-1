-- Log every H8 write to the C352 (and its reads) with the H8 cycle count,
-- using debugger watchpoints (Lua taps on the H8 space crash MAME). Run with
-- -debug -debugger none -log; output lands in error.log as lines
--   C352W <frame> <beamy> <beamx> <addr> <data>
-- Pair it with -wavwrite to capture the audio the same run produced.
local dbg = manager.machine.debugger
dbg:command("wpset a00000:mcu,8000,w,,{logerror \"C352W %d %d %d %06X %04X\\n\",frame,beamy,beamx,wpaddr,wpdata; g}")
dbg:command("wpset a00000:mcu,8000,r,,{logerror \"C352R %d %d %d %06X %04X\\n\",frame,beamy,beamx,wpaddr,wpdata; g}")
dbg:command("go")
local frames = 0
local stopf = tonumber(os.getenv("NCV1_STOP") or "3000")
local presses = {}
for p in string.gmatch(os.getenv("NCV1_INPUTS") or "", "[^,]+") do
  local f, name, len = string.match(p, "^(%d+):([^:]+):(%d+)$")
  if f then table.insert(presses, {f = tonumber(f), name = name, len = tonumber(len)}) end
end
local fields = {}
for _, pname in ipairs({":P1_P2", ":DSW"}) do
  for n, f in pairs(manager.machine.ioport.ports[pname].fields) do fields[n] = f end
end
emu.register_frame_done(function()
  frames = frames + 1
  for _, p in ipairs(presses) do
    if frames == p.f then fields[p.name]:set_value(0) end
    if frames == p.f + p.len then fields[p.name]:set_value(1) end
  end
  if frames >= stopf then manager.machine:exit() end
end)
