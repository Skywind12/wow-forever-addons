-- Settings in the game's Options window: Esc > Options > AddOns > DamageBot.
-- Page 1: general settings. Page 2 ("Click casting"): a spell for each mouse button and modifier.
local ADDON, ns = ...

local O = {}
ns.Options = O

-- key, kind, label, tooltip [, min, max, step]
local GENERAL = {
    { "clickCast", "boolean", "Click-casting",
        "Bars cast your spells when clicked (set them on the Click casting page). Because of the game's combat rules, every attackable enemy near you then gets a bar, and enemies that aren't fighting you are dimmed. Turn this off to list only enemies fighting you." },
    { "onlyInCombat", "boolean", "Only show in combat", "Hide the bars while you're out of combat." },
    { "showOnTarget", "boolean", "Also show when I target an enemy",
        "With click-casting on, the bars also appear out of combat while you target an attackable enemy, so you can start the fight with a click." },
    { "includeParty", "boolean", "Include enemies fighting my party", "Also list enemies that are fighting your party members." },
    { "dimIdle", "boolean", "Dim enemies not fighting me", "In click-casting mode, enemies that aren't fighting you are shown faded." },
    { "locked", "boolean", "Lock bars", "Hides the DamageBot tab used to move the bars." },
    { "showHealth", "boolean", "Show health numbers", "Shows the enemy's health under its name." },
    { "dotTimers", "boolean", "Show DoT countdown numbers", "Shows seconds left on each DoT icon (the swipe is always shown)." },
    { "nameplateDots", "boolean", "Use nameplate debuff icons",
        "In combat the game won't let addons read debuffs, so DamageBot moves the debuff icons from each enemy's nameplate onto its bar (and gives them back when the bar goes away). Turn off to keep them on the nameplates." },
    { "showAllMine", "boolean", "Show all my debuffs on nameplates",
        "Game setting (nameplateShowAllPersonalAuras). Nameplates normally show only some of your debuffs; turn this on if a DoT you cast doesn't appear." },
    { "mouseoverCast", "boolean", "Mouseover cast (cast on the bar under the mouse)",
        "Game setting (Options > Combat > Mouseover Cast). Your normal action bar keys cast on whatever is under the mouse: hover an enemy's bar and press your spell key. No macros needed." },
    { "width", "number", "Bar width", "Width of each bar.", 60, 200, 2 },
    { "height", "number", "Bar height", "Height of each bar.", 20, 60, 1 },
    { "columns", "number", "Columns", "How many bars side by side.", 1, 6, 1 },
    { "maxDots", "number", "DoT icons per bar", "How many of your DoTs to show on each bar.", 1, 8, 1 },
    { "dotSize", "number", "DoT icon size", "Size of the DoT icons.", 10, 26, 1 },
    { "scale", "number", "Scale", "Size of the whole list.", 0.5, 2, 0.05 },
}

local category

------------------------------------------------------------------------
-- Click casting page
------------------------------------------------------------------------
local MOUSE_LABELS = { Left = "Left click", Right = "Right click", Middle = "Middle click",
    Button4 = "Button 4", Button5 = "Button 5" }
local MOD_LABELS = { [""] = "Click", ["shift-"] = "Shift", ["ctrl-"] = "Ctrl", ["alt-"] = "Alt" }

