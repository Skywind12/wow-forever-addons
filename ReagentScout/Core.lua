-- Reagent Scout: shared namespace, saved data, helpers and slash commands.
local ADDON, ns = ...

ns.name = "Reagent Scout"
ns.isForever = select(4, GetBuildInfo()) == 16001
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = GetMeta and GetMeta(ADDON, "Version") or "?"

local PREFIX = "|cff33ff99Reagent Scout|r: "
function ns.Print(...)
    print(PREFIX .. string.join(" ", tostringall(...)))
end

-- Some values (a unit's GUID or name in some states) can be "secret" on Forever:
-- an addon may hold them but not read them.
function ns.CanRead(value)
    if value == nil then return false end
    if canaccessvalue then
        local ok, readable = pcall(canaccessvalue, value)
        return ok and readable
    end
    return true
end

function ns.ItemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

function ns.GetItemName(itemID)
    local name
    if C_Item and C_Item.GetItemNameByID then
        name = C_Item.GetItemNameByID(itemID)
    elseif GetItemInfo then
        name = GetItemInfo(itemID)
    end
    if not name and ns.QDB.Ready() then
        local ok, qname = pcall(ItemDB.name, itemID)
        if ok then name = qname end
    end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID) -- fires GET_ITEM_INFO_RECEIVED later
    end
    return name or ("item " .. itemID)
end

function ns.GetItemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
    if GetItemIcon then return GetItemIcon(itemID) end
    return 134400 -- question mark
end

function ns.GetItemCount(itemID)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not fn then return 0 end
    local ok, count = pcall(fn, itemID, true) -- include bank
    return ok and count or 0
end

function ns.FormatMoney(copper)
    if not copper then return "|cff888888price unknown|r" end
    copper = math.floor(copper + 0.5)
    if GetMoneyString then
        local ok, text = pcall(GetMoneyString, copper, true) -- Blizzard's coin icons
        if ok and text then return text end
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = "|cffffd700" .. g .. "g|r" end
    if s > 0 then parts[#parts + 1] = "|cffc7c7cf" .. s .. "s|r" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = "|cffeda55f" .. c .. "c|r" end
    return table.concat(parts, " ")
end

------------------------------------------------------------------------
-- Saved data
------------------------------------------------------------------------
-- The Forever client has had a bug where SavedVariables are written at logout but
-- not loaded back at login. Vendor locations come from the built-in data and don't need
-- saved data; only prices and vendors you discovered yourself are remembered here.
ns.sv = { loaded = false }

local function InitDB()
    ns.sv.loaded = type(ReagentScoutDB) == "table" and (ReagentScoutDB.sessions or 0) > 0
    if type(ReagentScoutDB) ~= "table" then ReagentScoutDB = {} end
    local db = ReagentScoutDB
    db.version = 1
    db.sessions = (db.sessions or 0) + 1
    db.prices = db.prices or {}   -- [itemID] = copper per single item
    db.vendors = db.vendors or {} -- [npcID] = { name, map, x, y, items = { [itemID] = true } }
    db.panel = db.panel or { shown = true }
    ns.sv.lastLogout = db.lastLogout
    ns.db = db
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local events = CreateFrame("Frame")
ns.events = events
local handlers = {}

function ns.On(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
    pcall(events.RegisterEvent, events, event) -- an event that doesn't exist on this client is skipped
end

events:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, event, ...)
        if not ok then ns.Print("|cffff5555error in " .. event .. ":|r", err) end
    end
end)

ns.On("ADDON_LOADED", function(_, name)
    if name == ADDON then InitDB() end
end)

ns.On("PLAYER_LOGIN", function()
    if ns.Options and ns.Vendors and ns.Professions then
        ns.Print(("version %s loaded. Type /rscout for settings."):format(ns.version))
    else
        ns.Print("|cffff5555some files didn't load.|r Quit WoW completely and start it again (a /reload isn't enough after an update).")
    end
end)

ns.On("PLAYER_LOGOUT", function()
    if ns.db then ns.db.lastLogout = time() end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local function CountKeys(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

function ns.PrintStatus()
    ns.Print("status")
    print("  Client: " .. (ns.isForever and "WoW Forever (16001)" or ("interface " .. select(4, GetBuildInfo()))))

    print("  Vendor data: |cff55ff55" .. ns.Vendors.SourceText() .. "|r")
    if ns.QDB.Ready() then
        print("  Zone map: " .. (ns.QDB.ZoneMapStatus()))
    end

    print("  Profession API: " .. (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic and "|cff55ff55C_TradeSkillUI|r" or "|cffff5555not found|r"))
    print("  Merchant API: " .. ((C_MerchantFrame and C_MerchantFrame.GetItemInfo) and "C_MerchantFrame" or (GetMerchantItemInfo and "GetMerchantItemInfo" or "|cffff5555not found|r")))

    local db = ns.db or {}
    if ns.sv.loaded then
        print(("  Saved data: |cff55ff55loaded|r (%d prices, %d vendors you've visited, session #%d)")
            :format(CountKeys(db.prices), CountKeys(db.vendors), db.sessions or 0))
    else
        print("  Saved data: |cffffcc00nothing loaded from a previous session|r")
        print("    Fine on your first login. If you've played with Reagent Scout before, Forever's")
        print("    SavedVariables bug is active: vendor locations still work, but prices you've seen")
        print("    are forgotten at logout. Community fixes: Forever Data Protect, ForeverSVFix.")
    end
    local x = ns.Vendors.PlayerPosition()
    print("  Your position: " .. (x and "|cff55ff55readable|r" or "|cffffcc00not readable here|r (distances disabled)"))
end

SLASH_REAGENTSCOUT1 = "/rscout"
SLASH_REAGENTSCOUT2 = "/reagentscout"
SlashCmdList.REAGENTSCOUT = function(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "settings" or cmd == "options" or cmd == "config" then
        if ns.Options then ns.Options.Open() else ns.Print("settings didn't load. Quit WoW completely and start it again.") end
    elseif cmd == "debug" then
        ns.Professions.Debug()
    elseif cmd == "status" then
        ns.PrintStatus()
    elseif cmd == "item" and rest ~= "" then
        local itemID = ns.ItemIDFromLink(rest) or tonumber(rest)
        if not itemID then ns.Print("usage: /rscout item <item link or item ID>") return end
        ns.Panel.ShowItems({ { itemID = itemID, need = 1 } }, ns.GetItemName(itemID), ns.GetItemIcon(itemID))
    elseif cmd == "show" or cmd == "hide" then
        if ns.db then ns.db.inline = (cmd == "show") end
        ns.Print(cmd == "show" and "showing price and place under reagents." or "hiding price and place under reagents.")
    elseif cmd == "reset" then
        if ns.db then wipe(ns.db.prices); wipe(ns.db.vendors) end
        ns.Print("forgot all remembered prices and vendors.")
    else
        ns.Print("commands:")
        print("  /rscout - open the settings page")
        print("  /rscout status - check vendor data, saved data and position")
        print("  /rscout show | hide - show or hide price and place under each reagent")
        print("  /rscout item <link or ID> - full vendor list for one item in a window")
        print("  /rscout debug - show what the addon sees in the profession window")
        print("  /rscout reset - forget remembered prices and vendors")
    end
end
