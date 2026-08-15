local ADDON, ns = ...

--------------------------------------------------------------------------------
-- Key bindings
--------------------------------------------------------------------------------

function ns.GetBindingKeyFor(action)
	return GetBindingKey(action)
end

-- Rebinds `action` to `key`, dropping whatever keys it used to own. A nil `key`
-- just unbinds it. Returns success plus the action that was displaced.
function ns.SetBindingFor(action, key)
	if InCombatLockdown() then
		return false, nil, "combat"
	end

	-- An action holds at most two keys; the loop bound is a safety net.
	for _ = 1, 4 do
		local existing = GetBindingKey(action)
		if not existing then break end
		SetBinding(existing, nil)
	end

	local displaced
	if key then
		displaced = GetBindingAction(key)
		if displaced == "" or displaced == action then displaced = nil end
		if not SetBinding(key, action) then
			SaveBindings(GetCurrentBindingSet())
			return false, nil, "failed"
		end
	end

	SaveBindings(GetCurrentBindingSet())
	if ns.Config then ns.Config:Refresh() end
	return true, displaced
end

-- The one binding the addon writes on its own, once, and only into keys nobody
-- else has claimed.
function ns.ApplyDefaultBindings()
	if ns.db.defaultBindingsApplied then return end
	if InCombatLockdown() then return end

	local applied, skipped = {}, {}
	for _, entry in ipairs(ns.DEFAULT_BINDINGS) do
		local current = GetBindingAction(entry.key)
		if GetBindingKey(entry.action) then
			-- Already bound by the player; leave it alone.
		elseif current == nil or current == "" then
			SetBinding(entry.key, entry.action)
			applied[#applied + 1] = entry.key
		else
			skipped[#skipped + 1] = entry.key
		end
	end

	if #applied > 0 then
		SaveBindings(GetCurrentBindingSet())
		ns.Print("Default hotkeys set: %s. Change them with /markr.", table.concat(applied, ", "))
	end
	if #skipped > 0 then
		ns.Print("%s already in use, so no default hotkey was set. Assign one with /markr.",
			table.concat(skipped, ", "))
	end

	ns.db.defaultBindingsApplied = true
end

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

local function ShowHelp()
	ns.Print("commands:")
	print("  |cffffff00/markr|r - open the settings window")
	print("  |cffffff00/markr list|r - list your presets")
	print("  |cffffff00/markr use <name>|r - switch to a preset")
	print("  |cffffff00/markr reset|r - restart the marker sequence")
end

SLASH_MARKR1 = "/markr"
SlashCmdList["MARKR"] = function(input)
	local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	command = (command or ""):lower()

	if command == "" then
		ns.Config:Toggle()
	elseif command == "help" then
		ShowHelp()
	elseif command == "list" then
		ns.Print("presets:")
		for i, preset in ipairs(ns.db.presets) do
			local marker = (i == ns.db.activePreset) and "|cff00ff00*|r" or " "
			print(("  %s %d. %s (%d markers)"):format(marker, i, preset.name, #ns.ActiveMarkers(preset)))
		end
	elseif command == "use" then
		if rest == "" then
			ns.Print("Usage: /markr use <preset name>")
			return
		end
		local index, preset = ns.FindPreset(rest)
		if index then
			ns.SetActivePreset(index)
			ns.Print("Switched to |cffffff00%s|r.", preset.name)
		else
			ns.Print("No single preset matches \"%s\".", rest)
		end
	elseif command == "reset" then
		ns.ResetSequence()
	else
		ns.Print("Unknown command \"%s\".", command)
		ShowHelp()
	end
end
