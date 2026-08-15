local ADDON, ns = ...

--------------------------------------------------------------------------------
-- Secure button
--------------------------------------------------------------------------------

-- Attributes pushed while out of combat:
--
--   count      markers in the active preset
--   mt1..mtN   pre-built macro text for each step
--   clearmacro macro text that wipes every world marker
--   pos        how far through the sequence we are (0 = nothing placed yet)
local button = CreateFrame("Button", "MarkrButton", UIParent, "SecureActionButtonTemplate")
button:SetSize(1, 1)
button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
button:SetAlpha(0)
button:EnableMouse(false)
button:RegisterForClicks("AnyDown")
button:SetAttribute("type", "macro")
button:SetAttribute("macrotext", "")
button:SetAttribute("clearmacro",
	((SLASH_CLEAR_WORLD_MARKER1 or "/cwm") .. " " .. (ALL or "All")))
button:SetAttribute("count", 0)
button:SetAttribute("pos", 0)
ns.button = button

SecureHandlerWrapScript(button, "OnClick", button, [[
	if button == "RightButton" then
		self:SetAttribute("pos", 0)
		self:SetAttribute("macrotext", self:GetAttribute("clearmacro"))
		return
	end

	if button == "MiddleButton" then
		self:SetAttribute("pos", 0)
		self:SetAttribute("macrotext", "")
		return
	end

	local count = self:GetAttribute("count") or 0
	if count < 1 then
		self:SetAttribute("macrotext", "")
		return
	end

	local pos = (self:GetAttribute("pos") or 0) + 1
	if pos > count then
		pos = 1
	end
	self:SetAttribute("pos", pos)
	self:SetAttribute("macrotext", self:GetAttribute("mt" .. pos))
]])

local pendingApply = false

-- The sequence the button is currently loaded with, which PostClick reports from.
local sequence = {}

function ns.ApplyPreset()
	if not ns.db then return end

	if InCombatLockdown() then
		pendingApply = true
		return
	end
	pendingApply = false

	sequence = ns.ActiveMarkers(ns.GetActivePreset())

	local wm = SLASH_WORLD_MARKER1 or "/wm"
	local prefix = (ns.db.placement == "cursor") and (wm .. " [@cursor] ") or (wm .. " ")

	for i = 1, ns.MARKER_COUNT do
		button:SetAttribute("mt" .. i, sequence[i] and (prefix .. sequence[i]) or nil)
	end
	button:SetAttribute("count", #sequence)
	button:SetAttribute("pos", 0)
	button:SetAttribute("macrotext", "")

	if ns.Config then ns.Config:Refresh() end
end

function ns.ResetSequence()
	if InCombatLockdown() then
		ns.Print("Cannot reset the sequence during combat. Use your reset hotkey instead.")
		return
	end
	button:SetAttribute("pos", 0)
	ns.Print("Sequence restarted.")
end

--------------------------------------------------------------------------------
-- Announcements
--------------------------------------------------------------------------------

-- Rate limited per message, not globally.
local lastWarning = {}
local function Throttled(fmt)
	local now = GetTime()
	if now - (lastWarning[fmt] or 0) < 5 then return true end
	lastWarning[fmt] = now
	return false
end

local function Warn(fmt, ...)
	if not Throttled(fmt) then ns.Print(fmt, ...) end
end

-- Red brand, for warnings that fire mid-spam.
local function Alert(fmt, ...)
	if not Throttled(fmt) then ns.Alert(fmt, ...) end
end

-- These codes are generic, so one only counts as ours if we pressed within
-- ERROR_WINDOW.
local PLACE_ERROR = { [61] = true, [278] = true, [1054] = true }
local ERROR_WINDOW = 1.0
local lastPress = 0

local watch = CreateFrame("Frame")
watch:RegisterEvent("UI_ERROR_MESSAGE")
watch:RegisterEvent("PLAYER_REGEN_ENABLED")
watch:SetScript("OnEvent", function(_, event, messageType)
	if event == "PLAYER_REGEN_ENABLED" then
		if pendingApply then ns.ApplyPreset() end
		return
	end

	if not PLACE_ERROR[messageType] then return end
	if GetTime() - lastPress > ERROR_WINDOW then return end

	Alert("Placing too fast -- the server is refusing some markers.")
end)

button:SetScript("PostClick", function(self, mouseButton)
	if not ns.db then return end

	-- Clearing is refused under the same rank rules as placing and fails silently.
	if mouseButton == "RightButton" then
		if not IsInGroup() then
			Warn("World markers only exist in a group, so there is nothing to clear.")
		elseif IsInRaid() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
			Warn("You need to be raid leader or an assistant to clear world markers.")
		elseif ns.db.announce then
			ns.Print("Cleared all world markers.")
		end
		return
	end

	if mouseButton ~= "LeftButton" then return end

	if not IsInGroup() then
		Warn("You have to be in a group to place world markers.")
		return
	end

	if IsInRaid() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
		Warn("You need to be raid leader or an assistant to place world markers.")
		return
	end

	local count = self:GetAttribute("count") or 0
	if count == 0 then
		Warn("Every marker in the active preset is switched off. Turn some on with /markr.")
		return
	end

	local pos = self:GetAttribute("pos") or 0
	local marker = sequence[pos]
	if not marker then return end

	-- Announced for whatever the press asked for, in and out of combat.
	lastPress = GetTime()
	if ns.db.announce then
		ns.Print("%s (%d/%d)", ns.MarkerName(marker, true), pos, count)
	end
end)
