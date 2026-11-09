# DamageBot (WoW Forever)

HealBot-style bars, but for the enemies you're fighting. Each bar shows the enemy's name, health,
and your DoTs on it in the bottom-right corner (icon plus a timer swipe), the same way HealBot
shows your HoTs.

## Install

Copy the `DamageBot` folder to `World of Warcraft\_forever_\Interface\AddOns\`, then quit and
restart the game.

- Type `/dbot test` to see sample bars, then drag the **DamageBot** tab to place them.
- Keep **enemy nameplates on** (default key: V). DamageBot finds enemies through their nameplates.

## Two modes

**Click-casting on (default).** Click a bar to cast on that enemy. Set what each click does with
`/dbot clicks` (or Esc > Options > AddOns > DamageBot > **Click casting**): one spell (or Target /
Set focus) for left, right, middle, button 4 and button 5, each plain or with Shift, Ctrl or Alt.
Chat confirms each choice. Out of combat, the bars also appear while you target an enemy, so you
can start the fight with a click. DamageBot's clicks don't use, and aren't affected by,
Blizzard's own Click Casting settings.

The game only lets its own secure code show, hide or move clickable bars during combat, and
that code can't tell whether an enemy is in combat. So in this mode every attackable enemy near
you gets a bar, and the ones that aren't fighting you are **dimmed**.

**Click-casting off.** Display only. Only enemies fighting you (or your pet or party) are
listed, oldest first, with no gaps.

## DoT icons

In combat Forever won't let addons read debuffs at all ("Auras cannot be accessed when secret
while tainted"). Blizzard's own nameplates can, and each enemy nameplate shows a row of your
debuffs on that enemy. DamageBot moves that row onto the enemy's bar (bottom-right), and gives
it back to the nameplate when the bar goes away. If a DoT you cast doesn't show on the
nameplate, it won't show on the bar either: turn on **Show all my debuffs on nameplates**.

## Click casting and mouseover

**Mouseover cast** (on by default): hover an enemy's bar and press your normal spell key; the
spell goes to that enemy, no macros needed. This is the game's own Mouseover Cast setting
(Options > Combat), which DamageBot turns on the first time it loads; untick "Mouseover cast"
on the DamageBot page to turn it off. If Options > Combat shows a key for Mouseover Cast, hold
that key or set it to None. Macros like `/cast [@mouseover,harm,nodead] Shadow Word: Pain` also work.

Clicks set to a spell may be blocked by Forever ("Interface action failed because of an AddOn").
Click bindings are saved per character and start empty.

## What Forever hides during combat

Forever hides enemy health, debuffs and threat from addons during combat. DamageBot passes
those values straight to the game's own bars, icons and timers, which are allowed to show them.
It can't make decisions with them, so it can't, for example, warn you when a DoT is about to
expire or sort enemies by health. When the game hides whether an enemy is fighting you,
DamageBot shows it rather than risk hiding a real attacker.

## Settings

Esc > Options > AddOns > DamageBot (or `/dbot`): click-casting, only show in combat, include
enemies fighting your party, dim idle enemies, lock, health numbers, DoT countdown numbers, bar
width and height, columns, DoT icon count and size, scale.

## Commands

- `/dbot`: settings
- `/dbot test`: sample bars for placing them
- `/dbot unlock` / `/dbot lock`: show or hide the move tab
- `/dbot debug`: what DamageBot sees right now (send this if something looks wrong)
