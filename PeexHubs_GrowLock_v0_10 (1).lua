--[[
    PeexHubs | GrowLock v0.10   (untuk build Growlock.lua)

    Command (prefix default "/"):
      /cd <jumlah> [lock]     Fast drop lock. Tanpa [lock] = pakai lock terpilih
      /cdset <lock>           Pilih lock default untuk /cd
      /cdid <lock> <id>       Paksa ID item untuk sebuah lock
      /ctp [on|off]           Click TP: klik tile mana saja -> teleport (world.goTo bawaan game)
      /noclip [on|off]        Noclip = mode ghost game (terbang tembus block)
      /god [on|off]           God mode (lava/spike/api tidak melukai, client saja)
      /pinfo <nama|id>        Info player
      /sinfo                  Info server
      /af [on|off]            Auto Farm area 5x5 (place, break, collect)
      /afdelay <detik>        Delay hit/place (hit min 0.22 dtk, place min 0.2 dtk)
      /log                    Buka tab Update Log
      /afid <nama|id>         Block yang di-farm
      /gstatus                Cek status world / posisi / kamera
      /gt                     Buka/tutup GUI

    Nama lock: wl, dl, bgl, small, big, huge
    Skrip ini butuh executor dengan getgc, debug.getupvalue, dan getconnections.
]]

local genv = (getgenv and getgenv()) or _G
if genv.GrowlockToolsLoaded then
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "PeexHubs | GrowLock", Text = "Sudah aktif. Ketik /gt untuk panel.", Duration = 4,
        })
    end)
    return
end
genv.GrowlockToolsLoaded = true

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- LOCK YANG DIDUKUNG
----------------------------------------------------------------------
local LOCKS = {
    { key = "wl", name = "World Lock", alias = { "wl", "world", "worldlock" } },
    { key = "dl", name = "Diamond Lock", alias = { "dl", "diamond", "diamondlock" } },
    { key = "bgl", name = "Blue Gem Lock", alias = { "bgl", "bluegem", "bluegemlock", "blue" } },
    { key = "small", name = "Small Lock", alias = { "small", "sl", "smalllock" } },
    { key = "big", name = "Big Lock", alias = { "big", "biglock" } },
    { key = "huge", name = "Huge Lock", alias = { "huge", "hl", "hugelock" } },
}

----------------------------------------------------------------------
-- UPDATE LOG
----------------------------------------------------------------------
local UPDATE_LOG = {
    {
        version = "v0.10",
        date = "2026-11-26",
        notes = {
            "Auto Collect dikembalikan ke sistem awal v0.7: pindah ke drop, tunggu sistem collect game mengambilnya, lalu kembali ke posisi awal.",
            "Pengambilan tetap hanya untuk drop di kolom tile yang dipilih di grid 5x5.",
            "Fix Auto Farm v0.8 (paket hit/act, jeda minimal) tetap dipakai.",
        },
    },
    {
        version = "v0.9",
        date = "2026-11-26",
        notes = {
            "Auto Collect tidak lagi teleport. Player berjalan sungguhan lewat kontrol gerak (analog) milik game, lalu item/gems diambil oleh sistem collect game sendiri saat player berdiri di atasnya.",
            "Auto Collect hanya mengambil drop di kolom tile yang dipilih di grid 5x5.",
            "Setelah collect, player berjalan kembali ke posisi awal (tanpa teleport).",
            "Drop yang terhalang block atau di luar jangkauan jalan dilewati, tidak ditunggu.",
            "Kalau kontrol gerak game tidak ditemukan, Auto Collect dilewati dan muncul pemberitahuan (tidak jatuh kembali ke teleport).",
        },
    },
    {
        version = "v0.8",
        date = "2026-11-26",
        notes = {
            "Auto Farm: tidak lagi kena kick \"illegal packet\".",
            "Setiap pukulan sekarang mengirim paket hit dan paket pukul (act) seperti pukulan asli, jadi server melihat hit yang cukup sebelum block pecah.",
            "Block dipukul satu per satu sampai pecah (bukan bergantian antar sel), supaya damage tidak reset di server.",
            "Jeda minimal dipaksa: hit 0.22 dtk, place 0.2 dtk. Delay di bawah itu otomatis dinaikkan.",
            "Paket posisi sebelum place/break memakai posisi, kecepatan, dan flag asli dari game.",
            "Pindah ambil drop tidak lagi loncat langsung: bergerak 1 tile per langkah dan tidak masuk ke block.",
            "Auto Farm berhenti dengan pesan jelas kalau fungsi hit game tidak ditemukan.",
            "Tab Log baru dan command /log.",
        },
    },
    {
        version = "v0.7",
        notes = {
            "Auto Farm area 5x5 (place, break, collect) dengan pilihan block.",
            "Click TP, Noclip, God Mode, Fast Drop lock, tab Visual, dan Info player/server.",
        },
    },
}

----------------------------------------------------------------------
-- CONFIG (disimpan kalau executor punya writefile/readfile)
----------------------------------------------------------------------
local CONFIG_FILE = "PeexHubs_GrowLock.json"
local cfg = {
    prefix = "/",
    lock = "wl",
    amount = 1,
    lockIds = {},
    clickTp = false,
    shiftOnly = false,
    farmGrid = {},        -- sel 5x5 yang dipilih: ["dx,dy"] = true (relatif posisi pemain)
    farmId = 0,           -- id block yang di-farm
    farmDelay = 0.05,     -- jeda antar hit / place (detik, minimal 0.01)
    farmCollect = true,   -- ambil drop otomatis di area 5x5
    uiScale = 1,          -- skala GUI (0.6 - 1.6)
    winX = 0,             -- posisi window (offset dari tengah layar)
    winY = 0,
    noclip = false,       -- dinyalakan lagi otomatis saat script jalan
    god = false,
    visual = {},          -- id item (string) -> jumlah yang dimasukkan ke inventory lewat tab Visual
    visualAmount = 1,     -- jumlah per tekan di tab Visual (1-200)
}

local function LoadConfig()
    pcall(function()
        if readfile and isfile and isfile(CONFIG_FILE) then
            local data = HttpService:JSONDecode(readfile(CONFIG_FILE))
            if type(data) == "table" then
                for key, value in pairs(data) do
                    if cfg[key] ~= nil then
                        cfg[key] = value
                    end
                end
            end
        end
    end)
    if type(cfg.lockIds) ~= "table" then
        cfg.lockIds = {}
    end
    if type(cfg.farmGrid) ~= "table" then
        cfg.farmGrid = {}
    end
    cfg.farmDelay = math.max(0.01, tonumber(cfg.farmDelay) or 0.05)
    cfg.farmId = tonumber(cfg.farmId) or 0
    local gifts = {}
    if type(cfg.visual) == "table" then
        for key, value in pairs(cfg.visual) do
            -- format lama (slot -> id) dibuang; format baru: id -> jumlah
            if tonumber(key) and type(value) == "number" and value > 0 then
                gifts[tostring(math.floor(tonumber(key)))] = math.min(200, math.floor(value))
            end
        end
    end
    cfg.visual = gifts
    cfg.visualAmount = math.clamp(math.floor(tonumber(cfg.visualAmount) or 1), 1, 200)
    cfg.uiScale = math.clamp(tonumber(cfg.uiScale) or 1, 0.6, 1.6)
    cfg.winX = tonumber(cfg.winX) or 0
    cfg.winY = tonumber(cfg.winY) or 0
end

local function SaveConfig()
    pcall(function()
        if writefile then
            writefile(CONFIG_FILE, HttpService:JSONEncode(cfg))
        end
    end)
end

LoadConfig()

----------------------------------------------------------------------
-- UTIL
----------------------------------------------------------------------
local function Notify(message)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "PeexHubs | GrowLock", Text = tostring(message), Duration = 4,
        })
    end)
end

local function Trim(text)
    return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

local getgcFn = getgc or (debug and debug.getgc)
local getupvalueFn = (debug and debug.getupvalue) or getupvalue

local function Safe(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c = pcall(fn, ...)
    if ok then
        return a, b, c
    end
    return nil
end

local getupvaluesFn = (debug and debug.getupvalues) or getupvalues

local function ReadUpvalues(fn, limit)
    local list, count = {}, 0
    if type(fn) ~= "function" then
        return list, 0
    end
    limit = limit or 255
    if getupvalueFn then
        for i = 1, limit do
            local ok, value = pcall(getupvalueFn, fn, i)
            if not ok then
                break
            end
            list[i] = value
            count = i
        end
        -- executor yang tidak error di indeks berlebih mengisi nil: buang ekor nil
        while count > 0 and list[count] == nil do
            count -= 1
        end
    end
    if count == 0 and getupvaluesFn then
        local ok, all = pcall(getupvaluesFn, fn)
        if ok and type(all) == "table" then
            for key, value in pairs(all) do
                if type(key) == "number" and key >= 1 and key <= limit then
                    list[key] = value
                    if key > count then
                        count = key
                    end
                end
            end
        end
    end
    return list, count
end

local cache = {}
local function ScanGc(name, check)
    local cached = cache[name]
    if cached and check(cached) then
        return cached
    end
    if not getgcFn then
        return nil
    end
    for _, obj in ipairs(getgcFn(true)) do
        if type(obj) == "table" then
            local ok, valid = pcall(check, obj)
            if ok and valid then
                cache[name] = obj
                return obj
            end
        end
    end
    return nil
end

-- Tabel world game (enter, dropOk, goTo, name, w, h, fg, ghost, backpackNow)
local function IsWorldTable(t)
    return type(rawget(t, "enter")) == "function"
        and type(rawget(t, "dropOk")) == "function"
        and type(rawget(t, "goTo")) == "function"
end

-- Sudah "di dalam world" = ukuran + grid block sudah terisi (nama bisa saja kosong)
local function InWorld(world)
    return type(world) == "table"
        and type(rawget(world, "w")) == "number"
        and type(rawget(world, "h")) == "number"
        and type(rawget(world, "fg")) == "table"
end

local worldScanAt = 0
local function FindWorld()
    local cached = cache.world
    if cached and InWorld(cached) and IsWorldTable(cached) then
        return cached
    end
    if not getgcFn then
        return cached
    end
    -- jangan scan getgc terus-menerus kalau memang belum di world
    if cached and os.clock() - worldScanAt < 1.5 then
        return cached
    end
    worldScanAt = os.clock()
    local fallback = nil
    for _, obj in ipairs(getgcFn(true)) do
        if type(obj) == "table" then
            local ok, valid = pcall(IsWorldTable, obj)
            if ok and valid then
                if InWorld(obj) then
                    cache.world = obj
                    return obj
                end
                fallback = fallback or obj
            end
        end
    end
    if fallback then
        cache.world = fallback
    end
    return fallback
end

-- Tabel inventory game (onDrop, canDrop, isWorn)
local function FindInventory()
    return ScanGc("inventory", function(t)
        return type(rawget(t, "onDrop")) == "function"
            and type(rawget(t, "canDrop")) == "function"
            and type(rawget(t, "isWorn")) == "function"
    end)
end

-- Tabel "env" yang dikirim game ke modul UI (Trade): berisi inv, invUI, worn(), me(), PX.
-- Semua field publik, jadi tidak perlu upvalue / debug.info.
local function FindGameEnv()
    return ScanGc("env", function(t)
        return type(rawget(t, "worn")) == "function"
            and type(rawget(t, "me")) == "function"
            and type(rawget(t, "inv")) == "table"
            and type(rawget(t, "invUI")) == "table"
    end)
end

-- Tabel API menu game (profile, level, playerLevel, gems)
local function FindApi()
    return ScanGc("api", function(t)
        return type(rawget(t, "profile")) == "function"
            and type(rawget(t, "playerLevel")) == "function"
            and type(rawget(t, "level")) == "function"
    end)
end

-- Tabel "others" game (pemain lain di world)
local function FindOthers()
    return ScanGc("others", function(t)
        return type(rawget(t, "list")) == "function"
            and type(rawget(t, "playerAt")) == "function"
    end)
end

local ItemDB = nil
local function GetItemDB()
    if ItemDB then
        return ItemDB
    end
    local ok, result = pcall(function()
        local shared = ReplicatedStorage:WaitForChild("Shared", 5)
        return require(shared:WaitForChild("ItemDB", 5))
    end)
    if ok and type(result) == "table" then
        ItemDB = result
    end
    return ItemDB
end

local function CurrentWorldName()
    local world = FindWorld()
    if not InWorld(world) then
        return ""
    end
    local name = rawget(world, "name")
    return (type(name) == "string" and name ~= "") and name or "?"
end

-- Posisi float (x, y, arah). Dibaca dari upvalue fungsi milik game:
--  B) world.goTo  -> dua angka pertama = posisi pemain (x, kaki y)  [utama]
--  A) inventory.canDrop / onDrop -> cadangan
-- Hasil divalidasi terhadap ukuran world supaya tidak salah baca.
local function ValidPos(world, x, y)
    if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then
        return false
    end
    local w, h = rawget(world, "w"), rawget(world, "h")
    if type(w) == "number" and type(h) == "number" then
        return x >= 0 and x <= w + 1 and y >= 0 and y <= h + 3
    end
    return true
end

-- Variabel posisi game (x, y kaki) adalah upvalue milik banyak fungsi. Dibaca dari
-- beberapa fungsi sekaligus lalu dicocokkan supaya tidak salah indeks:
--  1) world.goTo        -> numerik pertama: x, kedua: y
--  2) world.displayHere -> numerik pertama: y, kedua: x
--  3) pengirim PlayerPos (FireServer tiap 0.033 detik) -> [waktu, x, y, vx, vy, hadap]
--  4) inventory.canDrop / onDrop (cadangan lama)
-- Posisi dari paket PlayerPos yang dikirim game tiap 0.033 detik:
-- FireServer(x, y, vx, vy, flags, timestamp). flags: bit1 = hadap kanan, bit2 = di tanah.
-- Ditangkap lewat hook, jadi tidak bergantung pada upvalue / getgc sama sekali.
local PosHook = { last = nil, how = "belum terpasang", count = 0 }

local function PosRecord(x, y, vx, vy, flags)
    if type(x) == "number" and type(y) == "number" and x == x and y == y then
        PosHook.last = { x = x, y = y, vx = vx, vy = vy, flags = flags, t = os.clock() }
        PosHook.count += 1
    end
end

