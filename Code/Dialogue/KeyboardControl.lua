-- Press Key to select option


local _, addon = ...
local CreateFrame = addon.Legacy.CreateFrame or CreateFrame;
local C_Timer = addon.Legacy.C_Timer or C_Timer;
local API = addon.API;
local Clipboard = addon.Clipboard;
local SecureButtonContainer = addon.SecureButtonContainer;
local BindingUtil = addon.BindingUtil;
local NativeCreateFrame = addon.Legacy.NativeCreateFrame or CreateFrame;


local GAMEPAD_CONFIRM = "PAD1";
local GAMEPAD_CANCEL = "PAD2";
local GAMEPAD_ALT = "PAD4";
local IS_KBM = true;


local USE_CUSTOM_BINDINGS = false;

-- Custom Settings
local ENABLE_KEYCONTROL_IN_COMBAT = true;
local DISABLE_CONTROL_KEY = false;          --If true, pressing the key (Space) will not continue quest
local CYCLE_REWARD_ENABLED = false;         --Press Tab to cycle through choosable rewards
local TTS_ENABLED = false;
local TTS_HOTKEY_ENABLED = false;
local DEBUG_SHOW_GAMEPAD_BUTTON = false;    --[TEMP] Console user
------------------

local InCombatLockdown = InCombatLockdown;
local IsModifierKeyDown = IsModifierKeyDown;
local SetOverrideBindingClick = SetOverrideBindingClick;
local ClearOverrideBindings = ClearOverrideBindings;
local RegisterStateDriver = RegisterStateDriver;
local type = type;

local KeyboardControl = CreateFrame("Frame");
KeyboardControl:Hide();
KeyboardControl:SetFrameStrata("TOOLTIP");
KeyboardControl:SetFixedFrameStrata(true);
addon.KeyboardControl = KeyboardControl;


-- Wrath has no SetPropagateKeyboardInput, so enabling a raw OnKeyDown listener
-- can swallow every unhandled action-bar key.  The legacy client does support
-- override click bindings, however.  Keep those bindings on an isolated owner
-- and route only explicitly owned dialogue actions through stable proxy
-- buttons.  This restores the Retail-style numbered choice keys without ever
-- enabling a raw keyboard listener that could swallow action-bar input.
--
-- The secure combat state driver is important: protected bindings cannot be
-- changed from ordinary Lua after combat lockdown starts.  Its restricted
-- snippet clears this owner's bindings at the state transition, before they
-- could mask an action-bar key in combat.  No secure frame is parented to the
-- DialogueUI tree or to another addon's action buttons.
local LegacyBindingOwner;
local LegacyConfirmButton;
local LegacyExitButton;
local LegacyOptionButtons = {};

if addon.IS_LEGACY_ASCENSION
    and type(SetOverrideBindingClick) == "function"
    and type(ClearOverrideBindings) == "function"
    and type(RegisterStateDriver) == "function" then

    local ownerCreated, owner = pcall(
        NativeCreateFrame,
        "Frame",
        "DUIDialogLegacyKeyBindingOwner",
        UIParent,
        "SecureHandlerStateTemplate"
    );

    if ownerCreated and owner then
        local stateReady = pcall(function()
            owner:SetAttribute("_onstate-combat", [[
                if newstate == "combat" then
                    local confirmKey = self:GetAttribute("dui-confirm-key")
                    if confirmKey then
                        self:ClearBinding(confirmKey)
                    end
                    self:ClearBinding("ESCAPE")
                    local optionKey = self:GetAttribute("dui-option-key-1")
                    if optionKey then self:ClearBinding(optionKey) end
                    optionKey = self:GetAttribute("dui-option-key-2")
                    if optionKey then self:ClearBinding(optionKey) end
                    optionKey = self:GetAttribute("dui-option-key-3")
                    if optionKey then self:ClearBinding(optionKey) end
                    optionKey = self:GetAttribute("dui-option-key-4")
                    if optionKey then self:ClearBinding(optionKey) end
                    optionKey = self:GetAttribute("dui-option-key-5")
                    if optionKey then self:ClearBinding(optionKey) end
                    optionKey = self:GetAttribute("dui-option-key-6")
                    if optionKey then self:ClearBinding(optionKey) end
                    optionKey = self:GetAttribute("dui-option-key-7")
                    if optionKey then self:ClearBinding(optionKey) end
                    optionKey = self:GetAttribute("dui-option-key-8")
                    if optionKey then self:ClearBinding(optionKey) end
                    optionKey = self:GetAttribute("dui-option-key-9")
                    if optionKey then self:ClearBinding(optionKey) end
                end
            ]]);
            RegisterStateDriver(owner, "combat", "[combat] combat; nocombat");
        end);

        if stateReady then
            LegacyBindingOwner = owner;
            LegacyConfirmButton = NativeCreateFrame("Button", "DUIDialogLegacyConfirmKeyButton", UIParent);
            LegacyExitButton = NativeCreateFrame("Button", "DUIDialogLegacyExitKeyButton", UIParent);
            LegacyConfirmButton:Hide();
            LegacyExitButton:Hide();
            LegacyConfirmButton:RegisterForClicks("LeftButtonUp");
            LegacyExitButton:RegisterForClicks("LeftButtonUp");
            for i = 1, 9 do
                local index = i;
                local button = NativeCreateFrame(
                    "Button",
                    "DUIDialogLegacyOptionKeyButton"..index,
                    UIParent
                );
                button:Hide();
                button:RegisterForClicks("LeftButtonUp");
                LegacyOptionButtons[index] = button;
            end
        end
    end
