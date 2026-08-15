--[[
	StatGenerator.lua
	Location: ServerScriptService/Systems/StatGeneration/StatGenerator

	WHAT THIS DOES:
	- Rolls all 17 sub-stats for a player using a true bell-curve distribution
	  (Irwin-Hall method -- independent per sub-stat, unlike math.noise which
	  correlates nearby values)
	- Computes the 4 parent stats as equal-weighted averages of their sub-stats
	- Saves everything through PlayerDataManager under the "generatedStats" key
	- Does NOT run automatically on PlayerAdded. This must be called explicitly
	  by the SpawnWheel system once it has a wheel-tier result, so the
	  race -> wheel -> stats sequence happens in the correct order.

	HOW THIS GETS CALLED (once SpawnWheel exists):
		local StatGenerator = require(path.to.StatGenerator)
		local stats = StatGenerator.GenerateForPlayer(player, wheelBias)
		-- wheelBias: a number from -1 (Bleak wheel) to 1 (Fortunate wheel).
		-- Pass 0 or nil to roll with no bias (useful for testing standalone).
]]

local ServerScriptService = game:GetService("ServerScriptService")
local PlayerDataManager = require(ServerScriptService.Systems.DataStore.PlayerDataManager)

local StatGenerator = {}

-- ============================================================
-- SUB-STAT DEFINITIONS (17 total, matches design doc Section D.1)
-- ============================================================

local STAT_DEFINITIONS = {
	PhysicalAppearance = {
		subStats = { "Height", "Frame", "Appeal", "Hair" },
		weights = { Height = 0.25, Frame = 0.25, Appeal = 0.25, Hair = 0.25 },
	},
	Intelligence = {
		subStats = { "Intuitiveness", "Analytic", "Memory", "Creativity", "Conscientiousness" },
		weights = {
			Intuitiveness = 0.2,
			Analytic = 0.2,
			Memory = 0.2,
			Creativity = 0.2,
			Conscientiousness = 0.2,
		},
	},
	Wealth = {
		subStats = { "FinancialDiscipline", "Generosity", "Frugality", "RiskTolerance" },
		weights = {
			FinancialDiscipline = 0.25,
			Generosity = 0.25,
			Frugality = 0.25,
			RiskTolerance = 0.25,
		},
	},
	SocialStatus = {
		subStats = { "Humor", "Outgoingness", "Relatability", "Kindness", "Confidence" },
		weights = {
			Humor = 0.2,
			Outgoingness = 0.2,
			Relatability = 0.2,
			Kindness = 0.2,
			Confidence = 0.2,
		},
	},
}

local RARE_LOW_CHANCE = 0.005  -- 0.5% chance a sub-stat rolls exactly 1
local RARE_HIGH_CHANCE = 0.005 -- 0.5% chance a sub-stat rolls exactly 100

-- ============================================================
-- BELL-CURVE RANDOM (1-100), Irwin-Hall method
-- ============================================================

local function rollBellCurve(rng: Random): number
	local rareRoll = rng:NextNumber()
	if rareRoll < RARE_LOW_CHANCE then
		return 1
	elseif rareRoll > (1 - RARE_HIGH_CHANCE) then
		return 100
	end

	local sum = 0
	local SAMPLES = 4
	for _ = 1, SAMPLES do
		sum += rng:NextInteger(2, 99)
	end
	local average = math.floor(sum / SAMPLES)

	return math.clamp(average, 2, 99)
end

-- wheelBias: -1 (Bleak) to 1 (Fortunate). Shifts the bell curve up or
-- down without destroying its shape or making outcomes deterministic.
local function rollSubStat(rng: Random, wheelBias: number?): number
	local base = rollBellCurve(rng)

	if wheelBias and wheelBias ~= 0 then
		local shift = wheelBias * 15 -- tune this multiplier once playtested
		base = math.clamp(math.floor(base + shift), 1, 100)
	end

	return base
end

local function computeParentStat(subStatValues: { [string]: number }, definition): number
	local total = 0
	for _, subStatName in definition.subStats do
		local weight = definition.weights[subStatName]
		total += subStatValues[subStatName] * weight
	end
	return math.floor(total + 0.5)
