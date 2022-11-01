--------------------------------------------------------------------------------
-- ActionButtonMixin
-- Additional methods we define on action buttons
--------------------------------------------------------------------------------
local AddonName, Addon = ...
local ActionButtonMixin = {}

function ActionButtonMixin:SetActionOffsetInsecure(offset)
    if InCombatLockdown() then
        return
    end

    local oldActionId = self:GetAttribute('action')
    local newActionId = self:GetAttribute('index') + (offset or 0)

    if oldActionId ~= newActionId then
        self:SetAttribute('action', newActionId)
        self:UpdateState()
    end
end

function ActionButtonMixin:SetShowGridInsecure(showgrid, force)
    if InCombatLockdown() then
        return
    end

    showgrid = tonumber(showgrid) or 0

    if (self:GetAttribute("showgrid") ~= showgrid) or force then
        self:SetAttribute("showgrid", showgrid)
        self:UpdateShownInsecure()
    end
end

function ActionButtonMixin:UpdateShownInsecure()
    if InCombatLockdown() then
        return
    end

    local show = (self:GetAttribute("showgrid") > 0 or HasAction(self:GetAttribute("action")))
        and not self:GetAttribute("statehidden")

    self:SetShown(show)
end

-- configuration commands
function ActionButtonMixin:SetFlyoutDirection(direction)
    if InCombatLockdown() then
        return
    end

    self:SetAttribute("flyoutDirection", direction)
    self:UpdateFlyout()
end

function ActionButtonMixin:SetShowCountText(show)
    if show then
        self.Count:Show()
    else
        self.Count:Hide()
    end
end

function ActionButtonMixin:SetShowMacroText(show)
    if show then
        self.Name:Show()
    else
        self.Name:Hide()
    end
end

function ActionButtonMixin:SetShowEquippedItemBorders(show)
    if show then
        self.Border:SetParent(self)
    else
        self.Border:SetParent(Addon.ShadowUIParent)
    end
end

-- we hide cooldowns when action buttons are transparent
-- so that the sparks don't appear
function ActionButtonMixin:SetShowCooldowns(show)
    if show then
        if self.cooldown:GetParent() ~= self then
            self.cooldown:SetParent(self)
            ActionButton_UpdateCooldown(self)
        end
    else
        self.cooldown:SetParent(Addon.ShadowUIParent)
    end
end

-- in classic, blizzard action buttons don't use a mixin
-- so define some methods that we'd expect
if not Addon:IsBuild('retail') then
    ActionButtonMixin.HideGrid = ActionButton_HideGrid
    ActionButtonMixin.ShowGrid = ActionButton_ShowGrid
    ActionButtonMixin.Update = ActionButton_Update
    ActionButtonMixin.UpdateFlyout = ActionButton_UpdateFlyout
    ActionButtonMixin.UpdateState = ActionButton_UpdateState

    hooksecurefunc("ActionButton_UpdateHotkeys", Addon.BindableButton.UpdateHotkeys)
end

Addon.ActionButtonMixin = ActionButtonMixin


--------------------------------------------------------------------------------
-- ActionButtons - A pool of action buttons
--------------------------------------------------------------------------------

-- dragonflight hack: whenever a Dominos action button's action changes
-- set the action of the corresponding blizzard action button
-- this ensures that pressing a blizzard keybinding does the same thing as
-- clicking a Dominos button would
--
-- We want to not remap blizzard keybindings in dragonflight, so that we can
-- use some behaviors only available to blizzard action buttons, mainly cast on
-- key down and press and hold casting
local source_OnAttributeChanged = [[
    if name ~= "action" then return end

    local target = control:GetFrameRef("target")
    if target and target:GetAttribute(name) ~= value then
        target:SetAttribute(name, value)
    end
]]

local proxyActionButton

if Addon:IsBuild("retail") then
    proxyActionButton = function(button, target)
        if not target then return end

        button.commandName = target.commandName

        local proxy = CreateFrame('Frame', nil, nil, "SecureHandlerBaseTemplate")

        proxy:SetFrameRef("target", target)
        proxy:WrapScript(button, "OnAttributeChanged", source_OnAttributeChanged)
        proxy:Hide()

        hooksecurefunc(target, "SetButtonState", function(_, state)
            button:SetButtonStateBase(state)
        end)
    end
else
    proxyActionButton = function(button, target)
        if not target then return end

        if target.buttonType then
            button.commandName = target.buttonType .. (1 + (button.id - 1) % 12)
        else
            button.commandName = target:GetName():upper()
        end

        local proxy = CreateFrame('Frame', nil, nil, "SecureHandlerBaseTemplate")

        proxy:SetFrameRef("target", target)
        proxy:WrapScript(button, "OnAttributeChanged", source_OnAttributeChanged)
        proxy:Hide()

        hooksecurefunc(target, "SetButtonState", function(_, state)
            button:SetButtonState(state)
        end)
    end
end

local function createActionButton(id)
    local name = ('%sActionButton%d'):format(AddonName, id)

    local button = CreateFrame('CheckButton', name, nil, 'ActionBarButtonTemplate')

    button.id = id
    proxyActionButton(button, Addon.ActionButtonMap[id])

    return button
end

-- handle notifications from our parent bar about whate the action button
-- ID offset should be
local actionButton_OnUpdateOffset = [[
    local offset = message or 0
    local id = self:GetAttribute('index') + offset

    if self:GetAttribute('action') ~= id then
        self:SetAttribute('action', id)
        self:RunAttribute("UpdateShown")
        self:CallMethod('UpdateState')
    end
]]

local actionButton_OnUpdateShowGrid = [[
    local new = message or 0
    local old = self:GetAttribute("showgrid") or 0

    if old ~= new then
        self:SetAttribute("showgrid", new)
        self:RunAttribute("UpdateShown")
    end
]]

local actionButton_UpdateShown = [[
    local show = (self:GetAttribute("showgrid") > 0 or HasAction(self:GetAttribute("action")))
                 and not self:GetAttribute("statehidden")

    if show then
        self:Show(true)
    else
        self:Hide(true)
    end
]]

-- action button creation is deferred so that we can avoid creating buttons for
-- bars set to show less than the maximum
local ActionButtons = setmetatable({}, {
    -- index creates & initializes buttons as we need them
    __index = function(self, id)
        -- validate the ID of the button we're getting is within an
        -- our expected range
        id = tonumber(id) or 0
        if id < 1 then
            error(('Usage: %s.ActionButtons[>0]'):format(AddonName), 2)
        end

        local button = createActionButton(id)

        -- apply our extra action button methods
        Mixin(button, Addon.ActionButtonMixin)

        -- apply hooks for quick binding
        -- this must be done before we reset the button ID, as we use it
        -- to figure out the binding action for the button
        Addon.BindableButton:AddQuickBindingSupport(button)

        -- set a handler for updating the action from a parent frame
        button:SetAttribute('_childupdate-offset', actionButton_OnUpdateOffset)

        -- set a handler for updating showgrid status
        button:SetAttribute('_childupdate-showgrid', actionButton_OnUpdateShowGrid)

        button:SetAttribute("UpdateShown", actionButton_UpdateShown)

        -- reset the showgrid setting to default
        button:SetAttribute('showgrid', 0)

        button:Hide()

        -- enable mousewheel clicks
        button:EnableMouseWheel(true)

        rawset(self, id, button)
        return button
    end,

    -- newindex is set to block writes to prevent errors
    __newindex = function()
        error(('%s.ActionButtons does not support writes'):format(AddonName), 2)
    end
})

-- exports
Addon.ActionButtons = ActionButtons
