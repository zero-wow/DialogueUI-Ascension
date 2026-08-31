-- Focused regression harness for the stock-3.3.5 DialogueUI override bindings.
-- Usage: lua Tests/LegacyKeyboardBindingHarness.lua [addon root]

local addonRoot = (arg and arg[1]) or "."
local addonName = "DialogueUI-Ascension"

local function Assert(condition, message)
    if not condition then
        error(message, 2)
    end
end

local inCombat = false
local queued = {}
local frames = {}
local callbacks = {}
local enabledKeyboard = false

local Frame = {}
Frame.__index = Frame

function Frame:SetFrameStrata() end
function Frame:SetFixedFrameStrata() end
function Frame:RegisterForClicks() end
function Frame:SetParent(parent) self.parent = parent end
function Frame:GetName() return self.name end
function Frame:SetAttribute(key, value) self.attributes[key] = value end
function Frame:GetAttribute(key) return self.attributes[key] end
function Frame:SetScript(script, handler) self.scripts[script] = handler end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:EnableGamePadButton() end
function Frame:SetPropagateKeyboardInput() end
function Frame:ClearBinding(key) self.bindings[key] = nil end
function Frame:IsShown() return self.shown end
function Frame:IsVisible()
    return self.shown and (not self.parent or self.parent:IsVisible())
end
function Frame:IsEnabled() return self.enabled end
function Frame:EnableKeyboard(state)
    if state then enabledKeyboard = true end
end
function Frame:Show()
    local changed = not self.shown
    self.shown = true
    if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Frame:Hide()
    local changed = self.shown
    self.shown = false
    if changed and self.scripts.OnHide then self.scripts.OnHide(self) end
end

local function NewFrame(_, name, parent)
    local frame = setmetatable({
        name = name,
        parent = parent,
        shown = true,
        enabled = true,
        scripts = {},
        events = {},
        attributes = {},
        bindings = {},
    }, Frame)
    if name then
        frames[name] = frame
        _G[name] = frame
    end
    return frame
end

UIParent = NewFrame("Frame", "UIParent")
CreateFrame = NewFrame
InCombatLockdown = function() return inCombat end
IsModifierKeyDown = function() return false end
RegisterStateDriver = function(owner, state, condition)
    owner.stateDriver = {state, condition}
end
SetOverrideBindingClick = function(owner, priority, key, buttonName, mouseButton)
    Assert(not inCombat, "attempted to set a protected binding in combat")
    owner.bindings[key] = {buttonName = buttonName, mouseButton = mouseButton, priority = priority}
end
ClearOverrideBindings = function(owner)
    Assert(not inCombat, "attempted to clear protected bindings in combat")
    owner.bindings = {}
end

local function FlushTimers()
    local pending = queued
    queued = {}
    for i = 1, #pending do pending[i]() end
end

local function SetCombat(state)
    inCombat = state
    local owner = frames.DUIDialogLegacyKeyBindingOwner
    if state and owner then
        local snippet = owner:GetAttribute("_onstate-combat")
        Assert(type(snippet) == "string" and string.find(snippet, "ClearBinding", 1, true),
            "combat state driver does not clear bindings")
        local confirmKey = owner:GetAttribute("dui-confirm-key")
        if confirmKey then owner:ClearBinding(confirmKey) end
        owner:ClearBinding("ESCAPE")
    end
end

