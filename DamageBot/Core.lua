-- DamageBot: shared namespace, saved settings, events and slash commands.
local ADDON, ns = ...

ns.name = "DamageBot"
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = GetMeta and GetMeta(ADDON, "Version") or "?"

local PREFIX = "|cffff5533DamageBot|r: "
function ns.Print(...)
    print(PREFIX .. string.join(" ", tostringall(...)))
end

-- In combat, Forever hides many values from addons ("secret" values). Secret values can
-- still be handed to the game's own bars, icons and text, but an addon can't compare them.
-- nil is never secret.
function ns.CanRead(value)
    if value == nil then return true end
    if canaccessvalue then
        local ok, readable = pcall(canaccessvalue, value)
        return ok and readable
    end
    return true
end

-- Report each different error once, so a problem doesn't flood the chat.
local reported = {}
function ns.ReportError(where, err)
    local key = where .. tostring(err)
    if reported[key] then return end
    reported[key] = true
    ns.lastError = where .. ": " .. tostring(err)
    ns.Print("|cffff5555error in " .. where .. ":|r", tostring(err))
end

------------------------------------------------------------------------
-- Saved settings
------------------------------------------------------------------------
ns.defaults = {
    clickCast = true,      -- clickable bars that cast your spells
    onlyInCombat = true,   -- hide the bars while you're out of combat
    showOnTarget = true,   -- click-cast mode: also show them while you target an enemy
    includeParty = true,   -- also enemies fighting your party
    dimIdle = true,        -- click-cast mode: dim enemies that aren't fighting you
    locked = false,
    showHealth = true,
    dotTimers = false,     -- countdown numbers on the DoT icons
    width = 90, height = 36, columns = 1, spacing = 2,
    maxDots = 5, dotSize = 14, scale = 1,
    point = { "CENTER", "CENTER", -350, 100 },
    nameplateDots = true,  -- show Blizzard's nameplate debuff icons on the bars
    showAllMine = false,   -- mirrors the game setting nameplateShowAllPersonalAuras
    mouseoverCast = false, -- mirrors the game setting enableMouseoverCast
}

local function InitDB()
    if type(DamageBotDB) ~= "table" then DamageBotDB = {} end
    local db = DamageBotDB
    for k, v in pairs(ns.defaults) do
        if db[k] == nil then
            if type(v) == "table" then
                local copy = {}
                for k2, v2 in pairs(v) do copy[k2] = v2 end
                db[k] = copy
            else
                db[k] = v
            end
        end
    end
    ns.db = db
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local events = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
    pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, event, ...)
        if not ok then ns.ReportError(event, err) end
    end
end)

ns.On("ADDON_LOADED", function(_, name)
    if name == ADDON then InitDB() end
end)

-- Click bindings are per character (each class has its own spells). They start empty:
-- Forever blocks clicks that act on an enemy's nameplate, so a default would only cause
-- "Interface action failed" messages.
ns.On("PLAYER_LOGIN", function()
    local db = ns.db
    local key = tostring(UnitName("player")) .. "-" .. tostring(GetRealmName and GetRealmName() or "")
    db.chars = db.chars or {}
    db.chars[key] = db.chars[key] or {}
    local char = db.chars[key]
    char.bindings = char.bindings or {}
    db.bindings = char.bindings
end)

ns.On("PLAYER_LOGOUT", function()
    if ns.db then ns.db.bindings = nil end -- the real copy lives in db.chars
end)

-- Clickable bars can only be changed out of combat. Changes made during combat wait here.
local pending = {}
function ns.OutOfCombat(key, fn)
    if InCombatLockdown() then
        pending[key] = fn
        return false
    end
    fn()
    return true
end

ns.On("PLAYER_REGEN_ENABLED", function()
    local list = pending
    pending = {}
    for key, fn in pairs(list) do
        local ok, err = pcall(fn)
        if not ok then ns.ReportError(key, err) end
    end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_DAMAGEBOT1 = "/dbot"
SLASH_DAMAGEBOT2 = "/damagebot"
SlashCmdList.DAMAGEBOT = function(input)
    local cmd = (input or ""):match("^%s*(%S*)"):lower()
    if cmd == "" or cmd == "settings" or cmd == "options" or cmd == "config" then
        ns.Options.Open()
    elseif cmd == "clicks" or cmd == "bind" or cmd == "bindings" then
        ns.Options.Open(true)
    elseif cmd == "lock" or cmd == "unlock" then
        ns.db.locked = (cmd == "lock")
        ns.Frames.Apply()
        ns.Print(ns.db.locked and "bars locked." or "bars unlocked. Drag the DamageBot tab to move them.")
    elseif cmd == "clickreport" then
        ns.db.clickReport = not ns.db.clickReport
        ns.Print(ns.db.clickReport and "reporting every click, including ones that worked." or "only reporting clicks that didn't work.")
    elseif cmd == "test" then
        ns.Frames.ToggleTest()
    elseif cmd == "debug" then
        ns.Frames.Debug()
    else
        ns.Print("commands:")
        print("  /dbot - open settings")
        print("  /dbot clicks - choose the spell for each click")
        print("  /dbot unlock | lock - move the bars")
        print("  /dbot test - show sample bars so you can place them")
        print("  /dbot debug - show what DamageBot sees right now")
    end
end
