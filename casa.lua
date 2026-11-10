-- Casa - Smart Home fuer ComputerCraft 1.5 (Tekkit Lite, Minecraft 1.4.7)
-- Eine Datei fuer alle Rollen: Zentrale, Station, Panel.
-- Start: "casa"   Neu einrichten: "casa setup"

local VERSION = "1.0"
local DIR = "/casa_data"
local DUSK, DAWN = 18.54, 5.47
local unpack = unpack or table.unpack
local args = { ... }
local cfg = nil

------------------------------------------------------------------
-- Helfer
------------------------------------------------------------------
local function hasBit(mask, c) return math.floor(mask / c) % 2 == 1 end
local function clock() return os.clock() end
local function isNight(t) return t >= DUSK or t < DAWN end
local function mod24(x) return x - math.floor(x / 24) * 24 end
local function fmtTime(t)
  local h = math.floor(t)
  local m = math.floor((t - h) * 60)
  return string.format("%d:%02d", h, m)
end
local function trim(s)
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  return s
end
local function cut(s, w)
  if w < 0 then w = 0 end
  if #s > w then return string.sub(s, 1, w) end
  return s
end
local function wrapText(s, w, maxLines)
  local lines = {}
  local rest = s
  if w < 1 then w = 1 end
  while #rest > 0 and #lines < maxLines do
    if #rest <= w then
      lines[#lines + 1] = rest
      rest = ""
    else
      local at = nil
      for i = w + 1, 2, -1 do
        if string.sub(rest, i, i) == " " then at = i break end
      end
      if at then
        lines[#lines + 1] = string.sub(rest, 1, at - 1)
        rest = string.sub(rest, at + 1)
      else
        lines[#lines + 1] = string.sub(rest, 1, w)
        rest = string.sub(rest, w + 1)
      end
    end
  end
  return lines
end

------------------------------------------------------------------
-- Codec: eigenes, sicheres Format (kein loadstring auf Funkdaten)
------------------------------------------------------------------
local codec = {}
local function keyLess(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta == "number" end
  return a < b
end
local function encVal(v, out)
  local tv = type(v)
  if tv == "number" then
    if v == math.floor(v) and v > -1e15 and v < 1e15 then
      out[#out + 1] = "n" .. string.format("%d", v) .. ";"
    else
      out[#out + 1] = "n" .. tostring(v) .. ";"
    end
  elseif tv == "string" then
    out[#out + 1] = "s" .. string.format("%d", #v) .. ":" .. v
  elseif tv == "boolean" then
    out[#out + 1] = v and "t" or "f"
  elseif tv == "table" then
    local keys = {}
    for k in pairs(v) do
      local tk = type(k)
      if tk == "number" or tk == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys, keyLess)
    out[#out + 1] = "{"
    for i = 1, #keys do
      local x = v[keys[i]]
      local tx = type(x)
      if tx == "number" or tx == "string" or tx == "boolean" or tx == "table" then
        encVal(keys[i], out)
        encVal(x, out)
      end
    end
    out[#out + 1] = "}"
  end
end
function codec.encode(v)
  local out = {}
  encVal(v, out)
  return table.concat(out)
end
local function decVal(s, i, depth)
  if depth > 24 then error("depth") end
  local c = string.sub(s, i, i)
  if c == "n" then
    local j = string.find(s, ";", i, true)
    if not j then error("num") end
    local n = tonumber(string.sub(s, i + 1, j - 1))
    if not n then error("num") end
    return n, j + 1
  elseif c == "s" then
    local j = string.find(s, ":", i, true)
    if not j then error("str") end
    local len = tonumber(string.sub(s, i + 1, j - 1))
    if not len or len < 0 or len ~= math.floor(len) or j + len > #s then error("str") end
    return string.sub(s, j + 1, j + len), j + len + 1
  elseif c == "t" then
    return true, i + 1
  elseif c == "f" then
    return false, i + 1
  elseif c == "{" then
    local t = {}
    local p = i + 1
    while true do
      local c2 = string.sub(s, p, p)
      if c2 == "}" then return t, p + 1 end
      if c2 == "" then error("eof") end
      local k, v
      k, p = decVal(s, p, depth + 1)
      v, p = decVal(s, p, depth + 1)
      if type(k) ~= "number" and type(k) ~= "string" then error("key") end
      t[k] = v
    end
  end
  error("bad")
end
function codec.decode(s)
  if type(s) ~= "string" then return nil end
  local ok, v = pcall(decVal, s, 1, 0)
  if ok then return v end
  return nil
end

local function hash(str)
  local h = 5381
  for i = 1, #str do
    h = (h * 33 + string.byte(str, i) + math.floor(h / 65536)) % 4294967296
  end
  return h
end
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n, width)
  local s = ""
  for _ = 1, width do
    local d = n % 36
    s = string.sub(B36, d + 1, d + 1) .. s
    n = math.floor(n / 36)
  end
  return s
end

------------------------------------------------------------------
-- Speicher (mit Sicherungskopie)
------------------------------------------------------------------
local store = {}
local function readFile(p)
  if not fs.exists(p) then return nil end
  local f = fs.open(p, "r")
  if not f then return nil end
  local s = f.readAll()
  f.close()
  return s
end
function store.load(name)
  local p = DIR .. "/" .. name
  local v = codec.decode(readFile(p))
  if v == nil then v = codec.decode(readFile(p .. ".bak")) end
  return v
end
function store.save(name, value)
  local p = DIR .. "/" .. name
  local ok = pcall(function()
    if not fs.exists(DIR) then fs.makeDir(DIR) end
    local f = fs.open(p .. ".tmp", "w")
    f.write(codec.encode(value))
    f.close()
    if fs.exists(p) then
      if fs.exists(p .. ".bak") then fs.delete(p .. ".bak") end
      fs.move(p, p .. ".bak")
    end
    fs.move(p .. ".tmp", p)
  end)
  return ok
end

------------------------------------------------------------------
-- Funk: ein Kanal, signierte Pakete, optionales Weiterleiten
------------------------------------------------------------------
local net = { modem = nil, side = nil, seq = 0, last = {}, legacy = false }
local function stamp()
  local d = 0
  if os.day then d = os.day() end
  return d * 24 + os.time()
end
function net.init()
  net.seq = math.floor(stamp() * 1000)
  net.open()
end
function net.open()
  if net.side and peripheral.getType(net.side) ~= "modem" then
    net.side = nil
    net.modem = nil
  end
  if net.modem then return true end
  for _, s in ipairs(rs.getSides()) do
    if peripheral.getType(s) == "modem" then
      net.side = s
      net.modem = peripheral.wrap(s)
      if net.modem and net.modem.open then
        net.legacy = false
        pcall(net.modem.open, cfg.channel)
      else
        net.legacy = true
        pcall(rednet.open, s)
      end
      return true
    end
  end
  return false
end
function net.reopen()
  if net.modem and net.modem.closeAll then pcall(net.modem.closeAll) end
  net.modem = nil
  net.side = nil
  net.open()
end
function net.raw(msg)
  if not net.modem then return false end
  if net.legacy then
    return pcall(rednet.broadcast, msg)
  end
  return pcall(net.modem.transmit, cfg.channel, cfg.channel, msg)
end
local function sign(body)
  return b36(hash(cfg.key .. body .. cfg.key), 7)
end
function net.send(to, kind, data)
  if not net.modem then return false end
  net.seq = net.seq + 1
  local body = codec.encode({ f = cfg.id, t = to, k = kind, d = data, q = net.seq, ts = stamp() })
  return net.raw(string.format("%d", cfg.hops or 3) .. sign(body) .. body)
end
function net.receive(msg)
  if type(msg) ~= "string" or #msg < 9 then return nil end
  local ttl = tonumber(string.sub(msg, 1, 1))
  if not ttl then return nil end
  local sig = string.sub(msg, 2, 8)
  local body = string.sub(msg, 9)
  if sign(body) ~= sig then return nil end
  local p = codec.decode(body)
  if type(p) ~= "table" or type(p.f) ~= "string" or type(p.q) ~= "number"
    or type(p.k) ~= "string" or type(p.t) ~= "string" or type(p.ts) ~= "number" then
    return nil
  end
  if p.f == cfg.id then return nil end
  local dt = mod24(math.abs(stamp() - p.ts))
  if dt > 12 then dt = 24 - dt end
  if dt > 0.5 then return nil end
  local now = clock()
  local last = net.last[p.f]
  if last and now - last.at < 30 and p.q <= last.q then return nil end
  net.last[p.f] = { q = p.q, at = now }
  if cfg.relay and ttl > 0 and p.t ~= cfg.id then
    net.raw(string.format("%d", ttl - 1) .. sig .. body)
  end
  if p.t == "*" or p.t == cfg.id then return p end
  return nil
end
function net.fromEvent(ev)
  if ev[1] == "modem_message" then return net.receive(ev[5]) end
  if ev[1] == "rednet_message" then return net.receive(ev[3]) end
  return nil
end

------------------------------------------------------------------
-- Redstone-Hardware (lokale Seiten)
------------------------------------------------------------------
local hw = { applied = {} }
local SIDES = { top = true, bottom = true, left = true, right = true, front = true, back = true }
function hw.sides()
  local list = {}
  for _, s in ipairs(rs.getSides()) do
    if not peripheral.isPresent(s) then list[#list + 1] = s end
  end
  return list
end
function hw.clean(o)
  local out = {}
  if type(o) ~= "table" then return out end
  for side, v in pairs(o) do
    if SIDES[side] and type(v) == "table" then
      local m = tonumber(v.m) or 0
      m = math.floor(m) % 65536
      out[side] = { m = m, r = v.r == true }
    end
  end
  return out
end
function hw.apply(outs)
  for _, side in ipairs(hw.sides()) do
    local want = outs[side]
    local m, r = 0, false
    if want then m = want.m r = want.r end
    local cur = hw.applied[side]
    if not cur then
      cur = {}
      hw.applied[side] = cur
    end
    if cur.m ~= m then
      pcall(rs.setBundledOutput, side, m)
      cur.m = m
    end
    if cur.r ~= r then
      pcall(rs.setOutput, side, r)
      cur.r = r
    end
  end
end
function hw.read()
  local inp = {}
  for _, side in ipairs(hw.sides()) do
    local okM, m = pcall(rs.getBundledInput, side)
    local okR, r = pcall(rs.getInput, side)
    if not okM or type(m) ~= "number" then m = 0 end
    if not okR then r = false end
    local cur = hw.applied[side]
    if cur then
      -- eigene Ausgaenge nicht als Eingang lesen
      if cur.m and cur.m > 0 then
        local res, c = 0, 1
        for _ = 1, 16 do
          if hasBit(m, c) and not hasBit(cur.m, c) then res = res + c end
          c = c * 2
        end
        m = res
      end
      if cur.r then r = false end
    end
    inp[side] = { m = m, r = r == true }
  end
  return inp
end
function hw.same(a, b)
  for side, v in pairs(a) do
    local w = b[side]
    if not w or w.m ~= v.m or w.r ~= v.r then return false end
  end
  for side in pairs(b) do
    if not a[side] then return false end
  end
  return true
end

------------------------------------------------------------------
-- Bildschirm-Puffer: zeichnet nur geaenderte Zeilen (kein Flackern)
------------------------------------------------------------------
local LIGHT = {}
LIGHT[colors.white] = true
LIGHT[colors.yellow] = true
LIGHT[colors.lime] = true
LIGHT[colors.orange] = true

local function newScreen(t)
  local scr = { w = 0, h = 0, cur = {}, old = {} }
  local color = t.isColor and t.isColor()
  function scr.begin()
    local w, h = t.getSize()
    if w ~= scr.w or h ~= scr.h then
      scr.w, scr.h = w, h
      scr.old = {}
      t.setBackgroundColor(colors.black)
      t.clear()
    end
    scr.cur = {}
    for y = 1, h do scr.cur[y] = {} end
  end
  function scr.put(x, y, str, fg, bg)
    if y < 1 or y > scr.h then return end
    if x < 1 then
      str = string.sub(str, 2 - x)
      x = 1
    end
    if x + #str - 1 > scr.w then str = string.sub(str, 1, scr.w - x + 1) end
    if #str == 0 then return end
    if not color then
      bg = LIGHT[bg] and colors.white or colors.black
      fg = (bg == colors.white) and colors.black or colors.white
    end
    local row = scr.cur[y]
    row[#row + 1] = x
    row[#row + 1] = str
    row[#row + 1] = fg
    row[#row + 1] = bg
  end
  function scr.flush()
    for y = 1, scr.h do
      local row = scr.cur[y]
      local sig = table.concat(row, "\1")
      if sig ~= scr.old[y] then
        scr.old[y] = sig
        t.setBackgroundColor(colors.black)
        t.setCursorPos(1, y)
        t.clearLine()
        for i = 1, #row, 4 do
          t.setCursorPos(row[i], y)
          t.setTextColor(row[i + 2])
          t.setBackgroundColor(row[i + 3])
          t.write(row[i + 1])
        end
      end
    end
  end
  return scr
end

------------------------------------------------------------------
-- Panel: Touch-Oberflaeche (Monitor oder Advanced-Computer)
------------------------------------------------------------------
local function newPanel(t, getView, sendCmd, onlyRoom)
  local P = { tab = 1, page = 1, first = 1, hits = {}, pend = {}, scr = newScreen(t) }

  local function hit(x1, y1, x2, y2, fn)
    P.hits[#P.hits + 1] = { x1, y1, x2, y2, fn }
  end

  function P.touch(x, y)
    for i = #P.hits, 1, -1 do
      local h = P.hits[i]
      if x >= h[1] and x <= h[3] and y >= h[2] and y <= h[4] then
        h[5]()
        return true
      end
    end
    return false
  end

  local function tile(x, y, tw, th, name, fg, bg)
    local scr = P.scr
    local blank = string.rep(" ", tw)
    for i = 0, th - 1 do scr.put(x, y + i, blank, fg, bg) end
    local inner = tw - 2
    if tw < 9 then inner = tw end
    local lines = wrapText(name, inner, th)
    local sy = y + math.floor((th - #lines) / 2)
    for i = 1, #lines do
      scr.put(x + math.floor((tw - #lines[i]) / 2), sy + i - 1, lines[i], fg, bg)
    end
  end

  function P.render()
    local scr = P.scr
    scr.begin()
    P.hits = {}
    local W, H = scr.w, scr.h
    local view = getView()
    local now = os.time()
    local night = isNight(now)
    local clk = " " .. fmtTime(now) .. " "

    if not view then
      scr.put(1, 1, string.rep(" ", W), colors.white, colors.red)
      scr.put(2, 1, "Casa", colors.white, colors.red)
      local lines = wrapText("Keine Verbindung zur Zentrale", W - 2, H - 2)
      for i = 1, #lines do scr.put(2, 2 + i, lines[i], colors.white, colors.black) end
      scr.flush()
      return
    end

    -- Reiter
    local tabs = {}
    for _, r in ipairs(view.rooms) do
      if not onlyRoom or onlyRoom == "" or onlyRoom == r then
        tabs[#tabs + 1] = { name = r, room = r }
      end
    end
    tabs[#tabs + 1] = { name = "Szenen", scenes = true }
    if P.tab > #tabs then P.tab = #tabs end
    if P.tab < 1 then P.tab = 1 end
    local showTabs = H >= 8 and #tabs > 1
    local function nextTab()
      P.tab = P.tab + 1
      if P.tab > #tabs then P.tab = 1 end
      P.page = 1
    end
    local function prevTab()
      P.tab = P.tab - 1
      if P.tab < 1 then P.tab = #tabs end
      P.page = 1
    end

    -- Kopfzeile
    local title = view.name
    if not showTabs and #tabs > 1 then title = tabs[P.tab].name end
    scr.put(1, 1, string.rep(" ", W), colors.white, colors.blue)
    local room = W - 1
    if W - #title - 2 >= #clk or W < 10 then
      scr.put(W - #clk + 1, 1, clk, night and colors.white or colors.black,
        night and colors.gray or colors.yellow)
      room = W - #clk - 1
    end
    if W >= 10 then scr.put(2, 1, cut(title, room), colors.white, colors.blue) end
    if not showTabs and #tabs > 1 then hit(1, 1, W, 1, nextTab) end

    -- Reiterzeile
    if showTabs then
      scr.put(1, 2, string.rep(" ", W), colors.white, colors.gray)
      if P.first > P.tab then P.first = P.tab end
      if P.first < 1 then P.first = 1 end
      while true do
        local x = (P.first > 1) and 2 or 1
        for i = P.first, P.tab do x = x + #tabs[i].name + 2 end
        if x - 1 <= W - 1 or P.first >= P.tab then break end
        P.first = P.first + 1
      end
      local x = (P.first > 1) and 2 or 1
      local clipped = false
      for i = P.first, #tabs do
        local label = " " .. tabs[i].name .. " "
        if x + #label - 1 > W then clipped = true end
        if x > W then break end
        local idx = i
        if i == P.tab then
          scr.put(x, 2, label, colors.black, colors.white)
        else
          scr.put(x, 2, label, colors.lightGray, colors.gray)
        end
        hit(x, 2, x + #label - 1, 2, function() P.tab = idx P.page = 1 end)
        x = x + #label
      end
      if P.first > 1 then
        scr.put(1, 2, "<", colors.yellow, colors.gray)
        hit(1, 2, 1, 2, prevTab)
      end
      if clipped then
        scr.put(W, 2, ">", colors.yellow, colors.gray)
        hit(W, 2, W, 2, nextTab)
      end
    end

    -- Inhalt sammeln
    local tab = tabs[P.tab]
    local items = {}
    if tab.scenes then
      for _, s in ipairs(view.scn) do items[#items + 1] = { kind = "scn", o = s } end
      items[#items + 1] = { kind = "off" }
    else
      for _, d in ipairs(view.dev) do
        if d.r == tab.room then items[#items + 1] = { kind = "dev", o = d } end
      end
      for _, s in ipairs(view.sen) do
        if s.r == tab.room then items[#items + 1] = { kind = "sen", o = s } end
      end
    end

    local y0 = showTabs and 3 or 2
    if H >= 12 then y0 = y0 + 1 end
    local areaH = H - y0 + 1
    local minTw = (W >= 21) and 10 or 7
    local cols = math.floor((W + 1) / (minTw + 1))
    if cols < 1 then cols = 1 end
    local tw = math.floor((W - (cols - 1)) / cols)
    local x0 = 1 + math.floor((W - (cols * tw + cols - 1)) / 2)
    local th, gapY, rows, per, pages
    for pass = 1, 2 do
      th = (areaH >= 7) and 3 or 1
      gapY = (th == 3) and 1 or 0
      rows = math.floor((areaH + gapY) / (th + gapY))
      if rows < 1 then rows = 1 end
      per = cols * rows
      pages = math.ceil(#items / per)
      if pages < 1 then pages = 1 end
      if pass == 1 and pages > 1 then areaH = areaH - 1 else break end
    end
    if P.page > pages then P.page = pages end
    if P.page < 1 then P.page = 1 end

    if #view.dev == 0 and #view.sen == 0 and not tab.scenes then
      local lines = wrapText("Noch nichts eingerichtet. Bitte am Computer der Zentrale Schalter anlegen.", W - 2, areaH)
      for i = 1, #lines do scr.put(2, y0 + i - 1, lines[i], colors.lightGray, colors.black) end
    end

    local tnow = clock()
    for k = 1, per do
      local it = items[(P.page - 1) * per + k]
      if not it then break end
      local x = x0 + ((k - 1) % cols) * (tw + 1)
      local y = y0 + math.floor((k - 1) / cols) * (th + gapY)
      if it.kind == "dev" then
        local d = it.o
        local on = d.s % 2 == 1
        local flag = math.floor(d.s / 2)
        local p = P.pend[d.i]
        if p then
          if (on == p.on and flag == 0) or tnow > p.t then
            P.pend[d.i] = nil
          else
            on = p.on
            if flag == 0 then flag = 1 end
          end
        end
        local fg, bg = colors.white, colors.gray
        if flag == 2 then fg, bg = colors.white, colors.red
        elseif flag == 1 then fg, bg = colors.black, colors.yellow
        elseif on then fg, bg = colors.black, colors.lime end
        tile(x, y, tw, th, d.n, fg, bg)
        local id, target = d.i, not on
        hit(x, y, x + tw - 1, y + th - 1, function()
          P.pend[id] = { on = target, t = clock() + 3 }
          sendCmd({ op = "set", id = id, on = target })
        end)
      elseif it.kind == "sen" then
        local s = it.o
        if s.v == 1 then
          tile(x, y, tw, th, s.n, colors.black, colors.orange)
        elseif s.v == 0 then
          tile(x, y, tw, th, s.n, colors.gray, colors.lightGray)
        else
          tile(x, y, tw, th, s.n .. " ?", colors.gray, colors.lightGray)
        end
      elseif it.kind == "scn" then
        local s = it.o
        local key = "s" .. tostring(s.i)
        local p = P.pend[key]
        if p and tnow > p.t then
          P.pend[key] = nil
          p = nil
        end
        if p then
          tile(x, y, tw, th, s.n, colors.black, colors.white)
        else
          tile(x, y, tw, th, s.n, colors.black, colors.cyan)
        end
        local id = s.i
        hit(x, y, x + tw - 1, y + th - 1, function()
          P.pend[key] = { t = clock() + 0.6 }
          sendCmd({ op = "scene", id = id })
        end)
      else
        tile(x, y, tw, th, "Alles aus", colors.white, colors.red)
        hit(x, y, x + tw - 1, y + th - 1, function() sendCmd({ op = "alloff" }) end)
      end
    end

    if pages > 1 then
      local third = math.floor(W / 3)
      if third < 1 then third = 1 end
      scr.put(1, H, string.rep(" ", W), colors.white, colors.gray)
      scr.put(1, H, "<", colors.yellow, colors.gray)
      scr.put(W, H, ">", colors.yellow, colors.gray)
      local label = string.format("%d/%d", P.page, pages)
      scr.put(1 + math.floor((W - #label) / 2), H, label, colors.white, colors.gray)
      hit(1, H, third, H, function()
        P.page = P.page - 1
        if P.page < 1 then P.page = pages end
      end)
      hit(W - third + 1, H, W, H, function()
        P.page = P.page + 1
        if P.page > pages then P.page = 1 end
      end)
    end
    scr.flush()
  end

  return P
end

local function setupMonitor(side)
  local mon = peripheral.wrap(side)
  if not mon then return nil end
  local sc = cfg.scale or 0
  if sc > 0 then
    pcall(mon.setTextScale, sc)
  else
    pcall(mon.setTextScale, 1)
    local w = mon.getSize()
    if w < 18 then pcall(mon.setTextScale, 0.5) end
  end
  return mon
end

------------------------------------------------------------------
-- Kern der Zentrale: Zustand, Regeln, Stationen
------------------------------------------------------------------
local core = {
  db = nil, nodes = {}, inputs = {}, sens = {}, offAt = {}, logs = {},
  viewDirty = true, viewQueued = false, dirty = false, lastSave = 0,
  lastView = -100, lastT = nil, depth = 0,
}

function core.log(msg)
  table.insert(core.logs, 1, fmtTime(os.time()) .. " " .. msg)
  while #core.logs > 40 do table.remove(core.logs) end
end
function core.touch()
  core.viewDirty = true
  if not core.viewQueued then
    core.viewQueued = true
    os.queueEvent("casa_view")
  end
end
function core.save()
  store.save("db", core.db)
  core.dirty = false
  core.lastSave = clock()
end
function core.changed()
  core.save()
  core.flush()
  core.touch()
end
function core.newId()
  local id = core.db.nextId
  core.db.nextId = id + 1
  return id
end
local function findById(list, id)
  for i, o in ipairs(list) do
    if o.id == id then return o, i end
  end
  return nil
end
function core.dev(id) return findById(core.db.devices, id) end
function core.sensor(id) return findById(core.db.sensors, id) end
function core.scene(id) return findById(core.db.scenes, id) end

function core.init()
  local db = store.load("db")
  if type(db) ~= "table" then db = {} end
  db.devices = db.devices or {}
  db.sensors = db.sensors or {}
  db.scenes = db.scenes or {}
  db.rules = db.rules or {}
  db.nextId = db.nextId or 1
  core.db = db
  for _, d in ipairs(db.devices) do
    d.on = d.on == true
    if d.on and d.auto and d.auto > 0 then core.offAt[d.id] = clock() + d.auto end
  end
  for _, s in ipairs(db.scenes) do s.set = s.set or {} end
end

function core.rooms()
  local list, seen = {}, {}
  local function add(r)
    if r and not seen[r] then
      seen[r] = true
      list[#list + 1] = r
    end
  end
  for _, d in ipairs(core.db.devices) do add(d.room) end
  for _, s in ipairs(core.db.sensors) do add(s.room) end
  return list
end
function core.nodeIds()
  local list, seen = {}, {}
  local function add(n)
    if n and n ~= "local" and not seen[n] then
      seen[n] = true
      list[#list + 1] = n
    end
  end
  for n in pairs(core.nodes) do add(n) end
  for _, d in ipairs(core.db.devices) do add(d.node) end
  for _, s in ipairs(core.db.sensors) do add(s.node) end
  table.sort(list)
  return list
end
function core.usedBy(node, side, color, exceptId)
  for _, d in ipairs(core.db.devices) do
    if d.id ~= exceptId and d.node == node and d.side == side and d.color == color then return d, "Schalter" end
  end
  for _, s in ipairs(core.db.sensors) do
    if s.id ~= exceptId and s.node == node and s.side == side and s.color == color then return s, "Sensor" end
  end
  return nil
end
function core.isOutput(node, side, color)
  for _, d in ipairs(core.db.devices) do
    if d.node == node and d.side == side and d.color == color then return true end
  end
  return false
end

function core.outsFor(nid)
  local o = {}
  for _, d in ipairs(core.db.devices) do
    if d.node == nid then
      local s = o[d.side]
      if not s then
        s = { m = 0, r = false }
        o[d.side] = s
      end
      local lvl = d.on
      if d.inv then lvl = not lvl end
      if lvl then
        if d.color == 0 then
          s.r = true
        elseif not hasBit(s.m, d.color) then
          s.m = s.m + d.color
        end
      end
    end
  end
  return o
end
function core.flushNode(nid)
  local rec = core.nodes[nid]
  if not rec then return end
  local o = core.outsFor(nid)
  local g = hash(codec.encode(o))
  rec.want = g
  if rec.online and rec.g ~= g then
    local now = clock()
    if rec.sentG ~= g or now - (rec.sentAt or -10) >= 1 then
      net.send(nid, "set", { o = o, g = g })
      rec.sentG = g
      rec.sentAt = now
    end
  end
end
function core.flush()
  hw.apply(core.outsFor("local"))
  for nid in pairs(core.nodes) do core.flushNode(nid) end
end

function core.view()
  local v = { name = cfg.name or "Casa", rooms = core.rooms(), dev = {}, sen = {}, scn = {} }
  for _, d in ipairs(core.db.devices) do
    local flag = 0
    if d.node ~= "local" then
      local rec = core.nodes[d.node]
      if not rec or not rec.online then flag = 2
      elseif rec.g ~= rec.want then flag = 1 end
    end
    v.dev[#v.dev + 1] = { i = d.id, n = d.name, r = d.room, s = (d.on and 1 or 0) + flag * 2 }
  end
  for _, s in ipairs(core.db.sensors) do
    local val = core.sens[s.id]
    local n = 2
    if val == true then n = 1 elseif val == false then n = 0 end
    v.sen[#v.sen + 1] = { i = s.id, n = s.name, r = s.room, v = n }
  end
  for _, s in ipairs(core.db.scenes) do
    v.scn[#v.scn + 1] = { i = s.id, n = s.name }
  end
  return v
end
function core.broadcast()
  core.viewDirty = false
  core.lastView = clock()
  net.send("*", "view", core.view())
end

function core.setDevice(id, on, quiet)
  local d = core.dev(id)
  if not d then return end
  on = on == true
  if on and d.auto and d.auto > 0 then
    core.offAt[id] = clock() + d.auto
  elseif not on then
    core.offAt[id] = nil
  end
  if d.on == on then return end
  d.on = on
  core.dirty = true
  core.flush()
  core.touch()
  if not quiet then core.fire("device", id, on) end
end
function core.pulse(id, secs)
  core.setDevice(id, true)
  core.offAt[id] = clock() + secs
end
function core.runScene(id)
  local sc = core.scene(id)
  if not sc then return end
  core.log("Szene " .. sc.name)
  for _, d in ipairs(core.db.devices) do
    local v = sc.set[d.id]
    if v ~= nil then core.setDevice(d.id, v) end
  end
end
function core.allOff()
  for _, d in ipairs(core.db.devices) do core.setDevice(d.id, false) end
end
function core.command(c)
  if type(c) ~= "table" then return end
  if c.op == "set" and type(c.id) == "number" then
    core.setDevice(c.id, c.on == true)
  elseif c.op == "scene" and type(c.id) == "number" then
    core.runScene(c.id)
  elseif c.op == "alloff" then
    core.allOff()
  end
end

function core.runAction(a, v)
  if a.t == "dev" then
    local d = core.dev(a.id)
    if not d then return end
    if a.v == "on" then core.setDevice(a.id, true)
    elseif a.v == "off" then core.setDevice(a.id, false)
    elseif a.v == "toggle" then core.setDevice(a.id, not d.on)
    elseif a.v == "follow" then core.setDevice(a.id, v ~= false) end
  elseif a.t == "pulse" then
    core.pulse(a.id, a.secs or 10)
  elseif a.t == "scene" then
    core.runScene(a.id)
  elseif a.t == "alloff" then
    core.allOff()
  end
end
function core.runRule(r, v)
  local night = isNight(os.time())
  if r.cond == "night" and not night then return end
  if r.cond == "day" and night then return end
  if core.depth >= 6 then
    core.log("Regel-Schleife gestoppt")
    return
  end
  core.depth = core.depth + 1
  core.log("Regel: " .. core.trigText(r.trig))
  local ok, err = pcall(core.runAction, r.act, v)
  core.depth = core.depth - 1
  if not ok then core.log("Regel-Fehler: " .. tostring(err)) end
end
function core.fire(kind, id, v)
  local list = {}
  for _, r in ipairs(core.db.rules) do
    local tr = r.trig
    if r.on and tr.t == kind and tr.id == id then
      if tr.edge == "any" or (tr.edge == "on") == v then list[#list + 1] = r end
    end
  end
  for _, r in ipairs(list) do core.runRule(r, v) end
end

function core.evalSensors(nid)
  local inp = core.inputs[nid]
  if not inp then return end
  for _, s in ipairs(core.db.sensors) do
    if s.node == nid and inp[s.side] then
      local x = inp[s.side]
      local v
      if s.color == 0 then v = x.r else v = hasBit(x.m, s.color) end
      if s.inv then v = not v end
      local old = core.sens[s.id]
      if old ~= v then
        core.sens[s.id] = v
        core.touch()
        if old ~= nil then core.fire("sensor", s.id, v) end
      end
    end
  end
end
function core.onInputs(nid, inp)
  local old = core.inputs[nid]
  core.inputs[nid] = inp
  if old then
    for side, s in pairs(inp) do
      local o = old[side]
      if o then
        if s.r ~= o.r then os.queueEvent("casa_input", nid, side, 0, s.r) end
        if s.m ~= o.m then
          local c = 1
          for _ = 1, 16 do
            if hasBit(s.m, c) ~= hasBit(o.m, c) then
              os.queueEvent("casa_input", nid, side, c, hasBit(s.m, c))
            end
            c = c * 2
          end
        end
      end
    end
  end
  core.evalSensors(nid)
end

function core.onPacket(p)
  if p.k == "node" and type(p.d) == "table" and p.f ~= "local" then
    local rec = core.nodes[p.f]
    if not rec then
      rec = { online = false }
      core.nodes[p.f] = rec
    end
    rec.seen = clock()
    if rec.g ~= p.d.g then
      rec.g = p.d.g
      core.touch()
    end
    local sides = {}
    if type(p.d.s) == "table" then
      for _, s in ipairs(p.d.s) do
        if SIDES[s] then sides[#sides + 1] = s end
      end
    end
    rec.sides = sides
    if not rec.online then
      rec.online = true
      core.log("Station online: " .. p.f)
      core.touch()
    end
    core.onInputs(p.f, hw.clean(p.d.i))
    core.flushNode(p.f)
  elseif p.k == "cmd" then
    core.command(p.d)
  elseif p.k == "hi" then
    core.touch()
  end
end

function core.tick()
  local now = clock()
  -- Zeit-Regeln (auch wenn die Nacht im Bett uebersprungen wird)
  local t = os.time()
  local prev = core.lastT
  core.lastT = t
  if prev and t ~= prev then
    local d = mod24(t - prev)
    if d <= 12 then
      local due = {}
      for _, r in ipairs(core.db.rules) do
        if r.on then
          local at = nil
          if r.trig.t == "time" then at = r.trig.at
          elseif r.trig.t == "dusk" then at = DUSK
          elseif r.trig.t == "dawn" then at = DAWN end
          if at then
            local a = mod24(at - prev)
            if a > 0 and a <= d then due[#due + 1] = { a = a, r = r } end
          end
        end
      end
      table.sort(due, function(x, y) return x.a < y.a end)
      for _, e in ipairs(due) do core.runRule(e.r, true) end
    end
  end
  -- Auto-Aus
  local ids = {}
  for id, at in pairs(core.offAt) do
    if now >= at then ids[#ids + 1] = id end
  end
  for _, id in ipairs(ids) do
    core.offAt[id] = nil
    core.setDevice(id, false)
  end
  -- Stationen
  for nid, rec in pairs(core.nodes) do
    if rec.online and now - rec.seen > 12 then
      rec.online = false
      core.log("Station offline: " .. nid)
      core.touch()
    end
  end
  net.open()
  core.flush()
  if core.dirty and now - core.lastSave > 1 then core.save() end
  if now - core.lastView >= 5 then core.touch() end
end

local function nameOf(o) return o and o.name or "(entfernt)" end
function core.trigText(t)
  local edge = { on = "AN", off = "AUS", any = "wechselt" }
  if t.t == "sensor" then return nameOf(core.sensor(t.id)) .. " " .. (edge[t.edge] or "") end
  if t.t == "device" then return nameOf(core.dev(t.id)) .. " " .. (edge[t.edge] or "") end
  if t.t == "time" then return fmtTime(t.at) .. " Uhr" end
  if t.t == "dusk" then return "Abend" end
  if t.t == "dawn" then return "Morgen" end
  return "?"
end
function core.actText(a)
  local v = { on = "AN", off = "AUS", toggle = "umschalten", follow = "folgt" }
  if a.t == "dev" then return nameOf(core.dev(a.id)) .. " " .. (v[a.v] or "") end
  if a.t == "pulse" then return nameOf(core.dev(a.id)) .. " " .. string.format("%d", a.secs or 10) .. "s AN" end
  if a.t == "scene" then return "Szene " .. nameOf(core.scene(a.id)) end
  if a.t == "alloff" then return "Alles AUS" end
  return "?"
end
function core.purge(kind, id)
  local keep = {}
  for _, r in ipairs(core.db.rules) do
    local hitT = r.trig.t == kind and r.trig.id == id
    local hitA = false
    if kind == "device" and (r.act.t == "dev" or r.act.t == "pulse") and r.act.id == id then hitA = true end
    if kind == "scene" and r.act.t == "scene" and r.act.id == id then hitA = true end
    if not hitT and not hitA then keep[#keep + 1] = r end
  end
  core.db.rules = keep
  if kind == "device" then
    for _, s in ipairs(core.db.scenes) do s.set[id] = nil end
    core.offAt[id] = nil
  end
  if kind == "sensor" then core.sens[id] = nil end
end

------------------------------------------------------------------
-- Text-Menues am Computer (Tastatur, auf Advanced auch Maus)
------------------------------------------------------------------
local ui = {}
ui.color = term.isColor and term.isColor() or false

function ui.head(title)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  if ui.color then term.setBackgroundColor(colors.blue) end
  term.clearLine()
  term.write(" " .. title)
  term.setBackgroundColor(colors.black)
  term.setCursorPos(1, 3)
end

function ui.menu(title, build, st, status)
  st = st or {}
  st.sel = st.sel or 1
  st.top = st.top or 1
  local timer = os.startTimer(2)
  local lastSig = nil
  while true do
    local items = build()
    local w, h = term.getSize()
    local rows = h - 4
    if st.sel > #items then st.sel = #items end
    if st.sel < 1 then st.sel = 1 end
    if st.sel < st.top then st.top = st.sel end
    if st.sel >= st.top + rows then st.top = st.sel - rows + 1 end
    local stat = status and status() or ""
    local parts = { title, stat, tostring(st.sel), tostring(st.top) }
    for i = 1, #items do
      parts[#parts + 1] = items[i].label
      parts[#parts + 1] = items[i].right or ""
    end
    local sig = table.concat(parts, "\1")
    if sig ~= lastSig then
      lastSig = sig
      ui.head(title)
      term.setCursorPos(2, 2)
      if ui.color then term.setTextColor(colors.lightGray) end
      term.write(cut(stat, w - 2))
      term.setTextColor(colors.white)
      for i = 0, rows - 1 do
        local it = items[st.top + i]
        if it then
          local y = 3 + i
          local selected = (st.top + i) == st.sel
          term.setCursorPos(1, y)
          if selected and ui.color then term.setBackgroundColor(colors.gray) end
          term.clearLine()
          local right = cut(it.right or "", w - 14)
          term.write(cut((selected and "> " or "  ") .. it.label, w - #right - 2))
          if #right > 0 then
            term.setCursorPos(w - #right, y)
            if ui.color and not selected then term.setTextColor(colors.lightGray) end
            term.write(right)
            term.setTextColor(colors.white)
          end
          if it.sw and ui.color then
            term.setCursorPos(w - #right - 3, y)
            term.setBackgroundColor(it.sw)
            term.write("  ")
          end
          term.setBackgroundColor(colors.black)
        end
      end
      term.setCursorPos(1, h)
      if ui.color then term.setTextColor(colors.lightGray) end
      term.write(cut(" Pfeile=Wahl  Enter=OK  Pfeil links=Abbruch", w - 1))
      term.setTextColor(colors.white)
    end
    local ev = { os.pullEvent() }
    if ev[1] == "key" then
      local k = ev[2]
      if k == 200 then
        st.sel = st.sel - 1
        if st.sel < 1 then st.sel = #items end
      elseif k == 208 then
        st.sel = st.sel + 1
        if st.sel > #items then st.sel = 1 end
      elseif k == 28 then
        if items[st.sel] then return items[st.sel] end
      elseif k == 14 or k == 203 then
        return nil
      end
    elseif ev[1] == "mouse_click" then
      local idx = st.top + (ev[4] - 3)
      if ev[4] >= 3 and items[idx] then
        st.sel = idx
        return items[idx]
      end
    elseif ev[1] == "timer" and ev[2] == timer then
      timer = os.startTimer(2)
    end
  end
end
function ui.run(title, build, status)
  local st = {}
  while true do
    local it = ui.menu(title, build, st, status)
    if not it then return end
    if it.fn and it.fn() == "back" then return end
  end
end
function ui.pick(title, list)
  local it = ui.menu(title, function() return list end)
  if not it then return nil end
  return it.value
end
function ui.prompt(title, label, default)
  ui.head(title)
  print(label)
  if default ~= nil and default ~= "" then print("(leer lassen = " .. tostring(default) .. ")") end
  write("> ")
  local s = trim(read() or "")
  if s == "" then return default end
  return cut(s, 20)
end
function ui.number(title, label, default, lo, hi)
  local s = ui.prompt(title, label, default)
  local n = tonumber(s)
  if not n or n < lo or n > hi then return default end
  return n
end
function ui.message(title, text)
  ui.head(title)
  print(text)
  print("")
  print("[Enter] weiter")
  while true do
    local _, k = os.pullEvent("key")
    if k == 28 then return end
  end
end
function ui.confirm(question)
  return ui.pick(question, { { label = "Nein", value = false }, { label = "Ja", value = true } }) == true
end

------------------------------------------------------------------
-- Verwaltung an der Zentrale
------------------------------------------------------------------
local admin = {}
local COLORS = {
  { 1, "weiss" }, { 2, "orange" }, { 4, "magenta" }, { 8, "hellblau" },
  { 16, "gelb" }, { 32, "hellgruen" }, { 64, "rosa" }, { 128, "grau" },
  { 256, "hellgrau" }, { 512, "cyan" }, { 1024, "lila" }, { 2048, "blau" },
  { 4096, "braun" }, { 8192, "gruen" }, { 16384, "rot" }, { 32768, "schwarz" },
}
local SIDE_DE = { top = "oben", bottom = "unten", left = "links", right = "rechts", front = "vorne", back = "hinten" }
local function colorName(c)
  if c == 0 then return "Redstone" end
  for _, e in ipairs(COLORS) do
    if e[1] == c then return e[2] end
  end
  return "?"
end
local function wireText(o)
  local n = (o.node == "local") and "Zentrale" or o.node
  return n .. " " .. (SIDE_DE[o.side] or o.side) .. " " .. colorName(o.color)
end

function admin.pickNode()
  local list = { { label = "Dieser Computer (Zentrale)", value = "local" } }
  for _, n in ipairs(core.nodeIds()) do
    local rec = core.nodes[n]
    list[#list + 1] = { label = "Station " .. n, right = (rec and rec.online) and "online" or "offline", value = n }
  end
  return ui.pick("Welcher Computer?", list)
end
function admin.pickSide(nid)
  local sides
  if nid == "local" then
    sides = hw.sides()
  elseif core.nodes[nid] and core.nodes[nid].sides and #core.nodes[nid].sides > 0 then
    sides = core.nodes[nid].sides
  else
    sides = { "top", "bottom", "left", "right", "front", "back" }
  end
  local list = {}
  for _, s in ipairs(sides) do list[#list + 1] = { label = SIDE_DE[s] or s, right = s, value = s } end
  return ui.pick("Welche Seite? (vorne = Bildschirm)", list)
end
function admin.pickColor()
  local list = { { label = "Normales Redstone (kein Kabel)", value = 0 } }
  for _, e in ipairs(COLORS) do list[#list + 1] = { label = "Kabelfarbe " .. e[2], value = e[1], sw = e[1] } end
  return ui.pick("Welche Farbe im Buendelkabel?", list)
end
function admin.pickRoom()
  local list = {}
  for _, r in ipairs(core.rooms()) do list[#list + 1] = { label = r, value = r } end
  list[#list + 1] = { label = "+ Neuer Raum", value = false }
  local v = ui.pick("Welcher Raum?", list)
  if v == nil then return nil end
  if v == false then return ui.prompt("Neuer Raum", "Name des Raums:", nil) end
  return v
end
local function pickFrom(title, source, empty)
  if #source == 0 then
    ui.message(title, empty)
    return nil
  end
  local list = {}
  for _, o in ipairs(source) do list[#list + 1] = { label = o.name, right = o.room or "", value = o.id } end
  return ui.pick(title, list)
end
function admin.pickDevice() return pickFrom("Welcher Schalter?", core.db.devices, "Es gibt noch keine Schalter.") end
function admin.pickSensor() return pickFrom("Welcher Sensor?", core.db.sensors, "Es gibt noch keine Sensoren.") end
function admin.pickScene() return pickFrom("Welche Szene?", core.db.scenes, "Es gibt noch keine Szenen.") end

function admin.warnUsed(o)
  local other, kind = core.usedBy(o.node, o.side, o.color, o.id)
  if other then
    ui.message("Achtung", "Diese Leitung wird schon benutzt von " .. kind .. " \"" .. other.name .. "\".")
  end
end
local function removeFrom(list, o)
  for i, x in ipairs(list) do
    if x == o then
      table.remove(list, i)
      return
    end
  end
end

-- Felder, die Schalter und Sensor gemeinsam haben
local function wireItems(o, title)
  return {
    { label = "Name", right = o.name, fn = function()
      o.name = ui.prompt(title, "Neuer Name:", o.name)
      core.changed()
    end },
    { label = "Raum", right = o.room, fn = function()
      local r = admin.pickRoom()
      if r then o.room = r core.changed() end
    end },
    { label = "Computer", right = (o.node == "local") and "Zentrale" or o.node, fn = function()
      local n = admin.pickNode()
      if n then o.node = n admin.warnUsed(o) core.changed() end
    end },
    { label = "Seite", right = SIDE_DE[o.side] or o.side, fn = function()
      local s = admin.pickSide(o.node)
      if s then o.side = s admin.warnUsed(o) core.changed() end
    end },
    { label = "Farbe", right = colorName(o.color), fn = function()
      local c = admin.pickColor()
      if c then o.color = c admin.warnUsed(o) core.changed() end
    end },
    { label = "Signal umkehren", right = o.inv and "ja" or "nein", fn = function()
      o.inv = not o.inv
      core.changed()
      core.evalSensors(o.node)
    end },
  }
end

function admin.editDevice(d)
  ui.run("Schalter bearbeiten", function()
    local items = { { label = "Jetzt umschalten (Test)", right = d.on and "AN" or "aus", fn = function()
      core.setDevice(d.id, not d.on)
    end } }
    for _, it in ipairs(wireItems(d, "Schalter")) do items[#items + 1] = it end
    items[#items + 1] = { label = "Automatisch aus nach", right = (d.auto and d.auto > 0) and (string.format("%d", d.auto) .. " s") or "nie", fn = function()
      d.auto = math.floor(ui.number("Schalter", "Sekunden bis automatisch aus (0 = nie):", 0, 0, 86400))
      core.changed()
    end }
    items[#items + 1] = { label = "Schalter entfernen", fn = function()
      if ui.confirm("\"" .. d.name .. "\" wirklich entfernen?") then
        removeFrom(core.db.devices, d)
        core.purge("device", d.id)
        core.changed()
        return "back"
      end
    end }
    return items
  end)
end
function admin.newDevice()
  local name = ui.prompt("Neuer Schalter", "Name (z.B. Licht Kueche):", nil)
  if not name then return end
  local room = admin.pickRoom()
  if not room then return end
  local node = admin.pickNode()
  if not node then return end
  local side = admin.pickSide(node)
  if not side then return end
  local color = admin.pickColor()
  if not color then return end
  local d = { id = core.newId(), name = name, room = room, node = node, side = side, color = color, inv = false, auto = 0, on = false }
  table.insert(core.db.devices, d)
  admin.warnUsed(d)
  core.changed()
  admin.editDevice(d)
end
function admin.devices()
  ui.run("Schalter", function()
    local items = {}
    for _, d in ipairs(core.db.devices) do
      items[#items + 1] = { label = d.name, right = d.room .. "  " .. (d.on and "AN " or "aus"), fn = function() admin.editDevice(d) end }
    end
    items[#items + 1] = { label = "+ Neuer Schalter", fn = admin.newDevice }
    return items
  end)
end

function admin.learn()
  ui.head("Sensor lernen")
  print("Jetzt den Hebel, Knopf oder die Druckplatte")
  print("einmal schalten. Casa erkennt die Leitung.")
  print("")
  print("Warte 60 Sekunden...   [Pfeil links] Abbruch")
  local t = os.startTimer(60)
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "casa_input" then
      if not core.isOutput(ev[2], ev[3], ev[4]) then return ev[2], ev[3], ev[4] end
    elseif ev[1] == "key" and (ev[2] == 14 or ev[2] == 203) then
      return nil
    elseif ev[1] == "timer" and ev[2] == t then
      return nil
    end
  end
end
function admin.editSensor(s)
  ui.run("Sensor bearbeiten", function()
    local v = core.sens[s.id]
    local items = { { label = "Zustand jetzt", right = (v == true and "AN") or (v == false and "aus") or "unbekannt" } }
    for _, it in ipairs(wireItems(s, "Sensor")) do items[#items + 1] = it end
    items[#items + 1] = { label = "Sensor entfernen", fn = function()
      if ui.confirm("\"" .. s.name .. "\" wirklich entfernen?") then
        removeFrom(core.db.sensors, s)
        core.purge("sensor", s.id)
        core.changed()
        return "back"
      end
    end }
    return items
  end)
end
function admin.newSensor()
  local name = ui.prompt("Neuer Sensor", "Name (z.B. Haustuer):", nil)
  if not name then return end
  local room = admin.pickRoom()
  if not room then return end
  local how = ui.pick("Wie anschliessen?", {
    { label = "Lernen (Signal einmal ausloesen)", value = "learn" },
    { label = "Von Hand eintragen", value = "manual" },
  })
  if not how then return end
  local node, side, color
  if how == "learn" then
    node, side, color = admin.learn()
    if not node then
      ui.message("Sensor lernen", "Kein Signal erkannt.")
      return
    end
  else
    node = admin.pickNode()
    if not node then return end
    side = admin.pickSide(node)
    if not side then return end
    color = admin.pickColor()
    if not color then return end
  end
  local s = { id = core.newId(), name = name, room = room, node = node, side = side, color = color, inv = false }
  table.insert(core.db.sensors, s)
  admin.warnUsed(s)
  core.changed()
  core.evalSensors(node)
  if how == "learn" then ui.message("Sensor gelernt", "Erkannt: " .. wireText(s)) end
  admin.editSensor(s)
end
function admin.sensors()
  ui.run("Sensoren", function()
    local items = {}
    for _, s in ipairs(core.db.sensors) do
      local v = core.sens[s.id]
      items[#items + 1] = { label = s.name, right = s.room .. "  " .. ((v == true and "AN ") or (v == false and "aus") or "?  "), fn = function() admin.editSensor(s) end }
    end
    items[#items + 1] = { label = "+ Neuer Sensor", fn = admin.newSensor }
    return items
  end)
end

function admin.editScene(sc)
  ui.run("Szene bearbeiten", function()
    local items = {
      { label = "Name", right = sc.name, fn = function()
        sc.name = ui.prompt("Szene", "Neuer Name:", sc.name)
        core.changed()
      end },
      { label = "Jetzt starten", fn = function() core.runScene(sc.id) end },
      { label = "Aktuellen Zustand aller Schalter merken", fn = function()
        sc.set = {}
        for _, d in ipairs(core.db.devices) do sc.set[d.id] = d.on end
        core.changed()
      end },
    }
    for _, d in ipairs(core.db.devices) do
      local v = sc.set[d.id]
      items[#items + 1] = { label = "  " .. d.name, right = (v == true and "AN") or (v == false and "AUS") or "egal", fn = function()
        if v == nil then sc.set[d.id] = true elseif v == true then sc.set[d.id] = false else sc.set[d.id] = nil end
        core.changed()
      end }
    end
    items[#items + 1] = { label = "Szene entfernen", fn = function()
      if ui.confirm("\"" .. sc.name .. "\" wirklich entfernen?") then
        removeFrom(core.db.scenes, sc)
        core.purge("scene", sc.id)
        core.changed()
        return "back"
      end
    end }
    return items
  end)
end
function admin.scenes()
  ui.run("Szenen", function()
    local items = {}
    for _, sc in ipairs(core.db.scenes) do
      items[#items + 1] = { label = sc.name, fn = function() admin.editScene(sc) end }
    end
    items[#items + 1] = { label = "+ Neue Szene", fn = function()
      local name = ui.prompt("Neue Szene", "Name (z.B. Gute Nacht):", nil)
      if not name then return end
      local sc = { id = core.newId(), name = name, set = {} }
      table.insert(core.db.scenes, sc)
      core.changed()
      admin.editScene(sc)
    end }
    return items
  end)
end

function admin.pickTrigger()
  local kind = ui.pick("Wenn...", {
    { label = "Sensor geht AN", value = "s_on" },
    { label = "Sensor geht AUS", value = "s_off" },
    { label = "Sensor wechselt (AN oder AUS)", value = "s_any" },
    { label = "Schalter geht AN", value = "d_on" },
    { label = "Schalter geht AUS", value = "d_off" },
    { label = "Uhrzeit im Spiel", value = "time" },
    { label = "Es wird Abend", value = "dusk" },
    { label = "Es wird Morgen", value = "dawn" },
  })
  if not kind then return nil end
  if kind == "dusk" or kind == "dawn" then return { t = kind } end
  if kind == "time" then
    local s = ui.prompt("Uhrzeit", "Uhrzeit im Spiel, z.B. 18:30", nil)
    if not s then return nil end
    local h, m = s, "0"
    local p = string.find(s, ":", 1, true)
    if p then
      h = string.sub(s, 1, p - 1)
      m = string.sub(s, p + 1)
    end
    h, m = tonumber(h), tonumber(m)
    if not h or not m or h < 0 or h >= 24 or m < 0 or m >= 60 then
      ui.message("Uhrzeit", "Das war keine Uhrzeit.")
      return nil
    end
    return { t = "time", at = h + m / 60 }
  end
  local edge = string.sub(kind, 3)
  if string.sub(kind, 1, 1) == "s" then
    local id = admin.pickSensor()
    if not id then return nil end
    return { t = "sensor", id = id, edge = edge }
  end
  local id = admin.pickDevice()
  if not id then return nil end
  return { t = "device", id = id, edge = edge }
end
function admin.pickAction()
  local kind = ui.pick("Dann...", {
    { label = "Schalter AN", value = "on" },
    { label = "Schalter AUS", value = "off" },
    { label = "Schalter umschalten", value = "toggle" },
    { label = "Schalter folgt dem Sensor", value = "follow" },
    { label = "Schalter eine Zeit lang AN", value = "pulse" },
    { label = "Szene starten", value = "scene" },
    { label = "Alles AUS", value = "alloff" },
  })
  if not kind then return nil end
  if kind == "alloff" then return { t = "alloff" } end
  if kind == "scene" then
    local id = admin.pickScene()
    if not id then return nil end
    return { t = "scene", id = id }
  end
  local id = admin.pickDevice()
  if not id then return nil end
  if kind == "pulse" then
    local secs = math.floor(ui.number("Dauer", "Wie viele Sekunden AN?", 10, 1, 86400))
    return { t = "pulse", id = id, secs = secs }
  end
  return { t = "dev", id = id, v = kind }
end
local COND_DE = { night = "nur nachts", day = "nur am Tag" }
function admin.editRule(r)
  ui.run("Regel bearbeiten", function()
    return {
      { label = "Wenn", right = core.trigText(r.trig), fn = function()
        local t = admin.pickTrigger()
        if t then r.trig = t core.changed() end
      end },
      { label = "Dann", right = core.actText(r.act), fn = function()
        local a = admin.pickAction()
        if a then r.act = a core.changed() end
      end },
      { label = "Wann gilt die Regel", right = COND_DE[r.cond] or "immer", fn = function()
        if r.cond == "night" then r.cond = "day" elseif r.cond == "day" then r.cond = nil else r.cond = "night" end
        core.changed()
      end },
      { label = "Aktiv", right = r.on and "ja" or "nein", fn = function()
        r.on = not r.on
        core.changed()
      end },
      { label = "Jetzt testen", fn = function() core.runAction(r.act, true) end },
      { label = "Regel entfernen", fn = function()
        removeFrom(core.db.rules, r)
        core.changed()
        return "back"
      end },
    }
  end)
end
function admin.rules()
  ui.run("Regeln", function()
    local items = {}
    for _, r in ipairs(core.db.rules) do
      items[#items + 1] = { label = (r.on and "" or "(aus) ") .. core.trigText(r.trig) .. " -> " .. core.actText(r.act), right = COND_DE[r.cond] or "", fn = function() admin.editRule(r) end }
    end
    items[#items + 1] = { label = "+ Neue Regel", fn = function()
      local t = admin.pickTrigger()
      if not t then return end
      local a = admin.pickAction()
      if not a then return end
      local r = { id = core.newId(), on = true, trig = t, act = a }
      table.insert(core.db.rules, r)
      core.changed()
      admin.editRule(r)
    end }
    return items
  end)
end

function admin.nodes()
  ui.run("Stationen", function()
    local items = {}
    for _, n in ipairs(core.nodeIds()) do
      local rec = core.nodes[n]
      local state = "nie gesehen"
      if rec then
        if rec.online then
          state = (rec.g == rec.want) and "online" or "online, sendet..."
        else
          state = "offline"
        end
      end
      items[#items + 1] = { label = n, right = state, fn = function()
        local used = false
        for _, d in ipairs(core.db.devices) do if d.node == n then used = true end end
        for _, s in ipairs(core.db.sensors) do if s.node == n then used = true end end
        if used then
          ui.message("Station " .. n, "Diese Station wird von Schaltern oder Sensoren benutzt.")
        elseif ui.confirm("Station " .. n .. " aus der Liste nehmen?") then
          core.nodes[n] = nil
          core.inputs[n] = nil
        end
      end }
    end
    if #items == 0 then
      items[1] = { label = "Noch keine Station gefunden." }
      items[2] = { label = "Auf dem anderen Computer casa starten." }
    end
    return items
  end)
end
function admin.logView()
  ui.run("Protokoll", function()
    local items = {}
    for _, l in ipairs(core.logs) do items[#items + 1] = { label = l } end
    if #items == 0 then items[1] = { label = "(noch leer)" } end
    return items
  end)
end
function admin.settings()
  ui.run("Einstellungen", function()
    local scaleText = "automatisch"
    if (cfg.scale or 0) > 0 then scaleText = tostring(cfg.scale) end
    return {
      { label = "Name des Hauses", right = cfg.name, fn = function()
        cfg.name = ui.prompt("Einstellungen", "Name (steht oben auf den Panels):", cfg.name)
        store.save("cfg", cfg)
        core.touch()
      end },
      { label = "Textgroesse der Monitore hier", right = scaleText, fn = function()
        local v = ui.pick("Textgroesse", {
          { label = "automatisch", value = 0 }, { label = "0.5 (klein)", value = 0.5 },
          { label = "1", value = 1 }, { label = "1.5", value = 1.5 }, { label = "2 (gross)", value = 2 },
        })
        if v then
          cfg.scale = v
          store.save("cfg", cfg)
          core.touch()
        end
      end },
      { label = "Funk weiterleiten (Relay)", right = cfg.relay and "ja" or "nein", fn = function()
        cfg.relay = not cfg.relay
        store.save("cfg", cfg)
      end },
      { label = "Funkkanal", right = string.format("%d", cfg.channel), fn = function()
        cfg.channel = math.floor(ui.number("Funkkanal", "Kanal 1-65535. Auf ALLEN Computern gleich!", cfg.channel, 1, 65535))
        store.save("cfg", cfg)
        net.reopen()
      end },
      { label = "Passwort", right = cfg.key, fn = function()
        cfg.key = ui.prompt("Passwort", "Passwort. Auf ALLEN Computern gleich!", cfg.key)
        store.save("cfg", cfg)
      end },
    }
  end)
end
function admin.main()
  ui.run("Casa " .. VERSION .. " - Zentrale", function()
    return {
      { label = "Schalter", right = string.format("%d", #core.db.devices), fn = admin.devices },
      { label = "Sensoren", right = string.format("%d", #core.db.sensors), fn = admin.sensors },
      { label = "Szenen", right = string.format("%d", #core.db.scenes), fn = admin.scenes },
      { label = "Regeln", right = string.format("%d", #core.db.rules), fn = admin.rules },
      { label = "Stationen", fn = admin.nodes },
      { label = "Protokoll", fn = admin.logView },
      { label = "Einstellungen", fn = admin.settings },
      { label = "Casa beenden", fn = function()
        if ui.confirm("Casa beenden? Dann wird nichts mehr gesteuert.") then return "back" end
      end },
    }
  end, function()
    local on, online, total = 0, 0, 0
    for _, d in ipairs(core.db.devices) do if d.on then on = on + 1 end end
    for _, n in ipairs(core.nodeIds()) do
      total = total + 1
      if core.nodes[n] and core.nodes[n].online then online = online + 1 end
    end
    local t = os.time()
    return string.format("%d an | Stationen %d/%d | %s %s", on, online, total, fmtTime(t), isNight(t) and "Nacht" or "Tag")
      .. (net.modem and "" or " | KEIN MODEM")
  end)
end

------------------------------------------------------------------
-- Rollen
------------------------------------------------------------------
local function runServer()
  cfg.id = "srv"
  core.init()
  net.init()

  local function coreLoop()
    core.onInputs("local", hw.read())
    core.flush()
    local tick = os.startTimer(0.5)
    while true do
      local ev = { os.pullEvent() }
      local e = ev[1]
      if e == "timer" and ev[2] == tick then
        core.tick()
        tick = os.startTimer(0.5)
      elseif e == "modem_message" or e == "rednet_message" then
        local p = net.fromEvent(ev)
        if p then core.onPacket(p) end
      elseif e == "redstone" then
        core.onInputs("local", hw.read())
      elseif e == "casa_view" then
        core.viewQueued = false
        core.broadcast()
      end
    end
  end

  local function displayLoop()
    local panels = {}
    local function scan()
      for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "monitor" then
          local p = panels[side]
          if not p or p.scale ~= (cfg.scale or 0) then
            local mon = setupMonitor(side)
            if mon then
              p = newPanel(mon, core.view, core.command, nil)
              p.scale = cfg.scale or 0
              panels[side] = p
            end
          end
        else
          panels[side] = nil
        end
      end
    end
    local function renderAll()
      for side, p in pairs(panels) do
        if not pcall(p.render) then panels[side] = nil end
      end
    end
    scan()
    renderAll()
    local t = os.startTimer(1)
    while true do
      local ev = { os.pullEvent() }
      local e = ev[1]
      if e == "monitor_touch" then
        local p = panels[ev[2]]
        if p then p.touch(ev[3], ev[4]) end
        renderAll()
      elseif e == "casa_view" then
        renderAll()
      elseif e == "timer" and ev[2] == t then
        scan()
        renderAll()
        t = os.startTimer(1)
      elseif e == "peripheral" or e == "peripheral_detach" then
        scan()
        renderAll()
      end
    end
  end

  parallel.waitForAny(coreLoop, displayLoop, admin.main)
  core.save()
end

local function runNode()
  net.init()
  local outs, sig = {}, nil
  local cache = store.load("outs")
  if type(cache) == "table" then
    outs = hw.clean(cache.o)
    sig = cache.g
  end
  hw.apply(outs)
  local inputs = hw.read()
  local srvSeen = nil

  local function report()
    net.send("srv", "node", { i = inputs, g = sig, s = hw.sides(), v = VERSION })
  end
  local function draw()
    ui.head("Casa " .. VERSION .. " - Station " .. cfg.id)
    if not net.modem then
      print("KEIN MODEM! Bitte ein Funkmodem anbauen.")
    elseif srvSeen and clock() - srvSeen < 15 then
      print("Zentrale: verbunden")
    else
      print("Zentrale: suche... (Kanal " .. string.format("%d", cfg.channel) .. ")")
    end
    print("")
    for _, side in ipairs(hw.sides()) do
      local o = outs[side] or { m = 0, r = false }
      local i = inputs[side] or { m = 0, r = false }
      local name = SIDE_DE[side] or side
      print(name .. string.rep(" ", 7 - #name) .. " aus: " .. string.format("%d", o.m) .. (o.r and " R" or " -")
        .. "   ein: " .. string.format("%d", i.m) .. (i.r and " R" or " -"))
    end
    print("")
    print("Einrichten an der Zentrale. Strg+T = Ende")
  end

  report()
  draw()
  local hb = os.startTimer(4)
  while true do
    local ev = { os.pullEvent() }
    local e = ev[1]
    if e == "timer" and ev[2] == hb then
      net.open()
      inputs = hw.read()
      report()
      draw()
      hb = os.startTimer(4)
    elseif e == "redstone" then
      local cur = hw.read()
      if not hw.same(cur, inputs) then
        inputs = cur
        report()
        draw()
      end
    elseif e == "modem_message" or e == "rednet_message" then
      local p = net.fromEvent(ev)
      if p and p.f == "srv" then
        local was = srvSeen and clock() - srvSeen < 15
        srvSeen = clock()
        if p.k == "set" and type(p.d) == "table" then
          outs = hw.clean(p.d.o)
          sig = p.d.g
          hw.apply(outs)
          store.save("outs", { o = outs, g = sig })
          inputs = hw.read()
          report()
          draw()
        elseif not was then
          draw()
        end
      end
    end
  end
end

local function runPanel()
  net.init()
  local view, viewAt = nil, -100
  local outbox = {}
  local panels = {}

  local function getView()
    if view and clock() - viewAt < 15 then return view end
    return nil
  end
  local function sendCmd(c)
    net.send("srv", "cmd", c)
    outbox[#outbox + 1] = { c = c, n = 2, at = clock() + 0.6 }
  end
  local function scan()
    if not panels.term then
      panels.term = newPanel(term, getView, sendCmd, cfg.room)
    end
    for _, side in ipairs(rs.getSides()) do
      if peripheral.getType(side) == "monitor" then
        if not panels[side] then
          local mon = setupMonitor(side)
          if mon then panels[side] = newPanel(mon, getView, sendCmd, cfg.room) end
        end
      else
        panels[side] = nil
      end
    end
  end
  local function renderAll()
    for side, p in pairs(panels) do
      if not pcall(p.render) then panels[side] = nil end
    end
  end
  local function pump()
    local now = clock()
    local keep = {}
    for _, e in ipairs(outbox) do
      if now >= e.at then
        net.send("srv", "cmd", e.c)
        e.n = e.n - 1
        e.at = now + 0.6
      end
      if e.n > 0 then keep[#keep + 1] = e end
    end
    outbox = keep
  end

  scan()
  net.send("srv", "hi", {})
  renderAll()
  local tick = os.startTimer(0.5)
  local n = 0
  while true do
    local ev = { os.pullEvent() }
    local e = ev[1]
    if e == "timer" and ev[2] == tick then
      n = n + 1
      net.open()
      pump()
      if n % 4 == 0 then
        scan()
        if clock() - viewAt > 6 then net.send("srv", "hi", {}) end
      end
      renderAll()
      tick = os.startTimer(0.5)
    elseif e == "monitor_touch" then
      local p = panels[ev[2]]
      if p then p.touch(ev[3], ev[4]) end
      renderAll()
    elseif e == "mouse_click" then
      if panels.term then panels.term.touch(ev[3], ev[4]) end
      renderAll()
    elseif e == "modem_message" or e == "rednet_message" then
      local p = net.fromEvent(ev)
      if p and p.f == "srv" and p.k == "view" and type(p.d) == "table"
        and type(p.d.rooms) == "table" and type(p.d.dev) == "table"
        and type(p.d.sen) == "table" and type(p.d.scn) == "table" then
        view = p.d
        view.name = tostring(view.name or "Casa")
        viewAt = clock()
        local keep = {}
        for _, o in ipairs(outbox) do
          local done = false
          if o.c.op == "set" then
            for _, d in ipairs(view.dev) do
              if d.i == o.c.id and (d.s % 2 == 1) == o.c.on then done = true end
            end
          end
          if not done then keep[#keep + 1] = o end
        end
        outbox = keep
        renderAll()
      end
    end
  end
end

------------------------------------------------------------------
-- Ersteinrichtung
------------------------------------------------------------------
local function setup(old)
  old = old or {}
  local c = {
    channel = old.channel or 4711, key = old.key or "casa", name = old.name or "Casa",
    relay = false, scale = old.scale or 0, hops = 3,
  }
  local role = ui.pick("Casa " .. VERSION .. " - Was ist dieser Computer?", {
    { label = "Zentrale  (steuert alles, 1x pro Haus)", value = "srv" },
    { label = "Station   (Kabel/Redstone woanders)", value = "node" },
    { label = "Panel     (Monitor zum Schalten)", value = "panel" },
  })
  if not role then return nil end
  c.role = role
  local cid = string.format("%d", os.getComputerID())
  if role == "srv" then
    c.id = "srv"
  elseif role == "node" then
    local def = (old.role == "node" and old.id) or ("station" .. cid)
    local id = ui.prompt("Station", "Name dieser Station (z.B. keller):", def)
    if id == "srv" or id == "local" or id == "*" then id = def end
    c.id = id
  else
    c.id = "panel" .. cid
  end
  c.channel = math.floor(ui.number("Funkkanal", "Funkkanal (auf allen Computern gleich):", c.channel, 1, 65535))
  c.key = ui.prompt("Passwort", "Passwort (auf allen Computern gleich):", c.key)
  if role == "srv" then
    c.name = ui.prompt("Name", "Name des Hauses (steht auf den Panels):", c.name)
  else
    c.relay = ui.pick("Funk fuer andere weiterleiten (Relay)?", {
      { label = "Nein", value = false }, { label = "Ja (verlaengert die Reichweite)", value = true },
    }) == true
  end
  if role == "panel" then
    c.room = ui.prompt("Panel", "Nur einen Raum zeigen? Name eintippen,\nleer lassen = alle Raeume:", "")
  end
  local auto = ui.pick("Beim Einschalten automatisch starten?", {
    { label = "Ja (empfohlen)", value = true }, { label = "Nein", value = false },
  })
  if auto then
    local prog = "casa"
    if shell and shell.getRunningProgram then prog = shell.getRunningProgram() end
    if fs.exists("/startup") then
      if fs.exists("/startup.old") then fs.delete("/startup.old") end
      fs.move("/startup", "/startup.old")
    end
    local f = fs.open("/startup", "w")
    f.write("shell.run(\"/" .. prog .. "\")\n")
    f.close()
  end
  store.save("cfg", c)
  return c
end

------------------------------------------------------------------
-- Start
------------------------------------------------------------------
local function main()
  if not fs.exists(DIR) then fs.makeDir(DIR) end
  cfg = store.load("cfg")
  if args[1] == "setup" or type(cfg) ~= "table" or not cfg.role then
    cfg = setup(cfg)
    if not cfg then return end
  end
  if cfg.role == "srv" then
    runServer()
  elseif cfg.role == "node" then
    runNode()
  else
    runPanel()
  end
end

local ok, err = pcall(main)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
if ok or string.find(tostring(err), "Terminated", 1, true) then
  print("Casa beendet.")
else
  print("Casa Fehler: " .. tostring(err))
  pcall(function()
    local f = fs.open(DIR .. "/fehler.txt", "w")
    f.write(tostring(err))
    f.close()
  end)
  print("Neustart in 5 Sekunden (Strg+T = Abbruch)")
  sleep(5)
  os.reboot()
end
