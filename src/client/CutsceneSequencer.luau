-- CutsceneSequencer (client-side ModuleScript)
--
-- Generic, content-agnostic cutscene playback engine. It knows NOTHING about
-- this game's story -- it takes a list of beats plus a camera-cue table and
-- plays them in order. All actual dialogue/content lives in a separate data
-- module, so rewriting dialogue never means touching this file.
--
-- Built to support, without needing the design decision made yet:
--   * skip-one-beat and skip-entire-cutscene (a repeat/short version of any
--     cutscene is just a filtered subset of beat IDs, not a second script)
--   * section tags, so Play() can be handed only the beats belonging to a
--     named section
--   * a completion callback, so whatever comes next (the race) is wired in by
--     the caller rather than hardcoded here
--
-- Uses the same token/generation-counter guard as TimelapseViewer and
-- WheelSpinViewer: a second Play() immediately supersedes any in-progress
-- playback instead of running two coroutines over the same GUI.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CutsceneSequencer = {}

-- ===== Presentation tuning =====
-- GREYBOX PLACEHOLDERS: these drive how the cutscene *feels* and have not been
-- judged by a human yet. Expect to change all of them after a watch-through.
local TEXT_REVEAL_CPS = 45      -- characters revealed per second
local HOLD_AFTER_TEXT = 1.4     -- seconds a finished line stays up before auto-advancing
local SILENT_BEAT_DEFAULT = 3.0 -- default hold for a beat with no dialogue
local FADE_TIME = 0.6
local CAMERA_TWEEN_TIME = 1.0

-- Sits above WheelSpinGui (20) -- a cutscene covers everything else.
local DISPLAY_ORDER = 30

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local currentToken = 0
local playing = false
local advanceRequested = false
local skipAllRequested = false

-- Set per-playback from opts. Both default FALSE: a first playthrough is
-- deliberately unskippable and self-paced -- you don't get to fast-forward your
-- own conception. A later reroll/replay opts back in by passing them true.
local allowAdvance = false
local allowSkip = false

local gui, letterboxTop, letterboxBottom, speakerLabel, textLabel, fadeFrame, skipHint
local voiceSound
local inputConnection

-- ===== GUI construction (built once, on first play) =====
local function buildGui()
    if gui then return end

    gui = Instance.new("ScreenGui")
    gui.Name = "CutsceneGui"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = DISPLAY_ORDER
    gui.Enabled = false
    gui.Parent = player:WaitForChild("PlayerGui")

    -- Cinematic letterbox bars
    letterboxTop = Instance.new("Frame")
    letterboxTop.Name = "LetterboxTop"
    letterboxTop.Size = UDim2.new(1, 0, 0, 90)
    letterboxTop.Position = UDim2.new(0, 0, 0, 0)
    letterboxTop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    letterboxTop.BorderSizePixel = 0
    letterboxTop.ZIndex = 2
    letterboxTop.Parent = gui

    letterboxBottom = Instance.new("Frame")
    letterboxBottom.Name = "LetterboxBottom"
    letterboxBottom.Size = UDim2.new(1, 0, 0, 90)
    letterboxBottom.Position = UDim2.new(0, 0, 1, -90)
    letterboxBottom.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    letterboxBottom.BorderSizePixel = 0
    letterboxBottom.ZIndex = 2
    letterboxBottom.Parent = gui

    -- Speaker name, above the line
    speakerLabel = Instance.new("TextLabel")
    speakerLabel.Name = "SpeakerLabel"
    speakerLabel.Size = UDim2.new(0.7, 0, 0, 24)
    speakerLabel.Position = UDim2.new(0.15, 0, 1, -172)
    speakerLabel.BackgroundTransparency = 1
    speakerLabel.Font = Enum.Font.RobotoMono
    speakerLabel.TextSize = 16
    speakerLabel.TextColor3 = Color3.fromRGB(150, 150, 155)
    speakerLabel.TextXAlignment = Enum.TextXAlignment.Left
    speakerLabel.Text = ""
    speakerLabel.ZIndex = 3
    speakerLabel.Parent = gui

    -- The dialogue line itself
    textLabel = Instance.new("TextLabel")
    textLabel.Name = "TextLabel"
    textLabel.Size = UDim2.new(0.7, 0, 0, 110)
    textLabel.Position = UDim2.new(0.15, 0, 1, -146)
    textLabel.BackgroundTransparency = 1
    textLabel.Font = Enum.Font.RobotoMono
    textLabel.TextSize = 20
    textLabel.TextColor3 = Color3.fromRGB(225, 225, 225)
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.TextYAlignment = Enum.TextYAlignment.Top
    textLabel.TextWrapped = true
    textLabel.Text = ""
    textLabel.ZIndex = 3
    textLabel.Parent = gui

    -- Skip affordance
    skipHint = Instance.new("TextLabel")
    skipHint.Name = "SkipHint"
    skipHint.Size = UDim2.new(0, 300, 0, 20)
    skipHint.Position = UDim2.new(1, -320, 1, -34)
    skipHint.BackgroundTransparency = 1
    skipHint.Font = Enum.Font.RobotoMono
    skipHint.TextSize = 13
    skipHint.TextColor3 = Color3.fromRGB(110, 110, 115)
    skipHint.TextXAlignment = Enum.TextXAlignment.Right
    skipHint.Text = "[click] continue    [esc] skip"
    skipHint.ZIndex = 3
    skipHint.Parent = gui

    -- Reused for every voiced line. One instance rather than one per beat so
    -- a new line always cuts off the previous one cleanly.
    voiceSound = Instance.new("Sound")
    voiceSound.Name = "VoiceSound"
    voiceSound.Volume = 1
    voiceSound.Parent = gui

    -- Full-screen fade overlay, sits on top of everything in this GUI
    fadeFrame = Instance.new("Frame")
    fadeFrame.Name = "FadeFrame"
    fadeFrame.Size = UDim2.new(1, 0, 1, 0)
    fadeFrame.Position = UDim2.new(0, 0, 0, 0)
    fadeFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    fadeFrame.BackgroundTransparency = 1
    fadeFrame.BorderSizePixel = 0
    fadeFrame.ZIndex = 10
    fadeFrame.Parent = gui