end
KeyboardControl.legacyBindingOwnerAvailable = LegacyBindingOwner ~= nil;

KeyboardControl.combatFrame = CreateFrame("Frame", nil, KeyboardControl, "DUISetPropagateKeyboardInputTemplate");   --"combatFrame" doesn't change KeyProgation dynamically based on input
--KeyboardControl.combatFrame:SetPropagateKeyboardInput(true);

function KeyboardControl:ResetKeyActions()
    if addon.IS_LEGACY_ASCENSION and self.UpdateLegacyConfirmHotkey then
        self:UpdateLegacyConfirmHotkey(nil);
        self:UpdateLegacyOptionHotkeys();
        self.legacyOptionCandidates = {};
        self.legacyRewardChoiceArm = nil;
    end
    self.keyActions = {};
    self.actions = {};
    if addon.IS_LEGACY_ASCENSION and self.RefreshLegacyBindings then
        self:RefreshLegacyBindings();
    end
end
KeyboardControl:ResetKeyActions()

function KeyboardControl:CanSetKey(key)
    if key then
        if type(key) == "number" then
            return key <= 9
        else
            return true
        end
    end
    return false
end

--[[
function KeyboardControl:SetKeyFunction(key, func, override)
    if not self:CanSetKey(key) then return end;

    key = tostring(key);

    if (not self.keyActions[key]) or override then
        self.keyActions[key] = {
            obj = func,
            type = "function",
        };
        return key
    end
end

function KeyboardControl:SetKeyButton(key, buttonToClick, override)
    if key == "PRIMARY" then
        key = PRIMARY_CONTROL_KEY;
    end

    if not self:CanSetKey(key) then return end;

    key = tostring(key)

    if (not self.keyActions[key]) or override then
        self.keyActions[key] = {
            obj = buttonToClick,
            type = "button",
        };
        return key
    end
end
--]]

function KeyboardControl:SetAction(action, buttonToClick, override)
    if (not self.actions[action]) or override then
        if addon.IS_LEGACY_ASCENSION then
            self.legacyBindingSuspended = nil;
        end
        self.actions[action] = {
            obj = buttonToClick,
            type = "button",
        };
        if addon.IS_LEGACY_ASCENSION then
            self:QueueLegacyBindingRefresh();
            if action == "Confirm" then
                return BindingUtil:GetActiveActionKey(action)
            end
            return nil
        end
        return BindingUtil:GetActiveActionKey(action)
    end
end

function KeyboardControl:SetIndexedAction(buttonIndex, buttonToClick, override)
    if type(buttonIndex) == "number"
        and buttonIndex >= 1
        and buttonIndex <= 9
        and buttonIndex % 1 == 0 then
        if addon.IS_LEGACY_ASCENSION then
            local action = "Option"..buttonIndex;
            self.legacyOptionCandidates = self.legacyOptionCandidates or {};
            self.legacyOptionCandidates[buttonIndex] = buttonToClick;
            self:SetAction(action, buttonToClick, override);
            -- Custom bindings are disabled on legacy, so these are guaranteed
            -- to be the visible 1-9 keys.  Return the key now so initial layout
            -- reserves the full keycap height; the queued refresh validates
            -- the final button type and removes it if the override fails.
            if LegacyBindingOwner then
                return tostring(buttonIndex)
            end
            return nil
        end
        if buttonIndex == 1 then
            self:SetAction("Confirm", buttonToClick, override);
        end
        local action = "Option"..buttonIndex;
        return self:SetAction(action, buttonToClick, override)
    end
end


local function IsVisibleAndEnabled(object)
    if not object or type(object.OnClick) ~= "function" then
        return false
    end
    if object.IsEnabled and not object:IsEnabled() then
        return false
    end
    if object.IsVisible then
        return object:IsVisible()
    end
    return object.IsShown and object:IsShown()
end

