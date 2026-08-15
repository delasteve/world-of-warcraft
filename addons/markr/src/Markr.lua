local ADDON, ns = ...

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

ns.MARKER_COUNT = 8

ns.COLOR = { hex = "00ffab", r = 0.00, g = 1.00, b = 0.67 }

ns.ICON = "Interface\\AddOns\\Markr\\Textures\\Glyph.png"

-- The brand color, turned red for warnings.
ns.ALERT_HEX = "ff4040"

-- Keyed by the index /worldmarker uses; `icon` is a different number.
ns.MARKERS = {
	[1] = { name = "Square",   icon = 6, r = 0.25, g = 0.55, b = 1.00 },
	[2] = { name = "Triangle", icon = 4, r = 0.25, g = 0.90, b = 0.35 },
	[3] = { name = "Diamond",  icon = 3, r = 0.75, g = 0.45, b = 1.00 },
	[4] = { name = "Cross",    icon = 7, r = 1.00, g = 0.30, b = 0.30 },
	[5] = { name = "Star",     icon = 1, r = 1.00, g = 0.90, b = 0.20 },
	[6] = { name = "Circle",   icon = 2, r = 1.00, g = 0.60, b = 0.15 },
	[7] = { name = "Moon",     icon = 5, r = 0.65, g = 0.85, b = 1.00 },
	[8] = { name = "Skull",    icon = 8, r = 0.95, g = 0.95, b = 0.95 },
}

ns.BINDING_PLACE = "CLICK MarkrButton:LeftButton"
ns.BINDING_CLEAR = "CLICK MarkrButton:RightButton"
ns.BINDING_RESET = "CLICK MarkrButton:MiddleButton"

-- Claimed once on first login, and only if the key is free; see ApplyDefaultBindings.
ns.DEFAULT_BINDINGS = {
	{ action = ns.BINDING_PLACE, key = "SHIFT-G" },
	{ action = ns.BINDING_CLEAR, key = "CTRL-G" },
}

-- The keybindings panel titles a section with _G[category], so this global is the
-- section name for the `category="BINDING_HEADER_MARKR"` in Bindings.xml.
BINDING_HEADER_MARKR = "Markr"
_G["BINDING_NAME_CLICK MarkrButton:LeftButton"] = "Place next world marker"
_G["BINDING_NAME_CLICK MarkrButton:RightButton"] = "Clear all world markers"
_G["BINDING_NAME_CLICK MarkrButton:MiddleButton"] = "Restart marker sequence"

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

function ns.Branded(text, hex)
	return ("|cff%s%s|r"):format(hex or ns.COLOR.hex, text or "Markr")
end

local function Say(hex, fmt, ...)
	local msg = (select("#", ...) > 0) and fmt:format(...) or fmt
	print(ns.Branded(nil, hex) .. ": " .. msg)
end

function ns.Print(fmt, ...)
	Say(nil, fmt, ...)
end

function ns.Alert(fmt, ...)
	Say(ns.ALERT_HEX, fmt, ...)
end

function ns.MarkerIcon(index)
	local info = ns.MARKERS[index]
	return info and ("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. info.icon) or nil
end

function ns.MarkerColor(index)
	local info = ns.MARKERS[index]
	if not info then return 1, 1, 1 end
	return info.r, info.g, info.b
end

function ns.MarkerName(index, colored)
	local info = ns.MARKERS[index]
	if not info then return "?" end
	if colored then
		return ("|cff%02x%02x%02x%s|r"):format(
			math.floor(info.r * 255), math.floor(info.g * 255), math.floor(info.b * 255), info.name)
	end
	return info.name
end

--------------------------------------------------------------------------------
-- Load
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then
			ns.InitDB()
			events:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "PLAYER_LOGIN" then
		if not ns.db then ns.InitDB() end
		ns.ApplyDefaultBindings()
		ns.ApplyPreset()
		ns.InitLaunchers()
	end
end)