end

-- ===== Input =====
local function connectInput()
    if inputConnection then return end
    inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.KeyCode == Enum.KeyCode.Space
            or input.KeyCode == Enum.KeyCode.Return then
            if allowAdvance then
                advanceRequested = true
            end
        elseif input.KeyCode == Enum.KeyCode.Escape then
            if allowSkip then
                skipAllRequested = true
                advanceRequested = true
            end
        end
    end)
end

local function disconnectInput()
    if inputConnection then
        inputConnection:Disconnect()
        inputConnection = nil
    end
end

-- ===== Helpers =====
local function isCurrent(token)
    return token == currentToken
end

local function fadeTo(transparency, token)
    if not isCurrent(token) then return end
    local tween = TweenService:Create(
        fadeFrame,
        TweenInfo.new(FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
        {BackgroundTransparency = transparency}
    )
    tween:Play()
    local elapsed = 0
    while elapsed < FADE_TIME do
        if not isCurrent(token) then return end
        elapsed = elapsed + task.wait()
    end
end

-- Waits `duration` seconds, but bails early if the player advances/skips or a
-- newer playback supersedes this one. Returns false if superseded.
local function waitOrAdvance(duration, token)
    local elapsed = 0
    while elapsed < duration do
        if not isCurrent(token) then return false end
        if advanceRequested then
            advanceRequested = false
            return true
        end
        elapsed = elapsed + task.wait()
    end
    return true
end

-- Reveals text character-by-character. A click mid-reveal completes the line
-- instantly rather than skipping it (standard dialogue convention).
local function revealText(text, token)
    local total = #text
    local revealed = 0
    textLabel.Text = ""

    while revealed < total do
        if not isCurrent(token) then return false end
        if advanceRequested then
            advanceRequested = false
            textLabel.Text = text
            return true
        end
        local dt = task.wait()
        revealed = math.min(total, revealed + TEXT_REVEAL_CPS * dt)
        textLabel.Text = string.sub(text, 1, math.floor(revealed))
    end
    textLabel.Text = text
    return true
end

-- ===== Voice lines =====
-- Returns the clip's length in seconds, or nil if there's no clip / it never
-- loaded. A voiced beat takes its timing from the audio rather than from the
-- text-length estimate, so line pacing matches the performance.
local function playVoice(audioId, token)
    if not audioId then return nil end

    voiceSound:Stop()
    voiceSound.SoundId = (type(audioId) == "number")
        and ("rbxassetid://" .. audioId)
        or tostring(audioId)

    -- TimeLength stays 0 until the asset loads
    local waited = 0
    while voiceSound.TimeLength <= 0 and waited < 3 do
        if not isCurrent(token) then return nil end
        waited = waited + task.wait()
    end

    if voiceSound.TimeLength <= 0 then
        warn("[CutsceneSequencer] Voice clip failed to load: " .. tostring(audioId))
        return nil
    end

    voiceSound:Play()
    return voiceSound.TimeLength
end

-- ===== Camera cues =====
-- The sequencer never computes geometry itself. A beat names a cue; the caller
-- supplies a cue table mapping that name to a CFrame (or nil). Unset cues are
-- simply skipped, which is what lets beat data be written before any greybox
-- environment exists.
local function applyCameraCue(cueName, cueTable, token, instant)
    if not cueName or not cueTable then return end
    local target = cueTable[cueName]
    if not target then return end -- cue declared but not positioned yet

    camera.CameraType = Enum.CameraType.Scriptable
    if instant then
        camera.CFrame = target
    else
        TweenService:Create(
            camera,
            TweenInfo.new(CAMERA_TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
            {CFrame = target}
        ):Play()
    end
end

-- ===== Public API =====

function CutsceneSequencer.IsPlaying()
    return playing
end

-- Stops any in-progress playback without running the completion callback.
function CutsceneSequencer.Stop()
    currentToken = currentToken + 1
    playing = false
    skipAllRequested = false
    advanceRequested = false
    disconnectInput()
    if voiceSound then voiceSound:Stop() end
    if gui then
        gui.Enabled = false
        if fadeFrame then fadeFrame.BackgroundTransparency = 1 end
    end
end

-- beats: array of beat tables. Recognised fields:
--   id          string   -- stable identifier, used for section filtering/logging
--   section     string   -- optional grouping tag
--   speaker     string?  -- name shown above the line; nil for unattributed
--   text        string?  -- the line; nil for a silent/visual-only beat
--   duration    number?  -- explicit hold; omit to auto-pace from text length
--   camera      string?  -- camera cue name, resolved via cueTable
--   cameraCut   boolean? -- true = hard cut, false/nil = tween
--   fadeOut     boolean? -- fade to black before this beat's content
--   fadeIn      boolean? -- fade back in after this beat's content
--   placeholder boolean? -- content not written yet; rendered dimmed
--   waitForInput boolean? -- hold indefinitely until the player advances
--   audioId     number|string? -- voice clip; when present the beat's hold is
--                                taken from the clip length instead of text length
--
-- opts:
--   cameraCues   table?    -- name -> CFrame
--   onComplete   function? -- called after playback finishes normally
--   onBeat       function(beat, index)?
--   allowAdvance boolean?  -- default false; player can advance/complete lines
--   allowSkip    boolean?  -- default false; player can escape out entirely
function CutsceneSequencer.Play(beats, opts)
    opts = opts or {}
    buildGui()

    currentToken = currentToken + 1
    local token = currentToken
    playing = true
    skipAllRequested = false
    advanceRequested = false

    allowAdvance = opts.allowAdvance == true
    allowSkip = opts.allowSkip == true
    skipHint.Visible = allowAdvance or allowSkip
    if allowSkip then
        skipHint.Text = allowAdvance and "[click] continue    [esc] skip" or "[esc] skip"
    elseif allowAdvance then
        skipHint.Text = "[click] continue"
    end

    connectInput()
    gui.Enabled = true
    fadeFrame.BackgroundTransparency = 1
    speakerLabel.Text = ""
    textLabel.Text = ""

    task.spawn(function()
        local startClock = os.clock()

        for index, beat in ipairs(beats) do
            if not isCurrent(token) then return end
            if skipAllRequested then break end

            if opts.onBeat then
                opts.onBeat(beat, index)
            end

            if beat.fadeOut then
                fadeTo(0, token)
                if not isCurrent(token) then return end
            end

            applyCameraCue(beat.camera, opts.cameraCues, token, beat.cameraCut)

            if beat.fadeIn then
                fadeTo(1, token)
                if not isCurrent(token) then return end
            end

            -- Speaker / text presentation
            speakerLabel.Text = beat.speaker or ""
            textLabel.TextColor3 = beat.placeholder
                and Color3.fromRGB(140, 120, 90)  -- dimmed amber = not yet written
                or Color3.fromRGB(225, 225, 225)

            local voiceLength = playVoice(beat.audioId, token)
            if not isCurrent(token) then return end

            if beat.text then
                if not revealText(beat.text, token) then return end
                if not isCurrent(token) then return end

                if beat.waitForInput then
                    while not advanceRequested do
                        if not isCurrent(token) then return end
                        task.wait()
                    end
                    advanceRequested = false
                else
                    -- Voiced lines wait out the remaining audio; unvoiced lines
                    -- fall back to the text-length estimate.
                    local hold
                    if voiceLength then
                        hold = math.max(0, voiceLength - (#beat.text / TEXT_REVEAL_CPS)) + HOLD_AFTER_TEXT
                    else
                        hold = beat.duration or HOLD_AFTER_TEXT
                    end
                    if not waitOrAdvance(hold, token) then return end
                end
            else
                textLabel.Text = ""
                local hold = voiceLength or beat.duration or SILENT_BEAT_DEFAULT
                if not waitOrAdvance(hold, token) then return end
            end
        end

        if not isCurrent(token) then return end

        local totalTime = os.clock() - startClock
        print(string.format("[CutsceneSequencer] Playback finished in %.1fs (%d beats)", totalTime, #beats))

        -- Fade out and hand control back to the caller
        fadeTo(0, token)
        if not isCurrent(token) then return end

        playing = false
        disconnectInput()
        gui.Enabled = false
        fadeFrame.BackgroundTransparency = 1

        if opts.onComplete then
            opts.onComplete()
        end
    end)

    return token
end

-- Convenience: returns only the beats whose `section` is in the allowed set.
-- This is how a short/repeat version of a cutscene gets defined -- as a subset
-- of the same data, never a duplicate script.
function CutsceneSequencer.FilterSections(beats, allowedSections)
    local allowed = {}
    for _, name in ipairs(allowedSections) do
        allowed[name] = true
    end

    local filtered = {}
    for _, beat in ipairs(beats) do
        if beat.section and allowed[beat.section] then
            table.insert(filtered, beat)
        end
    end
    return filtered
end

return CutsceneSequencer
