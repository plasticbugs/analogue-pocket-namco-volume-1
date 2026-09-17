-- Dump YGV608 state (+ PNG snapshot) from MAME at chosen frames, driving the
-- game with a scripted input sequence.
--
--   mame ncv1 -autoboot_script tools/dump_state.lua ... with environment:
--     NCV1_OUT      output directory (default artifacts/states)
--     NCV1_TAG      name prefix for the dumps
--     NCV1_FRAMES   comma-separated frame numbers to dump
--     NCV1_INPUTS   comma-separated "frame:field:frames" presses, e.g.
--                   "400:Coin 1:8,500:1 Player Start:8,700:P1 Button 1:8"
--     NCV1_STOP     frame to exit at
--
-- State file format (text): one "name value" per line for scalars, then
-- "name[i] value" for arrays, hex. Read by tools/render_model.py.
local out   = os.getenv("NCV1_OUT") or "artifacts/states"
local tag   = os.getenv("NCV1_TAG") or "state"
local stopf = tonumber(os.getenv("NCV1_STOP") or "3000")
local frames_wanted = {}
for f in string.gmatch(os.getenv("NCV1_FRAMES") or "", "[^,]+") do frames_wanted[tonumber(f)] = true end
local presses = {}
for p in string.gmatch(os.getenv("NCV1_INPUTS") or "", "[^,]+") do
  local f, name, len = string.match(p, "^(%d+):([^:]+):(%d+)$")
  if f then table.insert(presses, {f = tonumber(f), name = name, len = tonumber(len)}) end
end

local machine = manager.machine
local ygv = machine.devices[":ygv608"]
local cpu = machine.devices[":maincpu"]
local sp  = cpu.spaces["program"]
local ioport = machine.ioport
local fields = {}
for _, pname in ipairs({":P1_P2", ":DSW"}) do
  for n, f in pairs(ioport.ports[pname].fields) do fields[n] = f end
end

local scalars = {
  "m_md","m_page_x","m_page_y","m_page_size","m_pattern_size","m_bits16","m_pny_shift","m_na8_mask",
  "m_base_y_shift","m_h_div_size","m_v_div_size","m_col_shift","m_flip","m_zron","m_dspe","m_dckm",
  "m_h_display_size","m_v_display_size","m_roz_wrap_disable","m_scroll_wrap_disable",
  "m_planeA_trans_enable","m_planeB_trans_enable","m_priority_mode","m_cbdr","m_yse","m_scm",
  "m_planeA_color_fetch","m_planeB_color_fetch","m_sprite_color_fetch",
  "m_mosaic_aplane","m_mosaic_bplane","m_sprite_disable","m_sprite_aux_mode","m_sprite_aux_reg",
  "m_border_color","m_sprite_bank","m_namcond1_gfxbank","m_vblank_irq_mask","m_raster_irq_mask",
  "m_raster_irq_hpos","m_raster_irq_vpos","m_raster_irq_mode",
  "m_ax","m_ay","m_dx","m_dy","m_dxy","m_dyx","m_raw_ax","m_raw_ay","m_raw_dx","m_raw_dy","m_raw_dxy","m_raw_dyx",
  "m_crtc.htotal","m_crtc.vtotal","m_crtc.display_hstart","m_crtc.display_vstart","m_crtc.display_width",
  "m_crtc.display_height","m_crtc.display_hsync","m_crtc.display_vsync","m_crtc.border_width","m_crtc.border_height",
  "m_screen_status","m_ba_plane_scroll_select","m_plane_select_access","m_xtile_ptr","m_ytile_ptr",
}
local arrays = { "m_pattern_name_table", "m_sprite_attribute_table.b", "m_scroll_data_table", "m_colour_palette", "m_base_addr" }

local function rd(name, idx)
  local it = emu.item(ygv.items["0/" .. name])
  return it:read(idx or 0)
end

local function dump(frame)
  local path = string.format("%s/%s_%05d.txt", out, tag, frame)
  local f = io.open(path, "w")
  f:write(string.format("frame %d\n", frame))
  for _, n in ipairs(scalars) do f:write(string.format("%s %x\n", n, rd(n))) end
  for _, n in ipairs(arrays) do
    local it = emu.item(ygv.items["0/" .. n])
    f:write(string.format("%s[] %d %d\n", n, it.count, it.size))
    local line = {}
    for i = 0, it.count - 1 do
      line[#line + 1] = string.format("%x", it:read(i))
      if #line == 64 then f:write(table.concat(line, " "), "\n"); line = {} end
    end
    if #line > 0 then f:write(table.concat(line, " "), "\n") end
  end
  f:close()
  machine.video:snapshot()
  print("dumped", path)
end

local frames = 0
emu.register_frame_done(function()
  frames = frames + 1
  for _, p in ipairs(presses) do
    if frames == p.f then fields[p.name]:set_value(0) end
    if frames == p.f + p.len then fields[p.name]:set_value(1) end
  end
  if frames_wanted[frames] then dump(frames) end
  if frames >= stopf then machine:exit() end
end)
