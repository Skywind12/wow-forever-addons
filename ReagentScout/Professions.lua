-- Adds a small "price - place" line right under each reagent's name in the profession window.
--
-- Forever runs its UI through secure code, so this file never hooks Blizzard functions or
-- writes fields on Blizzard's frames. It only reads the reagent slots the profession window
-- already shows, and puts its own small labels inside the recipe area next to them.
local _, ns = ...

local P = {}
ns.Professions = P

local BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
local LABEL_X, LABEL_Y = 46, 2     -- under the reagent name (the icon takes the first 46px)
local LABEL_W, LABEL_H = 150, 12
local LOOKUP_TTL = 3               -- seconds before vendor distances are recalculated
local INTERVAL = 0.25              -- how often the visible reagents are checked

local driver = CreateFrame("Frame", nil, UIParent) -- only runs the timer, never shown on screen
local layer                                         -- our own frame inside the recipe area
local labels, cache, errors = {}, {}, {}

------------------------------------------------------------------------
-- Reading the profession window
------------------------------------------------------------------------
local function GetForm()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    return page and page.SchematicForm
end

-- Returns { slot, itemID, need } for every visible basic reagent.
local function VisibleReagents(form)
    local out = {}
    if type(form.reagentSlots) ~= "table" then return out end
    for reagentType, slots in pairs(form.reagentSlots) do
        if (BASIC == nil or reagentType == BASIC) and type(slots) == "table" then
            for _, slot in ipairs(slots) do
                local schematic = slot.reagentSlotSchematic
                local reagent = schematic and schematic.reagents and schematic.reagents[1]
                local itemID = reagent and reagent.itemID
                if itemID and ns.CanRead(itemID) and slot:IsVisible() then
                    out[#out + 1] = { slot = slot, itemID = itemID, need = schematic.quantityRequired or 1 }
                end
            end
        end
    end
    return out
end

------------------------------------------------------------------------
-- Vendor info per item (cached briefly)
------------------------------------------------------------------------
local function Info(itemID)
    local now = GetTime()
    local c = cache[itemID]
    if c and now - c.time < LOOKUP_TTL then return c end
    local zones, count = ns.Vendors.Lookup(itemID)
    local best
    for _, z in ipairs(zones) do
        for _, v in ipairs(z.vendors) do
            if not best or (v.dist and (not best.dist or v.dist < best.dist)) then best = v end
        end
    end
    c = { time = now, zones = zones, count = count, best = best }
    cache[itemID] = c
    return c
end

function P.ClearCache() wipe(cache) end

local function LabelText(itemID, info)
    local price = ns.Vendors.Price(itemID)
    local priceText = price and ns.FormatMoney(price) or "|cff888888?|r"
    local best = info.best
    local place = best.zoneName or "?"
    if ns.db and ns.db.colorDistance == false then
        place = "|cffffffff" .. place .. "|r"
    elseif best.dist and best.dist <= 300 then
        place = "|cff55ff55" .. place .. "|r"
    elseif best.dist and best.dist <= 1500 then
        place = "|cffffd100" .. place .. "|r"
    else
        place = "|cffbbbbbb" .. place .. "|r"
    end
    return priceText .. " |cff888888-|r " .. place
end

------------------------------------------------------------------------
-- Labels
------------------------------------------------------------------------
local function ShowTooltip(self)
    local d = self.data
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.GetItemName(d.itemID), 1, 1, 1)
    local price = ns.Vendors.Price(d.itemID)
    GameTooltip:AddDoubleLine("Price", price and (ns.FormatMoney(price) .. " each") or "open a vendor that sells it once",
        1, 0.82, 0, 1, 1, 1)
    local maxZones = ns.db and ns.db.tooltipZones or 3
    local maxVendors = ns.db and ns.db.tooltipVendors or 3
    local shownZones = 0
    for _, z in ipairs(d.info.zones) do
        if shownZones >= maxZones then break end
        shownZones = shownZones + 1
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(z.name .. (z.isHere and " |cff55ff55(you are here)|r" or ""), 1, 0.82, 0)
        for i, v in ipairs(z.vendors) do
            if i > maxVendors then break end
            GameTooltip:AddDoubleLine("  " .. v.name, ns.DistanceText(v), 1, 1, 1, 1, 1, 1)
        end
    end
    if d.info.count > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click for a waypoint to " .. d.info.best.name .. ".", 0.3, 1, 0.3)
    end
    GameTooltip:Show()
