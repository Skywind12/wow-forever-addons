-- The panel shown beside the profession window. It is built from the same Blizzard
-- templates the Forever profession window uses (portrait frame, inset, scroll box,
-- minimal scroll bar), so it looks like part of the game. Every template is optional:
-- if one is missing on this client, a plain fallback is used instead.
local _, ns = ...

local Panel = {}
ns.Panel = Panel

local WIDTH, MIN_HEIGHT = 340, 480
local MAX_VENDORS = 6 -- per reagent, until you click "more"
local HEIGHTS = { reagent = 42, zone = 24, vendor = 20, note = 18, more = 18, spacer = 10 }
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local VENDOR_ICON = "Interface\\GossipFrame\\VendorGossipIcon"
local READY_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t"

local state = { reagents = nil, expanded = {}, standalone = false, professionOpen = false }

local function TryCreate(frameType, name, parent, template)
    local ok, f = pcall(CreateFrame, frameType, name, parent, template)
    if ok then return f end
    return nil
end

local function HasAtlas(atlas)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local function SetAtlasOr(tex, atlas, r, g, b, a)
    if HasAtlas(atlas) then
        tex:SetAtlas(atlas)
        return true
    end
    tex:SetColorTexture(r, g, b, a)
    return false
end

local function QualityColor(itemID)
    local q = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local frame = TryCreate("Frame", "ReagentScoutPanel", UIParent, "PortraitFrameTemplate")
