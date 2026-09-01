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
        Assert(string.find(snippet, "dui-option-key-9", 1, true),
            "combat state driver does not cover every numbered option")
        local confirmKey = owner:GetAttribute("dui-confirm-key")
        if confirmKey then owner:ClearBinding(confirmKey) end
        for i = 1, 9 do
            local optionKey = owner:GetAttribute("dui-option-key-"..i)
            if optionKey then owner:ClearBinding(optionKey) end
        end
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
        local index = string.match(action or "", "^Option([1-9])$")
        if index then return index end
    end,
    GetActiveKeyAction = function(_, key)
        if key == activeConfirmKey then return "Confirm" end
    end,
    LoadBindings = function() end,
}

local function TriggerCallbacks(event)
    for _, callback in ipairs(callbacks[event] or {}) do
        callback()
    end
end

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
confirm.type = "accept"
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

local option1 = NewFrame("Button", nil, parent)
option1.clicks = 0
function option1:OnClick(button)
    Assert(button == "GamePad", "numbered proxy did not preserve keyboard click semantics")
    self.clicks = self.clicks + 1
end
function option1:SetHotkey(key) self.hotkey = key end
function option1:Layout() self.layoutCalls = (self.layoutCalls or 0) + 1 end

local option2 = NewFrame("Button", nil, parent)
option2.clicks = 0
function option2:OnClick(button)
    Assert(button == "GamePad", "second numbered proxy used wrong click semantics")
    self.clicks = self.clicks + 1
end
function option2:SetHotkey(key) self.hotkey = key end
function option2:Layout() self.layoutCalls = (self.layoutCalls or 0) + 1 end

-- SetIndexedAction runs before DialogueUI assigns each pooled button's final
-- type.  The deferred refresh must validate that final type.
local initialOptionKey1 = control:SetIndexedAction(1, option1)
local initialOptionKey2 = control:SetIndexedAction(2, option2)
Assert(initialOptionKey1 == "1", "first numbered keycap was not reserved")
Assert(initialOptionKey2 == "2", "second numbered keycap was not reserved")
option1.type = "gossip"
option2.type = "availableQuest"
option1:SetHotkey(initialOptionKey1)
option2:SetHotkey(initialOptionKey2)
FlushTimers()
Assert(owner.bindings["1"] and owner.bindings["2"], "numbered choices were not acquired")
Assert(option1.hotkey == "1" and option2.hotkey == "2", "numbered keycaps were not shown")
Assert((option1.layoutCalls or 0) > 0 and (option2.layoutCalls or 0) > 0,
    "numbered keycaps did not relayout their option rows")

local optionProxy1 = frames[owner.bindings["1"].buttonName]
local optionProxy2 = frames[owner.bindings["2"].buttonName]
optionProxy2.scripts.OnClick(optionProxy2, "LeftButton")
Assert(option1.clicks == 0 and option2.clicks == 1,
    "numbered option proxy indices were aliased")
Assert(not owner.bindings["1"] and not owner.bindings["2"]
    and option1.hotkey == nil and option2.hotkey == nil,
    "a selected option left repeatable numbered bindings active")
optionProxy2.scripts.OnClick(optionProxy2, "LeftButton")
Assert(option2.clicks == 1, "a repeated numbered key selected the same page twice")

local reward1 = NewFrame("Button", nil, parent)
reward1.type = "choice"
reward1.index = 1
reward1.clicks = 0
function reward1:OnClick(button)
    Assert(button == "GamePad", "reward proxy did not preserve keyboard click semantics")
    self.clicks = self.clicks + 1
    parent.rewardChoiceID = self.index
    return true
end
function reward1:SetHotkey(key) self.hotkey = key end

local reward2 = NewFrame("Button", nil, parent)
reward2.type = "choice"
reward2.index = 2
reward2.clicks = 0
function reward2:OnClick(button)
    Assert(button == "GamePad", "second reward proxy used wrong click semantics")
    self.clicks = self.clicks + 1
    parent.rewardChoiceID = self.index
    return true
end
function reward2:SetHotkey(key) self.hotkey = key end

local rewardComplete = NewFrame("Button", nil, parent)
rewardComplete.type = "complete"
rewardComplete.clicks = 0
function rewardComplete:OnClick(button)
    Assert(button == "GamePad", "reward completion used wrong click semantics")
    self.clicks = self.clicks + 1
    return true
end
function rewardComplete:SetHotkey(key) self.hotkey = key end

