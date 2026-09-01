local _, addon = ...
local CreateFrame = addon.Legacy.CreateFrame or CreateFrame;
local C_AddOns = addon.Legacy.C_AddOns or C_AddOns;
local C_Timer = addon.Legacy.C_Timer or C_Timer;
local API = addon.API;
local C_GossipInfo = addon.Legacy.C_GossipInfo or C_GossipInfo;
local MainFrame = addon.DialogueUI;
local IsInteractingWithDialogNPC = API.IsInteractingWithDialogNPC;
local CancelClosingGossipInteraction = API.CancelClosingGossipInteraction;
local QuestIsFromAreaTrigger = API.QuestIsFromAreaTrigger;
local GossipDataProvider = addon.GossipDataProvider;
local QuestGetAutoAccept = API.QuestGetAutoAccept;
local ShouldMuteQuestDetail = API.ShouldMuteQuestDetail;
local CloseQuest = CloseQuest;
local InCombatLockdown = InCombatLockdown;
local IsInInstance = IsInInstance;
local GetQuestID = addon.Legacy.GetQuestID or GetQuestID;
local IsExcludedInteraction = addon.Legacy and addon.Legacy.IsExcludedInteraction;


local EVENT_PROCESS_DELAY = 0.017;          --Affected by CameraMovement
local MAINTAIN_CAMERA_POSITION = false;
local USE_AUTO_QUEST_POPUP = true;
local DISABLE_DUI_IN_INSTANCE = false;
local HANDLE_EVENT_EXTERNALLY = false;      --If true, Events will be handled by Skimmers


local EL = CreateFrame("Frame");
local Muter = {};
local LastInteraction = {};
local SuppressLegacyStockGossip;

local function RecordInteraction(event, result)
    LastInteraction.event = event;
    LastInteraction.result = result;
    LastInteraction.time = GetTime and GetTime() or 0;
    LastInteraction.frameShown = MainFrame and MainFrame.IsShown and MainFrame:IsShown() or false;
end

function addon.GetInteractionDebugState()
    return {
        takeoverActive = Muter.muted == true,
        handledExternally = HANDLE_EVENT_EXTERNALLY == true,
        lastEvent = LastInteraction.event,
        lastResult = LastInteraction.result,
        lastTime = LastInteraction.time,
        frameShown = LastInteraction.frameShown,
        stockGossipShown = GossipFrame and GossipFrame.IsShown and GossipFrame:IsShown() or false,
        gossipFallbackGated = Muter.gossipHandleShowWrapper ~= nil
            and GossipFrame and GossipFrame.HandleShow == Muter.gossipHandleShowWrapper or false,
        stockGossipSuppressionArmed = addon.IS_LEGACY_ASCENSION
            and Muter.muted == true and type(SuppressLegacyStockGossip) == "function" or false,
        stockGossipSuppressions = Muter.stockGossipSuppressions or 0,
    };
end

local function GetCustomGossipHandler()
end

local GossipEvents = {
    "GOSSIP_SHOW", "GOSSIP_CLOSED",
    "CONFIRM_TALENT_WIPE",  --Classic
};

local QuestEvents = {
    "QUEST_PROGRESS",
    "QUEST_DETAIL",
    "QUEST_FINISHED",   --Close QuestFrame
    "QUEST_GREETING",   --Offer several quests
    "QUEST_COMPLETE",   --Talk to turn in quest
};

local MapEvents = {
    PLAYER_ENTERING_WORLD = true,
    ZONE_CHANGED_NEW_AREA = true,
};

local CloseDialogEvents = {};

local ExcludedInteractionEvents = {
    GOSSIP_SHOW = true,
    QUEST_GREETING = true,
    QUEST_DETAIL = true,
    QUEST_PROGRESS = true,
    QUEST_COMPLETE = true,
};

if not addon.IsToCVersionEqualOrNewerThan(50000) then
    local ClassicEvents = {
        "CONFIRM_TALENT_WIPE",
    };

    for _, event in ipairs(ClassicEvents) do
        table.insert(GossipEvents, event);
        CloseDialogEvents[event] = true;
    end
