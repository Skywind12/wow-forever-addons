-- How one enemy bar looks and how it's filled in.
--
-- Everything that changes during combat (health, name, DoT icons, timers) is passed straight
-- to the game's own widgets, which accept Forever's hidden combat values. Visibility of the
-- parts inside a bar is done with alpha, never Show/Hide, so it is also safe on the
-- clickable (protected) bars during combat.
local _, ns = ...

local Bars = {}
ns.Bars = Bars

local WHITE = "Interface\\Buttons\\WHITE8x8"
local HOSTILE = { 0.78, 0.16, 0.12 }
local NEUTRAL = { 0.85, 0.68, 0.12 }
local IDLE = { 0.45, 0.45, 0.45 }

local function Visible(region, shown) region:SetAlpha(shown and 1 or 0) end

------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------
local function NewDot(art)
    local d = CreateFrame("Frame", nil, art)
    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetAllPoints()
    d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    d.border = d:CreateTexture(nil, "BACKGROUND")
    d.border:SetPoint("TOPLEFT", -1, 1)
    d.border:SetPoint("BOTTOMRIGHT", 1, -1)
    d.border:SetColorTexture(0, 0, 0, 1)
    d.cd = CreateFrame("Cooldown", nil, d, "CooldownFrameTemplate")
    d.cd:SetAllPoints()
    d.cd:SetDrawEdge(false)
    d.cd:SetReverse(true)
    d.count = d:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    d.count:SetPoint("BOTTOMRIGHT", 2, -1)
    Visible(d, false)
    return d
end

-- Builds the visuals inside a bar frame (a plain frame or a clickable secure button).
function Bars.Build(f)
    local art = CreateFrame("Frame", nil, f)
    art:SetAllPoints()
    f.art = art

    -- White outline when this enemy is your target; drawn behind the black edge, 1px outside it.
    art.targetEdge = art:CreateTexture(nil, "BACKGROUND", nil, -8)
    art.targetEdge:SetPoint("TOPLEFT", -1, 1)
    art.targetEdge:SetPoint("BOTTOMRIGHT", 1, -1)
    art.targetEdge:SetColorTexture(1, 1, 1, 1)
    art.targetEdge:SetAlpha(0)

    art.edge = art:CreateTexture(nil, "BACKGROUND", nil, -7)
    art.edge:SetAllPoints()
    art.edge:SetColorTexture(0, 0, 0, 0.9)

    art.missing = art:CreateTexture(nil, "BACKGROUND", nil, -6)
    art.missing:SetPoint("TOPLEFT", 1, -1)
    art.missing:SetPoint("BOTTOMRIGHT", -1, 1)
    art.missing:SetColorTexture(0.12, 0.12, 0.12, 1)

    art.health = CreateFrame("StatusBar", nil, art)
    art.health:SetPoint("TOPLEFT", 1, -1)
    art.health:SetPoint("BOTTOMRIGHT", -1, 1)
    art.health:SetStatusBarTexture(WHITE)
    art.health:SetMinMaxValues(0, 1)
    art.health:SetValue(1)

    -- A soft sheen on the top half, like HealBot's default bar texture.
    art.sheen = art.health:CreateTexture(nil, "OVERLAY")
    art.sheen:SetPoint("TOPLEFT")
    art.sheen:SetPoint("RIGHT")
    art.sheen:SetHeight(f:GetHeight() / 2)
    art.sheen:SetTexture(WHITE)
    if art.sheen.SetGradient and CreateColor then
        art.sheen:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.22))
    else
        art.sheen:SetVertexColor(1, 1, 1, 0.1)
    end

    art.text = CreateFrame("Frame", nil, art)
    art.text:SetAllPoints()
    art.text:SetFrameLevel(art.health:GetFrameLevel() + 2)

    art.name = art.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    art.name:SetPoint("TOPLEFT", 3, -4)
    art.name:SetPoint("TOPRIGHT", -3, -4)
    art.name:SetJustifyH("CENTER")
    art.name:SetWordWrap(false)

    art.hp = art.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    art.hp:SetPoint("TOP", art.name, "BOTTOM", 0, -2)
    art.hp:SetJustifyH("CENTER")

    art.hover = art.text:CreateTexture(nil, "HIGHLIGHT")
    art.hover:SetAllPoints(art.health)
    art.hover:SetColorTexture(1, 1, 1, 0.12)

    art.dots = {}
    f.built = true
