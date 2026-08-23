# 06 — Combat policy, and the fallback if the secure path fails

Type: grilling
Status: open
Blocked by: 03, 04

## Question

HITL, and only answerable once 03 says whether a Skyriding conditional exists and 04 says
whether the overrides bite.

- If **no conditional isolates Skyriding**: is a combat-blind `event` mode acceptable? The
  failure it produces is "you entered combat mid-flight and your keys are stuck in the
  wrong mode until combat ends" — decide whether that is worse than not having the feature.
- If a conditional **does** exist but is approximate (fires for vehicles or travel form
  too): do we accept the false positives, or gate the secure driver behind an additional
  insecure check that can only run out of combat?
- Is there an acceptable **panic key** — a manual toggle for when the state machine is
  wrong — and should it be secure too?
- Should the addon announce state changes at all, or stay silent once trusted?
