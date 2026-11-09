-- Settings page in the game's own Options window (Esc > Options > AddOns > Reagent Scout).
-- Built with Blizzard's addon settings API, so it looks like every other options page.
local ADDON, ns = ...

local O = {}
ns.Options = O

-- key, kind, default, label, tooltip [, min, max, step]
O.list = {
    { "inline", "boolean", true, "Show price and place under reagents",
        "Adds a small line under each reagent in the profession window with its price and the zone of the nearest vendor." },
    { "colorDistance", "boolean", true, "Color the zone by distance",
        "Green: under 300 yards. Yellow: under 1,500 yards. Gray: farther away or on another continent." },
    { "otherFaction", "boolean", false, "Include vendors of the other faction",
        "Also list vendors that are only friendly to the other faction." },
    { "tooltipZones", "number", 3, "Zones shown when hovering",
        "How many zones the hover tooltip lists, nearest first.", 1, 6, 1 },
    { "tooltipVendors", "number", 3, "Vendors per zone when hovering",
        "How many vendors the hover tooltip lists in each zone, nearest first.", 1, 6, 1 },
}

-- Fill in anything missing, so the addon works even if the settings page can't be built.
function O.ApplyDefaults(db)
    for _, o in ipairs(O.list) do
        if db[o[1]] == nil then db[o[1]] = o[3] end
    end
end

local category

local function Register()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
        return false, "this client has no addon settings API"
    end
    category = Settings.RegisterVerticalLayoutCategory(ns.name)
    for _, o in ipairs(O.list) do
        local key, kind, default, label, tip, min, max, step = unpack(o)
        local setting = Settings.RegisterAddOnSetting(category, "ReagentScout_" .. key, key, ns.db, kind, label, default)
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
    Settings.RegisterAddOnCategory(category)
    return true
end

function O.Open()
    if category and Settings and Settings.OpenToCategory then
        local ok = pcall(Settings.OpenToCategory, category:GetID())
        if ok then return end
    end
    ns.Print("the settings page isn't available here. Use /rscout help for commands.")
end

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON or not ns.db then return end
    O.ApplyDefaults(ns.db)
    local ok, registered, why = pcall(Register)
    if not (ok and registered) then
        category = nil
        ns.Print("|cffffcc00couldn't add the settings page:|r", tostring(ok and why or registered))
    end
end)
