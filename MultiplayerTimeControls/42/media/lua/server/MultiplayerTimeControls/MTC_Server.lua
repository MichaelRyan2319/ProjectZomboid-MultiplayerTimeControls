-- Multiplayer Time Controls: the server's side. The server holds the world's speed, decides who
-- may change it, and tells every player's game.
--
-- Only on a multiplayer server. The game also loads this folder in single player and in a
-- player's own game, where there is nothing for it to do (single player has its own buttons).

if not isServer() then return end

require "MultiplayerTimeControls/MTC_Core"

local MTC = MultiplayerTimeControls

local Server = {}
MTC.Server = Server

Server.speed = MTC.PLAY
Server.before = MTC.PLAY    -- the speed a pause ends with
Server.by = nil             -- who set the current speed (shown to the other players)
Server.why = nil            -- set when a player's game dropped out of fast forward by itself

local function name(player)
    local text = nil
    pcall(function() text = player:getDisplayName() end)
    if not text or text == "" then
        pcall(function() text = player:getUsername() end)
    end
    return tostring(text or "?")
end

function Server.state()
    return { speed = Server.speed, by = Server.by, why = Server.why }
end

function Server.apply()
    getGameTime():setMultiplier(MTC.MULTIPLIER[Server.speed])
end

-- The speed anti-cheat.
--
-- A dedicated server kicks a player who covers more than 20 tiles in a real second on foot (or
-- drives faster than the SpeedLimit option). In fast forward everybody moves 5, 20 or 40 times
-- faster, so an honest player walking at x20 was kicked within a second (tried on 42.22.2). The
-- limit on foot is fixed in the game, so the check cannot be scaled: while the world runs fast it
-- is switched off, and the owner's own setting comes back a few seconds after the speed is normal
-- again. Only in the server's memory: the server's .ini is not written.
local GUARD = "AntiCheatSpeed"
local GUARD_OFF = "4"               -- the option's "Disabled" value
local GUARD_BACK_AFTER_MS = 5000    -- players still report the last fast steps for a moment

Server.guardSaved = nil             -- the owner's value, while this mod holds the check off
Server.guardBackAt = nil            -- when to put it back (ms), nil while fast

local function guardOff()
    Server.guardBackAt = nil
    if Server.guardSaved ~= nil then
        return
    end
    local ok, err = pcall(function()
        local options = getServerOptions()
        local value = options:getOption(GUARD)
        if value ~= nil and tostring(value) ~= GUARD_OFF then
            Server.guardSaved = tostring(value)
            options:putOption(GUARD, GUARD_OFF)
            MTC.log("speed anti-cheat off while the world runs fast (the server's setting, " .. Server.guardSaved .. ", comes back at normal speed)")
        end
    end)
    if not ok then
        MTC.log("could not switch the speed anti-cheat off: " .. tostring(err))
    end
end

local function guardBack()
    Server.guardBackAt = nil
    if Server.guardSaved == nil then
        return
    end
    local saved = Server.guardSaved
    Server.guardSaved = nil
    local ok, err = pcall(function()
        local options = getServerOptions()
        -- an admin who changed the option meanwhile keeps what they chose
        if tostring(options:getOption(GUARD)) == GUARD_OFF then
            options:putOption(GUARD, saved)
            MTC.log("speed anti-cheat back to the server's setting (" .. saved .. ")")
        end
    end)
    if not ok then
        MTC.log("could not put the speed anti-cheat back: " .. tostring(err))
    end
end

-- Set the speed and tell everybody. by: the player's name, nil when the server did it itself.
-- why: only when a player's game dropped out of fast forward by itself ("moved", "danger", "died").
function Server.set(speed, by, why)
    if speed == Server.speed then
        return
    end
    if speed == MTC.PAUSE then
        Server.before = Server.speed
    end
    if speed > MTC.PLAY then
        guardOff()
    elseif Server.guardSaved ~= nil then
        Server.guardBackAt = getTimestampMs() + GUARD_BACK_AFTER_MS
    end
    Server.speed = speed
    Server.by = by
    Server.why = why
    Server.apply()
    sendServerCommand(MTC.MOD, "speed", Server.state())
    local label = speed == MTC.PAUSE and "pause" or ("x" .. tostring(MTC.MULTIPLIER[speed]))
    MTC.log("speed " .. tostring(speed) .. " (" .. label .. ") set by " .. tostring(by or "the server") .. (why and (" (" .. why .. ")") or ""))