end

-- Sizes everything to the current settings (only call out of combat for clickable bars).
function Bars.Resize(f, db)
    Bars.EnsureDots(f, db) -- create the icons now, out of combat
    f:SetSize(db.width, db.height)
    f.art.sheen:SetHeight(db.height / 2)
    for i, d in ipairs(f.art.dots) do
        d:SetSize(db.dotSize, db.dotSize)
        d:ClearAllPoints()
        d:SetPoint("BOTTOMRIGHT", f.art, "BOTTOMRIGHT", -2 - (i - 1) * (db.dotSize + 2), 2)
        d.cd:SetHideCountdownNumbers(not db.dotTimers)
    end
end

local function EnsureDots(f, db)
    local dots = f.art.dots
    while #dots < db.maxDots do
        local d = NewDot(f.art)
        d:SetFrameLevel(f.art.text:GetFrameLevel() + 1)
        dots[#dots + 1] = d
        d:SetSize(db.dotSize, db.dotSize)
        d:SetPoint("BOTTOMRIGHT", f.art, "BOTTOMRIGHT", -2 - (#dots - 1) * (db.dotSize + 2), 2)
        d.cd:SetHideCountdownNumbers(not db.dotTimers)
    end
end
Bars.EnsureDots = EnsureDots

------------------------------------------------------------------------
-- Reading a unit
------------------------------------------------------------------------
local function Readable(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok then return nil, false end
    return v, ns.CanRead(v)
end

-- true / false, or nil when the game won't say.
local function OnThreatList(who, unit)
    if not UnitExists(who) then return false end
    local v, readable = Readable(UnitThreatSituation, who, unit)
    if not readable then return nil end
    return v ~= nil
end

-- Is this enemy fighting you (or your pet, or your party)?
-- Returns true, false, or nil when the game hides the answer (treated as "maybe").
function Bars.IsFighting(unit, db)
    local inCombat, readable = Readable(UnitAffectingCombat, unit)
    if readable and not inCombat then return false end
    local unknown = not readable
    local function check(who)
        local r = OnThreatList(who, unit)
        if r == nil then unknown = true end
        return r
    end
    if check("player") or check("pet") then return true end
    if db.includeParty and IsInGroup and IsInGroup() then
        for i = 1, 4 do
            if check("party" .. i) then return true end
        end
    end
    if unknown then return nil end
    return false
end

------------------------------------------------------------------------
-- Filling a bar
------------------------------------------------------------------------
local function SetColor(art, c, dim)
    local m = dim and 0.55 or 1
    art.health:SetStatusBarColor(c[1] * m, c[2] * m, c[3] * m)
end

-- Reads auras on a unit. Returns the list, or nil and the reason the game gave.
function Bars.ReadAuras(unit, filter, max)
    if not (C_UnitAuras and C_UnitAuras.GetUnitAuras) then return nil, "C_UnitAuras.GetUnitAuras doesn't exist" end
    local ok, list = pcall(C_UnitAuras.GetUnitAuras, unit, filter, max)
    if not ok then return nil, tostring(list) end
    if not ns.CanRead(list) then return nil, "the list itself is hidden" end
    if type(list) ~= "table" then return nil, "returned " .. type(list) end
    return list
end

------------------------------------------------------------------------
-- Borrowing Blizzard's nameplate debuff rows
--
-- In combat Forever won't let addons read auras at all. Blizzard's own nameplates can, and
-- each enemy nameplate has a row of "your debuffs on this enemy" icons (with timer swipe and
-- stack count). DamageBot moves that row onto the enemy's bar and gives it back when the bar
-- goes away. It only calls widget methods on Blizzard's frames (parent, position, scale,
-- alpha) and never writes into their tables, which would break Blizzard's nameplates.
------------------------------------------------------------------------
local AURA_HEIGHT = (NamePlateConstants and NamePlateConstants.AURA_ITEM_HEIGHT) or 25
local holder = {}   -- debuff row -> bar art holding it
local home = {}     -- debuff row -> { auras = AurasFrame, unitFrame = UnitFrame, scale = n }
local claimed = {}  -- rows claimed during the current refresh

-- The debuff row on this unit's nameplate, or nil and why not.
function Bars.PlateRow(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil, "no C_NamePlate" end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok then return nil, "GetNamePlateForUnit failed: " .. tostring(plate) end
    if not plate then return nil, "the game gives addons no nameplate frame" end
    if plate.IsForbidden and plate:IsForbidden() then return nil, "the nameplate is off-limits to addons" end
    local unitFrame = plate.UnitFrame
    local auras = unitFrame and unitFrame.AurasFrame
    local row = auras and auras.DebuffListFrame
    if not row then return nil, "the nameplate has no debuff row" end
    return row, nil, auras, unitFrame
end

local function GiveBack(row)
    local h = home[row]
    holder[row] = nil
    if not h then return end
    local ok, err = pcall(function()
        row:SetParent(h.auras)
        row:SetScale(h.scale)
        row:SetAlpha(1)
        row:ClearAllPoints()
        local bars = h.unitFrame.HealthBarsContainer
        if bars then
            local pad = tonumber(GetCVar and GetCVar("nameplateDebuffPadding")) or 0
            row:SetPoint("LEFT", bars, "LEFT")
            row:SetPoint("BOTTOM", bars.healthBar or bars, "TOP", 0, pad)
        end
    end)
    if not ok then ns.rowError = "giving back: " .. tostring(err) end
end

-- Puts the unit's nameplate debuff row on bar f. Returns true if the bar has a row.
local function BorrowRow(f, unit, db)
    local art = f.art
    local row, why, auras, unitFrame = Bars.PlateRow(unit)
    if art.row and art.row ~= row then
        if holder[art.row] == art then GiveBack(art.row) end
        art.row = nil
    end
    art.rowWhy = why
    if not row then return false end

    local prev = holder[row]
    if prev and prev ~= art then prev.row = nil end
    if not home[row] then
        local okScale, scale = pcall(row.GetScale, row)
        home[row] = { auras = auras, unitFrame = unitFrame, scale = (okScale and ns.CanRead(scale) and scale) or 1 }
    end
    holder[row], art.row, claimed[row] = art, row, true

    local itemScale = auras.auraItemScale
    if not (type(itemScale) == "number" and itemScale > 0) then itemScale = 1 end
    local scale = db.dotSize / (AURA_HEIGHT * itemScale)
    local okP, parent = pcall(row.GetParent, row)
    local okN, points = pcall(row.GetNumPoints, row)
    -- Blizzard re-anchors the row whenever the nameplate is set up again, so check every time.
    if not okP or parent ~= art or not okN or points ~= 1 or art.rowScale ~= scale then
        local ok, err = pcall(function()
            row:SetParent(art)
            row:SetScale(scale)
            row:ClearAllPoints()
            row:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -2 / scale, 2 / scale)
            row:SetFrameLevel(art.text:GetFrameLevel() + 2)
        end)
        if not ok then
            ns.rowError = "moving the row: " .. tostring(err)
            art.rowWhy = ns.rowError
            return false
        end
        art.rowScale = scale
    end

    -- Icon limit and countdown numbers, applied to Blizzard's icons through widget methods only.
    for _, item in ipairs({ row:GetChildren() }) do
        local index = item.layoutIndex
        local shown = type(index) ~= "number" or index <= db.maxDots
        item:SetAlpha(shown and 1 or 0)
        if item.Cooldown and item.Cooldown.SetHideCountdownNumbers then
            item.Cooldown:SetHideCountdownNumbers(not db.dotTimers)
        end
    end
    return true
end

-- Call before refreshing the bars...
function Bars.BeginRefresh() wipe(claimed) end

-- ...and after: rows no visible bar asked for go back to their nameplates.
function Bars.EndRefresh()
    for row, art in pairs(holder) do
        if not claimed[row] then
            art.row = nil
            GiveBack(row)
        end
    end
end

-- Gives every row back (feature turned off).
function Bars.ReleaseAll()
    wipe(claimed)
    Bars.EndRefresh()
end

function Bars.RowCount(row)
    local n = 0
    for _, item in ipairs({ row:GetChildren() }) do
        if item:IsShown() then n = n + 1 end
    end
    return n
end

local function UpdateDots(f, unit, db)
    EnsureDots(f, db)
    local dots = f.art.dots
    local auras, err
    if db.nameplateDots and BorrowRow(f, unit, db) then
        auras = {} -- Blizzard's icons are on the bar; hide DamageBot's own
    else
        -- Without a nameplate row, read the auras directly. This works out of combat only.
        auras, err = Bars.ReadAuras(unit, "HARMFUL|PLAYER", db.maxDots)
        if err then ns.auraError = err end
    end
    local n = 0
    for _, aura in ipairs(auras or {}) do
        n = n + 1
        local d = dots[n]
        if not d then break end
        d.icon:SetTexture(aura.icon)
        local id = aura.auraInstanceID
        local timed = false
        if C_UnitAuras.GetAuraDuration and d.cd.SetCooldownFromDurationObject then
            local ok, duration = pcall(C_UnitAuras.GetAuraDuration, unit, id)
            if ok and duration then timed = pcall(d.cd.SetCooldownFromDurationObject, d.cd, duration) end
        end
        if not timed then d.cd:Clear() end
        local okCount, count = false, nil
        if C_UnitAuras.GetAuraApplicationDisplayCount then
            okCount, count = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, id, 2)
        end
        d.count:SetText(okCount and count or "")
        Visible(d, true)
    end
    for i = n + 1, #dots do
        if dots[i]:GetAlpha() > 0 then
            dots[i].cd:Clear()
            Visible(dots[i], false)
        end
    end
end

-- Fills bar f from a unit. Returns whether the enemy is fighting you (true/false/nil).
function Bars.Update(f, unit, db)
    local art = f.art
    local name = UnitName(unit)
    art.name:SetText(name)
    art.health:SetMinMaxValues(0, UnitHealthMax(unit))
    art.health:SetValue(UnitHealth(unit))
    if db.showHealth then
        art.hp:SetText(UnitHealth(unit))
    else
        art.hp:SetText("")
    end

    local dead, deadReadable = Readable(UnitIsDead, unit)
    local fighting = Bars.IsFighting(unit, db)
    local idle = fighting == false
    local enemy, enemyReadable = Readable(UnitIsEnemy, "player", unit)
    local color = (enemyReadable and not enemy) and NEUTRAL or HOSTILE
    if deadReadable and dead then
        color = IDLE
        art.hp:SetText("|cff999999Dead|r")
    end
    SetColor(art, color, idle and db.dimIdle)
    art:SetAlpha((idle and db.dimIdle) and 0.45 or 1)

    local isTarget, targetReadable = Readable(UnitIsUnit, unit, "target")
    art.targetEdge:SetAlpha((targetReadable and isTarget) and 0.9 or 0)

    UpdateDots(f, unit, db)
    return fighting
end

-- Sample data for /dbot test, so the bars can be placed without a fight.
local SAMPLES = {
    { "Defias Pillager", 0.72, 377, HOSTILE, 2 },
    { "Riverpaw Gnoll", 0.40, 210, HOSTILE, 1 },
    { "Harvest Watcher", 0.95, 590, NEUTRAL, 0 },
}
local SAMPLE_ICONS = { 136118, 135817 } -- Corruption, Immolate

function Bars.UpdateSample(f, i, db)
    local s = SAMPLES[(i - 1) % #SAMPLES + 1]
    local art = f.art
    art.name:SetText(s[1])
    art.health:SetMinMaxValues(0, 1)
    art.health:SetValue(s[2])
    art.hp:SetText(db.showHealth and s[3] or "")
    SetColor(art, s[4], false)
    art:SetAlpha(1)
    art.targetEdge:SetAlpha(i == 1 and 0.9 or 0)
    EnsureDots(f, db)
    for n, d in ipairs(art.dots) do
        if n <= s[5] then
            d.icon:SetTexture(SAMPLE_ICONS[n])
            d.count:SetText("")
            Visible(d, true)
        else
            Visible(d, false)
        end
    end
end
