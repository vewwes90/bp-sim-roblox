-- IntroCutsceneData
--
-- The intro cutscene as data. Played by CutsceneSequencer, which knows nothing
-- about any of this -- so rewriting dialogue means editing only this file.
--
-- SOURCE OF TRUTH FOR THE WORDS: the project owner's own draft, transcribed
-- verbatim. The ONLY line not written by the project owner is the one marked
-- [ADDED] in the announcer's speech, which was explicitly approved to resolve
-- the ten-contestants / one-egg inconsistency.
--
-- Beats flagged `placeholder = true` are beats the draft DESCRIBED but did not
-- WRITE (the backstory narration and the player's bar monologue). Their text
-- here is a bracketed stand-in with an estimated duration so total runtime can
-- be measured -- it is deliberately NOT invented prose. These render dimmed
-- amber in playback so they're obvious during a watch-through.
--
-- `section` tags exist so a shorter repeat-play version can be defined as a
-- subset (see CutsceneSequencer.FilterSections) rather than a second script.
-- Which sections a short version keeps is NOT decided yet.

local IntroCutsceneData = {}

-- Camera cue names are declared here but intentionally left unpositioned --
-- no greybox environments exist yet. CutsceneSequencer skips any cue with no
-- CFrame, so this data is playable now and gains camera work later without
-- any edit to the beat list.
IntroCutsceneData.CameraCues = {
    -- EXT_CASINO      = CFrame.new(...),
    -- CASINO_ENTRANCE = CFrame.new(...),
    -- SLOT_MACHINE    = CFrame.new(...),
    -- SLOT_REELS      = CFrame.new(...),
    -- BAR             = CFrame.new(...),
    -- GUIDE_APPROACH  = CFrame.new(...),
    -- BACKROOM        = CFrame.new(...),
    -- TRAPDOOR        = CFrame.new(...),
    -- BASEMENT_WIDE   = CFrame.new(...),
    -- RECEPTION_DESK  = CFrame.new(...),
    -- CROWD_WALK      = CFrame.new(...),
    -- BANNERS         = CFrame.new(...),
    -- TUBE_POV        = CFrame.new(...),
    -- ANNOUNCER       = CFrame.new(...),
    -- TUBES_WIDE      = CFrame.new(...),
}

IntroCutsceneData.Beats = {
    -- ===== Scene 1: alleyway exterior =====
    {id = "S1_EXTERIOR", section = "Arrival", camera = "EXT_CASINO", cameraCut = true, duration = 4.0},
    {id = "S1_ENTER", section = "Arrival", camera = "CASINO_ENTRANCE", duration = 3.0},

    -- ===== Scene 2: the slot machine =====
    {id = "S2_SEATED", section = "SlotMachine", camera = "SLOT_MACHINE", cameraCut = true, duration = 2.5},
    {id = "S2_INSERT_BILL", section = "SlotMachine", duration = 2.5},
    {
        id = "S2_BACKSTORY", section = "SlotMachine", speaker = "",
        text = "[BACKSTORY NARRATION -- NOT YET WRITTEN. Draft describes: pitiable and matter-of-fact; establishes tremendous debt, the sold kidney, the mortgaged home, everything gambled chasing the high life.]",
        placeholder = true, duration = 6.0,
    },
    {id = "S2_RISE", section = "SlotMachine", camera = "SLOT_REELS", duration = 2.0},
    {id = "S2_REELS", section = "SlotMachine", speaker = "", text = "Cherry... Cherry... Grape.", duration = 3.0},

    -- ===== Scene 3: the bar =====
    {id = "S3_TO_BAR", section = "Bar", camera = "BAR", duration = 2.5},
    {id = "S3_TAB", section = "Bar", speaker = "PLAYER", text = "Put it on my tab."},
    {id = "S3_REJECTED", section = "Bar", speaker = "BARTENDER", text = "You already owe too much on your tab."},
    {
        id = "S3_MONOLOGUE", section = "Bar", speaker = "PLAYER",
        text = "[MONOLOGUE -- NOT YET WRITTEN. Draft describes: the player lists their failures and how unlucky their life has been.]",
        placeholder = true, duration = 6.0,
    },
    {id = "S3_WISH", section = "Bar", speaker = "PLAYER", text = "I'd do anything to not have to live life how I am!", duration = 2.0},

    -- ===== Scene 4: the Guide's offer =====
    {id = "S4_APPROACH", section = "Offer", camera = "GUIDE_APPROACH", duration = 2.5},
    {id = "S4_G1", section = "Offer", speaker = "GUIDE", text = "Do you mean what you wish?"},
    {id = "S4_P1", section = "Offer", speaker = "PLAYER", text = "Yes. I'd do anything -- I don't have another kidney to sell."},
    {id = "S4_G2", section = "Offer", speaker = "GUIDE", text = "An organ is little to lose when you have as much as you do."},
    {id = "S4_P2", section = "Offer", speaker = "PLAYER", text = "What do you mean -- I'm dead broke, in debt, and ugly!"},
    {id = "S4_G3", section = "Offer", speaker = "GUIDE", text = "Yes. But I can tell your soul has value. You may have made the wrong choices, but given another chance, you could change that. Follow me if you want a chance to win it all back -- and more."},

    -- ===== Scene 5: the hidden entrance =====
    {id = "S5_BACKROOM", section = "Descent", camera = "BACKROOM", duration = 3.0},
    {id = "S5_MECHANISM", section = "Descent", camera = "TRAPDOOR", duration = 4.0},
    {id = "S5_HESITATE", section = "Descent", duration = 2.5},
    {id = "S6_DESCEND", section = "Descent", camera = "BASEMENT_WIDE", cameraCut = true, fadeOut = true, fadeIn = true, duration = 3.5},

    -- ===== Scene 7: reception =====
    {id = "S7_DESK", section = "Reception", camera = "RECEPTION_DESK", duration = 2.0},
    {id = "S7_R1", section = "Reception", speaker = "RECEPTIONIST", text = "First time here?"},
    {id = "S7_P1", section = "Reception", speaker = "PLAYER", text = "Yeah... but it looks oddly familiar, for some reason..."},
    {id = "S7_R2", section = "Reception", speaker = "RECEPTIONIST", text = "They all say that.", duration = 2.5},

    -- ===== Scene 8: through the crowd =====
    {id = "S8_CROWD", section = "Crowd", camera = "CROWD_WALK", duration = 3.0},
    {id = "S8_P1", section = "Crowd", speaker = "PLAYER", text = "So your promise to help me was actually just recruiting me to do crimes?"},
    {id = "S8_G1", section = "Crowd", speaker = "GUIDE", text = "No, no, no. I'm giving you what you wished for -- another chance at life. But first, I need you to do me a favor."},
    {id = "S8_P2", section = "Crowd", speaker = "PLAYER", text = "I gambled my life away -- I'm happy to gamble yours away too. So how can I help you?"},
    {id = "S8_G2", section = "Crowd", speaker = "GUIDE", camera = "BANNERS", text = "You see up there? I just need you to pick one of those little guys. Which one do you think has the most potential."},

    -- ===== Scene 9: selection =====
    -- The actual banner-selection UI does not exist yet. This beat is a
    -- placeholder hold so runtime can be measured; when the selection screen is
    -- built it replaces this beat rather than being appended to it.
    {
        id = "S9_SELECTION", section = "Selection",
        text = "[RACER SELECTION SCREEN -- NOT YET BUILT. Player picks 1 of 10 from the banners.]",
        placeholder = true, waitForInput = true,
    },
    {id = "S9_PROMPT", section = "Selection", speaker = "", text = "Pick with your gut instinct. It's random -- but gut still knows best.", duration = 3.0},
    {id = "S9_G3", section = "Selection", speaker = "GUIDE", text = "Alright, that's all I needed to know. Best of luck to you in your new life."},
    {id = "S9_KNOCKOUT", section = "Selection", fadeOut = true, duration = 2.0},

    -- ===== Scene 10: the tubes and the announcer =====
    {id = "S10_WAKE", section = "Announcement", camera = "TUBE_POV", cameraCut = true, fadeIn = true, duration = 3.5},
    {id = "S10_TUBES_WIDE", section = "Announcement", camera = "TUBES_WIDE", duration = 3.0},
    {id = "S10_A1", section = "Announcement", speaker = "ANNOUNCER", camera = "ANNOUNCER", text = "Ladies and gentlemen! It's time for the main event we've all been waiting for!"},
    {id = "S10_APPLAUSE", section = "Announcement", duration = 2.0},

    -- The speech is split across beats deliberately: as one block it is ~200
    -- words of unvoiced subtitle and drags badly. Split gives cut points for
    -- visual movement underneath and shows exactly where it sags on a watch-through.
    {id = "S10_A2", section = "Announcement", speaker = "ANNOUNCER", text = "As everyone here is aware, this casino has been very lucky, and very privileged, to work alongside the government to grant our finest customers an opportunity of a lifetime."},
    {id = "S10_A3", section = "Announcement", speaker = "ANNOUNCER", text = "Our casino has been delighted to serve countless customers into luxury lives with tremendous wealth. Handing our big winners their checks makes my soul glow with pride."},
    {id = "S10_A4", section = "Announcement", speaker = "ANNOUNCER", text = "And while you in the audience may have won big -- so many of my guests leave with nothing. To make up for the sadness I've unfortunately brought to these wonderful people, we run this event once a year: to surprise those less fortunate with something potentially more valuable than anything even the richest members of this audience possess."},
    {id = "S10_A5", section = "Announcement", speaker = "ANNOUNCER", text = "Earlier today, ten lucky participants were granted the gamble of a lifetime! They chose from a selection of ten possible futures, and will shortly be collecting their winnings!"},

    -- [ADDED] The one line not from the original draft. Approved fix for the
    -- ten-contestants / one-egg inconsistency: everyone is reborn, placement
    -- only decides into what -- which is exactly what SpawnWheel already does.
    {id = "S10_A6_FIX", section = "Announcement", speaker = "ANNOUNCER", text = "Every one of them walks away reborn. Only the order they arrive in decides into what.", duration = 3.0},

    {id = "S10_A7", section = "Announcement", speaker = "ANNOUNCER", camera = "TUBES_WIDE", text = "Let their wishes be granted, and their new lives begin...", duration = 2.5},

    -- ===== Scene 10b: submersion =====
    {id = "S10_LIQUID", section = "Submersion", camera = "TUBE_POV", duration = 5.0},
    {id = "S10_BLACKOUT", section = "Submersion", fadeOut = true, duration = 2.5},
}

return IntroCutsceneData
