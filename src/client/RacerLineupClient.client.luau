-- RacerLineupClient
--
-- The horse-race-style lineup the player picks from, replacing the old
-- click-a-racer-in-the-world flow (which can't work any more: with per-player
-- instanced races there IS no track until after you've chosen).
--
-- DEFERRED REVEAL, per the project owner's chosen option: no form information
-- is available at pick time, and afterwards the game tells you why.
--
-- The owner's specific worry was that blank cards would read as a bug -- like
-- text failed to load. So the cards deliberately show the STRUCTURE of a form
-- guide (FORM / ODDS / NOTE rows) with every value visibly redacted, rather
-- than showing nothing. "Information exists and is being withheld from you"
-- reads as authored; "nothing here" reads as broken.
--
-- ⚠️ COPY WRITTEN BY COWORK, NOT THE PROJECT OWNER -- all display strings
-- marked OWNER_COPY below are placeholders in the established institutional
-- register and should be rewritten or approved. No stat, number, or mechanic
-- is invented: every racer's number and colour comes from its real attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local localSelectedEvent = ReplicatedStorage:WaitForChild("LocalRacerSelectedEvent", 10)
local resultEvent = ReplicatedStorage:WaitForChild("RaceResultEvent", 10)
local showLineupEvent = ReplicatedStorage:WaitForChild("ShowRacerLineupEvent", 10)

local RACER_COUNT = 10
local DISPLAY_ORDER = 35 -- above CutsceneGui (30): the lineup appears during the cutscene's selection beat

-- Racer identity comes from the authored track, not from anything invented here.
-- Colours mirror the Racer1-10 parts' RacerColor attributes.
local RACER_COLORS = {
    {name = "Red", color = Color3.fromRGB(196, 40, 28)},
    {name = "Orange", color = Color3.fromRGB(218, 133, 65)},
    {name = "Yellow", color = Color3.fromRGB(245, 205, 48)},
    {name = "Lime", color = Color3.fromRGB(164, 189, 71)},
    {name = "Green", color = Color3.fromRGB(75, 151, 75)},
    {name = "SpringGreen", color = Color3.fromRGB(123, 178, 116)},
    {name = "Cyan", color = Color3.fromRGB(4, 175, 236)},
    {name = "LightBlue", color = Color3.fromRGB(110, 153, 202)},
    {name = "Purple", color = Color3.fromRGB(107, 50, 124)},
    {name = "Magenta", color = Color3.fromRGB(170, 66, 156)},
}

-- OWNER_COPY -- placeholder strings, rewrite freely
local COPY = {
    header = "TEN CANDIDATES",
    subheader = "RECORDS WITHHELD -- SELECTION IS FINAL",
    redacted = "[ WITHHELD ]",
    revealHeader = "THE FORM GUIDE",
    revealBody = "There was no form to withhold. Nothing recorded, nothing predictable, nothing you could have read. The order was decided the moment the gates dropped, and you were asked to choose before it was.",
    revealDismiss = "Continue",
}

local gui, grid, revealFrame
local cards = {}
local locked = false
local lastPick = nil

-- ===== Build =====
local function buildRedactedRow(parent, label, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -16, 0, 18)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order
    row.Parent = parent

    local key = Instance.new("TextLabel")
    key.Size = UDim2.new(0.38, 0, 1, 0)
    key.BackgroundTransparency = 1
    key.Font = Enum.Font.RobotoMono
    key.TextSize = 11
    key.TextColor3 = Color3.fromRGB(105, 105, 112)
    key.TextXAlignment = Enum.TextXAlignment.Left
    key.Text = label
    key.Parent = row

    -- A visible redaction bar rather than empty space: the point is that the
    -- player can see a value has been removed.
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0.62, 0, 0, 12)
    bar.Position = UDim2.new(0.38, 0, 0.5, -6)
    bar.BackgroundColor3 = Color3.fromRGB(58, 58, 64)
    bar.BorderSizePixel = 0
    bar.Parent = row
end