end

local DeclinedQuests = {};

local function FlagQuestDeclined()
    local questID = GetQuestID();
    if questID and questID ~= 0 then
        if DeclinedQuests[questID] then
            DeclinedQuests[questID] = DeclinedQuests[questID] + 1;
        else
            DeclinedQuests[questID] = 1;
        end
    end
end
addon.FlagQuestDeclined = FlagQuestDeclined;

API.AddCustomLinkType("UnblockQuest", function(questID)
    questID = questID and tonumber(questID);
    if questID and DeclinedQuests[questID] then
        DeclinedQuests[questID] = nil;
        API.PrintMessage(addon.L["Quest Unblocked Alert"]);
    end
end);

local function GetQuestDeclinedTimes()
    -- Only affect area triggered quests
    local questID = GetQuestID();
    if questID and questID ~= 0 then
        return DeclinedQuests[questID]
    end
end

local function ShouldMuteQuest()
    local questID = GetQuestID();
    return ShouldMuteQuestDetail(questID)
end

function EL:OnManualEvent(event, ...)
    self:SetScript("OnUpdate", nil);

    if event == "QUEST_FINISHED" or event == "QUEST_FINISHED_FORCED" then
        --For the issue where the quest window fails to close:
        --Sometimes QUEST_FINISHED fires but IsInteractingWithNpcOfType still thinks we are interacting with QuestGiver
        --/dump C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.QuestGiver)
        --print(event, "IS INTERACTING", IsInteractingWithDialogNPC(), GetTimePreciseSec())   --debug
        if (event == "QUEST_FINISHED_FORCED") or (not IsInteractingWithDialogNPC()) then
            self.timeSinceQuestFinish = nil;
            MainFrame:HideUI();
        end
    elseif event == "GOSSIP_SHOW" then
        MainFrame:ShowUI(event);
    elseif event == "GOSSIP_CLOSED" then
        self:OnGossipClosed(...);
    end
end

function EL:OnGossipClosed(interactionIsContinuing)
    if self.customFrame then
        local f = self.customFrame;
        self.customFrame = nil;
        if not InCombatLockdown() then
            HideUIPanel(f);
        end
        return
    end

    if not IsInteractingWithDialogNPC() then
        if not MainFrame:IsGossipCloseConsumed() then
            --MainFrame:SetInteractionIsContinuing(interactionIsContinuing);
            self.timeSinceQuestFinish = nil;
            MainFrame:HideUI();
        end
        GossipDataProvider:OnInteractStopped();
    end
end

function EL:NegateLastEvent(event)
    if event == self.lastEvent then
        self.lastEvent = nil;
    end
end

