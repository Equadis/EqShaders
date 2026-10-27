-- EqProfiles: authored environment profiles for ComfyAtmosphere.
-- Picks the right atmosphere values for the zone / subzone / indoors / time of day you are in and fades to them,
-- so the player does not have to touch the Atmosphere sliders. Rendering settings only: it reads where you are
-- and writes ComfyAtmosphere's own CVars (the same ones its sliders set). It does nothing else.
--
-- Layers (see ProfileData.lua):  Global -> Biome -> Zone -> Subzone -> Interior (if indoors); the Night layer is blended
-- in by how dark the game clock is. Lua 5.0 / WoW 1.12 API.

local DATA = EqProfilesData
local SCHEMA = EqProfilesSchema

local POLL = 0.5        -- seconds between "where am I" checks
local STEP = 0.1        -- seconds between CVar writes while fading

local from, to, applied = {}, {}, {}
local blendStart, blendLen = 0, 0
local areaKey = ""
local enabled = true
local forcedBiome = nil
local pollAcc, stepAcc, retargetAcc = 0, 0, 0
local lastInfo = {}

local function CVarNumber(name)
	local ok, v = pcall(GetCVar, name)
	if ok and v then return tonumber(v) end
	return nil
end

local function Clamp(name, v)
	local r = SCHEMA[name]
	if r then
		if v < r[1] then v = r[1] end
		if v > r[2] then v = r[2] end
	end
	return v
end

-- values a layer lists that Comfy's slider cannot hold are NOT applied (clamping would pin them to the slider's end):
-- rejected[key] = "layer: value (min..max)" for the profile resolved last
local rejected = {}

local function Overlay(dst, src, label)
	if src then
		for k, v in pairs(src) do
			local r = SCHEMA[k]
			if r then
				if v < r[1] or v > r[2] then
					rejected[k] = (label or "?") .. ": " .. v .. " (" .. r[1] .. ".." .. r[2] .. ")"
				else
					dst[k] = v
					rejected[k] = nil
				end
			end
		end
	end
end

local function Smooth(a, b, x)
	if x <= a then return 0 end
	if x >= b then return 1 end
	local t = (x - a) / (b - a)
	return t * t * (3 - 2 * t)
end

-- the hour ComfyAtmosphere is lighting the world with (it can force a fixed hour), else the server's
local function ClockHour()
	local ok, raw = pcall(GetCVar, "comfyTimeShown")
	if ok and raw then
		local _, _, h = string.find(raw, "^%s*([%d%.]+)")
		h = tonumber(h)
		if h then return h end
	end
	local gh, gm = GetGameTime()
	return gh + gm / 60
end

local function NightFactor(h)
	if h >= 12 then return Smooth(19, 21, h) end
	return 1 - Smooth(5, 7, h)
end

local function Indoors()
	local i = IsIndoors and IsIndoors()
	return i and i ~= 0
end

-- Resolve the layered profile for where the player is now. Returns the merged table and a description.
local function Resolve()
	local zone = GetRealZoneText() or ""
	local sub = GetSubZoneText() or ""
	local indoors = Indoors()
	local biome = forcedBiome or DATA.ZoneBiome[zone]

	rejected = {}
	local day = {}
	Overlay(day, DATA.Global, "Global")
	if biome then Overlay(day, DATA.Biomes[biome], "Biome " .. biome) end
	Overlay(day, DATA.Zones[zone], "Zone " .. zone)
	if sub ~= "" then Overlay(day, DATA.Subzones[zone .. "/" .. sub], "Subzone " .. sub) end

	local night = {}
	for k, v in pairs(day) do night[k] = v end
	Overlay(night, DATA.Night, "Night")

	local hour = ClockHour()
	local nf = NightFactor(hour)
	local merged = {}
	for k, v in pairs(day) do
		local n = night[k] or v
		merged[k] = v + (n - v) * nf
	end
	if indoors then
		-- interiors do not follow the clock: take the day layers, then the Interior overrides
		for k, v in pairs(day) do merged[k] = v end
		Overlay(merged, DATA.Interior, "Interior")
	end

	lastInfo = { zone = zone, sub = sub, biome = biome or "(none)", indoors = indoors, hour = hour, night = nf }
	local key = zone .. "/" .. sub .. "|" .. (indoors and "in" or "out") .. "|" .. (biome or "")
	return merged, key
end

local function Snapshot()
	local s = {}
	for k, _ in pairs(SCHEMA) do
		local v = CVarNumber(k)
		if v then s[k] = v end
	end
	return s
end

local function StartBlend(seconds)
	from = Snapshot()
	blendStart = GetTime()
	blendLen = seconds
end

local function Apply()
	local s = 1
	if blendLen > 0 then s = Smooth(0, 1, (GetTime() - blendStart) / blendLen) end
	for k, target in pairs(to) do
		local f = from[k]
		if f == nil then f = target end
		local v = Clamp(k, f + (target - f) * s)
		v = math.floor(v + 0.5)
		if applied[k] ~= v then
			pcall(SetCVar, k, tostring(v))
			applied[k] = v
		end
	end
