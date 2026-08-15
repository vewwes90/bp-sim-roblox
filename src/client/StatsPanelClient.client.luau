-- StatsPanelClient LocalScript
-- Small toggleable panel showing the player's generated stats (4 parent
-- stats with tier names, plus their sub-stats). Plain/dark styling to
-- match the project's bleak tone -- see TimelapseViewer for the same
-- convention.
--
-- NOTE: layout, spacing, and toggle feel are first-pass and have NOT been
-- playtested live -- check these in Studio.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local requestStatsEvent = ReplicatedStorage:WaitForChild("RequestStatsEvent", 10)
local statsUpdateEvent = ReplicatedStorage:WaitForChild("StatsUpdateEvent", 10)

if not requestStatsEvent or not statsUpdateEvent then
    warn("StatsPanelClient: RequestStatsEvent/StatsUpdateEvent not found in ReplicatedStorage")
    return
end

-- ===== GUI =====
local gui = Instance.new("ScreenGui")
gui.Name = "StatsPanelGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
-- Stays below TimelapseGui (DisplayOrder 10), which is fully opaque and
-- full-screen, so this panel is naturally hidden during the timelapse
-- without any cross-script coupling.
gui.DisplayOrder = 1
gui.Parent = player:WaitForChild("PlayerGui")

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.Size = UDim2.new(0, 110, 0, 40)
toggleButton.Position = UDim2.new(0, 20, 0, 20)
toggleButton.BackgroundColor3 = Color3.fromRGB(20, 20, 23)
toggleButton.BorderSizePixel = 1
toggleButton.BorderColor3 = Color3.fromRGB(80, 80, 85)
toggleButton.Font = Enum.Font.RobotoMono
toggleButton.TextSize = 16
toggleButton.TextColor3 = Color3.fromRGB(190, 190, 195)
toggleButton.Text = "STATS"
toggleButton.AutoButtonColor = true
toggleButton.ZIndex = 2
toggleButton.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(0, 340, 0, 440)
panel.Position = UDim2.new(0, 20, 0, 70)
panel.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 1
panel.BorderColor3 = Color3.fromRGB(70, 70, 75)
panel.Visible = false
panel.ZIndex = 1
panel.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -20, 0, 30)
title.Position = UDim2.new(0, 10, 0, 8)
title.BackgroundTransparency = 1
title.Font = Enum.Font.RobotoMono
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(150, 150, 155)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "RECORD"
title.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Scroll"
scroll.Size = UDim2.new(1, -20, 1, -50)
scroll.Position = UDim2.new(0, 10, 0, 42)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 95)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 4)
listLayout.Parent = scroll

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.new(1, 0, 0, 30)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.RobotoMono
statusLabel.TextSize = 15
statusLabel.TextColor3 = Color3.fromRGB(140, 140, 145)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextWrapped = true
statusLabel.Text = "Loading..."
statusLabel.LayoutOrder = 0
statusLabel.Visible = false
statusLabel.Parent = scroll

-- ===== Row builders =====
local function clearRows()
    for _, child in scroll:GetChildren() do
        if child:IsA("TextLabel") and child ~= statusLabel then
            child:Destroy()
        end
    end
end

local function makeRow(text, order, indent, color)
    local row = Instance.new("TextLabel")
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1, -indent, 0, 22)
    row.Position = UDim2.new(0, indent, 0, 0)
    row.Font = Enum.Font.RobotoMono
    row.TextSize = indent > 0 and 14 or 16
    row.TextColor3 = color
    row.TextXAlignment = Enum.TextXAlignment.Left
    row.Text = text
    row.LayoutOrder = order
    row.Parent = scroll
    return row
end

local function renderPayload(payload)
    clearRows()
    statusLabel.Visible = false

    local order = 1
    for _, parentEntry in ipairs(payload.parentStats) do
        makeRow(
            string.format("%s \226\128\148 %s (%d)", parentEntry.displayName, parentEntry.tierName, parentEntry.value),
            order, 0, Color3.fromRGB(210, 210, 215)
        )
        order += 1

        local subRows = payload.subStatsByParent[parentEntry.statName]
        if subRows then
            for _, sub in ipairs(subRows) do
                makeRow(
                    string.format("%s: %d", sub.name, sub.value),
                    order, 18, Color3.fromRGB(130, 130, 135)
                )
                order += 1
            end
        end
    end
end

local function showPlaceholder(text)
    clearRows()
    statusLabel.Text = text
    statusLabel.Visible = true
end

-- ===== State =====
local latestPayload = nil

statsUpdateEvent.OnClientEvent:Connect(function(payload)
    latestPayload = payload
    if panel.Visible then
        renderPayload(payload)
    end
end)

local panelOpen = false
toggleButton.MouseButton1Click:Connect(function()
    panelOpen = not panelOpen
    panel.Visible = panelOpen

    if panelOpen then
        if latestPayload then
            renderPayload(latestPayload)
        else
            showPlaceholder("Loading...")
        end
        requestStatsEvent:FireServer()

        -- If nothing arrives shortly, this player hasn't gone through
        -- conception yet -- show a placeholder instead of spinning forever.
        task.delay(3, function()
            if panelOpen and not latestPayload then
                showPlaceholder("Nothing recorded yet.")
            end
        end)
    end
end)

print("StatsPanelClient loaded.")