local styled = frame ~= nil
if not frame then
    frame = CreateFrame("Frame", "ReagentScoutPanelBasic", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    end
end
frame:SetSize(WIDTH, MIN_HEIGHT)
frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
frame:SetFrameStrata("HIGH")
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()

local titleText
if styled and frame.SetTitle then
    frame:SetTitle(ns.name)
else
    titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", 0, -8)
    titleText:SetText(ns.name)
end

local function SetPortrait(icon)
    if styled and frame.SetPortraitToAsset then
        pcall(frame.SetPortraitToAsset, frame, icon or DEFAULT_ICON)
    end
end
SetPortrait(DEFAULT_ICON)

-- Our own close behaviour (not Blizzard's panel manager).
local close = frame.CloseButton or TryCreate("Button", nil, frame, "UIPanelCloseButton")
if close then
    if not frame.CloseButton then close:SetPoint("TOPRIGHT", -2, -2) end
    close:SetScript("OnClick", function()
        frame:Hide()
        if not state.standalone and ns.db then
            ns.db.panel.shown = false
            ns.Print("panel hidden. Type /rscout show to bring it back.")
        end
    end)
end

-- Header: recipe name and a hint line, to the right of the round portrait.
local headerLeft = styled and 64 or 14
local recipeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
recipeText:SetPoint("TOPLEFT", headerLeft, -30)
recipeText:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
recipeText:SetJustifyH("LEFT")
recipeText:SetWordWrap(false)

local hintText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hintText:SetPoint("TOPLEFT", recipeText, "BOTTOMLEFT", 0, -3)
hintText:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
hintText:SetJustifyH("LEFT")

-- Inset content area, like the profession window's recipe list.
local inset = TryCreate("Frame", nil, frame, "InsetFrameTemplate") or CreateFrame("Frame", nil, frame)
inset:SetPoint("TOPLEFT", 8, -70)
inset:SetPoint("BOTTOMRIGHT", -8, 34)
local insetBg = inset:CreateTexture(nil, "BACKGROUND", nil, 1)
insetBg:SetPoint("TOPLEFT", 3, -3)
insetBg:SetPoint("BOTTOMRIGHT", -3, 3)
SetAtlasOr(insetBg, "Professions-background-summarylist", 0, 0, 0, 0.35)

local footerLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
footerLabel:SetPoint("BOTTOMLEFT", 14, 13)
local footerValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
footerValue:SetPoint("BOTTOMRIGHT", -14, 12)
footerValue:SetJustifyH("RIGHT")

------------------------------------------------------------------------
-- Rows (shared by both list backends)
------------------------------------------------------------------------
function ns.SetWaypoint(c)
    local where = ("%s, %s"):format(c.name, c.zoneName or "?")
    if c.x then where = where .. (" (%.1f, %.1f)"):format(c.x, c.y) end
    if not (c.map and c.x) then ns.Print(where) return end
    if TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(c.map, c.x / 100, c.y / 100, { title = c.name, from = ns.name })
        ns.Print("TomTom waypoint set: " .. where)
        return
    end
    if C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local can = not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(c.map)
        if can and pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(c.map, c.x / 100, c.y / 100)) then
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
            end
            ns.Print("map pin set: " .. where)
            return
        end
    end
    ns.Print(where)
end

local SetWaypoint = ns.SetWaypoint

local function RowOnEnter(self)
    local d = self.data
    if not d then return end
    if d.kind == "reagent" then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(d.itemID) end
        GameTooltip:Show()
    elseif d.kind == "vendor" then
        local c = d.vendor
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(c.name, 1, 1, 1)
        if c.sub then GameTooltip:AddLine("<" .. c.sub .. ">", 0.7, 0.7, 0.7) end
        GameTooltip:AddLine(c.zoneName or "?", 1, 0.82, 0)
        if c.x then GameTooltip:AddLine(("%.1f, %.1f"):format(c.x, c.y), 0.8, 0.8, 0.8) end
        GameTooltip:AddLine(c.source == "visited" and "You've visited this vendor." or "Location from Forever vendor data.", 0.5, 0.8, 1)
        GameTooltip:AddLine("Click to set a waypoint.", 0.3, 1, 0.3)
        GameTooltip:Show()
    end
end

local function RowOnClick(self)
    local d = self.data
    if not d then return end
    if d.kind == "vendor" then
        SetWaypoint(d.vendor)
    elseif d.kind == "more" then
        state.expanded[d.itemID] = true
        Panel.Refresh()
    end
end

local function BuildRow(b)
    b.created = true
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    SetAtlasOr(b.hl, "Professions_Recipe_Hover", 1, 1, 1, 0.08)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Common\\WhiteIconFrame")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.sub:SetJustifyH("LEFT")
    b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.right:SetJustifyH("RIGHT")
    b.right2 = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.right2:SetJustifyH("RIGHT")
    b.divider = b:CreateTexture(nil, "ARTWORK")
    b.divider:SetHeight(2)
    b.divider:SetPoint("BOTTOMLEFT", 6, 0)
    b.divider:SetPoint("BOTTOMRIGHT", -6, 0)
    SetAtlasOr(b.divider, "Options_HorizontalDivider", 1, 0.82, 0, 0.25)
    b:SetScript("OnEnter", RowOnEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", RowOnClick)
end

function ns.DistanceText(c)
    if c.dist then
        local text = c.dist >= 1000 and ("%.1fk yd"):format(c.dist / 1000) or ("%d yd"):format(c.dist)
        if c.dist <= 300 then return "|cff55ff55" .. text .. "|r" end
        if c.dist <= 1500 then return "|cffffd100" .. text .. "|r" end
        return "|cffbbbbbb" .. text .. "|r"
    end
    if c.otherContinent then return "|cff888888other continent|r" end
    return ""
end

local DistanceText = ns.DistanceText

local function InitRow(b, d)
    if not b.created then BuildRow(b) end
    b.data = d
    for _, part in ipairs({ b.icon, b.border, b.text, b.sub, b.right, b.right2, b.divider }) do
        part:Hide()
        if part ~= b.divider then part:ClearAllPoints() end
    end
    b.bg:SetColorTexture(0, 0, 0, 0)
    b.hl:SetAlpha(1)
    b:EnableMouse(d.kind == "reagent" or d.kind == "vendor" or d.kind == "more")

    if d.kind == "reagent" then
        b.bg:SetColorTexture(1, 1, 1, 0.05)
        b.hl:SetAlpha(0.4)
        b.icon:SetSize(32, 32)
        b.icon:SetPoint("LEFT", 6, 0)
        b.icon:SetTexture(ns.GetItemIcon(d.itemID))
        b.icon:Show()
        b.border:SetAllPoints(b.icon)
        b.border:SetVertexColor(QualityColor(d.itemID))
        b.border:Show()
        b.right:SetPoint("TOPRIGHT", -8, -7)
        b.right:SetText(d.price and (ns.FormatMoney(d.price) .. " |cff999999each|r") or "|cff888888price unknown|r")
        b.right:Show()
        b.right2:SetPoint("BOTTOMRIGHT", -8, 7)
        b.right2:SetText(d.short == 0 and (READY_ICON .. " |cff55ff55ready|r") or ("|cffff9933buy %d|r"):format(d.short))
        b.right2:Show()
        b.text:SetFontObject("GameFontNormal")
        b.text:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, -2)
        b.text:SetPoint("RIGHT", b.right, "LEFT", -6, 0)
        b.text:SetText(ns.GetItemName(d.itemID))
        b.text:SetTextColor(QualityColor(d.itemID))
        b.text:Show()
        b.sub:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 8, 2)
        b.sub:SetText(("|cff999999Need|r %d   |cff999999Have|r %s"):format(d.need,
            d.have >= d.need and ("|cff55ff55" .. d.have .. "|r") or ("|cffff7777" .. d.have .. "|r")))
        b.sub:Show()
    elseif d.kind == "zone" then
        b.right:SetPoint("RIGHT", -10, 1)
        b.right:SetText(d.isHere and "|cff55ff55you are here|r" or "")
        b.right:Show()
        b.text:SetFontObject("GameFontNormal")
        b.text:SetPoint("LEFT", 12, 1)
        b.text:SetPoint("RIGHT", b.right, "LEFT", -6, 0)
        b.text:SetText(d.name)
        b.text:SetTextColor(1, 0.82, 0)
        b.text:Show()
        b.divider:Show()
    elseif d.kind == "vendor" then
        local c = d.vendor
        b.icon:SetSize(14, 14)
        b.icon:SetPoint("LEFT", 18, 0)
        b.icon:SetTexture(VENDOR_ICON)
        b.icon:Show()
        b.right:SetPoint("RIGHT", -10, 0)
        b.right:SetText(DistanceText(c))
        b.right:Show()
        b.text:SetFontObject("GameFontHighlightSmall")
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
        b.text:SetPoint("RIGHT", b.right, "LEFT", -6, 0)
        local label = c.name .. (c.sub and (" |cff999999<" .. c.sub .. ">|r") or "")
        if c.source == "visited" then label = label .. " |cff66ccff*|r" end
        b.text:SetText(label)
        b.text:SetTextColor(1, 1, 1)
        b.text:Show()
    elseif d.kind == "note" or d.kind == "more" then
        b.text:SetFontObject("GameFontHighlightSmall")
        b.text:SetPoint("LEFT", d.indent or 40, 0)
        b.text:SetPoint("RIGHT", -10, 0)
        b.text:SetText(d.text)
        b.text:SetTextColor(1, 1, 1)
        b.text:Show()
    end
