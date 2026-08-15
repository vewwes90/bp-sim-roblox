--[[
	TimelapseGenerator.lua
	Location: ServerScriptService/Systems/Timelapse/TimelapseGenerator

	WHAT THIS DOES:
	- Builds the procedural birth-to-high-school narrative for a player, using
	  their already-generated stats (StatGenerator.GetStats).
	- 4 chapters (confirmed with project owner 2026-08-14, "simpler" structure):
		Infancy -> Childhood -> Middle School -> High School
	- Each chapter is driven by exactly ONE parent stat, chosen so every
	  chapter reads naturally for that age and all 4 parent stats get used
	  exactly once across the whole timelapse:
		Infancy      -> Physical Appearance (the only stat visibly "present" on a newborn)
		Childhood    -> Intelligence (school starts, learning ability becomes visible)
		Middle School -> Social Status (cliques/popularity peak in salience at this age)
		High School  -> Wealth (family financial reality shapes senior-year prospects)
	- Tier lookup reuses StatGenerator.GetTierName exactly -- this module never
	  redefines tier breakpoints or names, only reuses the canonical ones.
	- 3 pre-written text variants per (chapter, tier) pair, picked at random.
	  Tone: bleak, deterministic, matter-of-fact -- per project tone rules.
	  Never sentimental, never uses real-world hate-group/subculture slang.

	HOW THIS GETS CALLED:
		local TimelapseGenerator = require(path.to.TimelapseGenerator)
		local chapters = TimelapseGenerator.GenerateAndSendToPlayer(player)
		-- Requires StatGenerator.GetStats(player) to already have data (i.e.
		-- call this AFTER SpawnWheel.RollForPlayer, not before).
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatGenerator = require(ServerScriptService.Systems.StatGeneration.StatGenerator)

local timelapseEvent = ReplicatedStorage:FindFirstChild("TimelapseEvent")

local TimelapseGenerator = {}

-- ============================================================
-- CHAPTER STRUCTURE
-- ============================================================

local CHAPTER_ORDER = { "Infancy", "Childhood", "MiddleSchool", "HighSchool" }

local CHAPTER_DISPLAY_NAMES = {
	Infancy = "Infancy",
	Childhood = "Childhood",
	MiddleSchool = "Middle School",
	HighSchool = "High School",
}

local CHAPTER_STAT_MAP = {
	Infancy = "PhysicalAppearance",
	Childhood = "Intelligence",
	MiddleSchool = "SocialStatus",
	HighSchool = "Wealth",
}

-- ============================================================
-- FRAGMENT BANK -- 3 variants per (chapter, tier).
-- Tier name strings MUST match StatGenerator.TIER_TABLES exactly.
-- ============================================================

local FRAGMENT_BANK = {

	Infancy = {
		Disfigured = {
			"The nurses' faces changed before they said a word. Something in the bone structure had gone wrong on the way in, and no amount of swaddling hid it. The chart would carry a note for this. The child would carry the rest.",
			"Even the birth certificate photographer asked for a second take, then gave up. Strangers would learn to look away quickly, and call it politeness.",
			"The pediatrician used the word 'irregular' four times in the first exam. It would not be the last time that word followed this child into a room.",
		},
		Repulsive = {
			"Relatives smiled for the photos and said less than they usually did. Nobody used the word ugly. Nobody needed to.",
			"The features settled early and settled unkindly. Neighbors would remember the face before they remembered the name.",
			"A nurse described the baby as 'a late bloomer, probably' to the parents, the way people describe things they don't expect to happen.",
		},
		["Below Average"] = {
			"Nothing about the face demanded comment, which was itself a kind of verdict. Plain enough to be forgotten in a crowd.",
			"The baby photos would go in the album without complaint and without anyone reaching for them again.",
			"A forgettable set of features, assembled without malice or favor. The kind of face that requires a name tag twice.",
		},
		Average = {
			"An ordinary infant, unremarkable in every measurable way. The kind of face a hundred other families would recognize as their own.",
			"Nothing about the birth suggested a future in either direction. The odds, for now, sat exactly in the middle.",
			"The chart said 'healthy, typical.' Nobody wrote anything else, because there was nothing else to write.",
		},
		Attractive = {
			"The delivery room nurses made a point of it -- not loudly, just enough that the parents noticed them noticing. It would keep happening.",
			"Strangers lingered a beat too long over the stroller. It was the first of many rooms this face would be granted entry to without asking.",
			"Symmetry, in this case, arrived early and stayed. It would open doors this child hadn't yet learned existed.",
		},
		Elite = {
			"People stopped mid-sentence to look. It happened at the hospital, and it would keep happening for the rest of this life, in rooms this child hadn't been born into yet.",
			"The obstetrician joked that this one would never buy a drink at a bar. It wasn't really a joke.",
			"Even swaddled and red-faced, the child drew a small crowd of nurses who had seen thousands of newborns and stopped for this one anyway.",
		},
		Flawless = {
			"There would be a before-and-after to this birth for everyone in the room -- the moment they thought they knew what a striking face looked like, and the moment after, when they didn't anymore.",
			"The photographs from this week would circulate for years, passed around as evidence that the ordinary rules of appearance simply hadn't applied here.",
			"Nobody in that hospital would ever describe this face as merely attractive again. The word stopped being adequate before the first week was out.",
		},
	},

	Childhood = {
		["Questionably Aware"] = {
			"Simple instructions had to be repeated, then repeated again, then simplified further. Teachers ran out of new ways to say the same thing.",
			"The worksheets came back mostly blank, not from defiance but from something that looked, up close, like the information simply hadn't landed anywhere.",
			"By the end of elementary school, the file had grown thick with notes that all said some version of the same thing: further support required, results limited.",
		},
		["Cognitively Impaired"] = {
			"Reading groups were quietly reshuffled to make room. The lowest tier existed for a reason, and this was it.",
			"Homework came home barely started most nights, not out of laziness anyone could point to, just a kind of static that never cleared.",
			"Teachers learned to lower their expectations early and were rarely surprised by the results that followed.",
		},
		Slow = {
			"Concepts arrived a beat behind the rest of the class, every time, in every subject. Not hopeless -- just always running to catch up to a bus that had already left.",
			"Report cards used the word 'developing' so often it stopped meaning anything. It meant this: still behind, quietly, consistently.",
			"Extra tutoring helped, some. It closed the gap without ever quite closing it.",
		},
		Average = {
			"Grades landed in the middle of the bell curve and stayed there, year after year, with the unbothered consistency of a metronome.",
			"Nothing about the report cards demanded a parent-teacher conference. The kind of student a school forgets by name within a year of graduating.",
			"Competent, unremarkable, replaceable. The system was built for children exactly like this one, and processed them accordingly.",
		},
		Smart = {
			"Teachers started keeping the harder worksheets in reserve, just for this one. It became a habit before anyone acknowledged it out loud.",
			"Standardized test scores came back high enough that a letter went home suggesting advanced placement. The letter would not be the last of its kind.",
			"Concepts that took the rest of the class a week took this child an afternoon. Boredom became the more pressing problem than comprehension.",
		},
		Genius = {
			"By third grade, the school had run out of grade-appropriate material and started improvising. Nobody had a real plan for what came next.",
			"A psychologist administered an IQ test that was supposed to be routine. It was not routine. The number went into a file that would follow this child for years.",
			"Teachers stopped calling on this child in class discussions -- not to exclude, but because the answer was never in doubt, and the rest of the room needed a turn.",
		},
		["Mega Genius"] = {
			"The district didn't have a program built for a mind like this one. They would end up building one, specifically, because there was no other option.",
			"A university researcher, of all people, asked to run some tests. The results would be discussed in rooms this child would never see, by people deciding what to do with a number nobody had expected.",
			"Elementary school became a formality this child had already outgrown by the second week. What happened next was less about ability and more about what a system does with someone it wasn't built for.",
		},
	},

	MiddleSchool = {
		Pariah = {
			"The cafeteria has an unwritten map, and this name landed on the part nobody sits near. It would take years to understand why, and by then it wouldn't matter.",
			"Group projects meant getting assigned a group, not choosing one. The distinction mattered more than it should have.",
			"Rumors didn't need to be true to stick. By the end of seventh grade, most of them weren't, and none of that mattered either.",
		},
		Outcast = {
			"There was a group, eventually, but it was the group made of everyone else's rejects -- a coalition built on mutual unpopularity rather than anything shared.",
			"Invitations arrived rarely and always felt like an afterthought, the kind extended because someone counted heads and came up one short.",
			"The hallway had a rhythm this name never quite matched. Close enough to notice. Never close enough to belong.",
		},
		Overlooked = {
			"Not disliked, exactly -- just consistently unconsidered. The kind of name a yearbook committee has to be reminded to include.",
			"Conversations happened around this student more often than with them. Nobody meant anything by it. That was, somehow, the worst part.",
			"By the class photo, most peers could place the face but not the name. It wasn't hostility. It was just how little space had been claimed.",
		},
		Unremarkable = {
			"Neither popular nor unpopular -- filed somewhere in the wide, undifferentiated middle where most of middle school actually happens.",
			"A handful of friends, a stable-enough lunch table, no particular reputation in either direction. The safest kind of invisible.",
			"Nobody wrote anything memorable in the yearbook, and nobody expected them to. The arrangement suited everyone fine.",
		},
		["Well-Regarded"] = {
			"Group chats formed around this name without much discussion. It was simply assumed this one would be included, the way weather is assumed.",
			"Teachers noticed the way other students orbited this one in the hallway, the small gravitational pull that popularity runs on before anyone calls it that.",
			"Birthday parties filled up fast when this name was on the invite list. Other parents took note of who their kids wanted to be around.",
		},
		Influential = {
			"By eighth grade, this name could make or end a friendship with a single comment, and everyone involved knew it, including the teachers who pretended not to.",
			"Trends moved through the grade a few days after this student adopted them, reliably enough that other kids started watching, not following on purpose, just watching.",
			"A single seating choice at lunch could reshuffle the entire social order for a week. Nobody said this out loud. Everybody acted on it.",
		},
		Legacy = {
			"Years later, teachers at this school would still bring up the name unprompted, the way people talk about a particular kind of weather event -- something that reorganized everything around it while it was happening.",
			"This wasn't popularity in the ordinary sense. It was closer to gravity -- other students didn't choose to orbit, they just did, the way planets don't choose anything either.",
			"The yearbook superlatives weren't really a contest by eighth grade. Everyone already knew where this name was going before the votes were counted.",
		},
	},

	HighSchool = {
		Destitute = {
			"College counselors handed out the same brochures to everyone, but some conversations quietly ended at 'brochures.' The number at the bottom of the page did the talking neither adult wanted to.",
			"A part-time job wasn't optional by junior year. The paycheck went toward things that had nothing to do with being a teenager.",
			"Senior photos, class rings, the trip everyone else was going on -- each one arrived as a small, private negotiation this family lost by default.",
		},
		Poor = {
			"The financial aid forms got filled out early and carefully, because there was no version of this plan that could absorb a mistake.",
			"Some doors were technically open. The gap between technically and actually was where most of senior year got spent.",
			"A guidance counselor mentioned a scholarship deadline twice, gently, the way people repeat things they suspect won't get acted on in time.",
		},
		Modest = {
			"Nothing about the household budget made headlines in either direction. Enough to get by, rarely enough to get ahead.",
			"College would mean loans, like it did for most of the graduating class. Not a crisis. Just the ordinary math of an ordinary family.",
			"A used car showed up junior year, secondhand and unglamorous, and it was treated like the achievement it actually was.",
		},
		Comfortable = {
			"Money wasn't a conversation this household needed to have very often, which was, itself, a kind of privilege nobody in it thought to name.",
			"The college list stayed open longer than most -- cost was a factor, not the factor. A small distinction that changed everything downstream.",
			"Summers meant a job if one was wanted, not a job because one was required. The difference shaped more decisions than anyone noticed.",
		},
		Wealthy = {
			"A private tutor appeared sophomore year, quietly, the way solutions do for families that can afford to skip the waiting line.",
			"The car that showed up for a sixteenth birthday wasn't secondhand, and nobody in the family treated that as remarkable.",
			"College applications went out to reach schools without a second thought about the cost of applying, let alone attending.",
		},
		Elite = {
			"A family name opened a few doors before a resume ever had the chance to. Nobody called it what it was, but everyone in the room understood the mechanism.",
			"Vacations were the kind other students only saw in photos. The gap between this household and most others had stopped being subtle years ago.",
			"A donation, a legacy application, a phone call from someone who knew someone -- the ordinary admissions process simply didn't apply the same way here.",
		},
		Dynastic = {
			"This family's name was on a building before this student ever set foot in a classroom named after somebody else's. The rules that governed everyone else's future were, for this one, more of a suggestion.",
			"College wasn't an application so much as a formality -- the kind of formality that exists for institutions to maintain the appearance of a process everyone already knows the outcome of.",
			"By senior year, the question was never whether doors would open. It was only ever which ones, and how many at once.",
		},
	},
}

-- ============================================================
-- PUBLIC API
-- ============================================================

--[[
	GenerateForPlayer(player)

	Builds the 4-chapter timelapse from the player's already-rolled stats.
	Does NOT fire any event -- use GenerateAndSendToPlayer for that.

	Returns an ordered array of:
		{
			chapter = "Infancy" | "Childhood" | "MiddleSchool" | "HighSchool",
			displayName = string, -- e.g. "Middle School"
			statUsed = string,    -- parent stat name driving this chapter
			tierName = string,    -- from StatGenerator.GetTierName
			text = string,        -- the flavor text
		}
	Returns nil if the player has no generated stats yet.
]]
function TimelapseGenerator.GenerateForPlayer(player: Player)
	local stats = StatGenerator.GetStats(player)
	if not stats or not stats.parentStats then
		warn("[TimelapseGenerator] No generated stats for " .. player.Name .. " -- call SpawnWheel.RollForPlayer first.")
		return nil
	end

	local chapters = {}

	for _, chapterKey in CHAPTER_ORDER do
		local statName = CHAPTER_STAT_MAP[chapterKey]
		local value = stats.parentStats[statName]
		local tierName = StatGenerator.GetTierName(statName, value)

		local variants = FRAGMENT_BANK[chapterKey] and FRAGMENT_BANK[chapterKey][tierName]
		local text
		if variants and #variants > 0 then
			text = variants[math.random(1, #variants)]
		else
			warn(string.format("[TimelapseGenerator] No fragments for chapter=%s tier=%s (stat=%s value=%s)",
				chapterKey, tostring(tierName), statName, tostring(value)))
			text = ""
		end

		table.insert(chapters, {
			chapter = chapterKey,
			displayName = CHAPTER_DISPLAY_NAMES[chapterKey],
			statUsed = statName,
			tierName = tierName,
			text = text,
		})
	end

	return chapters
end

--[[
	GenerateAndSendToPlayer(player)

	Generates the timelapse (see above) and fires TimelapseEvent to the
	player with the chapter array, for TimelapseViewer to display.
	Call this once, right after SpawnWheel.RollForPlayer for that player.
]]
function TimelapseGenerator.GenerateAndSendToPlayer(player: Player)
	local chapters = TimelapseGenerator.GenerateForPlayer(player)
	if chapters and timelapseEvent then
		timelapseEvent:FireClient(player, chapters)
	end
	return chapters
end

return TimelapseGenerator
