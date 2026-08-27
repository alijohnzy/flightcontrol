-- Headless regression tests. Run with: lua tools/test.lua [dev|build]
--
-- Stubs enough of the WoW API to load the addon outside the game, then drives
-- it through the situations that have actually broken in play. Every scenario
-- here is a bug that shipped at least once.

local WHICH = arg[1] or "dev"
local ROOT = arg[0]:match("(.*)tools/test%.lua") or "./"
local SRC = WHICH == "build"
	and (ROOT .. "FlightControl/FlightControl.lua")
	or (ROOT .. "dev/FlightControl.lua")

--------------------------------------------------------------------------------
-- World state the stubs report
--------------------------------------------------------------------------------

local world = { gliding = false, mounted = false, flying = false, combat = false, held = {} }

local BINDINGS = {
	MOVEFORWARD = { "W", "UP" }, MOVEBACKWARD = { "S", "DOWN" },
	TURNLEFT = { "LEFT", "SHIFT-A" }, TURNRIGHT = { "RIGHT", "SHIFT-D" },
	STRAFELEFT = { "A" }, STRAFERIGHT = { "D" },
	PITCHUP = { "SHIFT-W" }, PITCHDOWN = { "SHIFT-S" }, JUMP = { "SPACE" },
}

local keyToAction = {}
local function reindex()
	keyToAction = {}
	for action, keys in pairs(BINDINGS) do
		for _, key in ipairs(keys) do keyToAction[key] = action end
	end
end
reindex()

--------------------------------------------------------------------------------
-- Stubs
--------------------------------------------------------------------------------

function GetBindingKey(a) local k = BINDINGS[a]; if not k then return nil end; return k[1], k[2] end
function GetBindingAction(k) return keyToAction[k] or "" end
function GetBindingText(k) return k end
function IsMounted() return world.mounted end
function IsFlying() return world.flying end
function IsFlyableArea() return true end
function IsAdvancedFlyableArea() return true end
function InCombatLockdown() return world.combat end
function IsKeyDown(k) return world.held[k] == true end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function IsMetaKeyDown() return false end
function SetBinding() end
function RegisterStateDriver() end
function UnregisterStateDriver() end
function SecureCmdOptionParse() return "no" end
function CopyTable(t)
	local c = {}
	for k, v in pairs(t) do c[k] = (type(v) == "table") and CopyTable(v) or v end
	return c
end
function tinsert(t, v) table.insert(t, v) end
UIParent, UISpecialFrames = {}, {}
GameTooltip = setmetatable({}, { __index = function() return function() end end })
function GameTooltip_Hide() end
C_PlayerInfo = { GetGlidingInfo = function() return world.gliding, true, 0 end }
C_ActionBar = setmetatable({}, { __index = function() return function() return 0 end end })
C_KeyBindings = { GetTurnStrafeStyle = function() return 2 end }
SlashCmdList = {}

local timers = {}
C_Timer = { After = function(_, fn) table.insert(timers, fn) end }
local function runTimers()
	local due = timers; timers = {}
	for _, fn in ipairs(due) do fn() end
end

local watchers = {}
EventUtil = { ContinueAfterAllEvents = function(cb) table.insert(watchers, cb) end }

local applied = {}
function SetOverrideBinding(_, _, key, action)
	if action then applied[key] = action else applied[key] = nil end
end
function ClearOverrideBindings() applied = {} end

local frames = {}
function CreateFrame(_, name, _, template)
	local attrs, scripts = {}, {}
	local f
	f = setmetatable({
		attrs = attrs, scripts = scripts, name = name, template = template,
		registered = {},
		RegisterEvent = function(x, e) x.registered[e] = true end,
		UnregisterEvent = function(x, e) x.registered[e] = nil end,
		SetAttribute = function(_, k, v) attrs[k] = v end,
		GetAttribute = function(_, k) return attrs[k] end,
		SetScript = function(_, w, fn) scripts[w] = fn end,
		HookScript = function(_, w, fn) scripts[w] = fn end,
		Show = function(x) x.shown = true end,
		Hide = function(x) x.shown = false end,
		IsShown = function(x) return x.shown end,
		CreateFontString = function()
			return setmetatable({}, { __index = function() return function() end end })
		end,
		SetChecked = function(x, v) x.checked = v and true or false end,
		GetChecked = function(x) return x.checked end,
		Fire = function(x, ...) if scripts.OnEvent then scripts.OnEvent(x, ...) end end,
		Tick = function(x, dt) if x.shown and scripts.OnUpdate then scripts.OnUpdate(x, dt) end end,
	}, { __index = function() return function() end end })
	f.text = setmetatable({}, { __index = function() return function() end end })
	f.TitleText = setmetatable({}, { __index = function() return function() end end })
	table.insert(frames, f)
	return f