local function InstallPosHook()
    local wrap = newcclosure or function(f) return f end
    if hookmetamethod and getnamecallmethod then
        local okHook = pcall(function()
            local old
            old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
                if getnamecallmethod() == "FireServer" and typeof(self) == "Instance" and self.Name == "PlayerPos" then
                    pcall(PosRecord, ...)
                end
                return old(self, ...)
            end))
        end)
        if okHook then
            PosHook.how = "hookmetamethod"
            return true
        end
    end
    if hookfunction then
        local okHook = pcall(function()
            local remote = Instance.new("RemoteEvent")
            local old
            old = hookfunction(remote.FireServer, wrap(function(self, ...)
                if typeof(self) == "Instance" and self.Name == "PlayerPos" then
                    pcall(PosRecord, ...)
                end
                return old(self, ...)
            end))
        end)
        if okHook then
            PosHook.how = "hookfunction"
            return true
        end
    end
    PosHook.how = "tidak didukung executor"
    return false
end
pcall(InstallPosHook)

local posDebug = { sources = {}, picked = "-" }
local posSender = nil
local posSenderTry = 0

local function NumericUpvalues(fn, limit)
    local ups, count = ReadUpvalues(fn, limit)
    local nums = {}
    for i = 1, count do
        local value = ups[i]
        if type(value) == "number" and value == value then
            table.insert(nums, value)
        end
    end
    return nums
end

local function FindPosSender(world)
    if posSender then
        return posSender
    end
    if not getgcFn or os.clock() - posSenderTry < 6 then
        return nil
    end
    posSenderTry = os.clock()
    for _, fn in ipairs(getgcFn(true)) do
        if type(fn) == "function" then
            local ups, count = ReadUpvalues(fn, 16)
            local hasRemote, hasWorld = false, false
            for i = 1, count do
                local value = ups[i]
                if value == world then
                    hasWorld = true
                elseif typeof(value) == "Instance" and value.Name == "PlayerPos" then
                    hasRemote = true
                end
            end
            if hasRemote and hasWorld then
                posSender = fn
                return fn
            end
        end
    end
    return nil
end