function EL:OnEvent(event, ...)
    if HANDLE_EVENT_EXTERNALLY then
        RecordInteraction(event, "handled externally");
        return
    end

    if ExcludedInteractionEvents[event] and IsExcludedInteraction and IsExcludedInteraction() then
        -- Custom Ascension boards and scripted panels emit Blizzard quest
        -- events without a normal NPC contract. Leave those owners untouched.
        if MainFrame:IsShown() then
            MainFrame.interactionIsContinuing = true;
            MainFrame:Hide();
        end
        self.lastEvent = nil;
        RecordInteraction(event, "excluded interaction");
        return
    end

    --print(event, GetTimePreciseSec(), ...);    --debug

    if event == "GOSSIP_SHOW" then
        self.lastEvent = event;
        local handler = GetCustomGossipHandler(...);
        if handler then
            self.customFrame = handler(...);
        else
            if self:ThrottleGossipEvent() then
                GossipDataProvider:OnInteractWithNPC();
                MainFrame:ShowUI(event);    --Depends on the options, we may select the non-gossip one directly without openning the UI
                CancelClosingGossipInteraction();
                RecordInteraction(event, MainFrame:IsShown() and "shown" or "no eligible dialogue data");
            else
                RecordInteraction(event, "throttled duplicate");
            end
        end

        -- Ascension may show the stock GossipFrame from a separate manager
        -- after every GOSSIP_SHOW listener has run.  Remove that duplicate on
        -- the next update without closing the live gossip interaction.
        if SuppressLegacyStockGossip then
            SuppressLegacyStockGossip(true);
        end

        self:NegateLastEvent(event);

    elseif event == "GOSSIP_CLOSED" then
        self.lastEvent = event;
        self:ProcessEventNextUpdate(0.1);
        --self:OnGossipClosed(...);

    elseif event == "QUEST_FINISHED" then
        --When the quest giver has more than one quest
        --sometimes there is a delay between QUEST_FINISHED and GOSSIP_SHOW (presumably depends on various of factors including latency)
        --the game determinates interaction then re-engage, messing up ActionCam and gossip info
        --our workaround is setting s delay to this event
        --print(event, GetTimePreciseSec(), IsInteractingWithDialogNPC());

        local delay = MainFrame:GetQuestFinishedDelay();

        self.timeSinceQuestFinish = -delay;

        if self.lastEvent ~= "QUEST_FINISHED_FORCED" then
            self.lastEvent = event;
            self:ProcessEventNextUpdate(delay);
        end

    elseif event == "QUEST_DETAIL" then
        --Can fire multiple times in rare occasions, possibly due to cross-character progress

        if ShouldMuteQuest() then
            if API.IsQuestAutoAccepted() then
                API.AcknowledgeAutoAcceptQuest();
            end
            CloseQuest();
            return
        end

        self.lastEvent = event;

        local questStartItemID = ...

        if USE_AUTO_QUEST_POPUP and questStartItemID and questStartItemID ~= 0 then
			addon.WidgetManager:AddAutoQuestPopUp(questStartItemID);
            CloseQuest();
            return
		end

        if QuestIsFromAreaTrigger() then
            local declinedTimes = GetQuestDeclinedTimes();
            if declinedTimes then
                if declinedTimes == 1 then
                    local isReroutedQuest = true;
                    addon.WidgetManager:AddAutoQuestPopUp(nil, isReroutedQuest);
                else
                    FlagQuestDeclined();
                    if declinedTimes < 3 then
                        API.ShowBlockedQuestMessage(GetQuestID());
                    end
                    CloseQuest();
                end
                return
            elseif USE_AUTO_QUEST_POPUP and (QuestGetAutoAccept() or InCombatLockdown()) then
                --"QuestIsFromAreaTrigger" and "QuestGetAutoAccept" Doesn't work in Classic
                --Some quests that triggered upon login aren't "QuestIsFromAreaTrigger"
                addon.WidgetManager:AddAutoQuestPopUp();
                CloseQuest();
                return
            end
        end

        MainFrame:ShowUI(event, questStartItemID);

    elseif event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" or event == "QUEST_GREETING" then
        --Sometimes QUEST_FINISHED fires before QUEST_COMPLETE
        self.lastEvent = event;
        MainFrame:ShowUI(event);

    elseif CloseDialogEvents[event] then
        self.lastEvent = event;
        self.timeSinceQuestFinish = nil;
        MainFrame:HideUI();

    elseif MapEvents[event] then
        if DISABLE_DUI_IN_INSTANCE then
            Muter:UpdateForInstance();
        end
    end
end

