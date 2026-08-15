-- ConceptionRaceServer
--
-- Coordinator for per-player conception races. Rewritten 2026-08-14 from a
-- single shared continuous race loop into per-player instanced sessions, after
-- the project owner confirmed the cutscene and race are single-player (the
-- nine rival racers are NPCs) even though the wider game is multiplayer.
--
-- Responsibilities kept here: global environment mood (Lighting is genuinely
-- shared), the race track template, world-slot allocation, and the post-race
-- pipeline (SpawnWheel -> Timelapse -> StatsPanel). Everything about running an
-- individual race lives in Systems.ConceptionRace.RaceSession.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local SpawnWheel = require(ServerScriptService.Systems.SpawnWheel.SpawnWheel)
local TimelapseGenerator = require(ServerScriptService.Systems.Timelapse.TimelapseGenerator)
local StatsPanelServer = require(ServerScriptService.Systems.StatsPanel.StatsPanelServer)
local RaceSession = require(ServerScriptService.Systems.ConceptionRace.RaceSession)

local events = {
    select = ReplicatedStorage:WaitForChild("RacerSelectEvent"),
    result = ReplicatedStorage:WaitForChild("RaceResultEvent"),
    countdown = ReplicatedStorage:WaitForChild("CountdownEvent"),
    progress = ReplicatedStorage:WaitForChild("RaceProgressEvent"),
    assigned = ReplicatedStorage:WaitForChild("RaceAssignedEvent"),
}

local RACE_START_DELAY = 3
local CLEANUP_DELAY = 5      -- how long a finished track stays up before being removed
local SLOT_SPACING = 500     -- studs between concurrent sessions' world slots
local MAX_CONCURRENT = 24    -- slot pool size; well above any realistic server

-- ===== Race track template =====
-- The authored track lives in Workspace so it stays visible/editable in Studio,
-- but at runtime it is moved into ServerStorage and only ever cloned. Nothing
-- races on the template itself.
local template = Workspace:FindFirstChild("ConceptionRace")
if not template then
    template = ServerStorage:FindFirstChild("ConceptionRaceTemplate")
end
if not template then
    warn("[ConceptionRace] No race template found in Workspace or ServerStorage!")
    return
end
template.Name = "ConceptionRaceTemplate"
template.Parent = ServerStorage

-- ===== Global environment mood (shared -- Lighting is not per-player) =====
local function setupEnvironmentMood()
    Lighting.Brightness = 1
    Lighting.Ambient = Color3.fromRGB(15, 15, 18)
    Lighting.OutdoorAmbient = Color3.fromRGB(20, 18, 20)
    Lighting.ColorShift_Bottom = Color3.fromRGB(40, 5, 5)
    Lighting.FogColor = Color3.fromRGB(10, 8, 10)
    Lighting.FogStart = 60
    Lighting.FogEnd = 220

    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
    if not atmosphere then
        atmosphere = Instance.new("Atmosphere")
        atmosphere.Parent = Lighting
    end
    atmosphere.Density = 0.3
    atmosphere.Offset = 0.25
    atmosphere.Color = Color3.fromRGB(140, 140, 145)
    atmosphere.Decay = Color3.fromRGB(30, 30, 35)
    atmosphere.Glare = 0
    atmosphere.Haze = 0.5
end

-- Static dressing baked into the TEMPLATE once, so every clone inherits it
-- instead of each session rebuilding identical lights.
local function dressTemplate()
    for i = 1, 9 do
        local divider = template:FindFirstChild("Divider" .. i)
        if divider then
            divider.Material = Enum.Material.Neon
            divider.Color = Color3.fromRGB(90, 15, 15)
        end
    end

    for _, child in ipairs(template:GetChildren()) do
        if child.Name:match("^LightRig_") then
            child:Destroy()
        end
    end

    -- Overhead strip lights the racer passes under at a steady rhythm --
    -- monotone so nothing mixes into the colour banding an earlier
    -- three-spotlight rig produced.
    for _, z in ipairs({15, 30, 45, 60, 75, 90}) do
        local rig = Instance.new("Part")
        rig.Name = "LightRig_" .. z
        rig.Anchored = true
        rig.CanCollide = false
        rig.CanQuery = false
        rig.Transparency = 1
        rig.Size = Vector3.new(1, 1, 1)
        rig.CFrame = CFrame.new(0, 16, z)
        rig.Parent = template

        local spot = Instance.new("SpotLight")
        spot.Color = Color3.fromRGB(200, 195, 190)
        spot.Brightness = 3
        spot.Range = 25
        spot.Angle = 60
        spot.Face = Enum.NormalId.Bottom
        spot.Parent = rig
    end