local function GetGridState()
    local world = FindWorld()
    if not InWorld(world) then
        return nil, "Belum masuk world"
    end

    local facing = nil
    local found = {}
    local function add(name, x, y)
        if ValidPos(world, x, y) then
            table.insert(found, { name = name, x = x, y = y })
        end
    end

    -- sumber 0: fungsi me() milik game (posisi langsung, tanpa upvalue)
    local envEntry = nil
    local env = FindGameEnv()
    if env then
        local okMe, mx, my = pcall(env.me)
        if okMe then
            add("game.me", mx, my)
            envEntry = found[#found]
            if envEntry and (envEntry.x ~= mx or envEntry.y ~= my) then
                envEntry = nil
            end
        end
    end

    -- sumber utama: paket PlayerPos yang baru dikirim game
    local hookEntry, hookFresh = nil, false
    local last = PosHook.last
    if last and os.clock() - last.t < 3 then
        add("PlayerPos hook", last.x, last.y)
        hookEntry = found[#found]
        hookFresh = hookEntry ~= nil
        if hookFresh and type(last.flags) == "number" then
            facing = (last.flags % 2 == 1) and 1 or -1
        end
    end

    if type(world.goTo) == "function" then
        local n = NumericUpvalues(world.goTo, 24)
        add("goTo", n[1], n[2])
    end
    if type(rawget(world, "displayHere")) == "function" then
        local n = NumericUpvalues(world.displayHere, 24)
        add("displayHere", n[2], n[1])
    end
    -- sumber ketiga hanya dicari kalau dua sumber pertama belum sepakat
    local agreed = false
    for i = 1, #found do
        for j = i + 1, #found do
            if math.abs(found[i].x - found[j].x) < 1e-4 and math.abs(found[i].y - found[j].y) < 1e-4 then
                agreed = true
            end
        end
    end
    if not agreed and not hookFresh and not envEntry then
        local sender = FindPosSender(world)
        if sender then
            local n = NumericUpvalues(sender, 24)
            add("PlayerPos", n[2], n[3])
            if type(n[6]) == "number" and n[6] ~= 0 then
                facing = n[6] > 0 and 1 or -1
            end
        end
    end

    posDebug.sources = found
    local best = nil
    for i = 1, #found do
        for j = i + 1, #found do
            if not best and math.abs(found[i].x - found[j].x) < 1e-4 and math.abs(found[i].y - found[j].y) < 1e-4 then
                best = found[i]
            end
        end
    end
    best = envEntry or hookEntry or best or found[1]

    if not facing then
        local inv = FindInventory()
        if inv and type(inv.canDrop) == "function" then
            local up = ReadUpvalues(inv.canDrop, 12)
            if type(up[3]) == "number" then
                facing = (up[3] >= 0) and 1 or -1
            end
        end
    end
    facing = facing or 1

    if best then
        posDebug.picked = best.name .. (agreed and " (cocok)" or "")
        return best.x, best.y, facing
    end

    -- cadangan lama: inventory
    local inv = FindInventory()
    if inv and type(inv.canDrop) == "function" and type(inv.onDrop) == "function" then
        local canDropUp = ReadUpvalues(inv.canDrop, 12)
        local x = canDropUp[2]
        local dropUp, dropCount = ReadUpvalues(inv.onDrop, 40)
        local nums = {}
        for i = 1, dropCount do
            if type(dropUp[i]) == "number" then
                table.insert(nums, dropUp[i])
            end
        end
        local y = nums[3]
        if ValidPos(world, x, y) then
            posDebug.picked = "inventory"
            return x, y, facing
        end
    end
    posDebug.picked = "-"
    return nil, "Posisi pemain tidak terbaca (executor perlu getgc + debug.getupvalue)"
end

local function GetTile()
    local x, y = GetGridState()
    if not x then
        return nil
    end
    return math.floor(x), math.floor(y - 0.475)
end

----------------------------------------------------------------------
-- FAST DROP  (/cd)
-- Memakai inventory.onDrop milik game: validasi, kurangi inventory, dan kirim
-- Net.drop.send semuanya dikerjakan game sendiri.
----------------------------------------------------------------------
local function ParseLock(text)
    local s = (tostring(text or ""):lower():gsub("[%s_%-]", ""))
    if s == "" then
        return nil
    end
    for _, lock in ipairs(LOCKS) do
        if s == lock.key or s == (lock.name:lower():gsub("%s", "")) then
            return lock
        end
        for _, alias in ipairs(lock.alias) do
            if s == alias then
                return lock
            end
        end
    end
    return nil
end

local function LockByKey(key)
    for _, lock in ipairs(LOCKS) do
        if lock.key == key then
            return lock
        end
    end
    return LOCKS[1]
end

local function ItemName(id)
    local db = GetItemDB()
    local item = db and db[id]
    return type(item) == "table" and type(item.name) == "string" and item.name or nil
end

local function FindItemIdByName(name)
    local db = GetItemDB()
    if not db then
        return nil
    end
    local want = name:lower()
    local partialId, partialLen = nil, math.huge
    for id, item in pairs(db) do
        if type(id) == "number" and type(item) == "table" and type(item.name) == "string" then
            local lower = item.name:lower()
            if lower == want then
                return id
            end
            if lower:find(want, 1, true) and #lower < partialLen then
                partialId, partialLen = id, #lower
            end
        end
    end
    return partialId
end

local lockCache = {}
local function ResolveLock(lock)
    local override = cfg.lockIds[lock.key]
    if type(override) == "number" then
        return override
    end
    if lockCache[lock.key] then
        return lockCache[lock.key]
    end
    local id = FindItemIdByName(lock.name)
    if id then
        lockCache[lock.key] = id
    end
    return id
end

-- Jumlah item di backpack (world.backpackNow -> { [slot] = { id, n } })
local function CountItem(id)
    local world = FindWorld()
    if not world or type(rawget(world, "backpackNow")) ~= "function" then
        return nil
    end
    local ok, bag = pcall(world.backpackNow)
    if not ok or type(bag) ~= "table" then
        return nil
    end
    local total = 0
    for _, slot in pairs(bag) do
        if type(slot) == "table" then
            local slotId = slot[1] or slot.id
            if slotId == id then
                total = total + (slot[2] or slot.n or 0)
            end
        end
    end
    return total
end

local dropBusy = false
local lastDropAt = 0
local STACK_MAX = 200 -- batas item per slot di inventory game

local function DropLock(amount, lock)
    lock = lock or LockByKey(cfg.lock)
    if dropBusy then
        Notify("Tunggu sebentar, drop sebelumnya belum selesai.")
        return false
    end
    if CurrentWorldName() == "" then
        Notify("Kamu belum berada di dalam world.")
        return false
    end
    local id = ResolveLock(lock)
    if not id then
        Notify(lock.name .. " tidak ditemukan di ItemDB. Pakai " .. cfg.prefix .. "cdid " .. lock.key .. " <id>")
        return false
    end
    local have = CountItem(id)
    if have ~= nil and have <= 0 then
        Notify("Kamu tidak punya " .. lock.name .. ".")
        return false
    end
    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then
        Notify("Jumlah drop tidak valid.")
        return false
    end
    if have and amount > have then
        amount = have
    end

    local inv = FindInventory()
    if not inv or type(inv.onDrop) ~= "function" then
        Notify("Inventory game tidak ditemukan (executor perlu getgc).")
        return false
    end
    local okCan, canDrop = pcall(inv.canDrop)
    if okCan and canDrop == false then
        Notify("Tidak bisa drop di posisi ini!")
        return false
    end

    dropBusy = true
    task.spawn(function()
        local before = CountItem(id)
        local remaining = amount
        while remaining > 0 do
            local wait = 0.34 - (os.clock() - lastDropAt)
            if wait > 0 then
                task.wait(wait)
            end
            local n = math.min(remaining, STACK_MAX)
            lastDropAt = os.clock()
            local ok, err = pcall(inv.onDrop, id, n)
            if not ok then
                Notify("Drop gagal: " .. tostring(err))
                break
            end
            remaining = remaining - n
        end
        task.wait(0.5)
        local after = CountItem(id)
        if before ~= nil and after ~= nil then
            local dropped = before - after
            if dropped > 0 then
                Notify(string.format("Drop %d %s (sisa %d)", dropped, lock.name, after))
            else
                Notify("Jumlah " .. lock.name .. " tidak berkurang. Mungkin diblok game (cek posisi/lock world).")
            end
        else
            Notify("Drop " .. tostring(amount) .. " " .. lock.name .. " dikirim.")
        end
        dropBusy = false
    end)
    return true
end

----------------------------------------------------------------------
-- CLICK TP
-- Klik layar -> tile memakai rumus yang sama dengan klik bawaan game:
--   tile = floor(kamera + (posisiKlik - frameDunia) / skala / ukuranTile)
-- Teleport memakai world.goTo bawaan game.
----------------------------------------------------------------------
----------------------------------------------------------------------
-- NOCLIP  (= mode GHOST milik game)
-- Di Growlock.lua, world.ghost = true membuat pemain terbang bebas tembus block
-- (kontrol: kiri/kanan, lompat = naik, bawah = turun). Tiap frame client game
-- mereset ghost jadi false kalau Roles.isStaff(UserId) false, jadi selama noclip
-- aktif isStaff dibungkus supaya mengembalikan true khusus untuk akun kamu
-- (hanya di sisi client; server tetap menentukan sendiri).
----------------------------------------------------------------------
local Noclip = { on = false, conn = nil, roles = nil, orig = nil }

function Noclip.Stop()
    if not Noclip.on then
        return false
    end
    Noclip.on = false
    if Noclip.conn then
        Noclip.conn:Disconnect()
        Noclip.conn = nil
    end
    if Noclip.roles and Noclip.orig then
        pcall(function()
            if setreadonly then
                setreadonly(Noclip.roles, false)
            end
            rawset(Noclip.roles, "isStaff", Noclip.orig)
        end)
    end
    Noclip.roles, Noclip.orig = nil, nil
    if Noclip.ShowDown then
        Noclip.ShowDown(false)
    end
    local world = FindWorld()
    if world then
        pcall(function()
            world.ghost = false
        end)
    end
    Notify("Noclip: mati")
    return true
end

function Noclip.Start()
    if Noclip.on then
        return true
    end
    local world = FindWorld()
    if not InWorld(world) then
        Notify("Noclip: masuk world dulu.")
        return false
    end
    local okRoles, roles = pcall(function()
        local shared = ReplicatedStorage:WaitForChild("Shared", 5)
        return require(shared:WaitForChild("Roles", 5))
    end)
    if not okRoles or type(roles) ~= "table" or type(roles.isStaff) ~= "function" then
        Notify("Noclip: modul Roles game tidak ditemukan.")
        return false
    end
    local orig = roles.isStaff
    local myId = Player.UserId
    local function wrapper(userId, ...)
        if Noclip.on and userId == myId then
            return true
        end
        return orig(userId, ...)
    end
    pcall(function()
        if setreadonly then
            setreadonly(roles, false)
        end
        rawset(roles, "isStaff", wrapper)
    end)
    if roles.isStaff ~= wrapper then
        Notify("Noclip: gagal memasang (modul Roles terkunci di executor ini).")
        return false
    end
    Noclip.roles, Noclip.orig, Noclip.on = roles, orig, true
    pcall(function()
        world.ghost = true
    end)
    Noclip.conn = RunService.Heartbeat:Connect(function()
        local w = FindWorld()
        if w and rawget(w, "ghost") ~= true then
            pcall(function()
                w.ghost = true
            end)
        end
    end)
    if Noclip.ShowDown then
        Noclip.ShowDown(true)
    end
    Notify("Noclip: AKTIF. Tombol Turun muncul di layar (tahan untuk turun).")
    return true
end


-- Turun satu tile ke bawah (mode ghost tidak ada tabrakan, jadi goTo aman)
function Noclip.StepDown()
    local world = FindWorld()
    if not InWorld(world) then
        return false
    end
    local x, y = GetGridState()
    if not x then
        return false
    end
    local tx, ty = math.floor(x), math.floor(y - 0.475)
    if ty + 1 >= world.h then
        return false
    end
    return (pcall(world.goTo, tx, ty + 1))
end

do
    local rawStart, rawStop = Noclip.Start, Noclip.Stop
    function Noclip.Start(...)
        local ok = rawStart(...)
        if ok then
            cfg.noclip = true
            SaveConfig()
        end
        return ok
    end
    function Noclip.Stop(...)
        rawStop(...)
        cfg.noclip = false
        SaveConfig()
    end
end

local cam = nil
local camError = nil

local function FindCameraScored()
    if cam then
        return cam
    end
    if not getconnections or not getupvalueFn then
        camError = "executor tidak punya getconnections/getupvalue"
        return nil
    end
    local px, py = GetGridState()
    if not px then
        camError = "posisi karakter belum terbaca (masuk world dulu)"
        return nil
    end
    local okConn, conns = pcall(getconnections, UserInputService.InputBegan)
    if not okConn or type(conns) ~= "table" then
        camError = "getconnections gagal"
        return nil
    end

    local best, bestScore = nil, math.huge
    for _, conn in ipairs(conns) do
        local fn = conn.Function
        if type(fn) == "function" then
            local ups, count = ReadUpvalues(fn)
            local frames, scales, numbers = {}, {}, {}
            for i = 1, count do
                local value = ups[i]
                if typeof(value) == "Instance" then
                    if value:IsA("UIScale") then
                        table.insert(scales, { i = i, o = value })
                    elseif value:IsA("GuiObject") and value.AbsoluteSize.X > 100 and value.AbsoluteSize.Y > 80 then
                        table.insert(frames, { i = i, o = value })
                    end
                elseif type(value) == "number" and value == value and math.abs(value) < 100000 then
                    table.insert(numbers, { i = i, v = value })
                end
            end
            if #frames > 0 and #scales > 0 and #numbers >= 3 and #numbers <= 120 then
                for _, f in ipairs(frames) do
                    for _, sc in ipairs(scales) do
                        if sc.o.Scale > 0 then
                            local halfW = f.o.AbsoluteSize.X / sc.o.Scale / 2
                            local halfH = f.o.AbsoluteSize.Y / sc.o.Scale / 2
                            for _, t in ipairs(numbers) do
                                if t.v >= 4 and t.v <= 512 then
                                    for _, a in ipairs(numbers) do
                                        local errX = math.abs(a.v + halfW / t.v - px)
                                        if a.i ~= t.i and errX < 6 then
                                            for _, b in ipairs(numbers) do
                                                if b.i ~= t.i and b.i ~= a.i then
                                                    local errY = math.abs(b.v + halfH / t.v - py)
                                                    if errY < 8 and errX + errY < bestScore then
                                                        bestScore = errX + errY
                                                        best = {
                                                            fn = fn, iX = a.i, iY = b.i, iT = t.i,
                                                            iFrame = f.i, iScale = sc.i,
                                                        }
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if best then
        cam = best
        camError = nil
        return cam
    end
    camError = "kamera tidak cocok (berdiri di tengah world, jauh dari tepi, lalu coba lagi)"
    return nil
end

-- Handler klik bawaan game: upvalue berurutan ... frame, ItemDB, frame dunia, UIScale,
-- kameraX, ukuranTile, kameraY ... Dikenali dari upvalue world + UIScale. Tidak butuh
-- posisi pemain sama sekali.
local function FindCameraOrdered()
    if not getconnections or not getupvalueFn then
        return nil, "executor tidak punya getconnections/getupvalue"
    end
    local world = FindWorld()
    if not world then
        return nil, "tabel world tidak ketemu"
    end
    local okConn, conns = pcall(getconnections, UserInputService.InputBegan)
    if not okConn or type(conns) ~= "table" then
        return nil, "getconnections gagal"
    end
    local w, h = rawget(world, "w"), rawget(world, "h")
    for _, conn in ipairs(conns) do
        local fn = conn.Function
        if type(fn) == "function" then
            local ups, count = ReadUpvalues(fn, 80)
            local hasWorld, scaleIdx = false, nil
            for i = 1, count do
                local value = ups[i]
                if value == world then
                    hasWorld = true
                elseif not scaleIdx and typeof(value) == "Instance" and value:IsA("UIScale") then
                    scaleIdx = i
                end
            end
            if hasWorld and scaleIdx then
                local frameIdx = nil
                for i = scaleIdx - 1, 1, -1 do
                    local value = ups[i]
                    if typeof(value) == "Instance" and value:IsA("GuiObject") and value.AbsoluteSize.X > 100 then
                        frameIdx = i
                        break
                    end
                end
                local nums = {}
                for i = scaleIdx + 1, count do
                    if type(ups[i]) == "number" then
                        table.insert(nums, i)
                        if #nums == 3 then
                            break
                        end
                    end
                end
                if frameIdx and #nums == 3 then
                    local cx, size, cy = ups[nums[1]], ups[nums[2]], ups[nums[3]]
                    local frame, scale = ups[frameIdx], ups[scaleIdx]
                    if size >= 4 and size <= 512 and scale.Scale > 0 then
                        local ccx = cx + frame.AbsoluteSize.X / scale.Scale / 2 / size
                        local ccy = cy + frame.AbsoluteSize.Y / scale.Scale / 2 / size
                        if type(w) == "number" and type(h) == "number"
                            and ccx > -4 and ccx < w + 4 and ccy > -4 and ccy < h + 4 then
                            return {
                                fn = fn, iX = nums[1], iT = nums[2], iY = nums[3],
                                iFrame = frameIdx, iScale = scaleIdx,
                            }
                        end
                    end
                end
            end
        end
    end
    return nil, "handler klik game tidak cocok"
end

local function FindCameraUpvalues()
    if cam then
        return cam
    end
    local found, why = FindCameraOrdered()
    if found then
        cam = found
        camError = nil
        return cam
    end
    local scored = FindCameraScored()
    if scored then
        return scored
    end
    camError = tostring(why) .. "; " .. tostring(camError)
    return nil
end

-- Kamera dari tabel world.view = { kameraX, kameraY, lebarTile, tinggiTile } yang
-- diperbarui game tiap frame (field publik, tanpa upvalue). Ukuran tile = Assets.TileSize * 2.
local worldGuiCache, worldScaleCache = nil, nil
local function FindWorldGui()
    if worldGuiCache and worldGuiCache.Parent and worldScaleCache and worldScaleCache.Parent then
        return worldGuiCache, worldScaleCache
    end
    for _, obj in ipairs(PlayerGui:GetDescendants()) do
        if obj.Name == "World" and obj:IsA("GuiObject") then
            local scale = obj:FindFirstChildWhichIsA("UIScale", true)
            if scale then
                worldGuiCache, worldScaleCache = obj, scale
                return obj, scale
            end
        end
    end
    return nil
end

local tileSizeCache = nil
local function GameTileSize()
    if tileSizeCache then
        return tileSizeCache
    end
    local ok, value = pcall(function()
        local shared = ReplicatedStorage:WaitForChild("Shared", 3)
        return require(shared:WaitForChild("Assets", 3)).TileSize
    end)
    if ok and type(value) == "number" and value > 0 then
        tileSizeCache = value * 2
    end
    return tileSizeCache
end

local function ViewCam()
    local world = FindWorld()
    local view = world and rawget(world, "view")
    if type(view) ~= "table" or type(view[1]) ~= "number" or type(view[2]) ~= "number" then
        return nil
    end
    local gui, scale = FindWorldGui()
    if not gui or scale.Scale <= 0 then
        return nil
    end
    local size = GameTileSize()
    if not size and type(view[3]) == "number" and view[3] > 0 then
        size = gui.AbsoluteSize.X / scale.Scale / view[3]
    end
    if not size or size <= 0 then
        return nil
    end
    return view[1], view[2], size, gui, scale
end

local function FindCamera()
    if ViewCam() then
        camError = nil
        return { view = true }
    end
    local found = FindCameraUpvalues()
    if found then
        return found
    end
    camError = "world.view/UI World tidak ketemu; " .. tostring(camError)
    return nil
end

local function ScreenToTileLegacy(position)
    local c = FindCameraUpvalues()
    if not c then
        return nil
    end
    local ups = ReadUpvalues(c.fn)
    local cx, cy, size = ups[c.iX], ups[c.iY], ups[c.iT]
    local frame, scale = ups[c.iFrame], ups[c.iScale]
    if type(cx) ~= "number" or type(cy) ~= "number" or type(size) ~= "number" or size <= 0
        or typeof(frame) ~= "Instance" or typeof(scale) ~= "Instance" or scale.Scale <= 0 then
        cam = nil
        camError = "kalibrasi kamera hilang, klik lagi"
        return nil
    end
    -- kalibrasi salah (mis. dihitung saat kamera nempel tepi world)? ulangi di klik berikutnya
    local px, py = GetGridState()
    if px then
        local ccx = cx + frame.AbsoluteSize.X / scale.Scale / 2 / size
        local ccy = cy + frame.AbsoluteSize.Y / scale.Scale / 2 / size
        if math.abs(ccx - px) > 14 or math.abs(ccy - py) > 14 then
            cam = nil
            camError = "kalibrasi kamera melenceng, klik lagi"
            return nil
        end
    end
    local rel = (Vector2.new(position.X, position.Y) - frame.AbsolutePosition) / scale.Scale
    return math.floor(cx + rel.X / size), math.floor(cy + rel.Y / size)
end

local function ScreenToTile(position)
    local cx, cy, size, gui, scale = ViewCam()
    if cx then
        local rel = (Vector2.new(position.X, position.Y) - gui.AbsolutePosition) / scale.Scale
        return math.floor(cx + rel.X / size), math.floor(cy + rel.Y / size)
    end
    return ScreenToTileLegacy(position)
end

local clickConn = nil

local function TeleportToTile(tx, ty)
    local world = FindWorld()
    if not InWorld(world) then
        Notify("Belum masuk world.")
        return
    end
    local w, h, fg = rawget(world, "w"), rawget(world, "h"), rawget(world, "fg")
    if tx < 0 or ty < 0 or tx >= w or ty >= h then
        Notify("Di luar batas world.")
        return
    end
    if not Noclip.on then
        local row = type(fg) == "table" and fg[ty] or nil
        local cell = type(row) == "table" and row[tx] or nil
        if cell and cell ~= 0 then
            Notify("Tujuan tertutup block.")
            return
        end
    end
    local ok, err = pcall(world.goTo, tx, ty)
    if ok then
        Notify(string.format("TP ke %d, %d", tx, ty))
    else
        Notify("TP gagal: " .. tostring(err))
    end
end

local function OnClick(input, processed)
    if processed or not cfg.clickTp then
        return
    end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if cfg.shiftOnly and not (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)) then
        return
    end
    local tx, ty = ScreenToTile(input.Position)
    if not tx then
        Notify("Click TP: " .. tostring(camError or "posisi klik tidak terbaca"))
        return
    end
    TeleportToTile(tx, ty)
end

local function SetClickTp(on)
    if on then
        if not FindCamera() then
            Notify("Click TP belum siap: " .. tostring(camError))
            -- tetap diaktifkan; kalibrasi dicoba lagi di setiap klik
        end
        if not clickConn then
            clickConn = UserInputService.InputBegan:Connect(OnClick)
        end
        cfg.clickTp = true
    else
        cfg.clickTp = false
        if clickConn then
            clickConn:Disconnect()
            clickConn = nil
        end
    end
    SaveConfig()
    Notify("Click TP: " .. (cfg.clickTp and "AKTIF" or "mati"))
end

----------------------------------------------------------------------
-- GOD MODE
-- Flag "hurts"/"deadly" di ItemDB dimatikan (lava, spike, api) dan event
-- "Burned" dari server diabaikan. Hanya di sisi client; tidak berlaku untuk
-- kick / ban / aksi staff.
----------------------------------------------------------------------
local godOn = false
local godSaved = {}
local godConns = {}

local function StopGod()
    if not godOn then
        return
    end
    for _, saved in ipairs(godSaved) do
        pcall(function()
            rawset(saved.item, saved.key, saved.value)
        end)
    end
    godSaved = {}
    for _, conn in ipairs(godConns) do
        pcall(function()
            conn:Enable()
        end)
    end
    godConns = {}
    godOn = false
    cfg.god = false
    SaveConfig()
    Notify("God mode: mati")
end

local function StartGod()
    if godOn then
        return
    end
    local db = GetItemDB()
    if not db then
        Notify("ItemDB game tidak ditemukan!")
        return
    end
    godSaved = {}
    for _, item in pairs(db) do
        if type(item) == "table" then
            for _, key in ipairs({ "hurts", "deadly" }) do
                if rawget(item, key) then
                    table.insert(godSaved, { item = item, key = key, value = rawget(item, key) })
                    pcall(function()
                        if setreadonly then
                            setreadonly(item, false)
                        end
                        rawset(item, key, false)
                    end)
                end
            end
        end
    end
    local remotes = ReplicatedStorage:FindFirstChild("WorldRemotes")
    local burned = remotes and remotes:FindFirstChild("Burned")
    if burned and getconnections then
        local okConn, conns = pcall(getconnections, burned.OnClientEvent)
        if okConn and type(conns) == "table" then
            for _, conn in ipairs(conns) do
                if pcall(function() conn:Disable() end) then
                    table.insert(godConns, conn)
                end
            end
        end
    end
    godOn = true
    cfg.god = true
    SaveConfig()
    Notify("God mode: AKTIF")
end

local function Diag()
    local world = FindWorld()
    local inWorld = InWorld(world)
    local x, y = GetGridState()
    local c = FindCamera()
    return string.format("World: %s | Posisi: %s | Hook: %s (%d paket) | Kamera: %s | Noclip: %s",
        inWorld and CurrentWorldName() or "BELUM (tabel world tidak ketemu / belum masuk)",
        x and string.format("%.1f, %.1f [%s]", x, y, posDebug.picked) or "tidak terbaca",
        PosHook.how, PosHook.count,
        c and "siap" or ("belum - " .. tostring(camError)),
        Noclip.on and "on" or "off")
end

----------------------------------------------------------------------
-- PROFIL PLAYER & INFO SERVER (hanya membaca data)
----------------------------------------------------------------------
local Info = { selected = nil, remote = {}, remoteBusy = false, fps = 60 }

RunService.Heartbeat:Connect(function(dt)
    if dt > 0 then
        Info.fps = Info.fps * 0.9 + (1 / dt) * 0.1
    end
end)

function Info.Roles()
    if Info.roles == nil then
        Info.roles = false
        pcall(function()
            local shared = ReplicatedStorage:FindFirstChild("Shared")
            local module = shared and shared:FindFirstChild("Roles")
            if module then
                Info.roles = require(module)
            end
        end)
    end
    return Info.roles or nil
end

function Info.RoleOf(player)
    local roles = Info.Roles()
    if not roles then
        return "-"
    end
    local parts = {}
    if Safe(roles.isDeveloper, player.UserId) then
        table.insert(parts, "Developer")
    end
    if Safe(roles.isModerator, player.UserId) then
        table.insert(parts, "Moderator")
    end
    if #parts == 0 and Safe(roles.isStaff, player.UserId) then
        table.insert(parts, "Staff")
    end
    return #parts > 0 and table.concat(parts, ", ") or "Pemain"
end

function Info.WorldPlayers()
    local map, count = {}, 0
    local others = FindOthers()
    if others then
        local list = Safe(others.list)
        if type(list) == "table" then
            for _, entry in ipairs(list) do
                if type(entry) == "table" and entry[1] then
                    map[entry[1]] = true
                    count = count + 1
                end
            end
        end
    end
    return map, count
end

function Info.PlayerTile(player)
    if player == Player then
        return GetTile()
    end
    local others = FindOthers()
    if others and type(others.where) == "function" then
        local x, y = Safe(others.where, player.UserId)
        if type(x) == "number" and type(y) == "number" then
            return math.floor(x), math.floor(y - 0.475)
        end
    end
    return nil
end

function Info.FormatLevel(level, a, b)
    local text = "Lv " .. tostring(level)
    if a ~= nil and b ~= nil then
        text = text .. string.format(" (%s / %s)", tostring(a), tostring(b))
    elseif a ~= nil then
        text = text .. " (" .. tostring(a) .. ")"
    end
    return text
end

function Info.Find(query)
    query = (Trim(query or ""):lower():gsub("^@", ""))
    if query == "" then
        return nil
    end
    local id = tonumber(query)
    local partial = nil
    for _, p in ipairs(Players:GetPlayers()) do
        local name, display = p.Name:lower(), p.DisplayName:lower()
        local gameName = tostring(p:GetAttribute("GameName") or ""):lower()
        if (id and p.UserId == id) or name == query or display == query or gameName == query then
            return p
        end
        if not partial and (name:find(query, 1, true) or display:find(query, 1, true)
            or (gameName ~= "" and gameName:find(query, 1, true))) then
            partial = p
        end
    end
    return partial
end

function Info.PlayerData(player)
    local rows = {}
    local function add(key, label, value)
        table.insert(rows, { key = key, label = label, value = tostring(value) })
    end
    add("name", "Username", "@" .. player.Name .. (player == Player and "  (kamu)" or ""))
    add("display", "Display name", player.DisplayName)
    add("id", "UserId", player.UserId)
    local gameName = player:GetAttribute("GameName") or player:GetAttribute("Nick")
    if gameName and tostring(gameName) ~= "" then
        add("gamename", "Nama di game", gameName)
    end
    add("age", "Umur akun", string.format("%d hari (~%.1f tahun)", player.AccountAge, player.AccountAge / 365))
    local country = player:GetAttribute("Country")
    if country and tostring(country) ~= "" and tostring(country) ~= "00" then
        add("country", "Negara", country)
    end
    add("role", "Role", Info.RoleOf(player))
    local status = {}
    for _, attr in ipairs({ "Invisible", "Ghost", "Frozen" }) do
        if player:GetAttribute(attr) == true then
            table.insert(status, attr:lower())
        end
    end
    if (tonumber(player:GetAttribute("MutedUntil")) or 0) > workspace:GetServerTimeNow() then
        table.insert(status, "muted")
    end
    add("status", "Status", #status > 0 and table.concat(status, ", ") or "normal")

    local worldMap = Info.WorldPlayers()
    local worldName = CurrentWorldName()
    local here = (player == Player and worldName ~= "") or worldMap[player.UserId] == true
    add("world", "Di world kamu", here and (worldName ~= "" and worldName or "ya") or "tidak")
    local tx, ty = Info.PlayerTile(player)
    add("pos", "Posisi (tile)", tx and string.format("%d, %d", tx, ty) or "-")
    if player ~= Player and tx then
        local mx, my = GetTile()
        if mx then
            local dx, dy = tx - mx, ty - my
            add("dist", "Jarak dari kamu", string.format("%.1f tile (dx %d, dy %d)", math.sqrt(dx * dx + dy * dy), dx, dy))
        end
    end
    add("level", "Level", "memuat...")
    return rows
end

function Info.FetchLevel(player, cb)
    task.spawn(function()
        local api = FindApi()
        if not api then
            cb("(API game tidak ditemukan)")
            return
        end
        if player == Player then
            local level, a, b = Safe(api.level)
            cb(level ~= nil and Info.FormatLevel(level, a, b) or "-")
            return
        end
        local level, extra = Safe(api.playerLevel, player.UserId)
        if level == nil then
            cb("-")
        elseif type(level) == "table" then
            local ok, encoded = pcall(function()
                return HttpService:JSONEncode(level)
            end)
            cb(ok and encoded or "(data level tidak terbaca)")
        else
            cb(Info.FormatLevel(level, extra))
        end
    end)
end

function Info.PlayerSummary(player)
    local worldMap = Info.WorldPlayers()
    local worldName = CurrentWorldName()
    local here = (player == Player and worldName ~= "") or worldMap[player.UserId] == true
    local tx, ty = Info.PlayerTile(player)
    return string.format("%s (@%s) | ID %d | Akun %d hari | Role %s | %s%s",
        player.DisplayName, player.Name, player.UserId, player.AccountAge, Info.RoleOf(player),
        here and ("di world " .. (worldName ~= "" and worldName or "?")) or "tidak di world kamu",
        tx and string.format(" | pos %d,%d", tx, ty) or "")
end

function Info.ServerData()
    local d = {}
    d.serverId = (game.JobId ~= "" and game.JobId) or "(Studio/privat)"
    d.players = string.format("%d / %d", #Players:GetPlayers(), Players.MaxPlayers)
    local okPing, ping = pcall(function()
        return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    d.ping = okPing and ping and string.format("%d ms", math.floor(ping)) or "-"
    d.fps = tostring(math.floor(Info.fps + 0.5))
    local up = math.max(0, math.floor(workspace.DistributedGameTime))
    d.uptime = string.format("%d:%02d:%02d", math.floor(up / 3600), math.floor((up % 3600) / 60), up % 60)
    local worldName = CurrentWorldName()
    d.world = worldName ~= "" and worldName or "(belum masuk world)"
    if worldName ~= "" then
        local _, count = Info.WorldPlayers()
        d.worldPlayers = tostring(count + 1)
    else
        d.worldPlayers = "-"
    end
    local tx, ty = GetTile()
    d.pos = tx and string.format("%d, %d", tx, ty) or "-"
    local r = Info.remote or {}
    d.level = r.level or "-"
    d.gems = r.gems ~= nil and tostring(r.gems) or "-"
    return d
end

function Info.ServerSummary()
    local d = Info.ServerData()
    return string.format("Server: %s pemain | Ping %s | FPS %s | Aktif %s | World %s (%s pemain) | ID %s",
        d.players, d.ping, d.fps, d.uptime, d.world, d.worldPlayers, string.sub(d.serverId, 1, 8))
end

function Info.RefreshRemote(done)
    if Info.remoteBusy then
        return
    end
    Info.remoteBusy = true
    task.spawn(function()
        local r = {}
        local api = FindApi()
        if api then
            local level, a, b = Safe(api.level)
            if level ~= nil then
                r.level = Info.FormatLevel(level, a, b)
            end
            r.gems = Safe(api.gems)
        end
        Info.remote = r
        Info.remoteBusy = false
        if done then
            pcall(done)
        end
    end)
end

----------------------------------------------------------------------
-- VISUAL ITEM (inventory lokal)
-- Memasukkan item/block/lock ke objek inventory game (inv:add) supaya muncul di
-- inventory dan bisa di-equip/unequip lewat UI game seperti biasa. Hanya ada di
-- layarmu: server tidak tahu item ini. Game menyamakan inventory dengan server
-- (InventorySync) dan membuang kelebihannya, jadi item dipulihkan otomatis (termasuk status dipakai).
----------------------------------------------------------------------
local Visual = { list = nil, worn = {}, busy = false, hooked = nil }

function Visual.Items()
    if Visual.list then
        return Visual.list
    end
    local db = GetItemDB()
    if not db then
        return nil
    end
    local list = {}
    for id, item in pairs(db) do
        if type(id) == "number" and type(item) == "table" and type(item.name) == "string" and item.name ~= "" then
            local cat
            if item.lock then
                cat = "lock"
            elseif type(item.slot) == "string" then
                cat = "pakaian"
            elseif item.kind == "seed" then
                cat = "seed"
            elseif item.kind == "tool" then
                cat = "alat"
            else
                cat = "block"
            end
            table.insert(list, { id = id, name = item.name, lower = item.name:lower(), cat = cat })
        end
    end
    table.sort(list, function(a, b)
        if a.name == b.name then
            return a.id < b.id
        end
        return a.name < b.name
    end)
    Visual.list = list
    return list
end

local function VisualInv()
    local env = FindGameEnv()
    local inv = env and env.inv
    if type(inv) == "table" and type(inv.add) == "function" and type(inv.count) == "function" then
        return inv
    end
    return nil
end

-- Jumlah item palsu yang masih ada di inventory (untuk Auto Farm supaya tidak ikut dihitung)
function Visual.Granted(id)
    local given = tonumber(cfg.visual[tostring(id)]) or 0
    if given <= 0 then
        return 0
    end
    local inv = VisualInv()
    if not inv then
        return 0
    end
    local ok, have = pcall(inv.count, inv, id)
    if ok and type(have) == "number" then
        return math.min(given, have)
    end
    return 0
end

function Visual.Give(id, amount)
    local inv = VisualInv()
    if not inv then
        Notify("Inventory game belum terbaca (masuk world dulu).")
        return false
    end
    amount = math.clamp(math.floor(tonumber(amount) or 1), 1, 200)
    local ok, added = pcall(inv.add, inv, id, amount)
    if not ok or type(added) ~= "number" or added <= 0 then
        Notify("Inventory penuh atau item tidak bisa ditambah.")
        return false
    end
    local key = tostring(id)
    cfg.visual[key] = (tonumber(cfg.visual[key]) or 0) + added
    SaveConfig()
    return true
end

function Visual.Take(id)
    local inv = VisualInv()
    local n = Visual.Granted(id)
    if inv and n > 0 and type(inv.remove) == "function" then
        pcall(inv.remove, inv, id, n)
    end
    cfg.visual[tostring(id)] = nil
    SaveConfig()
end

function Visual.Clear()
    local ids = {}
    for key in pairs(cfg.visual) do
        table.insert(ids, tonumber(key))
    end
    for _, id in ipairs(ids) do
        Visual.Take(id)
    end
    Notify("Semua item visual dihapus dari inventory.")
end

-- Pulihkan item visual yang dibuang game (sinkronisasi inventory dengan server terjadi
-- tiap place/break/jalan). Kalau item itu sebelumnya sedang kamu pakai, langsung dipakai
-- lagi. Kalau kamu sendiri yang melepas (item masih ada di inventory), tidak dipasang ulang.
function Visual.Reapply()
    if Visual.busy then
        return
    end
    local env = FindGameEnv()
    local inv = VisualInv()
    if not env or not inv then
        return
    end
    Visual.busy = true
    local db = GetItemDB()
    local okWorn, worn = pcall(env.worn)
    local canWorn = okWorn and type(worn) == "table"
    local needRefresh = false
    for key, given in pairs(cfg.visual) do
        local id = tonumber(key)
        if id and type(given) == "number" and given > 0 then
            local okCount, have = pcall(inv.count, inv, id)
            if okCount and type(have) == "number" then
                local item = db and db[id]
                local slot = (type(item) == "table" and type(item.slot) == "string") and item.slot or nil
                if have < given then
                    pcall(inv.add, inv, id, given - have)
                    if slot and canWorn and Visual.worn[id] and worn[slot] ~= id then
                        worn[slot] = id
                        needRefresh = true
                    end
                elseif slot and canWorn then
                    -- item aman di inventory: ingat apakah kamu sedang memakainya
                    Visual.worn[id] = (worn[slot] == id) or nil
                end
            end
        end
    end
    Visual.busy = false
    if needRefresh and type(env.invUI) == "table" and type(env.invUI.refresh) == "function" then
        pcall(env.invUI.refresh)
    end
end

-- Pantau perubahan inventory game: pulihkan segera (di frame yang sama setelah game
-- membuang item), jadi pakaian tidak sempat terlihat terlepas.
function Visual.Hook()
    local inv = VisualInv()
    if not inv or Visual.hooked == inv then
        return
    end
    local okEvent, event = pcall(function()
        return inv.changed
    end)
    if okEvent and typeof(event) == "Instance" and event:IsA("BindableEvent") then
        Visual.hooked = inv
        event.Event:Connect(function()
            if next(cfg.visual) ~= nil then
                task.defer(Visual.Reapply)
            end
        end)
    end
end

task.spawn(function()
    while true do
        task.wait(0.2)
        pcall(Visual.Hook)
        if next(cfg.visual) ~= nil then
            pcall(Visual.Reapply)
        end
    end
end)

----------------------------------------------------------------------
-- AUTO FARM
-- Cara kerja (dipelajari dari Growlock.lua):
--  * PLACE   : fungsi game setTile(layer, x, y, id, false, flip) lalu
--              inventory:remove(id, 1). Server dikabari lewat Net.tile.
--  * BREAK   : fungsi game hit(x, y, true) menambah hit pada tile; saat
--              hit >= hits tile pecah (setTile id 0) dan item jatuh.
--  * COLLECT : drop ada di world.dropList(). Game mengambilnya otomatis
--              (takeDrop) kalau pemain berdiri di atas drop, jadi kita
--              jalan ke drop lewat world.goTo lalu kembali ke posisi awal.
-- Area = kotak 5x5 dengan pusat di tile pemain saat Auto Farm dinyalakan.
----------------------------------------------------------------------
local Farm = {
    on = false,
    token = 0,
    anchor = nil,
    status = "Mati",
    stats = { cycles = 0, placed = 0, broken = 0, picked = 0 },
    fns = {},
    fnWorld = nil,
}

local LAYER_NUM = { fg = 1, bg = 2 }

-- Modul Net game: Net.tile.send({layer, x, y, id, flip}) = persis yang dikirim setTile milik game
local function FarmNet()
    local ok, net = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Shared", 3):WaitForChild("Net", 3))
    end)
    if ok and type(net) == "table" and type(net.tile) == "table" and type(net.tile.send) == "function" then
        return net
    end
    return nil
end

-- PlayerPos ping (x, y, vx, vy, flags, timestamp).
-- Game selalu mengirim paket ini tepat sebelum paket tile (place maupun break).
-- Isi paket memakai PlayerPos ASLI terakhir yang dikirim game (posisi,
-- kecepatan, flag), hanya timestamp yang diperbarui, jadi server melihat nilai
-- yang sama persis dengan yang game laporkan sendiri.
local FarmPosRemote = nil
local function FarmPing()
    if FarmPosRemote == nil then
        local remotes = ReplicatedStorage:FindFirstChild("WorldRemotes")
        FarmPosRemote = (remotes and remotes:FindFirstChild("PlayerPos")) or false
    end
    if not FarmPosRemote then
        return
    end
    local x, y, vx, vy, flags
    local last = PosHook.last
    if last and os.clock() - last.t < 0.2 then
        x, y, vx, vy, flags = last.x, last.y, last.vx or 0, last.vy or 0, last.flags or 2
    else
        local gx, gy, facing = GetGridState()
        if not gx then
            return
        end
        x, y, vx, vy = gx, gy, 0, 0
        flags = (facing and facing > 0 and 1 or 0) + 2
    end
    pcall(FarmPosRemote.FireServer, FarmPosRemote, x, y, vx, vy, flags, math.floor(os.clock() * 1000) % 65535)
end

-- Place (id > 0) atau break selesai (id = 0): kirim ke server lalu terapkan lokal
-- lewat world.tileChanged (field publik game, tidak mengirim ulang).
local function FarmSetTile(net, world, layer, x, y, id)
    FarmPing()
    local okSend = pcall(net.tile.send, { layer = LAYER_NUM[layer] or 1, x = x, y = y, id = id, flip = false })
    if not okSend then
        return false
    end
    if id == 0 and type(net.flush) == "function" then
        pcall(net.flush)
    end
    if type(rawget(world, "tileChanged")) == "function" then
        pcall(world.tileChanged, layer, x, y, id, false)
    else
        local grid = rawget(world, layer)
        if type(grid) == "table" and type(grid[y]) == "table" then
            grid[y][x] = id
        end
    end
    return true
end

-- Jumlah pukulan agar block pecah: item.hits (seed = 20), tiap pukulan tangan = 6 dari hits * 6
local function FarmHits(id)
    local db = GetItemDB()
    local item = db and db[id]
    if type(item) ~= "table" then
        return nil
    end
    local hits = item.kind == "seed" and 20 or item.hits
    if type(hits) == "number" and hits > 0 then
        return math.ceil(hits)
    end
    return nil
end

local function FarmBag()
    local world = FindWorld()
    if world and type(rawget(world, "backpackNow")) == "function" then
        local ups, count = ReadUpvalues(world.backpackNow)
        for i = 1, count do
            local value = ups[i]
            if type(value) == "table" and type(value.slots) == "table"
                and type(value.remove) == "function" and type(value.add) == "function" then
                return value
            end
        end
    end
    -- fallback: tabel milik modul Trade (env.inv). Dipakai HANYA kalau scan
    -- di atas gagal menemukan bag asli, karena env.inv bisa jadi salinan/
    -- adapter terpisah, bukan tabel yang sama dipakai game saat place/break.
    local env = FindGameEnv()
    if env and type(env.inv) == "table" then
        return env.inv
    end
    return nil
end

-- Jumlah item asli (tanpa item visual) supaya Auto Farm tidak menaruh block palsu
local function RealCount(id)
    local n = CountItem(id)
    if n == nil then
        return nil
    end
    return n - Visual.Granted(id)
end

local function FarmLayerOf(id)
    local db = GetItemDB()
    local item = db and db[id]
    if type(item) == "table" and item.background then
        return "bg"
    end
    return "fg"
end

local function FarmTile(world, layer, x, y)
    local grid = rawget(world, layer)
    local row = type(grid) == "table" and grid[y] or nil
    return type(row) == "table" and row[x] or nil
end

local function FarmDelay()
    return math.max(0.01, tonumber(cfg.farmDelay) or 0.05)
end

-- Jeda minimal yang dipakai game: pukulan 0.22 dtk, place 0.15 dtk (dipakai 0.2 supaya aman)
local FARM_PUNCH_MIN = 0.22
local FARM_PLACE_MIN = 0.2
local farmGate = 0

-- Semua aksi (hit / place) lewat gerbang ini supaya tidak lebih cepat dari game
local function FarmGate(interval)
    local now = os.clock()
    if farmGate > now then
        task.wait(farmGate - now)
    end
    farmGate = os.clock() + interval
end

-- Objek "Others" milik game: punya sendHit (paket hit yang dikirim game di tiap pukulan)
local function FarmOthers()
    local others = FindOthers()
    if type(others) == "table" then
        local ok, fn = pcall(function() return others.sendHit end)
        if ok and type(fn) == "function" then
            return others
        end
    end
    return nil
end

-- Paket "act" kind=1 (pukulan) yang selalu dikirim game tiap kali pemain memukul
local function FarmAct(net, x, y)
    local act = net and net.act
    if type(act) == "table" and type(act.send) == "function" then
        pcall(act.send, { kind = 1, x = x + 0.5, y = y + 0.5 })
    end
end

-- Kekuatan satu pukulan (sama seperti game): tangan 6 per pukulan, handDig 8
local function FarmPunchPower()
    local per = 6
    local inv = FindInventory()
    if inv then
        local okDig, dig = pcall(function() return inv.handDig and inv.handDig() end)
        if okDig and type(dig) == "number" and dig > 0 then
            per = 8
        else
            local okPower, power = pcall(function() return inv.handPower and inv.handPower() end)
            if okPower and type(power) == "number" and power > 0 then
                per = power * 6
            end
        end
    end
    return per
end

-- Tile (x, y) masih dalam jangkauan pemain? (punch = punchRange, place = buildRange)
local function FarmInRange(forBuild, x, y)
    local gx, gy = GetGridState()
    if not gx then
        return false
    end
    local range = 2.5
    local inv = FindInventory()
    if inv then
        local ok, value = pcall(function()
            if not forBuild and inv.punchRange then
                return inv.punchRange() or inv.buildRange()
            end
            return inv.buildRange()
        end)
        if ok and type(value) == "number" then
            range = value
        end
    end
    return math.abs(x + 0.5 - gx) <= range and math.abs(y + 0.5 - (gy - 0.475)) <= range
end

-- Tile boleh dilewati (bukan block padat)?
local function FarmPassable(world, x, y)
    if x < 0 or y < 0 or x >= world.w or y >= world.h then
        return false
    end
    local id = FarmTile(world, "fg", x, y)
    if id == nil then
        return false
    end
    if id == 0 then
        return true
    end
    local db = GetItemDB()
    local item = db and db[id]
    return type(item) == "table" and not item.solid
end


-- Daftar block di inventory: { {id=, n=, name=}, ... }
function Farm.Inventory()
    local world = FindWorld()
    local list = {}
    if not world or type(rawget(world, "backpackNow")) ~= "function" then
        return list
    end
    local ok, bag = pcall(world.backpackNow)
    if not ok or type(bag) ~= "table" then
        return list
    end
    local db = GetItemDB()
    local total = {}
    for _, slot in pairs(bag) do
        if type(slot) == "table" then
            local id, n = slot[1] or slot.id, slot[2] or slot.n
            if type(id) == "number" and type(n) == "number" and n > 0 then
                total[id] = (total[id] or 0) + n
            end
        end
    end
    for id, n in pairs(total) do
        n = n - Visual.Granted(id)
        local item = db and db[id]
        local kind = type(item) == "table" and item.kind or nil
        if n > 0 and type(item) == "table" and kind ~= "tool" and kind ~= "cloth" then
            table.insert(list, { id = id, n = n, name = ItemName(id) or ("Item " .. id) })
        end
    end
    table.sort(list, function(a, b)
        return a.id < b.id
    end)
    return list
end

local function FarmCells(world, anchor)
    local cells = {}
    for key, on in pairs(cfg.farmGrid) do
        local dx, dy = tostring(key):match("^(-?%d+),(-?%d+)$")
        dx, dy = tonumber(dx), tonumber(dy)
        if on and dx and dy and math.abs(dx) <= 2 and math.abs(dy) <= 2 and not (dx == 0 and dy == 0) then
            local x, y = anchor.x + dx, anchor.y + dy
            if x >= 0 and y >= 0 and x < world.w and y < world.h then
                table.insert(cells, { x = x, y = y, key = x .. "," .. y })
            end
        end
    end
    table.sort(cells, function(p, q)
        if p.y ~= q.y then
            return p.y < q.y
        end
        return p.x < q.x
    end)
    return cells
end

local function FarmMayBuild(world, x, y)
    local ok, may = pcall(function()
        return world.areas.mayBuild(world.lock, x, y)
    end)
    if ok and may == false then
        return false
    end
    return true
end

-- Ambil drop yang jatuh di kolom tile yang DIPILIH di grid 5x5, lalu kembali ke
-- posisi awal. Pengambilan item/gems dilakukan sistem collect game sendiri saat
-- player berdiri di atas drop (script tidak memanggil takeDrop).
--
-- Cara kerja ASLI game (dipelajari dari Growlocks.lua): berdiri dekat drop
-- tidak langsung "nempel" ke inventory. Tiap frame game mengecek jarak lalu
-- men-"arm" drop itu, baru pada frame berikutnya memanggil world.takeDrop
-- (request ASYNC ke server, lengkap dengan ping posisi sendiri) -- dan HANYA
-- kalau server setuju (v1237 "got" > 0), tabel bag lokal (v_u_52) ditambah
-- lewat :add(...) dan ikon drop baru hilang/berkurang. Kalau server menolak
-- (posisi dianggap tidak meyakinkan, backpack penuh, dsb), ikon drop TETAP
-- ADA dan game otomatis coba lagi di frame berikutnya (ada jeda tunggu
-- "refused" 0.25 detik sebelum coba lagi).
--
-- PERBAIKAN dari versi lama: dulu hanya menunggu 0.8 detik lalu anggap
-- "hilang dari dropList = berhasil diambil". Itu kurang lama untuk siklus
-- arm -> request -> balasan server di atas, dan TIDAK memverifikasi item
-- benar-benar bertambah di inventory -- bisa membuat Auto Farm diam-diam
-- kehilangan beberapa drop (persis keluhan "item drop ga masuk inventory").
-- Sekarang: tunggu lebih lama (bisa dipanjangkan lewat Config kalau perlu),
-- dan verifikasi lewat DUA tanda: (a) drop hilang dari dropList(), DAN/ATAU
-- (b) jumlah item itu di backpack benar-benar bertambah (CountItem).
local function FarmCollect(world, anchor, alive)
    local ok, list = pcall(world.dropList)
    if not ok or type(list) ~= "table" then
        return 0
    end
    -- hanya kolom tile yang dipilih di grid 5x5
    local columns = {}
    for key, on in pairs(cfg.farmGrid) do
        local dx, dy = tostring(key):match("^(-?%d+),(-?%d+)$")
        dx, dy = tonumber(dx), tonumber(dy)
        if on and dx and dy and math.abs(dx) <= 2 and math.abs(dy) <= 2 then
            columns[anchor.x + dx] = true
        end
    end
    local targets = {}
    for _, drop in ipairs(list) do
        if type(drop) == "table" and type(drop.x) == "number" and type(drop.y) == "number" and not drop.pending
            and columns[math.floor(drop.x)] and math.abs(math.floor(drop.y) - anchor.y) <= 2 then
            table.insert(targets, drop)
        end
    end
    local picked = 0
    for _, drop in ipairs(targets) do
        if not alive() then
            break
        end
        local beforeN = (type(drop.id) == "number") and CountItem(drop.id) or nil
        pcall(world.goTo, math.floor(drop.x), math.floor(drop.y))
        local started = os.clock()
        local gotIt = false
        while alive() and os.clock() - started < 3.5 do
            local okList, current = pcall(world.dropList)
            local stillThere = okList and type(current) == "table" and table.find(current, drop)
            if not stillThere then
                gotIt = true
                break
            end
            if beforeN ~= nil then
                local nowN = CountItem(drop.id)
                if nowN ~= nil and nowN > beforeN then
                    gotIt = true
                    break
                end
            end
            -- berdiri diam di atas drop supaya loop "arm" milik game tetap
            -- menganggap kita dekat (sekaligus mengirim ulang permintaan
            -- goTo murah, kalau-kalau posisi tergeser oleh sebab lain)
            task.wait(0.1)
        end
        if gotIt then
            picked += 1
        end
    end
    if #targets > 0 then
        pcall(world.goTo, anchor.x, anchor.y)
    end
    return picked
end

local function FarmCycle(token)
    local function alive()
        return Farm.token == token
    end
    local world = FindWorld()
    local anchor = Farm.anchor
    if not InWorld(world) or not anchor then
        return false, "World tidak ditemukan"
    end
    if CurrentWorldName() ~= anchor.world then
        return false, "World berubah"
    end
    local id = cfg.farmId
    if type(id) ~= "number" or id <= 0 then
        return false, "Pilih block dulu"
    end
    local net = FarmNet()
    if not net then
        return false, "Modul Net game tidak ditemukan"
    end
    local others = FarmOthers()
    if not others then
        return false, "Fungsi hit game (sendHit) tidak ditemukan"
    end
    local hits = FarmHits(id)
    if not hits then
        return false, "Block ini tidak bisa dihancurkan"
    end
    local layer = FarmLayerOf(id)
    local cells = FarmCells(world, anchor)
    if #cells == 0 then
        return false, "Pilih tile di grid 5x5 dulu"
    end
    local delay = FarmDelay()

    -- tetap di posisi awal
    local tx, ty = GetTile()
    if tx ~= anchor.x or ty ~= anchor.y then
        pcall(world.goTo, anchor.x, anchor.y)
        task.wait(0.1)
    end

    -- 1) PLACE
    Farm.status = "Place " .. (ItemName(id) or id)
    local placedAt = {}
    local outOfItem = false
    local left = RealCount(id)
    for _, cell in ipairs(cells) do
        if not alive() then
            return true
        end
        if FarmTile(world, layer, cell.x, cell.y) == 0 and FarmMayBuild(world, cell.x, cell.y) then
            if left ~= nil and left <= 0 then
                outOfItem = true
                break
            end
            if not FarmInRange(true, cell.x, cell.y) then
                continue
            end
            FarmGate(math.max(FARM_PLACE_MIN, delay))
            if not alive() then
                return true
            end
            if FarmSetTile(net, world, layer, cell.x, cell.y, id) then
                local bag = FarmBag()
                local removed = false
                if bag and type(bag.remove) == "function" then
                    removed = pcall(bag.remove, bag, id, 1)
                end
                if removed then
                    left = RealCount(id)
                elseif left then
                    left -= 1
                end
                placedAt[cell.key] = os.clock()
                Farm.stats.placed += 1
            end
        end
    end

    -- 2) BREAK: sama seperti game. Tiap pukulan = paket hit (sendHit) + paket act,
    --    dengan jeda minimal 0.22 dtk. Satu block dipukul terus sampai pecah, baru
    --    paket tile id 0 dikirim (game melakukannya persis saat damage penuh).
    Farm.status = "Break " .. (ItemName(id) or id)
    local perPunch = FarmPunchPower()
    local needed = hits * 6
    local punchGap = math.max(FARM_PUNCH_MIN, delay)
    for _, cell in ipairs(cells) do
        if not alive() then
            return true
        end
        local progress = 0
        local guard = 0
        local didBreak = false
        while alive() and FarmTile(world, layer, cell.x, cell.y) == id and guard < 200 do
            guard += 1
            -- game menolak pukulan ke tile yang baru di-place (< 0.3 detik)
            local since = os.clock() - (placedAt[cell.key] or 0)
            if since < 0.32 then
                task.wait(0.32 - since)
            end
            if not FarmInRange(false, cell.x, cell.y) then
                break
            end
            FarmGate(punchGap)
            if not alive() then
                return true
            end
            pcall(others.sendHit, cell.x, cell.y)
            FarmAct(net, cell.x, cell.y)
            progress += perPunch
            if progress >= needed then
                FarmSetTile(net, world, layer, cell.x, cell.y, 0)
                didBreak = true
                break
            end
        end
        if didBreak then
            Farm.stats.broken += 1
        end
    end

    -- 3) COLLECT
    if cfg.farmCollect and alive() then
        Farm.status = "Collect"
        task.wait(0.25) -- drop muncul sedikit setelah tile pecah
        Farm.stats.picked += FarmCollect(world, anchor, alive)
    end

    Farm.stats.cycles += 1
    if outOfItem then
        return false, (ItemName(id) or "Block") .. " habis di inventory"
    end
    return true
