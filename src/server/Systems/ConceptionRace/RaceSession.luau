-- RaceSession
--
-- Owns ONE player's private conception race: its own cloned copy of the track,
-- its own racers, its own result. Confirmed 2026-08-14 that the cutscene and
-- race are single-player (the nine rivals are NPCs), so races must not share
-- state or physical parts between players even though the wider game is
-- multiplayer.
--
-- Each session's clone is offset along X into its own "slot" so two players
-- racing simultaneously never see or collide with each other's track. Offsetting
-- on X only is deliberate: the race runs along Z, so FINISH_Z and all the pacing
-- math stay in absolute world coordinates and need no per-session translation.
--
-- NOTE ON LIFESPAN: the straight-line track this drives is slated for
-- replacement by the Petri-dish/converging layout. The SESSION STRUCTURE here
-- (slot allocation, lifecycle, per-player isolation, cleanup) is meant to
-- survive that change; the movement math marked GEOMETRY-SPECIFIC below is not.

local RaceSession = {}
RaceSession.__index = RaceSession

local RACER_COUNT = 10

-- ===== GEOMETRY-SPECIFIC (straight-track only; expect to replace) =====
local FINISH_Z = 100
local START_Y = 1.5
local CLUSTER_SPEED = 7
local REVEAL_START_PROGRESS = 0.55
local WOBBLE_AMPLITUDE = 1.5
local MIN_FINAL_SPEED = 400  -- /100 -> 4.00 studs/s
local MAX_FINAL_SPEED = 1200 -- /100 -> 12.00 studs/s
-- ===== end geometry-specific =====

local RANK_BROADCAST_INTERVAL = 0.2
local STEP_INTERVAL = 0.03 -- ~30Hz

-- ===== Construction =====