local LegacyConfirmButtonTypes = {
    accept = true,
    continue = true,
    complete = true,
    closeAutoAccepted = true,
};

local LegacyOptionButtonTypes = {
    gossip = true,
    availableQuest = true,
    activeQuest = true,
    choice = true,
};

local function IsLegacyQuestConfirmButton(object)
    return object and LegacyConfirmButtonTypes[object.type] == true
end

local function IsLegacyOptionButton(object)
    return object and LegacyOptionButtonTypes[object.type] == true
end

local function IsSafeLegacyConfirmKey(key)
    if type(key) ~= "string" or key == "" or key == "ESCAPE" then
        return false
    end
    if BindingUtil.IsKeyInvalid and BindingUtil:IsKeyInvalid(key) then
        return false
    end
    -- An Interact binding can technically be assigned to a mouse button.  A
    -- dialog-wide mouse override would turn ordinary clicks into quest accepts.
    return string.sub(key, 1, 6) ~= "BUTTON"
        and string.sub(key, 1, 10) ~= "MOUSEWHEEL"
end

function KeyboardControl:UpdateLegacyConfirmHotkey(object, key)
    local previous = self.legacyConfirmObject;
    self.legacyConfirmObject = object;
    self.updatingLegacyHotkey = true;
    if previous and previous ~= object and previous.SetHotkey then
        previous:SetHotkey(nil);
        if previous.Layout then previous:Layout(true); end
    end
    if object and object.SetHotkey then
        object:SetHotkey(key);
        if object.Layout then object:Layout(true); end
    end
    self.updatingLegacyHotkey = nil;
end

local function LayoutLegacyOptionButton(object, hasHotkey)
    if object and object.Layout then
        -- The keycap is taller than a compact gossip row.  Use the regular
        -- option padding so its textured border is never clipped.
        object:Layout(hasHotkey or object.type ~= "gossip");
    end
end

function KeyboardControl:UpdateLegacyOptionHotkeys(boundOptions)
    local previous = self.legacyOptionObjects or {};
    local candidates = self.legacyOptionCandidates or {};
    local current = {};
    boundOptions = boundOptions or {};

    self.updatingLegacyHotkey = true;
    for i = 1, 9 do
        local previousObject = previous[i];
        local candidateObject = candidates[i];
        local data = boundOptions[i];
        local newObject = data and data.object;

        if previousObject and previousObject ~= newObject and previousObject.SetHotkey then
            previousObject:SetHotkey(nil);
            LayoutLegacyOptionButton(previousObject, false);
        end
        if candidateObject
            and candidateObject ~= newObject
            and candidateObject ~= previousObject
            and candidateObject.SetHotkey then
            candidateObject:SetHotkey(nil);
            LayoutLegacyOptionButton(candidateObject, false);
        end

        if newObject and newObject.SetHotkey then
            newObject:SetHotkey(data.key);
            LayoutLegacyOptionButton(newObject, true);
            current[i] = newObject;
        end

        if not (self.actions and self.actions["Option"..i]) then
            candidates[i] = nil;
        end
    end
    self.updatingLegacyHotkey = nil;
    self.legacyOptionObjects = current;
    self.legacyOptionCandidates = candidates;
end

function KeyboardControl:HasLegacyBlockingOverlay()
    return (Clipboard and Clipboard.IsShown and Clipboard:IsShown())
        or (addon.SettingsUI and addon.SettingsUI:IsShown())
        or (addon.BookUI and addon.BookUI:IsShown())
        or (self.parent and self.parent.inputboxShown)
end

function KeyboardControl:CanUseLegacyBindings()
    local parent = self.parent;
    return LegacyBindingOwner
        and parent
        and parent.IsShown
        and parent:IsShown()
        and not self.legacyBindingSuspended
        and not InCombatLockdown()
end

function KeyboardControl:ClearLegacyBindings()
    self.legacyBindingActive = nil;

    if not LegacyBindingOwner then
        return false
    end

    -- The combat state driver has already performed this operation inside the
    -- restricted environment when lockdown is active.
    if InCombatLockdown() then
        return true
    end

    local cleared = pcall(ClearOverrideBindings, LegacyBindingOwner);
    if cleared then
        LegacyBindingOwner:SetAttribute("dui-confirm-key", nil);
        for i = 1, 9 do
            LegacyBindingOwner:SetAttribute("dui-option-key-"..i, nil);
        end
    end
    return cleared
end