end

--------------------------------------------------------------------------------
-- Load and boot
--------------------------------------------------------------------------------

local FC = {}
assert(loadfile(SRC))("FlightControl", FC)

local eventFrame
for _, f in ipairs(frames) do
	if rawget(f.scripts, "OnEvent") and rawget(f, "name") == nil then eventFrame = f end
end

local function boot()
	eventFrame:Fire("ADDON_LOADED", "FlightControl")
	for _, cb in ipairs(watchers) do cb() end
	watchers = {}
	runTimers()
end
boot()

-- Dispatch to every frame that registered the event, as the game does. Some
-- events are only registered while the layout is applied, so this has to be
-- driven by the registrations rather than by one known frame.
local function fire(event, ...)
	for _, f in ipairs(frames) do
		if rawget(f, "registered") and f.registered[event] and rawget(f.scripts, "OnEvent") then
			f.scripts.OnEvent(f, event, ...)
		end
	end
end

local function tick(seconds)
	for _ = 1, math.ceil(seconds / 0.1) do
		for _, f in ipairs(frames) do f:Tick(0.1) end
	end
end

--------------------------------------------------------------------------------
-- Assertions
--------------------------------------------------------------------------------

local passed, failed = 0, 0

local function state()
	local parts = {}
	for k, v in pairs(applied) do parts[#parts + 1] = k .. "=" .. v end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, " ") or "(none)"
end

local function check(name, wantApplied)
	local isApplied = next(applied) ~= nil
	if isApplied == wantApplied then
		passed = passed + 1
		print(("  ok    %s"):format(name))
	else
		failed = failed + 1
		print(("  FAIL  %s"):format(name))
		print(("        wanted %s, got: %s"):format(
			wantApplied and "the layout applied" or "no layout", state()))
	end
end

local function takeOff()
	world.gliding, world.mounted, world.flying = true, true, true
	fire("PLAYER_IS_GLIDING_CHANGED", true)
	runTimers()
end

--------------------------------------------------------------------------------
-- Scenarios
--------------------------------------------------------------------------------

print(("FlightControl tests (%s: %s)"):format(WHICH, SRC))
FC.GetDB().mode = "event"
FC.Refresh()

takeOff()
check("take off applies the layout", true)

world.gliding = false
fire("PLAYER_IS_GLIDING_CHANGED", false)
runTimers()
check("landing clears it", false)

-- summoned: yanked out of the air behind a loading screen, no gliding event
takeOff()
world.gliding, world.mounted, world.flying = false, false, false
fire("PLAYER_ENTERING_WORLD")
runTimers()
check("summoned mid-flight clears it", false)

-- died mid-flight
takeOff()
world.gliding, world.mounted, world.flying = false, false, false
fire("PLAYER_UNGHOST")
runTimers()
check("dying mid-flight clears it", false)

-- water: dismounted, and the glide flag is still reading true
takeOff()
world.mounted, world.flying = false, false -- gliding stays true: stale
fire("PLAYER_MOUNT_DISPLAY_CHANGED")
runTimers()
check("water clears it from the dismount event despite a stale glide flag", false)

-- water where the dismount event lands before the state settles
takeOff()
fire("PLAYER_MOUNT_DISPLAY_CHANGED")     -- fires while still reading airborne
check("early dismount event does not clear a live flight", true)
world.mounted, world.flying = false, false
runTimers()                              -- the one deferred re-check
check("the deferred re-check catches it", false)

-- druid leaving Flight Form: no dismount, because druids never mounted
takeOff()
world.mounted = false          -- druids are never mounted
world.gliding, world.flying = true, true
fire("PLAYER_IS_GLIDING_CHANGED", true)
check("druid in Flight Form counts as flying", true)
world.gliding, world.flying = false, false
fire("UPDATE_SHAPESHIFT_FORM")
runTimers()
check("druid leaving Flight Form clears it", false)

world.gliding, world.mounted, world.flying = true, false, true
fire("PLAYER_IS_GLIDING_CHANGED", true)
world.gliding, world.flying = false, false
fire("UNIT_FORM_CHANGED", "player")
runTimers()
check("UNIT_FORM_CHANGED for the player clears it", false)

world.gliding, world.mounted, world.flying = true, false, true
fire("PLAYER_IS_GLIDING_CHANGED", true)
fire("UNIT_FORM_CHANGED", "party1")
runTimers()
check("someone else changing form is ignored", true)

-- evoker Soar: a third carrier. Whether the game counts it as a mount or a
-- form is unknown, so the generic skyriding signal has to be what catches it.
world.gliding, world.mounted, world.flying = true, false, true
fire("PLAYER_IS_GLIDING_CHANGED", true)
check("evoker soaring counts as flying", true)
world.gliding, world.flying = false, false
fire("PLAYER_CAN_GLIDE_CHANGED", false)
runTimers()
check("soar ending clears it via the carrier-agnostic signal", false)

-- and again if Soar happens to be a mount after all
world.gliding, world.mounted, world.flying = true, true, true
fire("PLAYER_IS_GLIDING_CHANGED", true)
world.gliding, world.mounted, world.flying = true, false, false
fire("PLAYER_MOUNT_DISPLAY_CHANGED")
runTimers()
check("soar ending clears it if it is mount-like", false)

-- zoning while genuinely still airborne must not clear
takeOff()
fire("ZONE_CHANGED_NEW_AREA")
runTimers()
check("zoning while still flying keeps it", true)

-- combat defers rather than losing the change
takeOff()
world.combat = true
world.gliding, world.mounted, world.flying = false, false, false
fire("PLAYER_IS_GLIDING_CHANGED", false)
runTimers()
check("landing in combat cannot unbind yet", true)
world.combat = false
fire("PLAYER_REGEN_ENABLED")
check("leaving combat applies the deferred clear", false)

-- Unmounted and swimming. Whatever the game reports, nothing here may switch
-- flight mode on: reported in play as W and S rotating the player in water.
world.held = {}
world.gliding, world.mounted, world.flying = false, false, false
fire("PLAYER_IS_GLIDING_CHANGED", false)
runTimers()
check("start on the ground with nothing applied", false)

world.gliding = true   -- the glide flag reading true while swimming
for _, e in ipairs({ "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_CAN_GLIDE_CHANGED",
                     "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
                     "UPDATE_SHAPESHIFT_FORM", "PLAYER_CONTROL_GAINED" }) do
	fire(e, "player")
	runTimers()
end
check("no event can switch flight mode on while swimming", false)

world.gliding, world.flying = true, true
fire("PLAYER_MOUNT_DISPLAY_CHANGED")
runTimers()
check("nor can one while genuinely airborne", false)

-- Entering water while still holding the key you were flying with. The key
-- keeps its flight meaning until released, on purpose: rebinding a held key
-- strands the old command, and PitchUpStop is protected so nothing can stop it.
-- Deferring means one awkward keypress; rebinding means rotating forever.
world.held = {}
takeOff()
world.held["W"] = true
world.gliding, world.mounted, world.flying = true, false, false
fire("PLAYER_MOUNT_DISPLAY_CHANGED")
runTimers()

local onlyHeldKeyRemains = state() == "W=PITCHUP"
if onlyHeldKeyRemains then
	passed = passed + 1
	print("  ok    water clears every key except the one being held")
else
	failed = failed + 1
	print("  FAIL  water clears every key except the one being held")
	print("        " .. state())
end

world.held["W"] = false
tick(0.5)
check("releasing the held key clears it too", false)

print()
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
