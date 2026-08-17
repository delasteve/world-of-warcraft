local ADDON, ns = ...

--------------------------------------------------------------------------------
-- EllesmereUI
--------------------------------------------------------------------------------

if not (EllesmereUI and EllesmereUI.RegisterSkin) then return end

-- The suite's own S.Font primitive primes a drop shadow back onto the string, so
-- only the face, size and outline flag are taken from it.
local function ApplyFont(S, label)
	local path, flags = S.GetFont()
	local _, size = label:GetFont()
	if not (path and size) then return false end
	label:SetFont(path, size, flags or "")
	return true
end

EllesmereUI.RegisterSkin(ADDON, function(S)
	ns.Skin.Use({
		Shell = function(frame, opts) S.Shell(frame, opts) end,
		Panel = function(frame, opts) S.Panel(frame, opts) end,
		Font = function(label) return ApplyFont(S, label) end,
		AccentColor = function() return S.GetAccentColor() end,
		OnLooksChanged = function(fn) S.OnLooksChanged(fn) end,
	})
end)
