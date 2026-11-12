-- Death Reason: when you die, shows the last hits you took (up to 10 by default), with the
-- attacker, the spell, the damage and your health after each hit.
--
-- Where the hits come from:
--   1. The game's own death recap (C_DeathRecap). It has the attacker and spell of each hit.
--   2. Hits DeathReason recorded itself (UNIT_COMBAT on you). The game doesn't say who or what
--      hit you there, so these only fill in older hits the recap doesn't have, marked "unknown".
-- WoW Forever blocks the combat log for addons, so these are the only sources available.
local ADDON, ns = ...

local PREFIX = "|cffcc3333Death Reason|r: "
function ns.Print(...) print(PREFIX .. string.join(" ", tostringall(...))) end

ns.defaults = {
    maxHits = 10,       -- hits shown per death
    autoOpen = true,    -- open the window when you die
    autoClose = true,   -- close it when you release your spirit (or are resurrected)
    scale = 100,        -- window size, percent
    chatLine = true,    -- one line in chat saying what killed you
    fillUnknown = true, -- add hits the recap doesn't have (no attacker known)
    keepDeaths = 10,    -- deaths remembered
}

-- In combat Forever can hide values from addons ("secret" values). They can still be shown in
-- the game's own text, but an addon can't do math with them. nil is never secret.
function ns.CanRead(v)
    if v == nil then return true end
    if canaccessvalue then
        local ok, readable = pcall(canaccessvalue, v)
        return ok and readable
    end
    return true
end
local CanRead = ns.CanRead
local function Num(v) return CanRead(v) and type(v) == "number" and v or nil end
local function Str(v) return CanRead(v) and type(v) == "string" and v ~= "" and v or nil end

------------------------------------------------------------------------
-- Recording your own hits (no attacker, but nothing is lost when the recap is short)
------------------------------------------------------------------------
local RECORD = 40          -- hits kept
local RECORD_SECONDS = 60  -- only hits this recent count
local recent = {}

local function OnUnitCombat(unit, action, descriptor, amount, school)
    if not CanRead(action) or action ~= "WOUND" then return end
    local hp = UnitHealth and UnitHealth("player")
    recent[#recent + 1] = {
        t = GetTime(),
        amount = amount,
        school = school,
        critical = CanRead(descriptor) and descriptor == "CRITICAL" or nil,
        currentHP = hp,
    }
    if #recent > RECORD then table.remove(recent, 1) end
end

------------------------------------------------------------------------
-- Building a death
------------------------------------------------------------------------
local SWING_ICON = "Interface\\Icons\\INV_Sword_04"
local ENV_ICONS = {
    DROWNING = "spell_shadow_demonbreath", FALLING = "ability_rogue_quickrecovery",
    FIRE = "spell_fire_fire", LAVA = "spell_fire_fire", SLIME = "inv_misc_slime_01",
    FATIGUE = "ability_creature_cursed_05",
}
local ENV_NAMES = { DROWNING = "Drowning", FALLING = "Falling", FIRE = "Fire", LAVA = "Lava",
    SLIME = "Slime", FATIGUE = "Fatigue" }

local function SpellIcon(id)
    if not Num(id) then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok and tex then return tex end
    end
    if GetSpellTexture then return GetSpellTexture(id) end
end

-- One hit from the game's recap, in DeathReason's own form.
local function FromRecap(e, maxHealth, deathTs)
    local event = Str(e.event) or ""
    local hit = {
        amount = e.amount, overkill = e.overkill, absorbed = e.absorbed, resisted = e.resisted,
        blocked = e.blocked, critical = e.critical, school = e.school, currentHP = e.currentHP,
        maxHealth = maxHealth, source = e.sourceName, spell = e.spellName,
    }
    if CanRead(e.hideCaster) and e.hideCaster then hit.source = nil end
    local ts = Num(e.timestamp)
    if ts and deathTs then hit.before = deathTs - ts end
    if event == "SWING_DAMAGE" then
        hit.spell, hit.icon = "Melee", SWING_ICON
    elseif event == "ENVIRONMENTAL_DAMAGE" then
        local kind = Str(e.environmentalType) and e.environmentalType:upper() or ""
        hit.spell = ENV_NAMES[kind] or "Environment"
        hit.icon = "Interface\\Icons\\" .. (ENV_ICONS[kind] or "ability_creature_cursed_05")
        hit.source = hit.spell
    else
        hit.icon = SpellIcon(e.spellId)
    end
    if not hit.icon and event == "RANGE_DAMAGE" then hit.icon = "Interface\\Icons\\INV_Weapon_Bow_07" end
    return hit
end