end

function Farm.Stop(reason)
    local was = Farm.on
    Farm.on = false
    Farm.token += 1
    Farm.status = reason or "Mati"
    if was and reason then
        Notify("Auto Farm: " .. reason)
    end
end

function Farm.Start()
    if Farm.on then
        return true
    end
    local world = FindWorld()
    if not InWorld(world) then
        Notify("Belum masuk world.")
        return false
    end
    local x, y, facing = GetGridState()
    if not x then
        Notify("Posisi pemain tidak terbaca. " .. Diag())
        return false
    end
    if type(cfg.farmId) ~= "number" or cfg.farmId <= 0 then
        Notify("Pilih block di tab Farm dulu.")
        return false
    end
    Farm.anchor = {
        x = math.floor(x),
        y = math.floor(y - 0.475),
        facing = facing or 1,
        world = CurrentWorldName(),
    }
    Farm.stats = { cycles = 0, placed = 0, broken = 0, picked = 0 }
    Farm.token += 1
    local token = Farm.token
    Farm.on = true
    Farm.status = "Mulai"
    task.spawn(function()
        while Farm.token == token do
            local okRun, ok, reason = pcall(FarmCycle, token)
            if Farm.token ~= token then
                break
            end
            if not okRun then
                Farm.Stop("Error: " .. tostring(ok))
                break
            elseif not ok then
                Farm.Stop(reason or "Berhenti")
                break
            end
            task.wait(0.05)
        end
    end)
    Notify("Auto Farm aktif.")
    return true
