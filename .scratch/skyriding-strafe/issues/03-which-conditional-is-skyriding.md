# 03 — Which signal is true exactly while Skyriding?

Type: task
Status: open
Blocked by: 01, 02

## Question

Ticket 01 established that the combat-safe mechanism needs a **macro conditional** that is
true while Skyriding and false otherwise, and that this cannot be determined by reading the
source. Determine it by observation.

Run `/fcon probe` in each of these states and record the full output:

1. On foot, unmounted, in a Skyriding-capable zone.
2. On a ground mount.
3. Mounted on a Skyriding mount, **standing on the ground**.
4. Mounted on a Skyriding mount, **airborne and gliding**.
5. Mounted on a Skyriding mount, **airborne, hovering with no vigor**.
6. On a flying mount in **steady flight** mode (not Skyriding).
7. In a zone where Skyriding is unavailable, on a flying mount.
8. Inside a vehicle, and in a druid travel form if convenient — these share the
   bonus/override bar machinery and are the most likely false positives.

The answer is the conditional (or combination) that is true in 3–5 and false everywhere
else, plus a note on whether `[bonusbar:5]` in particular holds up. If no conditional
separates Skyriding from steady flight, say so — that outcome forces ticket 06.


## Answer (partial)

**`[bonusbar:5]` is a *mount* test, not a *flight* test.** Confirmed in-game: it goes true
the moment a Skyriding mount is summoned and stays true while standing still on the ground,
so the swap engaged before take-off and the player lost normal ground movement. It does
identify the Skyriding bar correctly — it is just answering "am I on a Skyriding mount",
not "am I flying".

The same distinction exists on the API side and was already visible in the source:

| signal | meaning |
| --- | --- |
| `canGlide` / `PLAYER_CAN_GLIDE_CHANGED` | could glide if you took off — true while grounded |
| `isGliding` / `PLAYER_IS_GLIDING_CHANGED` | actually airborne |
| `[bonusbar:5]` | on a Skyriding mount, grounded or not |

The addon now defaults to **`[flying,bonusbar:5]`** for the secure path — airborne *and* on
a Skyriding mount — and `event` mode now follows `isGliding` rather than `canGlide`.
Existing saved settings are migrated off the old value automatically.

### Still open

Whether **`[flying]` is a conditional this client accepts** has not been demonstrated. It is
in the `/fcon probe` candidate list; running probe while airborne will confirm it, and
`/fcon cond flying` / `/fcon cond mounted` switch between the alternatives if it is not.
The eight-state sweep in the question above is still worth completing — vehicles and druid
travel form in particular remain unchecked as false positives.
