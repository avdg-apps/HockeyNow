# HockeyNow 2.3.1 (2.4.0 feature set, version number kept at 2.3.1; not compiled here)

New
- Notch pop-outs for your teams: goals, penalties, period ends, overtime, finals (banner opens the notch by itself; the notification opens the game page).
- Per-team alert profiles (Settings > Alerts): goals/periods/finals/game day/trades/injuries/notch per team, plus mute.
- Trade, signing and injury alerts for followed teams (Utilities/TransactionWatcher.swift).
- Picks & Fantasy tab (Cmd-7): pin players with live points, pick'em record, watch-party countdown with local time.
- Shots tab on game cards: shot map and expected goals (xG).
- Shortcuts / Siri: next game, score, team record (App/HockeyNowIntents.swift).
- Widget source in WidgetSource/ (needs a manual Xcode target, see its README).

Fixed
- Standings tiebreakers now follow the NHL rules: points, fewer games played, RW, ROW, W, head-to-head points (odd game removed), goal difference, goals for. New ROW column.
- Every loaded season is kept under its own key. My Team / Playoffs viewing an old year no longer overwrites the games that Standings, form, lineups and player stats read (this caused mixed-up lines, wrong records and constant reloading).
- Finished-game lookups are cached per team, removing a big per-render cost.

2.4.0_2 fixes
- Game card: the home team now shows score then SOG, so the score sits next to the middle on both sides (notch header matches).
- Period bar: real goals were being dropped by a text filter that matched "vis", "minor", "saved" inside player names. ESPN's scoring-play flag is now trusted.
- Notch: contents fade in after the shape starts growing, and the SOG labels grow with it instead of popping in early.

2.4.0_3
- Settings: "Notch live alerts" = Don't drop down / Small banner (default) / Full notch.
- Settings: "Skip if another game is shown" silences the live alert when the notch is on a different game.
- Small banner drops only a thin strip under the notch; the full notch is no longer opened for it.

2.4.0_4
- Notch header text is laid out in two halves either side of the physical notch (with margin), so the cut-out no longer covers it. Collapsed size is unchanged. Collapsed pill shows power play / empty net as a colour change instead of tags.

2.4.0_5
- Standings: the new ROW column made the table wider than the 560pt window, so everything looked zoomed and clipped. Column spacing tightened so it fits again.

2.4.0_6
- Notch: when you move to another day the notch kept a frozen copy of its game (e.g. still "EN" after the game ended). It now keeps refreshing the notched game even when it is not in the day list.
- Settings, favourites, fantasy pins, pick-em picks and alert profiles are also backed up to Application Support and restored if the defaults store is ever empty after an update; alert profiles tolerate fields added in future versions.
