-- FlightControlUI -- pick the flight layout by hand instead of deriving it.
--
-- Two modes, mirroring the core:
--   learn  -- the cluster is derived from the player's bindings; rows are read-only
--   custom -- the player assigns each flight action a key themselves
--
-- Key capture goes through Blizzard's own binding helpers (GetConvertedKeyOrButton,
-- IsKeyPressIgnoredForBinding, CreateKeyChordStringUsingMetaKeyState) rather than
-- hand-rolled modifier composition, so chords come out in the same canonical form
-- the binding system uses.

local ADDON_NAME, FC = ...

local ROW_HEIGHT = 30
local PANEL_WIDTH = 440

local frame
local rows = {}
local listeningRow

--------------------------------------------------------------------------------
-- Key capture
--------------------------------------------------------------------------------

local listenTimer

local function StopListening()
    if not listeningRow then return end
    local row = listeningRow
    listeningRow = nil
    listenTimer = nil

    -- Both, always. While either is left set the button eats every keypress in
    -- the game, which is how trying to walk with the window open ended up
    -- rewriting the layout one movement key at a time.
    row.KeyButton:SetPropagateKeyboardInput(true)
    row.KeyButton:EnableKeyboard(false)
    FlightControlUI:Refresh()
end

local function StartListening(row)
    StopListening()
    listeningRow = row

    row.KeyButton:SetText("press a key... (Esc cancels)")
    row.KeyButton:EnableKeyboard(true)
    row.KeyButton:SetPropagateKeyboardInput(false)

    -- Hard backstop. Capture is the only state in which this addon holds the
    -- keyboard, so it must not be possible to get stuck in it.
    local token = {}
    listenTimer = token
    C_Timer.After(6, function()
        if listeningRow == row and listenTimer == token then
            FC.Print("key capture timed out -- keyboard released")
            StopListening()
        end
    end)
end

