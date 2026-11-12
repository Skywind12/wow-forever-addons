# Death Reason (WoW Forever)

When you die, a window shows the last 10 hits you took, killing blow at the top: how long
before death, the spell, **who hit you**, the damage (with overkill, absorbed, blocked,
critical) and your health after each hit. Chat also gets one line saying what killed you.

- `/dreason` shows your last death; the arrows browse older ones (the last 10 are remembered).
- `/dreason test` shows a sample, `/dreason settings` opens the settings.
- The window closes when you release your spirit. Its size can be changed in the settings (Window size).

Forever blocks the combat log for addons, so the hits come from the game's own death recap,
which has the attacker and spell. If the recap holds fewer hits than you want, Death Reason
adds older hits it recorded itself, marked "attacker unknown" (the game doesn't say who
dealt those).