end

-- the Atmosphere options page (patched OptionsFrame) is open: somebody is tuning by hand, so do not fight them
local function Tuning()
	return OptionsFrame and OptionsFrame:IsVisible()
end

local function Retarget(immediate)
	local merged, key = Resolve()
	to = merged
	if key ~= areaKey then
		areaKey = key
		StartBlend(immediate and 0 or DATA.BlendSeconds)
		applied = {}
	end
end

-- ---- pixel strip: the biome's wetness baseline, drawn as four 6x6 pixel cells at the bottom edge --------------------------
-- EqShaders reads these pixels from the finished frame (and paints them over): cell1 marker, cell2 = (wet, puddle, murk),
-- cell3 = indoors flag, cell4 marker. Pixel position: x = 700 + 6*(cell-1), bottom 6 rows of the screen.
local stripFrame = nil
local stripCells = {}
local wetCur = { 0, 0, 0 }
local wetTarget = { 0, 0, 0 }
local indoorsFlag = false
local indoorCur = 0
local layoutAcc = 99

local function PixelUnit()
	-- UI units per screen pixel
	local res = GetCVar("gxResolution") or "1920x1080"
	local _, _, w, h = string.find(res, "(%d+)x(%d+)")
	h = tonumber(h) or 1080
	return GetScreenHeight() / h
end

local function BuildStrip()
	if stripFrame then return end
	stripFrame = CreateFrame("Frame", "EqProfilesStrip", UIParent)
	stripFrame:SetFrameStrata("TOOLTIP")
	stripFrame:SetFrameLevel(120)
	for i = 1, 4 do
		stripCells[i] = stripFrame:CreateTexture(nil, "OVERLAY")
	end
end

local function LayoutStrip()
	local u = PixelUnit()
	stripFrame:ClearAllPoints()
	stripFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
	stripFrame:SetWidth(1000 * u)
	stripFrame:SetHeight(6 * u)
	for i = 1, 4 do
		local t = stripCells[i]
		t:ClearAllPoints()
		t:SetPoint("BOTTOMLEFT", stripFrame, "BOTTOMLEFT", (700 + 6 * (i - 1)) * u, 0)
		t:SetWidth(6 * u)
		t:SetHeight(6 * u)
	end
end

local function Byte(v)
	if v < 0 then v = 0 end
	if v > 1 then v = 1 end
	return math.floor(v * 255 + 0.5) / 255
end

local function PaintStrip()
	if not stripFrame then return end
	stripCells[1]:SetTexture(1, 0, 1, 1)
	stripCells[2]:SetTexture(Byte(wetCur[1]), Byte(wetCur[2]), Byte(wetCur[3]), 1)
	-- red = how far indoors (fades over ~1.5 s so the room does not pop), green = daylight (1 day .. 0 night)
	stripCells[3]:SetTexture(Byte(indoorCur), Byte(1 - (lastInfo.night or 0)), 0, 1)
	stripCells[4]:SetTexture(0, 1, 1, 1)
end

local function UpdateWetTarget()
	local biome = lastInfo.biome
	local zone = lastInfo.zone or ""
	local row = DATA.WetZone and DATA.WetZone[zone]
	if not row and biome and DATA.WetBase then row = DATA.WetBase[biome] end
	if row and not lastInfo.indoors then
		wetTarget[1], wetTarget[2], wetTarget[3] = row[1], row[2], row[3]
	else
		wetTarget[1], wetTarget[2], wetTarget[3] = 0, 0, 0
	end
	indoorsFlag = lastInfo.indoors and true or false
end

local function StepWet(dt)
	local k = dt / (DATA.BlendSeconds or 5) * 1.5
	if k > 1 then k = 1 end
	for i = 1, 3 do
		wetCur[i] = wetCur[i] + (wetTarget[i] - wetCur[i]) * k
	end
	local ki = dt / 1.5
	if ki > 1 then ki = 1 end
	indoorCur = indoorCur + ((indoorsFlag and 1 or 0) - indoorCur) * ki
end
local frame = CreateFrame("Frame", "EqProfilesFrame", UIParent)
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
	if event == "PLAYER_ENTERING_WORLD" then
		areaKey = ""
		if enabled then
			Retarget(true) -- first entry: snap, do not fade from whatever the CVars last held
			Apply()
		end
	end
end)

frame:SetScript("OnUpdate", function()
	local dt0 = arg1 or 0
	if enabled then
		BuildStrip()
		layoutAcc = layoutAcc + dt0
		if layoutAcc > 2 then layoutAcc = 0; LayoutStrip() end
		StepWet(dt0)
		PaintStrip()
	end
	if not enabled or Tuning() then return end
	local dt = arg1 or 0
	pollAcc = pollAcc + dt
	stepAcc = stepAcc + dt
	if pollAcc >= POLL then
		pollAcc = 0
		Retarget(false)
		UpdateWetTarget()
	end
	if stepAcc >= STEP then
		stepAcc = 0
		Apply()
	end
end)

