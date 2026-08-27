-- FlightControl -- while Skyriding, WASD becomes the strafe + pitch cluster.
--
-- The swap is computed from the player's own bindings rather than hardcoded.
-- A "flight layout" says which action should sit on which key while flying; for
-- each key that isn't already correct, the wanted action moves onto it and the
-- action it displaced moves onto whichever key used to hold the wanted action.
-- Nothing is invented and nothing is lost -- it is a straight exchange.
--
-- The flight layout is pitch on the vertical axis and turn on the horizontal:
-- while gliding you are already moving forward, and turning is what actually
-- steers a mount -- strafe only drifts you sideways without changing heading.
--
-- Worked example, W=PITCHUP A=TURNLEFT S=PITCHDOWN D=TURNRIGHT:
--
--   before                    after (while flying)
--   W       MOVEFORWARD       W       PITCHUP
--   SHIFT-W PITCHUP           SHIFT-W MOVEFORWARD
--   S       MOVEBACKWARD      S       PITCHDOWN
--   SHIFT-S PITCHDOWN         SHIFT-S MOVEBACKWARD
--   A       STRAFELEFT        A       TURNLEFT
--   SHIFT-A TURNLEFT          SHIFT-A STRAFELEFT
--   D       STRAFERIGHT       D       TURNRIGHT
--   SHIFT-D TURNRIGHT         SHIFT-D STRAFERIGHT
--   LEFT    TURNLEFT          LEFT    TURNLEFT       (alternate, left alone)
--
-- which removes the reason the shift-modified layout misbehaves: nothing you
-- need in flight is behind a modifier any more.
--
-- Three mechanisms, because only one of them can work in combat and which one is
-- correct depends on facts that can only be checked in-game (see /fcon probe):
--
--   secure -- a SecureHandlerStateTemplate frame driven by RegisterStateDriver.
--             The snippet calls self:SetBinding(), which the restricted
--             environment exposes with no filtering on the action string
--             (Blizzard_RestrictedAddOnEnvironment/RestrictedFrames.lua:565).
--             Works in combat. Needs a macro conditional that is true exactly
--             while flying.
--
--   event  -- PLAYER_CAN_GLIDE_CHANGED + SetOverrideBinding(). Detection is
--             exact, but SetOverrideBinding is blocked during combat lockdown,
--             so a state flip mid-combat is deferred to PLAYER_REGEN_ENABLED.
--
--   swap   -- SetBinding() on the real binding set, with the previous actions
--             recorded and put back on landing. The fallback for the case where
--             override bindings turn out not to reach the movement system while
--             Skyriding. See .scratch ticket 04.
--
-- secure and event both use the override layer, so the player's saved bindings
-- are never written to and ClearOverrideBindings restores them for free.

local ADDON_NAME, FC = ...

local MAX_PLAN_ENTRIES = 8 -- the secure snippet reads a fixed number of slots

