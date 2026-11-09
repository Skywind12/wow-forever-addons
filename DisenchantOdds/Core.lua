-- Disenchant Odds: adds what an item disenchants into, and the chance of each result,
-- to item tooltips.
local ADDON, ns = ...

local PREFIX = "|cffa335eeDisenchant Odds|r: "
local function Print(...) print(PREFIX .. string.join(" ", tostringall(...))) end

ns.defaults = {
    enabled = true,
    onlyShift = false,      -- only while holding Shift
    onlyEnchanter = false,  -- only on characters that know Enchanting
    showSkill = true,       -- Enchanting skill needed
    showValue = true,       -- expected auction value (needs Auctionator)
    showIcons = true,
}

local WEAPON, ARMOR = 2, 4
local ENCHANTING_SKILL_LINE = 333
local HEADER_COLOR = { 0.64, 0.21, 0.93 }
local GRAY = { 0.6, 0.6, 0.6 }

------------------------------------------------------------------------
-- Game info
------------------------------------------------------------------------
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local GetLevel = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo

-- Your Enchanting skill, or nil if this character doesn't know Enchanting.
local function MyEnchanting()
    if GetProfessions and GetProfessionInfo then
        local ok, a, b = pcall(GetProfessions)
        if ok then
            for _, index in ipairs({ a, b }) do
                local ok2, _, _, rank, _, _, _, skillLine = pcall(GetProfessionInfo, index)
                if ok2 and skillLine == ENCHANTING_SKILL_LINE then return rank end
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        local ok, n = pcall(GetNumSkillLines)
        for i = 1, (ok and n or 0) do
            local name, isHeader, _, rank = GetSkillLineInfo(i)
            if not isHeader and name == "Enchanting" then return rank end
        end
    end
end
ns.MyEnchanting = MyEnchanting

local function MaterialName(id)
    local name = GetItemInfo(id)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return name or ns.NAMES[id] or ("item " .. id)
end

-- Auction price of one material, from Auctionator if it's installed.
local function AuctionPrice(id)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemID) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON, id)
    return ok and type(price) == "number" and price or nil
end

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------
local function QualityColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- What disenchanting this item gives, or nil if it can't be disenchanted.
function ns.ForItem(link)
    if not link then return nil end
    local _, _, quality, baseLevel, _, _, _, _, _, _, _, classID = GetItemInfo(link)
    if not quality or (classID ~= WEAPON and classID ~= ARMOR) or quality < 2 or quality > 4 then return nil end
    local level = (GetLevel and GetLevel(link)) or baseLevel
    if not level then return nil end
    return ns.Results(quality, level, classID == WEAPON), quality, level
end

function ns.AddLines(tooltip, link)
    local db = ns.db
    if not db or not db.enabled then return end
    if db.onlyShift and not IsShiftKeyDown() then return end
    local results, quality, level = ns.ForItem(link)
    if quality == nil then return end
    local skill = MyEnchanting()
    if db.onlyEnchanter and not skill then return end

    local need = ns.RequiredSkill(quality, level)
    local right, r, g, b = "", GRAY[1], GRAY[2], GRAY[3]
    if db.showSkill then
        right = "Enchanting " .. need
        if skill then
            if skill >= need then r, g, b = 0.25, 1, 0.25 else r, g, b = 1, 0.3, 0.3 end
        end
    end
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("Disenchants into:", right, HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3], r, g, b)

    if not results then
        tooltip:AddLine(("  no data for item level %d"):format(level), GRAY[1], GRAY[2], GRAY[3])
        return
    end

    local value, missing = 0, false
    for _, res in ipairs(results) do
        local qty = res.min == res.max and tostring(res.min) or (res.min .. "-" .. res.max)
        local icon = db.showIcons and GetIcon and GetIcon(res.item)
        local text = "  " .. (icon and ("|T" .. icon .. ":14:14|t ") or "") .. qty .. "x " .. MaterialName(res.item)
        local chance = (res.chance % 1 == 0) and (res.chance .. "%") or (("%.1f%%"):format(res.chance))
        local qr, qg, qb = QualityColor(ns.QUALITY[res.item] or 1)
        tooltip:AddDoubleLine(text, chance, qr, qg, qb, 1, 1, 1)
        if db.showValue then
            local price = AuctionPrice(res.item)
            if price then
                value = value + res.chance / 100 * (res.min + res.max) / 2 * price
            else
                missing = true
            end
        end
    end
    if db.showValue and value > 0 and GetMoneyString then
        local money = GetMoneyString(math.floor(value / 100 + 0.5) * 100, true) -- rounded to silver
        tooltip:AddDoubleLine("  Average value (Auctionator)" .. (missing and " *" or ""), money,
            GRAY[1], GRAY[2], GRAY[3], 1, 1, 1)
    end
    tooltip:Show() -- resize to fit the new lines
