-- Disenchanting results for Classic-era items (Forever uses the Classic Era item list).
-- Source: warcraft.wiki.gg "Disenchanting tables" and "Disenchanting" (required skill).
local _, ns = ...

-- Materials: item ID, English name (used until the game has the real name cached), quality.
local M = {
    STRANGE = 10940, LESSER_MAGIC = 10938, GREATER_MAGIC = 10939, SMALL_GLIMMERING = 10978,
    LESSER_ASTRAL = 10998, GREATER_ASTRAL = 11082, SOUL = 11083, LARGE_GLIMMERING = 11084,
    LESSER_MYSTIC = 11134, GREATER_MYSTIC = 11135, VISION = 11137, SMALL_GLOWING = 11138,
    LARGE_GLOWING = 11139, LESSER_NETHER = 11174, GREATER_NETHER = 11175, DREAM = 11176,
    SMALL_RADIANT = 11177, LARGE_RADIANT = 11178, SMALL_BRILLIANT = 14343, LARGE_BRILLIANT = 14344,
    LESSER_ETERNAL = 16202, GREATER_ETERNAL = 16203, ILLUSION = 16204, NEXUS = 20725,
}
ns.MATS = M

ns.NAMES = {
    [M.STRANGE] = "Strange Dust", [M.LESSER_MAGIC] = "Lesser Magic Essence", [M.GREATER_MAGIC] = "Greater Magic Essence",
    [M.SMALL_GLIMMERING] = "Small Glimmering Shard", [M.LESSER_ASTRAL] = "Lesser Astral Essence",
    [M.GREATER_ASTRAL] = "Greater Astral Essence", [M.SOUL] = "Soul Dust", [M.LARGE_GLIMMERING] = "Large Glimmering Shard",
    [M.LESSER_MYSTIC] = "Lesser Mystic Essence", [M.GREATER_MYSTIC] = "Greater Mystic Essence", [M.VISION] = "Vision Dust",
    [M.SMALL_GLOWING] = "Small Glowing Shard", [M.LARGE_GLOWING] = "Large Glowing Shard",
    [M.LESSER_NETHER] = "Lesser Nether Essence", [M.GREATER_NETHER] = "Greater Nether Essence", [M.DREAM] = "Dream Dust",
    [M.SMALL_RADIANT] = "Small Radiant Shard", [M.LARGE_RADIANT] = "Large Radiant Shard",
    [M.SMALL_BRILLIANT] = "Small Brilliant Shard", [M.LARGE_BRILLIANT] = "Large Brilliant Shard",
    [M.LESSER_ETERNAL] = "Lesser Eternal Essence", [M.GREATER_ETERNAL] = "Greater Eternal Essence",
    [M.ILLUSION] = "Illusion Dust", [M.NEXUS] = "Nexus Crystal",
}

-- Quality of each material, for coloring: dusts white, essences green, shards blue, crystal purple.
ns.QUALITY = {}
for id, name in pairs(ns.NAMES) do
    ns.QUALITY[id] = (name:find("Dust") and 1) or (name:find("Essence") and 2) or (name:find("Crystal") and 4) or 3
end

