# 07 — What should the flight layout be, and how is it derived?

Type: grilling
Status: resolved

## Question

The original framing assumed the feature was "A/D turn becomes A/D strafe". The user's
keybinding panel showed that assumption was wrong for them, and the real complaint was
different. Establish what the swap actually is, and how it is decided.

## Answer

### The real problem

The user's bindings already had `A`/`D` on Strafe Left/Right. What was on modifiers was
**Turn** (`SHIFT-A`/`SHIFT-D`) and **Pitch** (`SHIFT-W`/`SHIFT-S`). The failure that
motivated the whole effort: holding `SHIFT` to pitch changes what `A`/`D` do, so pitching
and strafing at the same time is impossible. It is a modifier collision, not a turn/strafe
preference.

### The scheme

While flying, the movement cluster becomes **pitch on the vertical axis, turn on the
horizontal axis** — you are already gliding forward, so forward/back is the axis that can
be spent, and *turn* is what steers a mount. Strafe was the initial (wrong) choice here:
strafe only drifts you sideways without changing heading, so it is useless for navigating.
The action displaced from each key moves onto the **least accessible** key already holding
the action taking its place — the modified one — so alternates like the arrow keys keep
working. For the user's bindings:

```
W       MOVEFORWARD   <->  SHIFT-W  PITCHUP
S       MOVEBACKWARD  <->  SHIFT-S  PITCHDOWN
A       STRAFELEFT    <->  SHIFT-A  TURNLEFT
D       STRAFERIGHT   <->  SHIFT-D  TURNRIGHT
LEFT / RIGHT arrows        keep TURNLEFT / TURNRIGHT -- untouched
```

Giving the displaced action to *every* key holding the wanted action was the first
implementation, and it clobbered the arrow keys. One target only, lowest-scoring.

### Derivation, not assumption

The cluster is **learned from the player's own bindings** rather than hardcoded to WASD:

1. The forward and backward keys are whichever keys hold `MOVEFORWARD` / `MOVEBACKWARD`,
   preferring unmodified single characters over arrows, mouse buttons and modified keys.
2. The left and right keys are the **physical neighbours of the backward key**, found by
   locating it in a set of keyboard rows (QWERTY, AZERTY, QWERTZ) and taking the row that
   explains the most of the player's existing left/right movement bindings.
3. Adjacency is only trusted when **both** neighbours already hold a left/right movement
   command; otherwise it falls back to scoring.

Step 2 exists because scoring alone gets it wrong: a Legacy-style player with `A`=TURNLEFT
and `Q`=STRAFELEFT has both on plain letters, and the scoring pass picked `Q` — the key
their hand is not on. Adjacency to the backward key fixes it and, as a free consequence,
finds `ZQSD` on AZERTY without being told the layout.

Any key already holding the action the layout wants is **skipped entirely** — no swap, no
churn. For the user's own setup that means `A` and `D` are never touched.

### Verified headless

Run against stubbed bindings for five setups (the user's own, Legacy `A`=turn,
ESDF, AZERTY `ZQSD`, and a setup with pitch unbound). All five derive the correct cluster.
Note the Legacy player already has turn on `A`/`D`, so for them only the pitch axis swaps.
The last one exposed a further edge: when nothing currently holds `PITCHUP`, the key taken
for it has nowhere to hand `MOVEFORWARD` back to, and the action is left with no key at
all. That is now reported by `/fcon status` and `/fcon layout` as a warning rather than done
silently.

### Rejected: C_KeyBindings.SetTurnStrafeStyle

12.x added `C_KeyBindings.GetTurnStrafeStyle()` / `SetTurnStrafeStyle()` with
`Enum.TurnStrafeStyle = { Modern, Legacy, Custom }` — Modern being A/D strafe, Legacy being
A/D turn. Tempting as a one-call swap, but `Blizzard_RPE_TurnStrafe.lua:67` shows it is a
one-time onboarding choice that calls `SaveBindings(GetCurrentBindingSet())` immediately —
it **rewrites the real binding set**. Worse, the API documents "Can only set to Modern or
Legacy", so a player on `Custom` (which the user is) could never be restored. Unusable for
a per-state toggle. `GetTurnStrafeStyle()` is still worth reading, and is in `/fcon probe`.


## Addendum — custom layout mode

Deriving is right by default but wrong to force, so the layout is now editable by hand
through `/fcon ui` (`FlightControlUI.lua`).

- Two modes, mirroring the core: **learn** (derived; rows read-only) and **custom** (the
  player assigns each flight action a key). Ticking "Work it out from my keybindings" drops
  back to derived and discards the pinned layout.
- Rows are the four flight actions — Pitch Up/Down, Turn Left/Right. Each shows the assigned
  key *and what that key does on the ground*, so the trade is visible before it is made.
- Assigning a key another flight action already holds **steals** it, dropping the other
  action from the layout rather than silently double-binding. The UI then shows that row as
  "not set".
- The panel previews the resulting plan and reproduces the stranded-action warning, so a
  layout that would leave Move Forward with no key is visible before flying.