function EL:ListenEvents(state)
    local method;

    if state then
        method = "RegisterEvent";
        self:SetScript("OnEvent", self.OnEvent);
    else
        method= "UnregisterEvent";
        if DISABLE_DUI_IN_INSTANCE then
            self:SetScript("OnEvent", self.OnEvent);
        else
            self:SetScript("OnEvent", nil);
        end
    end

    for _, event in ipairs(GossipEvents) do
        self[method](self, event);
    end

    for _, event in ipairs(QuestEvents) do
        self[method](self, event);
    end

    --self[method](self, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW");    --debug
    --self[method](self, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE");
end

function EL:OnUpdate(elapsed)
    if self.timeSinceQuestFinish then
        self.timeSinceQuestFinish = self.timeSinceQuestFinish + elapsed;
        if self.timeSinceQuestFinish > EVENT_PROCESS_DELAY then
            self.timeSinceQuestFinish = nil;
            if self.lastEvent == "QUEST_FINISHED" or self.lastEvent == "QUEST_FINISHED_FORCED" then
                if not IsInteractingWithDialogNPC() then
                    --print("COUNTER STOP", UnitExists("npc"))
                    self.processEvent = nil;
                    self.lastEvent = nil;
                    MainFrame:HideUI();
                end
            end
        end
    end

    if self.processEvent then
        self.t = self.t + elapsed;

        if self.t > EVENT_PROCESS_DELAY then
            self.t = 0;
            self.processEvent = nil;
            if self.lastEvent then
                --print("LAST EVENT", self.lastEvent)
                self:OnManualEvent(self.lastEvent);
                self.lastEvent = nil;
            end
        end
    end

    if self.pauseGossip then
        self.pauseGossip = self.pauseGossip + elapsed;
        if self.pauseGossip >= 0 then
            self.pauseGossip = nil;
        end
    end

    if not (self.processEvent or self.pauseGossip) then
        self:SetScript("OnUpdate", nil);
    end
end

function EL:ThrottleGossipEvent()
    if not self.pauseGossip then
        self.pauseGossip = 0.016;
        self:SetScript("OnUpdate", self.OnUpdate);
        return true
    end

    return false
end

function EL:ProcessEventNextUpdate(customDelay)
    customDelay = customDelay or 0;
    self.t = -customDelay;
    self.processEvent = true;
    self:SetScript("OnUpdate", self.OnUpdate);
end

do
    local DEFAULT_CAMERA_MODE = 1;

    local function OnCameraModeChanged(_, mode)
        if mode == 0 then   --0: No Zoom
            EVENT_PROCESS_DELAY = 0.017;
        elseif mode == 1 then   --1: Zoom to NPC
            if MAINTAIN_CAMERA_POSITION then
                EVENT_PROCESS_DELAY = 0.5;
            else
                EVENT_PROCESS_DELAY = 0.017;
            end
        elseif mode == 2 then   --2: Shift camear horizontally
            EVENT_PROCESS_DELAY = 0.5;
        end
        DEFAULT_CAMERA_MODE = mode;
    end

    addon.CallbackRegistry:Register("Camera.ModeChanged", OnCameraModeChanged, EL);

    local function Settings_CameraMovement1MaintainPosition(dbValue)
        MAINTAIN_CAMERA_POSITION = dbValue == true;
        if DEFAULT_CAMERA_MODE then
            OnCameraModeChanged(nil, DEFAULT_CAMERA_MODE);
        end
    end
    addon.CallbackRegistry:Register("SettingChanged.CameraMovement1MaintainPosition", Settings_CameraMovement1MaintainPosition);

    local function ManualTriggerQuestFinished(isAutoComplete)
        --print("TRIGGER FINISH", GetTimePreciseSec())      --debug
        if EL.lastEvent ~= "QUEST_FINISHED_FORCED" then
            EL.lastEvent = "QUEST_FINISHED_FORCED";
            EL:ProcessEventNextUpdate(1.5);                 --Force trigger QUEST_FINISHED event to close the UI. We use extended delay (1s) due to unavailable server latency
        end
    end
    addon.CallbackRegistry:Register("TriggerQuestFinished", ManualTriggerQuestFinished);

    local function Settings_AutoQuestPopup(dbValue)
        USE_AUTO_QUEST_POPUP = dbValue ~= false;
    end
    addon.CallbackRegistry:Register("SettingChanged.AutoQuestPopup", Settings_AutoQuestPopup);
end

do  --Unlisten events from default UI
    -- CustomGossipFrameManager owns Ascension item-driven panels such as the
    -- Travel Permit.  Legacy DialogueUI never hides UIParent, so it must not
    -- unregister this manager: doing so leaves those panels with no listener.


    Muter.questEvents = {
        QUEST_GREETING = true,
        QUEST_DETAIL = true,
        QUEST_PROGRESS = true,
        QUEST_COMPLETE = true,
        QUEST_FINISHED = true,
        QUEST_ITEM_UPDATE = true,
        QUEST_LOG_UPDATE = true,
        UNIT_PORTRAIT_UPDATE = true,
        PORTRAITS_UPDATED = true,
    };

    if addon.IsToCVersionEqualOrNewerThan(50000) then
        Muter.questEvents.LEARNED_SPELL_IN_SKILL_LINE = true;
    else
        Muter.questEvents.LEARNED_SPELL_IN_TAB = true;            --Classic
    end

    local function SuspendRegisteredEvents(frame, events)
        local saved = {};
        if not frame then
            return saved;
        end
        for event, enabled in pairs(events) do
            if enabled then
                local ok, registered = pcall(frame.IsEventRegistered, frame, event);
                if ok and registered then
                    saved[event] = true;
                    pcall(frame.UnregisterEvent, frame, event);
                end
            end
        end
        return saved;
    end

    local function MergeSavedEvents(saved, added)
        saved = saved or {};
        for event in pairs(added or {}) do
            saved[event] = true;
        end
        return saved;
    end

    local function RestoreRegisteredEvents(frame, saved)
        if not frame or not saved then
            return;
        end
        for event in pairs(saved) do
            pcall(frame.RegisterEvent, frame, event);
        end
    end

    SuppressLegacyStockGossip = function(defer)
        if not addon.IS_LEGACY_ASCENSION or not Muter.muted or not GossipFrame then
            return;
        end

        local function HideStockFrameSafely()
            if not Muter.muted or not GossipFrame
                or not GossipFrame.IsShown or not GossipFrame:IsShown() then
                return;
            end

            -- Stock 3.3.5 GossipFrame calls CloseGossip() from OnHide.  Hiding
            -- it normally would terminate the same interaction DialogueUI is
            -- displaying.  Remove only that script for the synchronous hide,
            -- then restore the exact handler immediately.
            local okScript, onHide = pcall(GossipFrame.GetScript, GossipFrame, "OnHide");
            if not okScript then
                return;
            end
            local cleared = pcall(GossipFrame.SetScript, GossipFrame, "OnHide", nil);
            if not cleared then
                return;
            end

            if HideUIPanel then
                pcall(HideUIPanel, GossipFrame);
            end
            if GossipFrame:IsShown() then
                pcall(GossipFrame.Hide, GossipFrame);
            end
            pcall(GossipFrame.SetScript, GossipFrame, "OnHide", onHide);

            if not GossipFrame:IsShown() then
                Muter.stockGossipSuppressions = (Muter.stockGossipSuppressions or 0) + 1;
            end
        end

        HideStockFrameSafely();
        if defer and C_Timer and C_Timer.After then
            C_Timer.After(0, HideStockFrameSafely);
        end
    end

    local gossipFrameEvents = {
        GOSSIP_SHOW = true,
        GOSSIP_CLOSED = true,
        QUEST_LOG_UPDATE = true,
    };

    local customGossipEvents = {
        GOSSIP_SHOW = true,
        GOSSIP_CLOSED = true,
    };
    local hideQuestFrame = true;    --false when we do debug

    local function GateLegacyGossipFallback()
        if not addon.IS_LEGACY_ASCENSION or not GossipFrame then
            return;
        end

        local current = GossipFrame.HandleShow;
        if current == Muter.gossipHandleShowWrapper then
            return;
        end
        if type(current) ~= "function" then
            return;
        end

        -- CustomGossipFrameManager must remain registered because it owns
        -- Ascension-only panels such as the Travel Permit.  Its unhandled
        -- fallback calls GossipFrame:HandleShow() directly, bypassing the
        -- stock frame's muted events.  Gate only that fallback while DUI owns
        -- the interaction; custom handlers continue to run normally.
        local original = current;
        local wrapper = function(self, ...)
            if Muter.muted then
                return;
            end
            return original(self, ...);
        end;

        Muter.gossipHandleShowOriginal = original;
        Muter.gossipHandleShowWrapper = wrapper;
        GossipFrame.HandleShow = wrapper;
    end

    local function RestoreLegacyGossipFallback()
        if addon.IS_LEGACY_ASCENSION and GossipFrame
            and GossipFrame.HandleShow == Muter.gossipHandleShowWrapper then
            GossipFrame.HandleShow = Muter.gossipHandleShowOriginal;
        end
        Muter.gossipHandleShowOriginal = nil;
        Muter.gossipHandleShowWrapper = nil;
    end

    local function SetUseDialogueUI(state)
        if state == nil then state = true end;

        if state then
            if Muter.muted then
                -- Refresh the gate in case Ascension or another addon supplied
                -- HandleShow or registered events after the first takeover.
                GateLegacyGossipFallback();
                if not addon.IS_LEGACY_ASCENSION then
                    Muter.customGossipEvents = MergeSavedEvents(Muter.customGossipEvents,
                        SuspendRegisteredEvents(CustomGossipFrameManager, customGossipEvents));
                end
                Muter.gossipFrameEvents = MergeSavedEvents(Muter.gossipFrameEvents,
                    SuspendRegisteredEvents(GossipFrame, gossipFrameEvents));
                if hideQuestFrame then
                    Muter.questFrameEvents = MergeSavedEvents(Muter.questFrameEvents,
                        SuspendRegisteredEvents(QuestFrame, Muter.questEvents));
                end
                SuppressLegacyStockGossip(true);
                return;
            end
            Muter.muted = true;
            GateLegacyGossipFallback();
            EL:ListenEvents(true);

            if not addon.IS_LEGACY_ASCENSION then
                Muter.customGossipEvents = SuspendRegisteredEvents(CustomGossipFrameManager, customGossipEvents);
            end
            Muter.gossipFrameEvents = SuspendRegisteredEvents(GossipFrame, gossipFrameEvents);
            SuppressLegacyStockGossip(true);

            if hideQuestFrame then
                -- Preserve unrelated Blizzard behavior and make restoration
                -- exact: only mute the quest events this replacement owns.
                Muter.questFrameEvents = SuspendRegisteredEvents(QuestFrame, Muter.questEvents);
            else
                QuestFrame:SetParent(nil);
                QuestFrame:SetScale(2/3);
            end

        elseif Muter.muted then
            Muter.muted = false;
            RestoreLegacyGossipFallback();
            EL:ListenEvents(false);

            if not addon.IS_LEGACY_ASCENSION then
                RestoreRegisteredEvents(CustomGossipFrameManager, Muter.customGossipEvents);
            end
            RestoreRegisteredEvents(GossipFrame, Muter.gossipFrameEvents);
            Muter.customGossipEvents = nil;
            Muter.gossipFrameEvents = nil;

            if hideQuestFrame then
                RestoreRegisteredEvents(QuestFrame, Muter.questFrameEvents);
                Muter.questFrameEvents = nil;
            else
                QuestFrame:SetParent(UIParent);
                QuestFrame:SetScale(1);
            end
        end

        addon.EnableBookUI(state);
        if addon.IS_LEGACY_ASCENSION then
            addon.CallbackRegistry:Trigger(state and "DialogueUI.LegacyTakeover" or "DialogueUI.LegacyRelease");
        end
    end
    addon.SetUseDialogueUI = SetUseDialogueUI;

    local function EnableDialogueUIAfterValidation()
        local ready = MainFrame
            and MainFrame.ShowUI
            and MainFrame.HideUI
            and C_GossipInfo
            and C_GossipInfo.GetOptions
            and C_GossipInfo.SelectOptionByIndex
            and GetTitleText
            and GetQuestText
            and GetProgressText
            and GetRewardText;

        if not ready then
            pcall(SetUseDialogueUI, false);
            API.PrintMessage("Dialogue UI - Ascension", "Compatibility self-test failed; Blizzard quest UI was restored.");
            return
        end

        local ok, message = pcall(SetUseDialogueUI, true);
        if not ok then
            pcall(SetUseDialogueUI, false);
            API.PrintMessage("Dialogue UI - Ascension", "Startup failed safely: "..tostring(message));
        end
    end

    addon.CallbackRegistry:Register("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(0, EnableDialogueUIAfterValidation);
    end, Muter);

    function Muter:UpdateForInstance()
        if IsInInstance() then
            SetUseDialogueUI(false);
        else
            SetUseDialogueUI(true);
        end
    end

    local function Settings_DisableDUIInInstance(dbValue, userInput)
        DISABLE_DUI_IN_INSTANCE = dbValue == true;
        if DISABLE_DUI_IN_INSTANCE then
            for event in pairs(MapEvents) do
                EL:RegisterEvent(event);
            end
            Muter:UpdateForInstance();
            if userInput and IsInInstance() and MainFrame:IsShown() then
                MainFrame:Hide();
            end
        else
            for event in pairs(MapEvents) do
                EL:UnregisterEvent(event);
            end
            SetUseDialogueUI(true);
        end
    end
    addon.CallbackRegistry:Register("SettingChanged.DisableDUIInInstance", Settings_DisableDUIInInstance);
end

do  --See Blizzard_UIPanels_Game/CustomGossipFrameBase.lua
	local function HandleNPEGuideGossipShow(textureKit)
		C_AddOns.LoadAddOn("Blizzard_NewPlayerExperienceGuide");
		ShowUIPanel(GuideFrame);
		return GuideFrame
	end

	local function HandleTorghastLevelPickerGossipShow(textureKit)
		C_AddOns.LoadAddOn("Blizzard_TorghastLevelPicker");
		TorghastLevelPickerFrame:TryShow(textureKit)
		return TorghastLevelPickerFrame
	end

    local function HandleDelvesDifficultyPickerGossipShow(textureKit)   --TWW
		C_AddOns.LoadAddOn("Blizzard_DelvesDifficultyPicker");
		DelvesDifficultyPickerFrame:TryShow(textureKit);
		return DelvesDifficultyPickerFrame
	end

    local Handlers = {};

    function EL:RegisterHandler(textureKit, func)
        Handlers[textureKit] = func;
    end

	function EL:RegisterCustomGossipFrames()
		self:RegisterHandler("npe-guide", HandleNPEGuideGossipShow);
		self:RegisterHandler("skoldushall", HandleTorghastLevelPickerGossipShow);
		self:RegisterHandler("mortregar", HandleTorghastLevelPickerGossipShow);
		self:RegisterHandler("coldheartinterstitia", HandleTorghastLevelPickerGossipShow);
		self:RegisterHandler("fracturechambers", HandleTorghastLevelPickerGossipShow);
		self:RegisterHandler("soulforges", HandleTorghastLevelPickerGossipShow);
		self:RegisterHandler("theupperreaches", HandleTorghastLevelPickerGossipShow);
		self:RegisterHandler("twistingcorridors", HandleTorghastLevelPickerGossipShow);
        self:RegisterHandler("delves-difficulty-picker", HandleDelvesDifficultyPickerGossipShow);   --For some reason this textureKit is sometimes nil, causing issue
	end
    EL:RegisterCustomGossipFrames();

    function GetCustomGossipHandler(textureKit)
        return textureKit and Handlers[textureKit]
    end
    addon.GetCustomGossipHandler = GetCustomGossipHandler;
end

do  --DEBUG Skimmer
    local function SetHandleEventExternally(state)
        HANDLE_EVENT_EXTERNALLY = state == true;
    end
    addon.SetHandleEventExternally = SetHandleEventExternally;
end
