-- EqProfiles/ProfileData.lua : the authored environment profiles. Edit THIS file (or use /eqprof capture) to tune areas.
--
-- Inheritance, lowest to highest priority; each layer only lists what it changes:
--     Global  ->  Biomes[biome of the zone]  ->  Zones[zone]  ->  Subzones["Zone/Subzone"]  ->  Interior (when indoors)
-- plus the Night layer, blended in by how dark the game clock is. Keys are ComfyAtmosphere CVar names (ProfileSchema.lua lists
-- every key a profile may set and its range).
--
-- The 13 Biomes below are generated from EqProfiles_13_Zone_Atmosphere_Profiles.csv (the authored source of truth); in-range values are copied unchanged.
-- Columns whose CSV values do not fit the real Comfy slider (MistReach, ShadowSoftness, RaysSoften, Sunlight, LampGlow,
-- FoliageShade*, WaveSize, WaveHeight, GrassWaveLength) are RESCALED proportionally, the whole column at once, as
-- real = min + csv / M * (max - min), M = max(100, largest value in that column), so the differences between biomes survive.
-- The authored CSV number is kept in the comment under each biome. (The engine still rejects any value outside a slider's range.)
-- WATER: the five water keys per biome (WaterZoneSaturation/Clarity/Bright/Reflect/Sunset) are NOT the CSV values: they were
-- retuned 2026-10-27 for the new bed-colour water model (patched comfyatmos water shader); the CSV numbers are kept in comments.
-- Global, Interior, Night, City and Dungeon are NOT in the CSV: they are the project owner's hand-tuned baseline (2026-10-27)
-- and conservative drafts.

EqProfilesData = {}
local D = EqProfilesData

-- seconds a change between two areas takes to fade in (smoothstep); the CSV recommends 5 for every biome
D.BlendSeconds = 5

D.Global = {
	comfyMistDensity = 55, comfyMistHeight = 165, comfyMistBrightness = 80, comfyMistSun = 0,
	comfyMistToward = 0, comfyMistHorizon = 0, comfyMistWater = 250, comfyMistMorning = 290,
	comfyMistLamps = 200, comfyMistWind = 45, comfyMistWindDir = 0,
	comfyVolumeStrength = 15, comfyVolumeDensity = 40, comfyVolumeDistance = 50, comfyVolumeDirection = 500,
	comfyShadeTint = 100, comfySunShadowStrength = 80, comfySunShadowsUnitStrength = 70, comfySunShadowsBody = 60,
	comfyShadowOnWater = 100, comfyShadowHighest = 89, comfyShadowRiseFrom = 30,
	comfyLampGlow = 20, comfyLampDistance = 400, comfyLanternLight = 91, comfyTorchLight = 85, comfyIndoorLamps = 55,
	comfyWaterZoneSaturation = 20, comfyWaterBright = 80, comfyWaterReflect = 85, comfyWaterBend = 65,
	comfyDaySaturation = 100,
	-- shoreline: a weaker, wider wet-sand band so the waterline does not read as a dark seam (tested at Lake Everstill)
	comfyWaterWetSand = 20, comfyWaterSwashHeight = 0,
	-- water sun glint: a wider, slightly stronger glitter so it survives normal third-person pitches (Comfy's own glint model; untested in-game)
	comfyWaterGlint = 65, comfyWaterGlintSize = 100,
	-- no pale rim at the waterline (2026-10-27): the edge line and the lake foam drew it; checked at Lake Everstill
	comfyWaterEdge = 0, comfyWaterLakeFoam = 0, comfyWaterFoamSize = 0, comfyWaterFoamReach = 0,
}

-- ---- biome layer: the 13 CSV profiles (verbatim) --------------------------------------------------------------------
D.Biomes = {
	["Temperate Forest"] = {   -- Elwynn Forest; Redridge wooded areas; Hillsbrad foothills
		comfyVolumeStrength = 42, comfyVolumeDensity = 14, comfyVolumeDistance = 78, comfyVolumeDirection = 60,
		comfyMistDensity = 32, comfyMistHeight = 22, comfyMistBrightness = 105, comfyMistSun = 46,
		comfyMistToward = 50, comfyMistHorizon = 38, comfyMistReach = 1354, comfyMistSky = 18,
		comfyMistPatches = 42, comfyMistLow = 28, comfyMistWater = 30, comfyMistMorning = 58,
		comfyMistLamps = 36, comfyMistWind = 32, comfySunShadowStrength = 75, comfyShadowSoftness = 4,
		comfyTreeShade = 72, comfyFoliageShadeSize = 28, comfyFoliageShadeEdge = 31, comfyFoliageSelfShade = 25,
		comfyRaysStrength = 42, comfyRaysSoften = 9, comfySunlight = 29, comfyDaySaturation = 102,
		comfyNightSaturation = 88, comfyNightStrength = 50, comfyNightDarkness = 28, comfyRainDarkness = 34,
		comfyMoonlight = 62, comfyCloudCover = 42, comfyCloudShapes = 58, comfyCloudSoftness = 62,
		comfyCloudShapeBillows = 55, comfyCloudPuffiness = 55, comfyCloudSpeed = 38, comfyGrassWind = 45,
		comfyGrassSpeed = 42, comfyGrassWaveLength = 35, comfyGrassLean = 30, comfyWaterZoneSaturation = 38,   -- water retuned for the bed-colour model; CSV had ZoneSaturation=82
		comfyWaterClarity = 110, comfyWaterBright = 62, comfyWaterReflect = 50, comfyWaterSunset = 60,   -- water retuned for the bed-colour model; CSV had Clarity=72, Bright=58, Reflect=62, Sunset=70
		comfyWaveHeight = 7, comfyWaveSize = 218, comfyLampGlow = 32, comfyLampsDay = 18,
		-- rescaled from the CSV (csv->real): comfyMistReach 66->1354; comfyShadowSoftness 52->4; comfyFoliageShadeSize 55->28; comfyFoliageShadeEdge 62->31; comfyFoliageSelfShade 50->25; comfyRaysSoften 58->9; comfySunlight 100->42; comfyGrassWaveLength 55->35; comfyWaveHeight 22->7; comfyWaveSize 48->218; comfyLampGlow 65->32
	},
	["Enchanted / Ancient Forest"] = {   -- Ashenvale; Moonglade; Feralas forest
		comfyVolumeStrength = 55, comfyVolumeDensity = 19, comfyVolumeDistance = 68, comfyVolumeDirection = 68,
		comfyMistDensity = 48, comfyMistHeight = 32, comfyMistBrightness = 92, comfyMistSun = 55,
		comfyMistToward = 62, comfyMistHorizon = 44, comfyMistReach = 1468, comfyMistSky = 26,
		comfyMistPatches = 62, comfyMistLow = 48, comfyMistWater = 52, comfyMistMorning = 70,
		comfyMistLamps = 48, comfyMistWind = 22, comfySunShadowStrength = 80, comfyShadowSoftness = 5,
		comfyTreeShade = 82, comfyFoliageShadeSize = 33, comfyFoliageShadeEdge = 29, comfyFoliageSelfShade = 32,
		comfyRaysStrength = 58, comfyRaysSoften = 11, comfySunlight = 27, comfyDaySaturation = 108,
		comfyNightSaturation = 94, comfyNightStrength = 58, comfyNightDarkness = 34, comfyRainDarkness = 42,
		comfyMoonlight = 70, comfyCloudCover = 52, comfyCloudShapes = 70, comfyCloudSoftness = 72,
		comfyCloudShapeBillows = 68, comfyCloudPuffiness = 64, comfyCloudSpeed = 25, comfyGrassWind = 32,
		comfyGrassSpeed = 32, comfyGrassWaveLength = 40, comfyGrassLean = 22, comfyWaterZoneSaturation = 55,   -- water retuned for the bed-colour model; CSV had ZoneSaturation=88
		comfyWaterClarity = 100, comfyWaterBright = 66, comfyWaterReflect = 56, comfyWaterSunset = 70,   -- water retuned for the bed-colour model; CSV had Clarity=60, Bright=52, Reflect=68, Sunset=74
		comfyWaveHeight = 5, comfyWaveSize = 239, comfyLampGlow = 39, comfyLampsDay = 24,
		-- rescaled from the CSV (csv->real): comfyMistReach 72->1468; comfyShadowSoftness 60->5; comfyFoliageShadeSize 66->33; comfyFoliageShadeEdge 58->29; comfyFoliageSelfShade 64->32; comfyRaysSoften 66->11; comfySunlight 92->38; comfyGrassWaveLength 64->40; comfyWaveHeight 16->5; comfyWaveSize 54->239; comfyLampGlow 78->39
	},
	["Dark / Haunted Forest"] = {   -- Duskwood; Tirisfal Glades; ghostly woodland subzones
		comfyVolumeStrength = 46, comfyVolumeDensity = 23, comfyVolumeDistance = 56, comfyVolumeDirection = 38,
		comfyMistDensity = 68, comfyMistHeight = 42, comfyMistBrightness = 62, comfyMistSun = 22,
		comfyMistToward = 28, comfyMistHorizon = 18, comfyMistReach = 1696, comfyMistSky = 52,
		comfyMistPatches = 74, comfyMistLow = 78, comfyMistWater = 66, comfyMistMorning = 78,
		comfyMistLamps = 85, comfyMistWind = 18, comfySunShadowStrength = 87, comfyShadowSoftness = 4,
		comfyTreeShade = 88, comfyFoliageShadeSize = 36, comfyFoliageShadeEdge = 23, comfyFoliageSelfShade = 37,
		comfyRaysStrength = 20, comfyRaysSoften = 12, comfySunlight = 21, comfyDaySaturation = 80,
		comfyNightSaturation = 72, comfyNightStrength = 72, comfyNightDarkness = 48, comfyRainDarkness = 58,
		comfyMoonlight = 54, comfyCloudCover = 82, comfyCloudShapes = 68, comfyCloudSoftness = 78,
		comfyCloudShapeBillows = 48, comfyCloudPuffiness = 48, comfyCloudSpeed = 28, comfyGrassWind = 40,
		comfyGrassSpeed = 34, comfyGrassWaveLength = 32, comfyGrassLean = 38, comfyWaterZoneSaturation = 22,   -- water retuned for the bed-colour model; CSV had ZoneSaturation=58
		comfyWaterClarity = 85, comfyWaterBright = 48, comfyWaterReflect = 40, comfyWaterSunset = 40,   -- water retuned for the bed-colour model; CSV had Clarity=38, Bright=34, Reflect=42, Sunset=42
		comfyWaveHeight = 4, comfyWaveSize = 197, comfyLampGlow = 46, comfyLampsDay = 48,
		-- rescaled from the CSV (csv->real): comfyMistReach 84->1696; comfyShadowSoftness 46->4; comfyFoliageShadeSize 72->36; comfyFoliageShadeEdge 46->23; comfyFoliageSelfShade 74->37; comfyRaysSoften 72->12; comfySunlight 72->30; comfyGrassWaveLength 50->32; comfyWaveHeight 12->4; comfyWaveSize 42->197; comfyLampGlow 92->46
	},
	["Tropical Jungle"] = {   -- Stranglethorn Vale; Un'Goro jungle areas
		comfyVolumeStrength = 60, comfyVolumeDensity = 24, comfyVolumeDistance = 58, comfyVolumeDirection = 72,
		comfyMistDensity = 56, comfyMistHeight = 36, comfyMistBrightness = 108, comfyMistSun = 62,
		comfyMistToward = 68, comfyMistHorizon = 48, comfyMistReach = 1506, comfyMistSky = 30,
		comfyMistPatches = 68, comfyMistLow = 56, comfyMistWater = 72, comfyMistMorning = 82,
		comfyMistLamps = 42, comfyMistWind = 30, comfySunShadowStrength = 83, comfyShadowSoftness = 5,
		comfyTreeShade = 90, comfyFoliageShadeSize = 37, comfyFoliageShadeEdge = 30, comfyFoliageSelfShade = 34,
		comfyRaysStrength = 66, comfyRaysSoften = 9, comfySunlight = 31, comfyDaySaturation = 112,
		comfyNightSaturation = 92, comfyNightStrength = 54, comfyNightDarkness = 32, comfyRainDarkness = 48,
		comfyMoonlight = 60, comfyCloudCover = 58, comfyCloudShapes = 76, comfyCloudSoftness = 66,
		comfyCloudShapeBillows = 78, comfyCloudPuffiness = 78, comfyCloudSpeed = 44, comfyGrassWind = 58,
		comfyGrassSpeed = 54, comfyGrassWaveLength = 31, comfyGrassLean = 44, comfyWaterZoneSaturation = 40,   -- water retuned for the bed-colour model; CSV had ZoneSaturation=92
		comfyWaterClarity = 120, comfyWaterBright = 66, comfyWaterReflect = 46, comfyWaterSunset = 60,   -- water retuned for the bed-colour model; CSV had Clarity=54, Bright=62, Reflect=58, Sunset=78
		comfyWaveHeight = 7, comfyWaveSize = 204, comfyLampGlow = 33, comfyLampsDay = 14,
		-- rescaled from the CSV (csv->real): comfyMistReach 74->1506; comfyShadowSoftness 58->5; comfyFoliageShadeSize 74->37; comfyFoliageShadeEdge 60->30; comfyFoliageSelfShade 68->34; comfyRaysSoften 58->9; comfySunlight 108->45; comfyGrassWaveLength 48->31; comfyWaveHeight 22->7; comfyWaveSize 44->204; comfyLampGlow 66->33
	},
	["Swamp / Marsh"] = {   -- Swamp of Sorrows; Wetlands marsh; Dustwallow Marsh
		comfyVolumeStrength = 44, comfyVolumeDensity = 25, comfyVolumeDistance = 52, comfyVolumeDirection = 38,
		comfyMistDensity = 78, comfyMistHeight = 34, comfyMistBrightness = 74, comfyMistSun = 28,
		comfyMistToward = 34, comfyMistHorizon = 24, comfyMistReach = 1810, comfyMistSky = 46,
		comfyMistPatches = 82, comfyMistLow = 92, comfyMistWater = 92, comfyMistMorning = 90,
		comfyMistLamps = 74, comfyMistWind = 12, comfySunShadowStrength = 70, comfyShadowSoftness = 6,
		comfyTreeShade = 76, comfyFoliageShadeSize = 31, comfyFoliageShadeEdge = 36, comfyFoliageSelfShade = 29,
		comfyRaysStrength = 24, comfyRaysSoften = 13, comfySunlight = 22, comfyDaySaturation = 86,
		comfyNightSaturation = 78, comfyNightStrength = 64, comfyNightDarkness = 40, comfyRainDarkness = 56,
		comfyMoonlight = 52, comfyCloudCover = 76, comfyCloudShapes = 62, comfyCloudSoftness = 84,
		comfyCloudShapeBillows = 46, comfyCloudPuffiness = 50, comfyCloudSpeed = 20, comfyGrassWind = 24,
		comfyGrassSpeed = 26, comfyGrassWaveLength = 39, comfyGrassLean = 26, comfyWaterZoneSaturation = 20,   -- water retuned for the bed-colour model; CSV had ZoneSaturation=54
		comfyWaterClarity = 70, comfyWaterBright = 42, comfyWaterReflect = 30, comfyWaterSunset = 30,   -- water retuned for the bed-colour model; CSV had Clarity=28, Bright=38, Reflect=34, Sunset=50
		comfyWaveHeight = 2, comfyWaveSize = 267, comfyLampGlow = 42, comfyLampsDay = 34,
		-- rescaled from the CSV (csv->real): comfyMistReach 90->1810; comfyShadowSoftness 76->6; comfyFoliageShadeSize 62->31; comfyFoliageShadeEdge 72->36; comfyFoliageSelfShade 58->29; comfyRaysSoften 82->13; comfySunlight 78->32; comfyGrassWaveLength 62->39; comfyWaveHeight 8->2; comfyWaveSize 62->267; comfyLampGlow 84->42
	},
	["Grassland / Plains"] = {   -- Mulgore; The Barrens grasslands; Arathi Highlands open areas
		comfyVolumeStrength = 32, comfyVolumeDensity = 9, comfyVolumeDistance = 92, comfyVolumeDirection = 64,
		comfyMistDensity = 18, comfyMistHeight = 14, comfyMistBrightness = 118, comfyMistSun = 42,
		comfyMistToward = 54, comfyMistHorizon = 52, comfyMistReach = 1202, comfyMistSky = 10,
		comfyMistPatches = 24, comfyMistLow = 12, comfyMistWater = 18, comfyMistMorning = 42,
		comfyMistLamps = 18, comfyMistWind = 58, comfySunShadowStrength = 78, comfyShadowSoftness = 4,
		comfyTreeShade = 52, comfyFoliageShadeSize = 22, comfyFoliageShadeEdge = 29, comfyFoliageSelfShade = 19,
		comfyRaysStrength = 38, comfyRaysSoften = 8, comfySunlight = 31, comfyDaySaturation = 104,
		comfyNightSaturation = 86, comfyNightStrength = 46, comfyNightDarkness = 24, comfyRainDarkness = 32,
		comfyMoonlight = 64, comfyCloudCover = 38, comfyCloudShapes = 70, comfyCloudSoftness = 56,
		comfyCloudShapeBillows = 72, comfyCloudPuffiness = 72, comfyCloudSpeed = 58, comfyGrassWind = 78,
		comfyGrassSpeed = 66, comfyGrassWaveLength = 44, comfyGrassLean = 62, comfyWaterZoneSaturation = 45,   -- water retuned for the bed-colour model; CSV had ZoneSaturation=76
		comfyWaterClarity = 130, comfyWaterBright = 64, comfyWaterReflect = 55, comfyWaterSunset = 70,   -- water retuned for the bed-colour model; CSV had Clarity=70, Bright=60, Reflect=66, Sunset=82
		comfyWaveHeight = 5, comfyWaveSize = 232, comfyLampGlow = 29, comfyLampsDay = 8,
		-- rescaled from the CSV (csv->real): comfyMistReach 58->1202; comfyShadowSoftness 46->4; comfyFoliageShadeSize 44->22; comfyFoliageShadeEdge 58->29; comfyFoliageSelfShade 38->19; comfyRaysSoften 48->8; comfySunlight 108->45; comfyGrassWaveLength 72->44; comfyWaveHeight 18->5; comfyWaveSize 52->232; comfyLampGlow 58->29
	},
	["Desert / Dunes"] = {   -- Tanaris; Silithus sandy areas
		comfyVolumeStrength = 24, comfyVolumeDensity = 7, comfyVolumeDistance = 98, comfyVolumeDirection = 54,
		comfyMistDensity = 20, comfyMistHeight = 10, comfyMistBrightness = 138, comfyMistSun = 54,
		comfyMistToward = 58, comfyMistHorizon = 72, comfyMistReach = 1582, comfyMistSky = 8,
		comfyMistPatches = 16, comfyMistLow = 4, comfyMistWater = 8, comfyMistMorning = 24,
		comfyMistLamps = 10, comfyMistWind = 72, comfySunShadowStrength = 92, comfyShadowSoftness = 2,
		comfyTreeShade = 44, comfyFoliageShadeSize = 18, comfyFoliageShadeEdge = 21, comfyFoliageSelfShade = 15,
		comfyRaysStrength = 34, comfyRaysSoften = 6, comfySunlight = 35, comfyDaySaturation = 96,
		comfyNightSaturation = 84, comfyNightStrength = 48, comfyNightDarkness = 30, comfyRainDarkness = 28,
		comfyMoonlight = 72, comfyCloudCover = 18, comfyCloudShapes = 44, comfyCloudSoftness = 50,
		comfyCloudShapeBillows = 38, comfyCloudPuffiness = 34, comfyCloudSpeed = 68, comfyGrassWind = 64,
		comfyGrassSpeed = 58, comfyGrassWaveLength = 49, comfyGrassLean = 58, comfyWaterZoneSaturation = 45,   -- water retuned for the bed-colour model; CSV had ZoneSaturation=62
		comfyWaterClarity = 170, comfyWaterBright = 74, comfyWaterReflect = 50, comfyWaterSunset = 70,   -- water retuned for the bed-colour model; CSV had Clarity=80, Bright=72, Reflect=72, Sunset=92
		comfyWaveHeight = 5, comfyWaveSize = 253, comfyLampGlow = 27, comfyLampsDay = 4,
		-- rescaled from the CSV (csv->real): comfyMistReach 78->1582; comfyShadowSoftness 28->2; comfyFoliageShadeSize 36->18; comfyFoliageShadeEdge 42->21; comfyFoliageSelfShade 30->15; comfyRaysSoften 36->6; comfySunlight 120->50; comfyGrassWaveLength 80->49; comfyWaveHeight 16->5; comfyWaveSize 58->253; comfyLampGlow 54->27
	},
	["Arid Badlands / Canyon"] = {   -- Badlands; Thousand Needles; Desolace dry areas
		comfyVolumeStrength = 30, comfyVolumeDensity = 10, comfyVolumeDistance = 90, comfyVolumeDirection = 48,
		comfyMistDensity = 30, comfyMistHeight = 16, comfyMistBrightness = 124, comfyMistSun = 48,
		comfyMistToward = 50, comfyMistHorizon = 64, comfyMistReach = 1658, comfyMistSky = 14,
		comfyMistPatches = 42, comfyMistLow = 10, comfyMistWater = 10, comfyMistMorning = 28,
		comfyMistLamps = 14, comfyMistWind = 82, comfySunShadowStrength = 91, comfyShadowSoftness = 3,
		comfyTreeShade = 48, comfyFoliageShadeSize = 19, comfyFoliageShadeEdge = 23, comfyFoliageSelfShade = 17,
		comfyRaysStrength = 32, comfyRaysSoften = 6, comfySunlight = 34, comfyDaySaturation = 94,
		comfyNightSaturation = 82, comfyNightStrength = 50, comfyNightDarkness = 32, comfyRainDarkness = 34,
		comfyMoonlight = 68, comfyCloudCover = 34, comfyCloudShapes = 58, comfyCloudSoftness = 54,
		comfyCloudShapeBillows = 56, comfyCloudPuffiness = 52, comfyCloudSpeed = 74, comfyGrassWind = 72,
		comfyGrassSpeed = 62, comfyGrassWaveLength = 45, comfyGrassLean = 68, comfyWaterZoneSaturation = 35,   -- water retuned for the bed-colour model; CSV had ZoneSaturation=58
		comfyWaterClarity = 120, comfyWaterBright = 62, comfyWaterReflect = 45, comfyWaterSunset = 60,   -- water retuned for the bed-colour model; CSV had Clarity=72, Bright=64, Reflect=60, Sunset=88
		comfyWaveHeight = 4, comfyWaveSize = 246, comfyLampGlow = 29, comfyLampsDay = 6,
		-- rescaled from the CSV (csv->real): comfyMistReach 82->1658; comfyShadowSoftness 34->3; comfyFoliageShadeSize 38->19; comfyFoliageShadeEdge 46->23; comfyFoliageSelfShade 34->17; comfyRaysSoften 38->6; comfySunlight 114->48; comfyGrassWaveLength 74->45; comfyWaveHeight 14->4; comfyWaveSize 56->246; comfyLampGlow 58->29
	},
	["Snow / Tundra"] = {   -- Dun Morogh; Winterspring
		comfyVolumeStrength = 34, comfyVolumeDensity = 10, comfyVolumeDistance = 90, comfyVolumeDirection = 52,
		comfyMistDensity = 26, comfyMistHeight = 20, comfyMistBrightness = 142, comfyMistSun = 46,
		comfyMistToward = 48, comfyMistHorizon = 58, comfyMistReach = 1430, comfyMistSky = 20,
		comfyMistPatches = 32, comfyMistLow = 24, comfyMistWater = 16, comfyMistMorning = 40,
		comfyMistLamps = 28, comfyMistWind = 68, comfySunShadowStrength = 66, comfyShadowSoftness = 6,
		comfyTreeShade = 62, comfyFoliageShadeSize = 23, comfyFoliageShadeEdge = 36, comfyFoliageSelfShade = 23,
		comfyRaysStrength = 30, comfyRaysSoften = 11, comfySunlight = 30, comfyDaySaturation = 88,
		comfyNightSaturation = 78, comfyNightStrength = 58, comfyNightDarkness = 34, comfyRainDarkness = 42,
		comfyMoonlight = 76, comfyCloudCover = 58, comfyCloudShapes = 52, comfyCloudSoftness = 82,
		comfyCloudShapeBillows = 44, comfyCloudPuffiness = 46, comfyCloudSpeed = 52, comfyGrassWind = 54,
		comfyGrassSpeed = 48, comfyGrassWaveLength = 40, comfyGrassLean = 46, comfyWaterZoneSaturation = 30,   -- water retuned for the bed-colour model; CSV had ZoneSaturation=48
		comfyWaterClarity = 150, comfyWaterBright = 70, comfyWaterReflect = 55, comfyWaterSunset = 50,   -- water retuned for the bed-colour model; CSV had Clarity=86, Bright=78, Reflect=80, Sunset=70
		comfyWaveHeight = 4, comfyWaveSize = 225, comfyLampGlow = 38, comfyLampsDay = 24,
		-- rescaled from the CSV (csv->real): comfyMistReach 70->1430; comfyShadowSoftness 72->6; comfyFoliageShadeSize 46->23; comfyFoliageShadeEdge 72->36; comfyFoliageSelfShade 46->23; comfyRaysSoften 68->11; comfySunlight 104->43; comfyGrassWaveLength 64->40; comfyWaveHeight 12->4; comfyWaveSize 50->225; comfyLampGlow 76->38
	},
	["Mountain / Alpine"] = {   -- Alterac Mountains; high ridges; mountain passes
		comfyVolumeStrength = 28, comfyVolumeDensity = 7, comfyVolumeDistance = 100, comfyVolumeDirection = 66,
		comfyMistDensity = 14, comfyMistHeight = 12, comfyMistBrightness = 132, comfyMistSun = 52,
		comfyMistToward = 62, comfyMistHorizon = 48, comfyMistReach = 1088, comfyMistSky = 8,
		comfyMistPatches = 24, comfyMistLow = 10, comfyMistWater = 12, comfyMistMorning = 34,
		comfyMistLamps = 14, comfyMistWind = 84, comfySunShadowStrength = 94, comfyShadowSoftness = 2,
		comfyTreeShade = 64, comfyFoliageShadeSize = 21, comfyFoliageShadeEdge = 24, comfyFoliageSelfShade = 20,
		comfyRaysStrength = 44, comfyRaysSoften = 6, comfySunlight = 34, comfyDaySaturation = 98,
		comfyNightSaturation = 82, comfyNightStrength = 56, comfyNightDarkness = 36, comfyRainDarkness = 40,
		comfyMoonlight = 74, comfyCloudCover = 46, comfyCloudShapes = 72, comfyCloudSoftness = 50,
		comfyCloudShapeBillows = 72, comfyCloudPuffiness = 66, comfyCloudSpeed = 82, comfyGrassWind = 84,
		comfyGrassSpeed = 72, comfyGrassWaveLength = 42, comfyGrassLean = 76, comfyWaterZoneSaturation = 45,   -- water retuned for the bed-colour model; CSV had ZoneSaturation=64
		comfyWaterClarity = 160, comfyWaterBright = 66, comfyWaterReflect = 58, comfyWaterSunset = 60,   -- water retuned for the bed-colour model; CSV had Clarity=82, Bright=68, Reflect=78, Sunset=82
		comfyWaveHeight = 6, comfyWaveSize = 211, comfyLampGlow = 30, comfyLampsDay = 8,
		-- rescaled from the CSV (csv->real): comfyMistReach 52->1088; comfyShadowSoftness 30->2; comfyFoliageShadeSize 42->21; comfyFoliageShadeEdge 48->24; comfyFoliageSelfShade 40->20; comfyRaysSoften 40->6; comfySunlight 116->48; comfyGrassWaveLength 68->42; comfyWaveHeight 20->6; comfyWaveSize 46->211; comfyLampGlow 60->30
	},
	["Coastal / Island"] = {   -- Darkshore coast; Westfall coast; Tel'Abim-style islands; Booty Bay approaches
		comfyVolumeStrength = 36, comfyVolumeDensity = 11, comfyVolumeDistance = 88, comfyVolumeDirection = 62,
		comfyMistDensity = 34, comfyMistHeight = 20, comfyMistBrightness = 118, comfyMistSun = 46,
		comfyMistToward = 54, comfyMistHorizon = 66, comfyMistReach = 1582, comfyMistSky = 20,
		comfyMistPatches = 38, comfyMistLow = 18, comfyMistWater = 72, comfyMistMorning = 58,
		comfyMistLamps = 32, comfyMistWind = 72, comfySunShadowStrength = 78, comfyShadowSoftness = 4,
		comfyTreeShade = 56, comfyFoliageShadeSize = 23, comfyFoliageShadeEdge = 29, comfyFoliageSelfShade = 21,
		comfyRaysStrength = 42, comfyRaysSoften = 8, comfySunlight = 31, comfyDaySaturation = 98,
		comfyNightSaturation = 84, comfyNightStrength = 52, comfyNightDarkness = 28, comfyRainDarkness = 44,
		comfyMoonlight = 70, comfyCloudCover = 52, comfyCloudShapes = 72, comfyCloudSoftness = 58,
		comfyCloudShapeBillows = 72, comfyCloudPuffiness = 70, comfyCloudSpeed = 74, comfyGrassWind = 70,
		comfyGrassSpeed = 60, comfyGrassWaveLength = 38, comfyGrassLean = 58, comfyWaterZoneSaturation = 48,   -- water retuned for the bed-colour model; CSV had ZoneSaturation=68
		comfyWaterClarity = 140, comfyWaterBright = 66, comfyWaterReflect = 60, comfyWaterSunset = 75,   -- water retuned for the bed-colour model; CSV had Clarity=70, Bright=66, Reflect=82, Sunset=90
		comfyWaveHeight = 13, comfyWaveSize = 246, comfyLampGlow = 34, comfyLampsDay = 12,
		-- rescaled from the CSV (csv->real): comfyMistReach 78->1582; comfyShadowSoftness 50->4; comfyFoliageShadeSize 46->23; comfyFoliageShadeEdge 58->29; comfyFoliageSelfShade 42->21; comfyRaysSoften 52->8; comfySunlight 108->45; comfyGrassWaveLength 60->38; comfyWaveHeight 42->13; comfyWaveSize 56->246; comfyLampGlow 68->34
	},
	["Volcanic / Scorched"] = {   -- Burning Steppes; Searing Gorge; volcanic subzones
		comfyVolumeStrength = 38, comfyVolumeDensity = 17, comfyVolumeDistance = 64, comfyVolumeDirection = 40,
		comfyMistDensity = 54, comfyMistHeight = 34, comfyMistBrightness = 72, comfyMistSun = 28,
		comfyMistToward = 34, comfyMistHorizon = 38, comfyMistReach = 1658, comfyMistSky = 42,
		comfyMistPatches = 72, comfyMistLow = 42, comfyMistWater = 20, comfyMistMorning = 36,
		comfyMistLamps = 62, comfyMistWind = 76, comfySunShadowStrength = 92, comfyShadowSoftness = 3,
		comfyTreeShade = 60, comfyFoliageShadeSize = 21, comfyFoliageShadeEdge = 21, comfyFoliageSelfShade = 23,
		comfyRaysStrength = 26, comfyRaysSoften = 9, comfySunlight = 27, comfyDaySaturation = 78,
		comfyNightSaturation = 72, comfyNightStrength = 64, comfyNightDarkness = 44, comfyRainDarkness = 48,
		comfyMoonlight = 52, comfyCloudCover = 68, comfyCloudShapes = 72, comfyCloudSoftness = 58,
		comfyCloudShapeBillows = 64, comfyCloudPuffiness = 56, comfyCloudSpeed = 68, comfyGrassWind = 66,
		comfyGrassSpeed = 56, comfyGrassWaveLength = 36, comfyGrassLean = 62, comfyWaterZoneSaturation = 18,   -- water retuned for the bed-colour model; CSV had ZoneSaturation=46
		comfyWaterClarity = 80, comfyWaterBright = 46, comfyWaterReflect = 34, comfyWaterSunset = 30,   -- water retuned for the bed-colour model; CSV had Clarity=40, Bright=42, Reflect=38, Sunset=64
		comfyWaveHeight = 4, comfyWaveSize = 204, comfyLampGlow = 44, comfyLampsDay = 38,
		-- rescaled from the CSV (csv->real): comfyMistReach 82->1658; comfyShadowSoftness 34->3; comfyFoliageShadeSize 42->21; comfyFoliageShadeEdge 42->21; comfyFoliageSelfShade 46->23; comfyRaysSoften 54->9; comfySunlight 94->39; comfyGrassWaveLength 58->36; comfyWaveHeight 12->4; comfyWaveSize 44->204; comfyLampGlow 88->44
	},
	["Corrupted / Blighted"] = {   -- Felwood; Western/Eastern Plaguelands; corrupted subzones
		comfyVolumeStrength = 48, comfyVolumeDensity = 21, comfyVolumeDistance = 58, comfyVolumeDirection = 32,
		comfyMistDensity = 64, comfyMistHeight = 38, comfyMistBrightness = 68, comfyMistSun = 20,
		comfyMistToward = 24, comfyMistHorizon = 20, comfyMistReach = 1734, comfyMistSky = 54,
		comfyMistPatches = 80, comfyMistLow = 70, comfyMistWater = 58, comfyMistMorning = 66,
		comfyMistLamps = 82, comfyMistWind = 20, comfySunShadowStrength = 83, comfyShadowSoftness = 4,
		comfyTreeShade = 84, comfyFoliageShadeSize = 34, comfyFoliageShadeEdge = 26, comfyFoliageSelfShade = 34,
		comfyRaysStrength = 18, comfyRaysSoften = 12, comfySunlight = 20, comfyDaySaturation = 74,
		comfyNightSaturation = 70, comfyNightStrength = 70, comfyNightDarkness = 46, comfyRainDarkness = 54,
		comfyMoonlight = 50, comfyCloudCover = 80, comfyCloudShapes = 78, comfyCloudSoftness = 66,
		comfyCloudShapeBillows = 56, comfyCloudPuffiness = 54, comfyCloudSpeed = 26, comfyGrassWind = 26,
		comfyGrassSpeed = 28, comfyGrassWaveLength = 34, comfyGrassLean = 30, comfyWaterZoneSaturation = 22,   -- water retuned for the bed-colour model; CSV had ZoneSaturation=42
		comfyWaterClarity = 80, comfyWaterBright = 50, comfyWaterReflect = 36, comfyWaterSunset = 30,   -- water retuned for the bed-colour model; CSV had Clarity=34, Bright=34, Reflect=36, Sunset=46
		comfyWaveHeight = 3, comfyWaveSize = 211, comfyLampGlow = 45, comfyLampsDay = 42,
		-- rescaled from the CSV (csv->real): comfyMistReach 86->1734; comfyShadowSoftness 54->4; comfyFoliageShadeSize 68->34; comfyFoliageShadeEdge 52->26; comfyFoliageSelfShade 68->34; comfyRaysSoften 78->12; comfySunlight 70->29; comfyGrassWaveLength 54->34; comfyWaveHeight 10->3; comfyWaveSize 46->211; comfyLampGlow 90->45
	},
	-- not in the CSV: cities and dungeons keep the earlier conservative drafts
	["City"]    = { comfyMistDensity = 40, comfyMistHeight = 120, comfyVolumeStrength = 18, comfyLampGlow = 28 },
	["Dungeon"] = { comfyMistDensity = 20, comfyVolumeStrength = 0, comfyLampGlow = 30, comfyIndoorLamps = 60 },
}

-- ---- zone layer: manual overrides on top of the biome baseline (zone name = GetRealZoneText()) -------------------------
D.Zones = {
	["Stormwind City"] = { comfyMistDensity = 38, comfyLampGlow = 28 },
	-- ["Elwynn Forest"] = { },
}

-- ---- subzone layer: key is "Zone/Subzone" (GetRealZoneText()/GetSubZoneText()) --------------------------------------
D.Subzones = {
	-- ["Westfall/Sentinel Hill"] = { },
}

-- ---- applied on top whenever the player is indoors (IsIndoors(), or inside a building as ComfyAtmosphere sees it) ----
-- (CSV Interior_Override: "reduce sun/rays/grass, increase local lamp emphasis" -- guidance only, no numbers, so these stay drafts)
-- dark ambient comes from EqShaders (indoor toe curve); here the local lights get their pools and the air stays clear
D.Interior = { comfyVolumeStrength = 0, comfyMistDensity = 15, comfyMistHeight = 60, comfyIndoorLamps = 65 }

-- ---- applied (blended by how dark the game clock is) when the clock says night ----------------------------------------
-- Night starts to blend at 19:00 and is complete at 21:00; dawn reverses it between 05:00 and 07:00.
-- (CSV Night_Override: "blend separate Night layer; do not bake night into biome values" -- no numbers either)
D.Night = { comfyMistBrightness = 55, comfyVolumeStrength = 8 }

-- ---- which biome each vanilla zone belongs to (zones missing here use Global only) --------------------------------------
D.ZoneBiome = {
	["Elwynn Forest"] = "Temperate Forest",
	["Redridge Mountains"] = "Temperate Forest",
	["Hillsbrad Foothills"] = "Temperate Forest",
	["Loch Modan"] = "Temperate Forest",
	["Ashenvale"] = "Enchanted / Ancient Forest",
	["Moonglade"] = "Enchanted / Ancient Forest",
	["Feralas"] = "Enchanted / Ancient Forest",
	["Teldrassil"] = "Enchanted / Ancient Forest",
	["Duskwood"] = "Dark / Haunted Forest",
	["Tirisfal Glades"] = "Dark / Haunted Forest",
	["Silverpine Forest"] = "Dark / Haunted Forest",
	["Deadwind Pass"] = "Dark / Haunted Forest",
	["Stranglethorn Vale"] = "Tropical Jungle",
	["Un'Goro Crater"] = "Tropical Jungle",
	["The Hinterlands"] = "Tropical Jungle",
	["Zul'Gurub"] = "Tropical Jungle",
	["Swamp of Sorrows"] = "Swamp / Marsh",
	["Wetlands"] = "Swamp / Marsh",
	["Dustwallow Marsh"] = "Swamp / Marsh",
	["Mulgore"] = "Grassland / Plains",
	["The Barrens"] = "Grassland / Plains",
	["Arathi Highlands"] = "Grassland / Plains",
	["Westfall"] = "Grassland / Plains",
	["Tanaris"] = "Desert / Dunes",
	["Silithus"] = "Desert / Dunes",
	["Ruins of Ahn'Qiraj"] = "Desert / Dunes",
	["Badlands"] = "Arid Badlands / Canyon",
	["Thousand Needles"] = "Arid Badlands / Canyon",
	["Desolace"] = "Arid Badlands / Canyon",
	["Durotar"] = "Arid Badlands / Canyon",
	["Dun Morogh"] = "Snow / Tundra",
	["Winterspring"] = "Snow / Tundra",
	["Alterac Mountains"] = "Mountain / Alpine",
	["Stonetalon Mountains"] = "Mountain / Alpine",
	["Darkshore"] = "Coastal / Island",
	["Azshara"] = "Coastal / Island",
	["Burning Steppes"] = "Volcanic / Scorched",
	["Searing Gorge"] = "Volcanic / Scorched",
	["Blasted Lands"] = "Volcanic / Scorched",
	["Felwood"] = "Corrupted / Blighted",
	["Western Plaguelands"] = "Corrupted / Blighted",
	["Eastern Plaguelands"] = "Corrupted / Blighted",
	["Stormwind City"] = "City",
	["Ironforge"] = "City",
	["Darnassus"] = "City",
	["Orgrimmar"] = "City",
	["Undercity"] = "City",
	["Thunder Bluff"] = "City",
	["The Deadmines"] = "Dungeon",
	["Wailing Caverns"] = "Dungeon",
	["Shadowfang Keep"] = "Dungeon",
	["Blackfathom Deeps"] = "Dungeon",
	["The Stockade"] = "Dungeon",
	["Gnomeregan"] = "Dungeon",
	["Razorfen Kraul"] = "Dungeon",
	["Razorfen Downs"] = "Dungeon",
	["Scarlet Monastery"] = "Dungeon",
	["Uldaman"] = "Dungeon",
	["Zul'Farrak"] = "Dungeon",
	["Maraudon"] = "Dungeon",
	["Sunken Temple"] = "Dungeon",
	["Blackrock Depths"] = "Dungeon",
	["Blackrock Spire"] = "Dungeon",
	["Dire Maul"] = "Dungeon",
	["Scholomance"] = "Dungeon",
	["Stratholme"] = "Dungeon",
	["Ragefire Chasm"] = "Dungeon",
	["Molten Core"] = "Dungeon",
	["Blackwing Lair"] = "Dungeon",
	["Onyxia's Lair"] = "Dungeon",
	["Temple of Ahn'Qiraj"] = "Dungeon",
	["Naxxramas"] = "Dungeon",
}

-- ---- ground wetness tendency per biome (read by EqShaders' wet-ground effect through a pixel strip) ----------------------
-- { baseline ground wetness, baseline puddle tendency, murk }, each 0..1. Rain raises wetness above the baseline and it dries
-- back down to it; murk tints puddles muddy. Zones[...] style overrides go in WetZone. Indoors the effect is switched off.
D.WetBase = {
	["Swamp / Marsh"]            = { 0.55, 0.70, 0.30 },
	["Tropical Jungle"]          = { 0.40, 0.50, 0.15 },
	["Temperate Forest"]         = { 0.12, 0.20, 0.10 },
	["Enchanted / Ancient Forest"] = { 0.20, 0.28, 0.10 },
	["Dark / Haunted Forest"]    = { 0.22, 0.30, 0.35 },
	["Coastal / Island"]         = { 0.18, 0.28, 0.10 },
	["Grassland / Plains"]       = { 0.08, 0.15, 0.10 },
	["Snow / Tundra"]            = { 0.04, 0.04, 0.00 },
	["Mountain / Alpine"]        = { 0.03, 0.05, 0.00 },
	["Desert / Dunes"]           = { 0.00, 0.00, 0.00 },
	["Arid Badlands / Canyon"]   = { 0.02, 0.01, 0.10 },
	["Volcanic / Scorched"]      = { 0.00, 0.00, 0.20 },
	["Corrupted / Blighted"]     = { 0.18, 0.22, 0.60 },
	["City"]                     = { 0.05, 0.08, 0.10 },
	["Dungeon"]                  = { 0.00, 0.00, 0.00 },
}
D.WetZone = {
	-- ["Zone Name"] = { wet, puddle, murk },
}