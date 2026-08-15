-- TimelapseViewer LocalScript
-- Displays the procedurally generated birth-to-high-school narrative,
-- chapter by chapter, after the server sends it via TimelapseEvent.
-- Deliberately plain/dark presentation (no playful styling) to match the
-- project's bleak, deterministic tone.
--
-- NOTE: fade timing, wait durations, and general "feel" here are first-pass
-- guesses and have NOT been playtested live -- check these in Studio.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local timelapseEvent = ReplicatedStorage:WaitForChild("TimelapseEvent", 10)

if not timelapseEvent then
    warn("TimelapseViewer: TimelapseEvent not found in ReplicatedStorage")
    return
end

-- ===== Build the GUI (created once, reused for every chapter) =====
local gui = Instance.new("ScreenGui")
gui.Name = "TimelapseGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.new(1, 0, 1, 0)
background.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
background.BackgroundTransparency = 0
background.BorderSizePixel = 0
background.Parent = gui

local chapterLabel = Instance.new("TextLabel")
chapterLabel.Name = "ChapterLabel"
chapterLabel.Size = UDim2.new(0.8, 0, 0, 50)
chapterLabel.Position = UDim2.new(0.1, 0, 0.18, 0)
chapterLabel.BackgroundTransparency = 1
chapterLabel.Font = Enum.Font.RobotoMono
chapterLabel.TextSize = 28
chapterLabel.TextColor3 = Color3.fromRGB(150, 150, 155)
chapterLabel.TextXAlignment = Enum.TextXAlignment.Left
chapterLabel.Text = ""
chapterLabel.Parent = background

local bodyLabel = Instance.new("TextLabel")
bodyLabel.Name = "BodyLabel"
bodyLabel.Size = UDim2.new(0.8, 0, 0.4, 0)
bodyLabel.Position = UDim2.new(0.1, 0, 0.3, 0)
bodyLabel.BackgroundTransparency = 1
bodyLabel.Font = Enum.Font.RobotoMono
bodyLabel.TextSize = 22
bodyLabel.TextColor3 = Color3.fromRGB(210, 210, 215)
bodyLabel.TextWrapped = true
bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
bodyLabel.Text = ""
bodyLabel.TextTransparency = 1
bodyLabel.Parent = background

local continueButton = Instance.new("TextButton")
continueButton.Name = "ContinueButton"
continueButton.Size = UDim2.new(0, 220, 0, 50)
continueButton.Position = UDim2.new(0.1, 0, 0.85, 0)
continueButton.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
continueButton.BorderSizePixel = 1
continueButton.BorderColor3 = Color3.fromRGB(90, 90, 95)
continueButton.Font = Enum.Font.RobotoMono
continueButton.TextSize = 18
continueButton.TextColor3 = Color3.fromRGB(200, 200, 205)
continueButton.Text = "Continue"
continueButton.AutoButtonColor = true
continueButton.Visible = false
continueButton.Parent = background

-- ===== Playback =====
-- `currentToken` guards against a second TimelapseEvent arriving while an
-- earlier playback is still in progress (e.g. during repeated testing, or
-- any future case where the server fires this more than once). Each
-- playTimelapse call captures the token it was started with and checks it
-- before every step; if a newer call has started, the older one bails out
-- immediately instead of continuing to fight over the shared GUI.
local currentToken = 0

local function fadeInText(label, targetTransparency, duration)
    local tween = TweenService:Create(label, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
        TextTransparency = targetTransparency,
    })
    tween:Play()
    return tween
end

local function showChapter(chapterData)
    chapterLabel.Text = string.upper(chapterData.displayName or chapterData.chapter or "")
    bodyLabel.Text = chapterData.text or ""
    bodyLabel.TextTransparency = 1
    continueButton.Visible = false

    fadeInText(bodyLabel, 0, 1.2)

    task.wait(0.6)
    continueButton.Visible = true
end

-- Returns true if the button was actually clicked, false if a newer
-- playback superseded this one while waiting.
local function waitForContinue(token)
    local clicked = false
    local connection
    connection = continueButton.MouseButton1Click:Connect(function()
        clicked = true
    end)

    while not clicked and token == currentToken do
        task.wait(0.1)
    end

    connection:Disconnect()
    return clicked and token == currentToken
end

local function playTimelapse(chapters, token)
    if not chapters or #chapters == 0 then
        warn("TimelapseViewer: received empty chapter list")
        return
    end

    gui.Enabled = true

    for _, chapterData in ipairs(chapters) do
        if token ~= currentToken then
            return -- superseded by a newer TimelapseEvent
        end
        showChapter(chapterData)
        if not waitForContinue(token) then
            return -- superseded while waiting for the click
        end
    end

    if token == currentToken then
        gui.Enabled = false
    end
end

timelapseEvent.OnClientEvent:Connect(function(chapters)
    currentToken += 1
    local token = currentToken
    playTimelapse(chapters, token)
end)

print("TimelapseViewer loaded. Waiting for TimelapseEvent...")
