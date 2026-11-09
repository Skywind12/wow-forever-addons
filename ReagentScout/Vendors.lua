-- Where can I buy this item? Forever vendor data (built in, or QuestieDB if installed)
-- plus vendors you've visited,
-- sorted by zone and distance from you.
local _, ns = ...

local V = {}
ns.Vendors = V

------------------------------------------------------------------------
-- QuestieDB access
------------------------------------------------------------------------
local QDB = {}
ns.QDB = QDB

function QDB.Ready()
    if type(LibQuestieDB) ~= "table" or type(ItemDB) ~= "table" or type(NpcDB) ~= "table" then
        return false, "LibQuestieDB is not loaded"
    end
    if LibQuestieDB.RequireContract then
        local ok, msg = LibQuestieDB.RequireContract(1)
        if not ok then return false, tostring(msg) end
    end
    return true, "ok"
end

local function Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
    return nil
end

-- QuestieDB stores spawns by AreaID; the game's map functions want a UiMapID.
-- QuestieDB ships the conversion table as Lua source strings.
local areaToUiMap, zoneMapError

local function LoadTable(src)
    if type(src) == "table" then return src end
    if type(src) ~= "string" then return nil end
    local chunk = loadstring(src)
    if not chunk then return nil end
    local ok, t = pcall(chunk)
    return ok and type(t) == "table" and t or nil
end

local function BuildZoneMap()
    if areaToUiMap or zoneMapError then return end
    local zoneDB = LibQuestieDB.Support and Safe(LibQuestieDB.Support.Get, "ZoneDB")
    local private = type(zoneDB) == "table" and zoneDB.private
    if type(private) ~= "table" then
        zoneMapError = "QuestieDB has no ZoneDB support data"
        return
    end
    local map = {}
    local base = LoadTable(private.areaIdToUiMapId)
    local override = LoadTable(private.areaIdToUiMapIdOverride)
    for k, v in pairs(base or {}) do map[k] = v end
    for k, v in pairs(override or {}) do map[k] = v end
    if next(map) == nil then
        zoneMapError = "zone table was empty"
        return
    end
    areaToUiMap = map
end

function QDB.ZoneMapStatus()
    BuildZoneMap()
    if areaToUiMap then
        local n = 0
        for _ in pairs(areaToUiMap) do n = n + 1 end
        return "|cff55ff55" .. n .. " zones|r"
    end
    return "|cffffcc00unavailable|r (" .. tostring(zoneMapError) .. "), grouping by zone name only"
end

local function AreaToUiMap(areaID)
    if QDB.Ready() then BuildZoneMap() end
    local id = areaToUiMap and areaToUiMap[areaID]
    if not id and ns.data then id = ns.data.zones[areaID] end
    if id and id > 0 then return id end
    return nil
end

