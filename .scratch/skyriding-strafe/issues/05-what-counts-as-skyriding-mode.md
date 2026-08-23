# 05 — What exactly counts as "Skyriding mode"?

Type: grilling
Status: open
Blocked by: 03

## Question

HITL. `canGlide` and `isGliding` are different states, and the probe will show whether the
conditionals draw the line somewhere else again. Pin the intended semantics:

- Should the swap engage the moment you **mount** a Skyriding mount, or only once
  **airborne**? Mounted-and-grounded is a real state with a real answer.
- What should happen while **hovering with no vigor**, or during the fall after being
  dismounted mid-air?
- Steady flight on the same mount — the player can toggle flight styles. Off, presumably,
  but confirm.
- *(moved to ticket 07 — the layout question is answered; only the trigger boundary
  below is still open.)*
- Should the swap be suppressed in any context — while a race is active, in instances,
  while a text field has focus?
