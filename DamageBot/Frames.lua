-- The list of enemy bars, in two modes:
--
-- Click-casting ON: one clickable bar per enemy nameplate. These are Blizzard "secure" buttons,
--   so during combat only the game's secure code may show, hide or move them. That code can
--   check "exists", "attackable" and "dead", but not "is it in combat". So every attackable
--   enemy near you gets a bar, and the ones that aren't fighting you are dimmed.
-- Click-casting OFF: plain bars. Only enemies fighting you are listed, with no gaps.
local _, ns = ...

local Frames = {}
ns.Frames = Frames

local MAX = 40               -- nameplate1 .. nameplate40
local UPDATE_EVERY = 0.1     -- seconds between bar refreshes
local MOUSE_BUTTONS = { "Left", "Right", "Middle", "Button4", "Button5" }
local MODIFIERS = { "", "shift-", "ctrl-", "alt-" }
Frames.MOUSE_BUTTONS, Frames.MODIFIERS = MOUSE_BUTTONS, MODIFIERS

local anchor           -- plain frame that holds the plain bars and the move tab
local header           -- secure frame that holds the clickable bars
local plain, secure = {}, {}
local testing = false
local built = false

------------------------------------------------------------------------
-- Secure layout: runs inside the game's secure environment, also in combat.
------------------------------------------------------------------------
local LAYOUT = [[
    local kids = newtable(self:GetChildren())
    local w = self:GetAttribute("barW")
    local h = self:GetAttribute("barH")
    local cols = self:GetAttribute("cols")
    local gap = self:GetAttribute("gap")
    local enabled = self:GetAttribute("enabled")
    local n, col, row = 0, 0, 0
    for i = 1, #kids do
        local b = kids[i]
        local unit = b:GetAttribute("unit")
        if unit then
            if enabled and UnitExists(unit) and PlayerCanAttack(unit) and not UnitIsDead(unit) then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", self, "TOPLEFT", col * (w + gap), -row * (h + gap))
                b:Show()
                n = n + 1
                col = col + 1
                if col >= cols then col = 0; row = row + 1 end
            else
                b:Hide()
            end
        end
    end
]]

-- Each clickable bar asks for a new layout when its enemy appears or disappears.
local ON_UNIT_CHANGE = [[
    if name == "state-unitexists" then
        self:GetParent():RunAttribute("layout")
    end
]]

------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------
local function SavePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint(1)
    ns.db.point = { point, relPoint, x, y }
end

local function PlaceAt(frame)
    local p = ns.db.point
    frame:ClearAllPoints()
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function ShowTooltip(self)
    if testing or not self.unit then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetUnit, GameTooltip, self.unit)
    GameTooltip:Show()
end

-- Does the game make the hovered bar your "mouseover" unit? If so, the game's Mouseover Cast
-- setting (or @mouseover macros) casts on the enemy under the mouse. Checked on the first hover, and
-- again after /dbot debug.
local mouseoverChecked = false
function Frames.ResetMouseoverCheck() mouseoverChecked = false end

local function CheckMouseover(self)
    if mouseoverChecked or testing or not self.unit then return end
    C_Timer.After(0.1, function()
        if mouseoverChecked or not self:IsMouseOver() then return end
        mouseoverChecked = true
        local exists = UnitExists("mouseover")
        local ok, same = pcall(UnitIsUnit, "mouseover", self.unit)
        local sameKnown = ok and ns.CanRead(same)
        local castOn = GetCVarBool and GetCVarBool("enableMouseoverCast")
        local how = castOn and "hover a bar and press your normal spell key."
            or "turn on \"Mouseover cast\" in /dbot, then hover a bar and press your normal spell key."
        if exists and (not sameKnown or same) then
            ns.Print("|cff55ff55hovering a bar makes that enemy your mouseover.|r To cast on it: " .. how)
        else
            ns.Print("|cffff7755the game doesn't make DamageBot bars your mouseover|r, so hovering them can't aim spells.")
        end
    end)