------------------------------------------------------------------------
-- Vendor data: QuestieDB when it's installed, otherwise the Forever data
-- bundled in Data.lua (extracted from QuestieDB's Forever set).
------------------------------------------------------------------------
local function VendorIDs(itemID)
    if QDB.Ready() then
        local v = Safe(ItemDB.vendors, itemID)
        if type(v) == "table" and #v > 0 then return v end
    end
    return ns.data and ns.data.items[itemID]
end

-- Returns name, subName, friendlyTo, points ({ {areaID, x, y}, ... }) or nil.
local function NpcInfo(npcID)
    if QDB.Ready() then
        local spawns = Safe(NpcDB.spawns, npcID)
        if type(spawns) == "table" then
            local points = {}
            for areaID, list in pairs(spawns) do
                for _, p in ipairs(list) do points[#points + 1] = { areaID, p[1], p[2] } end
            end
            return Safe(NpcDB.name, npcID), Safe(NpcDB.subName, npcID), Safe(NpcDB.friendlyToFaction, npcID), points
        end
    end
    local row = ns.data and ns.data.npcs[npcID]
    if not row then return nil end
    local points, flat = {}, row[4]
    for i = 1, #flat, 3 do points[#points + 1] = { flat[i], flat[i + 1], flat[i + 2] } end
    return row[1], row[2], row[3], points
end

function V.SourceText()
    local ok = QDB.Ready()
    if ok then return "QuestieDB (installed)" end
    local items, npcs = 0, 0
    for _ in pairs(ns.data and ns.data.items or {}) do items = items + 1 end
    for _ in pairs(ns.data and ns.data.npcs or {}) do npcs = npcs + 1 end
    return ("built-in Forever data (%d reagents, %d vendors)"):format(items, npcs)
end

------------------------------------------------------------------------
-- Positions and zones
------------------------------------------------------------------------

local ZONE_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

-- Climb from a sub-map (a building, a city district) to the zone it belongs to.
local function ZoneOf(uiMapID)
    local id, guard = uiMapID, 0
    while id and guard < 10 do
        local info = Safe(C_Map.GetMapInfo, id)
        if not info then break end
        if info.mapType == ZONE_TYPE then return id, info.name end
        if info.mapType and info.mapType < ZONE_TYPE then break end -- reached continent/world
        id, guard = info.parentMapID, guard + 1
    end
    local info = Safe(C_Map.GetMapInfo, uiMapID)
    return uiMapID, info and info.name
end

local function WorldPos(uiMapID, x01, y01)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, CreateVector2D(x01, y01))
    if not ok or not continent or not pos then return nil end
    local wx, wy = pos:GetXY()
    return continent, wx, wy
end

-- Returns uiMapID, x, y (0-100) of the player, or nil when the client won't say
-- (inside instances, or when the value is restricted).
function V.PlayerPosition()
    local mapID = Safe(C_Map.GetBestMapForUnit, "player")
    if not mapID or not ns.CanRead(mapID) then return nil end
    local pos = Safe(C_Map.GetPlayerMapPosition, mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not ns.CanRead(x) or not x or (x == 0 and y == 0) then return nil end
    return mapID, x * 100, y * 100
end

local function PlayerContext()
    local ctx = {}
    local mapID, x, y = V.PlayerPosition()
    if mapID then
        ctx.zoneMap, ctx.zoneName = ZoneOf(mapID)
        ctx.continent, ctx.wx, ctx.wy = WorldPos(mapID, x / 100, y / 100)
    end
    ctx.zoneName = ctx.zoneName or GetRealZoneText()
    local faction = UnitFactionGroup("player")
    ctx.faction = (faction == "Alliance" and "A") or (faction == "Horde" and "H") or nil
    return ctx
end

------------------------------------------------------------------------
-- Building the vendor list for one item
------------------------------------------------------------------------
-- A candidate: { npcID, name, sub, zoneName, map, x, y, dist, continent, source }
local function Place(ctx, cand, uiMapID, x, y)
    cand.map, cand.x, cand.y = uiMapID, x, y
    local zoneMap, zoneName = ZoneOf(uiMapID)
    cand.zoneMap = zoneMap
    cand.zoneName = cand.zoneName or zoneName
    local continent, wx, wy = WorldPos(uiMapID, x / 100, y / 100)
    cand.continent = continent
    cand.otherContinent = continent ~= nil and ctx.continent ~= nil and continent ~= ctx.continent
    if continent and ctx.continent == continent and ctx.wx then
        local dx, dy = wx - ctx.wx, wy - ctx.wy
        cand.dist = math.sqrt(dx * dx + dy * dy) -- world units are yards
    end
end

local function FromDatabase(ctx, itemID, out, seen)
    local vendors = VendorIDs(itemID)
    if type(vendors) ~= "table" then return end
    for _, npcID in ipairs(vendors) do
        local name, sub, friendly, points = NpcInfo(npcID)
        local hostile = ctx.faction and friendly and not friendly:find(ctx.faction, 1, true)
            and not (ns.db and ns.db.otherFaction)
        if points and not hostile and not seen[npcID] then
            local best
            for _, p in ipairs(points) do
                local areaID, x, y = p[1], p[2], p[3]
                if x and y and x >= 0 and y >= 0 then
                    local cand = { npcID = npcID, source = "database" }
                    local uiMapID = AreaToUiMap(areaID)
                    if uiMapID then
                        Place(ctx, cand, uiMapID, x, y)
                    else
                        local area = C_Map.GetAreaInfo and Safe(C_Map.GetAreaInfo, areaID)
                        cand.zoneName, cand.x, cand.y = area or ("zone " .. areaID), x, y
                    end
                    if not best or (cand.dist or math.huge) < (best.dist or math.huge) then best = cand end
                end
            end
            if best then
                best.name = name or ("NPC " .. npcID)
                best.sub = sub
                seen[npcID] = true
                out[#out + 1] = best
            end
        end
    end
end

local function FromVisited(ctx, itemID, out, seen)
    for npcID, v in pairs(ns.db and ns.db.vendors or {}) do
        if v.items and v.items[itemID] and not seen[npcID] and v.map then
            local cand = { npcID = npcID, name = v.name, sub = v.sub, source = "visited" }
            Place(ctx, cand, v.map, v.x, v.y)
            seen[npcID] = true
            out[#out + 1] = cand
        end
    end
end

-- Zones in order: yours first, then by nearest vendor on your continent,
-- then other continents alphabetically. Vendors inside each zone nearest first.
function V.Lookup(itemID)
    local ctx = PlayerContext()
    local list, seen = {}, {}
    FromVisited(ctx, itemID, list, seen)
    FromDatabase(ctx, itemID, list, seen)

    local zones, byName = {}, {}
    for _, c in ipairs(list) do
        local key = c.zoneName or "Unknown"
        local z = byName[key]
        if not z then
            z = { name = key, vendors = {}, isHere = (key == ctx.zoneName) }
            byName[key] = z
            zones[#zones + 1] = z
        end
        z.vendors[#z.vendors + 1] = c
        if c.dist and (not z.best or c.dist < z.best) then z.best = c.dist end
    end
    for _, z in ipairs(zones) do
        table.sort(z.vendors, function(a, b)
            if (a.dist ~= nil) ~= (b.dist ~= nil) then return a.dist ~= nil end
            if a.dist and b.dist and a.dist ~= b.dist then return a.dist < b.dist end
            return (a.name or "") < (b.name or "")
        end)
    end
    table.sort(zones, function(a, b)
        if a.isHere ~= b.isHere then return a.isHere end
        if (a.best ~= nil) ~= (b.best ~= nil) then return a.best ~= nil end
        if a.best and b.best and a.best ~= b.best then return a.best < b.best end
        return a.name < b.name
    end)
    return zones, #list
end

function V.Price(itemID)
    return ns.db and ns.db.prices[itemID]
end

------------------------------------------------------------------------
-- Learning prices (and vendors QuestieDB doesn't know) at the merchant window
------------------------------------------------------------------------
local function MerchantItem(i)
    local itemID = GetMerchantItemID and GetMerchantItemID(i)
    if not itemID and GetMerchantItemLink then itemID = ns.ItemIDFromLink(GetMerchantItemLink(i)) end
    if not itemID then return nil end
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = Safe(C_MerchantFrame.GetItemInfo, i)
        if not info then return nil end
        if info.hasExtendedCost or (info.price or 0) <= 0 then return itemID, nil end
        return itemID, info.price / math.max(1, info.stackCount or 1)
    elseif GetMerchantItemInfo then
        local _, _, price, quantity, _, _, _, extendedCost = GetMerchantItemInfo(i)
        if extendedCost or (price or 0) <= 0 then return itemID, nil end
        return itemID, price / math.max(1, quantity or 1)
    end
end

local function ScanMerchant()
    if not ns.db then return end
    local count = GetMerchantNumItems and GetMerchantNumItems() or 0
    if count == 0 then return end

    local guid = UnitGUID("npc")
    local npcID
    if ns.CanRead(guid) then
        local unitType, _, _, _, _, id = strsplit("-", guid)
        if unitType == "Creature" or unitType == "Vehicle" then npcID = tonumber(id) end
    end

    local items = {}
    for i = 1, count do
        local itemID, price = MerchantItem(i)
        if itemID then
            items[itemID] = true
            if price then ns.db.prices[itemID] = price end
        end
    end

    if npcID then
        local mapID, x, y = V.PlayerPosition()
        local name = UnitName("npc")
        if mapID then
            ns.db.vendors[npcID] = {
                name = ns.CanRead(name) and name or ("NPC " .. npcID),
                map = mapID, x = x, y = y, items = items,
            }
        end
    end
    if ns.Panel and ns.Panel.Refresh then ns.Panel.Refresh() end
end

ns.On("MERCHANT_SHOW", function() C_Timer.After(0.3, ScanMerchant) end)
ns.On("MERCHANT_UPDATE", function() ScanMerchant() end)
