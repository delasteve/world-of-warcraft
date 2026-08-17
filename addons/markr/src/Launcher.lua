local ADDON, ns = ...

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------

local MINIMAP_RADIUS = 80

local minimapButton

-- A button bar that gathers minimap icons takes this one by reparenting it, and
-- anchoring to the minimap from inside such a bar places the button outside it.
local function OnTheMinimap()
	return minimapButton:GetParent() == Minimap
end

local function PositionMinimapButton()
	if not OnTheMinimap() then return end

	local angle = math.rad(ns.db.minimap.angle or 200)
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER",
		math.cos(angle) * MINIMAP_RADIUS, math.sin(angle) * MINIMAP_RADIUS)
end

-- Tracks the cursor's bearing from the minimap's center, so the button stays on
-- the ring no matter where the cursor wanders.
local function TrackCursor()
	local centerX, centerY = Minimap:GetCenter()
	if not centerX then return end

	local scale = Minimap:GetEffectiveScale()
	local x, y = GetCursorPosition()
	ns.db.minimap.angle = math.deg(math.atan2(y / scale - centerY, x / scale - centerX)) % 360
	PositionMinimapButton()
end

local function CreateMinimapButton()
	minimapButton = CreateFrame("Button", "MarkrMinimapButton", Minimap)
	minimapButton:SetSize(31, 31)
	minimapButton:SetFrameStrata("MEDIUM")
	minimapButton:SetFrameLevel(8)
	minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	minimapButton:RegisterForDrag("LeftButton")

	local background = minimapButton:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

	-- Drawn at the background circle's full 20px: the glyph keeps to 70% of its own
	-- frame, so the ring cannot clip it.
	local icon = minimapButton:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", 7, -5)
	icon:SetTexture(ns.ICON)

	local border = minimapButton:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	minimapButton:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			ns.ResetSequence()
		else
			ns.Config:Toggle()
		end
	end)

	minimapButton:SetScript("OnDragStart", function(self)
		if not OnTheMinimap() then return end
		self:SetScript("OnUpdate", TrackCursor)
		GameTooltip:Hide()
	end)
	minimapButton:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)

	minimapButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(ns.Branded(), 1, 1, 1)
		local preset = ns.GetActivePreset()
		if preset then
			GameTooltip:AddLine(("Active preset: |cffffff00%s|r (%d markers)")
				:format(preset.name, #ns.ActiveMarkers(preset)), nil, nil, nil, true)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Left click: open settings", 0.6, 0.6, 0.6)
		GameTooltip:AddLine("Right click: restart the sequence", 0.6, 0.6, 0.6)
		if OnTheMinimap() then
			GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
		end
		GameTooltip:Show()
	end)
	minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

--------------------------------------------------------------------------------
-- Addon compartment
--------------------------------------------------------------------------------

-- Wired up by the `## AddonCompartment*` lines in Markr.toc, which name globals.
function Markr_OnAddonCompartmentClick()
	ns.Config:Toggle()
end

function Markr_OnAddonCompartmentEnter(_, menuButton)
	GameTooltip:SetOwner(menuButton or UIParent, "ANCHOR_LEFT")
	GameTooltip:SetText(ns.Branded(), 1, 1, 1)
	local preset = ns.GetActivePreset()
	if preset then
		GameTooltip:AddLine(("Active preset: |cffffff00%s|r (%d markers)")
			:format(preset.name, #ns.ActiveMarkers(preset)), nil, nil, nil, true)
	end
	GameTooltip:AddLine("Click to open the settings.", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

function Markr_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

--------------------------------------------------------------------------------
-- Options > AddOns entry
--------------------------------------------------------------------------------

-- A signpost to the addon's own window.
local function RegisterOptionsCategory()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		return
	end

	local panel = CreateFrame("Frame")
	panel.name = "Markr"

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(ns.Branded())

	local body = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	body:SetWidth(520)
	body:SetJustifyH("LEFT")
	body:SetText("Presets, marker order, placement and hotkeys all live in Markr's own window.")

	local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	open:SetSize(200, 26)
	open:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -16)
	open:SetText("Open Markr Settings")
	open:SetScript("OnClick", function()
		if SettingsPanel then HideUIPanel(SettingsPanel) end
		ns.Config:Open()
	end)

	local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -12)
	hint:SetText("You can also type /markr, click the minimap button, or use the addon compartment.")

	local category = Settings.RegisterCanvasLayoutCategory(panel, "Markr")
	category.ID = "Markr"
	Settings.RegisterAddOnCategory(category)
end

--------------------------------------------------------------------------------
-- Load
--------------------------------------------------------------------------------

function ns.InitLaunchers()
	RegisterOptionsCategory()
	CreateMinimapButton()
	PositionMinimapButton()
end