end

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------
local C = {
    window = Color3.fromRGB(255, 241, 204), -- krem
    header = Color3.fromRGB(255, 150, 60),  -- oranye
    card = Color3.fromRGB(255, 255, 255),
    cardOn = Color3.fromRGB(122, 220, 110), -- hijau permen
    accent = Color3.fromRGB(88, 172, 255),
    ink = Color3.fromRGB(70, 44, 32),       -- outline cokelat tua
    text = Color3.fromRGB(70, 44, 32),
    mute = Color3.fromRGB(128, 98, 80),
    ok = Color3.fromRGB(122, 220, 110),
    bad = Color3.fromRGB(255, 100, 100),
}
local FONT = Enum.Font.FredokaOne
local FONT_BODY = Enum.Font.GothamMedium

local ui = { gui = nil, window = nil, pages = {}, tabs = {}, refreshers = {}, orders = setmetatable({}, { __mode = "k" }) }

local function New(class, props, parent)
    local obj = Instance.new(class)
    for key, value in pairs(props) do
        obj[key] = value
    end
    obj.Parent = parent
    return obj
end

local function NextOrder(parent)
    local n = (ui.orders[parent] or 0) + 1
    ui.orders[parent] = n
    return n
end

local function Round(obj, radius)
    return New("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, obj)
end

-- garis tepi tebal ala kartun
local function Outline(obj, thickness)
    return New("UIStroke", {
        Color = C.ink,
        Thickness = thickness or 2,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, obj)
end

local function AddLabel(parent, text, color, size)
    return New("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = color or C.mute,
        Font = FONT_BODY,
        TextSize = size or 10,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = NextOrder(parent),
    }, parent)
end

local function AddSection(parent, text)
    return New("TextLabel", {
        Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1,
        Text = "~ " .. text .. " ~",
        TextColor3 = C.header,
        Font = FONT,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = NextOrder(parent),
    }, parent)
end

local function AddButton(parent, text, callback, color)
    local button = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = color or C.card,
        Text = text,
        TextColor3 = C.text,
        Font = FONT,
        TextSize = 12,
        TextTruncate = Enum.TextTruncate.AtEnd,
        AutoButtonColor = true,
        BorderSizePixel = 0,
        LayoutOrder = NextOrder(parent),
    }, parent)
    Round(button, 8)
    Outline(button, 2)
    button.MouseButton1Click:Connect(callback)
    return button