local function buildCard(index)
    local info = RACER_COLORS[index]

    local card = Instance.new("TextButton")
    card.Name = "Card" .. index
    card.Size = UDim2.new(0, 168, 0, 150)
    card.BackgroundColor3 = Color3.fromRGB(20, 20, 23)
    card.BorderSizePixel = 0
    card.AutoButtonColor = false
    card.Text = ""
    card.LayoutOrder = index
    card.Parent = grid

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(55, 55, 60)
    stroke.Thickness = 1
    stroke.Parent = card

    -- Colour swatch band -- the one genuinely distinguishing (and genuinely
    -- meaningless) thing about each racer.
    local swatch = Instance.new("Frame")
    swatch.Size = UDim2.new(1, 0, 0, 6)
    swatch.BackgroundColor3 = info.color
    swatch.BorderSizePixel = 0
    swatch.Parent = card

    local number = Instance.new("TextLabel")
    number.Size = UDim2.new(1, -16, 0, 30)
    number.Position = UDim2.new(0, 8, 0, 14)
    number.BackgroundTransparency = 1
    number.Font = Enum.Font.RobotoMono
    number.TextSize = 24
    number.TextColor3 = Color3.fromRGB(225, 225, 228)
    number.TextXAlignment = Enum.TextXAlignment.Left
    number.Text = string.format("%02d", index)
    number.Parent = card

    local colorName = Instance.new("TextLabel")
    colorName.Size = UDim2.new(1, -16, 0, 16)
    colorName.Position = UDim2.new(0, 8, 0, 44)
    colorName.BackgroundTransparency = 1
    colorName.Font = Enum.Font.RobotoMono
    colorName.TextSize = 12
    colorName.TextColor3 = Color3.fromRGB(140, 140, 146)
    colorName.TextXAlignment = Enum.TextXAlignment.Left
    colorName.Text = string.upper(info.name)
    colorName.Parent = card

    local rows = Instance.new("Frame")
    rows.Size = UDim2.new(1, -16, 0, 66)
    rows.Position = UDim2.new(0, 8, 0, 70)
    rows.BackgroundTransparency = 1
    rows.Parent = card

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 3)
    layout.Parent = rows

    buildRedactedRow(rows, "FORM", 1)
    buildRedactedRow(rows, "ODDS", 2)
    buildRedactedRow(rows, "NOTE", 3)

    card.MouseEnter:Connect(function()
        if locked then return end
        stroke.Color = Color3.fromRGB(180, 180, 186)
    end)
    card.MouseLeave:Connect(function()
        if locked then return end
        stroke.Color = Color3.fromRGB(55, 55, 60)
    end)

    card.MouseButton1Click:Connect(function()
        if locked then return end
        locked = true
        lastPick = index
        stroke.Color = Color3.fromRGB(255, 210, 90)
        stroke.Thickness = 2

        -- Dim everything not chosen, so the commitment reads immediately
        for otherIndex, other in pairs(cards) do
            if otherIndex ~= index then
                other.BackgroundTransparency = 0.55
                local s = other:FindFirstChildOfClass("UIStroke")
                if s then s.Transparency = 0.7 end
            end
        end

        localSelectedEvent:Fire(index)
        task.delay(1.0, function()
            gui.Enabled = false
        end)
    end)

    cards[index] = card
    return card
end

