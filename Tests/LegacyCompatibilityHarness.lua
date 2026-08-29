-- Standalone Lua 5.1 smoke test for Compatibility.lua.
-- This file is intentionally not listed in the addon TOC.

local addonRoot = assert(arg[1], "usage: lua LegacyCompatibilityHarness.lua <addon-root> [absent|sentinel]")
local secureCallMode = arg[2] or "absent"

assert(secureCallMode == "absent" or secureCallMode == "sentinel", "secure-call mode must be 'absent' or 'sentinel'")

local nativeSecureCallCount = 0
if secureCallMode == "sentinel" then
    securecallfunction = function(func, ...)
        nativeSecureCallCount = nativeSecureCallCount + 1
        return func(...)
    end
else
    securecallfunction = nil
end
local nativeSecureCallFunction = securecallfunction

local function Assert(condition, message)
    if not condition then
        error(message or "assertion failed", 2)
    end
end

local validEvents = {
    ADDON_LOADED = true,
    GOSSIP_SHOW = true,
    GOSSIP_CLOSED = true,
    QUEST_GREETING = true,
    QUEST_DETAIL = true,
    QUEST_PROGRESS = true,
    QUEST_COMPLETE = true,
    QUEST_FINISHED = true,
    QUEST_ACCEPTED = true,
    QUEST_ITEM_UPDATE = true,
    QUEST_LOG_UPDATE = true,
    QUEST_QUERY_COMPLETE = true,
    PLAYER_ENTERING_WORLD = true,
}

local validScripts = {
    OnEvent = true,
    OnUpdate = true,
    OnShow = true,
    OnHide = true,
    OnKeyDown = true,
    OnEnter = true,
    OnLeave = true,
    OnMouseDown = true,
    OnMouseUp = true,
    OnClick = true,
}

local frames = {}
local mouseDown = {}
local nativeFrameSnapshots = setmetatable({}, {__mode = "k"})
local lastNativeSecureFrame

local function NewRegion(objectType)
    local region = {
        objectType = objectType or "Texture",
        shown = true,
        width = 16,
        height = 16,
        fontHeight = 12,
        spacing = 0,
    }

    function region:GetObjectType() return self.objectType end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:IsShown() return self.shown end
    function region:SetWidth(value) self.width = value end
    function region:SetHeight(value) self.height = value end
    function region:GetWidth() return self.width end
    function region:GetHeight() return self.height end
    function region:SetTexture(...) self.textureArgs = {...}; return true end
    function region:SetVertexColor(...) self.vertexColor = {...} end
    function region:SetGradient(...) self.gradient = {...} end
    function region:SetGradientAlpha(...) self.gradientAlpha = {...} end
    function region:SetText(value) self.text = value end
    function region:GetText() return self.text end
    function region:GetStringWidth() return #(self.text or "") * 6 end
    function region:GetStringHeight() return self.height end
    function region:GetFont() return "mock.ttf", self.fontHeight, "" end
    function region:SetFont(_, size) self.fontHeight = size; return true end
    function region:GetSpacing() return self.spacing end
    function region:SetSpacing(value) self.spacing = value end
    function region:SetAlpha(value) self.alpha = value end

    return region
end

