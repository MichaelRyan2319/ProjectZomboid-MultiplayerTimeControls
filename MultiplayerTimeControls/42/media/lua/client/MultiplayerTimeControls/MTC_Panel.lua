-- Multiplayer Time Controls: the buttons. They are the game's own single-player speed buttons
-- (same pictures, same sizes, same place under the clock), drawn by this mod because the game
-- leaves its own out of a multiplayer game.

if isServer() then return end

require "ISUI/ISUIElement"
require "MultiplayerTimeControls/MTC_Core"

local MTC = MultiplayerTimeControls

local Panel = {}
MTC.Panel = Panel

local GAP = 2               -- between buttons, as in single player
local EDGE = 10             -- from the right edge of the screen and from the clock
local NOTE_MS = 6000        -- how long "who changed it" stays up
local DIR = "media/ui/speedControls/"

local BUTTONS = {
    { speed = MTC.PAUSE, off = "Pause_Off.png", on = "Pause_On.png" },
    { speed = MTC.PLAY, off = "Play_Off.png", on = "Play_On.png" },
    { speed = MTC.FAST1, off = "FFwd1_Off.png", on = "FFwd1_On.png" },
    { speed = MTC.FAST2, off = "FFwd2_Off.png", on = "FFwd2_On.png" },
    { speed = MTC.FAST3, off = "Wait_Off.png", on = "Wait_On.png" },
}

MTCSpeedPanel = ISUIElement:derive("MTCSpeedPanel")

function MTCSpeedPanel:new()
    local o = ISUIElement.new(self, 0, 0, 10, 22)
    o.buttons = {}
    local x = 0
    local height = 22
    for _, def in ipairs(BUTTONS) do
        local off = getTexture(DIR .. def.off)
        local on = getTexture(DIR .. def.on)
        local w = off and off:getWidth() or 20
        local h = off and off:getHeight() or 22
        table.insert(o.buttons, { speed = def.speed, off = off, on = on, x = x, w = w, h = h })
        x = x + w + GAP
        height = math.max(height, h)
    end
    o:setWidth(x - GAP)
    o:setHeight(height)
    o.hover = nil
    return o
end

function MTCSpeedPanel:place()
    local core = getCore()
    local x = core:getScreenWidth() - self.width - EDGE
    local y = EDGE
    local clock = UIManager.getClock()
    if clock then
        y = clock:getY()
        if clock:isVisible() then
            y = y + clock:getHeight() + EDGE
        end
    end
    if x ~= self.x or y ~= self.y then
        self:setX(x)
        self:setY(y)
    end
end

function MTCSpeedPanel:buttonAt(x, y)
    if y < 0 or y > self.height then
        return nil
    end
    for _, button in ipairs(self.buttons) do
        if x >= button.x and x < button.x + button.w then
            return button
        end
    end
    return nil
end

function MTCSpeedPanel:prerender()
    self:place()
end

function MTCSpeedPanel:render()
    local client = MTC.Client
    local speed = client.speed
    local hover = self:isMouseOver() and self:buttonAt(self:getMouseX(), self:getMouseY()) or nil
    for _, button in ipairs(self.buttons) do
        local texture = (button.speed == speed and client.known) and button.on or button.off
        local alpha = 1
        if not client.known or not client.mayUse(button.speed) then
            -- pause can always be ended by whoever may not start one
            if not (button.speed == MTC.PAUSE and speed == MTC.PAUSE) then
                alpha = 0.35
            end
        elseif hover == button then
            alpha = 1
        elseif button.speed ~= speed then
            alpha = 0.85
        end
        if texture then
            self:drawTexture(texture, button.x, 0, alpha, 1, 1, 1)
        end
    end

    -- one line under the buttons: the button under the mouse, a refusal, or who changed the speed
    local now = getTimestampMs()
    local text = nil
    if hover then
        text = getText("UI_MTC_Speed" .. tostring(hover.speed))
    elseif client.note and now - client.noteAt < NOTE_MS then
        text = client.note
    elseif client.known and client.by and (speed ~= MTC.PLAY or now - client.changedAt < NOTE_MS) then
        if speed == MTC.PLAY and client.why then
            text = getText("UI_MTC_Why_" .. tostring(client.why), tostring(client.by))
        else
            text = getText("UI_MTC_By", getText("UI_MTC_Speed" .. tostring(speed)), tostring(client.by))
        end
    end
    if text then
        local font = UIFont.Small
        local w = getTextManager():MeasureStringX(font, text)
        local x = self.width - w
        local y = self.height + 4
        self:drawRect(x - 4, y - 1, w + 8, getTextManager():getFontHeight(font) + 2, 0.5, 0, 0, 0)
        self:drawText(text, x, y, 1, 1, 1, 1, font)
    end

    -- a pause stops everybody: say so in the middle of the screen
    if client.known and speed == MTC.PAUSE then
        local font = UIFont.Large
        local banner = client.by and getText("UI_MTC_PausedBy", tostring(client.by)) or getText("UI_MTC_Paused")
        local w = getTextManager():MeasureStringX(font, banner)
        local h = getTextManager():getFontHeight(font)
        local cx = getCore():getScreenWidth() / 2 - self.x
        local y = 60 - self.y
        self:drawRect(cx - w / 2 - 12, y - 6, w + 24, h + 12, 0.6, 0, 0, 0)
        self:drawText(banner, cx - w / 2, y, 1, 1, 1, 1, font)
    end
end

function MTCSpeedPanel:onMouseDown(x, y)
    local button = self:buttonAt(x, y)
    if not button then
        return false
    end
    local client = MTC.Client
    if not client.known then
        return true
    end
    local ok, reason = client.mayUse(button.speed)
    if not ok and not (button.speed == MTC.PAUSE and client.speed == MTC.PAUSE) then
        client.note = getText("UI_MTC_Refused_" .. tostring(reason))
        client.noteAt = getTimestampMs()
        return true
    end
    client.request(button.speed)
    return true
end

function MTCSpeedPanel:onMouseUp(x, y)
    return self:buttonAt(x, y) ~= nil
end

-- Make the buttons if this game has none yet.
function Panel.ensure()
    if Panel.instance then
        return Panel.instance
    end
    local panel = MTCSpeedPanel:new()
    panel:initialise()
    panel:addToUIManager()
    panel:place()
    Panel.instance = panel
    return panel
end

function Panel.remove()
    if Panel.instance then
        Panel.instance:removeFromUIManager()
        Panel.instance = nil
    end
end
