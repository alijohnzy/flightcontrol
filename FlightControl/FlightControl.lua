local ADDON_NAME, FC = ...

local MAX_PLAN_ENTRIES = 8

local DEFAULTS = {
	enabled = true,

	mode = "event",

	conditional = "[flying,bonusbar:5]",
	verbose = false,
	schema = 4,

	flightLayout = nil,

	invertPitch = false,

	swapDisplaced = true,

	swapRestore = nil,
}

local db
local bindingsReady = false
local UpdateGroundWatch
local Initialise
local STATE_ID = "fcflight"

local CONDITIONAL_PRESETS = {
	air     = "[flying,bonusbar:5]",
	flying  = "[flying]",
	mounted = "[bonusbar:5]",
}

local CONDITIONAL_CANDIDATES = {
	"[flying,bonusbar:5]",
	"[flying]",
	"[bonusbar:5]",
	"[bonusbar:1]", "[bonusbar:2]", "[bonusbar:3]", "[bonusbar:4]",
	"[flying]",
	"[advflyable]",
	"[mounted]",
	"[overridebar]",
	"[vehicleui]",
}

local function Print(...)
	print("|cff33ff99FlightControl|r:", ...)
end

local function Debug(...)
	if db and db.verbose then Print(...) end
end

local MODIFIERS = { "SHIFT-", "CTRL-", "ALT-", "META-" }
local ARROW_KEYS = { UP = true, DOWN = true, LEFT = true, RIGHT = true }

local function IsModified(key)
	local upper = key:upper()
	for _, mod in ipairs(MODIFIERS) do
		if upper:find(mod, 1, true) then return true end
	end
	return false
end