end

local function AddToggle(parent, title, getState, onToggle)
    local button
    local function Paint()
        local on = getState()
        button.Text = title .. (on and "  [ON]" or "  [OFF]")
        button.BackgroundColor3 = on and C.cardOn or C.card
    end
    button = AddButton(parent, title, function()
        onToggle(not getState())
        Paint()
    end)
    Paint()
    table.insert(ui.refreshers, Paint)
    return button
end

local function AddInput(parent, title, value, placeholder, onCommit)
    local card = New("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = C.card,
        BorderSizePixel = 0,
        LayoutOrder = NextOrder(parent),
    }, parent)
    Round(card, 8)
    Outline(card, 2)
    New("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.new(0.5, -8, 1, 0),
        Text = title,
        TextColor3 = C.text,
        Font = FONT,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, card)
    local box = New("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -5, 0.5, 0),
        Size = UDim2.new(0.44, 0, 0, 20),
        BackgroundColor3 = C.window,
        BorderSizePixel = 0,
        Text = tostring(value),
        PlaceholderText = placeholder or "",
        TextColor3 = C.text,
        PlaceholderColor3 = C.mute,
        Font = FONT_BODY,
        TextSize = 11,
        ClearTextOnFocus = false,
    }, card)
    Round(box, 6)
    box.FocusLost:Connect(function()
        onCommit(box.Text, box)
    end)
    return box
end

local function MakeBox(parent)
    local box = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = NextOrder(parent),
    }, parent)
    New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, box)
    return box
end

local function ClearBox(box)
    for _, child in ipairs(box:GetChildren()) do
        if not child:IsA("UIListLayout") then
            child:Destroy()
        end
    end
    ui.orders[box] = 0
end

local function AddRows(parent, rows)
    local card = New("Frame", {
        Size = UDim2.new(1, 0, 0, #rows * 17 + 8),
        BackgroundColor3 = C.card,
        BorderSizePixel = 0,
        LayoutOrder = NextOrder(parent),
    }, parent)
    Round(card, 8)
    Outline(card, 2)
    local labels = {}
    for index, row in ipairs(rows) do
        local y = 4 + (index - 1) * 17
        New("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(8, y),
            Size = UDim2.new(0.38, -8, 0, 16),
            Text = row.label,
            TextColor3 = C.mute,
            Font = FONT_BODY,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, card)
        labels[row.key] = New("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0.38, 0, 0, y),
            Size = UDim2.new(0.62, -8, 0, 16),
            Text = row.value or "...",
            TextColor3 = C.text,
            Font = FONT_BODY,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, card)
    end
    return labels
end

local function GetGui()
    if ui.gui and ui.gui.Parent then
        return ui.gui
    end
    ui.gui = New("ScreenGui", {
        Name = "PeexHubsGrowLock",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 999,
    }, nil)
    local okParent = pcall(function()
        ui.gui.Parent = (gethui and gethui()) or PlayerGui
    end)
    if not okParent or not ui.gui.Parent then
        ui.gui.Parent = PlayerGui
    end
    return ui.gui
end

-- Tombol Turun (muncul selama Noclip aktif; tahan untuk turun terus)
function Noclip.ShowDown(show)
    if not show then
        Noclip.downHeld = false
        if Noclip.downBtn then
            Noclip.downBtn.Visible = false
        end
        return
    end
    if not Noclip.downBtn or not Noclip.downBtn.Parent then
        local btn = New("TextButton", {
            Name = "NoclipDown",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -14, 0.62, 0),
            Size = UDim2.fromOffset(74, 48),
            BackgroundColor3 = C.accent,
            Text = "Turun",
            TextColor3 = C.card,
            Font = FONT,
            TextSize = 14,
            AutoButtonColor = true,
            BorderSizePixel = 0,
            ZIndex = 50,
        }, GetGui())
        Round(btn, 10)
        Outline(btn, 2)
        btn.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            if Noclip.downHeld then
                return
            end
            Noclip.downHeld = true
            task.spawn(function()
                while Noclip.downHeld and Noclip.on do
                    if not Noclip.StepDown() then
                        break
                    end
                    task.wait(0.09)
                end
                Noclip.downHeld = false
            end)
        end)
        btn.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                Noclip.downHeld = false
            end
        end)
        Noclip.downBtn = btn
    end
    Noclip.downBtn.Visible = true
end

-- Halaman: Drop -------------------------------------------------------
local function BuildDropPage(page)
    AddSection(page, "Lock yang di-drop dengan /cd")
    local buttons = {}
    local function Repaint()
        for _, lock in ipairs(LOCKS) do
            local button = buttons[lock.key]
            if button then
                local id = ResolveLock(lock)
                local have = id and CountItem(id)
                button.Text = string.format("%s%s   (id %s, punya %s)", cfg.lock == lock.key and "> " or "",
                    lock.name, id and tostring(id) or "?", have ~= nil and tostring(have) or "?")
                button.BackgroundColor3 = cfg.lock == lock.key and C.cardOn or C.card
            end
        end
    end
    for _, lock in ipairs(LOCKS) do
        buttons[lock.key] = AddButton(page, lock.name, function()
            cfg.lock = lock.key
            SaveConfig()
            Repaint()
            Notify("Lock /cd: " .. lock.name)
        end)
    end
    table.insert(ui.refreshers, Repaint)
    Repaint()

    AddSection(page, "Drop sekarang")
    AddInput(page, "Jumlah", cfg.amount, "1", function(text, box)
        local value = math.floor(tonumber(text) or cfg.amount)
        cfg.amount = math.max(1, value)
        box.Text = tostring(cfg.amount)
        SaveConfig()
    end)
    AddButton(page, "Drop (jumlah di atas)", function()
        DropLock(cfg.amount)
    end, C.ok)
    AddLabel(page, "Command: " .. cfg.prefix .. "cd <jumlah> [lock]  |  " .. cfg.prefix .. "cdset <lock>  |  "
        .. cfg.prefix .. "cdid <lock> <id>\nNama lock: wl, dl, bgl, small, big, huge")
end

-- Halaman: Profil -----------------------------------------------------
local function BuildProfilePage(page)
    local owner = ui.window

    AddSection(page, "Info server")
    local serverLabels = AddRows(page, {
        { key = "serverId", label = "Server ID" },
        { key = "players", label = "Pemain server" },
        { key = "ping", label = "Ping" },
        { key = "fps", label = "FPS kamu" },
        { key = "uptime", label = "Server aktif" },
        { key = "world", label = "World" },
        { key = "worldPlayers", label = "Pemain di world" },
        { key = "pos", label = "Posisi kamu" },
        { key = "level", label = "Level kamu" },
        { key = "gems", label = "Gems" },
    })
    local function UpdateServer()
        local data = Info.ServerData()
        for key, label in pairs(serverLabels) do
            label.Text = data[key] ~= nil and tostring(data[key]) or "-"
        end
    end
    UpdateServer()
    Info.RefreshRemote(UpdateServer)
    AddButton(page, "Salin Server ID (JobId)", function()
        if setclipboard then
            pcall(setclipboard, game.JobId)
        end
        Notify("Server ID disalin.")
    end)

    AddSection(page, "Profil pemain")
    AddInput(page, "Cari pemain", "", "nama / id", function(text, box)
        if Trim(text) == "" then
            return
        end
        local found = Info.Find(text)
        if found then
            Info.Select(found)
            box.Text = ""
        else
            Notify("Pemain tidak ditemukan: " .. tostring(text))
        end
    end)
    local listBox = MakeBox(page)
    AddSection(page, "Detail")
    local detailBox = MakeBox(page)

    local lastSignature = nil
    local function RenderList(force)
        local worldMap = Info.WorldPlayers()
        local inWorld = CurrentWorldName() ~= ""
        local players = Players:GetPlayers()
        table.sort(players, function(a, b)
            if a == Player then
                return true
            elseif b == Player then
                return false
            end
            return a.DisplayName:lower() < b.DisplayName:lower()
        end)
        local parts = { tostring(Info.selected and Info.selected.UserId or 0) }
        for _, p in ipairs(players) do
            local here = (p == Player and inWorld) or worldMap[p.UserId] == true
            table.insert(parts, tostring(p.UserId) .. (here and "w" or "o"))
        end
        local signature = table.concat(parts, ",")
        if not force and signature == lastSignature then
            return
        end
        lastSignature = signature
        ClearBox(listBox)
        for _, p in ipairs(players) do
            local here = (p == Player and inWorld) or worldMap[p.UserId] == true
            AddButton(listBox, string.format("%s (@%s)%s - %s", p.DisplayName, p.Name,
                p == Player and " [kamu]" or "", here and "di world" or "di luar world"), function()
                Info.Select(p)
            end, Info.selected == p and C.cardOn or C.card)
        end
    end

    local function RenderDetail()
        ClearBox(detailBox)
        local player = Info.selected
        if not player then
            AddLabel(detailBox, "Pilih pemain di daftar, atau ketik " .. cfg.prefix .. "pinfo <nama>.")
            return
        end
        if not player.Parent then
            AddLabel(detailBox, "Pemain itu sudah keluar dari server.")
            return
        end
        local labels = AddRows(detailBox, Info.PlayerData(player))
        Info.FetchLevel(player, function(text)
            local label = labels.level
            if label and label.Parent and Info.selected == player then
                label.Text = text
            end
        end)
        AddButton(detailBox, "Salin ringkasan pemain", function()
            if setclipboard then
                pcall(setclipboard, Info.PlayerSummary(player))
            end
            Notify("Ringkasan pemain disalin.")
        end)
        AddButton(detailBox, "Refresh detail", RenderDetail)
    end

    Info.renderList = RenderList
    Info.renderDetail = RenderDetail
    RenderList(true)
    RenderDetail()

    task.spawn(function()
        local ticks = 0
        while ui.window == owner and owner and owner.Parent do
            task.wait(2)
            ticks = ticks + 1
            if owner.Visible and ui.active == "profile" then
                pcall(UpdateServer)
                pcall(RenderList, false)
                if ticks % 10 == 0 then
                    Info.RefreshRemote(UpdateServer)
                end
            end
        end
        Info.renderList = nil
        Info.renderDetail = nil
    end)
