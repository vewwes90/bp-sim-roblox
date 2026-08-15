-- RacerSelection LocalScript
-- Lets the player click a racer to select it before the race starts.
-- Listens for the race result from the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = Workspace.CurrentCamera

local selectEvent = ReplicatedStorage:WaitForChild("RacerSelectEvent", 10)
local resultEvent = ReplicatedStorage:WaitForChild("RaceResultEvent", 10)
local countdownEvent = ReplicatedStorage:WaitForChild("CountdownEvent", 10)
local raceProgressEvent = ReplicatedStorage:WaitForChild("RaceProgressEvent", 10)
local raceAssignedEvent = ReplicatedStorage:WaitForChild("RaceAssignedEvent", 10)
local localSelectedEvent = ReplicatedStorage:WaitForChild("LocalRacerSelectedEvent", 10)
local heartbeatSound = ReplicatedStorage:WaitForChild("RaceHeartbeat", 10)

-- Races are per-player instanced now (2026-08-14): the track no longer lives at
-- a fixed Workspace path, it's a clone the server assigns to this player and
-- destroys afterwards. Everything that used to resolve `Workspace.ConceptionRace`
-- at load now binds to whatever RaceAssignedEvent hands over.
local raceModel = nil
local racersFolder = nil

local selectedRacer = nil
local selectionHighlight = nil

local function getRacerPart(index)
    if not racersFolder or not index then return nil end
    return racersFolder:FindFirstChild("Racer" .. index)
end

raceAssignedEvent.OnClientEvent:Connect(function(model)
    raceModel = model
    racersFolder = model and model:FindFirstChild("Racers")
    print("[Race] Assigned track: " .. (model and model.Name or "nil"))
end)

-- Create a highlight to visually mark the selected racer
local function highlightRacer(racer)
    if selectionHighlight then
        selectionHighlight:Destroy()
    end
    selectionHighlight = Instance.new("SelectionBox")
    selectionHighlight.Adornee = racer
    selectionHighlight.Color3 = Color3.fromRGB(255, 255, 255)
    selectionHighlight.LineThickness = 0.15
    selectionHighlight.SurfaceTransparency = 0.5
    selectionHighlight.Parent = racer
end

