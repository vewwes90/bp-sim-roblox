-- IntroCutsceneClient (LocalScript)
--
-- Wires the intro cutscene data into the generic CutsceneSequencer and decides
-- what happens when it finishes. Deliberately thin: all content lives in
-- IntroCutsceneData, all playback logic lives in CutsceneSequencer.
--
-- Triggered by the `PlayIntroCutsceneEvent` BindableEvent in ReplicatedStorage.
-- Right now that's fired manually for testing; later it's fired by the main
-- menu's "Resume living in reality" button, which doesn't exist yet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local CutsceneSequencer = require(script.Parent:WaitForChild("CutsceneSequencer"))
local IntroCutsceneData = require(
    ReplicatedStorage:WaitForChild("Cutscenes"):WaitForChild("IntroCutsceneData")
)

local triggerEvent = ReplicatedStorage:WaitForChild("PlayIntroCutsceneEvent")

-- opts (all optional):
--   sections     array of section names, for a shortened replay. Omit to play
--                everything. Which sections a short version keeps is NOT
--                decided yet -- this makes it a one-line change when it is.
--   autoAdvance  true = never block on input. Used for unattended pacing
--                review, so the whole cutscene can be timed end to end without
--                a human sitting through it.
--   allowSkip    true = player can escape out. Defaults FALSE: confirmed
--                2026-08-14 that a first playthrough is unskippable, and skip
--                only becomes available if/when a reroll feature exists.
--   allowAdvance true = player can click to advance/complete lines. Also
--                defaults false, so the first run is fully self-paced.
local function playIntro(opts)
    opts = opts or {}

    local beats = IntroCutsceneData.Beats
    if opts.sections then
        beats = CutsceneSequencer.FilterSections(beats, opts.sections)
        print(string.format("[IntroCutscene] Playing %d beats from %d sections", #beats, #opts.sections))
    else
        print(string.format("[IntroCutscene] Playing full cutscene (%d beats)", #beats))
    end

    if opts.autoAdvance then
        -- Shallow-copy each beat so the source data is never mutated
        local copy = {}
        for i, beat in ipairs(beats) do
            local b = {}
            for k, v in pairs(beat) do b[k] = v end
            b.waitForInput = nil
            copy[i] = b
        end
        beats = copy
        print("[IntroCutscene] autoAdvance: input-blocking beats will not hold.")
    end

    local startClock = os.clock()
    local lastBeatClock = startClock

    CutsceneSequencer.Play(beats, {
        cameraCues = IntroCutsceneData.CameraCues,
        allowSkip = opts.allowSkip == true,
        allowAdvance = opts.allowAdvance == true,

        -- This is the actual instrument for the pacing pass. Each line shows
        -- when the beat started and how long the PREVIOUS beat held, so a
        -- watch-through log reads directly as "this is where it drags".
        onBeat = function(beat, index)
            local now = os.clock()
            local held = now - lastBeatClock
            lastBeatClock = now

            local elapsed = now - startClock
            print(string.format("[IntroCutscene]  %5.1fs (+%4.1fs)  %02d  %-16s %s",
                elapsed,
                held,
                index,
                beat.id or "?",
                beat.placeholder and "(PLACEHOLDER)" or ""
            ))
        end,

        onComplete = function()
            -- Hand the camera back. The real handoff target is the conception
            -- race, but the race currently starts from its own selection flow,
            -- so this only restores control for now rather than assuming a
            -- wiring that hasn't been designed yet.
            camera.CameraType = Enum.CameraType.Custom
            print("[IntroCutscene] Complete. Camera released.")
        end,
    })
end

triggerEvent.Event:Connect(function(opts)
    playIntro(opts)
end)

print("IntroCutsceneClient loaded. Fire ReplicatedStorage.PlayIntroCutsceneEvent to play.")
