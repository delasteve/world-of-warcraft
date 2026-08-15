local ADDON, ns = ...

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

local DB_VERSION = 4
local MAX_PRESET_NAME = 32

local function AllMarkers(on)
	local list = {}
	for index = 1, ns.MARKER_COUNT do
		list[index] = { marker = index, on = on }
	end
	return list
end

local function DefaultDB()
	return {
		version = DB_VERSION,
		activePreset = 1,
		placement = "cursor", -- "cursor" | "manual"
		announce = true,
		defaultBindingsApplied = false,
		minimap = { angle = 200 },
		presets = {
			{ name = "All Markers", markers = AllMarkers(true) },
		},
	}
end

-- Doubles as the v1 migration: a bare number means an enabled marker.
local function SanitizeMarkers(list)
	local clean, seen = {}, {}

	if type(list) == "table" then
		for _, value in ipairs(list) do
			local index, on
			if type(value) == "table" then
				index, on = tonumber(value.marker), value.on and true or false
			else
				index, on = tonumber(value), true
			end

			if index and ns.MARKERS[index] and not seen[index] then
				seen[index] = true
				clean[#clean + 1] = { marker = index, on = on }
			end
		end
	end

	for index = 1, ns.MARKER_COUNT do
		if not seen[index] then
			clean[#clean + 1] = { marker = index, on = false }
		end
	end

	return clean
end

local function SanitizeDB(db)
	local from = tonumber(db.version) or 0

	if type(db.presets) ~= "table" or #db.presets == 0 then
		db.presets = DefaultDB().presets
	end

	for i, preset in ipairs(db.presets) do
		if type(preset.name) ~= "string" or preset.name == "" then
			preset.name = "Preset " .. i
		end
		preset.name = preset.name:sub(1, MAX_PRESET_NAME)
		preset.markers = SanitizeMarkers(preset.markers)
	end

	local active = tonumber(db.activePreset) or 1
	if not db.presets[active] then active = 1 end
	db.activePreset = active

	if db.placement ~= "cursor" and db.placement ~= "manual" then
		db.placement = "cursor"
	end
	-- v3: force announce true once, so an older save adopts the new default.
	if type(db.announce) ~= "boolean" or from < 3 then db.announce = true end

	-- v4: the minimap button. `hide` is a removed option, stripped from old saves.
	if type(db.minimap) ~= "table" then db.minimap = {} end
	db.minimap.hide = nil
	db.minimap.angle = tonumber(db.minimap.angle) or 200

	db.version = DB_VERSION
end

function ns.InitDB()
	if type(MarkrDB) ~= "table" then
		MarkrDB = DefaultDB()
	end
	SanitizeDB(MarkrDB)
	ns.db = MarkrDB
end

--------------------------------------------------------------------------------
-- Preset access
--------------------------------------------------------------------------------

function ns.GetPresets()
	return ns.db.presets
end

-- The markers a preset will actually place, in order.
function ns.ActiveMarkers(preset)
	local active = {}
	if preset then
		for _, entry in ipairs(preset.markers) do
			if entry.on then active[#active + 1] = entry.marker end
		end
	end
	return active
end

function ns.GetActivePreset()
	return ns.db.presets[ns.db.activePreset]
end

function ns.SetActivePreset(index)
	if not ns.db.presets[index] then return false end
	ns.db.activePreset = index
	ns.ApplyPreset()
	if ns.Config then ns.Config:Refresh() end
	return true
end

function ns.FindPreset(name)
	local needle = name:lower()
	for i, preset in ipairs(ns.db.presets) do
		if preset.name:lower() == needle then return i, preset end
	end

	local match
	for i, preset in ipairs(ns.db.presets) do
		if preset.name:lower():find(needle, 1, true) == 1 then
			if match then return nil end
			match = i
		end
	end
	if match then return match, ns.db.presets[match] end
end

function ns.CreatePreset(name, markers)
	local preset = {
		name = (name or "New Preset"):sub(1, MAX_PRESET_NAME),
		markers = SanitizeMarkers(markers),
	}
	table.insert(ns.db.presets, preset)
	return #ns.db.presets, preset
end

function ns.DeletePreset(index)
	if #ns.db.presets <= 1 then return false end
	if not ns.db.presets[index] then return false end

	table.remove(ns.db.presets, index)
	if ns.db.activePreset > #ns.db.presets then
		ns.db.activePreset = #ns.db.presets
	elseif ns.db.activePreset > index then
		ns.db.activePreset = ns.db.activePreset - 1
	end
	ns.ApplyPreset()
	return true
end
