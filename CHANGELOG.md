# Changelog

## 1.0.9

- **Fixed: flying into water while holding forward kept you in flight mode.** Forward stayed
  on pitch, which in water rotates you instead of swimming, and letting go did not help.
  A key you are holding is no longer left behind when the flight layout comes off.
- Taking off while holding forward still waits for you to let go, which is what stops you
  running on after you land. The two directions genuinely need different handling: coming
  out of flight there is nothing to protect, going in there is.
- Nothing except the game reporting an actual take-off can switch flight mode on now. It was
  previously possible for it to turn itself on from a stray reading while you were swimming.
- `/fcon hold auto|defer|instant` if you want to override any of that.

## 1.0.8

Same behaviour as 1.0.7, reached a better way.

- 1.0.7 kept the water fix working by checking several times a second for as long as you
  were flying. It now waits to be told instead: a mount vanishing, a druid leaving Flight
  Form, or the game reporting you can no longer glide. Nothing is checked on a timer while
  you fly.
- Druid Flight Form and evoker Soar are both covered explicitly. Druids are never mounted
  and evokers fly by spell, so neither can be recognised by looking for a mount.

## 1.0.7

- **Fixed: flying into water left the flight controls on.** Hitting water dismounts you
  without firing anything the addon could listen for, and the game can still report you as
  gliding afterwards. While the flight layout is applied it is now checked several times a
  second and taken off as soon as you are neither mounted nor airborne. The check only ever
  turns the layout off, never on, so it cannot switch on at an odd moment, and it stops
  running entirely once you are back on the ground.
- Druid Flight Form is handled: you glide without being mounted, so being unmounted alone is
  not treated as having landed.

## 1.0.6

- **Fixed: the flight layout stayed on after being summoned mid-flight.** The keys only
  changed back when the game reported that gliding had stopped, and that report is not made
  for every way a flight can end. Being summoned, dying, boarding a taxi, hearthing and
  zoning all put you on the ground without it, leaving WASD on pitch and turn.
  The addon now re-checks whether you are actually airborne after any of those, and puts the
  keys back if they disagree. Zoning while still genuinely flying leaves the layout alone.

## 1.0.5

Metadata only. The addon itself is unchanged from 1.0.2.

- Author and copyright are now AliJohn, matching the name the project is published under.

## 1.0.4

Description only. The addon itself is unchanged from 1.0.2.

- Screenshot of the options window added at the top of the description.
- `/fcon ui` is now mentioned in the opening line, so it is clear how to start.

## 1.0.3

Documentation and metadata only. The addon itself is unchanged from 1.0.2.

- The description now explains the three cases you can actually be in: the key already does
  the flight command, the flight command lives on another key, or it isn't bound at all.
- Category corrected to Miscellaneous. It was listed as Action Bars, which the addon has
  nothing to do with.

## 1.0.2

- **Fixed: the options window swallowed the keyboard.** Clicking a key row put it into
  capture mode and nothing guaranteed capture ever ended, so you could not move with the
  window open, and every movement key you pressed was silently written into the layout
  instead. Capture now releases on Escape, on closing the window, and after six seconds, and
  a key arriving at any other row is handed straight back to the game.
- Assigning a key that another row already holds now says so, instead of quietly leaving
  that row blank.
- If nothing holds the command being moved onto a key, the displaced one now simply has no
  key while flying rather than being given an invented one. It returns on landing.
- The options window no longer describes a layout set with its own checkbox as "pinned by
  /fcon layout".

## 1.0.1

Packaging only. The addon itself is unchanged from 1.0.0.

- Adds the Wago project ID and website to the addon metadata, so addon managers can match
  the installed copy to its project page.
- The release now uploads to Wago Addons automatically.

## 1.0.0

First release.

- While flying, the movement cluster becomes pitch on the vertical axis and turn on the
  horizontal. Reverts on landing.
- The cluster is derived from your own keybindings, not assumed to be WASD. QWERTY, AZERTY
  and QWERTZ layouts are all found automatically, and keys that already do the right thing
  are left alone.
- Options window (`/fcon ui`) for pinning the layout by hand, with a live preview of what
  will change.
- Inverted pitch option, for a forward key that dives rather than climbs.
- Uses the override-binding layer, so your saved keybindings are never modified.
- A key held while the state changes keeps its old function until released, so movement is
  never left stuck on.
