# FlightControl

**While you're flying, your movement keys become flight controls. When you land, they go
back.**

## The problem it solves

Skyriding needs pitch, and your fingers are already on the movement keys. So most people put
pitch on `SHIFT-W` / `SHIFT-S` — and then hit this: holding `SHIFT` to pitch changes what
`A` and `D` do, because `SHIFT-A` is bound to turn. You can't pitch and steer at once.

## What it does

While you're airborne, the bare movement cluster *is* the flight cluster. Every change is a
straight **exchange** — whatever gets displaced moves onto the key that used to hold its
replacement, so nothing is lost while you fly:

| key | on the ground | while flying |
| --- | --- | --- |
| `W` | Move Forward | **Pitch Up** |
| `S` | Move Backward | **Pitch Down** |
| `A` | Strafe Left | **Turn Left** |
| `D` | Strafe Right | **Turn Right** |
| `SHIFT-W` | Pitch Up | **Move Forward** |
| `SHIFT-S` | Pitch Down | **Move Backward** |
| `SHIFT-A` | Turn Left | **Strafe Left** |
| `SHIFT-D` | Turn Right | **Strafe Right** |

Land, and every one of them goes straight back.

The top half is always your movement cluster. The bottom half follows wherever *you* keep
pitch and turn — if your turn keys are the arrow keys, then strafe moves to the arrow keys
while you fly rather than to `SHIFT-A` / `SHIFT-D`.

**Keys that already do the right thing are skipped**, so if you already have Turn on `A`/`D`,
only the pitch rows change.

**If something has nowhere to go it simply has no key while you fly.** With no turn keys
bound anywhere, `A`/`D` still become Turn — and Strafe has nothing to swap with, so it goes
unbound until you land. No key is ever invented, and nothing you didn't ask for is taken.

Run `/fcon layout` to see your own version of this table, including anything that would be
left without a key.

## It fits your keybindings

There's no assumption that you use `WASD`. FlightControl reads your actual bindings and
works out where your movement cluster is — `ESDF` and AZERTY `ZQSD` are found automatically.

## Getting started

Install, log in, and it works. Nothing to configure.

To see what it worked out for you, type **`/fcon ui`**. It shows which keys it picked, what
each one currently does on the ground, and exactly what will change while you fly — before
anything happens.

In that window you can also:

- **Assign the keys yourself** — untick *"Work it out from my keybindings"*.
- **Invert pitch** so the forward key dives instead of climbing.

## Commands

```
/fcon ui         open the options window
/fcon layout     what it worked out, and what will change
/fcon status     what's active right now
/fcon invert     forward key dives instead of climbs
/fcon on | off
```

`/fcon help` lists the rest. `/flightcontrol` works as a full-length alias.

## What to expect

**A key you're already holding keeps its old job until you let go.** Hold `W` through
take-off and `W` keeps moving you forward; release it and it becomes Pitch Up. So you tap it
once more to start pitching.

This is deliberate. Swapping a key mid-press would leave the old command running with
nothing able to stop it — you'd take off holding `W` and still be running after you landed.
Waiting for the release is the only way to avoid that, because the WoW API won't let addons
cancel a movement command.

**Bindings can't change during combat.** If you take off mid-fight, the swap applies as soon
as combat ends.

## Your keybindings are never modified

FlightControl uses a temporary layer on top of your real bindings. It's discarded on
`/reload`, on logout, and on a disconnect. Nothing is written to your saved keybindings, so
there's nothing that can be left in a bad state.

## Bugs and requests

Please open an issue: **https://github.com/alijohnzy/flightcontrol/issues**

Built for retail **12.1.0**. MIT licensed.