end

-- Is anybody online who could put the speed back? A pause or a fast forward must not outlive
-- the people able to end it: an empty server, or (with "Admins only") the last admin leaving.
function Server.somebodyCanChangeIt()
    local result = true
    pcall(function()
        local players = getOnlinePlayers()
        if players:size() == 0 then
            result = false
        elseif (tonumber(MTC.option("WhoCanControl")) or 1) == 2 then
            result = false
            for i = 0, players:size() - 1 do
                if MTC.isAdmin(players:get(i)) then
                    result = true
                    break
                end
            end
        end
    end)
    return result
end

local Commands = {}

-- A player's game asks for the current speed when it enters the world.
Commands.hello = function(player, args)
    -- A pause or a fast forward does not outlive the players who chose it: the first one into an
    -- empty world finds it at normal speed.
    local online = 1
    pcall(function() online = getOnlinePlayers():size() end)
    if online <= 1 and Server.speed ~= MTC.PLAY then
        Server.set(MTC.PLAY, nil)
    end
    sendServerCommand(player, MTC.MOD, "speed", Server.state())
end

-- args.speed: 0 to 4, or "resume" to end a pause at the speed it started from.
Commands.set = function(player, args)
    local speed = args and args.speed
    if speed == "resume" then
        speed = Server.before or MTC.PLAY
        if speed == MTC.PAUSE then
            speed = MTC.PLAY
        end
        if not MTC.allowed(speed, MTC.isAdmin(player)) then
            speed = MTC.PLAY
        end
    else
        speed = tonumber(speed)
    end
    local ok, reason = MTC.allowed(speed, MTC.isAdmin(player))
    if not ok then
        sendServerCommand(player, MTC.MOD, "refused", { reason = reason, speed = Server.speed, by = Server.by })
        return
    end
    Server.set(speed, name(player))
end

-- A player's game dropped out of fast forward by itself (the player moved, attacked, drove or saw
-- a zombie: see MTC_Client.lua). Anybody may do this, whatever "Who can change the speed" says:
-- it only ever goes from fast to normal, never out of a pause.
local WHY = { moved = true, danger = true, died = true }

Commands.normal = function(player, args)
    if Server.speed > MTC.PLAY then
        local why = args and args.why
        Server.set(MTC.PLAY, name(player), WHY[why] and why or "moved")
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= MTC.MOD then
        return
    end
    local handler = Commands[command]
    if handler and player then
        handler(player, args or {})
    end
end

-- Other code sets the multiplier back to 1 now and then (the game's own /setTimeSpeed, mods), and
-- an empty server should not keep racing or stay frozen.
local ticks = 0
local lastTick = 0
local STALLED_MS = 5000
local function onTick()
    -- A server with "PauseEmpty" stops running Lua the moment its last player leaves, so a pause
    -- or a fast forward left behind cannot be undone then. A long gap between two ticks means
    -- exactly that happened (or the server hung): start again at normal speed.
    local t = getTimestampMs()
    if lastTick ~= 0 and t - lastTick > STALLED_MS and Server.speed ~= MTC.PLAY then
        Server.set(MTC.PLAY, nil)
    end
    lastTick = t
    if getGameTime():getTrueMultiplier() ~= MTC.MULTIPLIER[Server.speed] then
        Server.apply()
    end
    if Server.guardBackAt and getTimestampMs() >= Server.guardBackAt then
        guardBack()
    end
    ticks = ticks + 1
    if ticks >= 20 then
        ticks = 0
        if Server.speed ~= MTC.PLAY and not Server.somebodyCanChangeIt() then
            Server.set(MTC.PLAY, nil)
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(onTick)

MTC.log("server part " .. MTC.VERSION .. " loaded")
