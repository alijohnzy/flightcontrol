# Changelog

## 1.0.4

Description only — the addon itself is unchanged from 1.0.2.

- Screenshot of the options window added at the top of the description.
- `/fcon ui` is now mentioned in the opening line, so it is clear how to start.

## 1.0.3

Documentation and metadata only — the addon itself is unchanged from 1.0.2.

- The description now explains the three cases you can actually be in: the key already does
  the flight command, the flight command lives on another key, or it isn't bound at all.
- Category corrected to Miscellaneous. It was listed as Action Bars, which the addon has
  nothing to do with.

## 1.0.2

- **Fixed: the options window swallowed the keyboard.** Clicking a key row put it into
  capture mode and nothing guaranteed capture ever ended, so you could not move with the
  window open — and every movement key you pressed was silently written into the layout
  instead. Capture now releases on Escape, on closing the window, and after six seconds, and
  a key arriving at any other row is handed straight back to the game.
- Assigning a key that another row already holds now says so, instead of quietly leaving
  that row blank.
- If nothing holds the command being moved onto a key, the displaced one now simply has no
  key while flying rather than being given an invented one. It returns on landing.
- The options window no longer describes a layout set with its own checkbox as "pinned by
  /fcon layout".

## 1.0.1

Packaging only — the addon itself is unchanged from 1.0.0.

- Adds the Wago project ID and website to the addon metadata, so addon managers can match
  the installed copy to its project page.
- The release now uploads to Wago Addons automatically.

## 1.0.0

First release.

- While flying, the movement cluster becomes pitch on the vertical axis and turn on the
  horizontal. Reverts on landing.
- The cluster is derived from your own keybindings, not assumed to be WASD — QWERTY, AZERTY
  and QWERTZ layouts are all found automatically, and keys that already do the right thing
  are left alone.
- Options window (`/fcon ui`) for pinning the layout by hand, with a live preview of what
  will change.
- Inverted pitch option, for a forward key that dives rather than climbs.
- Uses the override-binding layer, so your saved keybindings are never modified.
- A key held while the state changes keeps its old function until released, so movement is
  never left stuck on.