local function OnKeyCaptured(row, rawKey)
    -- Not the listening row: hand the key straight back to the game. Without
    -- this a stale keyboard-enabled button silently swallows input.
    if listeningRow ~= row then
        row.KeyButton:SetPropagateKeyboardInput(true)
        row.KeyButton:EnableKeyboard(false)
        return
    end

    local key = GetConvertedKeyOrButton(rawKey)

    if IsKeyPressIgnoredForBinding(key) then
        return -- a bare modifier; wait for the real key
    end

    if key == "ESCAPE" then
        StopListening()
        return
    end

    if key == "BACKSPACE" or key == "DELETE" then
        FC.SetLayoutKey(row.action, nil)
        StopListening()
        return
    end

    FC.SetLayoutKey(row.action, CreateKeyChordStringUsingMetaKeyState(key))
    StopListening()
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function Tooltip(widget, title, body)
	widget:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		GameTooltip:AddLine(body, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	widget:HookScript("OnLeave", GameTooltip_Hide)
end

local function CreateRow(parent, index, entry)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(PANEL_WIDTH - 40, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -(index - 1) * ROW_HEIGHT)
	row.action = entry.action

	row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.Label:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.Label:SetWidth(90)
	row.Label:SetJustifyH("RIGHT")
	row.Label:SetText(entry.label)

	row.KeyButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.KeyButton:SetSize(150, 22)
	row.KeyButton:SetPoint("LEFT", row.Label, "RIGHT", 12, 0)
	row.KeyButton:RegisterForClicks("LeftButtonUp")
	row.KeyButton:EnableKeyboard(false)
	row.KeyButton:SetPropagateKeyboardInput(true)
	row.KeyButton:SetScript("OnClick", function() StartListening(row) end)
	row.KeyButton:SetScript("OnKeyDown", function(_, key) OnKeyCaptured(row, key) end)
	row.KeyButton:SetScript("OnHide", StopListening)

	row.Current = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.Current:SetPoint("LEFT", row.KeyButton, "RIGHT", 10, 0)
	row.Current:SetJustifyH("LEFT")

	return row
end

local function Build()
	frame = CreateFrame("Frame", "FlightControlOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(PANEL_WIDTH, 478)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetScript("OnHide", StopListening)
	frame:SetFrameStrata("HIGH")
	frame:Hide()

	frame.TitleText:SetText("FlightControl")
	tinsert(UISpecialFrames, "FlightControlOptionsFrame") -- ESC closes it

	local intro = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	intro:SetPoint("TOPLEFT", 18, -32)
	intro:SetPoint("TOPRIGHT", -18, -32)
	intro:SetJustifyH("LEFT")
	intro:SetText("While flying, these keys take on these actions. Whatever they normally do "
		.. "moves onto the key the action came from, and everything reverts on landing.")
	intro:SetHeight(32)

	frame.Learn = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	frame.Learn:SetPoint("TOPLEFT", 18, -70)
	frame.Learn.text:SetText("Work it out from my keybindings")
	frame.Learn:SetScript("OnClick", function(self)
		if self:GetChecked() then
			FC.ClearCustom()
		else
			-- Declines if there is no cluster to copy; re-tick so the box never
			-- shows a custom layout that was not actually created.
			if FC.BeginCustom() then
				FC.Refresh()
			else
				self:SetChecked(true)
			end
		end
		FlightControlUI:Refresh()
	end)

	frame.Invert = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	frame.Invert:SetPoint("TOPLEFT", frame.Learn, "BOTTOMLEFT", 0, -2)
	frame.Invert.text:SetText("Invert pitch -- forward key dives, back key climbs")
	frame.Invert:SetScript("OnClick", function(self)
		FC.SetInvertPitch(self:GetChecked())
		FlightControlUI:Refresh()
	end)

	frame.Source = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	frame.Source:SetPoint("TOPLEFT", frame.Invert, "BOTTOMLEFT", 6, 2)

	local rowHost = CreateFrame("Frame", nil, frame)
	rowHost:SetPoint("TOPLEFT", 0, -152)
	rowHost:SetSize(PANEL_WIDTH, #FC.FLIGHT_ACTIONS * ROW_HEIGHT)
	for i, entry in ipairs(FC.FLIGHT_ACTIONS) do
		rows[i] = CreateRow(rowHost, i, entry)
	end

	local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", rowHost, "BOTTOMLEFT", 16, -4)
	hint:SetText("Click a key, then press one. Backspace clears it, Escape cancels.")

	local hint2 = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint2:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -2)
	hint2:SetText("Your real keybindings are never modified -- this is a temporary layer.")

	local previewLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	previewLabel:SetPoint("TOPLEFT", hint2, "BOTTOMLEFT", 0, -12)
	previewLabel:SetText("What changes while flying")

	frame.Preview = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.Preview:SetPoint("TOPLEFT", previewLabel, "BOTTOMLEFT", 6, -6)
	frame.Preview:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
	frame.Preview:SetJustifyH("LEFT")
	frame.Preview:SetJustifyV("TOP")
	frame.Preview:SetHeight(96)

	frame.Warning = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	frame.Warning:SetPoint("TOPLEFT", frame.Preview, "BOTTOMLEFT", 0, -4)
	frame.Warning:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
	frame.Warning:SetJustifyH("LEFT")
	frame.Warning:SetTextColor(1, 0.7, 0)

	frame.Relearn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.Relearn:SetSize(120, 22)
	frame.Relearn:SetPoint("BOTTOMLEFT", 18, 16)
	frame.Relearn:SetText("Reset to automatic")
	frame.Relearn:SetScript("OnClick", function()
		FC.ClearCustom()
		FlightControlUI:Refresh()
	end)
	Tooltip(frame.Relearn, "Reset to automatic",
		"Throw away your custom layout and go back to working the keys out from your "
		.. "keybindings. Nothing about your actual keybindings is changed.")

	Tooltip(frame.Learn, "Work it out from my keybindings",
		"On: the movement cluster is found from your own bindings every time they change, "
		.. "so this keeps working if you rebind things.|n|nOff: you choose each key below "
		.. "yourself, and it stays put.")

	Tooltip(frame.Invert, "Invert pitch",
		"Forward key dives and back key climbs, the way flight sims do it.|n|nOnly applies "
		.. "while the layout is being worked out automatically -- a layout you set by hand "
		.. "already says which key does what.")

	-- Footer version, so what is actually loaded can be read off the window
	-- rather than guessed at from what was last released.
	frame.Version = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	frame.Version:SetPoint("BOTTOM", frame, "BOTTOM", 0, 22)
	frame.Version:SetText("v" .. (FC.GetVersion and FC.GetVersion() or "?"))

	frame.Close2 = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.Close2:SetSize(100, 22)
	frame.Close2:SetPoint("BOTTOMRIGHT", -18, 16)
	frame.Close2:SetText("Close")
	frame.Close2:SetScript("OnClick", function() frame:Hide() end)
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

FlightControlUI = {}

function FlightControlUI:Refresh()
	if not frame then return end

	local custom = FC.IsCustom()
	frame.Learn:SetChecked(not custom)

	-- Inverting is a derivation setting. A pinned layout already says outright
	-- which key does which, so there is nothing left for it to flip.
	frame.Invert:SetChecked(FC.GetInvertPitch())
	frame.Invert:SetEnabled(not custom)
	frame.Invert.text:SetTextColor(custom and 0.5 or 1, custom and 0.5 or 0.82,
		custom and 0.5 or 0)

	frame.Source:SetText(FC.GetLayoutSource() or "")

	-- action -> key, from whichever layout is in force
	local assigned = {}
	for _, entry in ipairs(FC.GetLayout()) do
		assigned[entry.action] = entry.key
	end

	for _, row in ipairs(rows) do
		if row ~= listeningRow then
			local key = assigned[row.action]
			row.KeyButton:SetText(key and GetBindingText(key) or "not set")
			row.KeyButton:SetEnabled(custom)

			if key then
				local groundAction = GetBindingAction(key)
				if groundAction and groundAction ~= "" then
					row.Current:SetText("on the ground: " .. groundAction)
				else
					row.Current:SetText("unbound on the ground")
				end
			else
				row.Current:SetText("")
			end
		end
	end

	local plan = FC.GetPlan()
	if #plan == 0 then
		frame.Preview:SetText("|cff888888Nothing changes -- your keys already do this.|r")
	else
		local lines = {}
		for _, entry in ipairs(plan) do
			lines[#lines + 1] = ("%s  |cff888888->|r  %s"):format(GetBindingText(entry.key), entry.action)
		end
		frame.Preview:SetText(table.concat(lines, "\n"))
	end

	local stranded = FC.GetStranded()
	if #stranded > 0 then
		frame.Warning:SetText("Left with no key while flying: " .. table.concat(stranded, ", "))
	else
		frame.Warning:SetText("")
	end
end

function FlightControlUI:Toggle()
	if not frame then Build() end
	if frame:IsShown() then
		frame:Hide()
	else
		self:Refresh()
		frame:Show()
	end
end