end

-- Our labels live in one frame of our own, created inside the recipe area the first time
-- it's seen. Being inside it, they share its scale and layer and hide when it hides.
local function GetLayer(form)
    if not layer then
        layer = CreateFrame("Frame", nil, form)
        layer:SetAllPoints(form)
        layer:SetFrameLevel(form:GetFrameLevel() + 20)
    end
    return layer
end

local function NewLabel(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(LABEL_W, LABEL_H)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetAllPoints()
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnEnter", ShowTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if self.data and self.data.info.best then ns.SetWaypoint(self.data.info.best) end
    end)
    return b
end

local function HideFrom(n)
    for i = n, #labels do labels[i]:Hide() end
end

function P.Update()
    local form = GetForm()
    if not (form and form:IsVisible()) or (ns.db and ns.db.inline == false) then
        HideFrom(1)
        return
    end
    local parent = GetLayer(form)
    local n = 0
    for _, r in ipairs(VisibleReagents(form)) do
        local info = Info(r.itemID)
        if info.count > 0 and info.best then
            n = n + 1
            local b = labels[n] or NewLabel(parent)
            labels[n] = b
            b.data = { itemID = r.itemID, info = info }
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", r.slot, "BOTTOMLEFT", LABEL_X, LABEL_Y)
            b.text:SetText(LabelText(r.itemID, info))
            b:Show()
        end
    end
    HideFrom(n + 1)
end

-- Blizzard's code swaps recipes without telling addons, so check a few times a second.
-- This is a cheap check while the profession window is closed.
local elapsed = 0
driver:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < INTERVAL then return end
    elapsed = 0
    local ok, err = pcall(P.Update)
    if not ok then
        err = tostring(err)
        P.lastError = err
        if not errors[err] then
            errors[err] = true
            ns.Print("|cffff5555couldn't read the profession window:|r", err)
        end
    end
end)

ns.On("MERCHANT_CLOSED", function() P.ClearCache() end)

------------------------------------------------------------------------
-- /rscout debug: what the addon sees in the profession window right now
------------------------------------------------------------------------
function P.Debug()
    ns.Print("debug (version " .. tostring(ns.version) .. ")")
    print("  ProfessionsFrame: " .. (ProfessionsFrame and (ProfessionsFrame:IsVisible() and "open" or "closed") or "not loaded yet"))
    local form = GetForm()
    if not form then print("  Recipe area: not found") return end
    print("  Recipe area: " .. (form:IsVisible() and "visible" or "hidden"))
    if type(form.reagentSlots) ~= "table" then print("  Reagent slots: none") return end
    for reagentType, slots in pairs(form.reagentSlots) do
        print(("  Slot type %s%s: %d"):format(tostring(reagentType), reagentType == BASIC and " (basic)" or "",
            type(slots) == "table" and #slots or 0))
    end
    for _, r in ipairs(VisibleReagents(form)) do
        local info = Info(r.itemID)
        print(("  %s (%d): %d vendors, nearest %s"):format(ns.GetItemName(r.itemID), r.itemID, info.count,
            info.best and ((info.best.name or "?") .. " in " .. (info.best.zoneName or "?")) or "none"))
    end
    local shown = 0
    for _, b in ipairs(labels) do if b:IsShown() then shown = shown + 1 end end
    print(("  Lines shown: %d   Setting 'show lines': %s"):format(shown, tostring(not (ns.db and ns.db.inline == false))))
    print("  Last error: " .. (P.lastError or "none"))
end
