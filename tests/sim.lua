-- Simuliert mehrere ComputerCraft-1.5-Computer und testet casa.lua.
-- Aufruf im Projektordner:  lua tests/sim.lua
local SRC = arg and arg[1] or "casa.lua"
local unpack = table.unpack or unpack
local T, world = 0, 12.0
local computers, timers, timerId, air = {}, {}, 0, {}
local SIDELIST = { "top", "bottom", "left", "right", "front", "back" }
local COLORS = { white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16, lime = 32, pink = 64,
  gray = 128, lightGray = 256, cyan = 512, purple = 1024, blue = 2048, brown = 4096, green = 8192,
  red = 16384, black = 32768 }

local function newDisplay(w, h, color)
  local d = { w = w, h = h, cx = 1, cy = 1, rows = {}, bgs = {}, bg = 32768 }
  local function reset()
    for y = 1, h do d.rows[y] = string.rep(" ", w) d.bgs[y] = {} end
  end
  reset()
  local api = {}
  api.getSize = function() return d.w, d.h end
  api.isColor = function() return color end
  api.setCursorPos = function(x, y) d.cx, d.cy = x, y end
  api.getCursorPos = function() return d.cx, d.cy end
  api.setTextColor = function(c) assert(type(c) == "number") end
  api.setBackgroundColor = function(c) assert(type(c) == "number") d.bg = c end
  api.setTextScale = function() end
  api.setCursorBlink = function() end
  api.clear = reset
  api.clearLine = function()
    if d.rows[d.cy] then d.rows[d.cy] = string.rep(" ", w) d.bgs[d.cy] = {} end
  end
  api.write = function(s)
    s = tostring(s)
    local row = d.rows[d.cy]
    if row then
      for i = 1, #s do
        local x = d.cx + i - 1
        if x >= 1 and x <= d.w then
          row = string.sub(row, 1, x - 1) .. string.sub(s, i, i) .. string.sub(row, x + 1)
          d.bgs[d.cy][x] = d.bg
        end
      end
      d.rows[d.cy] = row
    end
    d.cx = d.cx + #s
  end
  return api, d
end