end

local function BuildAnchor()
    anchor = CreateFrame("Frame", "DamageBotAnchor", UIParent)
    anchor:SetSize(ns.db.width, 1)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    PlaceAt(anchor)

    -- The move tab, shown while unlocked.
    local tab = CreateFrame("Button", nil, anchor)
    tab:SetSize(90, 16)
    tab:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.bg:SetColorTexture(0.1, 0.1, 0.1, 0.85)
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tab.text:SetPoint("CENTER")
    tab.text:SetText("DamageBot")
    tab:RegisterForDrag("LeftButton")
    tab:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        anchor:StartMoving()
    end)
    tab:SetScript("OnDragStop", function()
        anchor:StopMovingOrSizing()
        SavePosition(anchor)
        ns.OutOfCombat("place", function() PlaceAt(header) end)
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("DamageBot", 1, 1, 1)
        GameTooltip:AddLine("Drag to move. /dbot lock to hide this tab.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Frames.tab = tab

    for i = 1, MAX do
        local f = CreateFrame("Button", nil, anchor)
        f:EnableMouse(false)
        ns.Bars.Build(f)
        f:SetScript("OnEnter", ShowTooltip)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f:Hide()
        plain[i] = f
    end
end

local function BuildHeader()
    header = CreateFrame("Frame", "DamageBotHeader", UIParent, "SecureHandlerStateTemplate")
    header:SetSize(ns.db.width, 1)
    PlaceAt(header)
    header:SetAttribute("layout", LAYOUT)
    -- Re-run the layout when you enter or leave combat.
    header:SetAttribute("_onstate-combat", [[ self:RunAttribute("layout") ]])
    RegisterStateDriver(header, "combat", "[combat] 1; 0")

    for i = 1, MAX do
        local unit = "nameplate" .. i
        -- SecureActionButtonTemplate, not SecureUnitButtonTemplate: on Forever the unit-button
        -- version hands clicks to Blizzard's own Click Casting settings first, which overrides
        -- or silently drops DamageBot's bindings.
        local b = CreateFrame("Button", "DamageBotUnit" .. i, header, "SecureActionButtonTemplate,SecureHandlerAttributeTemplate")
        b.unit = unit
        b:SetAttribute("unit", unit)
        b:EnableMouse(true)
        -- Register both press and release: the game casts on whichever one your
        -- "cast on key down" setting picks. With only one registered, clicks are ignored.
        b:RegisterForClicks("AnyUp", "AnyDown")
        ns.Clicks.Watch(b)
        b:SetAttribute("_onattributechanged", ON_UNIT_CHANGE)
        ns.Bars.Build(b)
        b:HookScript("OnEnter", ShowTooltip)
        b:HookScript("OnEnter", CheckMouseover)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        secure[i] = b
    end
end

------------------------------------------------------------------------
-- Click bindings
------------------------------------------------------------------------
-- db.bindings["shift-Right"] = "target" | "focus" | "spell:Corruption" | nil
local function ApplyBindings()
    for _, b in ipairs(secure) do
        for n, mouse in ipairs(MOUSE_BUTTONS) do
            for _, mod in ipairs(MODIFIERS) do
                local value = ns.db.bindings[mod .. mouse]
                local kind, spell = nil, nil
                if value == "target" or value == "focus" then
                    kind = value
                elseif type(value) == "string" and value:find("^spell:") then
                    kind, spell = "spell", value:sub(7)
                end
                b:SetAttribute(mod .. "type" .. n, kind)
                b:SetAttribute(mod .. "spell" .. n, spell)
            end
        end
    end
end

local MOD_NAMES = { ["shift-"] = "Shift + ", ["ctrl-"] = "Ctrl + ", ["alt-"] = "Alt + " }
local MOUSE_NAMES = { Left = "Left click", Right = "Right click", Middle = "Middle click",
    Button4 = "Button 4", Button5 = "Button 5" }

function Frames.BindingLabel(key)
    local mod, mouse = key:match("^(%a+%-)(.+)$")
    if not mod then mod, mouse = "", key end
    return (MOD_NAMES[mod] or "") .. (MOUSE_NAMES[mouse] or mouse)
end

function Frames.ValueLabel(value)
    if value == "target" then return "Target" end
    if value == "focus" then return "Set focus" end
    if type(value) == "string" and value:find("^spell:") then return value:sub(7) end
    return "nothing"
end

function Frames.SetBinding(key, value)
    ns.db.bindings[key] = value
    local text = Frames.BindingLabel(key) .. ": " .. Frames.ValueLabel(value)
    if ns.OutOfCombat("bindings", ApplyBindings) then
        ns.Print(text)
    else
        ns.Print(text .. " (takes effect when you leave combat)")
    end
end

------------------------------------------------------------------------
-- Applying settings (size, mode, visibility)
------------------------------------------------------------------------
local function ApplySecure()
    local db = ns.db
    header:SetScale(db.scale)
    header:SetSize(db.width * db.columns + db.spacing * (db.columns - 1), 1)
    header:SetAttribute("barW", db.width)
    header:SetAttribute("barH", db.height)
    header:SetAttribute("cols", db.columns)
    header:SetAttribute("gap", db.spacing)
    for _, b in ipairs(secure) do ns.Bars.Resize(b, db) end
    PlaceAt(header)
    ApplyBindings()

    local enabled = db.clickCast and not testing
    header:SetAttribute("enabled", enabled)
    if enabled then
        for _, b in ipairs(secure) do RegisterUnitWatch(b, true) end
        local visibility = "show"
        if db.onlyInCombat then
            -- Also before a fight while you target an enemy, so you can open on it with a click.
            visibility = db.showOnTarget and "[combat] show; [@target,harm,nodead] show; hide" or "[combat] show; hide"
        end
        RegisterStateDriver(header, "visibility", visibility)
        header:Execute([[ self:RunAttribute("layout") ]])
    else
        for _, b in ipairs(secure) do
            UnregisterUnitWatch(b)
            b:Hide()
        end
        RegisterStateDriver(header, "visibility", "hide")
    end
end

function Frames.Apply()
    if not built then return end
    local db = ns.db
    anchor:SetScale(db.scale)
    anchor:SetSize(db.width * db.columns + db.spacing * (db.columns - 1), 1)
    for _, f in ipairs(plain) do ns.Bars.Resize(f, db) end
    Frames.tab:SetShown(not db.locked)
    ns.OutOfCombat("apply", ApplySecure)
end

------------------------------------------------------------------------
-- Updating
------------------------------------------------------------------------
local order = {}   -- unit -> when it started fighting you, so new enemies go to the bottom
local stamp = 0

-- Enemies fighting you (or maybe fighting you), oldest first.
local function Fighting(db)
    local list = {}
    for i = 1, MAX do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitCanAttack("player", unit) and ns.Bars.IsFighting(unit, db) ~= false then
            if not order[unit] then stamp = stamp + 1; order[unit] = stamp end
            list[#list + 1] = unit
        else
            order[unit] = nil
        end
    end
    table.sort(list, function(a, b) return order[a] < order[b] end)
    return list
end

local function UpdatePlain(db)
    local shown = 0
    local playerInCombat = UnitAffectingCombat("player")
    if not (db.onlyInCombat and not playerInCombat) then
        for _, unit in ipairs(Fighting(db)) do
            do
                shown = shown + 1
                if shown > MAX then break end
                local f = plain[shown]
                local col = (shown - 1) % db.columns
                local row = math.floor((shown - 1) / db.columns)
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", anchor, "TOPLEFT", col * (db.width + db.spacing), -row * (db.height + db.spacing))
                f.unit = unit
                f:Show()
                ns.Bars.Update(f, unit, db)
            end
        end
    end
    for i = shown + 1, MAX do
        if plain[i]:IsShown() then plain[i]:Hide() end
    end
end

local function UpdateSecure(db)
    for _, b in ipairs(secure) do
        if b:IsVisible() then ns.Bars.Update(b, b.unit, db) end
    end
end

local function UpdateTest(db)
    for i = 1, MAX do
        local f = plain[i]
        if i <= 3 then
            local col = (i - 1) % db.columns
            local row = math.floor((i - 1) / db.columns)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", anchor, "TOPLEFT", col * (db.width + db.spacing), -row * (db.height + db.spacing))
            f.unit = nil
            f:Show()
            ns.Bars.UpdateSample(f, i, db)
        elseif f:IsShown() then
            f:Hide()
        end
    end
end

local driver = CreateFrame("Frame")
local elapsed = 0
driver:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < UPDATE_EVERY or not built then return end
    elapsed = 0
    local db = ns.db
    local ok, err
    if testing or db.clickCast then wipe(order) end -- the list order only matters in display mode
    ns.Bars.BeginRefresh()
    if testing then
        ok, err = pcall(UpdateTest, db)
    elseif db.clickCast then
        for _, f in ipairs(plain) do if f:IsShown() then f:Hide() end end
        ok, err = pcall(UpdateSecure, db)
    else
        ok, err = pcall(UpdatePlain, db)
    end
    if not ok then ns.ReportError("bar update", err) end
    ok, err = pcall(ns.Bars.EndRefresh)
    if not ok then ns.ReportError("nameplate debuff icons", err) end
end)

------------------------------------------------------------------------
-- Test mode and debug
------------------------------------------------------------------------
function Frames.ToggleTest()
    if InCombatLockdown() then ns.Print("test mode is only available out of combat.") return end
    testing = not testing
    if not testing then
        for _, f in ipairs(plain) do f:Hide() end
    end
    ns.OutOfCombat("apply", ApplySecure)
    ns.Print(testing and "showing sample bars. /dbot test again to stop." or "sample bars hidden.")
end

-- One line saying what the game returns for this unit's debuffs, with two filters.
local function AuraReport(unit)
    local parts = {}
    for _, filter in ipairs({ "HARMFUL|PLAYER", "HARMFUL" }) do
        local list, err = ns.Bars.ReadAuras(unit, filter)
        local label = filter == "HARMFUL" and "all debuffs" or "your debuffs"
        if list then
            local icons = ""
            for i, aura in ipairs(list) do
                if i > 4 then break end
                local ok, icon = pcall(function() return aura.icon end)
                icons = icons .. ((ok and icon ~= nil) and ("|T" .. (ns.CanRead(icon) and tostring(icon) or "134400") .. ":12|t") or "?")
            end
            parts[#parts + 1] = ("%s %d %s"):format(label, #list, icons)
        else
            parts[#parts + 1] = ("%s |cffff5555refused: %s|r"):format(label, err)
        end
    end
    return table.concat(parts, ",  ")
end

function Frames.Debug()
    local db = ns.db
    Frames.ResetMouseoverCheck()
    ns.Print("debug (version " .. tostring(ns.version) .. ")")
    print(("  Mode: %s   Only in combat: %s   In combat: %s"):format(
        db.clickCast and "click-casting" or "display only", tostring(db.onlyInCombat), tostring(InCombatLockdown())))
    local n = 0
    for i = 1, MAX do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            n = n + 1
            local attack = UnitCanAttack("player", unit)
            local fighting = attack and ns.Bars.IsFighting(unit, db)
            local name = UnitName(unit)
            print(("  %s: %s, attackable %s, fighting you %s"):format(unit,
                ns.CanRead(name) and tostring(name) or "(hidden)", tostring(attack),
                fighting == nil and "unknown" or tostring(fighting)))
            if attack then
                local row, why = ns.Bars.PlateRow(unit)
                if row then
                    local okS, rowShown = pcall(row.IsShown, row)
                    local onBar = false
                    for _, b in ipairs(secure) do if b.art.row == row then onBar = true end end
                    for _, f in ipairs(plain) do if f.art.row == row then onBar = true end end
                    print(("    nameplate debuff row: %d icons, row %s, %s"):format(ns.Bars.RowCount(row),
                        (okS and rowShown) and "turned on" or "|cffff5555turned off|r",
                        onBar and "on its DamageBot bar" or "still on the nameplate"))
                else
                    print("    |cffff5555no nameplate debuff row:|r " .. tostring(why))
                end
                print("    direct read: " .. AuraReport(unit))
            end
        end
    end
    if n == 0 then print("  No nameplates. Turn on enemy nameplates (default key: V).") end
    if GetCVar then
        print(("  Nameplate settings: enemy auras %s, show all your debuffs %s"):format(
            tostring(GetCVar("nameplateEnemyNpcAuraDisplay")), tostring(GetCVar("nameplateShowAllPersonalAuras"))))
    end
    if GetCVar then
        print("  Mouseover cast (game setting enableMouseoverCast): " .. tostring(GetCVar("enableMouseoverCast")))
    end
    print("  Last nameplate row error: " .. (ns.rowError or "none"))
    print("  Click bindings:")
    for _, mouse in ipairs(MOUSE_BUTTONS) do
        for _, mod in ipairs(MODIFIERS) do
            local value = db.bindings[mod .. mouse]
            if value then print("    " .. Frames.BindingLabel(mod .. mouse) .. ": " .. Frames.ValueLabel(value)) end
        end
    end
    local b = secure[1]
    print(("  Bar 1 left click: type=%s spell=%s unit=%s"):format(tostring(b:GetAttribute("type1")),
        tostring(b:GetAttribute("spell1")), tostring(b:GetAttribute("unit"))))
    print("  Last error: " .. (ns.lastError or "none"))
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
ns.On("PLAYER_LOGIN", function()
    BuildAnchor()
    BuildHeader()
    built = true
    Frames.Apply()
    if GetCVarBool and not GetCVarBool("nameplateShowEnemies") then
        ns.Print("enemy nameplates are off. DamageBot finds enemies through them, so press V (or turn them on in Options).")
    end
    ns.Print(("version %s loaded. Type /dbot for settings, /dbot test to see the bars."):format(ns.version))
end)

------------------------------------------------------------------------
-- Click reports: when a click on a bar doesn't start a cast, say why in chat.
-- Only reads what happened (the click, the bar's settings, the game's events); it never
-- changes the clickable bars, so it can't interfere with casting.
local Clicks = {}
ns.Clicks = Clicks

local WINDOW = 0.6 -- seconds to wait for the game to react to a click
local pending      -- the click being watched
local pressed      -- mouse-down seen on a bar, waiting for its click

local MOUSE = { LeftButton = "Left", RightButton = "Right", MiddleButton = "Middle", Button4 = "Button4", Button5 = "Button5" }

local function ModPrefix()
    if IsShiftKeyDown() then return "shift-" end
    if IsControlKeyDown() then return "ctrl-" end
    if IsAltKeyDown() then return "alt-" end
    return ""
end

local function Readable(v) return v ~= nil and ns.CanRead(v) end

local function Report()
    local c = pending
    pending = nil
    if not c or c.ok then
        if c and ns.db.clickReport then ns.Print(c.label .. ": " .. c.what .. " - worked.") end
        return
    end
    local why
    if c.blocked then
        why = "Blizzard blocked an addon action (" .. c.blocked .. ")."
    elseif c.error then
        why = "the game said: " .. c.error
    elseif c.tried and c.failed then
        why = "the button tried " .. c.tried .. " and the game rejected it without a message."
    elseif c.tried then
        why = "the button tried " .. c.tried .. " but the game ignored it."
    else
        why = "Blizzard's button didn't try to cast at all."
    end
    ns.Print(("%s: %s on %s - didn't happen, %s"):format(c.label, c.what, c.unitText, why))
    if c.kind == "spell" then
        ns.Print(("To test the game itself, target nothing and type:  /cast [@%s] %s"):format(c.unit, c.spell))
    end
end

-- Runs just before Blizzard's button handles the click, so nothing it does is missed.
local function OnPreClick(self, button, down)
    pressed = nil
    if not down then return end -- each click arrives as press + release; watch from the press
    local key = ModPrefix() .. (MOUSE[button] or button)
    local label = ns.Frames.BindingLabel(key)
    local kind = SecureButton_GetModifiedAttribute and SecureButton_GetModifiedAttribute(self, "type", button)
    if not kind then
        ns.Print(label .. " isn't set to anything. Choose a spell for it with /dbot clicks.")
        return
    end
    local spell = SecureButton_GetModifiedAttribute(self, "spell", button)
    local name = UnitName(self.unit)
    pending = {
        label = label,
        kind = kind,
        unit = self.unit,
        spell = spell,
        what = (kind == "spell" and tostring(spell)) or (kind == "target" and "Target") or (kind == "focus" and "Set focus") or kind,
        unitText = Readable(name) and name or self.unit,
    }
    C_Timer.After(WINDOW, Report)
end

local function OnMouseDown(self, button)
    local t = GetTime()
    pressed = t
    C_Timer.After(1.5, function()
        if pressed == t then
            pressed = nil
            ns.Print("the bar got your mouse press, but the game didn't treat it as a click (" .. tostring(button) .. ").")
        end
    end)
end

function Clicks.Watch(b)
    b:HookScript("PreClick", OnPreClick)
    b:HookScript("PostClick", function() pressed = nil end)
    b:HookScript("OnMouseDown", OnMouseDown)
end

-- Did Blizzard's button actually call the cast? These hooks run after the game's own
-- function and only write down that it was called.
local function Tried(fn)
    return function(what, unit)
        if pending and not pending.tried then
            pending.tried = ("%s(%s, %s)"):format(fn, tostring(what), tostring(unit))
        end
    end
end
for _, fn in ipairs({ "CastSpellByName", "CastSpellByID", "TargetUnit", "FocusUnit" }) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, Tried(fn)) end
end

local function Failed(_, unit)
    if pending and Readable(unit) and unit == "player" then pending.failed = true end
end
ns.On("UNIT_SPELLCAST_FAILED", Failed)
ns.On("UNIT_SPELLCAST_FAILED_QUIET", Failed)

-- What the game did after the click.
local function Started(_, unit)
    if pending and Readable(unit) and unit == "player" then pending.ok = true end
end
ns.On("UNIT_SPELLCAST_SENT", Started)
ns.On("UNIT_SPELLCAST_START", Started)
ns.On("UNIT_SPELLCAST_CHANNEL_START", Started)
ns.On("UNIT_SPELLCAST_SUCCEEDED", Started)
ns.On("PLAYER_TARGET_CHANGED", function() if pending and pending.kind == "target" then pending.ok = true end end)
ns.On("PLAYER_FOCUS_CHANGED", function() if pending and pending.kind == "focus" then pending.ok = true end end)

ns.On("UI_ERROR_MESSAGE", function(_, _, message)
    if pending and not pending.ok and Readable(message) then pending.error = message end
end)

local function Blocked(_, addon, fn)
    if pending and not pending.ok then
        pending.blocked = (Readable(addon) and tostring(addon) or "?") .. ": " .. (Readable(fn) and tostring(fn) or "?")
    end
end
ns.On("ADDON_ACTION_BLOCKED", Blocked)
ns.On("ADDON_ACTION_FORBIDDEN", Blocked)
