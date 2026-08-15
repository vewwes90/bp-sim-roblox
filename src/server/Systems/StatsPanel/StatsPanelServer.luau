--[[
	StatsPanelServer.lua
	Location: ServerScriptService/Systems/StatsPanel/StatsPanelServer

	WHAT THIS DOES:
	- Builds a display-ready payload from a player's generated stats
	  (StatGenerator.GetStats), using StatGenerator.GetTierName for the 4
	  parent stats exactly as already defined -- no new tier logic here.
	- Pushes that payload to the client via StatsUpdateEvent, either:
		(a) proactively, right after TimelapseGenerator runs (called from
		    ConceptionRaceServer), or
		(b) on demand, when the client fires RequestStatsEvent (e.g. the
		    player opens the stats panel after rejoining, before any push
		    has happened this session).
	- Sub-stats are sent as raw 1-100 values with no tier name, because
	  StatGenerator.GetTierName only has tier tables for the 4 parent
	  stats (PhysicalAppearance/Intelligence/Wealth/SocialStatus), not
	  individual sub-stats -- this module does not invent sub-stat tiers.

	HOW THIS GETS CALLED:
		local StatsPanelServer = require(path.to.StatsPanelServer)
		StatsPanelServer.PushToPlayer(player) -- after TimelapseGenerator
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatGenerator = require(ServerScriptService.Systems.StatGeneration.StatGenerator)

local requestStatsEvent = ReplicatedStorage:FindFirstChild("RequestStatsEvent")
local statsUpdateEvent = ReplicatedStorage:FindFirstChild("StatsUpdateEvent")

local StatsPanelServer = {}

local PARENT_STAT_ORDER = { "PhysicalAppearance", "Intelligence", "Wealth", "SocialStatus" }

local PARENT_STAT_DISPLAY_NAMES = {
	PhysicalAppearance = "Physical Appearance",
	Intelligence = "Intelligence",
	Wealth = "Wealth",
	SocialStatus = "Social Status",
}

-- Matches StatGenerator.STAT_DEFINITIONS exactly -- used only to group
-- sub-stat display rows under the right parent stat, not to compute anything.
local SUB_STATS_BY_PARENT = {
	PhysicalAppearance = { "Height", "Frame", "Appeal", "Hair" },
	Intelligence = { "Intuitiveness", "Analytic", "Memory", "Creativity", "Conscientiousness" },
	Wealth = { "FinancialDiscipline", "Generosity", "Frugality", "RiskTolerance" },
	SocialStatus = { "Humor", "Outgoingness", "Relatability", "Kindness", "Confidence" },
}

--[[
	BuildPayload(player)
	Returns nil if the player has no generated stats yet, otherwise:
		{
			parentStats = {
				{ statName, displayName, value, tierName },
				...
			},
			subStatsByParent = {
				PhysicalAppearance = { { name = "Height", value = n }, ... },
				...
			},
		}
]]
local function buildPayload(player: Player)
	local stats = StatGenerator.GetStats(player)
	if not stats or not stats.parentStats or not stats.subStats then
		return nil
	end

	local parentStats = {}
	for _, statName in PARENT_STAT_ORDER do
		local value = stats.parentStats[statName]
		table.insert(parentStats, {
			statName = statName,
			displayName = PARENT_STAT_DISPLAY_NAMES[statName],
			value = value,
			tierName = StatGenerator.GetTierName(statName, value),
		})
	end

	local subStatsByParent = {}
	for parentName, subNames in SUB_STATS_BY_PARENT do
		local rows = {}
		for _, subName in subNames do
			table.insert(rows, { name = subName, value = stats.subStats[subName] })
		end
		subStatsByParent[parentName] = rows
	end

	return {
		parentStats = parentStats,
		subStatsByParent = subStatsByParent,
	}
end

--[[
	PushToPlayer(player)
	Builds the payload and fires StatsUpdateEvent to the player if they have
	stats yet. Safe to call even if they don't -- does nothing in that case.
	Returns the payload (or nil).
]]
function StatsPanelServer.PushToPlayer(player: Player)
	local payload = buildPayload(player)
	if payload and statsUpdateEvent then
		statsUpdateEvent:FireClient(player, payload)
	end
	return payload
end

-- Client asks for a refresh (e.g. panel opened with no push received yet this session).
if requestStatsEvent then
	requestStatsEvent.OnServerEvent:Connect(function(player)
		StatsPanelServer.PushToPlayer(player)
	end)
end

return StatsPanelServer