end

local function OnItemTooltip(tooltip, data)
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local link = data and data.hyperlink
    if not link and tooltip.GetItem then
        local ok, _, l = pcall(tooltip.GetItem, tooltip)
        link = ok and l or nil
    end
    if not link and data and data.id then link = "item:" .. data.id end
    local ok, err = pcall(ns.AddLines, tooltip, link)
    if not ok and not ns.reported then
        ns.reported = true
        Print("|cffff5555tooltip error:|r", tostring(err))
    end
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
        return
    end
    -- Older tooltip API.
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
        if tip and tip.HookScript then
            pcall(tip.HookScript, tip, "OnTooltipSetItem", function(self) OnItemTooltip(self) end)
        end
    end
end

------------------------------------------------------------------------
-- Settings: Esc > Options > AddOns > Disenchant Odds
------------------------------------------------------------------------
local OPTIONS = {
    { "enabled", "Show disenchant results", "Adds what an item disenchants into, and the chance of each result, to item tooltips." },
    { "onlyShift", "Only while holding Shift", "Keeps tooltips short: the disenchant lines appear only while you hold Shift." },
    { "onlyEnchanter", "Only on my enchanters", "Hide the lines on characters that don't know Enchanting." },
    { "showSkill", "Show Enchanting skill needed", "Green if your skill is high enough, red if not, gray if this character isn't an enchanter." },
    { "showValue", "Show average auction value", "Average value of what you get, from Auctionator's last scan. * means some prices are unknown." },
    { "showIcons", "Show material icons", "Small icons next to each material." },
}

local category
local function RegisterSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
    category = Settings.RegisterVerticalLayoutCategory("Disenchant Odds")
    for _, o in ipairs(OPTIONS) do
        local key, label, tip = o[1], o[2], o[3]
        local setting = Settings.RegisterAddOnSetting(category, "DisenchantOdds_" .. key, key, ns.db, "boolean", label, ns.defaults[key])
        Settings.CreateCheckbox(category, setting, tip)
    end
    Settings.RegisterAddOnCategory(category)
end

local function OpenSettings()
    if category and Settings and Settings.OpenToCategory and pcall(Settings.OpenToCategory, category:GetID()) then return end
    Print("settings: Esc > Options > AddOns > Disenchant Odds. Type /deodds help for commands.")
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    if type(DisenchantOddsDB) ~= "table" then DisenchantOddsDB = {} end
    for k, v in pairs(ns.defaults) do
        if DisenchantOddsDB[k] == nil then DisenchantOddsDB[k] = v end
    end
    ns.db = DisenchantOddsDB
    HookTooltips()
    local ok, err = pcall(RegisterSettings)
    if not ok then Print("couldn't add the settings page:", tostring(err)) end
end)

SLASH_DISENCHANTODDS1 = "/deodds"
SLASH_DISENCHANTODDS2 = "/disenchantodds"
SlashCmdList.DISENCHANTODDS = function(input)
    local cmd = (input or ""):match("^%s*(%S*)"):lower()
    if cmd == "" or cmd == "settings" or cmd == "options" then
        OpenSettings()
    elseif cmd == "on" or cmd == "off" then
        ns.db.enabled = (cmd == "on")
        Print(ns.db.enabled and "showing disenchant results in tooltips." or "disenchant results hidden.")
    elseif cmd == "skill" then
        local skill = MyEnchanting()
        Print(skill and ("your Enchanting skill: " .. skill) or "this character doesn't know Enchanting.")
    else
        Print("commands:")
        print("  /deodds - settings")
        print("  /deodds on | off - show or hide the tooltip lines")
        print("  /deodds skill - show your Enchanting skill")
    end
end
