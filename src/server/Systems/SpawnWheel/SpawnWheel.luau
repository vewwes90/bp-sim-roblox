--[[
	SpawnWheel.lua
	Location: ServerScriptService/Systems/SpawnWheel/SpawnWheel

	WHAT THIS DOES:
	- Takes a player's conception-race placement (1-10) and picks one of the
	  4 wheels (Fortunate/Average/Difficult/Bleak) using placement-weighted,
	  bracket-based odds.
	- Rolls one of 3 named segments within that wheel to get a wheelBias
	  value (-1 to 1).
	- Calls StatGenerator.GenerateForPlayer(player, wheelBias) to actually
	  roll the player's stats.
	- Fires SpawnWheelResultEvent to the player with the wheel/segment
	  result for the client-side wheel-spin UI to display.

	ODDS TABLE (bracket-based, confirmed with project owner 2026-08-14):
	  Placement 1-2  (top):    Fortunate 60% / Average 30% / Difficult 8%  / Bleak 2%
	  Placement 3-5  (upper):  Fortunate 20% / Average 55% / Difficult 20% / Bleak 5%
	  Placement 6-8  (lower):  Fortunate 5%  / Average 20% / Difficult 55% / Bleak 20%
	  Placement 9-10 (bottom): Fortunate 2%  / Average 8%  / Difficult 30% / Bleak 60%
	Every bracket keeps a nonzero chance at every wheel -- no placement is
	ever locked out of the best or worst outcome. This is intentional per
	the game's core theme: unfair by design, but never literally impossible.

	SEGMENTS (3 per wheel, equal 1/3 odds within the wheel, confirmed with
	project owner 2026-08-14):
	  Fortunate: Great (+1.0)  / Good (+0.7)   / Fine (+0.45)
	  Average:   Lucky (+0.15) / Neutral (0)   / Unlucky (-0.15)
	  Difficult: Rough (-0.45) / Hard (-0.7)   / Severe (-0.85)
	  Bleak:     Grim (-0.9)   / Dire (-0.95)  / Doomed (-1.0)
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatGenerator = require(ServerScriptService.Systems.StatGeneration.StatGenerator)

local spawnWheelResultEvent = ReplicatedStorage:FindFirstChild("SpawnWheelResultEvent")

local SpawnWheel = {}

-- ============================================================
-- WHEEL ODDS BY PLACEMENT BRACKET
-- ============================================================

local WHEEL_NAMES = { "Fortunate", "Average", "Difficult", "Bleak" }

local ODDS_BY_BRACKET = {
	{ maxPlacement = 2, odds = { Fortunate = 0.60, Average = 0.30, Difficult = 0.08, Bleak = 0.02 } },
	{ maxPlacement = 5, odds = { Fortunate = 0.20, Average = 0.55, Difficult = 0.20, Bleak = 0.05 } },
	{ maxPlacement = 8, odds = { Fortunate = 0.05, Average = 0.20, Difficult = 0.55, Bleak = 0.20 } },
	{ maxPlacement = 10, odds = { Fortunate = 0.02, Average = 0.08, Difficult = 0.30, Bleak = 0.60 } },
}

local function getOddsForPlacement(placement: number)
	for _, bracket in ODDS_BY_BRACKET do
		if placement <= bracket.maxPlacement then
			return bracket.odds
		end
	end
	-- Fallback: anything out of the expected 1-10 range treated as bottom bracket
	return ODDS_BY_BRACKET[#ODDS_BY_BRACKET].odds
end

local function pickWheel(rng: Random, placement: number): string
	local odds = getOddsForPlacement(placement)
	local roll = rng:NextNumber()
	local cumulative = 0
	for _, wheelName in WHEEL_NAMES do
		cumulative += odds[wheelName]
		if roll <= cumulative then
			return wheelName
		end
	end
	return WHEEL_NAMES[#WHEEL_NAMES] -- fallback for floating point edge case
end

-- ============================================================
-- SEGMENTS BY WHEEL (equal odds within the wheel)
-- ============================================================

local SEGMENTS_BY_WHEEL = {
	Fortunate = {
		{ name = "Great", bias = 1.0 },
		{ name = "Good", bias = 0.7 },
		{ name = "Fine", bias = 0.45 },
	},
	Average = {
		{ name = "Lucky", bias = 0.15 },
		{ name = "Neutral", bias = 0 },
		{ name = "Unlucky", bias = -0.15 },
	},
	Difficult = {
		{ name = "Rough", bias = -0.45 },
		{ name = "Hard", bias = -0.7 },
		{ name = "Severe", bias = -0.85 },
	},
	Bleak = {
		{ name = "Grim", bias = -0.9 },
		{ name = "Dire", bias = -0.95 },
		{ name = "Doomed", bias = -1.0 },
	},
}

local function pickSegment(rng: Random, wheelName: string)
	local segments = SEGMENTS_BY_WHEEL[wheelName]
	local index = rng:NextInteger(1, #segments)
	return segments[index]
end

-- ============================================================
-- PUBLIC API
-- ============================================================

--[[
	RollForPlayer(player, placement)

	Call this once per player, right after ConceptionRaceServer determines
	their race placement (1-10). Picks a wheel, picks a segment, rolls the
	player's stats via StatGenerator, fires SpawnWheelResultEvent to the
	player, and returns the full result table.

	Returns:
		{
			wheelName = "Fortunate" | "Average" | "Difficult" | "Bleak",
			segmentName = string,
			wheelBias = number, -- -1 to 1, passed to StatGenerator
			stats = <StatGenerator stat table>,
		}
]]
function SpawnWheel.RollForPlayer(player: Player, placement: number)
	assert(type(placement) == "number" and placement >= 1 and placement <= 10, "placement must be 1-10")

	local rng = Random.new(player.UserId + os.time())

	local wheelName = pickWheel(rng, placement)
	local segment = pickSegment(rng, wheelName)

	local stats = StatGenerator.GenerateForPlayer(player, segment.bias)

	if spawnWheelResultEvent then
		spawnWheelResultEvent:FireClient(player, wheelName, segment.name, segment.bias)
	end

	print(string.format(
		"[SpawnWheel] %s placed #%d -> %s wheel, %s segment (bias %.2f)",
		player.Name, placement, wheelName, segment.name, segment.bias
	))

	return {
		wheelName = wheelName,
		segmentName = segment.name,
		wheelBias = segment.bias,
		stats = stats,
	}
end

return SpawnWheel