-- template: the pristine ConceptionRace folder (kept out of Workspace)
-- offsetX:  this session's world slot offset
-- events:   { countdown, result, progress, assigned }
function RaceSession.new(player, template, offsetX, events)
    local self = setmetatable({}, RaceSession)

    self.player = player
    self.offsetX = offsetX
    self.events = events
    self.cancelled = false

    self.model = template:Clone()
    self.model.Name = "ConceptionRace_" .. player.UserId
    self.model:SetAttribute("OwnerUserId", player.UserId)

    -- Shift the whole clone into its slot before parenting, so it never
    -- appears at the origin for a frame.
    for _, descendant in ipairs(self.model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.CFrame = descendant.CFrame + Vector3.new(offsetX, 0, 0)
        end
    end
    self.model.Parent = workspace

    local racersFolder = self.model:FindFirstChild("Racers")
    self.racers = {}
    if racersFolder then
        for i = 1, RACER_COUNT do
            local part = racersFolder:FindFirstChild("Racer" .. i)
            if part then
                local entry = {
                    part = part,
                    index = i,
                    speed = 0,
                    finalSpeed = 0,
                    finished = false,
                    finishTime = 0,
                    placement = 0,
                }
                self:_setupRacerFX(entry)
                self.racers[i] = entry
            end
        end
    end

    return self
end

-- Per-racer visual FX. Lives here rather than in the coordinator because each
-- session's racers are distinct instances that each need their own.
function RaceSession:_setupRacerFX(entry)
    local part = entry.part

    -- Frosted glowing capsule -- racers are seen close-up from the
    -- first-person camera, so flat plastic reads as placeholder.
    part.Material = Enum.Material.Glass
    part.Transparency = 0.15

    local light = Instance.new("PointLight")
    light.Color = part.Color
    light.Brightness = 1
    light.Range = 10
    light.Parent = part

    local attFront = Instance.new("Attachment")
    attFront.Name = "RacerTrailFront"
    attFront.Position = Vector3.new(0, 0, -2)
    attFront.Parent = part

    local attBack = Instance.new("Attachment")
    attBack.Name = "RacerTrailBack"
    attBack.Position = Vector3.new(0, 0, 2)
    attBack.Parent = part

    local trail = Instance.new("Trail")
    trail.Attachment0 = attFront
    trail.Attachment1 = attBack
    trail.Color = ColorSequence.new(part.Color)
    trail.Lifetime = 0.25
    trail.MinLength = 0
    trail.WidthScale = NumberSequence.new(1, 0)
    trail.Transparency = NumberSequence.new(0.6, 1)
    trail.Parent = part

    entry.light = light
    entry.trail = trail
end

-- ===== Lifecycle =====

function RaceSession:IsAlive()
    return not self.cancelled and self.player.Parent ~= nil
end

function RaceSession:Cancel()
    self.cancelled = true
end

function RaceSession:Destroy()
    self.cancelled = true
    if self.model then
        self.model:Destroy()
        self.model = nil
    end
    self.racers = {}
end

-- Tells this session's owner which track instance is theirs, so the client
-- camera and ranking HUD bind to their own clone rather than a hardcoded path.
function RaceSession:Announce()
    if self.events.assigned then
        self.events.assigned:FireClient(self.player, self.model)
    end
end

function RaceSession:Countdown(seconds)
    if self.events.countdown then
        self.events.countdown:FireClient(self.player, seconds)
    end

    for i = seconds, 1, -1 do
        if not self:IsAlive() then return false end
        task.wait(1)
    end

    if not self:IsAlive() then return false end
    if self.events.countdown then
        self.events.countdown:FireClient(self.player, 0)
    end
    return true
end

-- ===== The race itself =====

function RaceSession:_assignHiddenPaces()
    for i = 1, RACER_COUNT do
        local racer = self.racers[i]
        if racer then
            racer.finalSpeed = math.random(MIN_FINAL_SPEED, MAX_FINAL_SPEED) / 100
            racer.speed = CLUSTER_SPEED
        end
    end
end

function RaceSession:_broadcastRanking()
    if not self.events.progress then return end
    local ranking = {}
    for i = 1, RACER_COUNT do
        local racer = self.racers[i]
        if racer then
            table.insert(ranking, {index = i, z = racer.part.Position.Z, finished = racer.finished})
        end
    end
    table.sort(ranking, function(a, b) return a.z > b.z end)
    self.events.progress:FireClient(self.player, ranking)
end

-- Runs the race to completion. Returns the finish order (array of racer
-- indices, best first), or nil if the session was cancelled partway.
function RaceSession:Run()
    self:_assignHiddenPaces()

    local startClock = os.clock()
    local finishedCount = 0
    local finishOrder = {}
    local lastBroadcast = 0

    while finishedCount < RACER_COUNT do
        local dt = task.wait(STEP_INTERVAL)
        if not self:IsAlive() then return nil end

        local elapsed = os.clock() - startClock

        -- Cluster-then-reveal: everyone holds a shared pace until the leader
        -- crosses the reveal threshold, then each blends toward its true speed.
        local leaderZ = 0
        for i = 1, RACER_COUNT do
            local racer = self.racers[i]
            if racer and racer.part.Position.Z > leaderZ then
                leaderZ = racer.part.Position.Z
            end
        end

        local leaderProgress = math.clamp(leaderZ / FINISH_Z, 0, 1)
        local revealBlend = 0
        if leaderProgress > REVEAL_START_PROGRESS then
            local t = math.clamp((leaderProgress - REVEAL_START_PROGRESS) / (1 - REVEAL_START_PROGRESS), 0, 1)
            revealBlend = t * t * (3 - 2 * t) -- smoothstep
        end

        for i = 1, RACER_COUNT do
            local racer = self.racers[i]
            if racer and not racer.finished then
                local wobble = math.noise(elapsed * 1.5, i * 12.7) * WOBBLE_AMPLITUDE * (1 - revealBlend)
                racer.speed = (CLUSTER_SPEED + wobble) * (1 - revealBlend) + racer.finalSpeed * revealBlend

                local cf = racer.part.CFrame
                local newZ = cf.Position.Z + racer.speed * dt
                racer.part.CFrame = CFrame.new(Vector3.new(cf.Position.X, cf.Position.Y, newZ)) * (cf - cf.Position)

                if racer.trail then
                    local speedFrac = math.clamp((racer.speed - 3) / 10, 0, 1)
                    racer.trail.Lifetime = 0.25 + speedFrac * 0.5
                    racer.light.Brightness = 1 + speedFrac * 2.5
                end

                if newZ >= FINISH_Z then
                    racer.finished = true
                    racer.finishTime = elapsed
                    finishedCount = finishedCount + 1
                    racer.placement = finishedCount
                    table.insert(finishOrder, i)
                end
            end
        end

        if elapsed - lastBroadcast >= RANK_BROADCAST_INTERVAL then
            lastBroadcast = elapsed
            self:_broadcastRanking()
        end
    end

    return finishOrder
end

function RaceSession:GetPlacement(racerIndex)
    local racer = self.racers[racerIndex]
    return racer and racer.placement or 0
end

function RaceSession:GetRacerColor(racerIndex)
    local racer = self.racers[racerIndex]
    if not racer then return "Unknown" end
    return racer.part:GetAttribute("RacerColor") or "Unknown"
end

function RaceSession:GetFinishTime(racerIndex)
    local racer = self.racers[racerIndex]
    return racer and racer.finishTime or 0
end

RaceSession.RACER_COUNT = RACER_COUNT

return RaceSession