end

setupEnvironmentMood()
dressTemplate()

-- ===== World slot allocation =====
-- Concurrent sessions are spaced far enough apart that no player can see
-- another's race. Slots are recycled as sessions end.
local slotInUse = {}

local function acquireSlot()
    for i = 0, MAX_CONCURRENT - 1 do
        if not slotInUse[i] then
            slotInUse[i] = true
            return i
        end
    end
    return nil
end

local function releaseSlot(slot)
    slotInUse[slot] = nil
end

-- ===== Sessions =====
local activeSessions = {} -- [player] = RaceSession

local function runRaceForPlayer(player, racerIndex)
    if activeSessions[player] then
        print("[ConceptionRace] " .. player.Name .. " already has a race in progress; ignoring.")
        return
    end

    local slot = acquireSlot()
    if not slot then
        warn("[ConceptionRace] No free world slot for " .. player.Name)
        return
    end

    local session = RaceSession.new(player, template, slot * SLOT_SPACING, events)
    activeSessions[player] = session
    print(string.format("[ConceptionRace] %s -> Racer #%d, slot %d", player.Name, racerIndex, slot))

    local ok, err = pcall(function()
        session:Announce()

        if not session:Countdown(RACE_START_DELAY) then return end

        local finishOrder = session:Run()
        if not finishOrder then
            print("[ConceptionRace] Session cancelled for " .. player.Name)
            return
        end

        local placement = session:GetPlacement(racerIndex)
        local color = session:GetRacerColor(racerIndex)

        -- Full finish order, so a skewed distribution (e.g. the player's pick
        -- winning suspiciously often) is visible in the log rather than silent.
        local orderParts = {}
        for rank, idx in ipairs(finishOrder) do
            table.insert(orderParts, string.format("%d:R%d", rank, idx))
        end
        print("[ConceptionRace] Finish order -- " .. table.concat(orderParts, " "))

        print(string.format("[ConceptionRace] %s finished #%d/%d with Racer #%d (%s)",
            player.Name, placement, RaceSession.RACER_COUNT, racerIndex, color))

        events.result:FireClient(player, placement, RaceSession.RACER_COUNT, racerIndex, color)

        -- Post-race pipeline. Unchanged from the previous architecture -- it was
        -- always per-player, it just used to run inside a shared loop.
        SpawnWheel.RollForPlayer(player, placement)
        TimelapseGenerator.GenerateAndSendToPlayer(player)
        StatsPanelServer.PushToPlayer(player)

        task.wait(CLEANUP_DELAY)
    end)

    if not ok then
        warn("[ConceptionRace] Session error for " .. player.Name .. ": " .. tostring(err))
    end

    session:Destroy()
    releaseSlot(slot)
    activeSessions[player] = nil
    print("[ConceptionRace] Session cleaned up for " .. player.Name)
end

-- ===== Entry point =====
-- A selection now STARTS that player's race rather than feeding a shared loop.
-- Fired today by the in-world racer click; will be fired by the lineup
-- selection screen once that replaces it.
events.select.OnServerEvent:Connect(function(player, racerIndex)
    if type(racerIndex) ~= "number" then return end
    if racerIndex ~= math.floor(racerIndex) then return end
    if racerIndex < 1 or racerIndex > RaceSession.RACER_COUNT then return end

    task.spawn(runRaceForPlayer, player, racerIndex)
end)

-- Tear a session down immediately if its owner leaves mid-race, rather than
-- letting an orphaned track keep animating in a slot nobody can reclaim.
Players.PlayerRemoving:Connect(function(player)
    local session = activeSessions[player]
    if session then
        session:Cancel()
    end
end)

print("[ConceptionRace] Coordinator ready (per-player instanced sessions).")
