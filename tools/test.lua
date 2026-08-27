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

local world = { gliding = false, mounted = false, flying = false, combat = false }

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
function IsKeyDown() return false end
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
	eventFrame:Fire("PLAYER_IS_GLIDING_CHANGED", true)
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
eventFrame:Fire("PLAYER_IS_GLIDING_CHANGED", false)
check("landing clears it", false)

-- summoned: yanked out of the air behind a loading screen, no gliding event
takeOff()
world.gliding, world.mounted, world.flying = false, false, false
eventFrame:Fire("PLAYER_ENTERING_WORLD")
runTimers()
check("summoned mid-flight clears it", false)

-- died mid-flight
takeOff()
world.gliding, world.mounted, world.flying = false, false, false
eventFrame:Fire("PLAYER_UNGHOST")
check("dying mid-flight clears it", false)

-- water: dismounted with no event at all, and the glide flag goes stale
takeOff()
world.mounted, world.flying = false, false -- still gliding == true: stale
check("water, before any check runs, still applied", true)
tick(0.6)
check("water clears it despite the stale glide flag", false)

-- druid flight form: gliding without ever being mounted
world.gliding, world.mounted, world.flying = true, false, true
eventFrame:Fire("PLAYER_IS_GLIDING_CHANGED", true)
check("druid flight form still counts as flying", true)
tick(1.0)
check("druid flight form is not cleared by the watcher", true)

-- the watcher must never switch the layout on by itself
world.gliding, world.mounted, world.flying = false, false, false
tick(0.6)
check("watcher cleared it", false)
world.gliding, world.mounted, world.flying = true, true, true
tick(2.0)
check("watcher never turns it on without an event", false)

-- zoning while genuinely still airborne must not clear
takeOff()
eventFrame:Fire("ZONE_CHANGED_NEW_AREA")
runTimers()
check("zoning while still flying keeps it", true)

-- combat defers rather than losing the change
world.combat = true
world.gliding, world.mounted, world.flying = false, false, false
eventFrame:Fire("PLAYER_IS_GLIDING_CHANGED", false)
check("landing in combat cannot unbind yet", true)
world.combat = false
eventFrame:Fire("PLAYER_REGEN_ENABLED")
check("leaving combat applies the deferred clear", false)

print()
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