-- The game's recap of your latest death: list of hits (killing blow first), or nil.
local function ReadRecap()
    local dr = C_DeathRecap
    if not (dr and dr.GetRecapEvents) then return nil, "this client has no death recap" end
    local ok, has = pcall(dr.HasRecapEvents)
    if ok and CanRead(has) and not has then return nil, "the game kept no recap of this death" end
    local okE, events = pcall(dr.GetRecapEvents)
    if not okE then return nil, "the game refused the recap: " .. tostring(events) end
    if type(events) ~= "table" or not CanRead(events) then return nil, "the game hid the recap" end
    local okM, maxHealth = pcall(dr.GetRecapMaxHealth)
    maxHealth = okM and maxHealth or nil
    local deathTs
    for _, e in ipairs(events) do
        local ts = Num(e.timestamp)
        if ts and (not deathTs or ts > deathTs) then deathTs = ts end
    end
    local hits = {}
    for _, e in ipairs(events) do hits[#hits + 1] = FromRecap(e, maxHealth, deathTs) end
    if #hits == 0 then return nil, "the recap was empty" end
    local okL, link = pcall(dr.GetRecapLink)
    return hits, nil, okL and Str(link) or nil
end

-- Values that can be saved: secret values can't be kept after this session.
local KEYS = { "amount", "overkill", "absorbed", "resisted", "blocked", "critical", "school",
    "currentHP", "maxHealth", "source", "spell", "icon", "before", "unknown" }
local function Saveable(hit)
    local out = {}
    for _, k in ipairs(KEYS) do
        local v = hit[k]
        if CanRead(v) then out[k] = v end
    end
    return out
end

-- Turns the recap (if any) plus our own record into the list shown: newest hit first.
function ns.BuildDeath(recapHits, why, deathTime, maxHealth)
    local db = ns.db
    local hits = {}
    for _, h in ipairs(recapHits or {}) do
        if #hits >= db.maxHits then break end
        hits[#hits + 1] = h
    end
    -- Fill in older hits from our own record (no attacker known).
    if db.fillUnknown and #hits < db.maxHits then
        local oldest, haveTimes = 0, false
        for _, h in ipairs(hits) do
            if Num(h.before) then
                haveTimes = true
                if h.before > oldest then oldest = h.before end
            end
        end
        -- Our record also has the recap's hits: skip those (by time, or by count if the
        -- recap's times are hidden).
        local skip = recapHits and #recapHits or 0
        for i = #recent, 1, -1 do
            local r = recent[i]
            local before = deathTime - r.t
            if before > RECORD_SECONDS then break end
            local covered
            if haveTimes then
                covered = before <= oldest + 0.25
            else
                covered = skip > 0
                if covered then skip = skip - 1 end
            end
            if not covered and #hits < db.maxHits then
                hits[#hits + 1] = {
                    amount = r.amount, school = r.school, critical = r.critical, currentHP = r.currentHP,
                    maxHealth = maxHealth, before = before, unknown = true,
                }
            end
        end
    end
    -- Newest first (the killing blow at the top), when the times are known.
    local sortable = true
    for _, h in ipairs(hits) do if not Num(h.before) then sortable = false end end
    if sortable then table.sort(hits, function(x, y) return x.before < y.before end) end
    local death = { when = time and time() or 0, zone = GetRealZoneText and GetRealZoneText() or nil, hits = {}, note = why }
    for i, h in ipairs(hits) do death.hits[i] = h end
    return death
end

local function Remember(death)
    local db = ns.db
    local saved = { when = death.when, zone = death.zone, note = death.note, hits = {} }
    for i, h in ipairs(death.hits) do saved.hits[i] = Saveable(h) end
    table.insert(db.deaths, 1, saved)
    while #db.deaths > db.keepDeaths do table.remove(db.deaths) end
    ns.live = death -- this session's copy, which may still hold secret values for display
end

------------------------------------------------------------------------
-- Text helpers
------------------------------------------------------------------------
local SCHOOLS = { [1] = "Physical", [2] = "Holy", [4] = "Fire", [8] = "Nature", [16] = "Frost", [32] = "Shadow", [64] = "Arcane" }
local SCHOOL_COLORS = { [1] = "ffff00", [2] = "ffe680", [4] = "ff8000", [8] = "4dff4d", [16] = "80ffff", [32] = "8080ff", [64] = "ff80ff" }
function ns.SchoolColor(school)
    local s = Num(school)
    return s and SCHOOL_COLORS[s] or "ffffff"
end
function ns.SchoolName(school)
    local s = Num(school)
    return s and SCHOOLS[s] or nil
end

function ns.Short(n)
    n = Num(n)
    if not n then return nil end
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(math.floor(n + 0.5)) end
    return tostring(math.floor(n + 0.5))
end

-- "152 (30 overkill, critical)": the readable parts of a hit's damage.
function ns.Extra(hit)
    local parts = {}
    local function Add(v, label) if Num(v) and v > 0 then parts[#parts + 1] = ns.Short(v) .. " " .. label end end
    Add(hit.overkill, "overkill")
    Add(hit.absorbed, "absorbed")
    Add(hit.resisted, "resisted")
    Add(hit.blocked, "blocked")
    if CanRead(hit.critical) and hit.critical then parts[#parts + 1] = "critical" end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

function ns.HealthPercent(hit)
    local hp, max = Num(hit.currentHP), Num(hit.maxHealth) or Num(UnitHealthMax and UnitHealthMax("player"))
    if hp and max and max > 0 then return math.max(0, math.min(100, math.floor(hp / max * 100 + 0.5))) end
end

local function ChatLine(death)
    local kill = death.hits[1]
    if not kill then
        ns.Print("you died, but no hits were recorded." .. (death.note and (" (" .. death.note .. ")") or ""))
        return
    end
    local who = Str(kill.source) or (kill.unknown and "something" or "an unknown attacker")
    local what = Str(kill.spell)
    local amount = ns.Short(kill.amount)
    local extra = ns.Extra(kill)
    local text = "killed by |cffffd100" .. who .. "|r" .. (what and ("'s " .. what) or "")
    if amount then text = text .. " for " .. amount .. (extra and (" (" .. extra .. ")") or "") end
    ns.Print(text .. ". |cff71d5ff/dreason|r for the last " .. #death.hits .. " hits.")
end

------------------------------------------------------------------------
-- Death
------------------------------------------------------------------------
local lastLink
local function OnDeath()
    local deathTime = GetTime()
    local maxHealth = UnitHealthMax and UnitHealthMax("player")
    -- The recap can arrive a moment after you die; wait for a new one, up to 3 seconds.
    local tries = 0
    local function Try()
        tries = tries + 1
        local hits, why, link = ReadRecap()
        if hits and link and link == lastLink and tries < 10 then
            C_Timer.After(0.3, Try) -- still the previous death's recap
            return
        end
        if not hits and tries < 10 then
            C_Timer.After(0.3, Try)
            return
        end
        if hits and link == lastLink then hits, why = nil, "the game hasn't sent a recap for this death" end
        lastLink = link or lastLink
        local death = ns.BuildDeath(hits, why, deathTime, maxHealth)
        Remember(death)
        if ns.db.chatLine then ChatLine(death) end
        -- Don't pop up if you already released while the recap was loading.
        local released = ns.db.autoClose and UnitIsGhost and UnitIsGhost("player")
        if ns.db.autoOpen and ns.Window and not released then ns.Window.Show(1) end
    end
    C_Timer.After(0.3, Try)
end

-- A made-up death, to see the window without dying.
function ns.SampleDeath()
    local max = 1200
    local function H(before, source, spell, icon, amount, hp, extra)
        local h = { before = before, source = source, spell = spell, icon = icon, amount = amount, currentHP = hp, maxHealth = max, school = 1 }
        for k, v in pairs(extra or {}) do h[k] = v end
        return h
    end
    return { when = time and time() or 0, zone = "Sample", sample = true, hits = {
        H(0, "Defias Pillager", "Fireball", "Interface\\Icons\\Spell_Fire_FlameBolt", 312, 0, { overkill = 88, school = 4, critical = true }),
        H(1.4, "Defias Thug", "Melee", SWING_ICON, 96, 224),
        H(2.1, "Defias Pillager", "Fireball", "Interface\\Icons\\Spell_Fire_FlameBolt", 201, 320, { school = 4 }),
        H(3.0, "Defias Thug", "Melee", SWING_ICON, 88, 521),
        H(3.9, "Defias Thug", "Melee", SWING_ICON, 91, 609, { blocked = 30 }),
        H(5.2, "Defias Pillager", "Fire Shield", "Interface\\Icons\\Spell_Fire_FireArmor", 25, 700, { school = 4 }),
        H(6.0, "Defias Thug", "Melee", SWING_ICON, 140, 725, { critical = true }),
        H(7.5, nil, nil, nil, 64, 865, { unknown = true }),
        H(9.0, nil, nil, nil, 71, 929, { unknown = true }),
        H(10.6, nil, nil, nil, 200, 1000, { unknown = true }),
    } }
end

------------------------------------------------------------------------
-- Events, settings, commands
------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ALIVE")   -- released your spirit, or accepted a resurrection
events:RegisterEvent("PLAYER_UNGHOST") -- back to life from a ghost
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        if type(DeathReasonDB) ~= "table" then DeathReasonDB = {} end
        for k, v in pairs(ns.defaults) do
            if DeathReasonDB[k] == nil then DeathReasonDB[k] = v end
        end
        DeathReasonDB.deaths = type(DeathReasonDB.deaths) == "table" and DeathReasonDB.deaths or {}
        ns.db = DeathReasonDB
        local ok, err = pcall(ns.RegisterSettings)
        if not ok then ns.Print("couldn't add the settings page:", tostring(err)) end
    elseif event == "PLAYER_LOGIN" then
        -- Remember which recap already exists, so an old one isn't shown for a new death.
        local dr = C_DeathRecap
        if dr and dr.GetRecapLink then
            local ok, link = pcall(dr.GetRecapLink)
            lastLink = ok and Str(link) or nil
        end
    elseif event == "PLAYER_DEAD" then
        local ok, err = pcall(OnDeath)
        if not ok then ns.Print("|cffff5555error:|r", tostring(err)) end
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        if ns.db and ns.db.autoClose and ns.Window then ns.Window.Hide() end
    elseif event == "UNIT_COMBAT" then
        pcall(OnUnitCombat, ...)
    end
end)
if events.RegisterUnitEvent then
    pcall(events.RegisterUnitEvent, events, "UNIT_COMBAT", "player")
else
    pcall(events.RegisterEvent, events, "UNIT_COMBAT")
end
ns.events = events

local OPTIONS = {
    { "autoOpen", "boolean", "Open when I die", "Opens the Death Reason window when you die." },
    { "autoClose", "boolean", "Close when I release my spirit", "Closes the window when you release your spirit or are resurrected." },
    { "scale", "number", "Window size", "Size of the Death Reason window, in percent.", 50, 150, 5 },
    { "chatLine", "boolean", "Say in chat what killed me", "One chat line with the killing blow, its attacker and damage." },
    { "fillUnknown", "boolean", "Add hits with unknown attacker",
        "The game's recap may hold fewer hits than you want. DeathReason also records every hit you take, but the game doesn't say who or what hit you there; those are added as \"unknown\"." },
    { "maxHits", "number", "Hits shown", "How many hits to show for each death.", 3, 20, 1 },
    { "keepDeaths", "number", "Deaths remembered", "Older deaths can be browsed with the arrows in the window.", 1, 30, 1 },
}

local category
function ns.RegisterSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
    category = Settings.RegisterVerticalLayoutCategory("Death Reason")
    for _, o in ipairs(OPTIONS) do
        local key, kind, label, tip, min, max, step = unpack(o)
        local setting = Settings.RegisterAddOnSetting(category, "DeathReason_" .. key, key, ns.db, kind, label, ns.defaults[key])
        if kind == "boolean" then
            Settings.CreateCheckbox(category, setting, tip)
        else
            local options = Settings.CreateSliderOptions(min, max, step)
            if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            Settings.CreateSlider(category, setting, options, tip)
        end
        if key == "scale" and setting.SetValueChangedCallback then
            pcall(setting.SetValueChangedCallback, setting, function() if ns.Window then ns.Window.ApplyScale() end end)
        end
    end
    Settings.RegisterAddOnCategory(category)
end

local function OpenSettings()
    if category and Settings and Settings.OpenToCategory and pcall(Settings.OpenToCategory, category:GetID()) then return end
    ns.Print("settings: Esc > Options > AddOns > Death Reason.")
end

SLASH_DEATHREASON1 = "/dreason"
SLASH_DEATHREASON2 = "/deathreason"
SlashCmdList.DEATHREASON = function(input)
    local cmd = (input or ""):match("^%s*(%S*)"):lower()
    if cmd == "" or cmd == "show" then
        if #ns.db.deaths == 0 then
            ns.Print("no deaths recorded yet. |cff71d5ff/dreason test|r shows a sample.")
        else
            ns.Window.Show(1)
        end
    elseif cmd == "test" then
        ns.Window.ShowDeath(ns.SampleDeath())
    elseif cmd == "settings" or cmd == "options" then
        OpenSettings()
    elseif cmd == "clear" then
        wipe(ns.db.deaths)
        ns.live = nil
        ns.Print("death history cleared.")
    elseif cmd == "debug" then
        local hits, why = ReadRecap()
        ns.Print(("version %s. Recap API: %s. Latest recap: %s. Hits recorded this session: %d."):format(
            tostring(C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"),
            (C_DeathRecap and C_DeathRecap.GetRecapEvents) and "yes" or "no",
            hits and (#hits .. " hits") or tostring(why), #recent))
        local last = recent[#recent]
        if last then
            print(("  last hit you took: amount %s (%s), %.1fs ago"):format(tostring(Num(last.amount) or "hidden"),
                CanRead(last.amount) and "readable" or "hidden by the game", GetTime() - last.t))
        end
    else
        ns.Print("commands:")
        print("  /dreason - show your last death")
        print("  /dreason test - show a sample death")
        print("  /dreason settings - settings")
        print("  /dreason clear - forget recorded deaths")
        print("  /dreason debug - what the game gives DeathReason")
    end
end
