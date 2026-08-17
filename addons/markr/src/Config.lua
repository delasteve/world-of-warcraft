local ADDON, ns = ...

local Config = {}
ns.Config = Config

local frame
local markerSlots, bindingRows = {}, {}
local selectedPreset

local PANEL_WIDTH = 440
local PANEL_HEIGHT = 506
local TITLE_HEIGHT = 34
local PAD = 18
local CONTENT_WIDTH = PANEL_WIDTH - PAD * 2 -- 404
local CARD_PAD = 14
local CARD_WIDTH = CONTENT_WIDTH - CARD_PAD * 2 -- 376

-- Eight slots span a card's inner width exactly, and DropTarget() rederives the
-- destination from these two numbers.
local SLOT_SIZE = 40
local SLOT_GAP = 8

--------------------------------------------------------------------------------
-- Theme
--------------------------------------------------------------------------------

-- Every shade above the window base is white at low alpha, so one background
-- color change carries the whole palette with it. The base itself is opaque.
local UI = {
	window      = { 0.055, 0.060, 0.070, 1 },
	titleBar    = { 1, 1, 1, 0.035 },
	card        = { 1, 1, 1, 0.025 },
	border      = { 1, 1, 1, 0.09 },
	control     = { 1, 1, 1, 0.07 },
	controlOver = { 1, 1, 1, 0.14 },
	controlDown = { 1, 1, 1, 0.03 },
	slot        = { 1, 1, 1, 0.05 },
	-- The one exception to the white-alpha rule: the menu can open past the
	-- window's edge, so it needs its own ground rather than a tint of one.
	menu        = { 0.075, 0.081, 0.094, 1 },
	text        = { 0.87, 0.88, 0.90 },
	dim         = { 0.46, 0.48, 0.52 },
	-- Ink for text on an accent fill; OnAccent picks between the two.
	inkOnLight  = { 0.04, 0.05, 0.06 },
	inkOnDark   = { 0.97, 0.98, 1.00 },
	warn        = { 1.00, 0.55, 0.20 },
}

UI.accent = { ns.COLOR.r, ns.COLOR.g, ns.COLOR.b, 1 }

-- Window-only art, so it lives here rather than beside ns.ICON. The `.png`
-- extension is load-bearing: a PNG path will not resolve without it.
local CHEVRON_TEXTURE = "Interface\\AddOns\\Markr\\Textures\\Chevron.png"
local CLOSE_TEXTURE = "Interface\\AddOns\\Markr\\Textures\\Close.png"

local function Shade(color, alpha)
	return color[1], color[2], color[3], alpha or color[4] or 1
end

-- Perceived brightness, which weights green far above blue.
local function OnAccent()
	local r, g, b = UI.accent[1], UI.accent[2], UI.accent[3]
	return (0.299 * r + 0.587 * g + 0.114 * b) > 0.55 and UI.inkOnLight or UI.inkOnDark
end

-- For the `|cff` escapes, which take hex and not the four numbers everything else
-- here is painted with.
local function AccentHex()
	return ("%02x%02x%02x"):format(
		math.floor(UI.accent[1] * 255 + 0.5),
		math.floor(UI.accent[2] * 255 + 0.5),
		math.floor(UI.accent[3] * 255 + 0.5))
end

--------------------------------------------------------------------------------
-- Skin
--------------------------------------------------------------------------------

-- The regions painted in the accent that no Refresh already repaints.
local themePainters = {}