local DEFAULTS = {
	enabled = true,
	-- event, not secure. The secure state driver runs its snippet the instant the
	-- conditional flips and cannot wait for anything, so it rebinds keys that are
	-- still held and sticks movement on every take-off. Only the insecure paths
	-- can wait for a release, and with the movement functions protected that is
	-- the only fix available. Combat coverage is the lesser loss.
	mode = "event",
	-- [bonusbar:5] alone is true the moment you MOUNT a Skyriding mount, including
	-- standing still on the ground -- confirmed in-game. Adding [flying] narrows it
	-- to actually airborne, which is what the swap should follow.
	conditional = "[flying,bonusbar:5]",
	verbose = false,

	-- What to do about a key that is held while the bindings change.
	--
	-- "auto"    : defer only when the command being replaced would keep running.
	-- "defer"   : never rebind a held key either way.
	-- "instant" : always rebind immediately.
	--
	-- Auto is not a hedge, it is the shape of the problem. The two directions
	-- strand different commands and only one of them survives.
	--
	-- Going in, the key is on MOVEFORWARD. That is a perfectly good command on
	-- the ground, so if its stop never runs you keep running after you land.
	-- Confirmed in play, and the reason deferring exists at all.
	--
	-- Coming out, the key is on PITCHUP or PITCHDOWN, which mean nothing once
	-- you are not flying. The game drops them, so rebinding mid-press costs
	-- nothing. Also confirmed in play: deferring here was what left a player
	-- rotating in water because they were swimming with forward held.
	heldPolicy = "auto",
	schema = 4,

	-- nil = derive the movement cluster from the player's own bindings on every
	-- refresh. Set by /fcon layout to pin it manually instead.
	flightLayout = nil,

	-- Flight-sim style inverted pitch: forward key dives, back key climbs.
	-- Applies to derivation only -- a pinned custom layout is already explicit.
	invertPitch = false,

	-- Move each displaced action onto the key that used to hold the wanted one,
	-- instead of leaving it unbound for the duration.
	swapDisplaced = true,

	-- swap mode only: what the affected keys were bound to before we touched
	-- them. Persisted so a session that ends mid-flight is recoverable.
	swapRestore = nil,
}

local db
local bindingsReady = false
local Initialise
local STATE_ID = "fcflight"

