# Reagent Scout (WoW Forever)

Open a profession and select a recipe. Under each reagent you can buy from a vendor, a
small line shows its price and the zone of the nearest vendor, for example
`35c - Elwynn Forest`. The zone is green when the vendor is close (under 300 yards),
yellow when it's within 1,500 yards, and gray when it's farther.

Hover the line to see the nearest vendors, grouped by zone. Click it to set a waypoint
to the nearest one (TomTom if you have it, otherwise the game's own map pin).

## Install

1. Copy the `ReagentScout` folder to
   `World of Warcraft\_forever_\Interface\AddOns\ReagentScout\`
   (the folder must contain `ReagentScout.toc` directly).
2. In game, type `/rscout status` to check that everything was found.

No other addons are needed.

## Where the data comes from

- **Vendor locations**: `Data.lua`, built in. It covers 94 vendor-sold reagents and trade
  goods and the 333 vendors that sell them. It was extracted from QuestieDB's Forever data
  set, whose vendor coordinates were converted to Forever's redrawn maps (checked against
  client build 1.60.1) and which uses Forever's own zone table. Its item list is a copy of
  Classic Era, so reagents and vendors added only in Forever aren't in it. Any vendor you
  open is remembered, which covers that gap. If you have QuestieDB installed, Reagent Scout
  uses it instead, because it is updated more often.
- **Prices**: the game doesn't expose vendor prices until you open that vendor. Each time
  you open any vendor, Reagent Scout records its prices and location. Vendors you have
  visited are marked with a blue `*`.

## Known Forever issue

The client has had a bug where addon saved data is written at logout but not loaded at
login. If `/rscout status` keeps saying "nothing loaded from a previous session", remembered
prices reset every login. Vendor locations are not affected. Community fixes: Forever Data
Protect (CurseForge) or ForeverSVFix (GitHub).

## Settings

Esc > Options > AddOns > Reagent Scout (or type `/rscout`):

- Show price and place under reagents
- Color the zone by distance
- Include vendors of the other faction
- Zones shown when hovering (1-6)
- Vendors per zone when hovering (1-6)

## Commands

- `/rscout`: opens the settings page
- `/rscout status`: shows which vendor data is in use, whether saved data loaded, and
  whether your position is readable
- `/rscout show` / `/rscout hide`: shows or hides the price-and-place lines
- `/rscout item <item link or ID>`: opens a window with every known vendor for one item
- `/rscout debug`: shows what the addon sees in the open profession window (send this if the lines don't appear)
- `/rscout reset`: forgets remembered prices and vendors

## License

`Data.lua` is extracted from [QuestieDB](https://github.com/Questie/QuestieDB), which is
licensed under the GNU General Public License v3. Because Reagent Scout ships that data,
the addon as a whole is GPLv3 too: https://www.gnu.org/licenses/gpl-3.0.html

To rebuild `Data.lua` from a newer QuestieDB, run `tools/extract.py` (see the usage line
at the top of that script).
