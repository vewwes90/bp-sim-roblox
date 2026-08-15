--!strict
-- PlayerDataManager (ModuleScript)
-- A data management system inspired by ProfileService that uses session locking
-- to prevent data loss when servers crash or when a player joins twice.
--
-- HOW SESSION LOCKING WORKS (in simple terms):
-- When a player joins, we "lock" their data by writing a special marker into
-- the DataStore that says "this data is in use by server X." If another server
-- tries to load the same player, it sees the lock and waits for it to release.
-- If the server that holds the lock crashes, the lock eventually expires
-- (after a timeout), and another server can safely claim it.
-- This prevents two servers from overwriting each other's data.

-- ============================================================
-- SERVICES
-- ============================================================
-- Services are Roblox's built-in systems. We grab the ones we need here.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- ============================================================
-- DATASTORE SETUP
-- ============================================================
-- We create one DataStore to hold all player data. Think of a DataStore as a
-- dictionary stored on Roblox's servers — each player gets their own "key"
-- (their UserId) that maps to their saved data.
local PlayerDataStore = DataStoreService:GetDataStore("PlayerData_v1")

-- ============================================================
-- CONFIGURATION
-- ============================================================
-- These constants control how the system behaves. You can tweak them.

-- How long (in seconds) a session lock is considered valid before it expires.
-- If the server holding the lock crashes, other servers will wait this long
-- before assuming the lock is stale and claiming it themselves.
local LOCK_TIMEOUT = 30 -- seconds

-- How often (in seconds) we refresh our lock while a player is online.
-- This tells other servers "we're still here, don't take our lock."
local LOCK_HEARTBEAT_INTERVAL = 10 -- seconds

-- Retry settings for DataStore calls. DataStores can fail temporarily,
-- so we retry with exponential backoff (waiting longer each time).
local MAX_RETRIES = 5 -- maximum number of retry attempts
local INITIAL_BACKOFF = 1 -- first retry waits 1 second, then 2, then 4, then 8...

-- The default data template. Every new player starts with this structure.
-- You can add more fields here as your game grows.
local DEFAULT_DATA = {
    coins = 0,
    gems = 0,
    level = 1,
    xp = 0,
    playtime = 0,
    inventory = {},
    stats = {
        kills = 0,
        deaths = 0,
    },
}

-- ============================================================
-- INTERNAL STATE (not exposed to other scripts)
-- ============================================================
-- This table holds the in-memory data for every player currently on this server.
-- Key = Player object, Value = their data table (a copy of DEFAULT_DATA + saved data).
local sessions = {}

-- This table tracks the heartbeat thread for each player so we can clean it up.
-- Key = Player object, Value = the coroutine (thread) running the lock refresh loop.
local heartbeatThreads = {}