function KeyboardControl:RefreshLegacyBindings()
    if not addon.IS_LEGACY_ASCENSION or not LegacyBindingOwner then
        return
    end

    if not self:CanUseLegacyBindings() then
        self:UpdateLegacyConfirmHotkey(nil);
        self:UpdateLegacyOptionHotkeys();
        self:ClearLegacyBindings();
        return
    end

    -- Rebuild from scratch so a changed/disabled Confirm key never leaves its
    -- previous override behind.
    if not self:ClearLegacyBindings() then
        self:UpdateLegacyConfirmHotkey(nil);
        self:UpdateLegacyOptionHotkeys();
        return
    end

    local anyBinding;
    local boundKeys = {};
    local blockingOverlay = self:HasLegacyBlockingOverlay();
    if blockingOverlay then
        self.legacyRewardChoiceArm = nil;
    end
    local confirmBound;
    local confirmAction = self.actions and self.actions.Confirm;
    local confirmKey = confirmAction and BindingUtil:GetActiveActionKey("Confirm");
    if not blockingOverlay
        and IsSafeLegacyConfirmKey(confirmKey)
        and confirmAction.type == "button"
        and IsLegacyQuestConfirmButton(confirmAction.obj)
        and IsVisibleAndEnabled(confirmAction.obj) then
        confirmBound = pcall(
            SetOverrideBindingClick,
            LegacyBindingOwner,
            true,
            confirmKey,
            LegacyConfirmButton:GetName(),
            "LeftButton"
        );
        if confirmBound then
            LegacyBindingOwner:SetAttribute("dui-confirm-key", confirmKey);
            boundKeys[confirmKey] = true;
        end
        anyBinding = confirmBound or anyBinding;
    end

    self:UpdateLegacyConfirmHotkey(
        confirmAction and confirmAction.obj or nil,
        confirmBound and confirmKey or nil
    );

    local boundOptions = {};
    for i = 1, 9 do
        local actionName = "Option"..i;
        local optionAction = self.actions and self.actions[actionName];
        local optionObject = optionAction and optionAction.obj;
        local optionKey = optionAction and BindingUtil:GetActiveActionKey(actionName);

        if not blockingOverlay
            and IsSafeLegacyConfirmKey(optionKey)
            and not boundKeys[optionKey]
            and optionAction.type == "button"
            and IsLegacyOptionButton(optionObject)
            and IsVisibleAndEnabled(optionObject)
            and LegacyOptionButtons[i] then
            local optionBound = pcall(
                SetOverrideBindingClick,
                LegacyBindingOwner,
                true,
                optionKey,
                LegacyOptionButtons[i]:GetName(),
                "LeftButton"
            );
            if optionBound then
                LegacyBindingOwner:SetAttribute("dui-option-key-"..i, optionKey);
                boundOptions[i] = {object = optionObject, key = optionKey};
                boundKeys[optionKey] = true;
                anyBinding = true;
            end
        end
    end
    self:UpdateLegacyOptionHotkeys(boundOptions);

    local escapeBound = pcall(
        SetOverrideBindingClick,
        LegacyBindingOwner,
        true,
        "ESCAPE",
        LegacyExitButton:GetName(),
        "LeftButton"
    );
    anyBinding = escapeBound or anyBinding;
    self.legacyBindingActive = anyBinding or nil;
end


function KeyboardControl:QueueLegacyBindingRefresh()
    if not addon.IS_LEGACY_ASCENSION or self.legacyRefreshPending then
        return
    end

    self.legacyRefreshPending = true;
    C_Timer.After(0, function()
        self.legacyRefreshPending = nil;
        self:RefreshLegacyBindings();
    end);
end


function KeyboardControl:SuspendLegacyBindings()
    self.legacyBindingSuspended = true;
    self.legacyRewardChoiceArm = nil;
    self:UpdateLegacyConfirmHotkey(nil);
    self:UpdateLegacyOptionHotkeys();
    self.keyActions = {};
    self.actions = {};
    self:ClearLegacyBindings();
end


function KeyboardControl:ConsumeLegacyCompleteBindings(object)
    if not addon.IS_LEGACY_ASCENSION or (object and object.type ~= "complete") then
        return
    end

    -- Completion is one-shot while the server advances the quest.  Centralize
    -- the cleanup so keyboard, reward-number, and mouse clicks all release the
    -- same temporary overrides before GetQuestReward can run.
    if self.actions then
        self.actions.Confirm = nil;
        for i = 1, 9 do
            self.actions["Option"..i] = nil;
        end
    end
    self.legacyRewardChoiceArm = nil;
    self:RefreshLegacyBindings();
end