control:ResetKeyActions()
parent.rewardChoiceID = nil
local rewardKey1 = control:SetIndexedAction(1, reward1)
local rewardKey2 = control:SetIndexedAction(2, reward2)
reward1:SetHotkey(rewardKey1)
reward2:SetHotkey(rewardKey2)
control:SetAction("Confirm", rewardComplete)
FlushTimers()
Assert(owner.bindings["1"] and owner.bindings["2"],
    "reward choices did not acquire numbered bindings")
Assert(reward1.hotkey == "1" and reward2.hotkey == "2",
    "reward choices did not show numbered keycaps")
local rewardProxy1 = frames[owner.bindings["1"].buttonName]
local rewardProxy2 = frames[owner.bindings["2"].buttonName]
rewardProxy1.scripts.OnClick(rewardProxy1, "LeftButton")
Assert(reward1.clicks == 1 and reward2.clicks == 0,
    "first reward binding selected the wrong reward")
control:RefreshLegacyBindings()
Assert(owner.bindings["1"] and owner.bindings["2"],
    "the Complete-button refresh consumed numbered reward bindings")
rewardProxy2.scripts.OnClick(rewardProxy2, "LeftButton")
Assert(reward1.clicks == 1 and reward2.clicks == 1,
    "reward bindings did not allow changing the selected reward")
Assert(parent.rewardChoiceID == 2 and rewardComplete.clicks == 0,
    "changing the numbered reward completed instead of selecting it")

SetCombat(true)
control:OnEvent("PLAYER_REGEN_DISABLED")
Assert(next(owner.bindings) == nil and reward1.hotkey == nil and reward2.hotkey == nil,
    "combat entry retained reward bindings or keycaps")
SetCombat(false)
control:OnEvent("PLAYER_REGEN_ENABLED")
Assert(owner.bindings["1"] and owner.bindings["2"]
    and reward1.hotkey == "1" and reward2.hotkey == "2",
    "combat exit did not safely restore reward bindings")

-- Combat clears the double-press arm. The first post-combat press selects and
-- arms again; only the following press of that same number may complete.
rewardProxy2.scripts.OnClick(rewardProxy2, "LeftButton")
Assert(rewardComplete.clicks == 0, "first post-combat reward press completed unexpectedly")
rewardProxy2.scripts.OnClick(rewardProxy2, "LeftButton")
Assert(rewardComplete.clicks == 1, "second press of the selected reward did not complete")
Assert(not owner.bindings["1"] and not owner.bindings["2"],
    "reward completion left repeatable numbered bindings active")
rewardProxy2.scripts.OnClick(rewardProxy2, "LeftButton")
Assert(rewardComplete.clicks == 1, "reward completion repeated during server latency")

-- A direct mouse click uses the same one-shot cleanup as Space/numbered
-- completion, so temporary overrides cannot survive while the server closes.
control:ResetKeyActions()
control:SetIndexedAction(1, reward1)
control:SetIndexedAction(2, reward2)
control:SetAction("Confirm", rewardComplete)
FlushTimers()
control:ConsumeLegacyCompleteBindings(rewardComplete)
Assert(not owner.bindings.SPACE and not owner.bindings["1"] and not owner.bindings["2"],
    "mouse completion left temporary dialogue bindings active")

control:ResetKeyActions()
Assert(reward1.hotkey == nil and reward2.hotkey == nil,
    "reward keycaps survived the reward page reset")
control:SetAction("Confirm", confirm)
control:SetIndexedAction(1, option1)
control:SetIndexedAction(2, option2)
FlushTimers()
optionProxy1 = frames[owner.bindings["1"].buttonName]
optionProxy1.scripts.OnClick(optionProxy1, "LeftButton")
Assert(option1.clicks == 1 and option2.clicks == 1,
    "first numbered option invoked the wrong choice")

control:SetIndexedAction(1, option1)
control:SetIndexedAction(2, option2)
FlushTimers()

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

option2.enabled = false
control:QueueLegacyBindingRefresh()
FlushTimers()
Assert(owner.bindings["1"] and not owner.bindings["2"],
    "disabled numbered choice retained its override")
Assert(option1.hotkey == "1" and option2.hotkey == nil,
    "disabled numbered choice retained its keycap")
option2.enabled = true
control:QueueLegacyBindingRefresh()
FlushTimers()
Assert(owner.bindings["2"] and option2.hotkey == "2",
    "re-enabled numbered choice did not restore its keycap")

