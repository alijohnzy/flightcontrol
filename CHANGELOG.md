# Changelog

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