local addon = {
    IS_LEGACY_ASCENSION = true,
    Legacy = {
        CreateFrame = NewFrame,
        NativeCreateFrame = NewFrame,
        C_Timer = {After = function(_, callback) queued[#queued + 1] = callback end},
    },
    API = {},
    SecureButtonContainer = {IsActionKey = function() return false end},
    CallbackRegistry = {
        Register = function(_, event, callback)
            callbacks[event] = callbacks[event] or {}
            callbacks[event][#callbacks[event] + 1] = callback
        end,
    },
}

addon.Clipboard = NewFrame("Frame")
addon.Clipboard:Hide()
function addon.Clipboard:CloseIfShown()
    if self:IsShown() then self:Hide(); return true end
    return false
end
addon.SettingsUI = NewFrame("Frame")
addon.SettingsUI:Hide()
addon.BookUI = NewFrame("Frame")
addon.BookUI:Hide()

local activeConfirmKey = "SPACE"
addon.BindingUtil = {
    GetActiveActionKey = function(_, action)
        if action == "Confirm" then return activeConfirmKey end
    end,
    GetActiveKeyAction = function(_, key)
        if key == activeConfirmKey then return "Confirm" end
    end,
    LoadBindings = function() end,
}

local chunk = assert(loadfile(addonRoot.."\\Code\\Dialogue\\KeyboardControl.lua"))
chunk(addonName, addon)

local control = addon.KeyboardControl
local owner = frames.DUIDialogLegacyKeyBindingOwner
Assert(control and owner, "legacy binding controller was not created")
Assert(owner.stateDriver and owner.stateDriver[1] == "combat", "combat state driver was not registered")

local parent = NewFrame("Frame", "DUIQuestFrameHarness", UIParent)
parent.hideCalls = 0
function parent:HideUI(cancelPopupFirst, fromPressingKey)
    self.hideCalls = self.hideCalls + 1
    self.lastCancelPopupFirst = cancelPopupFirst
    self.lastFromPressingKey = fromPressingKey
end

local confirm = NewFrame("Button", nil, parent)
confirm.type = "complete"
confirm.clicks = 0
function confirm:OnClick(button)
    Assert(button == "GamePad", "Confirm proxy did not preserve keyboard click semantics")
    self.clicks = self.clicks + 1
end
function confirm:SetHotkey(key) self.hotkey = key end

control:SetParentFrame(parent)
control:SetAction("Confirm", confirm)
FlushTimers()
Assert(owner.bindings.SPACE, "Confirm key was not acquired")
Assert(owner.bindings.ESCAPE, "Escape key was not acquired")
Assert(confirm.hotkey == "SPACE", "active Confirm key was not shown on the footer button")
Assert(not enabledKeyboard, "legacy path enabled raw keyboard capture")

local confirmProxy = frames[owner.bindings.SPACE.buttonName]
confirmProxy.scripts.OnClick(confirmProxy, "LeftButton")
Assert(confirm.clicks == 1, "Confirm proxy did not invoke the active action")

confirm.enabled = false
control:QueueLegacyBindingRefresh()
FlushTimers()
Assert(not owner.bindings.SPACE and owner.bindings.ESCAPE,
    "disabled Confirm action retained its override")
Assert(confirm.hotkey == nil, "disabled Confirm action retained its visual hotkey")

confirm.enabled = true
control:QueueLegacyBindingRefresh()
FlushTimers()
Assert(owner.bindings.SPACE, "re-enabled Confirm action did not reacquire its override")
Assert(confirm.hotkey == "SPACE", "re-enabled Confirm action did not restore its visual hotkey")

local gossip = NewFrame("Button", nil, parent)
gossip.type = "gossip"
function gossip:OnClick() error("gossip action must not receive the quest Confirm override") end
control:ResetKeyActions()
control:SetAction("Confirm", gossip)
FlushTimers()
Assert(not owner.bindings.SPACE and owner.bindings.ESCAPE,
    "non-footer gossip action acquired the quest Confirm override")
control:ResetKeyActions()
control:SetAction("Confirm", confirm)
FlushTimers()

activeConfirmKey = "G"
control:RefreshLegacyBindings()
Assert(not owner.bindings.SPACE and owner.bindings.G,
    "changed Confirm key left its previous override behind")
Assert(confirm.hotkey == "G", "changed Confirm key did not update the footer label")

activeConfirmKey = "BUTTON1"
control:RefreshLegacyBindings()
Assert(not owner.bindings.BUTTON1 and owner.bindings.ESCAPE,
    "unsafe mouse Confirm key acquired a dialog-wide override")
Assert(confirm.hotkey == nil, "unsafe mouse Confirm key was advertised on the footer")
activeConfirmKey = "G"
control:RefreshLegacyBindings()

SetCombat(true)
control:OnEvent("PLAYER_REGEN_DISABLED")
Assert(next(owner.bindings) == nil, "combat state did not release dialogue bindings")
Assert(confirm.hotkey == nil, "combat entry retained the unavailable Confirm label")

SetCombat(false)
control:OnEvent("PLAYER_REGEN_ENABLED")
Assert(owner.bindings.G and owner.bindings.ESCAPE, "bindings were not safely restored after combat")
Assert(confirm.hotkey == "G", "combat exit did not restore the Confirm label")

local acknowledge = NewFrame("Button", nil, parent)
acknowledge.type = "closeAutoAccepted"
acknowledge.clicks = 0
function acknowledge:OnClick(button)
    Assert(button == "GamePad", "auto-accepted quest acknowledgement used wrong click semantics")
    self.clicks = self.clicks + 1
end
function acknowledge:SetHotkey(key) self.hotkey = key end
control:SetAction("Confirm", acknowledge, true)
FlushTimers()
Assert(owner.bindings.G, "auto-accepted quest acknowledgement did not acquire Confirm")
Assert(acknowledge.hotkey == "G", "auto-accepted quest acknowledgement did not show Confirm")

control:SetAction("Confirm", confirm, true)
FlushTimers()

local exitProxy = frames[owner.bindings.ESCAPE.buttonName]
exitProxy.scripts.OnClick(exitProxy, "LeftButton")
Assert(parent.hideCalls == 1 and parent.lastCancelPopupFirst and parent.lastFromPressingKey,
    "Escape proxy did not use the dialogue close path")

control:OnEvent("QUEST_FINISHED")
Assert(next(owner.bindings) == nil, "quest finish did not release every dialogue binding")

control:SetAction("Confirm", confirm, true)
FlushTimers()
Assert(owner.bindings.G and owner.bindings.ESCAPE, "new dialogue action did not resume bindings")

parent.shown = false
control:OnHide()
Assert(next(owner.bindings) == nil, "dialogue hide did not release every binding")

print("Legacy keyboard binding harness: PASS")