local unsafe = NewFrame("Button", nil, parent)
unsafe.type = "complete"
function unsafe:OnClick() error("unsafe indexed button must not execute") end
function unsafe:SetHotkey(key) self.hotkey = key end
function unsafe:Layout() self.layoutCalls = (self.layoutCalls or 0) + 1 end
Assert(control:SetIndexedAction(0, unsafe) == nil, "index zero was accepted")
Assert(control:SetIndexedAction(-1, unsafe) == nil, "negative index was accepted")
Assert(control:SetIndexedAction(1.5, unsafe) == nil, "fractional index was accepted")
Assert(control:SetIndexedAction("3", unsafe) == nil, "string index was accepted")
Assert(control:SetIndexedAction(10, unsafe) == nil, "choice ten was accepted")
local unsafeKey = control:SetIndexedAction(3, unsafe)
unsafe:SetHotkey(unsafeKey)
FlushTimers()
Assert(not owner.bindings["3"] and unsafe.hotkey == nil,
    "unsafe option type acquired a numbered binding")

addon.SettingsUI:Show()
TriggerCallbacks("SettingsUI.Show")
Assert(owner.bindings.ESCAPE and not owner.bindings.SPACE
    and not owner.bindings["1"] and not owner.bindings["2"],
    "settings overlay did not suspend Confirm and numbered choices")
Assert(confirm.hotkey == nil and option1.hotkey == nil and option2.hotkey == nil,
    "settings overlay retained unavailable keycaps")
addon.SettingsUI:Hide()
TriggerCallbacks("SettingsUI.Hide")
Assert(owner.bindings.SPACE and owner.bindings["1"] and owner.bindings["2"],
    "closing settings did not restore scoped dialogue bindings")

addon.Clipboard:Show()
TriggerCallbacks("Clipboard.Show")
Assert(owner.bindings.ESCAPE and not owner.bindings["1"],
    "clipboard overlay did not suspend numbered choices")
addon.Clipboard:Hide()
TriggerCallbacks("Clipboard.Hide")
Assert(owner.bindings["1"] and owner.bindings["2"],
    "closing clipboard did not restore numbered choices")

parent.inputboxShown = true
control:RefreshLegacyBindings()
Assert(owner.bindings.ESCAPE and not owner.bindings.SPACE and not owner.bindings["1"],
    "gossip input box did not suspend unsafe dialogue actions")
parent.inputboxShown = nil
control:RefreshLegacyBindings()
Assert(owner.bindings.SPACE and owner.bindings["1"] and owner.bindings["2"],
    "closing gossip input box did not restore dialogue actions")

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

control:SetIndexedAction(1, option1)
control:SetIndexedAction(2, option2)
FlushTimers()
Assert(owner.bindings.G and owner.bindings["1"] and owner.bindings["2"],
    "Confirm, Escape, and numbered choices did not coexist")

activeConfirmKey = "1"
control:RefreshLegacyBindings()
Assert(owner.bindings["1"] and confirm.hotkey == "1",
    "numeric Confirm key did not keep priority")
Assert(option1.hotkey == nil and owner.bindings["2"] and option2.hotkey == "2",
    "numbered choice stole a conflicting Confirm key")
activeConfirmKey = "G"
control:RefreshLegacyBindings()

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
Assert(option1.hotkey == nil and option2.hotkey == nil,
    "combat entry retained numbered keycaps")

SetCombat(false)
control:OnEvent("PLAYER_REGEN_ENABLED")
Assert(owner.bindings.G and owner.bindings.ESCAPE, "bindings were not safely restored after combat")
Assert(confirm.hotkey == "G", "combat exit did not restore the Confirm label")
Assert(owner.bindings["1"] and owner.bindings["2"]
    and option1.hotkey == "1" and option2.hotkey == "2",
    "combat exit did not restore numbered choices")

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

parent.handler = "HandleGossip"
control:OnEvent("QUEST_FINISHED")
Assert(owner.bindings.G and owner.bindings["1"] and owner.bindings["2"],
    "stale quest finish wiped a freshly rendered gossip page")
Assert(option1.hotkey == "1" and option2.hotkey == "2",
    "stale quest finish removed current gossip keycaps")
parent.handler = "HandleQuestGreeting"
control:OnEvent("QUEST_FINISHED")
Assert(owner.bindings["1"] and owner.bindings["2"],
    "stale quest finish wiped a freshly rendered quest-greeting page")
parent.handler = "HandleQuestComplete"
confirm.type = "complete"
control:RefreshLegacyBindings()
control:OnEvent("QUEST_FINISHED")
Assert(owner.bindings.G and confirm.hotkey == "G",
    "stale quest finish removed the current Complete-page binding or keycap")

parent.shown = false
control:OnHide()
Assert(next(owner.bindings) == nil, "dialogue hide did not release every binding")

print("Legacy keyboard binding harness: PASS")