-- ===== First-person race camera (mounted at the nose of the player's own racer) =====
-- Locked forward, no player look-around -- deliberate: the player has no more
-- control over what's coming than they had over the roll itself.
local FINISH_Z = 100 -- matches the track's finish line position
local EYE_HEIGHT_OFFSET = 0.35 -- above the racer's center, roughly rider eye-level
local NOSE_FORWARD_OFFSET = 2.3 -- just ahead of the racer's physical nose (half-length is 2 studs)
local LOOK_AHEAD_DISTANCE = 12
local LOOK_DOWN_DROP = 0.5 -- slight downward pitch so the track surface reads
local BOB_AMPLITUDE = 0.06
local BOB_FREQUENCY = 6
local SMOOTH_RATE = 10 -- higher = camera tracks the racer's real (steppy) position more tightly
local BASE_FOV = 80
local FOV_BOOST = 12 -- extra FOV at full reveal, for a "world rushing in" feel
local EASE_IN_TIME = 0.4
local DEFAULT_FOV = 70

local cameraConnection = nil
local cameraActive = false
local latestLiveRanking = nil -- kept in sync by RaceProgressEvent below, reused here for a leader-progress read

local function stopFPVCamera()
    cameraActive = false
    if cameraConnection then
        cameraConnection:Disconnect()
        cameraConnection = nil
    end
end

local function computeFPVCFrame(racerPart, t)
    local pos = racerPart.Position
    local bob = math.sin(t * BOB_FREQUENCY) * BOB_AMPLITUDE
    local eyePos = Vector3.new(pos.X, pos.Y + EYE_HEIGHT_OFFSET + bob, pos.Z + NOSE_FORWARD_OFFSET)
    local lookAt = eyePos + Vector3.new(0, -LOOK_DOWN_DROP, LOOK_AHEAD_DISTANCE)
    return CFrame.lookAt(eyePos, lookAt)
end

local function startFPVCamera()
    stopFPVCamera()
    if not selectedRacer then return end -- spectators who never picked a racer keep their own camera
    local racerPart = getRacerPart(selectedRacer)
    if not racerPart then return end

    cameraActive = true
    camera.CameraType = Enum.CameraType.Scriptable

    -- Ease in from wherever the camera currently is instead of snapping,
    -- so the cut into first-person isn't jarring.
    local targetCFrame = computeFPVCFrame(racerPart, os.clock())
    TweenService:Create(camera, TweenInfo.new(EASE_IN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {CFrame = targetCFrame, FieldOfView = BASE_FOV}):Play()

    cameraConnection = RunService.RenderStepped:Connect(function(dt)
        if not cameraActive then return end
        local racer = getRacerPart(selectedRacer)
        if not racer then return end

        local target = computeFPVCFrame(racer, os.clock())
        local alpha = 1 - math.exp(-SMOOTH_RATE * dt)
        camera.CFrame = camera.CFrame:Lerp(target, alpha)

        -- Widen FOV as the reveal window opens, using the leader's progress
        -- from the last live-ranking update (the same signal driving the HUD).
        local leaderProgress = 0
        if latestLiveRanking and latestLiveRanking[1] then
            leaderProgress = math.clamp(latestLiveRanking[1].z / FINISH_Z, 0, 1)
        end
        local revealFactor = math.clamp((leaderProgress - 0.55) / 0.45, 0, 1)
        camera.FieldOfView = BASE_FOV + revealFactor * FOV_BOOST
    end)
end

-- ===== Race tension vignette (built from primitive UI, no image assets) =====
local vignetteGui = Instance.new("ScreenGui")
vignetteGui.Name = "RaceVignetteGui"
vignetteGui.IgnoreGuiInset = true
vignetteGui.ResetOnSpawn = false
vignetteGui.DisplayOrder = 5
vignetteGui.Enabled = false
vignetteGui.Parent = player:WaitForChild("PlayerGui")

local function addVignetteEdge(size, position, rotation)
    local frame = Instance.new("Frame")
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BorderSizePixel = 0
    frame.Size = size
    frame.Position = position
    frame.Parent = vignetteGui

    local gradient = Instance.new("UIGradient")
    gradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    gradient.Rotation = rotation
    gradient.Parent = frame
end

-- Thicker than the original top-down version -- these now double as a
-- viewport/pod rim for the first-person view, not just a tension vignette.
addVignetteEdge(UDim2.new(1, 0, 0, 190), UDim2.new(0, 0, 0, 0), 90)
addVignetteEdge(UDim2.new(1, 0, 0, 190), UDim2.new(0, 0, 1, -190), 270)
addVignetteEdge(UDim2.new(0, 210, 1, 0), UDim2.new(0, 0, 0, 0), 0)
addVignetteEdge(UDim2.new(0, 210, 1, 0), UDim2.new(1, -210, 0, 0), 180)

-- ===== Live position-ranking HUD =====
local rankingGui = Instance.new("ScreenGui")
rankingGui.Name = "RaceRankingGui"
rankingGui.IgnoreGuiInset = true
rankingGui.ResetOnSpawn = false
rankingGui.DisplayOrder = 6
rankingGui.Enabled = false
rankingGui.Parent = player:WaitForChild("PlayerGui")

local rankingFrame = Instance.new("Frame")
rankingFrame.Size = UDim2.new(0, 170, 0, 280)
rankingFrame.Position = UDim2.new(1, -190, 0.5, -140)
rankingFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
rankingFrame.BackgroundTransparency = 0.35
rankingFrame.BorderSizePixel = 0
rankingFrame.Parent = rankingGui

local rankingLayout = Instance.new("UIListLayout")
rankingLayout.SortOrder = Enum.SortOrder.LayoutOrder
rankingLayout.Padding = UDim.new(0, 2)
rankingLayout.Parent = rankingFrame

local rankingLabels = {}
for rank = 1, 10 do
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 26)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.RobotoMono
    label.TextSize = 16
    label.TextColor3 = Color3.fromRGB(190, 190, 190)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.LayoutOrder = rank
    label.Text = ""
    label.Parent = rankingFrame
    rankingLabels[rank] = label
end

if raceProgressEvent then
    raceProgressEvent.OnClientEvent:Connect(function(liveRanking)
        latestLiveRanking = liveRanking
        for rank, entry in ipairs(liveRanking) do
            local label = rankingLabels[rank]
            if label then
                local racer = getRacerPart(entry.index)
                local colorName = racer and racer:GetAttribute("RacerColor") or "?"
                local isMine = entry.index == selectedRacer
                label.Text = string.format("%d. #%d %s%s", rank, entry.index, colorName, isMine and " <-- YOU" or "")
                label.TextColor3 = isMine and Color3.fromRGB(255, 210, 90) or Color3.fromRGB(190, 190, 190)
            end
        end
    end)
end

-- ===== Atmosphere audio =====
local function playHeartbeat()
    if heartbeatSound then
        heartbeatSound.Looped = true
        heartbeatSound.Volume = 0.5
        heartbeatSound:Play()
    end
end

local function stopHeartbeat()
    if heartbeatSound then
        heartbeatSound:Stop()
    end
end

local function beginRaceTension()
    startFPVCamera()
    vignetteGui.Enabled = true
    rankingGui.Enabled = true
    playHeartbeat()
end

-- ===== Selection =====
-- Selection now comes from the lineup screen rather than clicking a racer in
-- the world: with per-player instanced races there IS no track to click until
-- after you've chosen. This is the single place selection state is owned, so
-- the UI only has to announce a pick.
local function selectRacer(racerIndex)
    if type(racerIndex) ~= "number" then return end
    if selectedRacer == racerIndex then return end

    selectedRacer = racerIndex
    selectEvent:FireServer(racerIndex)
    print("[Race] Selected Racer #" .. racerIndex .. ". Waiting for the race to start...")
end

localSelectedEvent.Event:Connect(selectRacer)

-- Kept for the legacy in-world click path. Harmless once the track is gone --
-- racersFolder is nil until a race is assigned, so this simply never fires
-- before selection. Remove once the lineup screen is the only entry point.
mouse.Button1Down:Connect(function()
    if not racersFolder then return end
    local target = mouse.Target
    if not target then return end
    if not target:IsA("BasePart") then return end
    if target.Parent ~= racersFolder then return end
    if not string.match(target.Name, "^Racer%d+$") then return end

    local racerIndex = target:GetAttribute("RacerIndex")
    if not racerIndex then return end
    if selectedRacer == racerIndex then return end

    highlightRacer(target)
    selectRacer(racerIndex)
end)

-- Listen for race result from the server
resultEvent.OnClientEvent:Connect(function(placement, totalRacers, racerIndex, racerColor)
    local suffix = "th"
    if placement == 1 then suffix = "st"
    elseif placement == 2 then suffix = "nd"
    elseif placement == 3 then suffix = "rd" end
    
    print("========================================")
    print("RACE FINISHED!")
    print("Your racer (Racer #" .. racerIndex .. " - " .. racerColor .. ") finished in " .. placement .. suffix .. " place out of " .. totalRacers .. "!")
    print("========================================")

    -- Cinematic finish cut: stop the tracking loop and tween to a low,
    -- dramatic angle on the player's own racer before handing camera
    -- control back for whatever comes next (the wheel, the timelapse).
    stopFPVCamera()
    local myRacer = getRacerPart(racerIndex)
    if myRacer then
        local pos = myRacer.Position
        local finishCFrame = CFrame.lookAt(pos + Vector3.new(6, 5, -10), pos + Vector3.new(0, 1, 3))
        local tween = TweenService:Create(camera, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = finishCFrame})
        tween:Play()
    end

    task.delay(2.6, function()
        camera.CameraType = Enum.CameraType.Custom
        camera.FieldOfView = DEFAULT_FOV
        vignetteGui.Enabled = false
        rankingGui.Enabled = false
        stopHeartbeat()
    end)
end)