function KeyboardControl:ExecuteLegacyOption(index)
    if not self:CanUseLegacyBindings() then
        return
    end
    if self:HasLegacyBlockingOverlay() then
        return
    end

    local action = self.actions and self.actions["Option"..index];
    local object = action and action.obj;
    if action
        and action.type == "button"
        and IsLegacyOptionButton(object)
        and IsVisibleAndEnabled(object) then
        if object.type == "choice" then
            local arm = self.legacyRewardChoiceArm;
            local confirmAction = self.actions and self.actions.Confirm;
            local confirmObject = confirmAction and confirmAction.obj;
            local sameNumberedChoice = arm
                and arm.index == index
                and arm.object == object
                and self.parent
                and self.parent.rewardChoiceID == object.index;

            if sameNumberedChoice
                and confirmAction
                and confirmAction.type == "button"
                and confirmObject
                and confirmObject.type == "complete"
                and IsVisibleAndEnabled(confirmObject) then
                self.legacyRewardChoiceArm = nil;
                self:ExecuteLegacyConfirm();
                return
            end

            -- A reward number must first select and visibly arm that exact
            -- choice. Only a later press of the same number may complete it;
            -- mouse or automatic selection never makes the first press claim.
            self.legacyRewardChoiceArm = {index = index, object = object};
        else
            self.legacyRewardChoiceArm = nil;
            -- Gossip and quest-list choices replace the current page.  Consume
            -- their numbered set before selecting so a held/repeated key cannot
            -- choose again while the server is rebuilding the interaction.
            for i = 1, 9 do
                self.actions["Option"..i] = nil;
            end
            self:RefreshLegacyBindings();
        end
        local noFeedback = object:OnClick("GamePad");
        if (not noFeedback) and object.PlayKeyFeedback then
            object:PlayKeyFeedback();
        end
    end
end


function KeyboardControl:ExecuteLegacyConfirm()
    if not self:CanUseLegacyBindings() then
        return
    end

    -- Do not complete an obscured quest while the user is interacting with a
    -- modal/editing surface layered over the dialogue.
    if self:HasLegacyBlockingOverlay() then
        return
    end

    local action = self.actions and self.actions.Confirm;
    local object = action and action.obj;
    if action
        and action.type == "button"
        and IsLegacyQuestConfirmButton(object)
        and IsVisibleAndEnabled(object) then
        if object.type == "complete" then
            self:ConsumeLegacyCompleteBindings(object);
        end
        local noFeedback = object:OnClick("GamePad");
        if (not noFeedback) and object.PlayKeyFeedback then
            object:PlayKeyFeedback();
        end
    end
end


function KeyboardControl:ExecuteLegacyExit()
    if not self:CanUseLegacyBindings() then
        return
    end

    if Clipboard and Clipboard.CloseIfShown and Clipboard:CloseIfShown() then
        return
    elseif addon.SettingsUI and addon.SettingsUI:IsShown() then
        addon.SettingsUI:Hide();
        return
    elseif addon.BookUI and addon.BookUI:IsShown() then
        addon.BookUI:Hide();
        return
    elseif self.parent and self.parent.inputboxShown and self.parent.HideInputBox then
        self.parent:HideInputBox();
        return
    end

    local parent = self.parent;
    if parent and parent.HideUI then
        local cancelPopupFirst = true;
        local fromPressingKey = true;
        parent:HideUI(cancelPopupFirst, fromPressingKey);
    elseif parent then
        parent:Hide();
    end
end


if LegacyConfirmButton and LegacyExitButton then
    LegacyConfirmButton:SetScript("OnClick", function()
        KeyboardControl:ExecuteLegacyConfirm();
    end);
    LegacyExitButton:SetScript("OnClick", function()
        KeyboardControl:ExecuteLegacyExit();
    end);
    for i = 1, 9 do
        local index = i;
        local button = LegacyOptionButtons[index];
        if button then
            button:SetScript("OnClick", function()
                KeyboardControl:ExecuteLegacyOption(index);
            end);
        end
    end
end