end

function Info.Select(player)
    Info.selected = player
    if Info.renderList then
        pcall(Info.renderList, true)
    end
    if Info.renderDetail then
        pcall(Info.renderDetail)
    end
end

-- Halaman: Fitur (gerak) ------------------------------------------------
local function BuildMovePage(page)
    AddSection(page, "Gerak")
    AddToggle(page, "Click TP", function() return cfg.clickTp end, function(on)
        SetClickTp(on)
    end)
    AddToggle(page, "Click TP: tahan Shift", function() return cfg.shiftOnly end, function(on)
        cfg.shiftOnly = on
        SaveConfig()
    end)
    AddToggle(page, "Noclip (ghost)", function() return Noclip.on end, function(on)
        if on then
            Noclip.Start()
        else
            Noclip.Stop()
        end
    end)
    AddButton(page, "Turun 1 tile (noclip)", function()
        if not Noclip.StepDown() then
            Notify("Tidak bisa turun (posisi tidak terbaca atau sudah di dasar).")
        end
    end)
    AddLabel(page, "Click TP: klik tile tujuan. Noclip = mode ghost game: terbang tembus block "
        .. "(kiri/kanan, lompat = naik). Saat Noclip aktif ada tombol Turun melayang di layar: tahan untuk turun.")

    AddSection(page, "Aman")
    AddToggle(page, "God mode", function() return godOn end, function(on)
        if on then
            StartGod()
        else
            StopGod()
        end
    end)
    AddLabel(page, "God: lava, spike, api tidak melukai (client saja).")
end

-- Halaman: Setting ------------------------------------------------------
local function BuildSettingsPage(page)
    AddSection(page, "Tampilan GUI")
    AddInput(page, "Skala GUI (0.6 - 1.6)", cfg.uiScale, "1", function(text, box)
        local value = tonumber(text)
        if value and ui.setScale then
            ui.setScale(value)
        end
        box.Text = tostring(cfg.uiScale)
    end)
    AddButton(page, "Reset posisi dan skala GUI", function()
        if ui.resetLayout then
            ui.resetLayout()
        end
    end)
    AddSection(page, "Umum")
    AddInput(page, "Prefix command", cfg.prefix, "/", function(text, box)
        local value = Trim(text)
        if value ~= "" and #value <= 3 and not value:find("%s") then
            cfg.prefix = value
            SaveConfig()
            Notify("Prefix: " .. value)
        else
            box.Text = cfg.prefix
            Notify("Prefix 1-3 karakter, tanpa spasi.")
        end
    end)
    AddToggle(page, "Click TP aktif", function() return cfg.clickTp end, function(on)
        SetClickTp(on)
    end)
    AddToggle(page, "Click TP: tahan Shift", function() return cfg.shiftOnly end, function(on)
        cfg.shiftOnly = on
        SaveConfig()
    end)

    AddSection(page, "Drop")
    AddInput(page, "Jumlah /cd", cfg.amount, "1", function(text, box)
        cfg.amount = math.max(1, math.floor(tonumber(text) or cfg.amount))
        box.Text = tostring(cfg.amount)
        SaveConfig()
    end)

    AddSection(page, "Alat")
    AddButton(page, "Cek status (world/posisi/kamera)", function()
        cam = nil
        Notify(Diag())
    end, C.accent)
    AddButton(page, "Reset pengaturan", function()
        cfg.prefix, cfg.lock, cfg.amount, cfg.shiftOnly = "/", "wl", 1, false
        cfg.lockIds = {}
        lockCache = {}
        SetClickTp(false)
        SaveConfig()
        for _, refresh in ipairs(ui.refreshers) do
            pcall(refresh)
        end
        Notify("Pengaturan direset.")
    end)
    AddButton(page, "Tutup & hapus GUI", function()
        SetClickTp(false)
        Farm.Stop()
        Noclip.Stop()
        StopGod()
        genv.GrowlockToolsLoaded = nil
        if ui.gui then
            ui.gui:Destroy()
        end
    end, C.bad)
    AddLabel(page, "PeexHubs | GrowLock v0.10. Command: " .. cfg.prefix .. "gt, " .. cfg.prefix .. "cd, "
        .. cfg.prefix .. "ctp, " .. cfg.prefix .. "noclip, " .. cfg.prefix .. "god, " .. cfg.prefix .. "gstatus")
end

-- Halaman: Farm --------------------------------------------------------
local function BuildFarmPage(page)
    AddSection(page, "Auto Farm")
    AddToggle(page, "Auto Farm", function() return Farm.on end, function(on)
        if on then
            Farm.Start()
        else
            Farm.Stop("Dimatikan")
        end
    end)
    AddToggle(page, "Auto Collect", function() return cfg.farmCollect end, function(on)
        cfg.farmCollect = on
        SaveConfig()
    end)
    AddInput(page, "Delay hit/place (detik)", cfg.farmDelay, "0.22", function(text, box)
        local value = tonumber(text)
        if not value then
            box.Text = tostring(cfg.farmDelay)
            Notify("Isi angka, minimal 0.01.")
            return
        end
        cfg.farmDelay = math.clamp(value, 0.01, 5)
        box.Text = tostring(cfg.farmDelay)
        SaveConfig()
    end)
    AddLabel(page, "Game membatasi pukulan minimal 0.22 dtk dan place minimal 0.2 dtk. Delay di bawah itu otomatis dinaikkan supaya tidak kena kick.")

    AddSection(page, "Area 5x5 (tengah = posisimu)")
    -- Grid dibuat persegi (lebar = tinggi), dikunci di tengah lewat AnchorPoint
    -- + Position fromScale supaya selalu rapi di tengah berapa pun lebar
    -- panel-nya (sebelumnya lebar dibiarkan 1,0 / selebar panel, jadi grid
    -- bisa kelihatan "mengambang" tidak center kalau lebar panel berubah).
    local CELL, GAP = 36, 5
    local GRID_SIDE = CELL * 5 + GAP * 4
    local gridHolder = New("Frame", {
        Size = UDim2.new(1, 0, 0, GRID_SIDE),
        BackgroundTransparency = 1,
        LayoutOrder = NextOrder(page),
    }, page)
    local gridFrame = New("Frame", {
        Size = UDim2.fromOffset(GRID_SIDE, GRID_SIDE),
        Position = UDim2.fromScale(0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor3 = C.window,
        BorderSizePixel = 0,
    }, gridHolder)
    Round(gridFrame, 10)
    Outline(gridFrame, 2)
    New("UIPadding", {
        PaddingLeft = UDim.new(0, 0), PaddingRight = UDim.new(0, 0),
        PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 0),
    }, gridFrame)
    New("UIGridLayout", {
        CellSize = UDim2.fromOffset(CELL, CELL),
        CellPadding = UDim2.fromOffset(GAP, GAP),
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, gridFrame)
    local cellButtons, cellStrokes = {}, {}
    local function PaintCells()
        for key, button in pairs(cellButtons) do
            local on = cfg.farmGrid[key] and true or false
            button.BackgroundColor3 = on and C.cardOn or C.card
            local stroke = cellStrokes[key]
            if stroke then
                stroke.Color = on and C.accent or C.ink
                stroke.Thickness = on and 3 or 1.5
            end
        end
    end
    local order = 0
    for dy = -2, 2 do
        for dx = -2, 2 do
            order += 1
            local key = dx .. "," .. dy
            if dx == 0 and dy == 0 then
                local me = New("TextLabel", {
                    BackgroundColor3 = C.accent,
                    Text = "Kamu",
                    TextColor3 = C.card,
                    Font = FONT,
                    TextSize = 10,
                    BorderSizePixel = 0,
                    LayoutOrder = order,
                }, gridFrame)
                Round(me, 6)
                Outline(me, 2)
            else
                local button = New("TextButton", {
                    BackgroundColor3 = C.card,
                    Text = string.format("%d,%d", dx, dy),
                    TextColor3 = C.mute,
                    Font = FONT_BODY,
                    TextSize = 9,
                    AutoButtonColor = true,
                    BorderSizePixel = 0,
                    LayoutOrder = order,
                }, gridFrame)
                Round(button, 6)
                local stroke = Outline(button, 1.5)
                button.MouseButton1Click:Connect(function()
                    cfg.farmGrid[key] = (not cfg.farmGrid[key]) or nil
                    SaveConfig()
                    PaintCells()
                end)
                cellButtons[key] = button
                cellStrokes[key] = stroke
            end
        end
    end
    PaintCells()
    table.insert(ui.refreshers, PaintCells)

    local gridButtonsRow = New("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundTransparency = 1,
        LayoutOrder = NextOrder(page),
    }, page)
    New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, gridButtonsRow)
    local function GridMiniButton(text, order2, callback)
        local button = New("TextButton", {
            Size = UDim2.fromOffset(150, 32),
            BackgroundColor3 = C.card,
            Text = text,
            TextColor3 = C.text,
            Font = FONT_BODY,
            TextSize = 12,
            BorderSizePixel = 0,
            LayoutOrder = order2,
        }, gridButtonsRow)
        Round(button, 8)
        Outline(button, 2)
        button.MouseButton1Click:Connect(callback)
        return button
    end
    GridMiniButton("Pilih semua tile", 1, function()
        for key in pairs(cellButtons) do
            cfg.farmGrid[key] = true
        end
        SaveConfig()
        PaintCells()
    end)
    GridMiniButton("Kosongkan pilihan", 2, function()
        cfg.farmGrid = {}
        SaveConfig()
        PaintCells()
    end)

    AddSection(page, "Block dari inventory")
    local selectedLabel = AddLabel(page, "", C.text, 11)
    local listBox = MakeBox(page)
    local function PaintSelected()
        local name = cfg.farmId > 0 and (ItemName(cfg.farmId) or ("Item " .. cfg.farmId)) or "belum dipilih"
        selectedLabel.Text = "Terpilih: " .. name
    end
    local function FillList()
        ClearBox(listBox)
        local items = Farm.Inventory()
        if #items == 0 then
            AddLabel(listBox, "Inventory kosong atau belum terbaca (masuk world dulu).")
            return
        end
        for _, item in ipairs(items) do
            local button = AddButton(listBox, string.format("%s  x%d", item.name, item.n), function()
                cfg.farmId = item.id
                SaveConfig()
                PaintSelected()
                FillList()
            end, cfg.farmId == item.id and C.cardOn or C.card)
            button.TextSize = 11
        end
    end
    PaintSelected()
    FillList()
    AddButton(page, "Refresh inventory", function()
        PaintSelected()
        FillList()
    end, C.accent)

    AddSection(page, "Status")
    local labels = AddRows(page, {
        { key = "status", label = "Status" },
        { key = "cycles", label = "Siklus" },
        { key = "placed", label = "Place" },
        { key = "broken", label = "Break" },
        { key = "picked", label = "Collect" },
    })
    local function PaintStats()
        labels.status.Text = Farm.status
        labels.cycles.Text = tostring(Farm.stats.cycles)
        labels.placed.Text = tostring(Farm.stats.placed)
        labels.broken.Text = tostring(Farm.stats.broken)
        labels.picked.Text = tostring(Farm.stats.picked)
    end
    PaintStats()
    table.insert(ui.refreshers, PaintStats)
    task.spawn(function()
        while labels.status.Parent do
            task.wait(0.4)
            if page.Visible then
                pcall(PaintStats)
            end
        end
    end)
    AddLabel(page, "Pilih tile hijau, pilih block, lalu nyalakan Auto Farm. Area dikunci di posisi saat dinyalakan. "
        .. "Siklus: place, break sampai pecah, collect. Command: " .. cfg.prefix .. "af, "
        .. cfg.prefix .. "afdelay <detik>, " .. cfg.prefix .. "afid <nama|id>")
end

-- Halaman: Visual ------------------------------------------------------
local function BuildVisualPage(page)
    AddSection(page, "Item Visual")
    AddLabel(page, "Tekan item untuk memasukkannya ke inventory, tekan lagi untuk menghapus. "
        .. "Pakaian bisa kamu equip dan unequip sendiri dari inventory game. "
        .. "Hanya tampilan di layarmu: server tidak punya item ini, jadi tidak bisa ditaruh, di-drop, atau di-trade.")
    local query = ""
    local cats = { "semua", "pakaian", "block", "lock", "seed", "alat" }
    local catIndex = 1
    local box

    local function Fill()
        ClearBox(box)
        local list = Visual.Items()
        if not list then
            AddLabel(box, "ItemDB game belum terbaca (masuk world dulu).")
            return
        end
        local shown, q, cat = 0, query:lower(), cats[catIndex]
        for _, entry in ipairs(list) do
            if (cat == "semua" or entry.cat == cat) and (q == "" or entry.lower:find(q, 1, true)) then
                shown += 1
                if shown > 40 then
                    AddLabel(box, "Masih banyak, persempit pencarian (maks 40 ditampilkan).")
                    break
                end
                local granted = Visual.Granted(entry.id)
                local label = (granted > 0 and string.format("[ADA x%d] ", granted) or "") .. entry.name .. "  (" .. entry.cat .. ")"
                local button = AddButton(box, label, function()
                    if Visual.Granted(entry.id) > 0 then
                        Visual.Take(entry.id)
                    else
                        Visual.Give(entry.id, cfg.visualAmount)
                    end
                    Fill()
                end, granted > 0 and C.cardOn or C.card)
                button.TextSize = 11
            end
        end
        if shown == 0 then
            AddLabel(box, "Tidak ada item yang cocok.")
        end
    end

    AddInput(page, "Cari item", "", "nama item", function(text)
        query = Trim(text)
        Fill()
    end)
    local catButton
    catButton = AddButton(page, "Kategori: semua", function()
        catIndex = catIndex % #cats + 1
        catButton.Text = "Kategori: " .. cats[catIndex]
        Fill()
    end)
    AddInput(page, "Jumlah per tekan (1-200)", cfg.visualAmount, "1", function(text, inputBox)
        local value = tonumber(text)
        if value then
            cfg.visualAmount = math.clamp(math.floor(value), 1, 200)
            SaveConfig()
        end
        inputBox.Text = tostring(cfg.visualAmount)
    end)
    AddButton(page, "Hapus semua item visual", function()
        Visual.Clear()
        Fill()
    end, C.bad)
    box = MakeBox(page)
    Fill()
    table.insert(ui.refreshers, Fill)