end

------------------------------------------------------------------------
-- List backends: Blizzard's ScrollBox (preferred) or a simple clipped list
------------------------------------------------------------------------
local list = {}
local box, bar

local function SetupScrollBox()
    if not (CreateScrollBoxListLinearView and ScrollUtil and CreateDataProvider) then return false end
    box = TryCreate("Frame", nil, inset, "WowScrollBoxList")
    bar = box and TryCreate("EventFrame", nil, inset, "MinimalScrollBar")
    if not (box and bar) then return false end
    bar:SetPoint("TOPRIGHT", -8, -8)
    bar:SetPoint("BOTTOMRIGHT", -8, 8)
    box:SetPoint("TOPLEFT", 4, -4)
    box:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", -4, -4)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtentCalculator(function(_, d) return HEIGHTS[d.kind] or 18 end)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)

    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    function list.Set(rows) box:SetDataProvider(CreateDataProvider(rows), retain) end
    function list.ScrollToTop() pcall(box.ScrollToBegin, box) end
    return true
end

local function SetupSimpleList()
    local clip = CreateFrame("Frame", nil, inset)
    clip:SetPoint("TOPLEFT", 4, -4)
    clip:SetPoint("BOTTOMRIGHT", -4, 4)
    clip:SetClipsChildren(true)
    clip:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, clip)
    content:SetSize(WIDTH - 24, 1)
    local buttons, offset = {}, 0

    local function Apply()
        local maxOffset = math.max(0, content:GetHeight() - clip:GetHeight())
        offset = math.min(math.max(offset, 0), maxOffset)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, offset)
    end
    clip:SetScript("OnMouseWheel", function(_, delta) offset = offset - delta * 40; Apply() end)

    function list.Set(rows)
        local y = 0
        for i, d in ipairs(rows) do
            local b = buttons[i] or CreateFrame("Button", nil, content)
            buttons[i] = b
            local h = HEIGHTS[d.kind] or 18
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 0, -y)
            b:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            b:SetHeight(h)
            InitRow(b, d)
            b:Show()
            y = y + h
        end
        for i = #rows + 1, #buttons do buttons[i]:Hide() end
        content:SetHeight(math.max(1, y))
        Apply()
    end
    function list.ScrollToTop() offset = 0; Apply() end
end

local okBox, usedBox = pcall(SetupScrollBox)
if not (okBox and usedBox) then
    if box then box:Hide() end
    if bar then bar:Hide() end
    SetupSimpleList()
end

