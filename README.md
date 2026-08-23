# FlightControl

**While you're flying, your movement keys become flight controls. When you land, they go
back.**

![The FlightControl options window: the keys it worked out from the player's own bindings, and a preview of exactly what changes in the air](https://raw.githubusercontent.com/alijohnzy/flightcontrol/main/assets/screenshot.png)

## The problem it solves

Skyriding needs pitch, and your fingers are already on the movement keys. So most people put
pitch on `SHIFT-W` / `SHIFT-S` — and then hit this: holding `SHIFT` to pitch changes what
`A` and `D` do, because `SHIFT-A` is bound to turn. You can't pitch and steer at once.

## What it does

While you're airborne, your movement cluster becomes the flight cluster. Land, and it all
goes back:

| key | on the ground | while flying |
| --- | --- | --- |
| `W` | Move Forward | **Pitch Up** |
| `S` | Move Backward | **Pitch Down** |
| `A` | Strafe Left | **Turn Left** |
| `D` | Strafe Right | **Turn Right** |

## What happens to the command that was there

That depends on your own keybindings, and there are only three cases. Taking `A` as the
example — the same applies to every key in the cluster:

| your setup | while flying |
| --- | --- |
| `A` **already does Turn Left** | nothing happens. The key is skipped entirely. |
| **Turn Left is on some other key** | a straight swap: `A` does Turn Left, and that other key does Strafe Left. Nothing is lost. |
| **Turn Left isn't bound anywhere** | `A` does Turn Left, and Strafe Left has no key until you land. |

In the second case, the command you displaced goes to whichever key was holding the one that
replaced it — so if your Turn Left sits on `SHIFT-A`, that's where Strafe Left goes; if it
sits on your left arrow key, it goes there instead.

In the third case nothing is invented and no other binding is taken to make room. You get
the flight command you need, and the one it displaced comes back the moment you land.

Run `/fcon layout` to see which of these applies to you.

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
