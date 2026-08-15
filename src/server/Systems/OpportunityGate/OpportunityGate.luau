--[[
	OpportunityGate.lua
	Location: ServerScriptService/Systems/OpportunityGate/OpportunityGate

	WHAT THIS DOES:
	A generic, reusable stat-threshold access check. It does NOT hardcode
	any specific gate (a job, a housing tier, an event) -- none of that
	exists yet (jobs/housing/shop are still undecided per the project doc,
	and the 9-event bank isn't built). Instead this module gives every
	future system a single, consistent way to ask "does this player's stats
	qualify?" without each system reinventing its own threshold-checking
	logic or duplicating access to StatGenerator.

	USAGE (by a FUTURE system, e.g. a job posting):
		local OpportunityGate = require(path.to.OpportunityGate)

		local requirements = {
			{ statType = "parent", stat = "Intelligence", min = 50 },
			{ statType = "sub", stat = "Conscientiousness", min = 60 },
		}

		local allowed, failure = OpportunityGate.CheckAccess(player, requirements)
		if not allowed then
			-- failure.reasonCode, failure.stat, failure.statType, failure.actualValue,
			-- failure.min/failure.max are all available for the CALLING system to
			-- build its OWN specific denial flavor text (a job rejection should read
			-- differently than a housing application rejection) -- this module
			-- deliberately does not invent that content itself. OpportunityGate.
			-- DefaultDenialMessage(failure) is available as a generic bleak-toned
			-- fallback if a caller doesn't have custom text yet.
		end

	Requirement fields:
		statType: "parent" (one of the 4 parent stats) or "sub" (one of the 17
		          sub-stats) -- must match StatGenerator's exact names.
		stat:     exact stat name string, e.g. "Wealth" or "RiskTolerance".
		min:      optional number -- fails if the player's value is below this.
		max:      optional number -- fails if the player's value is above this
		          (useful for gates that require NOT having too much of
		          something, e.g. a charity program capped by Wealth).
		At least one of min/max should be set; a requirement with neither
		always passes.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local StatGenerator = require(ServerScriptService.Systems.StatGeneration.StatGenerator)

local OpportunityGate = {}

local function getStatValue(stats, statType, statName)
	if statType == "parent" then
		return stats.parentStats and stats.parentStats[statName]
	elseif statType == "sub" then
		return stats.subStats and stats.subStats[statName]
	end
	return nil
end

--[[
	CheckAccess(player, requirements)

	requirements: array of requirement tables (see field docs above). An
	empty or nil requirements list always passes (no conditions to fail).

	Returns:
		allowed: boolean
		failure: nil if allowed, otherwise a table:
			{
				reasonCode = "NoStats" | "UnknownStat" | "BelowMin" | "AboveMax",
				requirement = <the requirement table that failed>, -- nil for NoStats
				stat = string,        -- nil for NoStats
				statType = string,    -- nil for NoStats
				actualValue = number, -- nil for NoStats/UnknownStat
			}

	Checks are evaluated in order and this returns on the FIRST failure --
	it does not collect every failed requirement.
]]
function OpportunityGate.CheckAccess(player: Player, requirements: { any }?)
	local stats = StatGenerator.GetStats(player)
	if not stats then
		return false, { reasonCode = "NoStats" }
	end

	for _, requirement in requirements or {} do
		local value = getStatValue(stats, requirement.statType, requirement.stat)

		if value == nil then
			return false, {
				reasonCode = "UnknownStat",
				requirement = requirement,
				stat = requirement.stat,
				statType = requirement.statType,
			}
		end

		if requirement.min and value < requirement.min then
			return false, {
				reasonCode = "BelowMin",
				requirement = requirement,
				stat = requirement.stat,
				statType = requirement.statType,
				actualValue = value,
			}
		end

		if requirement.max and value > requirement.max then
			return false, {
				reasonCode = "AboveMax",
				requirement = requirement,
				stat = requirement.stat,
				statType = requirement.statType,
				actualValue = value,
			}
		end
	end

	return true, nil
end

--[[
	MeetsThreshold(player, statType, stat, min, max)
	Convenience wrapper around CheckAccess for the common single-condition
	case, so a simple gate doesn't need to build a one-item requirements
	array by hand. Returns the same (allowed, failure) shape.
]]
function OpportunityGate.MeetsThreshold(player: Player, statType: string, stat: string, min: number?, max: number?)
	return OpportunityGate.CheckAccess(player, { { statType = statType, stat = stat, min = min, max = max } })
end

--[[
	DefaultDenialMessage(failure)
	A generic, bleak-toned fallback message built from a CheckAccess failure
	result. Intentionally generic and content-agnostic -- any real system
	(a job, a housing tier) should write its OWN specific denial text using
	failure.stat/failure.statType/failure.actualValue and only fall back to
	this if it doesn't have custom copy yet.
]]
function OpportunityGate.DefaultDenialMessage(failure: { any }): string
	if not failure then
		return ""
	end

	if failure.reasonCode == "NoStats" then
		return "Nothing has been decided about this life yet."
	elseif failure.reasonCode == "UnknownStat" then
		return "That isn't a value this life has."
	elseif failure.reasonCode == "BelowMin" then
		return "Not enough. The number says so."
	elseif failure.reasonCode == "AboveMax" then
		return "Too much. The number says so."
	end

	return "No."
end

return OpportunityGate
