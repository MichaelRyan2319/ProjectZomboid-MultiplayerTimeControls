-- Multiplayer Time Controls: the player's side. Shows the buttons, sends what the player picks to
-- the server, and runs this game at the speed the server says.
--
-- Does nothing outside a multiplayer game. The check is made while playing, not when this file
-- loads: the game loads Lua at the main menu, before anybody has joined a server.

if isServer() then return end

require "MultiplayerTimeControls/MTC_Core"
require "MultiplayerTimeControls/MTC_Panel"

local MTC = MultiplayerTimeControls

local Client = {}
MTC.Client = Client

Client.speed = MTC.PLAY     -- what the server last said
Client.by = nil             -- who set it
Client.why = nil            -- why the world went back to normal by itself: "moved", "danger", "died"
Client.known = false        -- has the server answered yet?
Client.changedAt = 0        -- when the speed last changed (ms), for the note next to the buttons
Client.note = nil           -- a refusal to show for a few seconds
Client.noteAt = 0
Client.active = false       -- are we in a multiplayer world right now?

local HELLO_EVERY_MS = 2000
local lastHello = 0

local function now()
    return getTimestampMs()
end

function Client.showNote(text)
    Client.note = text
    Client.noteAt = now()
end

-- The interface during a pause.
--
-- With "Render UI offscreen" on (Options > Display, the game's default) the game redraws its
-- interface only when enough game time has passed, so with the world stopped every window,
-- the chat and the menu would stay frozen on their last picture (seen on 42.22.2). For the length
-- of a pause that option is held off, which makes the game draw the interface every frame, and
-- it is put back when the pause ends. A note in Zomboid\Lua says "held" meanwhile, so a game that
-- was closed in the middle (or saved its options in the middle) is put right the next time this
-- file loads.
local MARKER = "MultiplayerTimeControls.ini"
Client.heldInterface = false

local function writeMarker(held)
    pcall(function()
        local writer = getFileWriter(MARKER, true, false)
        if writer then
            writer:write("uiOffscreenHeldOff=" .. (held and "1" or "0") .. "\r\n")
            writer:close()
        end
    end)
end

local function readMarker()
    local held = false
    pcall(function()
        local reader = getFileReader(MARKER, false)
        if reader then
            local line = reader:readLine()
            reader:close()
            held = line ~= nil and string.find(line, "uiOffscreenHeldOff=1", 1, true) ~= nil
        end
    end)
    return held
end

function Client.holdInterface(hold)
    local core = getCore()
    if hold then
        if not Client.heldInterface and core:getOptionUIFBO() then
            Client.heldInterface = true
            writeMarker(true)
            core:setOptionUIFBO(false)
        end
    elseif Client.heldInterface then
        Client.heldInterface = false
        core:setOptionUIFBO(true)
        -- written out in case the options were saved while it was held off
        pcall(function() core:saveOptions() end)
        writeMarker(false)
    end
end

-- Left held by a game that ended in the middle of a pause?
pcall(function()
    if readMarker() then
        local core = getCore()
        if not core:getOptionUIFBO() then
            core:setOptionUIFBO(true)
            core:saveOptions()
            MTC.log("\"Render UI offscreen\" was left off by a pause that never ended; switched back on")
        end
        writeMarker(false)
    end
end)

-- The player during a pause.
--
-- The game puts the speed back to normal by itself whenever the player presses a movement key or
-- starts an attack (that is how moving cancels fast forward in single player). In a pause that
-- would let the rest of each frame run at normal speed for whoever holds a key down. So for the
-- length of a pause the character takes no movement and starts no attack.
Client.heldPlayer = nil

function Client.holdPlayer(hold)
    local player = getPlayer()
    if hold then
        if not Client.heldPlayer and player then
            local was = {}
            pcall(function()
                was.move = player:isBlockMovement()
                was.melee = player:isAuthorizeMeleeAction()
                was.shove = player:isAuthorizeShoveStomp()
                player:setBlockMovement(true)
                player:setAuthorizeMeleeAction(false)
                player:setAuthorizeShoveStomp(false)
            end)
            Client.heldPlayer = was
        end
    elseif Client.heldPlayer then
        local was = Client.heldPlayer
        Client.heldPlayer = nil
        if player then
            pcall(function()
                player:setBlockMovement(was.move == true)
                player:setAuthorizeMeleeAction(was.melee ~= false)
                player:setAuthorizeShoveStomp(was.shove ~= false)
            end)
        end
    end
end

function Client.apply()
    getGameTime():setMultiplier(MTC.MULTIPLIER[Client.speed])
    Client.holdInterface(Client.speed == MTC.PAUSE)
    Client.holdPlayer(Client.speed == MTC.PAUSE)
end

-- "The game wants normal speed." In single player the game drops out of fast forward by itself
-- when the player moves, attacks, drives, drags a body or sees a zombie come into view, and when
-- a dialog opens. That code also runs in a multiplayer game, where all it does is set this game's
-- own multiplier to 1. Seeing a 1 while the server says "fast" therefore means one of those just
-- happened here: the server is asked to go back to normal speed, for everybody, whoever this
-- player is. Nobody has to stand still at 20 times speed with a zombie walking up.
local DROP_EVERY_MS = 300
local lastDrop = 0

-- why: "moved" (the game's own drop, above), "danger" (zombies, below) or "died".
function Client.dropToNormal(player, why)
    if now() - lastDrop < DROP_EVERY_MS then
        return
    end
    lastDrop = now()
    sendClientCommand(player, MTC.MOD, "normal", { why = why })
end

-- Zombies. Single player also leaves fast forward when a zombie the player can see comes within
-- 4 tiles (7 when more than four are in view), but the game skips that check in a multiplayer
-- game: at x20 three zombies that appeared 8 tiles away had killed a test character two seconds
-- later, with the world still racing. So the check is made here, for multiplayer, a little wider:
--   a zombie is after this player, or very close; or
--   a zombie in view is within the single-player distance plus a margin that grows with the
--   speed, because the news has to reach the server and come back before anything slows down.
function Client.inDanger(player)
    local danger = false
    pcall(function()
        local stats = player:getStats()
        if stats:getNumChasingZombies() > 0 or stats:getNumVeryCloseZombies() > 0 then
            danger = true
            return
        end
        local visible = stats:getNumVisibleZombies()
        if visible <= 0 then
            return
        end
        local range = (visible > 4 and 7 or 4) + (MTC.MULTIPLIER[Client.speed] or 1) * 0.3
        local spotted = player:getSpottedList()
        local px, py, pz = player:getX(), player:getY(), math.floor(player:getZ())
        for i = 0, spotted:size() - 1 do
            local other = spotted:get(i)
            if instanceof(other, "IsoZombie") and math.floor(other:getZ()) == pz then
                local dx, dy = other:getX() - px, other:getY() - py
                if dx * dx + dy * dy < range * range then
                    danger = true
                    return
                end
            end
        end
    end)
    return danger
end

-- May this player press that button? (The server checks again; this only greys buttons out.)
function Client.mayUse(speed)
    local player = getPlayer()
    return MTC.allowed(speed, player ~= nil and MTC.isAdmin(player))
end

-- A button or a key: ask the server for a speed. Pause is a switch: pressed while paused, it
-- goes back to the speed the pause started from, as the single-player button does.
function Client.request(speed)
    local player = getPlayer()
    if not Client.active or not player then
        return
    end
    if speed == MTC.PAUSE and Client.speed == MTC.PAUSE then
        speed = "resume"
    elseif speed == Client.speed then
        return
    end
    if type(speed) == "number" and speed > MTC.PLAY and Client.inDanger(player) then
        -- it would be dropped again at once
        Client.showNote(getText("UI_MTC_Refused_danger"))
        return
    end
    sendClientCommand(player, MTC.MOD, "set", { speed = speed })
end

local function onServerCommand(module, command, args)
    if module ~= MTC.MOD or not args then
        return
    end
    if command == "speed" or command == "refused" then
        local speed = tonumber(args.speed)
        if MTC.isSpeed(speed) then
            if Client.known and speed ~= Client.speed then
                Client.changedAt = now()
            end
            Client.speed = speed
            Client.by = args.by
            Client.why = args.why
            Client.known = true
            Client.apply()
        end
        if command == "refused" then
            Client.showNote(getText("UI_MTC_Refused_" .. tostring(args.reason or "fast")))
        end
    end
end

local function leave()
    -- The multiplier belongs to the game, not to a world: left at 0 or 40 it would carry into the
    -- main menu and the next game.
    if Client.active then
        getGameTime():setMultiplier(1)
    end
    Client.holdInterface(false)
    Client.holdPlayer(false)
    Client.active = false
    Client.known = false
    Client.speed = MTC.PLAY
    Client.by = nil
    Client.why = nil
    MTC.Panel.remove()
end

-- Exit and Quit to Desktop in the in-game menu. The game throws this Lua away on the way out
-- without telling it, so everything a pause holds is put back here, before the game goes.
-- (Any other way out, like a lost connection, is covered by the note in Zomboid\Lua: see above.)
local LEAVING_MS = 15000
Client.leavingAt = nil

require "OptionScreens/MainScreen"

local originalMenuClick = MainScreen.onMenuItemMouseDownMainMenu
if originalMenuClick then
    MainScreen.onMenuItemMouseDownMainMenu = function(item, x, y)
        if item and (item.internal == "EXIT" or item.internal == "QUIT_TO_DESKTOP")
                and MainScreen.instance and MainScreen.instance.inGame and Client.active then
            pcall(leave)
            Client.leavingAt = now()
        end
        return originalMenuClick(item, x, y)
    end
end

local function onTick()
    if not isClient() then
        if Client.active then
            leave()
        end
        return
    end
    if Client.leavingAt then
        -- on the way out: do not take the server's speed up again
        if now() - Client.leavingAt < LEAVING_MS then
            return
        end
        Client.leavingAt = nil
    end
    local player = getPlayer()
    if not player then
        return
    end
    if not Client.active then
        Client.active = true
        Client.known = false
        lastHello = 0
    end
    MTC.Panel.ensure()
    if not Client.known then
        if now() - lastHello >= HELLO_EVERY_MS then
            lastHello = now()
            sendClientCommand(player, MTC.MOD, "hello", {})
        end
        return
    end
    if player:isDead() then
        -- the death screen sets the multiplier to 1 every frame; a dead player has no say
        return
    end
    local actual = getGameTime():getTrueMultiplier()
    if actual ~= MTC.MULTIPLIER[Client.speed] then
        if Client.speed > MTC.PLAY and actual == 1 then
            Client.dropToNormal(player, "moved")
        else
            Client.apply()
        end
    elseif Client.speed > MTC.PLAY and Client.inDanger(player) then
        Client.dropToNormal(player, "danger")
    end
end

-- The player's own speed keys (Options > Key Bindings: Pause, Normal Speed, Fast Forward x1-x3).
-- The game ignores them in multiplayer.
function Client.onKeyPressed(key)
    if not isClient() or not Client.active or not Client.known then
        return
    end
    if not MainScreen.instance or not MainScreen.instance.inGame or MainScreen.instance:getIsVisible() then
        return
    end
    local core = getCore()
    local speed = nil
    if core:isKey(KeybindId.PAUSE, key) then
        speed = MTC.PAUSE
    elseif core:isKey(KeybindId.NORMAL_SPEED, key) then
        speed = MTC.PLAY
    elseif core:isKey(KeybindId.FAST_FORWARD_X1, key) then
        speed = MTC.FAST1
    elseif core:isKey(KeybindId.FAST_FORWARD_X2, key) then
        speed = MTC.FAST2
    elseif core:isKey(KeybindId.FAST_FORWARD_X3, key) then
        speed = MTC.FAST3
    end
    if speed == nil then
        return
    end
    local ok, reason = Client.mayUse(speed)
    if not ok and not (speed == MTC.PAUSE and Client.speed == MTC.PAUSE) then
        Client.showNote(getText("UI_MTC_Refused_" .. tostring(reason)))
        return
    end
    Client.request(speed)
end

-- A death ends fast forward for everybody, as it does in single player. Asked for once, here:
-- the death screen keeps this game's multiplier at 1 from then on, and onTick leaves the dead alone.
local function onPlayerDeath(player)
    if not isClient() or not Client.active or not Client.known then
        return
    end
    if player ~= nil and player == getPlayer() and Client.speed > MTC.PLAY then
        sendClientCommand(player, MTC.MOD, "normal", { why = "died" })
    end
end

Events.OnServerCommand.Add(onServerCommand)
if Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(onPlayerDeath)
end
Events.OnTick.Add(onTick)
Events.OnKeyPressed.Add(Client.onKeyPressed)
if Events.OnDisconnect then
    Events.OnDisconnect.Add(leave)
end
if Events.OnMainMenuEnter then
    Events.OnMainMenuEnter.Add(leave)
end
