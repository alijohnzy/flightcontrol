# Skyriding strafe swap

Label: `wayfinder:map`

## Destination

A **FlightControl** addon, installed and proven in-game, that turns the player's movement
cluster into a flight layout — pitch on the vertical axis, turn on the horizontal — for
exactly as long as they are in Skyriding mode, and restores it cleanly afterwards — with its detection mechanism and its combat behaviour locked by
in-game evidence rather than guesswork.

## Notes

- **Domain**: World of Warcraft retail addon (Lua), live build `12.1.0.69404`, Interface `120100`.
- **Execution is in scope for this map.** The user asked for a testable artifact, not just
  a plan, so tickets may build and install code. Decisions still get recorded as answers.
- **Reference source**: `/home/can/Documents/frw/wow-ui-source` (branch `live`, kept at the
  same build as the client). Grep this before trusting any remembered API.
- **Addon source**: `/home/can/Documents/frw/lua/flightcontrol/FlightControl`,
  symlinked into the client's `Interface/AddOns`.
- Skills to consult: `/grilling` and `/domain-modeling` for the grilling tickets.
- **Standing preference**: never write the player's saved bindings. Use the
  override-binding layer only, so anything we do reverts on its own.

## Decisions so far

- [01 — Can an addon rebind movement keys, and can it do so in combat?](issues/01-can-we-rebind-movement-keys.md) —
  Yes. `SetOverrideBinding` works out of combat; the secure restricted environment exposes
  `HANDLE:SetBinding(priority, key, action)` with **no filter on the action string**, so a
  state-driver snippet can bind `STRAFELEFT`/`STRAFERIGHT` even in combat. The load-bearing
  unknown moves to *which macro conditional identifies Skyriding*.
- [02 — Get a testable addon into the client](issues/02-install-and-symlink.md) —
  `FlightControl` v0.1.0 built with both mechanisms selectable (`/fcon mode secure|event`)
  plus a `/fcon probe` readout; symlinked into the retail AddOns folder.

- [07 — What should the flight layout be, and how is it derived?](issues/07-flight-layout-and-derivation.md) —
  The swap is pitch onto the vertical axis and **turn** onto the horizontal (strafe only
  drifts sideways; turn is what steers), with each displaced action exchanged onto the least
  accessible key that held its replacement, so arrow-key alternates survive. The cluster is **learned** from the
  player's bindings via keyboard adjacency to the backward key, not hardcoded to WASD; keys
  already holding the wanted action are skipped. `SetTurnStrafeStyle` rejected — it rewrites
  the real binding set and cannot restore `Custom`. Addendum: the layout is also editable by
  hand via `/fcon ui`, with a live preview of what will change.

- [04 — Do strafe overrides actually take effect while Skyriding?](issues/04-do-strafe-overrides-actually-fire.md) —
  **Yes.** A secure snippet binding a movement action through `RegisterStateDriver` reaches
  the movement system, confirmed in-game. The mechanism from ticket 01 works end to end.
- [03 — Which signal is true exactly while Skyriding?](issues/03-which-conditional-is-skyriding.md) —
  *Partial.* `[bonusbar:5]` fires on **mounting**, not take-off. Default moved to
  `[flying,bonusbar:5]`, and event mode from `canGlide` to `isGliding`. Whether `[flying]`
  is accepted by this client is still unconfirmed.
- **Login-time binding race** — `UPDATE_BINDINGS` fires repeatedly during login with a
  half-loaded set, producing wrong plans (`MOVEFORWARD` handed to `INSERT`). The first plan
  is now gated on `PLAYER_ENTERING_WORLD` + `VARIABLES_LOADED` + `BINDINGS_LOADED`, the same
  three events Blizzard's own binding code waits for. **That gate must be registered at file
  scope**: `EventUtil.ContinueAfterAllEvents` only counts events arriving after the call
  (`EventUtil.lua:5`), and two of the three fire before `PLAYER_LOGIN` — registering from a
  login handler waits forever and the addon never initialises at all.
- **Airborne trigger confirmed working in-game** — `[flying,bonusbar:5]` fires on take-off
  and clears on landing, with normal ground movement preserved while mounted.

## Not yet specified

- **Whether the trigger should be Skyriding or all flight.** Pitch matters in steady flight
  too. `/fcon cond [flying]` covers both today, but which is the default is undecided.
- **Config surface.** `/fcon ui` covers the layout. Whether the rest (mode, conditional)
  deserves UI, and whether profiles are per-character, hangs on what survives in-game testing.
- **Coexistence with binding-owning addons.** Bartender/ElvUI and friends also call
  `SetOverrideBinding`. Priority collisions and load-order effects are only worth charting
  once we know which mechanism we're keeping.
- **Steady-flight toggle mid-flight.** The player can switch flight styles without landing.
  Whether that produces a clean state transition depends on which signal we end up using.
- **Distribution.** Packaging (`.pkgmeta`, CurseForge/WoWI) only matters if this stops being
  a personal addon.

## Out of scope

- Non-mainline flavours (Classic, Plunderstorm). Skyriding does not exist there.
- Rebinding anything outside the movement cluster — camera keys, ascend/descend,
  Skyriding abilities. The destination is the flight-layout swap on the cluster.