local function Themed(paint)
	themePainters[#themePainters + 1] = paint
	paint()
end

local function RepaintTheme()
	for _, paint in ipairs(themePainters) do paint() end
	Config:Refresh()
end

ns.Skin.OnLooksChanged(function()
	local r, g, b = ns.Skin.AccentColor()
	if r then UI.accent = { r, g, b } end
	RepaintTheme()
end)

--------------------------------------------------------------------------------
-- Pixel grid
--------------------------------------------------------------------------------

-- Every size and every non-zero offset is rounded to a whole number of pixels
-- before it reaches the widget, because a UI unit is not a screen pixel. Anchors
-- with no offset (`SetPoint("TOPLEFT")` and friends) sit exactly on the parent's
-- edge and need none of this.

local screenHeight

-- One physical pixel, in the UI units a region at this effective scale is measured
-- in. Resolved on first use rather than at load, since the window is built lazily.
local function PixelUnit(scale)
	screenHeight = screenHeight or select(2, GetPhysicalScreenSize())
	return 768 / (screenHeight or 768) / scale
end

-- `minPixels` is for the hairlines: a low enough UI scale would round one UI unit
-- down to nothing, so they are held at a pixel instead.
local function Snap(value, scale, minPixels)
	local unit = PixelUnit(scale)
	local pixels = math.floor(value / unit + 0.5)
	if minPixels and pixels > -minPixels and pixels < minPixels then
		pixels = (value < 0) and -minPixels or minPixels
	end
	return pixels * unit
end

-- Each call keeps the closure that produced it so Repixel can replay the lot.
-- Records are keyed by what they set, so a widget laid out again -- the preset menu
-- rows are, on every open -- replaces its entry instead of stacking up.
local pixelOwners, pixelLayout = {}, {}

local function Record(region, key, apply)
	local record = pixelLayout[region]
	if not record then
		record = {}
		pixelLayout[region] = record
		pixelOwners[#pixelOwners + 1] = region
	end
	record[key] = apply
	apply()
end

local function PixelSize(region, width, height)
	Record(region, "size", function()
		local scale = region:GetEffectiveScale()
		region:SetSize(Snap(width, scale), Snap(height, scale))
	end)
end

local function PixelWidth(region, width, minPixels)
	Record(region, "width", function()
		region:SetWidth(Snap(width, region:GetEffectiveScale(), minPixels))
	end)
end

local function PixelHeight(region, height, minPixels)
	Record(region, "height", function()
		region:SetHeight(Snap(height, region:GetEffectiveScale(), minPixels))
	end)
end

-- Takes either SetPoint shape: (point, x, y) or (point, relativeTo, relativePoint, x, y).
local function PixelPoint(region, point, a, b, c, d)
	local relativeTo, relativePoint, x, y
	if type(a) == "number" or a == nil then
		x, y = a or 0, b or 0
	else
		relativeTo, relativePoint, x, y = a, b, c or 0, d or 0
	end

	Record(region, point, function()
		local scale = region:GetEffectiveScale()
		local offsetX, offsetY = Snap(x, scale), Snap(y, scale)
		if relativeTo then
			region:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
		else
			region:SetPoint(point, offsetX, offsetY)
		end
	end)
end

-- Drops the anchor records with the anchors, so a re-layout that uses a different
-- set of points -- the menu flipping from below the picker to above it -- does not
-- leave the old one to be replayed on top of the new one.
local SIZE_KEYS = { size = true, width = true, height = true }

local function PixelClearPoints(region)
	local record = pixelLayout[region]
	if record then
		for key in pairs(record) do
			if not SIZE_KEYS[key] then record[key] = nil end
		end
	end
	region:ClearAllPoints()
end

local function Repixel()
	screenHeight = nil
	for _, region in ipairs(pixelOwners) do
		for _, apply in pairs(pixelLayout[region]) do apply() end
	end
end

--------------------------------------------------------------------------------
-- Flat drawing helpers
--------------------------------------------------------------------------------

local function Fill(owner, layer, color)
	local texture = owner:CreateTexture(nil, layer or "BACKGROUND")
	texture:SetAllPoints()
	if color then texture:SetColorTexture(Shade(color)) end
	return texture
end

-- A hairline rectangle from four one-unit textures. The handle it returns recolors
-- and shows or hides all four at once.
local function AddBorder(owner, color, layer)
	local lines = {}

	for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local line = owner:CreateTexture(nil, layer or "BORDER")
		line:SetColorTexture(Shade(color))
		if edge == "TOP" or edge == "BOTTOM" then
			PixelHeight(line, 1, 1)
			line:SetPoint(edge .. "LEFT")
			line:SetPoint(edge .. "RIGHT")
		else
			PixelWidth(line, 1, 1)
			line:SetPoint("TOP" .. edge)
			line:SetPoint("BOTTOM" .. edge)
		end
		lines[#lines + 1] = line
	end

	return {
		SetColor = function(_, ...)
			for _, line in ipairs(lines) do line:SetColorTexture(...) end
		end,
		SetShown = function(_, shown)
			for _, line in ipairs(lines) do line:SetShown(shown) end
		end,
	}
end

-- Every white font object also carries a black drop shadow, meant to hold up over
-- the 3D world. On these flat fills it only smears the glyph edges, so it is
-- cleared here rather than left on, after the skin's font so the clearing lands last.
local function CreateText(parent, text, font, color)
	local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
	ns.Skin.Font(label)
	label:SetShadowColor(0, 0, 0, 0)
	label:SetShadowOffset(0, 0)
	label:SetText(text)
	label:SetTextColor(Shade(color or UI.text))
	return label
end

-- The outline is dark, and so is the ink on a light accent, which fills the glyph
-- in solid.
local function FlattenOutline(label)
	local path, size = label:GetFont()
	if path and size then label:SetFont(path, size, "") end
end

local function CreateHeading(parent, text, x, y)
	local label = CreateText(parent, text:upper(), "GameFontHighlightSmall", UI.accent)
	PixelPoint(label, "TOPLEFT", x, y)
	Themed(function() label:SetTextColor(Shade(UI.accent)) end)
	return label
end

local function SetTooltip(widget, title, body)
	widget.tooltipTitle, widget.tooltipBody = title, body
end

-- Stored on the widget rather than claiming OnEnter/OnLeave, which the widgets
-- here need for their own hover art.
local function ShowTooltip(widget)
	if not widget.tooltipTitle then return end
	GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
	GameTooltip:SetText(widget.tooltipTitle, 1, 1, 1)
	if widget.tooltipBody then
		GameTooltip:AddLine(widget.tooltipBody, 0.7, 0.7, 0.7, true)
	end
	GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Flat widgets
--------------------------------------------------------------------------------

local function CreateCard(parent, heading, x, y, height)
	local card = CreateFrame("Frame", nil, parent)
	PixelSize(card, CONTENT_WIDTH, height)
	PixelPoint(card, "TOPLEFT", x, y)
	if not ns.Skin.Panel(card) then
		Fill(card, "BACKGROUND", UI.card)
		AddBorder(card, UI.border)
	end
	CreateHeading(card, heading, CARD_PAD, -11)
	return card
end

-- `primary` is the only place in the window anything is filled solid.
local function CreateButton(parent, text, width, height, onClick, primary)
	local button = CreateFrame("Button", nil, parent)
	PixelSize(button, width, height)

	button.bg = Fill(button, "BACKGROUND")
	button.border = AddBorder(button, UI.border)
	button.label = CreateText(button, text, "GameFontHighlight")
	button.label:SetPoint("CENTER")
	button.primary = primary
	if primary then FlattenOutline(button.label) end

	function button:UpdateVisuals(state)
		if not self:IsEnabled() then
			self.bg:SetColorTexture(Shade(UI.control, 0.03))
			self.border:SetColor(Shade(UI.border, 0.05))
			self.label:SetTextColor(Shade(UI.dim, 0.6))
		elseif self.primary then
			self.bg:SetColorTexture(Shade(UI.accent, state == "over" and 1 or 0.85))
			self.border:SetColor(Shade(UI.accent))
			self.label:SetTextColor(Shade(OnAccent()))
		else
			local shade = (state == "over" and UI.controlOver)
				or (state == "down" and UI.controlDown)
				or UI.control
			self.bg:SetColorTexture(Shade(shade))
			self.border:SetColor(Shade(UI.border))
			self.label:SetTextColor(Shade(UI.text))
		end
	end

	function button:SetLabel(value)
		self.label:SetText(value)
	end

	button:SetScript("OnEnter", function(self)
		self:UpdateVisuals("over")
		ShowTooltip(self)
	end)
	button:SetScript("OnLeave", function(self)
		self:UpdateVisuals()
		GameTooltip:Hide()
	end)
	button:SetScript("OnMouseDown", function(self) self:UpdateVisuals("down") end)
	button:SetScript("OnMouseUp", function(self) self:UpdateVisuals("over") end)
	button:SetScript("OnEnable", function(self) self:UpdateVisuals() end)
	button:SetScript("OnDisable", function(self) self:UpdateVisuals() end)
	button:SetScript("OnClick", onClick)

	button:UpdateVisuals()
	-- Only the primary state takes the accent; the rest repaint on hover and on enable.
	if primary then Themed(function() button:UpdateVisuals() end) end
	return button
end

-- A plain Button carrying its own boolean.
local function CreateToggle(parent, text, x, y, onToggle)
	local toggle = CreateFrame("Button", nil, parent)
	PixelPoint(toggle, "TOPLEFT", x, y)
	PixelHeight(toggle, 18)

	local box = CreateFrame("Frame", nil, toggle)
	PixelSize(box, 16, 16)
	box:SetPoint("LEFT")
	box.bg = Fill(box, "BACKGROUND", UI.control)
	box.border = AddBorder(box, UI.border)

	box.fill = box:CreateTexture(nil, "ARTWORK")
	PixelPoint(box.fill, "TOPLEFT", 4, -4)
	PixelPoint(box.fill, "BOTTOMRIGHT", -4, 4)
	Themed(function() box.fill:SetColorTexture(Shade(UI.accent)) end)
	box.fill:Hide()

	toggle.label = CreateText(toggle, text, "GameFontHighlight")
	PixelPoint(toggle.label, "LEFT", box, "RIGHT", 8, 0)
	PixelWidth(toggle, 24 + toggle.label:GetStringWidth())

	function toggle:SetValue(value)
		self.checked = value and true or false
		box.fill:SetShown(self.checked)
		box.border:SetColor(Shade(self.checked and UI.accent or UI.border))
	end

	toggle:SetScript("OnEnter", function(self)
		box.bg:SetColorTexture(Shade(UI.controlOver))
		ShowTooltip(self)
	end)
	toggle:SetScript("OnLeave", function()
		box.bg:SetColorTexture(Shade(UI.control))
		GameTooltip:Hide()
	end)
	toggle:SetScript("OnClick", function(self)
		self:SetValue(not self.checked)
		onToggle(self.checked)
	end)

	toggle:SetValue(false)
	return toggle
end

-- One-of-many as a segmented bar.
local function CreateSegments(parent, entries, x, y, width, height, onSelect)
	local control = CreateFrame("Frame", nil, parent)
	PixelSize(control, width, height)
	PixelPoint(control, "TOPLEFT", x, y)
	Fill(control, "BACKGROUND", UI.control)
	AddBorder(control, UI.border)

	-- Inset by the border: segments are child frames, so their fill would draw over
	-- the control's own hairline rather than under it. Anchored by both edges rather
	-- than sized, so neighbors share one rounded boundary instead of leaving a seam.
	local segmentWidth = (width - 2) / #entries
	control.segments = {}

	for i, entry in ipairs(entries) do
		local segment = CreateFrame("Button", nil, control)
		PixelPoint(segment, "TOPLEFT", control, "TOPLEFT", 1 + (i - 1) * segmentWidth, -1)
		PixelPoint(segment, "BOTTOMRIGHT", control, "TOPLEFT", 1 + i * segmentWidth, -(height - 1))
		segment.value = entry.value
		segment.bg = Fill(segment, "BACKGROUND")
		segment.label = CreateText(segment, entry.text, "GameFontHighlight")
		segment.label:SetPoint("CENTER")
		FlattenOutline(segment.label)
		SetTooltip(segment, entry.text, entry.tooltip)

		function segment:Paint(hovered)
			if control.value == self.value then
				self.bg:SetColorTexture(Shade(UI.accent, 0.9))
				self.label:SetTextColor(Shade(OnAccent()))
			else
				self.bg:SetColorTexture(Shade(UI.control, hovered and 0.12 or 0))
				self.label:SetTextColor(Shade(hovered and UI.text or UI.dim))
			end
		end

		segment:SetScript("OnEnter", function(self)
			self:Paint(true)
			ShowTooltip(self)
		end)
		segment:SetScript("OnLeave", function(self)
			self:Paint()
			GameTooltip:Hide()
		end)
		segment:SetScript("OnClick", function(self) onSelect(self.value) end)

		control.segments[i] = segment
	end

	function control:SetValue(value)
		self.value = value
		for _, segment in ipairs(self.segments) do segment:Paint() end
	end

	return control
end

--------------------------------------------------------------------------------
-- Popups
--------------------------------------------------------------------------------

-- Ask the GameDialog methods first, then fall back to every older spelling. A
-- missing widget here fails silently rather than erroring.
local function PopupEditBox(popup)
	if not popup then return end
	local editBox = popup.GetEditBox and popup:GetEditBox()
	return editBox or popup.EditBox or popup.editBox
end

-- The edit box's handlers only get the edit box, and its parent is not reliably the
-- dialog -- the dialog it belongs to is.
local function PopupOf(editBox)
	if not editBox then return end
	local dialog = editBox.GetOwningDialog and editBox:GetOwningDialog()
	return dialog or editBox:GetParent()
end

local function AcceptEditBox(editBox)
	local popup = PopupOf(editBox)
	if not popup then return end
	local container = popup.ButtonContainer
	local accept = (popup.GetButton1 and popup:GetButton1())
		or popup.button1
		or (container and container.Buttons and container.Buttons[1])
		or (popup.GetName and popup:GetName() and _G[popup:GetName() .. "Button1"])
	if accept then accept:Click() end
end

local function CancelEditBox(editBox)
	local popup = PopupOf(editBox)
	if popup then popup:Hide() end
end

StaticPopupDialogs["MARKR_NEW_PRESET"] = {
	text = "Name for the new preset:",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 32,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	OnShow = function(self)
		local editBox = PopupEditBox(self)
		if not editBox then return end
		editBox:SetText("")
		editBox:SetFocus()
	end,
	OnAccept = function(self)
		local editBox = PopupEditBox(self)
		local name = strtrim(editBox and editBox:GetText() or "")
		if name == "" then
			ns.Print("A preset needs a name.")
			return
		end
		local index = ns.CreatePreset(name, self.data)
		ns.SetActivePreset(index)
		selectedPreset = index
		Config:Refresh()
	end,
	EditBoxOnEnterPressed = AcceptEditBox,
	EditBoxOnEscapePressed = CancelEditBox,
}

StaticPopupDialogs["MARKR_RENAME_PRESET"] = {
	text = "Rename preset:",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 32,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	OnShow = function(self)
		local editBox = PopupEditBox(self)
		if not editBox then return end
		local preset = ns.GetPresets()[self.data]
		editBox:SetText(preset and preset.name or "")
		editBox:HighlightText()
		editBox:SetFocus()
	end,
	OnAccept = function(self)
		local preset = ns.GetPresets()[self.data]
		local editBox = PopupEditBox(self)
		local name = strtrim(editBox and editBox:GetText() or "")
		if name == "" then
			ns.Print("A preset needs a name.")
			return
		end
		if preset then
			preset.name = name:sub(1, 32)
			Config:Refresh()
		end
	end,
	EditBoxOnEnterPressed = AcceptEditBox,
	EditBoxOnEscapePressed = CancelEditBox,
}

StaticPopupDialogs["MARKR_DELETE_PRESET"] = {
	text = "Delete the preset \"%s\"?",
	button1 = YES,
	button2 = NO,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	OnAccept = function(self)
		if ns.DeletePreset(self.data) then
			selectedPreset = ns.db.activePreset
			Config:Refresh()
		end
	end,
}

--------------------------------------------------------------------------------
-- Key binding capture
--------------------------------------------------------------------------------

local capture

local function BuildCombo(key)
	local combo = ""
	if IsAltKeyDown() then combo = combo .. "ALT-" end
	if IsControlKeyDown() then combo = combo .. "CTRL-" end
	if IsShiftKeyDown() then combo = combo .. "SHIFT-" end
	return combo .. key
end

local IGNORED_KEYS = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
	LALT = true, RALT = true, UNKNOWN = true,
}

local function FinishCapture(combo)
	local action = capture.action
	capture:Hide()
	if not action or not combo then return end

	local ok, displaced, reason = ns.SetBindingFor(action, combo)
	if not ok then
		if reason == "combat" then
			ns.Print("Cannot change key bindings during combat.")
		else
			ns.Print("Could not bind %s.", combo)
		end
		return
	end

	if displaced then
		ns.Print("%s was taken from |cffffff00%s|r.", combo, _G["BINDING_NAME_" .. displaced] or displaced)
	end
	Config:Refresh()
end

local function CreateCapture()
	capture = CreateFrame("Frame", nil, UIParent)
	capture:SetFrameStrata("FULLSCREEN_DIALOG")
	capture:SetAllPoints(UIParent)
	capture:EnableKeyboard(true)
	capture:EnableMouse(true)
	capture:SetPropagateKeyboardInput(false)
	capture:Hide()

	local shade = capture:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(0, 0, 0, 0.7)

	capture.label = capture:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	capture.label:SetPoint("CENTER")
	capture.label:SetJustifyH("CENTER")

	capture:SetScript("OnKeyDown", function(self, key)
		if key == "ESCAPE" then
			self:Hide()
		elseif not IGNORED_KEYS[key] then
			FinishCapture(BuildCombo(key))
		end
	end)

	-- Left click backs out; the extra mouse buttons are fair game as hotkeys.
	capture:SetScript("OnMouseDown", function(self, mouseButton)
		if mouseButton == "Button4" or mouseButton == "Button5" then
			FinishCapture(BuildCombo(mouseButton:upper()))
		else
			self:Hide()
		end
	end)
end

local function StartCapture(action, label)
	if not capture then CreateCapture() end
	if InCombatLockdown() then
		ns.Print("Cannot change key bindings during combat.")
		return
	end
	capture.action = action
	capture.label:SetText(("Press a key for %s\n|cff777777Esc or left click to cancel|r")
		:format(ns.Branded(label, AccentHex())))
	capture:Show()
end

--------------------------------------------------------------------------------
-- Preset picker
--------------------------------------------------------------------------------

local function EditedPreset()
	return ns.GetPresets()[selectedPreset]
end

-- Only the active preset needs pushing back into the secure button.
local function CommitEdit()
	if selectedPreset == ns.db.activePreset then
		ns.ApplyPreset()
	end
	Config:Refresh()
end

local function DuplicateSelected()
	local preset = EditedPreset()
	if not preset then return end
	-- Deep copy: a shallow one would share entry tables with the source preset.
	local copy = {}
	for i, entry in ipairs(preset.markers) do
		copy[i] = { marker = entry.marker, on = entry.on }
	end
	StaticPopup_Show("MARKR_NEW_PRESET", nil, nil, copy)
end

local MENU_ROW_HEIGHT = 24
local MENU_PAD = 5

local menuLayer, menu
local menuRows = {}

local function CloseMenu()
	if menuLayer then menuLayer:Hide() end
end

local MENU_ACTIONS = {
	{ text = "New preset...", handler = function()
		StaticPopup_Show("MARKR_NEW_PRESET", nil, nil, {})
	end },
	{ text = "Duplicate selected", handler = function() DuplicateSelected() end },
}

-- The open state is the closed texture flipped vertically.
local function PointChevron(picker, up)
	if picker then
		picker.chevron:SetTexCoord(0, 1, up and 1 or 0, up and 0 or 1)
	end
end

local function BuildMenu()
	-- Clicking anywhere off the menu closes it; hiding this hides the menu with it.
	menuLayer = CreateFrame("Button", nil, UIParent)
	menuLayer:SetAllPoints(UIParent)
	menuLayer:SetFrameStrata("FULLSCREEN_DIALOG")
	menuLayer:RegisterForClicks("AnyUp")
	menuLayer:SetScript("OnClick", CloseMenu)
	menuLayer:SetScript("OnHide", function()
		PointChevron(frame and frame.picker, false)
	end)
	menuLayer:Hide()

	menu = CreateFrame("Frame", nil, menuLayer)
	menu:SetFrameLevel(menuLayer:GetFrameLevel() + 10)
	if not ns.Skin.Panel(menu) then
		Fill(menu, "BACKGROUND", UI.menu)
		AddBorder(menu, UI.border)
	end

	menu.divider = menu:CreateTexture(nil, "ARTWORK")
	PixelHeight(menu.divider, 1, 1)
	menu.divider:SetColorTexture(Shade(UI.border))
end

local function AcquireMenuRow(index)
	local row = menuRows[index]
	if row then return row end

	row = CreateFrame("Button", nil, menu)

	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.07)

	-- Marks the selected preset.
	row.mark = row:CreateTexture(nil, "ARTWORK")
	PixelWidth(row.mark, 2, 1)
	row.mark:SetPoint("TOPLEFT")
	row.mark:SetPoint("BOTTOMLEFT")
	Themed(function() row.mark:SetColorTexture(Shade(UI.accent)) end)

	row.label = CreateText(row, "", "GameFontHighlight")
	PixelPoint(row.label, "LEFT", 12, 0)
	PixelPoint(row.label, "RIGHT", -10, 0)
	row.label:SetJustifyH("LEFT")

	row:SetScript("OnEnter", function(self) self.label:SetTextColor(Shade(UI.text)) end)
	row:SetScript("OnLeave", function(self) self.label:SetTextColor(Shade(self.baseColor)) end)

	menuRows[index] = row
	return row
end

local function LayoutMenuRow(index, y, text, color, marked, onClick)
	local row = AcquireMenuRow(index)

	-- Anchored top and bottom rather than given a height, so tiled rows share one
	-- rounded boundary. Every offset is measured from the menu's TOPLEFT, the bottom
	-- edge included -- the shorthand `SetPoint("BOTTOMLEFT", x, y)` would measure that
	-- one up from the menu's *bottom* and stretch each row past the background.
	PixelClearPoints(row)
	PixelPoint(row, "TOPLEFT", menu, "TOPLEFT", 1, -y)
	PixelPoint(row, "TOPRIGHT", menu, "TOPRIGHT", -1, -y)
	PixelPoint(row, "BOTTOMLEFT", menu, "TOPLEFT", 1, -(y + MENU_ROW_HEIGHT))
	row.label:SetText(text)
	row.baseColor = color
	row.label:SetTextColor(Shade(color))
	row.mark:SetShown(marked)
	row:SetScript("OnClick", function()
		CloseMenu()
		onClick()
	end)
	row:Show()
	return y + MENU_ROW_HEIGHT
end

local function OpenMenu(picker)
	if not menu then BuildMenu() end

	local y, count = MENU_PAD, 0

	for index, preset in ipairs(ns.GetPresets()) do
		local text = preset.name
		if index == ns.db.activePreset then
			text = text .. "  " .. ns.Branded("(active)", AccentHex())
		end
		count = count + 1
		y = LayoutMenuRow(count, y, text,
			index == selectedPreset and UI.text or UI.dim,
			index == selectedPreset,
			function()
				selectedPreset = index
				Config:Refresh()
			end)
	end

	y = y + MENU_PAD
	PixelClearPoints(menu.divider)
	PixelPoint(menu.divider, "TOPLEFT", 8, -y)
	PixelPoint(menu.divider, "TOPRIGHT", -8, -y)
	y = y + MENU_PAD + 1

	for _, action in ipairs(MENU_ACTIONS) do
		count = count + 1
		y = LayoutMenuRow(count, y, action.text, UI.dim, false, action.handler)
	end

	for i = count + 1, #menuRows do
		menuRows[i]:Hide()
	end

	PixelSize(menu, picker:GetWidth(), y + MENU_PAD)

	-- Drop upward instead when a long preset list would run off the bottom.
	local below = picker:GetBottom()
	PixelClearPoints(menu)
	if below and below - menu:GetHeight() < 16 then
		PixelPoint(menu, "BOTTOMLEFT", picker, "TOPLEFT", 0, 2)
	else
		PixelPoint(menu, "TOPLEFT", picker, "BOTTOMLEFT", 0, -2)
	end

	PointChevron(picker, true)
	menuLayer:Show()
end

local function CreatePresetPicker(parent, width, height)
	local picker = CreateButton(parent, "", width, height, function(self)
		OpenMenu(self)
	end)

	PixelClearPoints(picker.label)
	PixelPoint(picker.label, "LEFT", 10, 0)
	PixelPoint(picker.label, "RIGHT", -24, 0)
	picker.label:SetJustifyH("LEFT")

	picker.chevron = picker:CreateTexture(nil, "ARTWORK")
	PixelSize(picker.chevron, 16, 16)
	PixelPoint(picker.chevron, "RIGHT", -10, 0)
	picker.chevron:SetTexture(CHEVRON_TEXTURE)
	picker.chevron:SetVertexColor(Shade(UI.dim))

	return picker
end

--------------------------------------------------------------------------------
-- Sequence editing
--------------------------------------------------------------------------------

-- Insert-and-shuffle: the entry is lifted out and put back at `to`, shifting
-- everything in between by one.
local function MoveMarkerTo(from, to)
	local preset = EditedPreset()
	if not preset or not from or not to then return end

	local count = #preset.markers
	if from < 1 or from > count then return end
	if to < 1 then to = 1 elseif to > count then to = count end
	if to == from then return end

	table.insert(preset.markers, to, table.remove(preset.markers, from))
	CommitEdit()
end

-- Flips a flag in place; switching a marker off never reorders anything.
local function ToggleMarker(position)
	local preset = EditedPreset()
	local entry = preset and preset.markers[position]
	if not entry then return end
	entry.on = not entry.on
	CommitEdit()
end

--------------------------------------------------------------------------------
-- Sequence drag and drop
--------------------------------------------------------------------------------

-- There is no drop-target event for a drag between plain frames, so the destination
-- slot is derived from the cursor against the strip's own rect.
local dragFrom, dragGhost

local function DropTarget()
	local holder = frame.markerHolder
	local left, bottom = holder:GetLeft(), holder:GetBottom()
	if not left or not bottom then return nil end

	local scale = holder:GetEffectiveScale()
	local x, y = GetCursorPosition()
	x, y = x / scale, y / scale

	-- Letting go well clear of the strip cancels rather than snapping to slot 1 or 8.
	if y < bottom - SLOT_SIZE or y > bottom + holder:GetHeight() + SLOT_SIZE then
		return nil
	end

	return math.floor((x - left) / (SLOT_SIZE + SLOT_GAP)) + 1
end

local function DragGhost()
	if dragGhost then return dragGhost end

	dragGhost = CreateFrame("Frame", nil, UIParent)
	PixelSize(dragGhost, SLOT_SIZE, SLOT_SIZE)
	dragGhost:SetFrameStrata("TOOLTIP")
	dragGhost:Hide()

	dragGhost.icon = dragGhost:CreateTexture(nil, "ARTWORK")
	dragGhost.icon:SetAllPoints()
	dragGhost.icon:SetAlpha(0.85)

	dragGhost:SetScript("OnUpdate", function(self)
		local scale = self:GetEffectiveScale()
		local x, y = GetCursorPosition()
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	end)

	return dragGhost
end

local function BeginDrag(index)
	local preset = EditedPreset()
	local entry = preset and preset.markers[index]
	if not entry then return end

	dragFrom = index

	local ghost = DragGhost()
	ghost.icon:SetTexture(ns.MarkerIcon(entry.marker))
	ghost.icon:SetDesaturated(not entry.on)
	ghost:Show()

	markerSlots[index].icon:SetAlpha(0.25)
end

local function EndDrag()
	if dragGhost then dragGhost:Hide() end

	local from = dragFrom
	dragFrom = nil
	if not from then return end

	MoveMarkerTo(from, DropTarget())
	Config:Refresh() -- restores the faded slot when the drop changed nothing
end

--------------------------------------------------------------------------------
-- Marker strip
--------------------------------------------------------------------------------

-- Click toggles, drag reorders.
local function CreateMarkerSlot(parent, index)
	local slot = CreateFrame("Button", nil, parent)
	PixelSize(slot, SLOT_SIZE, SLOT_SIZE)
	PixelPoint(slot, "TOPLEFT", (index - 1) * (SLOT_SIZE + SLOT_GAP), 0)
	slot.index = index

	slot.bg = Fill(slot, "BACKGROUND", UI.slot)
	-- Recolored per marker in RefreshMarkers: the border is what says "enabled".
	slot.border = AddBorder(slot, UI.border)

	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	PixelPoint(slot.icon, "TOPLEFT", 4, -4)
	PixelPoint(slot.icon, "BOTTOMRIGHT", -4, 4)

	slot.hover = slot:CreateTexture(nil, "HIGHLIGHT")
	slot.hover:SetAllPoints()
	slot.hover:SetColorTexture(1, 1, 1, 0.08)

	slot:SetScript("OnClick", function(self) ToggleMarker(self.index) end)

	slot:RegisterForDrag("LeftButton")
	slot:SetScript("OnDragStart", function(self) BeginDrag(self.index) end)
	slot:SetScript("OnDragStop", EndDrag)

	-- Built on hover: the slot's contents change as the strip is reordered.
	slot:SetScript("OnEnter", function(self)
		local entry = self.entry
		if not entry then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(ns.MarkerName(entry.marker, true), 1, 1, 1)
		GameTooltip:AddLine(entry.on and "Click to switch it off." or "Click to switch it on.",
			0.7, 0.7, 0.7, true)
		GameTooltip:AddLine("Drag to move it in the order.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

	return slot
end

-- `placed` only feeds the hint line.
local function RefreshMarkers()
	local preset = EditedPreset()
	local markers = preset and preset.markers or {}
	local placed = 0

	for i = 1, ns.MARKER_COUNT do
		local slot = markerSlots[i]
		if not slot then
			slot = CreateMarkerSlot(frame.markerHolder, i)
			markerSlots[i] = slot
		end

		local entry = markers[i]
		slot.entry = entry
		if entry then
			if entry.on then placed = placed + 1 end
			slot.icon:SetTexture(ns.MarkerIcon(entry.marker))
			slot.icon:SetDesaturated(not entry.on)
			slot.icon:SetAlpha(entry.on and 1 or 0.28)
			slot.bg:SetColorTexture(Shade(UI.slot, entry.on and 0.08 or 0.02))
			if entry.on then
				slot.border:SetColor(ns.MarkerColor(entry.marker))
			else
				slot.border:SetColor(Shade(UI.border, 0.05))
			end
			slot:Show()
		else
			slot:Hide()
		end
	end

	if placed == 0 then
		frame.markerHint:SetText("Every marker is switched off, so the hotkey has nothing to place.")
		frame.markerHint:SetTextColor(Shade(UI.warn))
	else
		frame.markerHint:SetText(
			("%d in the sequence  \226\128\162  click to toggle, drag to reorder"):format(placed))
		frame.markerHint:SetTextColor(Shade(UI.dim))
	end
end

--------------------------------------------------------------------------------
-- Frame construction
--------------------------------------------------------------------------------

local function BuildTitleBar()
	local bar = CreateFrame("Frame", nil, frame)
	PixelHeight(bar, TITLE_HEIGHT)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	Fill(bar, "BACKGROUND", UI.titleBar)

	local rule = bar:CreateTexture(nil, "ARTWORK")
	PixelHeight(rule, 1, 1)
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
	rule:SetColorTexture(Shade(UI.border))

	-- 22 rather than 16: the glyph keeps to 70% of its own frame, so the rect is
	-- oversized to land the mark itself back at 16.
	local icon = bar:CreateTexture(nil, "ARTWORK")
	PixelSize(icon, 22, 22)
	PixelPoint(icon, "LEFT", PAD, 0)
	icon:SetTexture(ns.ICON)

	local title = CreateText(bar, "Markr", "GameFontHighlight")
	PixelPoint(title, "LEFT", icon, "RIGHT", 8, 0)

	local close = CreateFrame("Button", nil, bar)
	PixelSize(close, TITLE_HEIGHT, TITLE_HEIGHT)
	close:SetPoint("TOPRIGHT")
	close.icon = close:CreateTexture(nil, "ARTWORK")
	PixelSize(close.icon, 20, 20)
	close.icon:SetPoint("CENTER")
	close.icon:SetTexture(CLOSE_TEXTURE)
	close.icon:SetVertexColor(Shade(UI.dim))
	close:SetScript("OnEnter", function(self) self.icon:SetVertexColor(Shade(UI.text)) end)
	close:SetScript("OnLeave", function(self) self.icon:SetVertexColor(Shade(UI.dim)) end)
	close:SetScript("OnClick", function() frame:Hide() end)
end

local function BuildPresetSection()
	CreateHeading(frame, "Preset", PAD, -46)

	frame.picker = CreatePresetPicker(frame, 286, 26)
	PixelPoint(frame.picker, "TOPLEFT", PAD, -64)

	frame.activateButton = CreateButton(frame, "Set Active", 110, 26, function()
		ns.SetActivePreset(selectedPreset)
	end, true)
	PixelPoint(frame.activateButton, "TOPLEFT", PAD + 294, -64)
	SetTooltip(frame.activateButton, "Set Active", "Use this preset for the place-marker hotkey.")

	local actions = {
		{ text = "New", handler = function() StaticPopup_Show("MARKR_NEW_PRESET", nil, nil, {}) end },
		{ text = "Duplicate", handler = DuplicateSelected },
		{ text = "Rename", handler = function() StaticPopup_Show("MARKR_RENAME_PRESET", nil, nil, selectedPreset) end },
		{ text = "Delete", key = "deleteButton", handler = function()
			local preset = EditedPreset()
			if preset then
				StaticPopup_Show("MARKR_DELETE_PRESET", preset.name, nil, selectedPreset)
			end
		end },
	}

	for i, action in ipairs(actions) do
		local button = CreateButton(frame, action.text, 95, 24, action.handler)
		PixelPoint(button, "TOPLEFT", PAD + (i - 1) * 103, -98)
		if action.key then frame[action.key] = button end
	end
end

local function BuildSequenceSection()
	local card = CreateCard(frame, "Sequence", PAD, -132, 100)

	frame.markerHolder = CreateFrame("Frame", nil, card)
	PixelPoint(frame.markerHolder, "TOPLEFT", CARD_PAD, -32)
	PixelSize(frame.markerHolder, CARD_WIDTH, SLOT_SIZE)

	frame.markerHint = CreateText(card, "", "GameFontHighlightSmall", UI.dim)
	PixelPoint(frame.markerHint, "TOPLEFT", frame.markerHolder, "BOTTOMLEFT", 0, -8)
	PixelPoint(frame.markerHint, "RIGHT", card, "RIGHT", -CARD_PAD, 0)
	frame.markerHint:SetJustifyH("LEFT")
end

local PLACEMENT_HINT = {
	cursor = "The marker lands instantly wherever you are pointing at the ground.",
	manual = "The hotkey arms the marker; you click to place it.",
}

local function BuildOptionsSection()
	local card = CreateCard(frame, "Placement", PAD, -240, 114)

	frame.placement = CreateSegments(card, {
		{ value = "cursor", text = "At the cursor",
			tooltip = "Instant, but there is no ground target when the mouse is over a UI panel." },
		{ value = "manual", text = "Placement reticle",
			tooltip = "Blizzard's default behavior: aim deliberately, then click." },
	}, CARD_PAD, -34, CARD_WIDTH, 28, function(value)
		ns.db.placement = value
		ns.ApplyPreset()
		Config:Refresh()
	end)

	frame.placementHint = CreateText(card, "", "GameFontHighlightSmall", UI.dim)
	PixelPoint(frame.placementHint, "TOPLEFT", CARD_PAD, -68)

	frame.announce = CreateToggle(card, "Print each marker to chat as it is placed",
		CARD_PAD, -88, function(checked)
			ns.db.announce = checked
		end)
end

local function BuildBindingSection()
	local card = CreateCard(frame, "Hotkeys", PAD, -362, 112)

	local BINDINGS = {
		{ action = ns.BINDING_PLACE, label = "Place next marker" },
		{ action = ns.BINDING_CLEAR, label = "Clear all markers" },
		{ action = ns.BINDING_RESET, label = "Restart sequence" },
	}

	for i, entry in ipairs(BINDINGS) do
		local y = -32 - (i - 1) * 26

		local label = CreateText(card, entry.label, "GameFontHighlight")
		PixelPoint(label, "TOPLEFT", CARD_PAD, y - 4)
		PixelWidth(label, 146)
		label:SetJustifyH("LEFT")

		local keyButton = CreateButton(card, "", 138, 22, function()
			StartCapture(entry.action, entry.label)
		end)
		PixelPoint(keyButton, "TOPLEFT", CARD_PAD + 154, y)
		SetTooltip(keyButton, entry.label, "Click, then press the key you want.")

		local clearButton = CreateButton(card, "Clear", 78, 22, function()
			ns.SetBindingFor(entry.action, nil)
			Config:Refresh()
		end)
		PixelPoint(clearButton, "TOPLEFT", CARD_PAD + 298, y)

		bindingRows[i] = { action = entry.action, keyButton = keyButton }
	end
end

-- Every offset inside the window is measured from the frame, so the frame landing
-- between two pixels carries all of it off the grid however carefully each child was
-- rounded. Both SetPoint("CENTER") on an odd-sized screen and a drag that ends
-- mid-pixel do that, so the frame is re-anchored to the grid after each.
local function SnapToPixelGrid()
	local left, bottom = frame:GetLeft(), frame:GetBottom()
	if not left or not bottom then return end

	PixelClearPoints(frame)
	PixelPoint(frame, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
end

local function BuildFrame()
	frame = CreateFrame("Frame", "MarkrConfigFrame", UIParent)
	PixelSize(frame, PANEL_WIDTH, PANEL_HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SnapToPixelGrid()
	end)
	frame:SetScript("OnShow", SnapToPixelGrid)
	-- Escape closes the window through UISpecialFrames without the menu ever seeing
	-- the key, so the menu is closed from here.
	frame:SetScript("OnHide", CloseMenu)
	frame:Hide()

	-- The title bar below is ours and sized to TITLE_HEIGHT, so the skin's own strip
	-- is skipped.
	if not ns.Skin.Shell(frame, { noTopBar = true }) then
		Fill(frame, "BACKGROUND", UI.window)
		AddBorder(frame, UI.border, "ARTWORK")
	end

	tinsert(UISpecialFrames, "MarkrConfigFrame")

	BuildTitleBar()
	BuildPresetSection()
	BuildSequenceSection()
	BuildOptionsSection()
	BuildBindingSection()

	frame.status = CreateText(frame, "", "GameFontHighlightSmall", UI.warn)
	PixelPoint(frame.status, "BOTTOMLEFT", PAD, 12)
	PixelPoint(frame.status, "BOTTOMRIGHT", -PAD, 12)
	frame.status:SetJustifyH("RIGHT")

	-- Bindings and preset edits both defer in combat; surface that in frame.status.
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	-- Both of these invalidate every rounded offset in the window at once.
	frame:RegisterEvent("UI_SCALE_CHANGED")
	frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
	frame:SetScript("OnEvent", function(_, event)
		if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
			Repixel()
			SnapToPixelGrid()
		else
			Config:Refresh()
		end
	end)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function Config:Refresh()
	if not frame or not frame:IsShown() then return end

	local presets = ns.GetPresets()
	if not selectedPreset or not presets[selectedPreset] then
		selectedPreset = ns.db.activePreset
	end

	RefreshMarkers()

	local preset = EditedPreset()
	if preset then
		local suffix = (selectedPreset == ns.db.activePreset)
			and "  " .. ns.Branded("(active)", AccentHex()) or ""
		frame.picker:SetLabel(preset.name .. suffix)
	end

	frame.activateButton:SetEnabled(selectedPreset ~= ns.db.activePreset)
	frame.deleteButton:SetEnabled(#presets > 1)
	frame.placement:SetValue(ns.db.placement)
	frame.placementHint:SetText(PLACEMENT_HINT[ns.db.placement] or "")
	frame.announce:SetValue(ns.db.announce)

	for _, row in ipairs(bindingRows) do
		local key = ns.GetBindingKeyFor(row.action)
		row.keyButton:SetLabel(key and ((GetBindingText and GetBindingText(key)) or key) or "Not Bound")
	end

	frame.status:SetText(InCombatLockdown()
		and "In combat: preset changes apply when you leave combat." or "")
end

function Config:Toggle()
	if not frame then BuildFrame() end
	if frame:IsShown() then
		frame:Hide()
	else
		selectedPreset = ns.db.activePreset
		frame:Show()
		self:Refresh()
	end
end

function Config:Open()
	if not frame then BuildFrame() end
	if not frame:IsShown() then
		selectedPreset = ns.db.activePreset
		frame:Show()
	end
	self:Refresh()
end
