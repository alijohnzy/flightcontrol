# 01 — Can an addon rebind movement keys, and can it do so in combat?

Type: research
Status: resolved

## Question

Is it possible at all for a retail addon to rebind the turn keys to strafe on the fly?
Specifically: which API can set a binding to a movement command like `STRAFELEFT`,
does it survive combat lockdown, and does it damage the player's saved bindings?

## Answer

**Yes, and there is a combat-safe path.** Three findings, all verified against
`wow-ui-source` at build `12.1.0.69404`.

### 1. Movement commands are ordinary binding actions

`Interface/AddOns/Blizzard_FrameXML/Bindings_Standard.xml:39` defines `STRAFELEFT` /
`STRAFERIGHT` as normal `<Binding>` entries under `BINDING_HEADER_MOVEMENT`, no different
in kind from `TURNLEFT` / `TURNRIGHT`. Nothing marks them as unbindable by addons.

### 2. The secure restricted environment will bind them in combat

`Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/RestrictedFrames.lua:565` exposes:

```lua
function HANDLE:SetBinding(priority, key, action)
	if (action ~= nil and type(action) ~= "string") then
		error("Invalid binding action");
		return;
	end
	SetOverrideBinding(GetHandleFrame(self), priority, key, action);
end
```

The only check is `type(action) == "string"` — **the action string is not filtered against
a whitelist**. Contrast `HANDLE:SetBindingClick` just above it, which does validate its
target. So a `SecureHandlerStateTemplate` snippet may call
`self:SetBinding(true, "A", "STRAFELEFT")` and it will run inside combat lockdown.
`HANDLE:ClearBindings()` (line 537) maps to `ClearOverrideBindings` and undoes it.

### 3. The state driver is macro-conditional powered

`RegisterStateDriver` funnels into `RegisterAttributeDriver`, and
`SecureStateDriver.lua:resolveDriver` resolves the value with `SecureCmdOptionParse(values)`
— i.e. the driver understands exactly the macro conditionals the game understands, nothing
more. It re-evaluates on a 0.2s throttle, with early rescans on a fixed event list that
notably includes **`UPDATE_BONUS_ACTIONBAR`** — the event that fires when the Skyriding
action bar swaps in.

### Consequence for the design

- Use the **override-binding layer**, never `SetBinding` + `SaveBindings`. Overrides are
  non-destructive and self-reverting; this is now a standing preference on the map.
- The insecure path (`SetOverrideBinding` called directly) is blocked by combat lockdown,
  so a state flip mid-combat cannot be honoured until `PLAYER_REGEN_ENABLED`.
- **The feasibility question has moved.** It is no longer "can we rebind" but "**is there a
  macro conditional that is true exactly while Skyriding?**" Macro conditionals are
  implemented client-side in C and do not appear anywhere in `wow-ui-source`, so this cannot
  be answered by reading. It needs the game. That is ticket 03.

### Detection candidates found on the API side

`C_PlayerInfo.GetGlidingInfo()` returns `isGliding, canGlide, forwardSpeed`, and there are
two events: `PLAYER_IS_GLIDING_CHANGED` and `PLAYER_CAN_GLIDE_CHANGED`.
`Blizzard_FrameXML/MotionSickness.lua:74` uses **`canGlide`** — not `isGliding` — to decide
whether to run the Skyriding motion-sickness vignette, which makes `canGlide` Blizzard's own
answer to "is this player in Skyriding mode". `isGliding` is the narrower "airborne and
gliding right now". This distinction is the substance of ticket 05.