local function buildGui()
    if gui then return end

    gui = Instance.new("ScreenGui")
    gui.Name = "RacerLineupGui"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = DISPLAY_ORDER
    gui.Enabled = false
    gui.Parent = playerGui

    local bg = Instance.new("Frame")
    bg.Name = "Backdrop"
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
    bg.BackgroundTransparency = 0.12
    bg.BorderSizePixel = 0
    bg.Parent = gui

    local header = Instance.new("TextLabel")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 34)
    header.Position = UDim2.new(0, 0, 0, 60)
    header.BackgroundTransparency = 1
    header.Font = Enum.Font.RobotoMono
    header.TextSize = 26
    header.TextColor3 = Color3.fromRGB(230, 230, 233)
    header.Text = COPY.header
    header.Parent = gui

    local sub = Instance.new("TextLabel")
    sub.Name = "Subheader"
    sub.Size = UDim2.new(1, 0, 0, 20)
    sub.Position = UDim2.new(0, 0, 0, 96)
    sub.BackgroundTransparency = 1
    sub.Font = Enum.Font.RobotoMono
    sub.TextSize = 13
    sub.TextColor3 = Color3.fromRGB(125, 125, 132)
    sub.Text = COPY.subheader
    sub.Parent = gui

    grid = Instance.new("Frame")
    grid.Name = "Lineup"
    grid.Size = UDim2.new(0, 900, 0, 330)
    grid.Position = UDim2.new(0.5, -450, 0.5, -140)
    grid.BackgroundTransparency = 1
    grid.Parent = gui

    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0, 168, 0, 150)
    gridLayout.CellPadding = UDim2.new(0, 12, 0, 12)
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.Parent = grid

    for i = 1, RACER_COUNT do
        buildCard(i)
    end

    -- ===== Deferred reveal panel =====
    revealFrame = Instance.new("Frame")
    revealFrame.Name = "RevealFrame"
    revealFrame.Size = UDim2.new(1, 0, 1, 0)
    revealFrame.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
    revealFrame.BorderSizePixel = 0
    revealFrame.Visible = false
    revealFrame.ZIndex = 5
    revealFrame.Parent = gui

    local revealTitle = Instance.new("TextLabel")
    revealTitle.Size = UDim2.new(0.7, 0, 0, 30)
    revealTitle.Position = UDim2.new(0.15, 0, 0.32, 0)
    revealTitle.BackgroundTransparency = 1
    revealTitle.Font = Enum.Font.RobotoMono
    revealTitle.TextSize = 22
    revealTitle.TextColor3 = Color3.fromRGB(225, 225, 228)
    revealTitle.TextXAlignment = Enum.TextXAlignment.Left
    revealTitle.Text = COPY.revealHeader
    revealTitle.ZIndex = 6
    revealTitle.Parent = revealFrame

    local revealBody = Instance.new("TextLabel")
    revealBody.Name = "RevealBody"
    revealBody.Size = UDim2.new(0.7, 0, 0, 140)
    revealBody.Position = UDim2.new(0.15, 0, 0.32, 46)
    revealBody.BackgroundTransparency = 1
    revealBody.Font = Enum.Font.RobotoMono
    revealBody.TextSize = 16
    revealBody.TextColor3 = Color3.fromRGB(175, 175, 180)
    revealBody.TextXAlignment = Enum.TextXAlignment.Left
    revealBody.TextYAlignment = Enum.TextYAlignment.Top
    revealBody.TextWrapped = true
    revealBody.Text = COPY.revealBody
    revealBody.ZIndex = 6
    revealBody.Parent = revealFrame

    local dismiss = Instance.new("TextButton")
    dismiss.Size = UDim2.new(0, 200, 0, 40)
    dismiss.Position = UDim2.new(0.15, 0, 0.32, 200)
    dismiss.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
    dismiss.BorderSizePixel = 0
    dismiss.Font = Enum.Font.RobotoMono
    dismiss.TextSize = 15
    dismiss.TextColor3 = Color3.fromRGB(210, 210, 214)
    dismiss.Text = COPY.revealDismiss
    dismiss.ZIndex = 6
    dismiss.Parent = revealFrame

    dismiss.MouseButton1Click:Connect(function()
        gui.Enabled = false
        revealFrame.Visible = false
    end)
end

-- ===== Public behaviour =====
local function showLineup()
    buildGui()
    locked = false
    lastPick = nil
    revealFrame.Visible = false

    for _, card in pairs(cards) do
        card.BackgroundTransparency = 0
        local s = card:FindFirstChildOfClass("UIStroke")
        if s then
            s.Transparency = 0
            s.Thickness = 1
            s.Color = Color3.fromRGB(55, 55, 60)
        end
    end

    gui.Enabled = true
    print("[Lineup] Shown -- awaiting selection.")
end

showLineupEvent.Event:Connect(showLineup)

-- Deferred reveal: fires after the race resolves. Uses only real outcome data
-- plus the framing copy above -- nothing about the form guide is fabricated,
-- because the point is that there never was one.
resultEvent.OnClientEvent:Connect(function(placement, totalRacers, racerIndex)
    if not gui then return end
    task.delay(4.0, function()
        local body = gui.RevealFrame:FindFirstChild("RevealBody")
        if body then
            body.Text = string.format(
                "%s\n\nYou chose %02d. It finished %d of %d.",
                COPY.revealBody, racerIndex, placement, totalRacers
            )
        end
        gui.Enabled = true
        revealFrame.Visible = true
        print("[Lineup] Deferred reveal shown.")
    end)
end)

buildGui()
print("RacerLineupClient loaded. Fire ReplicatedStorage.ShowRacerLineupEvent to display.")