function KeyboardControl:OnEvent(event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        self:RegisterEvent("PLAYER_REGEN_ENABLED");
        if addon.IS_LEGACY_ASCENSION then
            -- The secure state driver clears the actual overrides.  Only reset
            -- insecure bookkeeping here; protected APIs are forbidden now.
            self.legacyBindingActive = nil;
            self.legacyRewardChoiceArm = nil;
            self:UpdateLegacyConfirmHotkey(nil);
            self:UpdateLegacyOptionHotkeys();
            return
        end
        self:UpdateParentForCombat(true);
        --self:SetPropagateKeyboardInput(true);
    elseif event == "PLAYER_REGEN_ENABLED" then
        if addon.IS_LEGACY_ASCENSION then
            self:RefreshLegacyBindings();
            return
        end
        if self:IsVisible() then
            self:UpdateParentForCombat();
        end
    elseif event == "UPDATE_BINDINGS" then
        if addon.IS_LEGACY_ASCENSION and self:IsVisible() then
            BindingUtil:LoadBindings();
            self:RefreshLegacyBindings();
        else
            self.bindingDirty = true;
        end
    elseif addon.IS_LEGACY_ASCENSION and event == "PLAYER_LEAVING_WORLD" then
        self:SuspendLegacyBindings();
    end
end
KeyboardControl:SetScript("OnEvent", KeyboardControl.OnEvent);

function KeyboardControl:OnHide()
    if addon.IS_LEGACY_ASCENSION then
        self.legacyBindingSuspended = true;
    end
    self:StopListeningKeys();
    self:UnregisterEvent("PLAYER_REGEN_DISABLED");
    self:UnregisterEvent("PLAYER_REGEN_ENABLED");
    if addon.IS_LEGACY_ASCENSION then
        self:UnregisterEvent("PLAYER_LEAVING_WORLD");
    end
    self:ResetKeyActions();
    self:StopRepeatingAction();
end
KeyboardControl:SetScript("OnHide", KeyboardControl.OnHide);

function KeyboardControl:OnShow()
    self:RegisterEvent("PLAYER_REGEN_DISABLED");

    if addon.IS_LEGACY_ASCENSION then
        self:RegisterEvent("PLAYER_REGEN_ENABLED");
        self:RegisterEvent("PLAYER_LEAVING_WORLD");
    end

    if self.bindingDirty then
        self.bindingDirty = nil;
        BindingUtil:LoadBindings();
    end

    if addon.IS_LEGACY_ASCENSION then
        self:RefreshLegacyBindings();
    end
end

KeyboardControl:SetScript("OnShow", KeyboardControl.OnShow);

function KeyboardControl:OnKeyDown(key, fromGamePad)
    local inCombat = InCombatLockdown();

    if SecureButtonContainer:IsActionKey(key) and not inCombat then
        KeyboardControl:SetPropagateKeyboardInput(true);
        return
    end

    local valid = false;
    local processed = false;
    local action;

    if key == "ESCAPE" then
        action = "Exit";
    end

    if key == GAMEPAD_CONFIRM then
        valid = KeyboardControl.parent:ClickFocusedObject();
        if valid then
            processed = true;
            action = nil;
        else
            action = "Confirm";
        end
    end

    if (not processed) and (not action) then
        action = BindingUtil:GetActiveKeyAction(key);
    end

    if action == "Exit" then
        valid = true;

        if Clipboard:CloseIfShown() then
            processed = true;
        elseif addon.SettingsUI:IsShown() then
            addon.SettingsUI:Hide();
            processed = true;
        elseif addon.BookUI:IsShown() then
            addon.BookUI:Hide();
            processed = true;
        else
            if fromGamePad then

            else
                if KeyboardControl.parent.HideUI then
                    local cancelPopupFirst = true;
                    local fromPressingKey = true;
                    KeyboardControl.parent:HideUI(cancelPopupFirst, fromPressingKey);
                    processed = true;
                else
                    KeyboardControl.parent:Hide();
                    processed = true;
                end
            end
        end
    elseif key == "GAMEPAD_UP" then
        valid = true;
        processed = true;
        KeyboardControl.parent:FocusPreviousObject();
    elseif key == "GAMEPAD_DOWN" then
        valid = true;
        processed = true;
        KeyboardControl.parent:FocusNextObject();
    elseif action == "Settings" or key == "SETTINGS" then
        valid = true;
        processed = true;
        addon.SettingsUI:ToggleUI();
    elseif action == "TTS" and not IsModifierKeyDown() then
        if TTS_ENABLED and TTS_HOTKEY_ENABLED then
            valid = true;
            processed = true;
            addon.TTSUtil:ToggleSpeaking();
        end
    elseif (CYCLE_REWARD_ENABLED and IS_KBM) and key == "TAB" and not inCombat then
        local delta = IsModifierKeyDown() and -1 or 1;
        if addon.DialogueUI:CycleRewardChoice(delta) then
            valid = true;
        end
    end

    if action == "Confirm" and DISABLE_CONTROL_KEY and not USE_CUSTOM_BINDINGS then
        processed = true;
        valid = false;
    end

    if (not processed) and action and KeyboardControl.actions[action] then
        valid = true;

        local actionType = KeyboardControl.actions[action].type;
        local object = KeyboardControl.actions[action].obj;

        if actionType == "function" then
            object();
        elseif actionType == "button" then
            if object:IsEnabled() and object:IsVisible() then
                local noFeedback = object:OnClick("GamePad");
                if (not noFeedback) and object.PlayKeyFeedback then
                    object:PlayKeyFeedback();
                end
            end
        end
    end

    if not inCombat then
        KeyboardControl:SetPropagateKeyboardInput(not valid);
    end
end

function KeyboardControl:SetParentFrame(frame, inCombat)
    self.parent = frame;
    self:SetParent(frame);
    self:Show();

    self:StopListeningKeys();

    -- Retail can return unhandled keys to normal bindings with
    -- SetPropagateKeyboardInput. That API does not exist on 3.3.5, so a raw
    -- OnKeyDown listener can block spell and action-bar bindings. Keep the
    -- dialogue fully mouse-operable and never take keyboard focus on legacy.
    if addon.IS_LEGACY_ASCENSION then
        self:RefreshLegacyBindings();
        return
    end

    local listener;

    if inCombat or InCombatLockdown() then
        if ENABLE_KEYCONTROL_IN_COMBAT then
            listener = self.combatFrame;
        end
    else
        listener = self;
    end

    if listener then
        listener:SetScript("OnKeyDown", self.OnKeyDown);
        if not addon.IS_LEGACY_ASCENSION then
            listener:SetScript("OnGamePadButtonDown", self.OnGamePadButtonDown);
            listener:SetScript("OnGamePadButtonUp", self.OnGamePadButtonUp)
            listener:EnableGamePadButton(true);
        end
        listener:EnableKeyboard(true);
    end
end

function KeyboardControl:StopListeningKeys()
    self:SetScript("OnKeyDown", nil);
    self.combatFrame:SetScript("OnKeyDown", nil);

    if not addon.IS_LEGACY_ASCENSION then
        self:SetScript("OnGamePadButtonDown", nil);
        self.combatFrame:SetScript("OnGamePadButtonDown", nil);
        self:SetScript("OnGamePadButtonUp", nil);
        self.combatFrame:SetScript("OnGamePadButtonUp", nil);

        self:EnableGamePadButton(false);
        self.combatFrame:EnableGamePadButton(false);
    end

    self:EnableKeyboard(false);
    self.combatFrame:EnableKeyboard(false);
end

function KeyboardControl:UpdateParentForCombat(inCombat)
    if self.parent and self.parent:IsVisible() then
        self:SetParentFrame(self.parent, inCombat);
    end
end


do  --GamePad/Controller
    local KeyRemap = {
        PAD2 = "ESCAPE",
        PADDUP = "GAMEPAD_UP",
        PADDDOWN = "GAMEPAD_DOWN",
        PADFORWARD = "SETTINGS",  --Toggle Settings
        PADMENU = "SETTINGS",
        PADBACK = "ESCAPE",
        PADDLEFT = "GAMEPAD_UP",
        PADDRIGHT = "GAMEPAD_DOWN",
    };

    local RepeatableButton = {
        PADDUP = true,
        PADDDOWN = true,
        PADDLEFT = true,
        PADDRIGHT = true,
    };

    local REPEAT_INTERVAL = 0.125;

    function KeyboardControl:OnGamePadButtonDown(button)
        KeyboardControl:StopRepeatingAction();

        if addon.HelpTip:CloseAll() then
            return
        end

        local inCombat = InCombatLockdown();
        if SecureButtonContainer:IsActionKey(button) and not inCombat then
            KeyboardControl:SetPropagateKeyboardInput(true);
            return
        end

        if button == "PADRTRIGGER" then --Debug Console
            DEBUG_SHOW_GAMEPAD_BUTTON = not DEBUG_SHOW_GAMEPAD_BUTTON;
            if DEBUG_SHOW_GAMEPAD_BUTTON then
                addon.DevTool:PrintText("|cffffd100Display Pressed Buttons|r");
            else
                addon.DevTool:PrintText("|cffffd100No Longer Display Pressed Buttons|r");
            end
            if not inCombat then
                KeyboardControl:SetPropagateKeyboardInput(false);
            end
            return
        end

        if button == "PADLTRIGGER" then
            if TTS_HOTKEY_ENABLED then
                addon.TTSUtil:ToggleSpeaking();
                if not inCombat then
                    KeyboardControl:SetPropagateKeyboardInput(false);
                end
                return
            end
        end

        if DEBUG_SHOW_GAMEPAD_BUTTON then
            addon.DevTool:PrintText(button);
        end

        if button == GAMEPAD_CONFIRM then

        elseif button == GAMEPAD_ALT then
            local TooltipFrame = addon.SharedTooltip;
            if TooltipFrame and TooltipFrame:IsShown() then
                TooltipFrame:ToggleAlternateInfo();
            end
        else
            if RepeatableButton[button] then
                KeyboardControl:RepeatAction(KeyRemap[button]);
            end
            button = KeyRemap[button];
        end

        if button then
            KeyboardControl:OnKeyDown(button, true);
        end
    end

    function KeyboardControl:OnGamePadButtonUp(button)
        KeyboardControl:StopRepeatingAction();
    end

    local function RepeatGamePadButton_OnUpdate(self, elapsed)
        self.repeatElapsed = self.repeatElapsed + elapsed;
        if self.repeatElapsed >= REPEAT_INTERVAL then
            self.repeatElapsed = 0;
            if self.repeatButton then
                KeyboardControl:OnKeyDown(self.repeatButton, true);
            else
                self:StopRepeatingAction();
            end
        end
    end

    function KeyboardControl:RepeatAction(button)
        self.repeatElapsed = -0.375;
        self.repeatButton = button;
        self:SetScript("OnUpdate", RepeatGamePadButton_OnUpdate);
    end

    function KeyboardControl:StopRepeatingAction()
        self:SetScript("OnUpdate", nil);
        self.repeatElapsed = nil;
    end


    local function PostInputDeviceChanged(dbValue)
        IS_KBM = dbValue == 1;

        --Switch ABXY is reversed
        local isSwitch = dbValue == 4;

        if isSwitch then
            GAMEPAD_CONFIRM = "PAD2";
            GAMEPAD_CANCEL = "PAD1";
            GAMEPAD_ALT = "PAD3";
            KeyRemap.PAD1 = "ESCAPE";
            KeyRemap.PAD2 = nil;
        else
            GAMEPAD_CONFIRM = "PAD1";
            GAMEPAD_CANCEL = "PAD2";
            GAMEPAD_ALT = "PAD4";
            KeyRemap.PAD1 = nil;
            KeyRemap.PAD2 = "ESCAPE";
        end
    end
    addon.CallbackRegistry:Register("PostInputDeviceChanged", PostInputDeviceChanged);
end


do  --Settings
    local function Settings_PrimaryControlKey(dbValue)
        DISABLE_CONTROL_KEY = false;

        if dbValue == 1 then
            KeyboardControl:UnregisterEvent("UPDATE_BINDINGS");
        elseif dbValue == 2 then
            KeyboardControl:RegisterEvent("UPDATE_BINDINGS");
        elseif dbValue == 0 then
            KeyboardControl:UnregisterEvent("UPDATE_BINDINGS");
            DISABLE_CONTROL_KEY = true;
        end
    end
    addon.CallbackRegistry:Register("SettingChanged.PrimaryControlKey", Settings_PrimaryControlKey);

    local function Settings_CycleRewardHotkeyEnabled(dbValue)
        CYCLE_REWARD_ENABLED = dbValue == true
    end
    addon.CallbackRegistry:Register("SettingChanged.CycleRewardHotkeyEnabled", Settings_CycleRewardHotkeyEnabled);

    local function Settings_TTSEnabled(dbValue)
        TTS_ENABLED = dbValue == true
    end
    addon.CallbackRegistry:Register("SettingChanged.TTSEnabled", Settings_TTSEnabled);

    local function Settings_TTSUseHotkey(dbValue)
        TTS_HOTKEY_ENABLED = dbValue == true
    end
    addon.CallbackRegistry:Register("SettingChanged.TTSUseHotkey", Settings_TTSUseHotkey);

    local function Settings_UseCustomBindings(dbValue)
        USE_CUSTOM_BINDINGS = dbValue == true;
        if addon.IS_LEGACY_ASCENSION then
            KeyboardControl:RefreshLegacyBindings();
        end
    end
    addon.CallbackRegistry:Register("SettingChanged.UseCustomBindings", Settings_UseCustomBindings);

    if addon.IS_LEGACY_ASCENSION then
        addon.CallbackRegistry:Register("CustomBindingChanged", function()
            KeyboardControl:RefreshLegacyBindings();
        end);
        addon.CallbackRegistry:Register("SettingsUI.Show", function()
            KeyboardControl:RefreshLegacyBindings();
        end);
        addon.CallbackRegistry:Register("SettingsUI.Hide", function()
            KeyboardControl:RefreshLegacyBindings();
        end);
        addon.CallbackRegistry:Register("Clipboard.Show", function()
            KeyboardControl:RefreshLegacyBindings();
        end);
        addon.CallbackRegistry:Register("Clipboard.Hide", function()
            KeyboardControl:RefreshLegacyBindings();
        end);
        addon.CallbackRegistry:Register("BookUI.Show", function()
            KeyboardControl:RefreshLegacyBindings();
        end);
        addon.CallbackRegistry:Register("BookUI.Hide", function()
            KeyboardControl:RefreshLegacyBindings();
        end);
        addon.CallbackRegistry:Register("DialogueUI.LegacyRelease", function()
            KeyboardControl:SuspendLegacyBindings();
        end);
    end
end


do  --Error Prevention Disable Hotkey
    function KeyboardControl:DisableGossipHotkeys()
        local anyChange;

        if self.keyActions then
            for key, v in pairs(self.keyActions) do
                if v.obj and v.obj.type == "gossip" then
                    self.keyActions[key] = nil;
                    anyChange = true;
                end
            end
        end

        if anyChange then
            
        end
    end
end