------------------------------------------------------------------------
-- Building the rows from the selected recipe
------------------------------------------------------------------------
local function BuildRows()
    local rows, total, unknownPrice = {}, 0, false
    local qdbOk = ns.QDB.Ready()
    local function Add(d) rows[#rows + 1] = d end

    for i, r in ipairs(state.reagents or {}) do
        if i > 1 then Add({ kind = "spacer" }) end
        local have = ns.GetItemCount(r.itemID)
        local price = ns.Vendors.Price(r.itemID)
        local short = math.max(0, r.need - have)
        Add({ kind = "reagent", itemID = r.itemID, need = r.need, have = have, short = short, price = price })

        local zones, vendorCount = ns.Vendors.Lookup(r.itemID)
        if vendorCount == 0 then
            Add({ kind = "note", indent = 48,
                text = "|cff888888No known vendor. Open one that sells it and it'll be remembered.|r" })
        else
            if short > 0 then
                if price then total = total + price * short else unknownPrice = true end
            end
            if not price then
                Add({ kind = "note", indent = 48, text = "|cff888888Open any vendor that sells it once to learn the price|r" })
            end
            local shown, limit = 0, state.expanded[r.itemID] and math.huge or MAX_VENDORS
            for _, z in ipairs(zones) do
                if shown >= limit then break end
                Add({ kind = "zone", name = z.name, isHere = z.isHere })
                for _, c in ipairs(z.vendors) do
                    if shown >= limit then break end
                    shown = shown + 1
                    Add({ kind = "vendor", vendor = c })
                end
            end
            if vendorCount > shown then
                Add({ kind = "more", itemID = r.itemID, indent = 38,
                    text = ("|cff66ccffShow %d more vendors|r"):format(vendorCount - shown) })
            end
        end
    end

    if #rows == 0 then
        Add({ kind = "note", indent = 14, text = "|cff888888Select a recipe in your profession window.|r" })
    end
    return rows, total, unknownPrice
end

local function Render()
    local rows, total, unknownPrice = BuildRows()
    list.Set(rows)

    if state.reagents and #state.reagents > 0 then
        footerLabel:SetText("Cost of what you're missing")
        if total > 0 then
            footerValue:SetText(ns.FormatMoney(total) .. (unknownPrice and " |cff888888+ ?|r" or ""))
        else
            footerValue:SetText(unknownPrice and "|cff888888?|r" or "|cff55ff55nothing|r")
        end
    else
        footerLabel:SetText("")
        footerValue:SetText("")
    end
    hintText:SetText(ns.Vendors.PlayerPosition() and "Nearest vendors first. Click one for a waypoint."
        or "Your position isn't readable here, so distances are hidden.")
end

------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------
local ticker

-- HookScript keeps any OnShow/OnHide the template itself defines.
frame:HookScript("OnShow", function()
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(3, function() if frame:IsShown() then Render() end end)
end)
frame:HookScript("OnHide", function()
    if ticker then ticker:Cancel(); ticker = nil end
end)

function Panel.IsShown() return frame:IsShown() end

function Panel.Refresh()
    if frame:IsShown() then Render() end
end

function Panel.ShowItems(reagents, recipeName, icon)
    state.reagents = reagents
    state.expanded = {}
    recipeText:SetText(recipeName or "")
    SetPortrait(icon)
    if not state.professionOpen then
        state.standalone = true
        frame:Show()
    elseif ns.db and ns.db.panel.shown then
        frame:Show()
    end
    Render()
    list.ScrollToTop()
end

local function Dock()
    if not (state.professionOpen and ProfessionsFrame) then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 2, 0)
    frame:SetHeight(math.max(MIN_HEIGHT, ProfessionsFrame:GetHeight() or MIN_HEIGHT))
end

-- Dock next to the profession window when it opens; hide when it closes.
function Panel.Attach(open)
    state.professionOpen = open
    if open then
        state.standalone = false
        Dock()
        C_Timer.After(0.1, Dock) -- the profession window may still be loading on first open
        if ns.db and ns.db.panel.shown then frame:Show() end
    elseif not state.standalone then
        frame:Hide()
    end
end

function Panel.Toggle(show)
    if ns.db then ns.db.panel.shown = show end
    if show then
        frame:Show()
        Render()
    else
        frame:Hide()
    end
end

local pending
local function SoonRefresh()
    if pending or not frame:IsShown() then return end
    pending = true
    C_Timer.After(0.5, function() pending = false; Render() end)
end
ns.On("GET_ITEM_INFO_RECEIVED", SoonRefresh)
ns.On("BAG_UPDATE_DELAYED", SoonRefresh)
ns.On("ZONE_CHANGED_NEW_AREA", SoonRefresh)
