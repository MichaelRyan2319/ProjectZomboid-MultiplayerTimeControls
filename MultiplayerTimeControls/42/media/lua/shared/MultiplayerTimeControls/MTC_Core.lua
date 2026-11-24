-- Multiplayer Time Controls: shared core (loaded by the server and by every player's game).
--
-- Single player has pause and three fast-forward speeds; multiplayer has none. The game does have
-- one speed for the whole world (GameTime's multiplier), and a debug command that sets it on the
-- server and in every player's game at once. This mod does the same from buttons and keys: the
-- server holds the speed, checks who asked, and tells everyone.

MultiplayerTimeControls = MultiplayerTimeControls or {}
local MTC = MultiplayerTimeControls

MTC.MOD = "MultiplayerTimeControls"
MTC.VERSION = "1.0.0"

-- The speeds, numbered the way the game numbers its own (getGameSpeed() in single player).
MTC.PAUSE = 0
MTC.PLAY = 1
MTC.FAST1 = 2
MTC.FAST2 = 3
MTC.FAST3 = 4

-- How fast the world runs at each speed: the same numbers as the single-player buttons.
--
-- A pause is not quite zero. Single player pauses by not updating the world at all; a multiplayer
-- game has no such switch that a mod can reach, so a pause here is the world running about a
-- millionth as fast (an hour of pause is 3 ms in the game). Exactly zero also stops things, but
-- two of the game's own windows divide by this number every frame. 2^-20 is exact as a float, so
-- what the game reports back equals what was set.
MTC.PAUSE_MULTIPLIER = 1 / 1048576
MTC.MULTIPLIER = { [0] = MTC.PAUSE_MULTIPLIER, [1] = 1, [2] = 5, [3] = 20, [4] = 40 }

function MTC.log(msg)
    print("[MultiplayerTimeControls] " .. tostring(msg))
end

function MTC.isSpeed(speed)
    return type(speed) == "number" and MTC.MULTIPLIER[speed] ~= nil
end

-- The server owner's settings (sandbox options, page "Multiplayer Time Controls").
-- These defaults must match media/sandbox-options.txt.
local DEFAULTS = {
    WhoCanControl = 1,      -- 1 everyone, 2 admins only
    AllowPause = true,
    FastestSpeed = 4,       -- 1 no fast forward, 2 up to x5, 3 up to x20, 4 up to x40
}

function MTC.option(name)
    local value = nil
    pcall(function()
        local option = getSandboxOptions():getOptionByName(MTC.MOD .. "." .. name)
        if option then
            value = option:getValue()
        end
    end)
    if value == nil and SandboxVars and SandboxVars[MTC.MOD] then
        value = SandboxVars[MTC.MOD][name]
    end
    if value == nil then
        value = DEFAULTS[name]
    end
    return value
end

-- May somebody set this speed here? Returns true, or false and the reason
-- ("admin", "pause" or "fast"; the player's game has a sentence for each).
function MTC.allowed(speed, isAdmin)
    if not MTC.isSpeed(speed) then
        return false, "fast"
    end
    if (tonumber(MTC.option("WhoCanControl")) or 1) == 2 and not isAdmin then
        return false, "admin"
    end
    if speed == MTC.PAUSE and not MTC.option("AllowPause") then
        return false, "pause"
    end
    if speed > MTC.PLAY and speed > (tonumber(MTC.option("FastestSpeed")) or 4) then
        return false, "fast"
    end
    return true
end

-- Is this player one of the server's staff? (Any role with the admin powers; a normal player has none.)
function MTC.isAdmin(player)
    local admin = false
    pcall(function()
        local role = player:getRole()
        admin = role ~= nil and role:hasAdminPower() == true
    end)
    return admin
end