- Key capture goes through Blizzard's own `GetConvertedKeyOrButton`,
  `IsKeyPressIgnoredForBinding` and `CreateKeyChordStringUsingMetaKeyState` rather than
  hand-rolled modifier composition, so chords come out in the same canonical form the
  binding system uses. `UICheckButtonTemplate`'s `.text` alias and every other template used
  were checked against the 12.1 source rather than assumed.

Verified headless: derive → pin PITCHUP to R → steal R for TURNLEFT → clear TURNRIGHT →
back to derived, with the plan recomputed correctly at each step.


## Addendum — inverted pitch

Flight-sim players expect the forward key to *dive*, not climb. `invertPitch` swaps which
pitch action lands on the forward and backward keys. `/fcon invert`, or the checkbox in
`/fcon ui`.

It is a **derivation** setting, not a transform applied on top of the layout. A pinned
custom layout already states outright which key does which, so there is nothing left for
inversion to flip — the checkbox is disabled in custom mode and `/fcon invert` says so rather
than pretending to work.

One consequence worth knowing: the exchange rule sends each displaced action to the key that
held its replacement, so under inversion the displaced forward/backward actions cross over
(`SHIFT-S` gets `MOVEFORWARD`, `SHIFT-W` gets `MOVEBACKWARD`). Keeping them "near home"
instead would look tidier here, but the exchange rule is what guarantees nothing is ever
lost in configurations that aren't this symmetrical, so it stands. It is listed in the
`/fcon ui` preview, and anyone who wants it otherwise can pin a custom layout.

Verified headless: normal -> inverted -> normal round-trips exactly, the turn axis is
unaffected, and inverting while pinned is correctly a no-op.


## Addendum — handing over held keys

Reported in-game: take off holding W and the character keeps running after landing, and any
key can stick the same way.

Cause: movement bindings are `runOnUp="true"` (`Bindings_Standard.xml`), so the key-up runs
whatever the key is bound to at that moment. Rebinding mid-press means the old action's
`Stop` never runs. The stuck state then survives the whole flight and only becomes visible
after landing, when the key is bound back to movement.

Rejected first attempt: defer rebinding a held key until it is released. Safe, and needs no
protected calls, but wrong — the key should mean whatever the current state says, straight
away. The user was explicit about this.

Implemented instead, on every transition:

1. **Stop the outgoing command on every changed key**, held or not. A command already stuck
   from an earlier transition has no other chance to be cleared.
2. **Start the incoming command on keys that are down**, so a held key changes function
   under the finger.

Two details the tests forced out, both of which produced a self-cancelling no-op first time:

- **Two passes, stops before starts.** `W` and `SHIFT-W` trade `MOVEFORWARD` and `PITCHUP`,
  so stopping one key's outgoing command in a single interleaved pass killed the command the
  other key had just started.
- **Chords match modifiers exactly.** `IsKeyDown` takes a bare key, so testing the base key
  alone reported `SHIFT-W` as held whenever `W` was down, and the hand-over acted on both
  halves of the swap pair.

`plan` entries now carry `from` — what the key does with the layout off — recorded at build
time while nothing of ours is applied, so both sides of the hand-over are known in every
mode including secure, where the rebinding happens inside the snippet.

### Settled in-game: the movement functions are protected

The hand-over above **does not work** and has been removed. Calling `MoveForwardStop` /
`PitchUpStart` raised:

```
[ADDON_ACTION_FORBIDDEN] AddOn 'FlightControl' tried to call the protected function
[C]: in function 'pcall'   <-- pcall does not suppress it
```

Blizzard calling `MoveForwardStop()` from `DestinyFrame_OnEvent` was misleading: their code
runs untainted. Beyond failing, each attempt taints the addon, so there is no "try it and
fall back" option — the calls had to go entirely.

**Deferral is therefore the only available mechanism**, and is what ships: never rebind a
key that is currently down, wait for the release. The release delivers the key-up to the old
binding, which stops the old command properly. Keys not being held swap immediately.

This forces `event` to be the default mode. The secure state driver runs its snippet the
moment the conditional flips and cannot wait for a release, so it sticks movement on
essentially every take-off. Existing profiles are migrated (schema 3). `secure` remains
available for combat coverage with that caveat stated on selection.

`/fcon unstick` has been removed — it called the same protected functions and could never
have worked.

The same root cause explains the second report, camera continuing to turn after landing:
`TURNLEFT`/`TURNRIGHT` stuck exactly as `MOVEFORWARD` was.


## Addendum — stale deferred closures

Found while checking a fresh in-game report against the deferral code (the report itself was
from the previous build — the hand-over version — but the trace led here anyway).

`ApplyEventBindings` built its target set from the plan when turning **on**, but only from
`appliedKeys` when turning **off**. A key held through take-off never reaches `appliedKeys`,
because its closure had not run yet — so on landing it was absent from the targets, its
pending "apply the flight layout" closure survived untouched, and releasing the key **on the
ground** applied the flight layout there.

Fix: every plan key goes into the target set on both transitions, so a pending closure is
always replaced by the current one rather than left behind.

Swap mode now defers per key on the same machinery, with an early return when there is
nothing to put back — otherwise the other modes' routine `ApplySwapBindings(false)` calls
queued a no-op closure per held key and kept the watcher running forever.

Covered by a regression test: hold W, take off, land still holding W, release on the ground
-> no overrides. Release in the air instead -> `W=PITCHUP` applies.