local function ScoreKey(key)
	if not key or key == "" then return -1 end
	if IsModified(key) then return 0 end

	local upper = key:upper()
	if ARROW_KEYS[upper] then return 1 end
	if upper:find("BUTTON", 1, true) or upper:find("NUMPAD", 1, true)
		or upper:find("MOUSEWHEEL", 1, true) then
		return 1
	end

	return (#key == 1) and 3 or 2
end

local function BestKeyFor(action)
	local key1, key2 = GetBindingKey(action)
	local best, bestScore = nil, -1
	for _, key in ipairs({ key1 or false, key2 or false }) do
		if key then
			local score = ScoreKey(key)
			if score > bestScore then best, bestScore = key, score end
		end
	end
	return best, bestScore
end

local function BestClusterKey(actionA, actionB)
	local keyA, scoreA = BestKeyFor(actionA)
	local keyB, scoreB = BestKeyFor(actionB)
	if scoreA >= scoreB then return keyA, scoreA end
	return keyB, scoreB
end

local KEYBOARD_ROWS = {
	"QWERTYUIOP", "ASDFGHJKL",  "ZXCVBNM",
	"AZERTYUIOP", "QSDFGHJKLM", "WXCVBN",
	"QWERTZUIOP", "YXCVBNM",
}

local function KeyHoldsAny(key, ...)
	local action = GetBindingAction(key) or ""
	for i = 1, select("#", ...) do
		if action == select(i, ...) then return true end
	end
	return false
end

local function NeighboursOf(key)
	if not key or #key ~= 1 then return nil end
	key = key:upper()

	local best
	for _, row in ipairs(KEYBOARD_ROWS) do
		local i = row:find(key, 1, true)
		if i and i > 1 and i < #row then
			local left, right = row:sub(i - 1, i - 1), row:sub(i + 1, i + 1)
			local score = 0
			if KeyHoldsAny(left, "STRAFELEFT", "TURNLEFT") then score = score + 1 end
			if KeyHoldsAny(right, "STRAFERIGHT", "TURNRIGHT") then score = score + 1 end
			if not best or score > best.score then
				best = { left = left, right = right, score = score }
			end
		end
	end
	return best
end

local derivedFrom = nil

local function DeriveLayout()
	local fwd = BestKeyFor("MOVEFORWARD")
	local back = BestKeyFor("MOVEBACKWARD")

	local how = "adjacent to " .. tostring(back)
	local neighbours = NeighboursOf(back)
	local left, right
	if neighbours and neighbours.score == 2 then
		left, right = neighbours.left, neighbours.right
	else
		how = "best-scoring keys"
		left = BestClusterKey("STRAFELEFT", "TURNLEFT")
		right = BestClusterKey("STRAFERIGHT", "TURNRIGHT")
	end

	local layout = {}
	local function Slot(key, action)
		if key then layout[#layout + 1] = { key = key, action = action } end
	end

	local fwdPitch, backPitch = "PITCHUP", "PITCHDOWN"
	if db.invertPitch then
		fwdPitch, backPitch = backPitch, fwdPitch
	end

	Slot(fwd, fwdPitch)
	Slot(left, "TURNLEFT")
	Slot(back, backPitch)
	Slot(right, "TURNRIGHT")

	derivedFrom = ("cluster %s/%s/%s/%s, %s%s")
		:format(fwd or "?", left or "?", back or "?", right or "?", how,
		        db.invertPitch and ", inverted pitch" or "")

	return layout
end

local function ActiveLayout()
	if db.flightLayout then
		derivedFrom = "set by hand -- /fcon learn goes back to automatic"
		return db.flightLayout
	end
	return DeriveLayout()
end

local plan = {}

local function BuildPlan()
	local newPlan, claimed = {}, {}

	local function Add(key, action)
		if #newPlan >= MAX_PLAN_ENTRIES then return end

		newPlan[#newPlan + 1] = {
			key = key,
			action = action,
			from = GetBindingAction(key) or "",
		}
		claimed[key] = true
	end

	for _, want in ipairs(ActiveLayout()) do
		local currentOnKey = GetBindingAction(want.key) or ""

		if currentOnKey ~= want.action and not claimed[want.key] then
			Add(want.key, want.action)

			if db.swapDisplaced and currentOnKey ~= "" then

				local other1, other2 = GetBindingKey(want.action)
				local target, targetScore
				for _, other in ipairs({ other1 or false, other2 or false }) do
					if other and other ~= want.key and not claimed[other] then
						local score = ScoreKey(other)
						if not target or score < targetScore then
							target, targetScore = other, score
						end
					end
				end

				if target then Add(target, currentOnKey) end
			end
		end
	end

	plan = newPlan

	if #plan == 0 then
		Debug("plan: nothing to change -- bindings already match the flight layout")
	else
		local parts = {}
		for _, e in ipairs(plan) do
			parts[#parts + 1] = e.key .. "=" .. e.action
		end
		Debug("plan: " .. table.concat(parts, "  "))
	end
end

local WATCHED_ACTIONS = {
	"MOVEFORWARD", "MOVEBACKWARD", "STRAFELEFT", "STRAFERIGHT",
	"TURNLEFT", "TURNRIGHT", "PITCHUP", "PITCHDOWN",
}

local function ActionsStrandedByPlan()
	local overridden = {}
	for _, entry in ipairs(plan) do
		overridden[entry.key] = entry.action
	end

	local stranded = {}
	for _, action in ipairs(WATCHED_ACTIONS) do
		local key1, key2 = GetBindingKey(action)
		if key1 or key2 then
			local survives = false
			for _, key in ipairs({ key1 or false, key2 or false }) do
				if key and overridden[key] == nil then survives = true end
			end
			for _, entry in ipairs(plan) do
				if entry.action == action then survives = true end
			end
			if not survives then
				stranded[#stranded + 1] = action
			end
		end
	end
	return stranded
end

local driver = CreateFrame("Frame", "FlightControlDriver", UIParent, "SecureHandlerStateTemplate")

driver:SetAttribute("_onstate-" .. STATE_ID, ([[
	self:ClearBindings()
	if newstate == "on" then
		for i = 1, %d do
			local key = self:GetAttribute("fcKey" .. i)
			local action = self:GetAttribute("fcAct" .. i)
			if key and action then
				self:SetBinding(true, key, action)
			end
		end
	end
]]):format(MAX_PLAN_ENTRIES))

local function PushPlanToDriver()
	if InCombatLockdown() then return false end
	for i = 1, MAX_PLAN_ENTRIES do
		local entry = plan[i]
		driver:SetAttribute("fcKey" .. i, entry and entry.key or nil)
		driver:SetAttribute("fcAct" .. i, entry and entry.action or nil)
	end
	return true
end

local secureActive = false

local function SecureOverridesLive()
	return secureActive and driver:GetAttribute("state-" .. STATE_ID) == "on"
end

local function StartSecure()
	if secureActive then return end
	if not PushPlanToDriver() then return end
	RegisterStateDriver(driver, STATE_ID, db.conditional .. " on; off")
	secureActive = true
	Debug("secure driver registered with " .. db.conditional)
end

local function StopSecure()
	if not secureActive then return end
	UnregisterStateDriver(driver, STATE_ID)
	secureActive = false
	if not InCombatLockdown() then
		ClearOverrideBindings(driver)
	end
	Debug("secure driver unregistered")
end

local heldWatcher = CreateFrame("Frame")
heldWatcher:Hide()

local deferred = {}

local function StripModifiers(key)
	return key:match("([^%-]+)$") or key
end

local function ModifierDown(fn)
	return type(fn) == "function" and not not fn()
end

local function IsHeld(key)
	local upper = key:upper()

	if (upper:find("SHIFT-", 1, true) ~= nil) ~= ModifierDown(IsShiftKeyDown) then return false end
	if (upper:find("CTRL-", 1, true) ~= nil) ~= ModifierDown(IsControlKeyDown) then return false end
	if (upper:find("ALT-", 1, true) ~= nil) ~= ModifierDown(IsAltKeyDown) then return false end
	if (upper:find("META-", 1, true) ~= nil) ~= ModifierDown(IsMetaKeyDown) then return false end

	local ok, down = pcall(IsKeyDown, StripModifiers(key))
	return ok and down
end

local function ApplyOrDefer(key, apply)
	if IsHeld(key) then
		deferred[key] = apply
		heldWatcher:Show()
		Debug(key .. " is held -- waiting for the release")
	else
		deferred[key] = nil
		apply()
	end
end

heldWatcher:SetScript("OnUpdate", function(self)
	if InCombatLockdown() then return end

	local remaining = false
	for key, apply in pairs(deferred) do
		if IsHeld(key) then
			remaining = true
		else
			deferred[key] = nil
			apply()
		end
	end

	if not remaining then self:Hide() end
end)

local eventOwner = CreateFrame("Frame", "FlightControlEventOwner", UIParent)
local eventApplied = false
local pendingEvent = nil
local appliedKeys = {}

local function ApplyEventBindings(on)
	if InCombatLockdown() then
		pendingEvent = on
		Debug("combat lockdown -- deferring override " .. (on and "apply" or "clear"))
		return
	end
	pendingEvent = nil

	local targets = {}
	for _, entry in ipairs(plan) do
		targets[entry.key] = on and entry.action or false
	end
	for key in pairs(appliedKeys) do
		if targets[key] == nil then targets[key] = false end
	end

	for key, action in pairs(targets) do
		local wanted = action or nil
		ApplyOrDefer(key, function()
			SetOverrideBinding(eventOwner, true, key, wanted)
			appliedKeys[key] = wanted and true or nil
		end)
	end
	eventApplied = on
	if UpdateGroundWatch then UpdateGroundWatch() end
	Debug(on and "flight layout applied" or "flight layout cleared")
end

local pendingSwap = nil

local function ApplySwapBindings(on)
	if InCombatLockdown() then
		pendingSwap = on
		Debug("combat lockdown -- deferring swap " .. (on and "on" or "off"))
		return
	end
	pendingSwap = nil

	if not on and not db.swapRestore then return end

	db.swapRestore = db.swapRestore or {}
	local restore = db.swapRestore

	for _, entry in ipairs(plan) do
		local key, action = entry.key, entry.action
		ApplyOrDefer(key, function()
			if on then

				if restore[key] == nil then
					restore[key] = GetBindingAction(key) or ""
				end
				SetBinding(key, action)
			else
				local saved = restore[key]
				if saved ~= nil then
					SetBinding(key, saved ~= "" and saved or nil)
					restore[key] = nil
				end
			end

			if next(restore) == nil and db.swapRestore == restore then
				db.swapRestore = nil
			end
		end)
	end

	if UpdateGroundWatch then UpdateGroundWatch() end
	Debug(on and "real bindings swapped to flight layout" or "real bindings restored")
end

local function IsFlightState()
	local isGliding = C_PlayerInfo.GetGlidingInfo()
	if not isGliding then return false end

	if not IsMounted() and not IsFlying() then return false end

	return true
end

local function AnyOverrideLive()
	return eventApplied or db.swapRestore ~= nil or SecureOverridesLive()
end

local function ApplyMode()
	if not db.enabled then
		StopSecure()
		ApplyEventBindings(false)
		ApplySwapBindings(false)
		return
	end

	if db.mode == "secure" then
		ApplyEventBindings(false)
		ApplySwapBindings(false)
		StartSecure()
	elseif db.mode == "swap" then
		StopSecure()
		ApplyEventBindings(false)
		ApplySwapBindings(IsFlightState())
	else
		StopSecure()
		ApplySwapBindings(false)
		ApplyEventBindings(IsFlightState())
	end
end

local function Refresh()
	StopSecure()
	ApplyEventBindings(false)
	ApplySwapBindings(false)
	BuildPlan()
	ApplyMode()
end

local function Reconcile(reason)
	if not db or not db.enabled or not bindingsReady then return end

	local shouldBeOn = IsFlightState()

	if db.mode == "event" then
		if eventApplied ~= shouldBeOn then
			Debug(("reconcile after %s -> %s"):format(reason, tostring(shouldBeOn)))
			ApplyEventBindings(shouldBeOn)
		end
	elseif db.mode == "swap" then
		if (db.swapRestore ~= nil) ~= shouldBeOn then
			Debug(("reconcile after %s -> %s"):format(reason, tostring(shouldBeOn)))
			ApplySwapBindings(shouldBeOn)
		end
	end

end

local GROUND_CHECK_INTERVAL = 0.4

local groundWatch = CreateFrame("Frame")
groundWatch:Hide()

local sinceGroundCheck = 0
groundWatch:SetScript("OnUpdate", function(self, elapsed)
	sinceGroundCheck = sinceGroundCheck + elapsed
	if sinceGroundCheck < GROUND_CHECK_INTERVAL then return end
	sinceGroundCheck = 0

	if IsFlightState() then return end
	Reconcile("no longer airborne")
end)

function UpdateGroundWatch()
	local applied = eventApplied or (db and db.swapRestore ~= nil)

	if applied and db and db.enabled and db.mode ~= "secure" then
		groundWatch:Show()
	else
		groundWatch:Hide()
		sinceGroundCheck = 0
	end
end

local RECONCILE_EVENTS = {
	PLAYER_ENTERING_WORLD        = true,
	PLAYER_CONTROL_GAINED        = true,
	PLAYER_CONTROL_LOST          = true,
	PLAYER_UNGHOST               = true,
	PLAYER_ALIVE                 = true,
	PLAYER_MOUNT_DISPLAY_CHANGED = true,
	UNIT_EXITED_VEHICLE          = true,
	ZONE_CHANGED_NEW_AREA        = true,
	PLAYER_CAN_GLIDE_CHANGED     = true,
}

local TURN_STRAFE_STYLE = {
	[0] = "Modern (A/D strafe)",
	[1] = "Legacy (A/D turn)",
	[2] = "Custom",
}

local function Probe()
	local isGliding, canGlide, forwardSpeed = C_PlayerInfo.GetGlidingInfo()

	Print("---- probe ----")
	Print(("GetGlidingInfo: isGliding=%s canGlide=%s speed=%.1f")
		:format(tostring(isGliding), tostring(canGlide), forwardSpeed or 0))
	Print(("IsMounted=%s IsFlying=%s IsFlyableArea=%s IsAdvancedFlyableArea=%s")
		:format(tostring(IsMounted()), tostring(IsFlying()),
		        tostring(IsFlyableArea()), tostring(IsAdvancedFlyableArea())))
	Print(("bonusBarIndex=%s bonusBarOffset=%s hasBonusBar=%s hasOverrideBar=%s")
		:format(tostring(C_ActionBar.GetBonusBarIndex()),
		        tostring(C_ActionBar.GetBonusBarOffset()),
		        tostring(C_ActionBar.HasBonusActionBar()),
		        tostring(C_ActionBar.HasOverrideActionBar())))

	local style = C_KeyBindings.GetTurnStrafeStyle()
	Print(("turn/strafe style: %s"):format(TURN_STRAFE_STYLE[style] or tostring(style)))

	Print("conditionals that are currently TRUE:")
	local anyTrue = false
	for _, cond in ipairs(CONDITIONAL_CANDIDATES) do
		local ok, result = pcall(SecureCmdOptionParse, cond .. " yes; no")
		if not ok then
			Print("   " .. cond .. "  |cffff5555(rejected by client)|r")
		elseif result == "yes" then
			Print("   " .. cond)
			anyTrue = true
		end
	end
	if not anyTrue then
		Print("   (none)")
	end
	Print("---------------")
end

local function Status()
	Print(("enabled=%s mode=%s conditional=%s swapDisplaced=%s")
		:format(tostring(db.enabled), db.mode, db.conditional, tostring(db.swapDisplaced)))

	Print("layout source: " .. (derivedFrom or "not yet derived"))
	if #plan == 0 then
		Print("plan: nothing to change -- your bindings already match")
	else
		Print("plan while flying:")
		for _, e in ipairs(plan) do
			Print(("   %-10s -> %s"):format(e.key, e.action))
		end
	end

	local stranded = ActionsStrandedByPlan()
	if #stranded > 0 then
		Print("|cffffaa00unbound while flying:|r " .. table.concat(stranded, ", "))
	end

	if db.mode == "secure" then
		Print(("state driver registered=%s currently on=%s")
			:format(tostring(secureActive), tostring(SecureOverridesLive())))
	elseif db.mode == "swap" then
		Print("real bindings swapped: " .. tostring(db.swapRestore ~= nil))
	else
		Print("override bindings applied: " .. tostring(eventApplied))
	end
end

local function ShowLayout()
	local layout = ActiveLayout()
	Print("flight layout (" .. (derivedFrom or "?") .. "):")
	for _, want in ipairs(layout) do
		local currentOnKey = GetBindingAction(want.key) or "not bound"
		local mark = (currentOnKey == want.action) and " |cff888888(already correct)|r" or ""
		Print(("   %-10s %s -> %s%s"):format(want.key, currentOnKey, want.action, mark))
	end
	local stranded = ActionsStrandedByPlan()
	if #stranded > 0 then
		Print("no key while flying: " .. table.concat(stranded, ", "))
		Print("  nothing holds the command taking their key, so there is nothing to swap")
		Print("  them with. They come back on landing.")
	end
	Print("change with: /fcon layout W PITCHUP   |   /fcon layout W none   |   /fcon layout reset")
end

SLASH_FLIGHTCONTROL1 = "/fcon"
SLASH_FLIGHTCONTROL2 = "/flightcontrol"

local function WarnOnSlashConflict()
	local conflicts = {}
	for name, value in pairs(_G) do
		if type(name) == "string" and type(value) == "string"
			and name:find("^SLASH_") and not name:find("^SLASH_FLIGHTCONTROL") then
			local token = value:lower()
			if token == "/fcon" or token == "/flightcontrol" then
				local owner = name:match("^SLASH_(.-)%d*$")
				conflicts[token] = owner or name
			end
		end
	end

	for token, owner in pairs(conflicts) do
		Print(("|cffffaa00%s is also claimed by %s|r -- if it stops responding, use %s")
			:format(token, owner, token == "/fcon" and "/flightcontrol" or "/fcon"))
	end
end
SlashCmdList.FLIGHTCONTROL = function(msg)
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()

	if cmd == "probe" then
		Probe()

	elseif cmd == "on" or cmd == "off" then
		db.enabled = (cmd == "on")
		Refresh()
		Print("enabled = " .. tostring(db.enabled))

	elseif cmd == "mode" then
		if rest ~= "secure" and rest ~= "event" and rest ~= "swap" then
			Print("usage: /fcon mode secure|event|swap")
		else
			db.mode = rest
			Refresh()
			Print("mode = " .. db.mode)
			if rest == "secure" then
				Print("|cffffaa00note:|r secure mode rebinds instantly, so a key you are holding")
				Print("      through a take-off will stick its movement on. It works in")
				Print("      combat, which event mode cannot -- that is the trade.")
			end

		end

	elseif cmd == "cond" then
		if rest == "" then
			Print("current conditional: " .. db.conditional)
			Print("presets: air (airborne + Skyriding), flying (airborne, any mount),")
			Print("         mounted (on a Skyriding mount even grounded)")
			Print("or pass a raw conditional: /fcon cond [flying,bonusbar:5]")
		else
			db.conditional = CONDITIONAL_PRESETS[rest:lower()] or rest
			Refresh()
			Print("conditional = " .. db.conditional)
		end

	elseif cmd == "layout" then
		if rest == "" then
			ShowLayout()
		elseif rest:lower() == "reset" then
			db.flightLayout = nil
			Refresh()
			Print("layout unpinned -- deriving from your bindings again")
			ShowLayout()
		else
			local key, action = rest:match("^(%S+)%s+(%S+)$")
			if not key then
				Print("usage: /fcon layout <key> <ACTION|none>")
				return
			end
			key, action = key:upper(), action:upper()

			db.flightLayout = db.flightLayout or CopyTable(DeriveLayout())

			local found
			for i, want in ipairs(db.flightLayout) do
				if want.key == key then found = i end
			end

			if action == "NONE" then
				if found then table.remove(db.flightLayout, found) end
			elseif found then
				db.flightLayout[found].action = action
			else
				db.flightLayout[#db.flightLayout + 1] = { key = key, action = action }
			end
			Refresh()
			ShowLayout()
		end

	elseif cmd == "invert" then
		db.invertPitch = not db.invertPitch
		if FC.IsCustom() then
			Print("pitch inverted = " .. tostring(db.invertPitch)
				.. " |cffffaa00(no effect -- your layout is pinned; /fcon layout reset to derive)|r")
		else
			Print(("pitch inverted = %s -- forward key now %s")
				:format(tostring(db.invertPitch), db.invertPitch and "dives" or "climbs"))
		end
		Refresh()
		ShowLayout()

	elseif cmd == "displaced" then
		db.swapDisplaced = not db.swapDisplaced
		Refresh()
		Print("move displaced actions onto the freed keys = " .. tostring(db.swapDisplaced))

	elseif cmd == "ui" or cmd == "config" or cmd == "options" then
		if FlightControlUI then
			FlightControlUI:Toggle()
		else
			Print("UI not loaded")
		end

	elseif cmd == "learn" then
		db.flightLayout = nil
		Refresh()
		ShowLayout()
		Status()

	elseif cmd == "refresh" then
		Refresh()
		Status()

	elseif cmd == "verbose" then
		db.verbose = not db.verbose
		Print("verbose = " .. tostring(db.verbose))

	elseif cmd == "status" or cmd == "" then
		Status()

	else
		Print("commands: ui | probe | status | learn | layout | on | off")
		Print("          mode secure|event|swap")
		Print("          cond <conditional> | invert | displaced | refresh | verbose")
	end
end

FC.FLIGHT_ACTIONS = {
	{ action = "PITCHUP",    label = "Pitch Up" },
	{ action = "PITCHDOWN",  label = "Pitch Down" },
	{ action = "TURNLEFT",   label = "Turn Left" },
	{ action = "TURNRIGHT",  label = "Turn Right" },
}

function FC.GetDB() return db end
function FC.GetPlan() return plan end
function FC.GetLayout() return ActiveLayout() end
function FC.GetDerivedLayout() return DeriveLayout() end
function FC.GetLayoutSource() return derivedFrom end
function FC.IsCustom() return db.flightLayout ~= nil end
function FC.GetStranded() return ActionsStrandedByPlan() end
function FC.Refresh() Refresh() end
FC.Print = Print

function FC.BeginCustom()
	if not db.flightLayout then
		local derived = DeriveLayout()

		if #derived == 0 then
			Print("no movement cluster found yet -- staying on automatic")
			return nil
		end
		db.flightLayout = CopyTable(derived)
	end
	return db.flightLayout
end

function FC.GetInvertPitch() return db.invertPitch end

function FC.SetInvertPitch(value)
	db.invertPitch = value and true or false
	Refresh()
end

function FC.ClearCustom()
	db.flightLayout = nil
	Refresh()
end

function FC.SetLayoutKey(action, key)
	local layout = FC.BeginCustom()
	if not layout then return end

	for i = #layout, 1, -1 do
		local entry = layout[i]

		if key and entry.key == key and entry.action ~= action then
			Print(("%s taken from %s -- that one now has no key")
				:format(key, entry.action))
		end
		if entry.action == action or (key and entry.key == key) then
			table.remove(layout, i)
		end
	end

	if key then
		layout[#layout + 1] = { key = key, action = action }
	end
	Refresh()
end

Initialise = function()
	if bindingsReady then return end

	if not db then
		C_Timer.After(0.5, Initialise)
		return
	end

	if db.swapRestore then
		Print("last session ended mid-swap -- restoring bindings")
		ApplySwapBindings(false)
	end

	bindingsReady = true
	BuildPlan()
	ApplyMode()
	WarnOnSlashConflict()

end

EventUtil.ContinueAfterAllEvents(Initialise,
	"PLAYER_ENTERING_WORLD", "VARIABLES_LOADED", "BINDINGS_LOADED")

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
f:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("UPDATE_BINDINGS")
for event in pairs(RECONCILE_EVENTS) do
	f:RegisterEvent(event)
end

f:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then return end
		FlightControlDB = FlightControlDB or {}
		db = FlightControlDB

		local isNewProfile = (next(db) == nil)
		local fromSchema = db.schema or 1

		for k, v in pairs(DEFAULTS) do
			if db[k] == nil then
				db[k] = (type(v) == "table") and CopyTable(v) or v
			end
		end

		if not isNewProfile and fromSchema < 2 then
			if db.conditional == "[bonusbar:5]" then
				db.conditional = DEFAULTS.conditional
				Print("flight test updated to " .. db.conditional
					.. " -- the old one fired on mounting, not on take-off")
			end
		end

		if not isNewProfile and fromSchema < 4 and db.mode == "secure" then
			db.mode = "event"
			Print("switched to |cffffffffevent|r mode.")
			Print("Secure mode rebinds instantly and cannot wait for a key you are still")
			Print("holding, which is what leaves movement and camera turn stuck after")
			Print("landing. /fcon mode secure puts it back if you want combat coverage.")
		end

		db.schema = DEFAULTS.schema

	elseif event == "PLAYER_ENTERING_WORLD" then

		C_Timer.After(1, Initialise)

		Reconcile(event)
		C_Timer.After(2, function() Reconcile(event .. " (delayed)") end)

	elseif event == "PLAYER_IS_GLIDING_CHANGED" then
		local on = arg1 and true or false
		Debug("PLAYER_IS_GLIDING_CHANGED -> " .. tostring(on))

		if db.enabled and bindingsReady then
			if db.mode == "event" then
				ApplyEventBindings(on)
			elseif db.mode == "swap" then
				ApplySwapBindings(on)
			end

		end

	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingEvent ~= nil then ApplyEventBindings(pendingEvent) end
		if pendingSwap ~= nil then ApplySwapBindings(pendingSwap) end
		if db.enabled and db.mode == "secure" and not secureActive then
			StartSecure()
		end

	elseif RECONCILE_EVENTS[event] then

		if event ~= "UNIT_EXITED_VEHICLE" or arg1 == "player" then
			Reconcile(event)
		end

	elseif event == "UPDATE_BINDINGS" then

		if bindingsReady and not AnyOverrideLive() then
			BuildPlan()
			if secureActive then
				PushPlanToDriver()
			else
				ApplyMode()
			end
		end
	end
end)