-- A unique ID for this server instance, used in the lock to identify who holds it.
-- game.JobId is Roblox's real per-server unique identifier, but it's an empty
-- string in Studio (Edit mode and Play Solo aren't live servers), so we fall
-- back to a generated GUID there.
local SERVER_ID = (game.JobId ~= "" and game.JobId) or HttpService:GenerateGUID(false)

-- ============================================================
-- HELPER: deepCopy
-- ============================================================
-- Makes a complete copy of a table, including nested tables.
-- This is important because Lua tables are passed by reference — if we don't
-- copy, modifying one player's data could accidentally change another player's
-- data or even the DEFAULT_DATA template.
local function deepCopy(original)
    local copy = {}
    for key, value in pairs(original) do
        if type(value) == "table" then
            copy[key] = deepCopy(value) -- recursively copy nested tables
        else
            copy[key] = value
        end
    end
    return copy
end

-- ============================================================
-- HELPER: retryWithBackoff
-- ============================================================
-- Wraps a DataStore operation in retry logic with exponential backoff.
-- If the operation fails (e.g., Roblox servers are temporarily down), we wait
-- and try again, doubling the wait time each attempt.
--
-- Parameters:
--   callback: a function that performs the DataStore call and returns (success, result)
--   operationName: a string for logging (e.g., "LoadData")
--
-- Returns: (boolean success, any result)
local function retryWithBackoff(callback, operationName)
    local attempt = 0
    local backoff = INITIAL_BACKOFF

    while attempt < MAX_RETRIES do
        local success, result = callback()
        if success then
            return true, result
        end

        attempt += 1
        if attempt < MAX_RETRIES then
            warn(string.format("[PlayerDataManager] %s failed (attempt %d/%d). Retrying in %d seconds...",
                operationName, attempt, MAX_RETRIES, backoff))
            task.wait(backoff)
            backoff *= 2 -- exponential backoff: 1s, 2s, 4s, 8s, 16s...
        end
    end

    return false, result
end

-- ============================================================
-- CORE: acquireLock
-- ============================================================
-- Attempts to claim a session lock for a player in the DataStore.
--
-- A "lock" is just a small table we store alongside the player's data that says:
--   { serverId = SERVER_ID, timestamp = <current time> }
--
-- If another server already has a lock that hasn't expired, we wait and retry.
-- If the lock is expired (the other server crashed), we steal it.
-- If there's no lock at all, we claim it immediately.
--
-- Returns: (boolean success, table|nil savedData)
--   savedData is the player's existing data from the DataStore (or nil if new).
local function acquireLock(player)
    local key = tostring(player.UserId)
    local lockKey = key .. "_lock"

    -- We use UpdateAsync because it's the safest DataStore method — it reads the
    -- current value, lets us modify it, and writes it back atomically (no race conditions).
    local function attempt()
        local success, result = pcall(function()
            return PlayerDataStore:UpdateAsync(lockKey, function(existingLock)
                local now = os.time()

                -- Case 1: No lock exists — claim it.
                if not existingLock then
                    return {
                        serverId = SERVER_ID,
                        timestamp = now,
                    }
                end

                -- Case 2: We already hold the lock (e.g., retrying) — refresh it.
                if existingLock.serverId == SERVER_ID then
                    return {
                        serverId = SERVER_ID,
                        timestamp = now,
                    }
                end

                -- Case 3: Another server holds the lock, but it's expired — steal it.
                if (now - existingLock.timestamp) > LOCK_TIMEOUT then
                    warn(string.format("[PlayerDataManager] Stale lock detected for %s (held by %s, expired %ds ago). Claiming lock.",
                        player.Name, tostring(existingLock.serverId), now - existingLock.timestamp))
                    return {
                        serverId = SERVER_ID,
                        timestamp = now,
                    }
                end

                -- Case 4: Another server holds a valid lock — don't touch it.
                -- Returning nil tells UpdateAsync to not change the stored value.
                return nil
            end)
        end)

        if not success then
            return false, result
        end

        -- After UpdateAsync, we need to check if we actually got the lock.
        -- If another server's lock was valid, UpdateAsync returned nil and didn't change anything.
        -- We read back the lock to verify it's ours.
        local readSuccess, currentLock = pcall(function()
            return PlayerDataStore:GetAsync(lockKey)
        end)

        if not readSuccess then
            return false, currentLock
        end

        if currentLock and currentLock.serverId == SERVER_ID then
            -- We hold the lock! Now load the player's actual data.
            local dataSuccess, savedData = pcall(function()
                return PlayerDataStore:GetAsync(key)
            end)
            if not dataSuccess then
                return false, savedData
            end
            return true, savedData
        end

        -- Someone else holds the lock — return a special signal so the caller knows to wait.
        return false, "LOCK_HELD_BY_OTHER"
    end

    -- Retry the entire lock acquisition with backoff.
    -- We may need multiple rounds if another server holds the lock.
    local totalWaitTime = 0
    local maxTotalWait = LOCK_TIMEOUT + 10 -- give up after lock timeout + buffer

    while totalWaitTime < maxTotalWait do
        local success, result = retryWithBackoff(attempt, "acquireLock")
        if success then
            return true, result
        end
        if result ~= "LOCK_HELD_BY_OTHER" then
            -- A real error occurred, not just a lock conflict.
            return false, result
        end
        -- Lock is held by another server — wait a bit and try again.
        warn(string.format("[PlayerDataManager] Lock held by another server for %s. Waiting...", player.Name))
        task.wait(2)
        totalWaitTime += 2
    end

    return false, "LOCK_TIMEOUT"
end

-- ============================================================
-- CORE: releaseLock
-- ============================================================
-- Removes the session lock from the DataStore when a player leaves.
-- This lets other servers know the data is free to claim.
local function releaseLock(player)
    local lockKey = tostring(player.UserId) .. "_lock"

    local function attempt()
        local success, err = pcall(function()
            PlayerDataStore:RemoveAsync(lockKey)
        end)
        return success, err
    end

    local success, err = retryWithBackoff(attempt, "releaseLock")
    if not success then
        warn(string.format("[PlayerDataManager] Failed to release lock for %s: %s", player.Name, tostring(err)))
    end
end

-- ============================================================
-- CORE: saveData
-- ============================================================
-- Writes a player's current in-memory data to the DataStore.
-- Uses UpdateAsync to safely merge with any existing data.
local function saveData(player)
    local key = tostring(player.UserId)
    local data = sessions[player]
    if not data then return false, "No session data" end

    local function attempt()
        local success, err = pcall(function()
            PlayerDataStore:SetAsync(key, data)
        end)
        return success, err
    end

    local success, err = retryWithBackoff(attempt, "saveData")
    if not success then
        warn(string.format("[PlayerDataManager] Failed to save data for %s: %s", player.Name, tostring(err)))
    end
    return success, err
end

-- ============================================================
-- CORE: startHeartbeat
-- ============================================================
-- Spawns a background loop that periodically refreshes the lock timestamp.
-- This tells other servers "we're still active, don't steal our lock."
-- If we stop refreshing (because the server crashes), the lock will expire
-- after LOCK_TIMEOUT seconds, allowing another server to claim it.
local function startHeartbeat(player)
    -- Stop any existing heartbeat for this player.
    if heartbeatThreads[player] then
        task.cancel(heartbeatThreads[player])
    end

    local thread = task.spawn(function()
        while sessions[player] and player.Parent do
            task.wait(LOCK_HEARTBEAT_INTERVAL)

            local lockKey = tostring(player.UserId) .. "_lock"
            local function attempt()
                local success, err = pcall(function()
                    PlayerDataStore:UpdateAsync(lockKey, function(existingLock)
                        -- Only refresh if we still own the lock.
                        if existingLock and existingLock.serverId == SERVER_ID then
                            return {
                                serverId = SERVER_ID,
                                timestamp = os.time(),
                            }
                        end
                        return nil -- someone else took it, don't interfere
                    end)
                end)
                return success, err
            end

            local success, err = retryWithBackoff(attempt, "heartbeat")
            if not success then
                warn(string.format("[PlayerDataManager] Heartbeat failed for %s: %s", player.Name, tostring(err)))
            end
        end
    end)

    heartbeatThreads[player] = thread
end

-- ============================================================
-- CORE: loadPlayer
-- ============================================================
-- Called when a player joins. Acquires the lock, loads data (or creates
-- default data for new players), stores it in memory, and starts the heartbeat.
local function loadPlayer(player)
    print(string.format("[PlayerDataManager] Loading data for %s...", player.Name))

    -- Step 1: Acquire the session lock (waits if another server holds it).
    local lockSuccess, savedData = acquireLock(player)
    if not lockSuccess then
        warn(string.format("[PlayerDataManager] Could not acquire lock for %s: %s", player.Name, tostring(savedData)))
        -- We still let the player in with default data, but warn that their
        -- saved data couldn't be loaded. In a production game you might
        -- kick the player instead to prevent data overwrites.
        sessions[player] = deepCopy(DEFAULT_DATA)
        return
    end

    -- Step 2: Merge saved data with defaults.
    -- If the player is new (savedData is nil), they get DEFAULT_DATA.
    -- If they have saved data, we start with defaults and overwrite with saved
    -- values so new fields added in updates still get their defaults.
    local data = deepCopy(DEFAULT_DATA)
    if savedData and type(savedData) == "table" then
        for key, value in pairs(savedData) do
            data[key] = value
        end
    end

    -- Step 3: Store in memory and start the lock heartbeat.
    sessions[player] = data
    startHeartbeat(player)

    print(string.format("[PlayerDataManager] Data loaded for %s (coins: %d, level: %d)",
        player.Name, data.coins or 0, data.level or 1))
end

-- ============================================================
-- CORE: unloadPlayer
-- ============================================================
-- Called when a player leaves. Saves their data, releases the lock,
-- and cleans up in-memory state.
local function unloadPlayer(player)
    -- Stop the heartbeat loop.
    if heartbeatThreads[player] then
        task.cancel(heartbeatThreads[player])
        heartbeatThreads[player] = nil
    end

    -- Save data to the DataStore.
    if sessions[player] then
        saveData(player)
    end

    -- Release the session lock so other servers can claim it.
    releaseLock(player)

    -- Clean up in-memory data.
    sessions[player] = nil

    print(string.format("[PlayerDataManager] Data saved and lock released for %s", player.Name))
end

-- ============================================================
-- PUBLIC API
-- ============================================================
-- These are the functions other scripts can call after requiring this module.
-- Usage: local PlayerDataManager = require(game.ServerScriptService.Systems.DataStore.PlayerDataManager)

local PlayerDataManager = {}

-- GetData(player) -> table
-- Returns the player's current data table, or nil if not loaded.
-- Example: local data = PlayerDataManager.GetData(player)  ->  data.coins
function PlayerDataManager.GetData(player)
    return sessions[player]
end

-- SetData(player, key, value) -> boolean
-- Updates a single field in the player's data (in memory only).
-- The data is saved to the DataStore when the player leaves (via unloadPlayer).
-- Example: PlayerDataManager.SetData(player, "coins", 500)
function PlayerDataManager.SetData(player, key, value)
    local data = sessions[player]
    if not data then
        warn(string.format("[PlayerDataManager] Cannot set data for %s — no active session.", player.Name))
        return false
    end
    data[key] = value
    return true
end

-- SaveNow(player) -> boolean
-- Force-saves the player's data immediately (without waiting for them to leave).
-- Useful for important milestones like purchases or level-ups.
function PlayerDataManager.SaveNow(player)
    return saveData(player)
end

-- ============================================================
-- INITIALIZATION
-- ============================================================
-- Hook up PlayerAdded and PlayerRemoving events.
-- This runs automatically when the module is required.

-- Handle players who are already in the game (e.g., if this module loads late).
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(function()
        loadPlayer(player)
    end)
end

-- Handle players who join after this module is loaded.
Players.PlayerAdded:Connect(function(player)
    loadPlayer(player)
end)

-- Handle players who leave.
Players.PlayerRemoving:Connect(function(player)
    unloadPlayer(player)
end)

-- Handle the server shutting down (all players leaving at once).
-- On close, we save everyone's data and release all locks.
game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        unloadPlayer(player)
    end
    -- Give DataStore calls a moment to finish.
    task.wait(2)
end)

print("[PlayerDataManager] Module initialized and ready.")
return PlayerDataManager