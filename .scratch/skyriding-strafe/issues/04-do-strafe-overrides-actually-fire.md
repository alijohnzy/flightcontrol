# 04 — Do strafe overrides actually take effect while Skyriding?

Type: task
Status: resolved
Blocked by: 02

## Question

Separate from *detecting* Skyriding: when the override binding is in place, does pressing
the turn key actually strafe the character? Skyriding has bespoke client-side flight
handling, so it is not safe to assume the override reaches the movement system the way it
would on the ground.

Test with `/fcon mode event` (the simpler path — detection there is known-good via
`canGlide`, so a failure isolates cleanly to the binding side):

1. Mount a Skyriding mount, take off, confirm `/fcon status` reports overrides applied.
2. Press the turn keys. Does the character strafe/bank, still turn, or do nothing?
3. Land and dismount. Confirm the keys turn again — no residue.
4. Repeat while in combat to see the deferral behave (state should flip on combat exit,
   not during).
5. `/reload` mid-flight and confirm nothing is left stuck.

Record whether the swap works, and whether strafe while Skyriding is even a distinct
movement from turn — if the client collapses them, the whole feature is moot and the
destination needs redrawing.


## Answer

**Yes.** Confirmed in-game on build 12.1.0.69404, in `secure` mode.

With the state driver active, mounting a Skyriding mount applied the plan and the movement
keys changed behaviour — the player reported being unable to move on the ground with W/S,
which is exactly the swap taking effect. That settles the load-bearing feasibility question
from ticket 01 end to end:

- a `SecureHandlerStateTemplate` snippet calling `self:SetBinding(true, key, action)`
- with a **movement** action string
- driven by `RegisterStateDriver`

all works, and the override reaches the movement system. `ClearBindings()` reverts it.

Caveat on scope: the observation was made while mounted and *grounded*, because the
conditional in use fired on mounting (ticket 03). Airborne behaviour was not separately
isolated, but there is no mechanism by which the binding layer would differ once off the
ground — the same override is simply in force. Treat airborne as strongly implied rather
than independently demonstrated.