-- Named shortcuts for /fcon cond, so the useful ones don't have to be memorised.
local CONDITIONAL_PRESETS = {
	air     = "[flying,bonusbar:5]", -- airborne AND on a Skyriding mount (default)
	flying  = "[flying]",            -- airborne on anything, incl. steady flight
	mounted = "[bonusbar:5]",        -- mounted on a Skyriding mount, grounded or not
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

-- Read from the TOC rather than kept in a constant, so it cannot drift from
-- what was actually packaged.
local ADDON_VERSION = C_AddOns and C_AddOns.GetAddOnMetadata
	and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "unknown"

local function Print(...)
	print("|cff33ff99FlightControl|r:", ...)
end

local function Debug(...)
	if db and db.verbose then Print(...) end
end

--------------------------------------------------------------------------------
-- Learning the player's movement cluster
--------------------------------------------------------------------------------

-- The cluster is wherever the player actually put movement, not literally WASD.
-- An ESDF player has MOVEFORWARD on E; a Legacy-style player has TURNLEFT rather
-- than STRAFELEFT sitting on the left of the cluster. Both are derived, not assumed.

local MODIFIERS = { "SHIFT-", "CTRL-", "ALT-", "META-" }
local ARROW_KEYS = { UP = true, DOWN = true, LEFT = true, RIGHT = true }

local function IsModified(key)
	local upper = key:upper()
	for _, mod in ipairs(MODIFIERS) do
		if upper:find(mod, 1, true) then return true end
	end
	return false
end

-- Higher is a better home for a movement command: an unmodified single character
-- beats a named key, which beats an arrow or mouse button, which beats anything
-- behind a modifier. The modifier case is the whole reason this addon exists.
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

-- For the left and right of the cluster, either the strafe or the turn command
-- may be the one sitting on the good key. Take whichever scores higher.
local function BestClusterKey(actionA, actionB)
	local keyA, scoreA = BestKeyFor(actionA)
	local keyB, scoreB = BestKeyFor(actionB)
	if scoreA >= scoreB then return keyA, scoreA end
	return keyB, scoreB
end

-- Scoring alone picks the wrong keys when strafe and turn both sit on plain
-- letters: a player with A=TURNLEFT and Q=STRAFELEFT has their hand on A, but
-- both score identically. Physical adjacency to the backward key breaks the tie,
-- which also means the cluster is found on non-QWERTY layouts without asking.
local KEYBOARD_ROWS = {
	"QWERTYUIOP", "ASDFGHJKL",  "ZXCVBNM", -- QWERTY
	"AZERTYUIOP", "QSDFGHJKLM", "WXCVBN",  -- AZERTY
	"QWERTZUIOP", "YXCVBNM",               -- QWERTZ
}

local function KeyHoldsAny(key, ...)
	local action = GetBindingAction(key) or ""
	for i = 1, select("#", ...) do
		if action == select(i, ...) then return true end
	end
	return false
end

-- Returns the neighbours of `key` on whichever row explains the most of the
-- player's existing left/right movement bindings.
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

local derivedFrom = nil -- description of what learning found, for /fcon status

local function DeriveLayout()
	local fwd = BestKeyFor("MOVEFORWARD")
	local back = BestKeyFor("MOVEBACKWARD")

	-- Trust adjacency only when both neighbours of the backward key already hold
	-- a left/right movement command -- that is what makes it the cluster rather
	-- than a coincidence. Otherwise fall back to scoring.
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

	-- Forward/back give up their keys to pitch: while gliding you are already
	-- moving forward, so the cluster's vertical axis is free for climb/dive.
	-- Left/right become turn rather than strafe, because turning is what steers
	-- a mount -- strafe only drifts you sideways without changing heading.
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

--------------------------------------------------------------------------------
-- The plan
--------------------------------------------------------------------------------

-- plan[i] = { key = "W", action = "PITCHUP" }
--
-- Built only while no override of ours is live. GetBindingAction and
-- GetBindingKey both read through the override layer, so building the plan
-- while the swap is applied would read back our own work and lose the originals.
local plan = {}

local function BuildPlan()
	local newPlan, claimed = {}, {}

	local function Add(key, action)
		if #newPlan >= MAX_PLAN_ENTRIES then return end
		-- `from` is what the key does with the flight layout off. Recorded here,
		-- while nothing of ours is applied, so the hand-over knows both sides.
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
				-- The displaced action goes to exactly one key: the least
				-- accessible of those already holding the wanted action -- i.e.
				-- the modified one. Handing it to every such key would clobber
				-- alternates like the arrow keys, which should keep working.
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
				-- If nothing holds the wanted command there is no key to trade
				-- with, and the displaced one simply has no key for the flight.
				-- Inventing a chord for it would mean binding something the
				-- player never agreed to, and any chord we picked might already
				-- mean something to them.
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

-- A plan can strand an action with no key at all: if nothing currently holds
-- PITCHUP, the key we take for it has nowhere to hand its old action back to.
-- Silently unbinding someone's Move Forward would be a nasty surprise, so it is
-- reported rather than assumed acceptable.
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

--------------------------------------------------------------------------------
-- Secure mechanism
--------------------------------------------------------------------------------

local driver = CreateFrame("Frame", "FlightControlDriver", UIParent, "SecureHandlerStateTemplate")

-- Uses only self:GetAttribute, self:SetBinding and self:ClearBindings, plus the
-- `..` operator -- all language-level or exposed to the restricted environment.
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

--------------------------------------------------------------------------------
-- Held-key deferral
--------------------------------------------------------------------------------

-- Movement bindings are runOnUp="true" (Bindings_Standard.xml): the key-up runs
-- whatever the key is bound to *at that moment*. Rebind a key while it is held
-- and the old action's Stop never runs, so the command sticks on -- take off
-- holding W and you are still running after you land; the same on turn leaves
-- the camera spinning after landing.
--
-- Handing the key over (stop the old command, start the new one) would be the
-- nicer behaviour, but MoveForwardStop/PitchUpStart and the rest are PROTECTED:
-- calling them raises ADDON_ACTION_FORBIDDEN and taints the addon. pcall does
-- not suppress it. Confirmed in-game on 12.1.0.69404.
--
-- So the only mechanism available is to never rebind a key that is currently
-- down. The release delivers the key-up to the old binding, which stops the old
-- command properly, and only then does the key change meaning.

local heldWatcher = CreateFrame("Frame")
heldWatcher:Hide()

local deferred = {} -- key -> function to run once the key comes up

-- IsKeyDown takes a bare key, not a chord.
local function StripModifiers(key)
	return key:match("([^%-]+)$") or key
end

-- Physically down, modifiers ignored on purpose.
--
-- Requiring a chord's modifiers to match exactly meant IsHeld("W") went false
-- the moment CTRL went down, even with W still under your finger. The deferral
-- then rebound W mid-press and stranded whatever it was running. Anyone with a
-- modified binding they use in flight hits that.
--
-- What decides where a key-up lands is whether the physical key is down, so
-- that is the only question asked. Waiting longer than strictly necessary is
-- harmless; rebinding too early is not.
local function IsHeld(key)
	local ok, down = pcall(IsKeyDown, StripModifiers(key))
	return ok and down
end

-- Whether leaving this command running would still do something once the
-- player is back on the ground. That, not which way the transition is going,
-- decides whether a held key may be rebound underneath them.
--
-- All of these keep going once stranded: MOVEFORWARD runs you off, TURNLEFT
-- spins the camera. Pitch is deliberately absent, because the game drops it
-- the moment you stop flying, so rebinding it mid-press costs nothing. Both
-- halves confirmed in play.
local STRANDS_ON_GROUND = {
	MOVEFORWARD = true, MOVEBACKWARD = true,
	TURNLEFT = true,    TURNRIGHT = true,
	STRAFELEFT = true,  STRAFERIGHT = true,
}

local function ApplyOrDefer(key, apply)
	local policy = db and db.heldPolicy or "auto"

	local mayDefer
	if policy == "instant" then
		mayDefer = false
	elseif policy == "defer" then
		mayDefer = true
	else
		-- Whatever the key does right now is what gets stranded if it is
		-- rebound while held.
		mayDefer = STRANDS_ON_GROUND[GetBindingAction(key) or ""] == true
	end

	if not mayDefer then
		deferred[key] = nil
		apply()
		return
	end

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
	if InCombatLockdown() then return end -- neither binding API is usable now

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

--------------------------------------------------------------------------------
-- Event mechanism
--------------------------------------------------------------------------------

local eventOwner = CreateFrame("Frame", "FlightControlEventOwner", UIParent)
local eventApplied = false
local pendingEvent = nil
local appliedKeys = {} -- keys we currently hold an override on

local function ApplyEventBindings(on)
	if InCombatLockdown() then
		pendingEvent = on
		Debug("combat lockdown -- deferring override " .. (on and "apply" or "clear"))
		return
	end
	pendingEvent = nil

	-- EVERY plan key goes in, not just the ones we actually managed to set. A key
	-- that was held through the last transition still has a pending closure from
	-- it; leaving it out here means that stale closure fires on release and
	-- applies the wrong state -- turning the flight layout on after landing.
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
	Debug(on and "flight layout applied" or "flight layout cleared")
end

--------------------------------------------------------------------------------
-- Swap mechanism -- writes the real binding set
--------------------------------------------------------------------------------

local pendingSwap = nil

-- Deliberately never calls SaveBindings(). SetBinding alone changes the live
-- binding without persisting it, so a crash, disconnect or /reload while
-- airborne reverts the swap for free. db.swapRestore covers the one case that
-- survives that: the player opening the keybinding panel and saving while the
-- swap happens to be applied.
local function ApplySwapBindings(on)
	if InCombatLockdown() then
		pendingSwap = on
		Debug("combat lockdown -- deferring swap " .. (on and "on" or "off"))
		return
	end
	pendingSwap = nil

	-- Nothing to put back. Without this, the other modes' calls to
	-- ApplySwapBindings(false) would queue a deferred closure per held key that
	-- does nothing but keep the watcher spinning.
	if not on and not db.swapRestore then return end

	db.swapRestore = db.swapRestore or {}
	local restore = db.swapRestore

	for _, entry in ipairs(plan) do
		local key, action = entry.key, entry.action
		ApplyOrDefer(key, function()
			if on then
				-- recorded per key, before that key is touched, never after
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

			-- Only drop the record once every key really is back, otherwise a
			-- still-deferred key would lose the value it needs to restore.
			if next(restore) == nil and db.swapRestore == restore then
				db.swapRestore = nil
			end
		end)
	end

	Debug(on and "real bindings swapped to flight layout" or "real bindings restored")
end

--------------------------------------------------------------------------------
-- Mode switching
--------------------------------------------------------------------------------

-- isGliding, not canGlide. canGlide is "could glide if you took off" and is true
-- while sitting on the ground mounted; isGliding is actually airborne. Blizzard's
-- own Dragonriding tutorial uses isGliding for its take-off / land steps.
local function IsFlightState()
	local isGliding = C_PlayerInfo.GetGlidingInfo()
	if not isGliding then return false end

	-- The glide flag can lag behind reality. Flying into water dismounts you
	-- with no event of any kind, and the flag has been seen still reading true
	-- afterwards, which left the flight layout stuck on.
	--
	-- Being neither mounted nor airborne is unambiguous: the player is standing
	-- or swimming, so the flag is stale and the layout must come off. Both halves
	-- are needed. IsMounted alone would be wrong for druids, who skyride in
	-- Flight Form without ever being mounted, and IsFlying alone would be wrong
	-- for the moment a glide starts from the ground.
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

-- Rebuild from the live bindings and re-apply. Only safe with nothing of ours applied.
local function Refresh()
	StopSecure()
	ApplyEventBindings(false)
	ApplySwapBindings(false)
	BuildPlan()
	ApplyMode()
end

-- PLAYER_IS_GLIDING_CHANGED is the fast path, but it is not fired for every way
-- a flight can end. Being summoned, dying, boarding a taxi and zoning all put
-- the player on the ground without it, and the flight layout stayed applied.
-- So the truth is re-read from GetGlidingInfo whenever something might have
-- moved the player, and the bindings are corrected if they disagree.
-- Clear-only, deliberately. Turning the layout ON is the sole job of
-- PLAYER_IS_GLIDING_CHANGED, which is the game telling us a glide has actually
-- begun. Everything here is a second opinion about whether a glide has ENDED,
-- and a second opinion should never be able to start flight mode: reported
-- in play as the layout switching itself on while unmounted and swimming,
-- which turned W and S into pitch and rotated the player in the water.
local function Reconcile(reason)
	if not db or not db.enabled or not bindingsReady then return end
	if IsFlightState() then return end

	if db.mode == "event" then
		if eventApplied then
			Debug("reconcile after " .. reason .. ": no longer flying")
			ApplyEventBindings(false)
		end
	elseif db.mode == "swap" then
		if db.swapRestore ~= nil then
			Debug("reconcile after " .. reason .. ": no longer flying")
			ApplySwapBindings(false)
		end
	end
	-- secure mode needs nothing: its state driver re-evaluates the conditional
	-- on its own, so the snippet clears the bindings without our help.
end

-- Anything that can end a flight without PLAYER_IS_GLIDING_CHANGED firing.
-- One deferred re-check per event. Some of these arrive a moment before the
-- game's own state catches up, so a single immediate read can see the old
-- value. This is one extra call, not a repeating timer.
local function ReconcileSoon(reason)
	Reconcile(reason)
	C_Timer.After(0.2, function() Reconcile(reason .. " (settled)") end)
end

local RECONCILE_EVENTS = {
	PLAYER_ENTERING_WORLD        = true, -- summon, hearth, teleport, zoning
	PLAYER_CONTROL_GAINED        = true, -- released from taxi, cutscene, summon
	PLAYER_CONTROL_LOST          = true,
	PLAYER_UNGHOST               = true, -- died mid-flight
	PLAYER_ALIVE                 = true,
	-- Three things can carry you: a mount, a druid's Flight Form, and an
	-- evoker's Soar. A mount going away fires the first of these; a druid
	-- leaving form fires the other two, since druids never mount at all.
	-- Soar goes through the skyriding system proper, confirmed in play, so it
	-- is covered by PLAYER_CAN_GLIDE_CHANGED below regardless of whether the
	-- game counts it as a mount. These are the specific signals; that is the
	-- general one.
	PLAYER_MOUNT_DISPLAY_CHANGED = true,
	UPDATE_SHAPESHIFT_FORM       = true,
	UNIT_FORM_CHANGED            = true,
	UNIT_EXITED_VEHICLE          = true,
	ZONE_CHANGED_NEW_AREA        = true,
	-- Carrier-agnostic: whatever was holding you up, losing the ability to glide
	-- means the flight is over. This is the one that covers evoker Soar.
	PLAYER_CAN_GLIDE_CHANGED     = true,
}

--------------------------------------------------------------------------------
-- Probe
--------------------------------------------------------------------------------

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

	-- pcall each one: an unrecognised conditional must not abort the sweep,
	-- since finding out which ones the client accepts is half the point.
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

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local function Status()
	Print("version " .. ADDON_VERSION)
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

-- Two addons claiming the same slash token is resolved silently in favour of
-- whichever loaded last, so the loser just stops responding with no error. Worth
-- one scan of _G at login to say so out loud. /flightcontrol is the safe fallback.
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

			-- First manual edit pins the currently-derived layout, then edits it.
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

	elseif cmd == "version" or cmd == "ver" then
		Print("version " .. ADDON_VERSION)

	elseif cmd == "hold" then
		if rest ~= "auto" and rest ~= "defer" and rest ~= "instant" then
			Print("held-key policy is currently: " .. db.heldPolicy)
			Print("  auto    -- wait on the way in, rebind straight away on the way out")
			Print("  defer   -- a key you are holding keeps its old job until you let go")
			Print("  instant -- always rebind straight away, even mid-press")
			Print("usage: /fcon hold auto|defer|instant")
		else
			db.heldPolicy = rest
			Print("held-key policy = " .. db.heldPolicy)
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
		Print("commands: ui | version | probe | status | learn | layout | on | off")
		Print("          mode secure|event|swap")
		Print("          cond <conditional> | invert | hold | displaced | refresh | verbose")
	end
end

--------------------------------------------------------------------------------
-- Interface for FlightControlUI.lua
--------------------------------------------------------------------------------

FC.FLIGHT_ACTIONS = {
	{ action = "PITCHUP",    label = "Pitch Up" },
	{ action = "PITCHDOWN",  label = "Pitch Down" },
	{ action = "TURNLEFT",   label = "Turn Left" },
	{ action = "TURNRIGHT",  label = "Turn Right" },
}

function FC.GetVersion() return ADDON_VERSION end
function FC.GetDB() return db end
function FC.GetPlan() return plan end
function FC.GetLayout() return ActiveLayout() end
function FC.GetDerivedLayout() return DeriveLayout() end
function FC.GetLayoutSource() return derivedFrom end
function FC.IsCustom() return db.flightLayout ~= nil end
function FC.GetStranded() return ActionsStrandedByPlan() end
function FC.Refresh() Refresh() end
FC.Print = Print

-- Pin the current layout so the UI can edit it, if it isn't pinned already.
function FC.BeginCustom()
	if not db.flightLayout then
		local derived = DeriveLayout()
		-- Pinning an empty layout would switch the addon off for good, and the
		-- only sign of it would be a checkbox that refuses to stay ticked.
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

-- Assign `key` to `action`, dropping any other flight action that held it.
-- key = nil removes the action from the layout entirely.
function FC.SetLayoutKey(action, key)
	local layout = FC.BeginCustom()
	if not layout then return end

	for i = #layout, 1, -1 do
		local entry = layout[i]
		-- Taking a key off another command leaves that row blank, which is easy
		-- to miss in a window full of rows. Say so.
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

--------------------------------------------------------------------------------
-- Start-up
--------------------------------------------------------------------------------

-- Bindings are not loaded when PLAYER_LOGIN fires. Building the plan before
-- BINDINGS_LOADED reads a partially-populated set and produces a wrong plan
-- (observed in-game: MOVEFORWARD handed to INSERT, because PITCHUP was still on
-- its default key). Blizzard's own binding code waits on the same three events.
Initialise = function()
	if bindingsReady then return end

	-- ADDON_LOADED should always beat this, but if the addon were ever loaded on
	-- demand it might not -- re-arm rather than silently never starting.
	if not db then
		C_Timer.After(0.5, Initialise)
		return
	end

	-- A surviving swapRestore means the last session ended mid-flight.
	-- Put the bindings back before reading them for the new plan.
	if db.swapRestore then
		Print("last session ended mid-swap -- restoring bindings")
		ApplySwapBindings(false)
	end

	bindingsReady = true
	BuildPlan()
	ApplyMode()
	WarnOnSlashConflict()

end

-- Registered at file scope, NOT from inside a login handler.
-- EventUtil.ContinueAfterAllEvents only counts events that arrive *after* it is
-- called -- it has no "already fired" check -- and VARIABLES_LOADED and
-- BINDINGS_LOADED both fire before PLAYER_LOGIN. Registering any later means
-- waiting forever for events that have already been and gone.
EventUtil.ContinueAfterAllEvents(Initialise,
	"PLAYER_ENTERING_WORLD", "VARIABLES_LOADED", "BINDINGS_LOADED")

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------

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
		-- Read both of these BEFORE filling in defaults: the defaults loop would
		-- otherwise seed db.schema itself and make every profile look current.
		local isNewProfile = (next(db) == nil)
		local fromSchema = db.schema or 1

		for k, v in pairs(DEFAULTS) do
			if db[k] == nil then
				db[k] = (type(v) == "table") and CopyTable(v) or v
			end
		end

		-- schema 1 shipped with [bonusbar:5], which turned out to be true from the
		-- moment you mount rather than from take-off. Move anyone still on it.
		if not isNewProfile and fromSchema < 2 then
			if db.conditional == "[bonusbar:5]" then
				db.conditional = DEFAULTS.conditional
				Print("flight test updated to " .. db.conditional
					.. " -- the old one fired on mounting, not on take-off")
			end
		end

		-- Secure mode rebinds from inside its snippet the instant the conditional
		-- flips, so it cannot wait for a held key to come up -- and the movement
		-- stop/start functions that would otherwise cancel the stranded command
		-- are protected. Only the insecure paths can defer, so move people off it.
		if not isNewProfile and fromSchema < 4 and db.mode == "secure" then
			db.mode = "event"
			Print("switched to |cffffffffevent|r mode.")
			Print("Secure mode rebinds instantly and cannot wait for a key you are still")
			Print("holding, which is what leaves movement and camera turn stuck after")
			Print("landing. /fcon mode secure puts it back if you want combat coverage.")
		end

		db.schema = DEFAULTS.schema

	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Safety net. If the gate below somehow missed an event we would never
		-- initialise at all, and nothing would work until the user poked the UI.
		C_Timer.After(1, Initialise)

		-- A loading screen is exactly how a summon interrupts a flight. Check
		-- now, and again shortly after, because the player's state is not
		-- necessarily settled the instant the screen clears.
		ReconcileSoon(event)

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
		-- UNIT_EXITED_VEHICLE carries a unit; the rest carry nothing useful.
		local unitScoped = (event == "UNIT_EXITED_VEHICLE" or event == "UNIT_FORM_CHANGED")
		if not unitScoped or arg1 == "player" then
			ReconcileSoon(event)
		end

	elseif event == "UPDATE_BINDINGS" then
		-- Rebuilding while our own bindings are applied would read them back as
		-- the originals, so only rebuild in a clean window -- and never before
		-- the initial gate, since UPDATE_BINDINGS fires repeatedly during login
		-- with a half-loaded set.
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