-- Uncommon (green) items, by item level.
-- { low, high, dust, dustQty, essence, essenceQty, shard, armor %, weapon % }
-- The % lists are { dust, essence, shard }: armor gives mostly dust, weapons mostly essence.
local GREEN = {
    { 5, 15,  M.STRANGE,  { 1, 2 }, M.LESSER_MAGIC,    { 1, 2 }, nil,                { 80, 20, 0 },  { 20, 80, 0 } },
    { 16, 20, M.STRANGE,  { 2, 3 }, M.GREATER_MAGIC,   { 1, 2 }, M.SMALL_GLIMMERING, { 75, 20, 5 },  { 20, 75, 5 } },
    { 21, 25, M.STRANGE,  { 4, 6 }, M.LESSER_ASTRAL,   { 1, 2 }, M.SMALL_GLIMMERING, { 75, 15, 10 }, { 15, 75, 10 } },
    { 26, 30, M.SOUL,     { 1, 2 }, M.GREATER_ASTRAL,  { 1, 2 }, M.LARGE_GLIMMERING, { 75, 20, 5 },  { 20, 75, 5 } },
    { 31, 35, M.SOUL,     { 2, 5 }, M.LESSER_MYSTIC,   { 1, 2 }, M.SMALL_GLOWING,    { 75, 20, 5 },  { 20, 75, 5 } },
    { 36, 40, M.VISION,   { 1, 2 }, M.GREATER_MYSTIC,  { 1, 2 }, M.LARGE_GLOWING,    { 75, 20, 5 },  { 20, 75, 5 } },
    { 41, 45, M.VISION,   { 2, 5 }, M.LESSER_NETHER,   { 1, 2 }, M.SMALL_RADIANT,    { 75, 20, 5 },  { 20, 75, 5 } },
    { 46, 50, M.DREAM,    { 1, 2 }, M.GREATER_NETHER,  { 1, 2 }, M.LARGE_RADIANT,    { 75, 20, 5 },  { 20, 75, 5 } },
    { 51, 55, M.DREAM,    { 2, 5 }, M.LESSER_ETERNAL,  { 1, 2 }, M.SMALL_BRILLIANT,  { 75, 20, 5 },  { 22, 75, 3 } },
    { 56, 60, M.ILLUSION, { 1, 2 }, M.GREATER_ETERNAL, { 1, 2 }, M.LARGE_BRILLIANT,  { 75, 20, 5 },  { 22, 75, 3 } },
    { 61, 65, M.ILLUSION, { 2, 5 }, M.GREATER_ETERNAL, { 2, 3 }, M.LARGE_BRILLIANT,  { 75, 20, 5 },  { 22, 75, 3 } },
}

-- Rare (blue) items: one shard, plus a small Nexus Crystal chance at the top.
local BLUE = {
    { 1, 25,  M.SMALL_GLIMMERING }, { 26, 30, M.LARGE_GLIMMERING }, { 31, 35, M.SMALL_GLOWING },
    { 36, 40, M.LARGE_GLOWING },    { 41, 45, M.SMALL_RADIANT },    { 46, 50, M.LARGE_RADIANT },
    { 51, 55, M.SMALL_BRILLIANT },  { 56, 65, M.LARGE_BRILLIANT, nexus = 0.5 },
}

-- Epic (purple) items.
local PURPLE = {
    { 40, 45, M.SMALL_RADIANT, { 2, 4 } }, { 46, 50, M.LARGE_RADIANT, { 2, 4 } },
    { 51, 55, M.SMALL_BRILLIANT, { 2, 4 } }, { 56, 60, M.NEXUS, { 1, 1 } }, { 61, 100, M.NEXUS, { 1, 2 } },
}

local function Find(list, level)
    for _, row in ipairs(list) do
        if level >= row[1] and level <= row[2] then return row end
    end
end

local function Result(chance, item, qty) return { chance = chance, item = item, min = qty[1], max = qty[2] } end

-- What disenchanting gives: a list of { chance, item, min, max }, most likely first.
-- quality: 2 uncommon, 3 rare, 4 epic. isWeapon: weapons give mostly essences.
-- Returns nil when the item level is outside the known tables.
function ns.Results(quality, level, isWeapon)
    if quality == 2 then
        local r = Find(GREEN, level)
        if not r then return nil end
        local pct = isWeapon and r[9] or r[8]
        local list = { Result(pct[1], r[3], r[4]), Result(pct[2], r[5], r[6]) }
        if r[7] and pct[3] > 0 then list[#list + 1] = Result(pct[3], r[7], { 1, 1 }) end
        table.sort(list, function(a, b) return a.chance > b.chance end)
        return list
    elseif quality == 3 then
        local r = Find(BLUE, level)
        if not r then return nil end
        if r.nexus then return { Result(100 - r.nexus, r[3], { 1, 1 }), Result(r.nexus, M.NEXUS, { 1, 1 }) } end
        return { Result(100, r[3], { 1, 1 }) }
    elseif quality == 4 then
        local r = Find(PURPLE, level)
        if r then return { Result(100, r[3], r[4]) } end
        return ns.Results(3, level, isWeapon) -- low-level epics follow the rare table
    end
end

-- Enchanting skill needed to disenchant.
local SKILL = { { 20, 1 }, { 25, 25 }, { 30, 50 }, { 35, 75 }, { 40, 100 }, { 45, 125 }, { 50, 150 }, { 55, 175 }, { 60, 200 } }
function ns.RequiredSkill(quality, level)
    if quality >= 3 and level <= 25 then return 25 end
    for _, s in ipairs(SKILL) do
        if level <= s[1] then return s[2] end
    end
    return 225
end
