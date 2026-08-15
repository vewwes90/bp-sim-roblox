-- WheelSpinViewer LocalScript
-- Reveals the SpawnWheel result (wheel + segment) with a short slot-style
-- spin animation before the timelapse begins. Plain/dark styling, no
-- confetti or celebratory color -- matches the project's bleak tone even
-- on a "Fortunate" result (muted colors only, no gold/shiny).
--
-- Layering: this GUI's DisplayOrder (20) is above TimelapseGui (10), which
-- is above StatsPanelGui (1), and its background blocks input (Active =
-- true) so the player can't click through to the timelapse's Continue
-- button while the spin is still resolving. No server changes needed --
-- SpawnWheelResultEvent already fires with (wheelName, segmentName,
-- wheelBias) from SpawnWheel.RollForPlayer.
--
-- NOTE: spin speed/duration and overall pacing are first-pass and have
-- NOT been judged by a human -- check these in Studio.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local spawnWheelResultEvent = ReplicatedStorage:WaitForChild("SpawnWheelResultEvent", 10)

if not spawnWheelResultEvent then
    warn("WheelSpinViewer: SpawnWheelResultEvent not found in ReplicatedStorage")
    return
end

-- Must match SpawnWheel.lua's WHEEL_NAMES and SEGMENTS_BY_WHEEL exactly --
-- this is display-only cycling, the actual result always comes from the
-- server event, never rolled client-side.
local WHEEL_NAMES = { "Fortunate", "Average", "Difficult", "Bleak" }

local WHEEL_COLORS = {
    Fortunate = Color3.fromRGB(205, 205, 210),
    Average = Color3.fromRGB(150, 150, 155),
    Difficult = Color3.fromRGB(175, 115, 75),
    Bleak = Color3.fromRGB(150, 50, 50),
}

local SEGMENTS_BY_WHEEL = {
    Fortunate = { "Great", "Good", "Fine" },
    Average = { "Lucky", "Neutral", "Unlucky" },
    Difficult = { "Rough", "Hard", "Severe" },
    Bleak = { "Grim", "Dire", "Doomed" },
}

-- ===== GUI =====
local gui = Instance.new("ScreenGui")
gui.Name = "WheelSpinGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 20 -- above TimelapseGui (10) and StatsPanelGui (1)
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.new(1, 0, 1, 0)
background.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
background.BorderSizePixel = 0
background.Active = true -- blocks clicks from reaching anything underneath
background.Parent = gui

local header = Instance.new("TextLabel")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 40)
header.Position = UDim2.new(0, 0, 0.32, 0)
header.BackgroundTransparency = 1
header.Font = Enum.Font.RobotoMono
header.TextSize = 20
header.TextColor3 = Color3.fromRGB(120, 120, 125)
header.Text = "THE WHEEL"
header.Parent = background

local wheelLabel = Instance.new("TextLabel")
wheelLabel.Name = "WheelLabel"
wheelLabel.Size = UDim2.new(1, 0, 0, 70)
wheelLabel.Position = UDim2.new(0, 0, 0.4, 0)
wheelLabel.BackgroundTransparency = 1
wheelLabel.Font = Enum.Font.RobotoMono
wheelLabel.TextSize = 52
wheelLabel.TextColor3 = Color3.fromRGB(200, 200, 205)
wheelLabel.Text = ""
wheelLabel.Parent = background

local segmentLabel = Instance.new("TextLabel")
segmentLabel.Name = "SegmentLabel"
segmentLabel.Size = UDim2.new(1, 0, 0, 40)
segmentLabel.Position = UDim2.new(0, 0, 0.52, 0)
segmentLabel.BackgroundTransparency = 1
segmentLabel.Font = Enum.Font.RobotoMono
segmentLabel.TextSize = 26
segmentLabel.TextColor3 = Color3.fromRGB(160, 160, 165)
segmentLabel.Text = ""
segmentLabel.Visible = false
segmentLabel.Parent = background

-- ===== Spin sequences =====
-- Intervals shrink then grow again -- fast/blurry start, decelerating into
-- the landed result, like a slot reel settling.
local WHEEL_SPIN_INTERVALS = { 0.06, 0.06, 0.07, 0.08, 0.09, 0.11, 0.13, 0.16, 0.2, 0.25, 0.32, 0.4 }
local SEGMENT_SPIN_INTERVALS = { 0.06, 0.07, 0.08, 0.1, 0.12, 0.15, 0.19, 0.24, 0.3 }

-- `currentToken` guards against a second SpawnWheelResultEvent arriving
-- while an earlier spin animation is still running (e.g. repeated testing,
-- or any future case where the server fires this more than once) -- same
-- pattern as TimelapseViewer, so two spins never fight over the same labels.
local currentToken = 0

local function spinWheelName(finalWheelName, token)
    for _, interval in WHEEL_SPIN_INTERVALS do
        if token ~= currentToken then return false end
        local candidate = WHEEL_NAMES[math.random(1, #WHEEL_NAMES)]
        wheelLabel.Text = string.upper(candidate)
        wheelLabel.TextColor3 = WHEEL_COLORS[candidate]
        task.wait(interval)
    end
    if token ~= currentToken then return false end
    wheelLabel.Text = string.upper(finalWheelName)
    wheelLabel.TextColor3 = WHEEL_COLORS[finalWheelName]
    return true
end

local function spinSegmentName(wheelName, finalSegmentName, token)
    local options = SEGMENTS_BY_WHEEL[wheelName]
    for _, interval in SEGMENT_SPIN_INTERVALS do
        if token ~= currentToken then return false end
        local candidate = options[math.random(1, #options)]
        segmentLabel.Text = string.upper(candidate)
        task.wait(interval)
    end
    if token ~= currentToken then return false end
    segmentLabel.Text = string.upper(finalSegmentName)
    return true
end

spawnWheelResultEvent.OnClientEvent:Connect(function(wheelName, segmentName, wheelBias)
    if not WHEEL_COLORS[wheelName] or not SEGMENTS_BY_WHEEL[wheelName] then
        warn("WheelSpinViewer: unknown wheelName from server: " .. tostring(wheelName))
        return
    end

    currentToken += 1
    local token = currentToken

    gui.Enabled = true
    wheelLabel.Text = ""
    segmentLabel.Text = ""
    segmentLabel.Visible = false

    if not spinWheelName(wheelName, token) then return end
    task.wait(0.4)
    if token ~= currentToken then return end
    segmentLabel.Visible = true
    if not spinSegmentName(wheelName, segmentName, token) then return end

    task.wait(1.5)
    if token == currentToken then
        gui.Enabled = false
    end
end)

print("WheelSpinViewer loaded. Waiting for SpawnWheelResultEvent...")