local function push(c, ...) c.queue[#c.queue + 1] = { ... } end

local function newComputer(id, opts)
  local c = { id = id, x = opts.x or 0, files = {}, queue = {}, bout = {}, bin = {}, rout = {}, rin = {},
    modemSide = opts.modem, open = {}, monitors = {}, mdata = {}, running = false }
  c.term, c.tdata = newDisplay(51, 19, opts.color ~= false)
  for side, size in pairs(opts.monitors or {}) do
    c.monitors[side], c.mdata[side] = newDisplay(size[1], size[2], true)
  end
  computers[#computers + 1] = c

  local env = setmetatable({}, { __index = _G })
  c.env = env
  env.unpack = unpack
  env.colors = COLORS
  env.term = c.term
  env.os = {
    clock = function() return T end,
    time = function() return world % 24 end,
    day = function() return math.floor(world / 24) end,
    getComputerID = function() return id end,
    startTimer = function(s)
      timerId = timerId + 1
      timers[#timers + 1] = { c = c, id = timerId, at = T + s }
      return timerId
    end,
    queueEvent = function(...) push(c, ...) end,
    pullEvent = function(f)
      local ev = { coroutine.yield(f) }
      if ev[1] == "terminate" then error("Terminated", 0) end
      return unpack(ev)
    end,
    reboot = function() error("REBOOT", 0) end,
  }
  env.sleep = function(s)
    local t = env.os.startTimer(s)
    repeat local _, i = env.os.pullEvent("timer") until i == t
  end
  env.fs = {
    exists = function(p) return c.files[p] ~= nil end,
    makeDir = function(p) c.files[p] = c.files[p] or true end,
    delete = function(p) c.files[p] = nil end,
    move = function(a, b) assert(c.files[a] ~= nil and c.files[b] == nil, "fs.move") c.files[b] = c.files[a] c.files[a] = nil end,
    open = function(p, mode)
      if mode == "r" then
        if type(c.files[p]) ~= "string" then return nil end
        return { readAll = function() return c.files[p] end, close = function() end }
      end
      local buf = {}
      return { write = function(s) buf[#buf + 1] = s end, close = function() c.files[p] = table.concat(buf) end }
    end,
  }
  local rsapi = {
    getSides = function() return { unpack(SIDELIST) } end,
    setBundledOutput = function(s, m) c.bout[s] = m end,
    getBundledInput = function(s) return c.bin[s] or 0 end,
    setOutput = function(s, v) c.rout[s] = v end,
    getInput = function(s) return c.rin[s] or false end,
  }
  env.rs, env.redstone = rsapi, rsapi
  local modem = {
    open = function(ch) c.open[ch] = true end,
    closeAll = function() c.open = {} end,
    transmit = function(ch, reply, msg)
      assert(type(msg) == "string", "nur Strings funken")
      air[#air + 1] = { from = c, ch = ch, msg = msg }
      for _, o in ipairs(computers) do
        if o ~= c and o.running and o.modemSide and o.open[ch] and math.abs(o.x - c.x) <= 64 then
          push(o, "modem_message", o.modemSide, ch, reply, msg, math.abs(o.x - c.x))
        end
      end
    end,
  }
  local function ptype(s)
    if s == c.modemSide then return "modem" end
    if c.monitors[s] then return "monitor" end
    return nil
  end
  env.peripheral = {
    getType = ptype,
    isPresent = function(s) return ptype(s) ~= nil end,
    wrap = function(s)
      if s == c.modemSide then return modem end
      return c.monitors[s]
    end,
  }
  env.shell = { getRunningProgram = function() return "casa" end }
  env.write = function(s)
    s = tostring(s)
    local first = true
    for line in string.gmatch(s .. "\n", "(.-)\n") do
      if not first then c.term.setCursorPos(1, c.tdata.cy + 1) end
      c.term.write(line)
      first = false
    end
  end
  env.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    env.write(table.concat(parts, " ") .. "\n")
  end
  env.read = function()
    local s = ""
    while true do
      local e, a = env.os.pullEvent()
      if e == "char" then s = s .. a elseif e == "key" and a == 28 then return s end
    end
  end
  env.parallel = {
    waitForAny = function(...)
      local cos, filters, ev = {}, {}, {}
      for i, f in ipairs({ ... }) do cos[i] = coroutine.create(f) end
      while true do
        for i = 1, #cos do
          if filters[i] == nil or filters[i] == ev[1] or ev[1] == "terminate" then
            local ok, f = coroutine.resume(cos[i], unpack(ev))
            if not ok then error(f, 0) end
            filters[i] = f
            if coroutine.status(cos[i]) == "dead" then return i end
          end
        end
        ev = { coroutine.yield() }
      end
    end,
  }

  function c.boot(...)
    local args = { ... }
    c.queue, c.open, c.filter = {}, {}, nil
    local chunk = assert(loadfile(SRC, "t", env))
    c.co = coroutine.create(function() chunk(unpack(args)) end)
    c.running = true
    c.resume({})
  end
  function c.resume(ev)
    local ok, f = coroutine.resume(c.co, unpack(ev))
    if not ok then error("Computer " .. id .. " abgestuerzt: " .. tostring(f) .. "\n" .. debug.traceback(c.co)) end
    c.filter = f
    if coroutine.status(c.co) == "dead" then c.running = false end
  end
  return c
end

local function deliver()
  local busy = true
  local guard = 0
  while busy do
    busy = false
    guard = guard + 1
    assert(guard < 100000, "Ereignis-Schleife")
    for _, c in ipairs(computers) do
      if c.running and #c.queue > 0 then
        local ev = table.remove(c.queue, 1)
        busy = true
        if c.filter == nil or c.filter == ev[1] or ev[1] == "terminate" then c.resume(ev) end
      end
    end
  end
end
local function step(secs)
  local n = math.floor(secs / 0.05 + 0.5)
  for _ = 1, n do
    T = T + 0.05
    world = world + 0.05 / 50
    local keep = {}
    for _, t in ipairs(timers) do
      if t.at <= T + 1e-9 then
        if t.c.running then push(t.c, "timer", t.id) end
      else
        keep[#keep + 1] = t
      end
    end
    timers = keep
    deliver()
  end
end
local function key(c, k) push(c, "key", k) step(0.1) end
local function keysN(c, k, n) for _ = 1, n do key(c, k) end end
local function typeText(c, s)
  for i = 1, #s do push(c, "char", string.sub(s, i, i)) end
  step(0.1)
  key(c, 28)
end
local ENTER, DOWN, BACK = 28, 208, 14
local function find(d, text)
  for y = 1, d.h do
    local x = string.find(d.rows[y], text, 1, true)
    if x then return x, y end
  end
  return nil
end
local function dump(d) return table.concat(d.rows, "\n") end
local function touch(c, side, text)
  local x, y = find(c.mdata[side], text)
  assert(x, "'" .. text .. "' nicht auf Monitor:\n" .. dump(c.mdata[side]))
  push(c, "monitor_touch", side, x, y)
  step(0.2)
end
local passed = 0
local function check(cond, what)
  if not cond then error("FEHLER: " .. what, 2) end
  passed = passed + 1
  print("ok  " .. what)
end

------------------------------------------------------------------
local srv = newComputer(1, { x = 0, modem = "top", monitors = { right = { 39, 19 } } })
local node = newComputer(2, { x = 40, modem = "top", color = false })
local panel = newComputer(3, { x = 50, modem = "top", monitors = { left = { 18, 12 } } })
local far = newComputer(4, { x = 100, modem = "top" })
local tiny = newComputer(5, { x = 10, modem = "top", monitors = { back = { 7, 5 } } })

-- Ersteinrichtung ueber die echten Menues
srv.boot()
keysN(srv, ENTER, 5)
check(find(srv.tdata, "Zentrale") and find(srv.tdata, "Schalter"), "Zentrale: Einrichtung und Hauptmenue")
check(srv.files["/startup"] == 'shell.run("/casa")\n', "Autostart geschrieben")

node.boot()
key(node, DOWN) key(node, ENTER)
typeText(node, "keller")
key(node, ENTER) key(node, ENTER)
key(node, DOWN) key(node, ENTER)      -- Relay: Ja
key(node, ENTER)
step(1)
check(find(node.tdata, "Station keller"), "Station eingerichtet")

panel.boot()
keysN(panel, DOWN, 2) key(panel, ENTER)
keysN(panel, ENTER, 5)
step(6)
check(find(node.tdata, "verbunden"), "Station sieht die Zentrale")
check(find(panel.mdata.left, "Casa") and not find(panel.mdata.left, "Keine"), "Panel hat Verbindung")

-- Schalter "Licht" an Station keller, unten, weiss
key(srv, ENTER) key(srv, ENTER)
typeText(srv, "Licht")
key(srv, ENTER)
typeText(srv, "Wohnzimmer")
key(srv, DOWN) key(srv, ENTER)
check(find(srv.tdata, "Welche Seite"), "Station ist auswaehlbar")
key(srv, ENTER)
key(srv, DOWN) key(srv, ENTER)
check(find(srv.tdata, "Schalter bearbeiten"), "Schalter angelegt")
key(srv, ENTER)
step(0.5)
check(node.bout.bottom == 1, "Test-Umschalten erreicht die Station (weiss an)")
key(srv, BACK) key(srv, BACK)

touch(srv, "right", "Licht")
step(0.5)
check(node.bout.bottom == 0, "Touch am Monitor der Zentrale schaltet aus")
touch(panel, "left", "Licht")
step(1)
check(node.bout.bottom == 1, "Touch am Funk-Panel schaltet an")
local x, y = find(panel.mdata.left, "Licht")
check(panel.mdata.left.bgs[y][x] == COLORS.lime, "Kachel am Panel wird gruen (bestaetigt)")

-- Sensor per Lernen
key(srv, DOWN) key(srv, ENTER) key(srv, ENTER)
typeText(srv, "Tuer")
key(srv, ENTER) key(srv, ENTER)
check(find(srv.tdata, "Sensor lernen"), "Lernmodus offen")
node.bin.left = 2
push(node, "redstone")
step(0.5)
check(find(srv.tdata, "keller links orange"), "Leitung gelernt: keller links orange")
key(srv, ENTER) key(srv, BACK) key(srv, BACK)

-- Regel: Licht folgt Tuer
keysN(srv, DOWN, 2) key(srv, ENTER) key(srv, ENTER)
keysN(srv, DOWN, 2) key(srv, ENTER) key(srv, ENTER)
keysN(srv, DOWN, 3) key(srv, ENTER) key(srv, ENTER)
check(find(srv.tdata, "Tuer wechselt") and find(srv.tdata, "Licht folgt"), "Regel angelegt")
key(srv, BACK)
node.bin.left = 0
push(node, "redstone")
step(0.6)
check(node.bout.bottom == 0, "Regel: Tuer zu -> Licht aus")
node.bin.left = 2
push(node, "redstone")
step(0.6)
check(node.bout.bottom == 1, "Regel: Tuer auf -> Licht an")

-- Zeitregel: abends Licht aus
key(srv, DOWN) key(srv, ENTER)
keysN(srv, DOWN, 6) key(srv, ENTER)
key(srv, DOWN) key(srv, ENTER) key(srv, ENTER)
check(find(srv.tdata, "Abend") and find(srv.tdata, "Licht AUS"), "Abend-Regel angelegt")
key(srv, BACK) key(srv, BACK)
world = 18.5
step(5)
check(node.bout.bottom == 0, "Abend-Regel schaltet aus")

-- Schlafen ueberspringt die Nacht: Regel um 23:00 wird trotzdem nachgeholt
touch(panel, "left", "Licht")
step(1)
check(node.bout.bottom == 1, "wieder an")
world = 19.0 + 24
step(2)
world = 6.0 + 48
step(2)
check(node.bout.bottom == 1, "Zeitsprung ohne passende Regel aendert nichts")

-- Faelschen und Wiederholen von Funkpaketen
local cmdMsg
for i = #air, 1, -1 do
  if air[i].from == panel and string.find(air[i].msg, "s3:cmd", 1, true) then cmdMsg = air[i].msg break end
end
check(cmdMsg ~= nil, "Panel-Befehl mitgeschnitten")
touch(panel, "left", "Licht")
step(1)
check(node.bout.bottom == 0, "aus vor Angriffstest")
push(srv, "modem_message", "top", 4711, 4711, cmdMsg, 5)
step(1)
check(node.bout.bottom == 0, "wiederholtes altes Paket wird verworfen")
local forged = string.gsub(cmdMsg, "s2:on" .. "f", "s2:ont")
push(srv, "modem_message", "top", 4711, 4711, string.sub(cmdMsg, 1, 8) .. "{s1:fs6:hackers1:ts3:srvs1:ks3:cmdn1;" , 5)
push(srv, "modem_message", "top", 4711, 4711, forged, 5)
push(srv, "modem_message", "top", 4711, 4711, "3zzzzzzz{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{", 5)
push(srv, "modem_message", "top", 4711, 4711, 12345, 5)
step(1)
check(node.bout.bottom == 0 and srv.running, "kaputte und gefaelschte Pakete schaden nicht")

-- Relay: Station "garten" ausser Reichweite der Zentrale, erreichbar ueber keller
far.boot()
key(far, DOWN) key(far, ENTER)
typeText(far, "garten")
keysN(far, ENTER, 4)
step(10)
check(find(far.tdata, "verbunden"), "ferne Station ueber Relay verbunden")
check(far.files["/casa_data/outs"] ~= nil, "ferne Station hat ihren Zustand erhalten")

-- Neustart der Zentrale: Zustand bleibt
touch(panel, "left", "Licht")
step(3)
check(node.bout.bottom == 1, "an vor Neustart")
push(srv, "terminate")
step(0.5)
check(not srv.running, "Zentrale beendet")
check(node.bout.bottom == 1, "Station haelt den Ausgang ohne Zentrale")
step(20)
check(find(panel.mdata.left, "Keine"), "Panel zeigt fehlende Verbindung")
srv.boot()
step(8)
check(node.bout.bottom == 1, "nach Neustart der Zentrale weiter an")
check(find(panel.mdata.left, "Licht"), "Panel wieder verbunden")

-- Neustart der Station (Chunk neu geladen): Ausgang kommt sofort aus dem Cache
push(node, "terminate")
step(0.5)
node.bout = {}
node.boot()
check(node.bout.bottom == 1, "Station stellt Ausgang beim Start selbst wieder her")

-- Winziger 1x1-Monitor
tiny.boot()
keysN(tiny, DOWN, 2) key(tiny, ENTER)
keysN(tiny, ENTER, 5)
step(3)
check(find(tiny.mdata.back, "Licht"), "1x1-Monitor (7x5 Zeichen) zeigt Kachel")
touch(tiny, "back", "Licht")
step(1)
check(node.bout.bottom == 0, "1x1-Monitor schaltet")

-- Szene anlegen und am Panel starten
key(srv, DOWN) key(srv, DOWN) key(srv, ENTER) key(srv, ENTER)
typeText(srv, "Party")
keysN(srv, DOWN, 3) key(srv, ENTER)
check(find(srv.tdata, "AN"), "Szene: Licht = AN")
key(srv, BACK) key(srv, BACK)
step(1)
touch(panel, "left", "Szen")
touch(panel, "left", "Party")
step(1)
check(node.bout.bottom == 1, "Szene vom Panel gestartet")
touch(panel, "left", "Alles")
step(1)
check(node.bout.bottom == 0, "Alles aus")

print(string.format("\n%d Pruefungen bestanden.", passed))
print("\nMonitor der Zentrale (39x19):\n" .. dump(srv.mdata.right))
print("\nPanel (18x12):\n" .. dump(panel.mdata.left))