local function NewFrame(objectType, name, parent, template)
    local frame = {
        objectType = objectType or "Frame",
        name = name,
        parent = parent,
        template = template,
        events = {},
        scripts = {},
        children = {},
        regions = {},
        shown = true,
        width = 100,
        height = 100,
        alpha = 1,
    }
    frames[#frames + 1] = frame
    if parent and parent.children then
        parent.children[#parent.children + 1] = frame
    end

    function frame:GetObjectType() return self.objectType end
    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent end
    function frame:SetParent(value) self.parent = value end
    function frame:GetChildren() return unpack(self.children) end
    function frame:GetRegions() return unpack(self.regions) end
    function frame:RegisterEvent(event)
        if not validEvents[event] then error("unknown event: "..tostring(event)) end
        self.events[event] = true
        return true
    end
    function frame:UnregisterEvent(event)
        if not validEvents[event] then error("unknown event: "..tostring(event)) end
        self.events[event] = nil
    end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:IsEventRegistered(event) return self.events[event] == true end
    function frame:SetScript(scriptType, handler)
        if not validScripts[scriptType] then error("unknown script: "..tostring(scriptType)) end
        self.scripts[scriptType] = handler
    end
    function frame:GetScript(scriptType) return self.scripts[scriptType] end
    function frame:CreateTexture()
        local region = NewRegion("Texture")
        self.regions[#self.regions + 1] = region
        return region
    end
    function frame:CreateFontString()
        local region = NewRegion("FontString")
        self.regions[#self.regions + 1] = region
        return region
    end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown end
    function frame:GetEffectiveAlpha() return self.alpha end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:SetWidth(value) self.width = value end
    function frame:SetHeight(value) self.height = value end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:IsMouseOver() return self.mouseOver == true end
    function frame:EnableKeyboard(value) self.keyboard = value end
    function frame:SetSequence(value) self.sequence = value end
    function frame:SetSequenceTime(_, value) self.sequenceTime = value end
    function frame:SetDisplayInfo(value) self.displayInfo = value end
    function frame:SetLight(...) self.light = {...} end
    function frame:TryOn(value) self.triedOn = value end

    if template == "HarnessTemplate" then
        frame.HarnessTexture = frame:CreateTexture()
        frame.HarnessModel = NewFrame("PlayerModel", nil, frame)
    end

    return frame
end

local function NativeCreateFrame(frameType, name, parent, template)
    local frame = NewFrame(frameType, name, parent, template)
    nativeFrameSnapshots[frame] = {
        RegisterEvent = frame.RegisterEvent,
        UnregisterEvent = frame.UnregisterEvent,
        UnregisterAllEvents = frame.UnregisterAllEvents,
        IsEventRegistered = frame.IsEventRegistered,
        SetScript = frame.SetScript,
        CreateTexture = frame.CreateTexture,
        CreateFontString = frame.CreateFontString,
    }
    if type(template) == "string" and string.find(template, "SecureActionButtonTemplate", 1, true) then
        lastNativeSecureFrame = frame
    end
    return frame
end

CreateFrame = NativeCreateFrame
UIParent = NewFrame("Frame", "UIParent")
WorldFrame = NewFrame("Frame", "WorldFrame")

function GetScreenWidth() return 1920 end
function GetScreenHeight() return 1080 end
function GetTime() return 100 end
function GetMouseFocus() return nil end
function IsMouseButtonDown(button) return mouseDown[button] == true end
function geterrorhandler() return function(message) error(message, 0) end end
function UnitName(unit) return unit == "npc" and "Harness NPC" or "Player" end
function UnitGUID(unit) return unit == "npc" and "Creature-0-0-0-0-1" or "Player-0-1" end

local questLog = {
    {title = "Harness Quest", level = 10, complete = true, id = 42},
}
local currentQuestTitle = "Harness Quest"
local completedQuests = {}

function GetNumQuestLogEntries() return #questLog end
function GetQuestLogTitle(index)
    local info = questLog[index]
    if not info then return end
    return info.title, info.level, nil, 0, false, false, info.complete, false, info.id
end
function GetTitleText() return currentQuestTitle end
function GetContainerItemInfo()
    return "Interface\\Icons\\INV_Misc_QuestionMark", 2, false, 3, false, false, "item:17"
end
function GetQuestsCompleted(target)
    for questID, state in pairs(completedQuests) do target[questID] = state end
end
function QueryQuestsCompleted() end

function GetNumGossipOptions() return 2 end
function GetGossipOptions() return "Browse goods", "vendor", "Take me there", "taxi" end
function GetNumGossipActiveQuests() return 1 end
function GetGossipActiveQuests() return "Harness Quest", 10, false, true end
function GetNumGossipAvailableQuests() return 1 end
function GetGossipAvailableQuests() return "New Harness Quest", 8, false, false, false end
function GetGossipText() return "Welcome." end

function GetNumActiveQuests() return 1 end
function GetActiveTitle() return "Harness Quest", true end
function GetActiveLevel() return 10 end
function GetNumAvailableQuests() return 1 end
function GetAvailableTitle() return "New Harness Quest", 8 end
local nativeGetAvailableQuestInfo = function() return false, false, false end
GetAvailableQuestInfo = nativeGetAvailableQuestInfo

local selectedGossipOption
local selectedGossipActive
local selectedGossipAvailable
local selectedGreetingActive
local selectedGreetingAvailable
function SelectGossipOption(index) selectedGossipOption = index end
function SelectGossipActiveQuest(index) selectedGossipActive = index end
function SelectGossipAvailableQuest(index) selectedGossipAvailable = index end
local nativeSelectActiveQuest = function(index) selectedGreetingActive = index end
local nativeSelectAvailableQuest = function(index) selectedGreetingAvailable = index end
SelectActiveQuest = nativeSelectActiveQuest
SelectAvailableQuest = nativeSelectAvailableQuest
function CloseGossip() end

local nativeGetQuestReward = function() end
GetQuestReward = nativeGetQuestReward

local unrelatedFrame = NativeCreateFrame("Frame", "UnrelatedFrame")
local unrelatedRegisterEvent = unrelatedFrame.RegisterEvent
local nativeCGossipInfo = C_GossipInfo

local function SnapshotTable(tbl)
    local snapshot = {}
    for key, value in pairs(tbl) do
        snapshot[key] = value
    end
    return snapshot
end

local function AssertTableUnchanged(tbl, snapshot, label)
    for key, value in pairs(tbl) do
        Assert(snapshot[key] == value, label.." added or replaced member "..tostring(key))
    end
    for key, value in pairs(snapshot) do
        Assert(tbl[key] == value, label.." removed or replaced member "..tostring(key))
    end
end

local nativeTimerAfter = function(_, callback)
    if callback then callback() end
end
local nativeCVarGetter = function() return "1" end
local nativeSpellLoader = function() end
local nativeItemCounter = function() return 7 end
local nativeContainerItemID = function() return 731 end
local nativeBestMapForUnit = function() return 987 end
local nativeQuestLoader = function() end
local nativePlayerInteractionType = {NativeHarnessType = 97}
local legacyGetAddOnMetadata = function() return "LEGACY_METADATA" end
local legacyIsAddOnLoaded = function(name) return name == "LegacyLoaded" end
local legacyLoadAddOn = function(name) return name == "LegacyLoadable" end
local legacyGetAddOnInfo = function() return "Legacy AddOn" end
local legacyGetNumAddOns = function() return 12 end

local nativeCTimer = {After = nativeTimerAfter, NativeHarnessValue = "timer"}
local nativeCCVar = {GetCVar = nativeCVarGetter, NativeHarnessValue = "cvar"}
local nativeCContainer = {GetContainerItemID = nativeContainerItemID, NativeHarnessValue = "container"}
local nativeCSpell = {RequestLoadSpellData = nativeSpellLoader, NativeHarnessValue = "spell"}
local nativeCItem = {GetItemCount = nativeItemCounter, NativeHarnessValue = "item"}
local nativeCMap = {GetBestMapForUnit = nativeBestMapForUnit, NativeHarnessValue = "map"}
local nativeCQuestLog = {RequestLoadQuestByID = nativeQuestLoader, NativeHarnessValue = "questlog"}
local nativeEnum = {PlayerInteractionType = nativePlayerInteractionType, NativeHarnessValue = "enum"}
local nativeCAddOns
local nativeEventRegistry

GetAddOnMetadata = legacyGetAddOnMetadata
IsAddOnLoaded = legacyIsAddOnLoaded
LoadAddOn = legacyLoadAddOn
GetAddOnInfo = legacyGetAddOnInfo
GetNumAddOns = legacyGetNumAddOns

if secureCallMode == "sentinel" then
    nativeCAddOns = {
        IsAddOnLoaded = function(name) return name == "NativeLoaded" end,
        NativeHarnessValue = "addons",
    }

    nativeEventRegistry = {
        callbackTables = {},
        NativeHarnessValue = "event-registry",
    }

    function nativeEventRegistry:RegisterCallback(event, callback, owner)
        Assert(self == nativeEventRegistry, "native EventRegistry method received a facade as self")
        self.callbackTables[event] = self.callbackTables[event] or {}
        self.callbackTables[event][#self.callbackTables[event] + 1] = {callback = callback, owner = owner}
    end

    function nativeEventRegistry:UnregisterCallback(event, owner)
        Assert(self == nativeEventRegistry, "native EventRegistry unregister received a facade as self")
        local callbacks = self.callbackTables[event] or {}
        for index = #callbacks, 1, -1 do
            if callbacks[index].owner == owner then
                table.remove(callbacks, index)
            end
        end
    end

    function nativeEventRegistry:TriggerEvent(event, ...)
        Assert(self == nativeEventRegistry, "native EventRegistry trigger received a facade as self")
        for _, entry in ipairs(self.callbackTables[event] or {}) do
            entry.callback(entry.owner, ...)
        end
    end
end

C_Timer = nativeCTimer
C_CVar = nativeCCVar
C_Container = nativeCContainer
C_Spell = nativeCSpell
C_Item = nativeCItem
C_Map = nativeCMap
C_QuestLog = nativeCQuestLog
Enum = nativeEnum
C_AddOns = nativeCAddOns
EventRegistry = nativeEventRegistry

local nativeGetQuestID
local nativeGetQuestLogIndexByID
if secureCallMode == "sentinel" then
    nativeGetQuestID = function() return 42 end
    nativeGetQuestLogIndexByID = function(questID) return questID == 42 and 1 or nil end
end
GetQuestID = nativeGetQuestID
GetQuestLogIndexByID = nativeGetQuestLogIndexByID

local nativeCTimerSnapshot = SnapshotTable(nativeCTimer)
local nativeCCVarSnapshot = SnapshotTable(nativeCCVar)
local nativeCContainerSnapshot = SnapshotTable(nativeCContainer)
local nativeCSpellSnapshot = SnapshotTable(nativeCSpell)
local nativeCItemSnapshot = SnapshotTable(nativeCItem)
local nativeCMapSnapshot = SnapshotTable(nativeCMap)
local nativeCQuestLogSnapshot = SnapshotTable(nativeCQuestLog)
local nativeEnumSnapshot = SnapshotTable(nativeEnum)
local nativePlayerInteractionTypeSnapshot = SnapshotTable(nativePlayerInteractionType)
local nativeCAddOnsSnapshot = nativeCAddOns and SnapshotTable(nativeCAddOns)
local nativeEventRegistrySnapshot = nativeEventRegistry and SnapshotTable(nativeEventRegistry)

local addon = {}
local chunk = assert(loadfile(addonRoot.."\\Compatibility.lua"))
chunk("DialogueUI-Ascension", addon)

Assert(CreateFrame == NativeCreateFrame, "Compatibility.lua replaced global CreateFrame")
Assert(addon.Legacy.NativeCreateFrame == NativeCreateFrame, "Legacy.NativeCreateFrame is not the captured native factory")
Assert(GetQuestReward == nativeGetQuestReward, "Compatibility.lua replaced global GetQuestReward")
Assert(GetAvailableQuestInfo == nativeGetAvailableQuestInfo, "legacy GetAvailableQuestInfo contract was replaced")
Assert(SelectActiveQuest == nativeSelectActiveQuest, "legacy SelectActiveQuest was replaced")
Assert(SelectAvailableQuest == nativeSelectAvailableQuest, "legacy SelectAvailableQuest was replaced")
Assert(securecallfunction == nativeSecureCallFunction, "Compatibility.lua created or replaced global securecallfunction")
Assert(C_VoiceChat == nil and C_TTSSettings == nil, "Compatibility.lua manufactured optional TTS capability namespaces")
Assert(C_NamePlate == nil, "Compatibility.lua manufactured the optional C_NamePlate namespace")
Assert(C_GossipInfo == nativeCGossipInfo, "Compatibility.lua created or mutated the global C_GossipInfo namespace")
Assert(C_Timer == nativeCTimer, "Compatibility.lua replaced global C_Timer")
Assert(C_CVar == nativeCCVar, "Compatibility.lua replaced global C_CVar")
Assert(C_Container == nativeCContainer, "Compatibility.lua replaced global C_Container")
Assert(C_Spell == nativeCSpell, "Compatibility.lua replaced global C_Spell")
Assert(C_Item == nativeCItem, "Compatibility.lua replaced global C_Item")
Assert(C_Map == nativeCMap, "Compatibility.lua replaced global C_Map")
Assert(C_QuestLog == nativeCQuestLog, "Compatibility.lua replaced global C_QuestLog")
Assert(Enum == nativeEnum, "Compatibility.lua replaced global Enum")
Assert(C_AddOns == nativeCAddOns, "Compatibility.lua created or replaced global C_AddOns")
Assert(EventRegistry == nativeEventRegistry, "Compatibility.lua created or replaced global EventRegistry")
Assert(GetQuestID == nativeGetQuestID, "Compatibility.lua created or replaced global GetQuestID")
Assert(GetQuestLogIndexByID == nativeGetQuestLogIndexByID, "Compatibility.lua created or replaced global GetQuestLogIndexByID")
AssertTableUnchanged(nativeCTimer, nativeCTimerSnapshot, "global C_Timer")
AssertTableUnchanged(nativeCCVar, nativeCCVarSnapshot, "global C_CVar")
AssertTableUnchanged(nativeCContainer, nativeCContainerSnapshot, "global C_Container")
AssertTableUnchanged(nativeCSpell, nativeCSpellSnapshot, "global C_Spell")
AssertTableUnchanged(nativeCItem, nativeCItemSnapshot, "global C_Item")
AssertTableUnchanged(nativeCMap, nativeCMapSnapshot, "global C_Map")
AssertTableUnchanged(nativeCQuestLog, nativeCQuestLogSnapshot, "global C_QuestLog")
AssertTableUnchanged(nativeEnum, nativeEnumSnapshot, "global Enum")
AssertTableUnchanged(nativePlayerInteractionType, nativePlayerInteractionTypeSnapshot, "global Enum.PlayerInteractionType")
if nativeCAddOns then
    AssertTableUnchanged(nativeCAddOns, nativeCAddOnsSnapshot, "global C_AddOns")
    AssertTableUnchanged(nativeEventRegistry, nativeEventRegistrySnapshot, "global EventRegistry")
end

local PrivateTimer = addon.Legacy.C_Timer
local PrivateCVar = addon.Legacy.C_CVar
local PrivateContainer = addon.Legacy.C_Container
local PrivateSpell = addon.Legacy.C_Spell
local PrivateItem = addon.Legacy.C_Item
local PrivateMap = addon.Legacy.C_Map
local PrivateQuestLog = addon.Legacy.C_QuestLog
local PrivateEnum = addon.Legacy.Enum
local PrivateAddOns = addon.Legacy.C_AddOns
local PrivateEventRegistry = addon.Legacy.EventRegistry
Assert(PrivateTimer ~= nativeCTimer and PrivateCVar ~= nativeCCVar and PrivateContainer ~= nativeCContainer and PrivateSpell ~= nativeCSpell and PrivateItem ~= nativeCItem and PrivateMap ~= nativeCMap and PrivateQuestLog ~= nativeCQuestLog and PrivateEnum ~= nativeEnum, "compatibility namespaces are not private facades")
Assert(type(PrivateAddOns) == "table" and PrivateAddOns ~= nativeCAddOns, "C_AddOns compatibility namespace is not a private facade")
Assert(PrivateAddOns.GetAddOnMetadata == legacyGetAddOnMetadata and PrivateAddOns.GetAddOnInfo == legacyGetAddOnInfo and PrivateAddOns.GetNumAddOns() == 12, "private C_AddOns facade did not install legacy fallbacks")
if secureCallMode == "sentinel" then
    Assert(PrivateAddOns.IsAddOnLoaded == nativeCAddOns.IsAddOnLoaded and PrivateAddOns.IsAddOnLoaded("NativeLoaded"), "private C_AddOns facade did not retain its native member")
    Assert(nativeCAddOns.GetAddOnMetadata == nil and nativeCAddOns.LoadAddOn == nil, "C_AddOns fallbacks leaked into the native table")
    Assert(PrivateEventRegistry == nativeEventRegistry, "native EventRegistry identity was not preserved")
else
    Assert(C_AddOns == nil and EventRegistry == nil, "private compatibility registries leaked into absent globals")
    Assert(PrivateAddOns.IsAddOnLoaded("LegacyLoaded") and PrivateAddOns.LoadAddOn("LegacyLoadable"), "private C_AddOns legacy behavior failed")
    Assert(type(PrivateEventRegistry) == "table", "private EventRegistry fallback was not created")
end
local registryOwner = {}
local registryCallbackCount = 0
local registryCallbackValue
PrivateEventRegistry:RegisterCallback("Harness.Event", function(owner, value)
    Assert(owner == registryOwner, "private EventRegistry lost callback ownership")
    registryCallbackCount = registryCallbackCount + 1
    registryCallbackValue = value
end, registryOwner)
PrivateEventRegistry:TriggerEvent("Harness.Event", 731)
Assert(registryCallbackCount == 1 and registryCallbackValue == 731, "private EventRegistry callback behavior failed")
PrivateEventRegistry:UnregisterCallback("Harness.Event", registryOwner)
PrivateEventRegistry:TriggerEvent("Harness.Event", 999)
Assert(registryCallbackCount == 1, "private EventRegistry unregister behavior failed")
Assert(PrivateTimer.After == nativeTimerAfter, "private C_Timer facade did not retain a native member")
Assert(type(PrivateTimer.After) == "function" and type(PrivateTimer.NewTimer) == "function" and type(PrivateTimer.NewTicker) == "function", "private legacy timer namespace is incomplete")
Assert(nativeCTimer.NewTimer == nil and nativeCTimer.NewTicker == nil, "timer fallbacks leaked into global C_Timer")
local cancelledTimer = PrivateTimer.NewTimer(1, function() error("cancelled timer fired") end)
Assert(cancelledTimer and type(cancelledTimer.Cancel) == "function" and type(cancelledTimer.IsCancelled) == "function", "legacy timer object contract is incomplete")
cancelledTimer:Cancel()
Assert(cancelledTimer:IsCancelled(), "legacy timer cancellation state was not retained")
Assert(PrivateCVar.GetCVar == nativeCVarGetter and PrivateCVar.GetCVarBool("Harness") == true, "private C_CVar facade did not combine native and fallback members")
Assert(nativeCCVar.GetCVarBool == nil and nativeCCVar.SetCVar == nil, "CVar fallbacks leaked into global C_CVar")
local privateContainerInfo = PrivateContainer.GetContainerItemInfo(0, 1)
Assert(PrivateContainer.GetContainerItemID == nativeContainerItemID and privateContainerInfo and privateContainerInfo.itemID == 731, "private C_Container facade did not combine native and fallback members")
Assert(nativeCContainer.GetContainerItemInfo == nil and nativeCContainer.GetItemCooldown == nil, "container fallbacks leaked into global C_Container")
Assert(PrivateSpell.RequestLoadSpellData == nativeSpellLoader and type(PrivateSpell.DoesSpellExist) == "function" and type(PrivateSpell.GetSpellInfo) == "function", "private C_Spell facade is incomplete")
Assert(nativeCSpell.DoesSpellExist == nil and nativeCSpell.GetSpellInfo == nil, "spell fallbacks leaked into global C_Spell")
Assert(PrivateItem.GetItemCount == nativeItemCounter and PrivateItem.GetItemCount(1) == 7 and type(PrivateItem.GetItemInfoInstant) == "function", "private C_Item facade is incomplete")
Assert(nativeCItem.GetItemInfoInstant == nil and nativeCItem.GetItemIconByID == nil, "item fallbacks leaked into global C_Item")
Assert(PrivateMap.GetBestMapForUnit == nativeBestMapForUnit and PrivateMap.GetBestMapForUnit("player") == 987 and type(PrivateMap.GetMapInfo) == "function", "private C_Map facade is incomplete")
Assert(nativeCMap.GetMapInfo == nil and nativeCMap.GetAreaInfo == nil, "map fallbacks leaked into global C_Map")
Assert(PrivateQuestLog.RequestLoadQuestByID == nativeQuestLoader and PrivateQuestLog.GetLogIndexForQuestID(42) == 1 and PrivateQuestLog.GetTitleForQuestID(42) == "Harness Quest", "private C_QuestLog facade is incomplete")
Assert(nativeCQuestLog.GetInfo == nil and nativeCQuestLog.GetLogIndexForQuestID == nil, "quest-log fallbacks leaked into global C_QuestLog")
Assert(type(addon.Legacy.GetQuestID) == "function" and addon.Legacy.GetQuestID() == 42, "private GetQuestID resolver failed")
if secureCallMode == "sentinel" then
    Assert(addon.Legacy.GetQuestID == nativeGetQuestID, "private GetQuestID did not preserve the native function")
    Assert(PrivateQuestLog.GetLogIndexForQuestID == nativeGetQuestLogIndexByID, "private C_QuestLog did not preserve native GetQuestLogIndexByID")
else
    Assert(GetQuestID == nil, "private GetQuestID fallback leaked into the global contract")
    Assert(GetQuestLogIndexByID == nil, "private quest-log index fallback leaked into the global contract")
end
Assert(PrivateEnum.PlayerInteractionType ~= nativePlayerInteractionType, "private Enum reused a shared nested enum table")
Assert(PrivateEnum.PlayerInteractionType.NativeHarnessType == 97 and PrivateEnum.PlayerInteractionType.Gossip == 3, "private Enum did not combine native and fallback values")
Assert(nativePlayerInteractionType.Gossip == nil and nativeEnum.QuestFrequency == nil, "enum fallbacks leaked into global Enum")
Assert(IsQuestItemHidden() == 0, "missing IsQuestItemHidden did not use the legacy numeric visible value")
if secureCallMode == "absent" then
    Assert(securecallfunction == nil, "Compatibility.lua manufactured global securecallfunction")
end

local nativeUnitName = UnitName
UnitName = function(unit) return unit == "npc" and "Chromie" or "Player" end
Assert(addon.Legacy.IsExcludedInteraction() == false, "Ascension-only NPC exclusions leaked onto a stock Wrath client")
UnitName = nativeUnitName

local safeCallResultA, safeCallResultB = addon.Legacy.SafeCall(function(a, b)
    return a + b, a * b
end, 6, 7)
Assert(safeCallResultA == 13 and safeCallResultB == 42, "addon.Legacy.SafeCall did not preserve function results")
if secureCallMode == "sentinel" then
    Assert(nativeSecureCallCount == 1, "addon.Legacy.SafeCall did not retain the existing securecallfunction")
else
    Assert(addon.Legacy.SafeCall(false, 1, 2, 3) == nil, "private SafeCall fallback did not reject a non-function safely")
    Assert(nativeSecureCallCount == 0, "private SafeCall fallback unexpectedly used a global secure-call function")
end

local nativeBypassFrame = addon.Legacy.NativeCreateFrame("Frame", "DialogueUINativeBypassHarnessFrame")
local nativeBypassSnapshot = nativeFrameSnapshots[nativeBypassFrame]
Assert(nativeBypassSnapshot, "Legacy.NativeCreateFrame did not call the captured native factory")
Assert(nativeBypassFrame.__DialogueUILegacyCompatible == nil, "Legacy.NativeCreateFrame applied the compatibility wrapper")
Assert(nativeBypassFrame.RegisterEvent == nativeBypassSnapshot.RegisterEvent, "Legacy.NativeCreateFrame wrapped RegisterEvent")
Assert(nativeBypassFrame.SetScript == nativeBypassSnapshot.SetScript, "Legacy.NativeCreateFrame wrapped SetScript")
Assert(nativeBypassFrame.CreateTexture == nativeBypassSnapshot.CreateTexture, "Legacy.NativeCreateFrame wrapped CreateTexture")
Assert(nativeBypassFrame.SetShown == nil and nativeBypassFrame.SetSize == nil, "Legacy.NativeCreateFrame added compatibility methods")
local nativeBypassTexture = nativeBypassFrame:CreateTexture()
Assert(nativeBypassTexture.__DialogueUILegacySetTexture == nil and nativeBypassTexture.SetMaxLines == nil, "Legacy.NativeCreateFrame patched a child region")

local secureButton = addon.Legacy.CreateFrame("Button", "DialogueUISecureHarnessButton", nil, "SecureActionButtonTemplate")
local secureSnapshot = nativeFrameSnapshots[secureButton]
Assert(secureButton == lastNativeSecureFrame and secureSnapshot, "secure action button was not returned directly from native CreateFrame")
Assert(secureButton.__DialogueUILegacyCompatible == nil, "secure action button received the compatibility marker")
Assert(secureButton.__DialogueUILegacyRegisterEvent == nil, "secure action button RegisterEvent was wrapped")
Assert(secureButton.__DialogueUILegacySetScript == nil, "secure action button SetScript was wrapped")
Assert(secureButton.__DialogueUILegacyCreateTexture == nil, "secure action button CreateTexture was wrapped")
Assert(secureButton.RegisterEvent == secureSnapshot.RegisterEvent, "secure action button RegisterEvent identity changed")
Assert(secureButton.UnregisterEvent == secureSnapshot.UnregisterEvent, "secure action button UnregisterEvent identity changed")
Assert(secureButton.UnregisterAllEvents == secureSnapshot.UnregisterAllEvents, "secure action button UnregisterAllEvents identity changed")
Assert(secureButton.IsEventRegistered == secureSnapshot.IsEventRegistered, "secure action button IsEventRegistered identity changed")
Assert(secureButton.SetScript == secureSnapshot.SetScript, "secure action button SetScript identity changed")
Assert(secureButton.CreateTexture == secureSnapshot.CreateTexture, "secure action button CreateTexture identity changed")
Assert(secureButton.CreateFontString == secureSnapshot.CreateFontString, "secure action button CreateFontString identity changed")
Assert(secureButton.SetShown == nil and secureButton.SetSize == nil, "secure action button received compatibility methods")
local secureTexture = secureButton:CreateTexture()
Assert(secureTexture.__DialogueUILegacySetTexture == nil and secureTexture.SetMaxLines == nil, "secure action button child region was patched")

local inherited = addon.Legacy.CreateFrame("Frame", nil, nil, "HarnessTemplate")
Assert(type(inherited.HarnessTexture.SetMaxLines) == "function", "inherited texture/region tree was not patched")
Assert(type(inherited.HarnessTexture.ClearTextureSlice) == "function", "legacy texture slice cleanup fallback is missing")
Assert(type(inherited.HarnessModel.SetModelAlpha) == "function", "inherited model child was not patched")
inherited.HarnessTexture:SetTexture(134400)
Assert(inherited.HarnessTexture.textureArgs[1] == "Interface\\Icons\\INV_Misc_QuestionMark", "numeric texture ID was not redirected")
inherited.HarnessTexture:SetMaxLines(2)
Assert(inherited.HarnessTexture:GetMaxLines() == 2, "SetMaxLines compatibility state was not retained")
Assert(inherited:SetScript("OnGamePadButtonDown", function() end) == false, "invalid script handler was not rejected safely")

local mouseEvents = {}
inherited:SetScript("OnEvent", function(_, event, button)
    mouseEvents[#mouseEvents + 1] = event..":"..tostring(button)
end)
Assert(inherited:RegisterEvent("GLOBAL_MOUSE_DOWN") == true, "pseudo mouse event registration failed")
local updateFrames = {}
for _, frame in ipairs(frames) do
    if frame ~= inherited and frame.scripts.OnUpdate then
        updateFrames[#updateFrames + 1] = frame
    end
end
Assert(#updateFrames > 0, "pseudo mouse dispatcher did not start")
mouseDown.LeftButton = true
for _, frame in ipairs(updateFrames) do
    frame.scripts.OnUpdate(frame, 0.016)
end
Assert(mouseEvents[1] == "GLOBAL_MOUSE_DOWN:LeftButton", "pseudo mouse edge was not dispatched")
inherited:UnregisterAllEvents()

local lifecycleFrame
local xmlCompatibilityFrame
for _, frame in ipairs(frames) do
    if frame.events.QUEST_COMPLETE then lifecycleFrame = frame end
    if frame.events.ADDON_LOADED then xmlCompatibilityFrame = frame end
end
Assert(lifecycleFrame, "legacy lifecycle frame was not created")
Assert(xmlCompatibilityFrame, "XML compatibility frame was not created")

local completionEvent
local completionListener = addon.Legacy.CreateFrame("Frame")
completionListener:SetScript("OnEvent", function(_, event, questID)
    completionEvent = {event, questID}
end)
completionListener:RegisterEvent("QUEST_TURNED_IN")
lifecycleFrame.scripts.OnEvent(lifecycleFrame, "QUEST_COMPLETE")
addon.Legacy.MarkQuestRewardRequested()
questLog = {}
completedQuests[42] = true
lifecycleFrame.scripts.OnEvent(lifecycleFrame, "QUEST_FINISHED")
Assert(completionEvent and completionEvent[1] == "QUEST_TURNED_IN" and completionEvent[2] == 42, "quest turn-in synthesis failed")
Assert(PrivateQuestLog.GetTitleForQuestID(42) == "Harness Quest", "completed quest title cache failed")

lifecycleFrame.scripts.OnEvent(lifecycleFrame, "GOSSIP_SHOW")
local C_GossipInfo = addon.Legacy.C_GossipInfo
Assert(type(C_GossipInfo) == "table", "private gossip facade was not created")
Assert(_G.C_GossipInfo == nativeCGossipInfo, "Compatibility.lua polluted the global C_GossipInfo contract")
local gossipOptions = C_GossipInfo.GetOptions()
Assert(#gossipOptions == 2, "gossip option bridge count failed")
Assert(type(gossipOptions[1].icon) == "string", "legacy gossip icon is not a file path")
C_GossipInfo.SelectOptionByIndex(2)
Assert(selectedGossipOption == 2, "gossip option index bridge failed")
local active = C_GossipInfo.GetActiveQuests()
C_GossipInfo.SelectActiveQuest(active[1].questID)
Assert(selectedGossipActive == 1, "active gossip quest bridge failed")
local available = C_GossipInfo.GetAvailableQuests()
C_GossipInfo.SelectAvailableQuest(available[1].questID)
Assert(selectedGossipAvailable == 1, "available gossip quest bridge failed")

local trivial, frequency, repeatable = addon.Legacy.GetAvailableQuestInfo(1)
Assert(trivial == false and frequency == 0 and repeatable == false, "greeting quest normalization failed")
addon.Legacy.SelectActiveQuest(1)
addon.Legacy.SelectAvailableQuest(1)
Assert(selectedGreetingActive == 1 and selectedGreetingAvailable == 1, "greeting quest selection bridge failed")

DUIQuestFrame = NativeCreateFrame("Frame", "DUIQuestFrame")
DUIQuestFrame.FrontFrame = NativeCreateFrame("Frame", nil, DUIQuestFrame)
DUIQuestFrame.FrontFrame.QuestPortrait = NativeCreateFrame("Frame", nil, DUIQuestFrame.FrontFrame)
DUIQuestFrame.FrontFrame.QuestPortrait.Name = DUIQuestFrame.FrontFrame.QuestPortrait:CreateFontString()
DUIBookFrame = NativeCreateFrame("Frame", "DUIBookFrame")
DUIDialogSettings = NativeCreateFrame("Frame", "DUIDialogSettings")
xmlCompatibilityFrame.scripts.OnEvent(xmlCompatibilityFrame, "ADDON_LOADED", "DialogueUI-Ascension")
Assert(type(DUIQuestFrame.FrontFrame.QuestPortrait.Name.SetMaxLines) == "function", "targeted XML tree was not patched")
Assert(DUIQuestFrame.FrontFrame.QuestPortrait.Name:GetMaxLines() == 2, "quest portrait line limit was not restored")
Assert(unrelatedFrame.RegisterEvent == unrelatedRegisterEvent, "unrelated frame was mutated by XML sweep")

-- Initialization.lua can be exercised independently of the rest of the addon.
-- Start with deliberately corrupt and unsafe legacy values to verify that the
-- database loader restores type-correct defaults and legacy-client-safe modes.
local callbackEvents = {}
addon.CallbackRegistry = {
    Trigger = function(_, event, ...)
        callbackEvents[#callbackEvents + 1] = {event = event, args = {...}}
    end,
}
function GetBuildInfo() return "3.3.5", "12340", "Sep 29 2010", 30300 end

local legacyDatabase = {
    Theme = "corrupt",
    FrameSize = 99,
    FontText = 42,
    RightClickToCloseUI = "corrupt",
    InputDevice = 4,
    CameraMovement = 2,
    HideUI = true,
}
DialogueUI_DB = legacyDatabase
DialogueUI_Saves = nil

local initializationFrameStart = #frames + 1
local initializationChunk = assert(loadfile(addonRoot.."\\Initialization.lua"))
initializationChunk("DialogueUI-Ascension", addon)

local initializationFrame
for index = initializationFrameStart, #frames do
    local frame = frames[index]
    if frame.events.ADDON_LOADED and frame.events.PLAYER_ENTERING_WORLD then
        initializationFrame = frame
        break
    end
end
Assert(initializationFrame and initializationFrame.scripts.OnEvent, "Initialization.lua event frame was not created")
initializationFrame.scripts.OnEvent(initializationFrame, "ADDON_LOADED", "DialogueUI-Ascension")

Assert(DialogueUI_DB == legacyDatabase, "database loader replaced the SavedVariables table")
Assert(type(DialogueUI_Saves) == "table", "secondary SavedVariables table was not initialized")
Assert(DialogueUI_DB.Theme == 1, "wrong-type Theme was not restored to its default")
Assert(DialogueUI_DB.FrameSize == 2, "out-of-range FrameSize was not restored to its default")
Assert(DialogueUI_DB.FontText == "default", "wrong-type FontText was not restored to its default")
Assert(DialogueUI_DB.RightClickToCloseUI == true, "wrong-type boolean was not restored to its default")
Assert(DialogueUI_DB.InputDevice == 1, "legacy database retained an unsupported input device")
Assert(DialogueUI_DB.CameraMovement == 0, "legacy database retained camera movement without exact zoom restoration")
Assert(DialogueUI_DB.HideUI == false, "legacy database retained protected UIParent hiding")

addon.SetDBValue("InputDevice", 4, true)
addon.SetDBValue("CameraMovement", 2, true)
addon.SetDBValue("HideUI", true, true)
Assert(DialogueUI_DB.InputDevice == 1, "SetDBValue enabled an unsupported input device")
Assert(DialogueUI_DB.CameraMovement == 0, "SetDBValue enabled camera movement without exact zoom restoration")
Assert(DialogueUI_DB.HideUI == false, "SetDBValue enabled protected UIParent hiding")
addon.SetDBValue("Theme", 2, true)
Assert(DialogueUI_DB.Theme == 2, "SetDBValue rejected an ordinary setting")

local sawAddonLoaded
local sawThemeChange
for _, callback in ipairs(callbackEvents) do
    if callback.event == "ADDON_LOADED" and callback.args[1] == DialogueUI_DB then
        sawAddonLoaded = true
    elseif callback.event == "SettingChanged.Theme" and callback.args[1] == 2 and callback.args[2] == true then
        sawThemeChange = true
    end
end
Assert(sawAddonLoaded, "database loader did not publish ADDON_LOADED")
Assert(sawThemeChange, "SetDBValue did not publish the ordinary setting change")

print("LegacyCompatibilityHarness (securecallfunction="..secureCallMode.."): PASS")
