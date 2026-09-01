-- Focused Lua 5.1 regression test for DialogueUI's legacy QUEST_ACCEPTED path.

local addonRoot = assert(arg and arg[1], "usage: lua LegacyAutoAcceptHarness.lua <addon-root>")
local sourcePath = addonRoot.."\\Code\\Dialogue\\DialogueUI.lua"
local file = assert(io.open(sourcePath, "rb"))
local source = file:read("*a")
file:close()
local LoadString = loadstring or load

local function Extract(startMarker, endMarker)
    local first = assert(source:find(startMarker, 1, true), "missing source marker: "..startMarker)
    local last = assert(source:find(endMarker, first + #startMarker, true), "missing source marker: "..endMarker)
    return source:sub(first, last - 1)
end

local function Assert(value, message)
    if not value then
        error(message, 2)
    end
end

DUIDialogBaseMixin = {}
addon = {IS_LEGACY_ASCENSION = true}
C_QuestLog = {}
API = {}
KeyboardControl = {}
GossipDataProvider = {}

local offeredQuestID = 0
function GetQuestID()
    return offeredQuestID
end

function GossipDataProvider:ShouldAutoAcceptQuest()
    return false
end

local queued = {}
function After(_, callback)
    queued[#queued + 1] = callback
end

local function RunQueued()
    local callbacks = queued
    queued = {}
    for _, callback in ipairs(callbacks) do
        callback()
    end
end

assert(LoadString(Extract(
    "function DUIDialogBaseMixin:DismissAcceptedQuestDetail()",
    "function DUIDialogBaseMixin:HandleQuestDetail(playFadeIn)"
)))()
assert(LoadString(Extract(
    "function DUIDialogBaseMixin:HandleQuestDetail(playFadeIn)",
    "function DUIDialogBaseMixin:HandleQuestAccepted(questID, classicQuestID)"
)))()
assert(LoadString(Extract(
    "function DUIDialogBaseMixin:HandleQuestAccepted(questID, classicQuestID)",
    "local function CalulateLockDuration(rawCopper)"
)))()

local questInfoByIndex = {}
local questIndexByID = {}
local questTitleByID = {}
local onQuest = {}

function C_QuestLog.GetInfo(index)
    return questInfoByIndex[index]
end

function C_QuestLog.GetLogIndexForQuestID(questID)
    return questIndexByID[questID]
end

function C_QuestLog.GetTitleForQuestID(questID)
    return questTitleByID[questID]
end

function API.IsPlayerOnQuest(questID)
    return onQuest[questID] == true
end

local function NewFrame(questID, title)
    local frame = {
        handler = "HandleQuestDetail",
        questID = questID,
        questTitle = title,
        acknowledgeAutoAcceptQuest = true,
        shown = true,
        hideCount = 0,
    }

    function frame:IsShown()
        return self.shown
    end

    function frame:Hide()
        Assert(self.interactionIsContinuing == true, "dismissal did not preserve the underlying interaction")
        Assert(self.acknowledgeAutoAcceptQuest == nil, "dismissal retained a duplicate AcceptQuest acknowledgement")
        self.hideCount = self.hideCount + 1
        self.shown = false
    end

    return setmetatable(frame, {__index = DUIDialogBaseMixin})
end

local function ResetData()
    queued = {}
    questInfoByIndex = {}
    questIndexByID = {}
    questTitleByID = {}
    onQuest = {}
end

ResetData()
offeredQuestID = 42
onQuest[42] = true
local acceptedBeforeRender = NewFrame(42, "Harness Quest")
local shouldShow = acceptedBeforeRender:HandleQuestDetail()
Assert(shouldShow == false, "already-accepted QUEST_DETAIL attempted to render a stale page")
Assert(acceptedBeforeRender.hideCount == 1, "already-rendered stale detail was not dismissed")

ResetData()
questInfoByIndex[4] = {questID = 42, title = "Harness Quest"}
questIndexByID[42] = 4
local exact = NewFrame(42, "Harness Quest")
exact:HandleQuestAccepted(4, 42)
Assert(exact.hideCount == 1, "matching accepted quest did not dismiss the detail page")
Assert(#queued == 0, "exact match scheduled an unnecessary retry")

ResetData()
questInfoByIndex[4] = {questID = 42, title = "Harness Quest"}
local synthetic = NewFrame(1500000042, "Harness Quest")
synthetic:HandleQuestAccepted(4)
Assert(synthetic.hideCount == 1, "synthetic pre-accept ID did not match the accepted log title")

ResetData()
questInfoByIndex[4] = {questID = 42, title = "Harness Quest"}
questIndexByID[42] = 4
local syntheticDirectID = NewFrame(1500000042, "Harness Quest")
syntheticDirectID:HandleQuestAccepted(42)
Assert(syntheticDirectID.hideCount == 1, "sole questID payload did not bridge a synthetic rendered ID")

ResetData()
questInfoByIndex[7] = {questID = 99, title = "Different Quest"}
questTitleByID[99] = "Different Quest"
local mismatch = NewFrame(42, "Harness Quest")
mismatch:HandleQuestAccepted(7)
Assert(mismatch.hideCount == 0, "mismatched QUEST_ACCEPTED dismissed the current detail page")
RunQueued()
Assert(mismatch.hideCount == 0, "mismatched delayed acceptance dismissed the current detail page")

ResetData()
questInfoByIndex[4] = {questID = 42, title = "Duplicate Title"}
local duplicateTitle = NewFrame(77, "Duplicate Title")
duplicateTitle:HandleQuestAccepted(4)
Assert(duplicateTitle.hideCount == 0, "title fallback dismissed a different real quest with the same title")
RunQueued()
Assert(duplicateTitle.hideCount == 0, "delayed title fallback dismissed a different real quest")

ResetData()
local delayed = NewFrame(1500000042, "Harness Quest")
delayed:HandleQuestAccepted(4)
Assert(delayed.hideCount == 0 and #queued == 1, "unresolved acceptance did not defer exactly once")
questInfoByIndex[4] = {questID = 42, title = "Harness Quest"}
RunQueued()
Assert(delayed.hideCount == 1, "delayed quest-log update did not dismiss the stale detail page")

ResetData()
local newerPage = NewFrame(1500000042, "Harness Quest")
newerPage:HandleQuestAccepted(4)
newerPage.questID = 1500000099
newerPage.questTitle = "Newer Quest"
questInfoByIndex[4] = {questID = 42, title = "Harness Quest"}
RunQueued()
Assert(newerPage.hideCount == 0, "a delayed acceptance dismissed a newer detail page")

ResetData()
local directID = NewFrame(42, "Harness Quest")
directID:HandleQuestAccepted(42)
Assert(directID.hideCount == 1, "sole private-server questID payload did not dismiss the accepted detail")

print("Legacy auto-accept harness: PASS")
