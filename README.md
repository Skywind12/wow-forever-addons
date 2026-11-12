# WoW Forever Addons

Addons I made for the **WoW Forever** client (interface 16001).

| Addon | What it does |
|---|---|
| [Reagent Scout](#reagent-scout) | Vendor price and nearest vendor for each reagent, in the profession window |
| [DamageBot](#damagebot) | HealBot-style bars for enemies you're fighting, with your DoTs on them |
| [Disenchant Odds](#disenchant-odds) | Disenchant results and chances in item tooltips |
| [Death Reason](#death-reason) | When you die: your last 10 hits, who hit you and with what |

## Install

1. **Code > Download ZIP**, then unzip.
2. Copy the addon folders into `World of Warcraft\_forever_\Interface\AddOns\`.
3. Restart the game.

---

## Reagent Scout

Under each vendor-bought reagent in the profession window: its price and the zone of the
nearest vendor (green = close, yellow = medium, gray = far). Hover for more vendors, click to
set a waypoint. `/rscout` for settings.

## DamageBot

A bar for each enemy in combat with you, with name, health and your DoT icons in the corner.
Hover a bar and press a spell key to cast on that enemy. `/dbot` for settings, `/dbot test` to place the bars.

![DamageBot bars](screenshots/damagebot-bars.png)

![DamageBot click casting settings](screenshots/damagebot-click-casting.png)

## Disenchant Odds

Hover a green, blue or purple weapon or armor to see what it disenchants into, the chance of
each result, the Enchanting skill needed and (with Auctionator) the average value. `/deodds` for settings.

```
Disenchants into:              Enchanting 150
  1-2x Dream Dust                         75%
  1-2x Greater Nether Essence             20%
  1x Large Radiant Shard                   5%
```

## Death Reason

When you die, a window lists the hits you took (10 by default), killing blow at the top: time
before death, spell, attacker, damage and your health after each hit. It closes when you release
your spirit. `/dreason` shows your last deaths, `/dreason test` a sample, `/dreason settings` for size
and options. Attackers come from the game's death recap; older hits it doesn't cover show as "attacker unknown".

---

## Other addons I use

- [Angleur](https://www.curseforge.com/projects/893895)
- [AtlasLoot Forever](https://www.curseforge.com/projects/1422985)
- [Attune](https://warcraftratings.com)
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator)
- [Better Forever Chat](https://www.curseforge.com/wow/addons/better-forever-chat)
- [BtWQuests](https://www.curseforge.com/projects/280369)
- [BugSack](https://github.com/funkydude/BugSack)
- [Cinematic](https://www.curseforge.com/projects/1730730)
- CraftCost
- [Details! Damage Meter](https://www.curseforge.com/projects/61284)
- [Forever Dungeon Journal](https://www.curseforge.com/wow/search?search=forever%20dungeon%20journal)
- [Forever Loot Sparkles](https://www.curseforge.com/wow/addons/forever-loot-sparkles)
- [Forever Quest Tint](https://www.curseforge.com/wow/search?search=forever%20quest%20tint)
- [HealBot](https://www.wowinterface.com/downloads/info6096-HealBotContinued.html)
- [Leatrix Plus](https://www.curseforge.com/projects/94855)
- [Questie](https://www.curseforge.com/wow/addons/questie)
- [QuestieDB](https://github.com/Questie/QuestieDB)
- [QuestieTrace](https://www.curseforge.com/projects/1695789)
- [RareScanner](https://www.curseforge.com/wow/addons/rarescanner)
- [Shortest Path Forever](https://github.com/cjber/shortest-path-forever)
- [Spoken](https://www.curseforge.com/wow/search?search=spoken)
- [Syndicator](https://www.curseforge.com/wow/addons/syndicator)
- [TomTom](https://www.curseforge.com/projects/18808)
- [What's Training?](https://www.curseforge.com/projects/324944)

## License

GPLv3 (see [LICENSE](LICENSE)). Reagent Scout's vendor data comes from
[QuestieDB](https://github.com/Questie/QuestieDB), which is GPLv3.
