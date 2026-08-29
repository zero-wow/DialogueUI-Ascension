local _, addon = ...
local C_AddOns = addon.Legacy.C_AddOns or C_AddOns

if not addon.IS_LEGACY_ASCENSION then
    return
end

local CallbackRegistry = addon.CallbackRegistry

local IMMERSION_MAIN_EVENTS = {
    "GOSSIP_CLOSED",
    "GOSSIP_SHOW",
    "QUEST_ACCEPTED",
    "QUEST_COMPLETE",
    "QUEST_DETAIL",
    "QUEST_FINISHED",
    "QUEST_GREETING",
    "QUEST_PROGRESS",
    "QUEST_ITEM_UPDATE",
    "ITEM_TEXT_BEGIN",
    "ITEM_TEXT_READY",
    "ITEM_TEXT_CLOSED",
}

local IMMERSION_TITLE_EVENTS = {
    "GOSSIP_CLOSED",
    "GOSSIP_SHOW",
    "QUEST_ACCEPTED",
    "QUEST_COMPLETE",
    "QUEST_DETAIL",
    "QUEST_FINISHED",
    "QUEST_GREETING",
    "QUEST_PROGRESS",
    "UNIT_QUEST_LOG_CHANGED",
}

local CURSOR_QUEST_EVENTS = {
    "GOSSIP_SHOW",
    "GOSSIP_CLOSED",
    "QUEST_GREETING",
    "QUEST_DETAIL",
    "QUEST_PROGRESS",
    "QUEST_COMPLETE",
    "QUEST_ACCEPT_CONFIRM",
    "QUEST_FINISHED",
}

local DIALOG_KEY_QUEST_EVENTS = {
    "GOSSIP_SHOW",
    "GOSSIP_CLOSED",
    "QUEST_GREETING",
    "QUEST_DETAIL",
    "QUEST_PROGRESS",
    "QUEST_COMPLETE",
    "QUEST_FINISHED",
    "QUEST_CLOSED",
}

local savedEvents = {}

local function SuspendEvents(frame, events)
    if not frame or savedEvents[frame] then
        return
    end

    local registered = {}
    savedEvents[frame] = registered
    for _, event in ipairs(events) do
        local wasRegistered = frame.IsEventRegistered and frame:IsEventRegistered(event)
        if wasRegistered then
            registered[event] = true
            frame:UnregisterEvent(event)
        end
    end
end

local function RestoreEvents(frame)
    local registered = frame and savedEvents[frame]
    if not registered then
        return
    end

    for event in pairs(registered) do
        pcall(frame.RegisterEvent, frame, event)
    end
    savedEvents[frame] = nil
end

local function IsLoaded(name)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name)
end

local function SuspendCompetingQuestUIs()
    if IsLoaded("Immersion-Ascension") or IsLoaded("Immersion") then
        local frame = _G.ImmersionFrame
        local titles = frame and frame.TitleButtons
        SuspendEvents(frame, IMMERSION_MAIN_EVENTS)
        SuspendEvents(titles, IMMERSION_TITLE_EVENTS)
        if titles then
            titles:Hide()
        end
        if frame then
            frame:Hide()
        end
    end

    if IsLoaded("CursorQuestChoices") then
        local controller = _G.CursorQuestChoicesController
        SuspendEvents(controller, CURSOR_QUEST_EVENTS)
        if _G.CursorQuestChoicesFrame then
            _G.CursorQuestChoicesFrame:Hide()
        end
    end

    if IsLoaded("DialogKey-Ascension") then
        local dialogKey = _G.DialogKeyAscensionFrame
        -- DialogueUI supplies its own keyboard navigation. Keep DialogKey's
        -- popup and mailbox support, but prevent its quest proxy from briefly
        -- replacing DialogueUI's number/space bindings on every dialog event.
        SuspendEvents(dialogKey and dialogKey._eventsFrame, DIALOG_KEY_QUEST_EVENTS)
    end
end

local function RestoreCompetingQuestUIs()
    local immersion = _G.ImmersionFrame
    RestoreEvents(immersion)
    RestoreEvents(immersion and immersion.TitleButtons)
    RestoreEvents(_G.CursorQuestChoicesController)
    local dialogKey = _G.DialogKeyAscensionFrame
    RestoreEvents(dialogKey and dialogKey._eventsFrame)
end

CallbackRegistry:Register("DialogueUI.LegacyTakeover", SuspendCompetingQuestUIs)
CallbackRegistry:Register("DialogueUI.LegacyRelease", RestoreCompetingQuestUIs)
