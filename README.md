# FlightControl

**While you're flying, your movement keys become flight controls. When you land, they go back.**

A World of Warcraft addon for Skyriding.

---

## The problem

Skyriding needs pitch. Your fingers are already on the movement cluster. So most people end
up putting pitch on `SHIFT-W` / `SHIFT-S` and turn on `SHIFT-A` / `SHIFT-D` — and then hit
this:

> You hold `SHIFT` to pitch. Now `A` and `D` mean *turn* instead of *strafe*, because
> `SHIFT-A` is bound to turn. You can't pitch and steer at the same time.

Every flight control you actually need is stuck behind a modifier, fighting the keys you
need at the same time.

## What it does

FlightControl takes the modifier out of the equation. While you're airborne, the bare
movement cluster *is* the flight cluster — pitch on the vertical axis, turn on the
horizontal:

| key | on the ground | while flying |
| --- | --- | --- |
| `W` | Move Forward | **Pitch Up** |
| `S` | Move Backward | **Pitch Down** |
| `A` | Strafe Left | **Turn Left** |
| `D` | Strafe Right | **Turn Right** |

Nothing is lost. Each displaced command moves onto the key that used to hold its
replacement, so `SHIFT-W` becomes Move Forward for the duration, `SHIFT-A` becomes Strafe
Left, and so on. Land, and every one of them goes straight back.

Turn rather than strafe on `A`/`D`, because turning is what changes your heading. Strafe
just drifts you sideways, which is no use for getting anywhere.

## It learns your keybindings

There is no assumption that you use `WASD`. FlightControl reads your actual bindings:

- The forward and backward keys come from whatever holds `MOVEFORWARD` / `MOVEBACKWARD`,
  preferring unmodified single keys over arrows, mouse buttons and chords.
- The left and right keys are the **physical neighbours of your backward key**, found by
  locating it across QWERTY, AZERTY and QWERTZ rows and keeping whichever row best explains
  your existing bindings.

So an `ESDF` player gets `E/S/D/F`, and an AZERTY player gets `Z/Q/S/D` without being asked.

**Keys that already do the right thing are left alone.** If you already have Turn on `A`/`D`,
only the pitch axis changes.

Run `/fcon layout` to see exactly what it worked out, and what will change.

## Installing

Drop the `FlightControl` folder into:

```
World of Warcraft/_retail_/Interface/AddOns/
```

Then `/reload` or restart. Requires retail — Skyriding does not exist elsewhere.

## Commands

```
/fcon ui                 open the options window
/fcon layout             what it learned, and what will change while flying
/fcon status             current mode, plan, and whether the swap is live
/fcon learn              re-derive from your current keybindings

/fcon invert             forward key dives instead of climbs
/fcon layout W PITCHUP   pin one key by hand;  /fcon layout W none  leaves it alone
/fcon layout reset       go back to deriving automatically
/fcon displaced          toggle handing displaced commands to the freed keys

/fcon cond air           when to engage: air (default) | flying | mounted
/fcon mode event         event (default) | secure | swap
/fcon probe              dump every flight signal the game exposes
/fcon on | off | verbose
```

`/flightcontrol` works as a full-length alias. FlightControl warns at login if another addon
has claimed either name — slash collisions are otherwise resolved silently in favour of
whichever addon loaded last.

## Options

**Invert pitch** — `/fcon invert`, or the checkbox in `/fcon ui`. Forward key dives, back key
climbs, the way flight sims do it.

**Custom layout** — untick *"Work it out from my keybindings"* in `/fcon ui` and assign the
four flight commands yourself. Each row shows what that key currently does on the ground, so
you can see the trade before you make it. The window previews the full result and warns if a
layout would leave a command with no key at all.

**When to engage** — `/fcon cond`:

| preset | conditional | meaning |
| --- | --- | --- |
| `air` *(default)* | `[flying,bonusbar:5]` | airborne **and** on a Skyriding mount |
| `flying` | `[flying]` | airborne on anything, including steady flight |
| `mounted` | `[bonusbar:5]` | on a Skyriding mount, even standing still |

## Modes

| mode | how it swaps | trade-off |
| --- | --- | --- |
| **event** *(default)* | `PLAYER_IS_GLIDING_CHANGED` + override bindings | waits for held keys; cannot change bindings during combat |
| **secure** | secure state driver + `RegisterStateDriver` | works in combat, but rebinds instantly, so a key held through take-off sticks |
| **swap** | writes the real binding set | fallback only; not needed in practice |

## Known limitations

**A key you're holding when the state changes keeps its old function until you let go.**
Hold `W` through take-off and `W` keeps moving you forward; release it and it becomes Pitch
Up. So you press it again to start pitching.

This is not a choice. Movement bindings are `runOnUp="true"`, meaning the key-up runs
whatever the key is bound to *at that moment*. Rebinding mid-press means the old command's
stop never runs and it sticks on — take off holding `W` and you're still running after you
land. The obvious fix, stopping the old command and starting the new one, is impossible:
`MoveForwardStop`, `PitchUpStart` and the rest are **protected functions**. Calling one
raises `ADDON_ACTION_FORBIDDEN` and taints the addon, and `pcall` does not suppress it.

Waiting for the release is the only mechanism available, and it's why `event` is the default
mode — the secure state driver cannot wait for anything.

**In `event` mode, bindings cannot change during combat.** A take-off mid-combat applies when
combat ends. `/fcon mode secure` covers combat instead, at the cost above.

## Your keybindings are never modified

`event` and `secure` modes use the **override binding** layer, a temporary layer on top of
your real bindings. It's discarded on `/reload`, logout, or a disconnect. Nothing is written
to your saved bindings, so there is nothing to restore if something goes wrong.

## Compatibility

Built and tested against retail **12.1.0** (Interface `120100`).

## Licence

MIT.