end

-- Halaman: Update Log ---------------------------------------------------
local function BuildLogPage(page)
    for _, entry in ipairs(UPDATE_LOG) do
        AddSection(page, entry.version .. (entry.date and ("  (" .. entry.date .. ")") or ""))
        for _, note in ipairs(entry.notes) do
            AddLabel(page, "- " .. note, C.text, 10)
        end
    end
end

local TABS = {
    { id = "move", label = "Fitur", build = BuildMovePage },
    { id = "farm", label = "Farm", build = BuildFarmPage },
    { id = "visual", label = "Visual", build = BuildVisualPage },
    { id = "drop", label = "Drop", build = BuildDropPage },
    { id = "profile", label = "Info", build = BuildProfilePage },
    { id = "log", label = "Log", build = BuildLogPage },
    { id = "setting", label = "Setting", build = BuildSettingsPage },
}

local function SwitchTab(id)
    ui.active = id
    for tabId, page in pairs(ui.pages) do
        page.Visible = (tabId == id)
    end
    for tabId, button in pairs(ui.tabs) do
        button.BackgroundColor3 = (tabId == id) and C.cardOn or C.card
    end
    for _, refresh in ipairs(ui.refreshers) do
        pcall(refresh)
    end
end

local function OpenWindow(tabId)
    if ui.window and ui.window.Parent then
        ui.window.Visible = true
        SwitchTab(tabId or ui.active or "move")
        return
    end
    local viewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(800, 600)
    -- landscape: lebar sekitar 60% layar, tinggi sekitar 64%, tidak pernah memenuhi layar
    local width = math.clamp(math.floor(viewport.X * 0.6), 380, 580)
    local height = math.clamp(math.floor(viewport.Y * 0.64), 250, 340)

    local window = New("Frame", {
        Name = "Window",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(width, height),
        Position = UDim2.new(0.5, cfg.winX, 0.5, cfg.winY),
        BackgroundColor3 = C.window,
        BorderSizePixel = 0,
        Active = true,
    }, GetGui())
    Round(window, 14)
    Outline(window, 3)
    ui.window = window
    ui.pages, ui.tabs, ui.refreshers = {}, {}, {}

    -- skala GUI (tersimpan); dibatasi supaya window tidak melebihi layar
    local function MaxScale()
        local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or viewport
        return math.max(0.6, math.min(1.6, vp.X * 0.92 / width, vp.Y * 0.92 / height))
    end
    local scaleObj = New("UIScale", { Scale = math.clamp(cfg.uiScale, 0.6, MaxScale()) }, window)
    function ui.setScale(value)
        value = math.floor((tonumber(value) or 1) * 20 + 0.5) / 20
        cfg.uiScale = math.clamp(value, 0.6, MaxScale())
        scaleObj.Scale = cfg.uiScale
        SaveConfig()
    end
    function ui.resetLayout()
        cfg.winX, cfg.winY = 0, 0
        window.Position = UDim2.new(0.5, 0, 0.5, 0)
        ui.setScale(1)
    end

    local header = New("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = C.header,
        BorderSizePixel = 0,
    }, window)
    Round(header, 14)
    -- tutup sudut bawah header supaya rata dengan isi
    New("Frame", {
        Position = UDim2.new(0, 0, 1, -10),
        Size = UDim2.new(1, 0, 0, 10),
        BackgroundColor3 = C.header,
        BorderSizePixel = 0,
    }, header)
    New("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -90, 1, 0),
        Text = "PeexHubs | GrowLock v0.10",
        TextColor3 = Color3.new(1, 1, 1),
        Font = FONT,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 2,
    }, header)
    New("UIStroke", {
        Color = C.ink, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
    }, header:FindFirstChildOfClass("TextLabel"))
    local close = New("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -6, 0.5, 0),
        Size = UDim2.fromOffset(20, 20),
        BackgroundColor3 = C.bad,
        Text = "X",
        TextColor3 = Color3.new(1, 1, 1),
        Font = FONT,
        TextSize = 12,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, header)
    Round(close, 10)
    Outline(close, 2)
    close.MouseButton1Click:Connect(function()
        window.Visible = false
    end)
    local function HeaderButton(text, offset)
        local button = New("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, offset, 0.5, 0),
            Size = UDim2.fromOffset(20, 20),
            BackgroundColor3 = C.card,
            Text = text,
            TextColor3 = C.text,
            Font = FONT,
            TextSize = 13,
            BorderSizePixel = 0,
            ZIndex = 2,
        }, header)
        Round(button, 10)
        Outline(button, 2)
        return button
    end
    HeaderButton("+", -32).MouseButton1Click:Connect(function()
        ui.setScale(cfg.uiScale + 0.1)
    end)
    HeaderButton("-", -56).MouseButton1Click:Connect(function()
        ui.setScale(cfg.uiScale - 0.1)
    end)

    -- drag lewat header
    local dragging, dragStart, startPos = false, nil, nil
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, window.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    cfg.winX, cfg.winY = window.Position.X.Offset, window.Position.Y.Offset
                    SaveConfig()
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(800, 600)
            local limitX, limitY = vp.X / 2 - 30, vp.Y / 2 - 20
            window.Position = UDim2.new(0.5, math.clamp(startPos.X.Offset + delta.X, -limitX, limitX),
                0.5, math.clamp(startPos.Y.Offset + delta.Y, -limitY, limitY))
        end
    end)

    -- tab di sisi kiri (layout landscape)
    local tabBar = New("Frame", {
        Position = UDim2.fromOffset(6, 34),
        Size = UDim2.new(0, 78, 1, -40),
        BackgroundTransparency = 1,
    }, window)
    New("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, tabBar)

    local body = New("Frame", {
        Position = UDim2.fromOffset(90, 34),
        Size = UDim2.new(1, -94, 1, -38),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
    }, window)

    for index, tab in ipairs(TABS) do
        local button = New("TextButton", {
            Size = UDim2.new(1, 0, 0, 25),
            BackgroundColor3 = C.card,
            Text = tab.label,
            TextColor3 = C.text,
            Font = FONT,
            TextSize = 11,
            BorderSizePixel = 0,
            LayoutOrder = index,
        }, tabBar)
        Round(button, 7)
        Outline(button, 2)
        button.MouseButton1Click:Connect(function()
            SwitchTab(tab.id)
        end)
        ui.tabs[tab.id] = button

        local page = New("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = C.ink,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = false,
        }, body)
        New("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, page)
        New("UIPadding", {
            PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 9),
            PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8),
        }, page)
        ui.pages[tab.id] = page
        local okBuild, err = pcall(tab.build, page)
        if not okBuild then
            AddLabel(page, "Gagal memuat halaman: " .. tostring(err), C.bad)
        end
    end
    SwitchTab(tabId or "move")
end

local function ToggleWindow()
    if ui.window and ui.window.Parent and ui.window.Visible then
        ui.window.Visible = false
    else
        OpenWindow()
    end
end

local function BuildLauncher()
    local button = New("TextButton", {
        Name = "Launcher",
        Position = UDim2.new(0, 8, 0.5, -16),
        Size = UDim2.fromOffset(32, 32),
        BackgroundColor3 = C.header,
        Text = "PH",
        TextColor3 = Color3.new(1, 1, 1),
        Font = FONT,
        TextSize = 13,
        BorderSizePixel = 0,
    }, GetGui())
    Round(button, 16)
    Outline(button, 2.5)
    button.MouseButton1Click:Connect(ToggleWindow)
end

----------------------------------------------------------------------
-- COMMAND
----------------------------------------------------------------------
local function WantedState(arg, current)
    if arg == "on" then
        return true
    elseif arg == "off" then
        return false
    end
    return not current
end

local function HandleMessage(text)
    text = Trim(text)
    local prefix = cfg.prefix
    if text == "" or text:sub(1, #prefix) ~= prefix then
        return false
    end
    local body = text:sub(#prefix + 1)
    local command, rest = body:match("^(%S+)%s*(.-)%s*$")
    if not command then
        return false
    end
    command = command:lower()
    local args = {}
    for word in rest:gmatch("%S+") do
        table.insert(args, word)
    end

    if command == "cd" then
        local amount, lock = nil, nil
        for _, word in ipairs(args) do
            local number = tonumber(word)
            if number then
                amount = number
            else
                lock = ParseLock(word) or lock
            end
        end
        if not amount then
            local current = LockByKey(cfg.lock)
            local id = ResolveLock(current)
            local have = id and CountItem(id)
            Notify(string.format("Pakai: %scd <jumlah> [lock]. Lock sekarang: %s (punya %s)",
                prefix, current.name, have ~= nil and tostring(have) or "?"))
        else
            DropLock(amount, lock)
        end
        return true

    elseif command == "cdset" or command == "cdlock" then
        local lock = ParseLock(args[1])
        if not lock then
            Notify("Lock tidak dikenal. Pilih: wl, dl, bgl, small, big, huge")
        else
            cfg.lock = lock.key
            SaveConfig()
            local id = ResolveLock(lock)
            Notify(string.format("Lock /cd: %s (id %s)", lock.name, id and tostring(id) or "tidak ketemu"))
            for _, refresh in ipairs(ui.refreshers) do
                pcall(refresh)
            end
        end
        return true

    elseif command == "cdid" then
        local lock = ParseLock(args[1])
        local id = tonumber(args[2])
        if not lock or not id then
            Notify("Contoh: " .. prefix .. "cdid wl 242")
        else
            cfg.lockIds[lock.key] = id
            lockCache[lock.key] = nil
            SaveConfig()
            Notify(string.format("ID %s diset ke %d (%s)", lock.name, id, ItemName(id) or "?"))
        end
        return true

    elseif command == "ctp" or command == "clicktp" then
        SetClickTp(WantedState(args[1], cfg.clickTp))
        return true

    elseif command == "noclip" or command == "nc" or command == "ghost" then
        if WantedState(args[1], Noclip.on) then
            Noclip.Start()
        else
            Noclip.Stop()
        end
        for _, refresh in ipairs(ui.refreshers) do
            pcall(refresh)
        end
        return true

    elseif command == "gstatus" or command == "status" then
        cam = nil
        Notify(Diag())
        return true

    elseif command == "god" or command == "godmode" then
        if WantedState(args[1], godOn) then
            StartGod()
        else
            StopGod()
        end
        return true

    elseif command == "pinfo" or command == "pi" or command == "playerinfo" then
        if rest == "" then
            OpenWindow("profile")
        else
            local found = Info.Find(rest)
            if found then
                Info.Select(found)
                OpenWindow("profile")
                Notify(Info.PlayerSummary(found))
            else
                Notify("Pemain tidak ditemukan: " .. rest)
            end
        end
        return true

    elseif command == "log" or command == "updatelog" or command == "changelog" then
        OpenWindow("log")
        return true

    elseif command == "sinfo" or command == "serverinfo" or command == "si" then
        OpenWindow("profile")
        Notify(Info.ServerSummary())
        return true

    elseif command == "af" or command == "autofarm" then
        local want = WantedState(args[1], Farm.on)
        if want then
            Farm.Start()
        else
            Farm.Stop("Dimatikan")
        end
        for _, refresh in ipairs(ui.refreshers) do
            pcall(refresh)
        end
        return true

    elseif command == "afdelay" then
        local value = tonumber(args[1])
        if value then
            cfg.farmDelay = math.clamp(value, 0.01, 5)
            SaveConfig()
            Notify("Delay Auto Farm: " .. cfg.farmDelay .. " detik")
        else
            Notify("Pakai: " .. prefix .. "afdelay <detik> (hit minimal 0.22, place minimal 0.2)")
        end
        return true

    elseif command == "afid" then
        local query = rest
        local id = tonumber(query) or FindItemIdByName(query)
        if id then
            cfg.farmId = id
            SaveConfig()
            Notify("Block Auto Farm: " .. (ItemName(id) or id))
        else
            Notify("Item tidak ditemukan: " .. tostring(query))
        end
        return true

    elseif command == "vi" or command == "visual" then
        OpenWindow("visual")
        return true

    elseif command == "gt" or command == "growlocktools" then
        ToggleWindow()
        return true
    end
    return false
end

----------------------------------------------------------------------
-- DETEKSI CHAT (chat game memakai TextBox sendiri, jadi hook semua TextBox)
----------------------------------------------------------------------
local hooked = {}
local lastMessage, lastHandled = nil, 0

local function Process(text)
    if type(text) ~= "string" then
        return
    end
    local normalized = Trim(text):lower()
    if normalized == lastMessage and os.clock() - lastHandled < 1.5 then
        return
    end
    if HandleMessage(text) then
        lastMessage = normalized
        lastHandled = os.clock()
    end
end

local function HookTextBox(box)
    if hooked[box] or not box:IsA("TextBox") then
        return
    end
    if ui.gui and box:IsDescendantOf(ui.gui) then
        return
    end
    hooked[box] = true
    local lastText = ""
    box:GetPropertyChangedSignal("Text"):Connect(function()
        if box.Text ~= "" then
            lastText = box.Text
        end
    end)
    box.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            local text = box.Text ~= "" and box.Text or lastText
            lastText = ""
            Process(text)
        end
    end)
end

for _, descendant in ipairs(PlayerGui:GetDescendants()) do
    HookTextBox(descendant)
end
PlayerGui.DescendantAdded:Connect(HookTextBox)
Player.Chatted:Connect(Process)

BuildLauncher()
if cfg.clickTp then
    clickConn = UserInputService.InputBegan:Connect(OnClick)
end

-- Pulihkan fitur yang terakhir aktif begitu sudah masuk world
task.spawn(function()
    local started = os.clock()
    while os.clock() - started < 120 and not InWorld(FindWorld()) do
        task.wait(1)
    end
    if not InWorld(FindWorld()) then
        return
    end
    task.wait(1.5)
    if cfg.noclip then
        pcall(Noclip.Start)
    end
    if cfg.god then
        pcall(StartGod)
    end
    if next(cfg.visual) ~= nil then
        pcall(Visual.Reapply)
    end
end)

if FindInventory() or InWorld(FindWorld()) then
    Notify("PeexHubs | GrowLock v0.10 aktif. Ketik " .. cfg.prefix .. "gt atau tekan tombol GT.")
else
    Notify("Aktif. Belum masuk world / inventory belum terbaca; ketik " .. cfg.prefix .. "gstatus untuk cek.")
end
