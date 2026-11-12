-- The Death Reason window: the hits of one death, killing blow at the top.
local _, ns = ...

local W = {}
ns.Window = W

local WIDTH, ROW_H, TOP, MAX_ROWS = 360, 24, 42, 20
local frame, rows = nil, {}
local index = 1 -- which saved death is shown (1 = latest)

-- Shows a value as text. Readable values are formatted; values the game hides can still be
-- shown by handing them straight to the text.
local function SetValue(fs, readable, raw, fallback)
    if readable then
        fs:SetText(readable)
    elseif raw ~= nil and not ns.CanRead(raw) then
        if not pcall(fs.SetText, fs, raw) then fs:SetText(fallback or "?") end
    else
        fs:SetText(fallback or "")
    end
end

local function Ago(when)
    if not (when and time) then return "" end
    local s = time() - when
    if s < 60 then return "just now" end
    if s < 3600 then return math.floor(s / 60) .. "m ago" end
    if s < 86400 then return math.floor(s / 3600) .. "h ago" end
    return math.floor(s / 86400) .. "d ago"
end

local function BuildRow(i)
    local r = CreateFrame("Frame", nil, frame)
    r:SetSize(WIDTH - 16, ROW_H - 2)
    r:SetPoint("TOPLEFT", 8, -TOP - (i - 1) * ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.08)

    r.time = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.time:SetPoint("LEFT", 2, 0)
    r.time:SetWidth(32)
    r.time:SetJustifyH("RIGHT")

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", r.time, "RIGHT", 5, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    r.spell = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.spell:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 5, 0)
    r.spell:SetWidth(125)
    r.spell:SetJustifyH("LEFT")
    r.spell:SetWordWrap(false)

    r.source = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.source:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 5, 0)
    r.source:SetWidth(125)
    r.source:SetJustifyH("LEFT")
    r.source:SetWordWrap(false)

    r.hpBar = CreateFrame("StatusBar", nil, r)
    r.hpBar:SetSize(44, 7)
    r.hpBar:SetPoint("BOTTOMRIGHT", -4, 3)
    r.hpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    r.hpBar:SetMinMaxValues(0, 100)
    r.hpBar.bg = r.hpBar:CreateTexture(nil, "BACKGROUND")
    r.hpBar.bg:SetAllPoints()
    r.hpBar.bg:SetColorTexture(0, 0, 0, 0.6)
    r.hp = r.hpBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.hp:SetPoint("BOTTOM", r.hpBar, "TOP", 0, 1)

    r.amount = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.amount:SetPoint("TOPRIGHT", r, "TOPRIGHT", -54, -1)
    r.amount:SetJustifyH("RIGHT")
    r.amount:SetTextColor(1, 0.3, 0.3)

    r.extra = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.extra:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -54, 1)
    r.extra:SetJustifyH("RIGHT")

    r.skull = r:CreateTexture(nil, "OVERLAY")
    r.skull:SetSize(12, 12)
    r.skull:SetPoint("TOPLEFT", r.icon, "TOPLEFT", -5, 5)
    r.skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    return r
end

local function Build()
    frame = CreateFrame("Frame", "DeathReasonFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 200)
    frame:SetPoint("CENTER", 0, 80)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "DeathReasonFrame") end -- Esc closes it

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 12, -10)
    frame.title:SetText("|cffcc3333Death Reason|r")

    frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
    frame.sub:SetWidth(WIDTH - 110)
    frame.sub:SetWordWrap(false)
    frame.sub:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetSize(26, 26)

    local function Nav(dir, label)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(20, 18)
        b:SetText(label)
        b:SetScript("OnClick", function() W.Show(index + dir) end)
        return b
    end
    frame.older = Nav(1, ">")
    frame.older:SetPoint("TOPRIGHT", -26, -6)
    frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.count:SetPoint("RIGHT", frame.older, "LEFT", -4, 0)
    frame.newer = Nav(-1, "<")
    frame.newer:SetPoint("RIGHT", frame.count, "LEFT", -4, 0)

    frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.note:SetPoint("BOTTOMLEFT", 12, 8)
    frame.note:SetWidth(WIDTH - 24)
    frame.note:SetJustifyH("LEFT")

    for i = 1, MAX_ROWS do rows[i] = BuildRow(i) end
end