-- ---- authoring helpers --------------------------------------------------------------------------------------------------

local function Say(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffEqProfiles|r " .. msg)
end

local function SortedKeys(t)
	local keys = {}
	for k, _ in pairs(t) do table.insert(keys, k) end
	table.sort(keys)
	return keys
end

-- Print the CURRENT Comfy CVar values as a Lua table to paste into ProfileData.lua, and keep a copy in SavedVariables
local function Capture(layer)
	local cur = Snapshot()
	local zone = lastInfo.zone or (GetRealZoneText() or "")
	local label = layer
	if layer == "zone" then label = 'Zones["' .. zone .. '"]'
	elseif layer == "sub" then label = 'Subzones["' .. zone .. "/" .. (lastInfo.sub or "") .. '"]'
	elseif layer == "biome" then label = 'Biomes["' .. (lastInfo.biome or "?") .. '"]'
	elseif layer == "global" then label = "Global"
	elseif layer == "interior" then label = "Interior"
	elseif layer == "night" then label = "Night" end

	EqProfilesDB = EqProfilesDB or {}
	EqProfilesDB.captured = EqProfilesDB.captured or {}
	EqProfilesDB.captured[label] = cur

	local parts = {}
	for _, k in ipairs(SortedKeys(cur)) do
		table.insert(parts, k .. " = " .. cur[k])
	end
	Say("captured " .. label .. " (" .. table.getn(parts) .. " values). Saved to SavedVariables on /reload or logout:")
	local line = ""
	for _, p in ipairs(parts) do
		if string.len(line) + string.len(p) > 230 then
			DEFAULT_CHAT_FRAME:AddMessage(line)
			line = ""
		end
		line = line .. p .. ", "
	end
	if line ~= "" then DEFAULT_CHAT_FRAME:AddMessage(line) end
end

local function Status()
	Resolve()
	Say("zone: " .. (lastInfo.zone or "?") .. " / " .. (lastInfo.sub ~= "" and lastInfo.sub or "-") ..
		"  biome: " .. lastInfo.biome .. "  indoors: " .. (lastInfo.indoors and "yes" or "no") ..
		string.format("  clock: %.1f  night: %.2f", lastInfo.hour or 0, lastInfo.night or 0))
	local nrej = 0
	for _ in pairs(rejected) do nrej = nrej + 1 end
	Say("engine " .. (enabled and "ON" or "OFF") .. (Tuning() and " (paused: Atmosphere options open)" or "") ..
		", fade " .. DATA.BlendSeconds .. "s" .. (forcedBiome and (", biome forced to " .. forcedBiome) or "") ..
		(nrej > 0 and (", " .. nrej .. " value(s) outside Comfy's slider range not applied: /eqprof rejected") or ""))
end

local function ListRejected()
	Resolve()
	local n = 0
	for _, k in ipairs(SortedKeys(rejected)) do
		DEFAULT_CHAT_FRAME:AddMessage("  " .. k .. "  " .. rejected[k])
		n = n + 1
	end
	Say(n .. " value(s) not applied in the current profile")
end

SLASH_EQPROF1 = "/eqprof"
SlashCmdList["EQPROF"] = function(msg)
	msg = string.lower(msg or "")
	local _, _, cmd, arg = string.find(msg, "^%s*(%S*)%s*(.-)%s*$")
	if cmd == "" or cmd == "status" then
		Status()
	elseif cmd == "on" then
		enabled = true; areaKey = ""; Say("engine ON")
	elseif cmd == "off" then
		enabled = false; Say("engine OFF: Atmosphere sliders are yours again")
	elseif cmd == "capture" then
		if arg == "" then arg = "zone" end
		Capture(arg)
	elseif cmd == "rejected" then
		ListRejected()
	elseif cmd == "fade" then
		local s = tonumber(arg)
		if s and s >= 0 and s <= 60 then DATA.BlendSeconds = s; Say("fade " .. s .. "s") else Say("usage: /eqprof fade <0-60>") end
	elseif cmd == "biome" then
		-- preview a biome anywhere (empty = back to the zone's own)
		if arg == "" then forcedBiome = nil; Say("biome back to automatic") else
			local found
			for name, _ in pairs(DATA.Biomes) do if string.lower(name) == arg then found = name end end
			if found then forcedBiome = found; areaKey = ""; Say("previewing biome " .. found) else Say("unknown biome: " .. arg) end
		end
	else
		Say("/eqprof [status] | on | off | capture <zone|sub|biome|global|interior|night> | fade <s> | biome [name]")
	end
end
