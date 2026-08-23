# 02 — Get a testable addon into the client

Type: task
Status: resolved
Blocked by: 01

## Question

Manual work, not a decision: produce an addon that exercises both candidate mechanisms and
reports what the game actually says, and get it loading in the live client so the in-game
tickets can be worked.

## Answer

Built `FlightControl` v0.1.0 at
`/home/can/Documents/frw/lua/flightcontrol/FlightControl`, symlinked to
`.../World of Warcraft/_retail_/Interface/AddOns/FlightControl` — matching the existing
convention in that folder (`ThisWeeksAuras`, `NameplateSCT` are symlinked the same way).

Facts later tickets depend on:

- Client build **12.1.0.69404**, so the TOC declares `## Interface: 120100`.
- `wow-ui-source` was pulled to the same build, so source greps match the running client.
- SavedVariables table is `FlightControlDB`.
- Both mechanisms ship side by side, switchable at runtime without a reload:
  - `/fcon mode secure` (default) — `SecureHandlerStateTemplate` + `RegisterStateDriver`,
    conditional configurable via `/fcon cond`, default `[bonusbar:5]`.
  - `/fcon mode event` — `PLAYER_CAN_GLIDE_CHANGED` + `SetOverrideBinding`, with a
    `PLAYER_REGEN_ENABLED` retry for flips that land during combat.
- `/fcon probe` prints `GetGlidingInfo`, mount/flight state, bonus-bar indices, and which of
  ten candidate macro conditionals currently evaluate true.
- The keys swapped are read from `GetBindingKey("TURNLEFT"/"TURNRIGHT")` rather than
  hardcoded, so an ESDF or arrow-key player is handled. `/fcon keys A D` forces them.
  Re-reading is suppressed while overrides are live, because `GetBindingKey` reflects the
  override layer and would otherwise report `STRAFELEFT`'s key and lose the original.