local function FillRow(r, hit, isKill)
    local before = type(hit.before) == "number" and ns.CanRead(hit.before) and hit.before or nil
    r.time:SetText(before and (before < 0.05 and "0s" or ("-%.1fs"):format(before)) or "")

    r.icon:SetTexture(hit.icon or (hit.unknown and "Interface\\Icons\\INV_Misc_QuestionMark") or "Interface\\Icons\\INV_Misc_QuestionMark")

    local color = ns.SchoolColor(hit.school)
    local spellText = (type(hit.spell) == "string" and ns.CanRead(hit.spell)) and ("|cff" .. color .. hit.spell .. "|r") or nil
    if hit.unknown then
        local school = ns.SchoolName(hit.school)
        spellText = "|cff" .. color .. (school and (school .. " damage") or "Damage") .. "|r"
    end
    SetValue(r.spell, spellText, hit.spell, "?")

    local sourceText = (type(hit.source) == "string" and ns.CanRead(hit.source)) and hit.source or nil
    if hit.unknown then sourceText = "attacker unknown" end
    SetValue(r.source, sourceText, hit.source, "unknown attacker")

    SetValue(r.amount, ns.Short(hit.amount) and ("-" .. ns.Short(hit.amount)), hit.amount, "")
    r.extra:SetText(ns.Extra(hit) or "")

    local pct = ns.HealthPercent(hit)
    if pct then
        r.hpBar:Show()
        r.hpBar:SetMinMaxValues(0, 100)
        r.hpBar:SetValue(pct)
        r.hpBar:SetStatusBarColor(pct > 50 and 0.2 or 0.9, pct > 25 and 0.8 or 0.2, 0.2)
        r.hp:SetText(pct .. "%")
    elseif hit.currentHP ~= nil and not ns.CanRead(hit.currentHP) then
        r.hpBar:Show()
        pcall(r.hpBar.SetMinMaxValues, r.hpBar, 0, hit.maxHealth or (UnitHealthMax and UnitHealthMax("player")) or 1)
        pcall(r.hpBar.SetValue, r.hpBar, hit.currentHP)
        r.hpBar:SetStatusBarColor(0.2, 0.8, 0.2)
        r.hp:SetText("")
    else
        r.hpBar:Hide()
    end

    r.skull:SetShown(isKill)
    if isKill then r.bg:SetColorTexture(0.8, 0.1, 0.1, 0.25) end
    r:Show()
end

-- Shows one death (a table like those in DeathReasonDB.deaths).
function W.ShowDeath(death, position, total)
    if not frame then Build() end
    local hits = death.hits or {}
    local shown = math.min(#hits, MAX_ROWS)
    for i = 1, MAX_ROWS do
        local r = rows[i]
        r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.08)
        if i <= shown then FillRow(r, hits[i], i == 1) else r:Hide() end
    end

    local kill = hits[1]
    local killer = kill and type(kill.source) == "string" and ns.CanRead(kill.source) and kill.source
    local sub = killer and ("Killed by |cffffd100" .. killer .. "|r") or "You died"
    if death.zone then sub = sub .. " in " .. death.zone end
    if death.sample then sub = "Sample death (/dreason test)" else sub = sub .. ", " .. Ago(death.when) end
    frame.sub:SetText(sub)

    local unknown = 0
    for _, h in ipairs(hits) do if h.unknown then unknown = unknown + 1 end end
    local note = ""
    if #hits == 0 then
        note = "No hits were recorded for this death." .. (death.note and (" " .. death.note .. ".") or "")
    elseif unknown > 0 then
        note = ("%d hits from the game's death recap; %d recorded by Death Reason, which can't see who hit you."):format(#hits - unknown, unknown)
    end
    frame.note:SetText(note)

    total = total or 0
    frame.count:SetText(total > 0 and (position .. "/" .. total) or "")
    frame.newer:SetShown(total > 0)
    frame.older:SetShown(total > 0)
    if frame.newer.SetEnabled then
        frame.newer:SetEnabled((position or 1) > 1)
        frame.older:SetEnabled((position or 1) < total)
    end

    frame:SetHeight(TOP + math.max(shown, 1) * ROW_H + (note ~= "" and 30 or 10))
    W.ApplyScale()
    frame:Show()
end

-- The "Window size" setting (percent).
function W.ApplyScale()
    if frame and ns.db then frame:SetScale((ns.db.scale or 100) / 100) end
end

function W.Hide()
    if frame then frame:Hide() end
end

-- Shows saved death number i (1 = latest). The latest death of this session is shown from
-- its live copy, which may include values the game hid (they can't be saved).
function W.Show(i)
    local deaths = ns.db.deaths
    if #deaths == 0 then return end
    index = math.max(1, math.min(i or 1, #deaths))
    local death = (index == 1 and ns.live) or deaths[index]
    W.ShowDeath(death, index, #deaths)
end