-- ===== Countdown GUI =====
local countdownGui = Instance.new("ScreenGui")
countdownGui.Name = "CountdownGui"
countdownGui.IgnoreGuiInset = true
countdownGui.ResetOnSpawn = false
countdownGui.Parent = player:WaitForChild("PlayerGui")

local countdownLabel = Instance.new("TextLabel")
countdownLabel.Size = UDim2.new(0, 400, 0, 200)
countdownLabel.Position = UDim2.new(0.5, -200, 0.5, -100)
countdownLabel.BackgroundTransparency = 1
countdownLabel.Font = Enum.Font.FredokaOne
countdownLabel.TextSize = 120
countdownLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
countdownLabel.TextStrokeTransparency = 0
countdownLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
countdownLabel.TextTransparency = 1
countdownLabel.Visible = false
countdownLabel.Parent = countdownGui

local function showCountdownText(text, color)
    countdownLabel.Text = text
    countdownLabel.TextColor3 = color
    countdownLabel.Visible = true
    countdownLabel.TextTransparency = 0
    
    -- Quick pop-in scale animation
    countdownLabel.Size = UDim2.new(0, 300, 0, 150)
    local tweenService = game:GetService("TweenService")
    local tween = tweenService:Create(countdownLabel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 400, 0, 200)
    })
    tween:Play()
end

local function hideCountdown()
    countdownLabel.Visible = false
end

-- Listen for countdown events from the server
countdownEvent.OnClientEvent:Connect(function(seconds)
    if seconds == 0 then
        -- Show GO!
        showCountdownText("GO!", Color3.fromRGB(0, 255, 0))
        task.delay(1.5, hideCountdown)
    else
        -- Countdown is starting: bring up the tactical camera, vignette,
        -- ranking HUD, and tension audio ahead of the race itself.
        beginRaceTension()

        -- Show the countdown number, then tick down locally
        local current = seconds
        showCountdownText(tostring(current), Color3.fromRGB(255, 255, 0))
        
        while current > 1 do
            task.wait(1)
            current = current - 1
            showCountdownText(tostring(current), Color3.fromRGB(255, 170, 0))
        end
        
        -- Wait for the final second, then the server will fire GO!
        task.wait(1)
        hideCountdown()
    end
end)

print("Racer selection script loaded. Click a racer to select it!")