-- Your attack spells from the spellbook (active, not passive, harmful).
local spellCache
local function AttackSpells()
    if spellCache then return spellCache end
    local list, seen = {}, {}
    local book = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if book and book.GetNumSpellBookSkillLines and bank then
        for line = 1, book.GetNumSpellBookSkillLines() do
            local info = book.GetSpellBookSkillLineInfo(line)
            if info and not info.shouldHide and not info.offSpecID then
                for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = book.GetSpellBookItemInfo(slot, bank)
                    local isSpell = item and item.itemType == Enum.SpellBookItemType.Spell
                    if isSpell and not item.isPassive and item.spellID and item.name and not seen[item.name] then
                        local harmful = C_Spell and C_Spell.IsSpellHarmful and C_Spell.IsSpellHarmful(item.spellID)
                        if harmful then
                            seen[item.name] = true
                            list[#list + 1] = { name = item.name, icon = item.iconID }
                        end
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    if #list > 0 then spellCache = list end
    return list
end
ns.On("SPELLS_CHANGED", function() spellCache = nil end)

local function NewBindingDropdown(parent, key)
    local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd:SetWidth(150)
    local function IsSelected(value) return ns.db.bindings[key] == value end
    local function Select(value) ns.Frames.SetBinding(key, value) end
    dd:SetupMenu(function(_, root)
        root:CreateRadio("None", function() return ns.db.bindings[key] == nil end, function() Select(nil) end)
        root:CreateRadio("Target", IsSelected, Select, "target")
        root:CreateRadio("Set focus", IsSelected, Select, "focus")
        local spells = AttackSpells()
        if #spells > 0 then
            root:CreateDivider()
            root:CreateTitle("Your attack spells")
            local current, listed = ns.db.bindings[key], false
            for _, s in ipairs(spells) do
                root:CreateRadio("|T" .. s.icon .. ":14|t " .. s.name, IsSelected, Select, "spell:" .. s.name)
                if current == "spell:" .. s.name then listed = true end
            end
            if type(current) == "string" and current:find("^spell:") and not listed then
                root:CreateRadio(current:sub(7) .. " |cff999999(not known)|r", IsSelected, Select, current)
            end
        else
            root:CreateTitle("No attack spells found yet")
        end
        if root.SetScrollMode then root:SetScrollMode(400) end
    end)
    return dd
end

local function BuildClickPage()
    local page = CreateFrame("Frame")
    page:Hide()

    local title = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", 10, -15)
    title:SetText("Click casting")

    local help = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    help:SetWidth(600)
    help:SetJustifyH("LEFT")
    help:SetText("Pick what each click does on an enemy's bar. Changes made during combat apply when combat ends. "
        .. "Each character has its own clicks.\n|cffff7755Forever may block clicks that cast a spell on an enemy "
        .. "through its nameplate (you'll see \"Interface action failed\"). What works: turn on \"Mouseover cast\" "
        .. "on the DamageBot page, then hover a bar and press your normal spell key.|r")

    local x0, y0, colW, rowH = 110, -125, 158, 34
    for c, mod in ipairs(ns.Frames.MODIFIERS) do
        local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", x0 + (c - 1) * colW + 4, y0 + 20)
        h:SetText(MOD_LABELS[mod])
    end
    for r, mouse in ipairs(ns.Frames.MOUSE_BUTTONS) do
        local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", 10, y0 - (r - 1) * rowH - 6)
        label:SetText(MOUSE_LABELS[mouse])
        for c, mod in ipairs(ns.Frames.MODIFIERS) do
            local dd = NewBindingDropdown(page, mod .. mouse)
            dd:SetPoint("TOPLEFT", x0 + (c - 1) * colW, y0 - (r - 1) * rowH)
        end
    end

    local note = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 10, y0 - #ns.Frames.MOUSE_BUTTONS * rowH - 10)
    note:SetWidth(600)
    note:SetJustifyH("LEFT")
    note:SetText("Click-casting must be turned on on the DamageBot page. Enemies are found through their "
        .. "nameplates, so keep enemy nameplates on (default key: V).")
    return page
end

------------------------------------------------------------------------
-- Registration
------------------------------------------------------------------------
local function Register()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
        return false, "this client has no addon settings API"
    end
    category = Settings.RegisterVerticalLayoutCategory(ns.name)
    for _, o in ipairs(GENERAL) do
        local key, kind, label, tip, min, max, step = unpack(o)
        local setting = Settings.RegisterAddOnSetting(category, "DamageBot_" .. key, key, ns.db, kind, label, ns.defaults[key])
        if kind == "boolean" then
            Settings.CreateCheckbox(category, setting, tip)
        else
            local options = Settings.CreateSliderOptions(min, max, step)
            if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            Settings.CreateSlider(category, setting, options, tip)
        end
    end
    if Settings.RegisterCanvasLayoutSubcategory then
        local ok, err = pcall(function()
            O.clickCategory = Settings.RegisterCanvasLayoutSubcategory(category, BuildClickPage(), "Click casting")
        end)
        if not ok then ns.ReportError("click casting page", err) end
    end
    Settings.RegisterAddOnCategory(category)
    return true
end

function O.Open(clicks)
    local target = (clicks and O.clickCategory) or category
    if target and Settings and Settings.OpenToCategory then
        if pcall(Settings.OpenToCategory, target:GetID()) then return end
    end
    ns.Print("the settings page isn't available. Type /dbot help for commands.")
end

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON or not ns.db then return end
    if GetCVarBool then
        for key, cvar in pairs(O.CVARS) do ns.db[key] = GetCVarBool(cvar.name) and true or false end
    end
    -- Mouseover cast is what makes hovering a bar work, so turn it on once for everyone.
    if not ns.db.mouseoverOffered and SetCVar and GetCVar and GetCVar("enableMouseoverCast") ~= nil then
        ns.db.mouseoverOffered = true
        if not ns.db.mouseoverCast then
            SetCVar("enableMouseoverCast", "1")
            ns.db.mouseoverCast = true
            ns.Print("turned on the game's Mouseover Cast: hover an enemy's bar and press your normal spell key. "
                .. "Turn it off in /dbot or Options > Combat.")
        end
    end
    local ok, registered, why = pcall(Register)
    if not (ok and registered) then
        category = nil
        ns.Print("|cffffcc00couldn't add the settings page:|r", tostring(ok and why or registered))
    end
end)

-- DamageBot settings that are really game settings (CVars): shown on the DamageBot page,
-- read from the game at load, written back when you change them.
O.CVARS = {
    showAllMine = { name = "nameplateShowAllPersonalAuras",
        on = "nameplates now show all your debuffs (game setting nameplateShowAllPersonalAuras on).",
        off = "nameplates back to showing only some of your debuffs (nameplateShowAllPersonalAuras off)." },
    mouseoverCast = { name = "enableMouseoverCast",
        on = "Mouseover Cast on: hover an enemy's bar and press your normal spell key. If nothing happens, look in Options > Combat: if Mouseover Cast has a key set, hold that key or set it to None.",
        off = "Mouseover Cast off: spells go to your target again." },
}

-- Settings are applied when they change (checked twice a second; cheap).
local last
local lastCVar = {}
local watcher = CreateFrame("Frame")
local wait = 0
watcher:SetScript("OnUpdate", function(_, dt)
    wait = wait + dt
    if wait < 0.5 or not ns.db then return end
    wait = 0
    local parts = {}
    for _, o in ipairs(GENERAL) do parts[#parts + 1] = tostring(ns.db[o[1]]) end
    local sig = table.concat(parts, ",")
    for key, cvar in pairs(O.CVARS) do
        local value = ns.db[key]
        if lastCVar[key] ~= nil and value ~= lastCVar[key] and SetCVar then
            local ok = pcall(SetCVar, cvar.name, value and "1" or "0")
            ns.Print(ok and (value and cvar.on or cvar.off) or ("this game version has no " .. cvar.name .. " setting."))
        end
        lastCVar[key] = value
    end
    if last and sig ~= last then
        local ok, err = pcall(ns.Frames.Apply)
        if not ok then ns.ReportError("settings", err) end
    end
    last = sig
end)