end

-- ============================================================
-- PUBLIC API
-- ============================================================

--[[
	GenerateForPlayer(player, wheelBias)

	Call this ONLY after the player has a wheel result -- typically from
	inside SpawnWheel, right after it determines which tier the player
	landed on. Do NOT call this from a PlayerAdded listener.

	Safe to call multiple times: if stats already exist for this player,
	returns the EXISTING stats instead of re-rolling (stats are permanent).
]]
function StatGenerator.GenerateForPlayer(player: Player, wheelBias: number?)
	local existingData = PlayerDataManager.GetData(player)
	if existingData and existingData.generatedStats and existingData.generatedStats.hasGenerated then
		return existingData.generatedStats
	end

	local rng = Random.new(player.UserId + os.time())

	local subStatValues = {}
	local parentStats = {}

	for parentName, definition in STAT_DEFINITIONS do
		local subValues = {}
		for _, subStatName in definition.subStats do
			local value = rollSubStat(rng, wheelBias)
			subValues[subStatName] = value
			subStatValues[subStatName] = value
		end
		parentStats[parentName] = computeParentStat(subValues, definition)
	end

	local statTable = {
		subStats = subStatValues,
		parentStats = parentStats,
		hasGenerated = true,
	}

	PlayerDataManager.SetData(player, "generatedStats", statTable)
	PlayerDataManager.SaveNow(player)

	print(string.format("[StatGenerator] Generated stats for %s (wheelBias=%s):", player.Name, tostring(wheelBias)))
	for parentName, value in parentStats do
		print(string.format("  %s: %d", parentName, value))
	end

	return statTable
end

--[[
	GetStats(player)
	Returns the player's stat table, or nil if they haven't gone through
	the conception sequence yet.
]]
function StatGenerator.GetStats(player: Player)
	local data = PlayerDataManager.GetData(player)
	if data and data.generatedStats and data.generatedStats.hasGenerated then
		return data.generatedStats
	end
	return nil
end

-- ============================================================
-- TIER NAME LOOKUP (display only -- never used for gameplay math)
-- ============================================================

local TIER_TABLES = {
	PhysicalAppearance = {
		{ max = 1, name = "Disfigured" },
		{ max = 24, name = "Repulsive" },
		{ max = 44, name = "Below Average" },
		{ max = 64, name = "Average" },
		{ max = 84, name = "Attractive" },
		{ max = 99, name = "Elite" },
		{ max = 100, name = "Flawless" },
	},
	Intelligence = {
		{ max = 1, name = "Questionably Aware" },
		{ max = 24, name = "Cognitively Impaired" },
		{ max = 44, name = "Slow" },
		{ max = 64, name = "Average" },
		{ max = 84, name = "Smart" },
		{ max = 99, name = "Genius" },
		{ max = 100, name = "Mega Genius" },
	},
	Wealth = {
		{ max = 1, name = "Destitute" },
		{ max = 24, name = "Poor" },
		{ max = 44, name = "Modest" },
		{ max = 64, name = "Comfortable" },
		{ max = 84, name = "Wealthy" },
		{ max = 99, name = "Elite" },
		{ max = 100, name = "Dynastic" },
	},
	SocialStatus = {
		{ max = 1, name = "Pariah" },
		{ max = 24, name = "Outcast" },
		{ max = 44, name = "Overlooked" },
		{ max = 64, name = "Unremarkable" },
		{ max = 84, name = "Well-Regarded" },
		{ max = 99, name = "Influential" },
		{ max = 100, name = "Legacy" },
	},
}

function StatGenerator.GetTierName(parentStatName: string, value: number): string
	local tiers = TIER_TABLES[parentStatName]
	if not tiers then
		warn("[StatGenerator] No tier table found for: " .. tostring(parentStatName))
		return "Unknown"
	end

	for _, tier in tiers do
		if value <= tier.max then
			return tier.name
		end
	end

	return "Unknown"
end

return StatGenerator
