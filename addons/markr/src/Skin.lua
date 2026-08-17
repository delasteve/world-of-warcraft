local ADDON, ns = ...

local Skin = {}
ns.Skin = Skin

--------------------------------------------------------------------------------
-- Interface
--------------------------------------------------------------------------------

-- Every entry point no-ops and reports false when no suite is present, so a caller
-- asks for a skin unconditionally and paints its own art when it does not get one.

-- Installed by whichever file under Skins\ found the suite it is written for.
local provider

-- Callbacks handed over before a provider arrives.
local pending = {}

-- Takes a suite normalized to this shape: Shell and Panel paint a frame, Font
-- paints a FontString and reports whether it did, AccentColor returns r, g, b, and
-- OnLooksChanged registers a callback against a live change to any of it.
function Skin.Use(newProvider)
	provider = newProvider
	for _, fn in ipairs(pending) do
		provider.OnLooksChanged(fn)
		fn()
	end
	pending = {}
end

function Skin.IsActive()
	return provider ~= nil
end

function Skin.Shell(frame, opts)
	if not provider then return false end
	provider.Shell(frame, opts)
	return true
end

function Skin.Panel(frame, opts)
	if not provider then return false end
	provider.Panel(frame, opts)
	return true
end

function Skin.Font(label)
	if not provider then return false end
	return provider.Font(label) and true or false
end

function Skin.AccentColor()
	if not provider then return nil end
	return provider.AccentColor()
end

-- Runs once as soon as a skin is available and again on every later change to it.
function Skin.OnLooksChanged(fn)
	if not provider then
		pending[#pending + 1] = fn
		return
	end
	provider.OnLooksChanged(fn)
	fn()
end
