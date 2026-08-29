-- Narrator (Use VoiceC for Quest objective, <Enclosed Text>) is contributed by https://github.com/BelegCufea

local _, addon = ...
local CreateFrame = addon.Legacy.CreateFrame or CreateFrame;
local C_Timer = addon.Legacy.C_Timer or C_Timer;
local Enum = addon.Legacy.Enum or Enum;
local CallbackRegistry = addon.CallbackRegistry;
local GetDBBool = addon.GetDBBool;
local L = addon.L;
local IsShiftDown = addon.DeviceUtil.IsShiftDown;

local TTSUtil = CreateFrame("Frame");
addon.TTSUtil = TTSUtil;

local FALLBACK_VOICE_ID = 0;
local DESTINATION = 1;   --Local playback on Ascension 3.3.5.12340
local UNKNOWN_TEXT = _G.UNKNOWN or "Unknown";
local SAMPLE_TEXT = _G.TEXT_TO_SPEECH_SAMPLE_TEXT or "This is a text to speech sample.";

-- User Settings
local TTS_AUTO_PLAY = false;
local TTS_STOP_WHEN_LEAVING = true;
local TTS_STOP_ON_NEW = true;         --stop reading previous quest when new quest is available
local TTS_CONTENT_QUEST_TITLE = true;
local TTS_CONTENT_SPEAKER = false;
local TTS_CONTENT_OBJECTIVE = false;  --read objectives
local TTS_USE_NARRATOR = false;       --use narrator voice
local TTS_SKIP_RECENT = false;        --skp reading recently read quest dialogs
local TTS_HISTORY_DEPTH = 20;         --number of quest dialogs that will be skipped
------------------

local TTSFlags = {
    Translation = -1,
    Gossip = 0,
    QuestText = 1,
    QuestTitle = 2,
    QuestObjective = 3,
};
addon.TTSFlags = TTSFlags;


local UnitExists = UnitExists;
local UnitSex = UnitSex;
local VoiceChat = type(_G.C_VoiceChat) == "table" and _G.C_VoiceChat or nil;
local TTSSettings = type(_G.C_TTSSettings) == "table" and _G.C_TTSSettings or nil;
local After = C_Timer and C_Timer.After;
local gsub = string.gsub;

if type(After) ~= "function" then
    After = function(_, callback)
        if type(callback) == "function" then
            callback();
        end
    end;
end

local TTSButtons = {};      --DialogueUI, BookUI
local TTSButtonMixin = {};


-- GetSpeechVoiceID is deliberately part of the capability check: Compatibility.lua
-- does not synthesize it, so a no-op C_VoiceChat facade cannot be mistaken for the
-- native Ascension TTS extension.
local TTS_SUPPORTED = VoiceChat
    and TTSSettings
    and type(VoiceChat.SpeakText) == "function"
    and type(VoiceChat.StopSpeakingText) == "function"
    and type(VoiceChat.GetTtsVoices) == "function"
    and type(TTSSettings.GetSpeechVoiceID) == "function"
    and type(TTSSettings.GetSpeechRate) == "function"
    and type(TTSSettings.GetSpeechVolume) == "function";

TTSUtil.isSupported = TTS_SUPPORTED and true or false;

local function CallGetter(getter, fallback)
    if type(getter) == "function" then
        local success, value = pcall(getter);
        if success and value ~= nil then
            return value
        end
    end
    return fallback
end

local function GetSystemVoiceID()
    return CallGetter(TTSSettings and TTSSettings.GetSpeechVoiceID, FALLBACK_VOICE_ID);
end

local function GetSpeechRate()
    return CallGetter(TTSSettings and TTSSettings.GetSpeechRate, 0);
end

local function GetSpeechVolume()
    return CallGetter(TTSSettings and TTSSettings.GetSpeechVolume, 100);
end

local function GetTtsVoices()
    if not TTS_SUPPORTED then
        return {};
    end

    local success, voices = pcall(VoiceChat.GetTtsVoices);
    if success and type(voices) == "table" then
        return voices
    end
    return {};
end

local function SpeakText(voiceID, text, rate, volume)
    if not TTS_SUPPORTED or type(text) ~= "string" or text == "" then
        return nil;
    end

    -- Ascension's documented signature is
    -- SpeakText(voiceID, text, destination, rate, volume).
    local success, utteranceID = pcall(VoiceChat.SpeakText, voiceID, text, DESTINATION, rate, volume);
    if success and type(utteranceID) == "number" then
        return utteranceID
    end
    return nil;
end

local function StopSpeakingText()
    if TTS_SUPPORTED then
        pcall(VoiceChat.StopSpeakingText);
    end
end


local function AdjustTextForTTS(text)
    text = gsub(text, "[<>]", "");      --any "<>" as TTS has problems reading it
    text = gsub(text, "%-%-", ". ");    --"--" is used as an explanation but TTS treat them as a single word
    return text
end

function TTSUtil:UpdateTTSSettings()
    self.voiceID = GetSystemVoiceID();
    self.volume = self.defaultVolume or GetSpeechVolume();   --0 ~ 100 (Default: 100)
    self.rate = self.defaultRate or GetSpeechRate();          ---10 ~ +10 (Default: 0)
    self.destination = DESTINATION;
end

function TTSUtil:OnUpdate_InitialDelay(elapsed)
    self.t = self.t + elapsed;
    if self.t > 0 then
        self.t = nil;
        self:SetScript("OnUpdate", nil);
        self:ProcessQueue();
    end
end

function TTSUtil:UnregisterPlaybackEvents()
    self:UnregisterEvent("VOICE_CHAT_TTS_PLAYBACK_STARTED");
    self:UnregisterEvent("VOICE_CHAT_TTS_PLAYBACK_FINISHED");
    self:UnregisterEvent("VOICE_CHAT_TTS_PLAYBACK_FAILED");
end

function TTSUtil:FinishPlayback(continuePlayback)
    local contentSource = self.contentSource;
    self.utteranceID = nil;
    self.pendingUtteranceID = nil;
    self.playbackStarted = nil;
    self:UnregisterPlaybackEvents();

    for _, button in ipairs(TTSButtons) do
        button.AnimWave:Stop();
    end

    if continuePlayback then
        if contentSource == "dialogue" then
            self:ProcessQueue();
        elseif contentSource == "book" then
            self:RequestReadNextBookLine();
        end
    end
end

function TTSUtil:TryStopSpeaking()
    if self:IsSpeaking() then
        StopSpeakingText();
        -- Ascension can omit FINISHED after an interrupted utterance.  Clear our
        -- state immediately and ignore a late event for the old utterance.
        self:FinishPlayback(false);
    end
end

function TTSUtil:Clear()
    self.t = nil;
    self.queue = nil;
    self.nextSegment = nil;
    self:SetScript("OnUpdate", nil);
    self:TryStopSpeaking();
end

function TTSUtil:ProcessQueue()
    if self.queue and #self.queue > 0 then
        -- just return and wait for "VOICE_CHAT_TTS_PLAYBACK_FINISHED" that will trigger next ProcessQueue
        if self:IsSpeaking() then
            return
        end

        local segment = table.remove(self.queue, 1);
        self:StopThenPlay(segment);

        if TTS_AUTO_PLAY and GetDBBool("TTSAutoPlayDelay") then
            self.t = -2;
        end
    else
        self:Clear();
    end
end

-- Added voice for the text to be read with and some identifier for dialog the text belong to as there could be more segments of text to be read from the same quest
function TTSUtil:QueueText(text, voiceID, identifier, contentSource)
    --"identifier" determines which quest/gossip the queued text belongs to

    if not TTS_SUPPORTED or type(text) ~= "string" or text == "" then
        return
    end

    -- if "Stop reading on opening dialod" is enabled
    if TTS_STOP_ON_NEW then
        -- remove every entry from speech queue that does not belong to the same quest
        if self.queue then
            for i = #self.queue, 1, -1 do
                if self.queue[i].identifier ~= identifier then
                    table.remove(self.queue, i)
                end
            end
        end

        -- if TTS is currently reading and currentle read segment (self.nextSegment) does not belog to the same quest, stop reading
        if self:IsSpeaking() and self.nextSegment and self.nextSegment.identifier ~= identifier then
            self:TryStopSpeaking();
        end
    end

    if not self.queue then
        self.queue = {};
    end

    -- insert new entry into queue
    for _, segment in ipairs(self.queue) do
        if segment.text == text then
            return
        end
    end

    local segment = { text = text, voiceID = voiceID, identifier = identifier, contentSource = contentSource };
    table.insert(self.queue, segment);
    self.t = -0.75;
    self:SetScript("OnUpdate", self.OnUpdate_InitialDelay);
end

function TTSUtil:OnUpdate_StopThenPlay(elapsed)
    self.t = self.t + elapsed;
    if self.t > 0 then
        self.t = nil;
        self:SetScript("OnUpdate", nil);
        self:SpeakText(self.nextSegment);
    end
end

function TTSUtil:StopThenPlay(segment)
    self:TryStopSpeaking();
    self.t = -0.1;
    self.nextSegment = segment;
    self:SetScript("OnUpdate", self.OnUpdate_StopThenPlay);
end

function TTSUtil:GetVoiceIDForNPC()
    local voiceID;
    --added questnpc for remote quests
    if UnitExists("questnpc") or UnitExists("npc") then
        local unitSex = UnitSex("questnpc") or UnitSex("npc")
        if unitSex == 2 then
            voiceID = self:GetDefaultVoiceA();
        elseif unitSex == 3 then
            voiceID = self:GetDefaultVoiceB();
        end
    end

    if not voiceID then
        if TTS_USE_NARRATOR then
            voiceID = self:GetDefaultVoiceC();
        else
            voiceID = self:GetDefaultVoiceB();
        end
    end
    return voiceID or 0
end

function TTSUtil:SpeakText(segment)
    if not TTS_SUPPORTED or not segment or type(segment.text) ~= "string" or segment.text == "" then
        return false
    end

    self:UpdateTTSSettings();
    self.contentSource = segment.contentSource;
    self:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_STARTED");
    self:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FINISHED");
    self:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FAILED");

    local voiceID = self:ResolveVoiceID(segment.voiceID);
    local utteranceID = SpeakText(voiceID, segment.text, self.rate, self.volume);
    if not utteranceID then
        self:FinishPlayback(true);
        return false
    end

    -- SpeakText returns the utterance ID before the asynchronous STARTED event.
    -- Tracking it immediately also lets the user stop speech during synthesis.
    self.pendingUtteranceID = utteranceID;
    self.utteranceID = utteranceID;
    return true
end

function TTSUtil:ReadCurrentDialogue(fromAutoPlay)
    if self:DoesExternalVoiceoverExist() then
        self:StopLastTTS();
        self:RequestPlayingVoiceoverExternal(fromAutoPlay);
        return
    end

    if not TTS_SUPPORTED then
        return
    end

    local contentSource = "dialogue";
    self.contentSource = contentSource;

    local content = addon.DialogueUI:GetContentForTTS();
    local voiceID = self:GetVoiceIDForNPC();
    local voiceIDNarrator = self:GetDefaultVoiceC();

    local identifier = content.body;

    -- self.forceRead is set only when player clicks on the Play TTS button on the dialog
    -- well, if player wants to skip recent texts and has autoplay enabled ...
    if self.forceRead or (TTS_SKIP_RECENT and TTS_AUTO_PLAY) then
        if not self.history then
            self.history = { identifier };
        else
            --search fif the same text was read recently
            local found = false;
            for _, v in ipairs(self.history) do
                if v == identifier then
                    found = true;
                    break;
                end
            end
            --insert it into self.history
            table.insert(self.history, identifier)
            --remove older entries
            while #self.history > TTS_HISTORY_DEPTH do
                table.remove(self.history, 1)
            end
            -- if found and player didn't press the play button manually then return
            if found and not self.forceRead then return end
        end
        self.forceRead = nil;
    end
    --if player wants to use narrator and the current voice is not narrator, queue different parts of quest for reading
    if TTS_USE_NARRATOR and voiceID ~= voiceIDNarrator then
        if TTS_CONTENT_QUEST_TITLE and content.title then   --Quest Title
            -- don't repeat quest title
            if not self.previousTitle or (self.previousTitle ~= content.title) then
                self:QueueText(content.title.."\n", voiceIDNarrator, identifier, contentSource);
            end
            self.previousTitle = content.title;
        end
        if TTS_CONTENT_SPEAKER and content.speaker then     --NPC name
            -- don't repeat NPC name
            if not self.previousSpeaker or (self.previousSpeaker ~= content.speaker) then
                self:QueueText(content.speaker.."\n", voiceIDNarrator, identifier, contentSource);
            end
            self.previousSpeaker = content.speaker;
        end
        if content.body then
            --for body (trim any spaces), search any text inside <> and queue it as narrator, otherwise use actor voiceID
            local text = content.body:match("^%s*(.-)%s*$");
            local narrate = text:sub(1, 1) == "<";
            for segment in string.gmatch(text, "([^<>]+)") do
                if narrate then
                    self:QueueText(segment, voiceIDNarrator, identifier, contentSource);
                else
                    self:QueueText(segment, voiceID, identifier, contentSource);
                end
                narrate = not narrate;
            end
        end
        if TTS_CONTENT_OBJECTIVE and content.objective then --Objective
            self:QueueText(content.objective, voiceIDNarrator, identifier, contentSource);
        end
    else
        local text = content.body or "";

        if TTS_CONTENT_QUEST_TITLE and content.title then   --Quest Title
            -- don't repeat quest title
            if not self.previousTitle or (self.previousTitle ~= content.title) then
                text = content.title.."\n"..text;
            end
            self.previousTitle = content.title;
        end

        if TTS_CONTENT_SPEAKER and content.speaker then     --NPC name
            -- don't repeat NPC name
            if not self.previousSpeaker or (self.previousSpeaker ~= content.speaker) then
                text = content.speaker.."\n"..text;
            end
            self.previousSpeaker = content.speaker;
        end
        --added option to read objectives
        if TTS_CONTENT_OBJECTIVE and content.objective then --Objective
            text = text .. "\n" .. content.objective;
        end

        text = AdjustTextForTTS(text);
        self:QueueText(text, voiceID, identifier, contentSource);
    end
    -- force to read quest title when speaking to the same npc when returning from the quest
    if content.objective then
        self.previousTitle = nil;
    end
end

function TTSUtil:IsSpeaking()
    return self.utteranceID ~= nil;
end

function TTSUtil:ToggleSpeaking(system)
    system = system or "dialogue";

    if self:IsSpeaking() then
        if system == "book" then
            addon.BookUI:StopReadingBook();
        else
            self:StopLastTTS();
        end
    else
        --there is the forced reading of text when player pushes Play button, so it may override history when TTS_SKIP_RECENT is enabled
        self.forceRead = true;
        if system == "book" then
            addon.BookUI:SpeakTopContent();
        else
            self:ReadCurrentDialogue();
        end
    end
end

function TTSUtil:OnEvent(event, ...)
    if self[event] then
        self[event](self, ...)
    end
end

function TTSUtil:VOICE_CHAT_TTS_PLAYBACK_STARTED(numConsumers, utteranceID, durationMS, destination)
    if destination ~= nil and destination ~= DESTINATION then
        return
    end

    local expectedID = self.pendingUtteranceID or self.utteranceID;
    if not expectedID or (utteranceID ~= nil and utteranceID ~= expectedID) then
        return
    end

    self.pendingUtteranceID = nil;
    self.utteranceID = utteranceID or expectedID;
    self.playbackStarted = true;
    self:UnregisterEvent("VOICE_CHAT_TTS_PLAYBACK_STARTED");
    for _, button in ipairs(TTSButtons) do
        button.AnimWave:Play();
    end
end

function TTSUtil:VOICE_CHAT_TTS_PLAYBACK_FINISHED(numConsumers, utteranceID, destination)
    if destination ~= nil and destination ~= DESTINATION then
        return
    end

    local expectedID = self.pendingUtteranceID or self.utteranceID;
    if not expectedID or (utteranceID ~= nil and utteranceID ~= expectedID) then
        return
    end

    self:FinishPlayback(true);
end

function TTSUtil:VOICE_CHAT_TTS_PLAYBACK_FAILED(status, utteranceID, destination)
    if destination ~= nil and destination ~= DESTINATION then
        return
    end

    local expectedID = self.pendingUtteranceID or self.utteranceID;
    if not expectedID or (utteranceID ~= nil and utteranceID ~= expectedID) then
        return
    end

    self:FinishPlayback(true);
end

function TTSUtil:StopLastTTS()
    if self.utteranceID or self.queue or self.nextSegment then
        self:Clear();
    end
end

function TTSUtil:EnableModule(state)
    if state then
        self.isEnabled = true;
    elseif self.isEnabled then
        self.isEnabled = false;
        self.previousSpeaker = nil;
        self.previousTitle = nil;
        self.contentSource = nil;
        self:StopLastTTS();
        self:UnregisterPlaybackEvents();
        self:SetScript("OnEvent", nil);
    end

    if self.isEnabled then
        self:SetScript("OnEvent", self.OnEvent);
    else
        self:SetScript("OnEvent", nil);
    end
end

do  --Book
    function TTSUtil:OnUpdate_PauseThenReadNextBookLine(elapsed)
        self.t = self.t + elapsed;
        if self.t > 0.25 then
            self.t = 0;
            self:SetScript("OnUpdate", nil);
            if addon.BookUI:ReadAndMoveToNextLine() then

            else

            end
        end
    end

    function TTSUtil:RequestReadNextBookLine()
        self.t = 0;
        self:SetScript("OnUpdate", self.OnUpdate_PauseThenReadNextBookLine);
    end

    function TTSUtil:ReadBookLine(text, userInput)
        if not TTS_SUPPORTED then
            return
        end

        if userInput then
            self:StopReadingBook();
        end

        text = AdjustTextForTTS(text);

        local segment = {
            text = text,
            voiceID = self:GetDefaultVoiceForBook(),
            contentSource = "book",
        };

        self.queue = nil;
        self:SetScript("OnUpdate", nil);
        self:StopThenPlay(segment)
        self.t = -0.1;
    end

    function TTSUtil:StopReadingBook()
        if self.contentSource == "book" then
            self.contentSource = nil;
            TTSUtil:StopLastTTS();
        end
    end
end

do  --TTS Play Button
    local BUTTON_SIZE = 24;
    local ICON_SIZE = 16;
    local ALPHA_UNFOCUSED = 0.6;


    function TTSButtonMixin:OnEnter()
        self:SetAlpha(1);
        local TooltipFrame = addon.SharedTooltip;
        TooltipFrame:Hide();
        TooltipFrame:SetOwner(self, "TOPRIGHT");

        local titleText = L["TTS"];
        if GetDBBool("TTSUseHotkey") then
            local key = addon.BindingUtil:GetActiveActionKey("TTS");
            if key then
                titleText = titleText .. string.format(" |cffffd100(%s)", key);
            end
        end
        TooltipFrame:SetTitle(titleText, 1, 1, 1);

        if TTS_AUTO_PLAY then
            TooltipFrame:AddDoubleLine(L["TTS Auto Play"], L["Option Enabled"], 1, 1, 1, 0.098, 1.000, 0.098);
        else
            TooltipFrame:AddDoubleLine(L["TTS Auto Play"], L["Option Disabled"], 1, 1, 1, 1.000, 0.125, 0.125);
        end

        TooltipFrame:AddLeftLine(L["TTS Button Tooltip"], 1, 0.82, 0);

        if self:CheckTranslator(true) then
            local HOTKEY_ALTERNATE_MODE = "Shift";
            local description;
            local readTranslation = GetDBBool("TTSReadTranslation");
            if readTranslation then
                description = L["TTS Button Read Original"];
            else
                description = L["TTS Button Read Translation"];
            end
            local alternateModeCallback = nil;  --Handled by OnModiferStateChanged
            TooltipFrame:ShowHotkey(HOTKEY_ALTERNATE_MODE, description, alternateModeCallback);
        end

        self:CheckExternalVoiceover(TooltipFrame);

        TooltipFrame:Show();
    end

    function TTSButtonMixin:OnLeave()
        self:SetAlpha(ALPHA_UNFOCUSED);
        addon.SharedTooltip:Hide();
        self:CheckTranslator(false);
    end

    function TTSButtonMixin:SetTheme(themeID)
        themeID = themeID or 1;
        local x = (themeID - 1) * 0.125;
        self.Icon:SetTexCoord(x, 64/512 + x, 0, 0.5);
        self.Wave1:SetTexCoord(x, 16/512 + x, 0.5, 1);
        self.Wave2:SetTexCoord(16/512 + x, 40/512 + x, 0.5, 1);
        self.Wave3:SetTexCoord(40/512 + x, 64/512 + x, 0.5, 1);
    end

    function TTSButtonMixin:OnClick(button)
        if button == "LeftButton" then
            TTSUtil:ToggleSpeaking(self.system);
        elseif button == "RightButton" then
            addon.SetDBValue("TTSAutoPlay", not TTS_AUTO_PLAY);
            if self:IsMouseOver() then
                self:OnEnter();
            end
            addon.SettingsUI:RequestUpdate();
        end
    end

    local function CreateSpeakerAnimationController(button)
        -- Legacy animations cannot target sibling regions.  Give each wave its
        -- own synchronized group and expose the small controller interface used
        -- by the TTS button.
        local waves = {button.Wave1, button.Wave2, button.Wave3};
        local delays = {0, 0.25, 0.5};
        local groups = {};

        for i, wave in ipairs(waves) do
            local group = wave:CreateAnimationGroup();
            group:SetLooping("REPEAT");

            local fadeIn = group:CreateAnimation("Alpha");
            fadeIn:SetChange(1);
            fadeIn:SetDuration(0.25);
            fadeIn:SetStartDelay(delays[i]);
            fadeIn:SetOrder(1);

            local fadeOut = group:CreateAnimation("Alpha");
            fadeOut:SetChange(-1);
            fadeOut:SetDuration(0.25);
            fadeOut:SetStartDelay(delays[i] + 0.75);
            fadeOut:SetOrder(1);

            local cycleLength = group:CreateAnimation("Animation");
            cycleLength:SetDuration(1.5);
            cycleLength:SetOrder(1);

            groups[i] = group;
        end

        local controller = {scripts = {}};

        function controller:SetScript(scriptType, callback)
            self.scripts[scriptType] = callback;
        end

        function controller:Play()
            if self.scripts.OnPlay then
                self.scripts.OnPlay();
            end
            for _, group in ipairs(groups) do
                group:Play();
            end
        end

        function controller:Stop()
            for _, group in ipairs(groups) do
                group:Stop();
            end
            if self.scripts.OnStop then
                self.scripts.OnStop();
            end
        end

        return controller
    end

    local function CreateTTSButton(parent, themeID)
        local b = CreateFrame("Button", nil, parent);
        b:SetSize(BUTTON_SIZE, BUTTON_SIZE);
        b:SetAlpha(ALPHA_UNFOCUSED);
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp");

        local file = "Interface/AddOns/DialogueUI-Ascension/Art/Theme_Shared/TTSButton.tga";

        b.Icon = b:CreateTexture(nil, "OVERLAY");
        b.Icon:SetSize(ICON_SIZE, ICON_SIZE);
        b.Icon:SetPoint("CENTER", b, "CENTER", 0, 0);
        b.Icon:SetTexture(file);
        b.Icon:SetSize(ICON_SIZE, ICON_SIZE);


        b.Wave1 = b:CreateTexture(nil, "OVERLAY");
        b.Wave1:SetSize(0.25*ICON_SIZE, ICON_SIZE);
        b.Wave1:SetPoint("LEFT", b, "RIGHT", -8, 0);
        b.Wave1:SetTexture(file);

        b.Wave2 = b:CreateTexture(nil, "OVERLAY");
        b.Wave2:SetSize(0.375*ICON_SIZE, ICON_SIZE);
        b.Wave2:SetPoint("LEFT", b.Wave1, "RIGHT", -3, 0);
        b.Wave2:SetTexture(file);

        b.Wave3 = b:CreateTexture(nil, "OVERLAY");
        b.Wave3:SetSize(0.375*ICON_SIZE, ICON_SIZE);
        b.Wave3:SetPoint("LEFT", b.Wave2, "RIGHT", -4, 0);
        b.Wave3:SetTexture(file);

        b.Wave1:Hide();
        b.Wave2:Hide();
        b.Wave3:Hide();

        b.AnimWave = CreateSpeakerAnimationController(b);

        b.AnimWave:SetScript("OnPlay", function()
            b.Wave1:SetAlpha(0);
            b.Wave2:SetAlpha(0);
            b.Wave3:SetAlpha(0);
            b.Wave1:Show();
            b.Wave2:Show();
            b.Wave3:Show();
        end);

        b.AnimWave:SetScript("OnStop", function()
            b.Wave1:Hide();
            b.Wave2:Hide();
            b.Wave3:Hide();
        end);

        addon.API.Mixin(b, TTSButtonMixin);

        b:SetScript("OnClick", b.OnClick);
        b:SetScript("OnEnter", b.OnEnter);
        b:SetScript("OnLeave", b.OnLeave);

        b:SetTheme(themeID);

        table.insert(TTSButtons, b);

        return b
    end
    addon.CreateTTSButton = CreateTTSButton;


    --Translator: Press Shift to switch between reading original texts or the translation.
    function TTSButtonMixin:CheckTranslator(state)
        if state and addon.DialogueUI:IsTranslationAvailable() and addon.IsTranslatorEnabled() then
            self:RegisterEvent("MODIFIER_STATE_CHANGED");
            self:SetScript("OnEvent", self.OnModiferStateChanged);
            return true
        else
            self:UnregisterEvent("MODIFIER_STATE_CHANGED");
            self:SetScript("OnEvent", nil);
            return false
        end
    end

    function TTSButtonMixin:OnModiferStateChanged(event, key, down)
        if IsShiftDown(key, down) then
            if self:IsMouseOver() then
                local userInput = true;
                addon.FlipDBBool("TTSReadTranslation", userInput);
                self:OnEnter();
            else
                self:CheckTranslator(false);
            end
        end
    end
end

do  --Voice List
    local GetDBValue = addon.GetDBValue;

    function TTSUtil:GetAvailableVoices()
        if not self.voices then
            self.voices = {};
            self.validVoice = {};

            for _, data in ipairs(GetTtsVoices()) do
                local voiceID = type(data) == "table" and tonumber(data.voiceID or data.voiceId or data.id);
                if voiceID then
                    local name = data.name or data.voiceName or UNKNOWN_TEXT;
                    table.insert(self.voices, {
                        voiceID = voiceID,
                        name = name,
                    });
                    self.validVoice[voiceID] = true;
                end
            end

            if TTS_SUPPORTED then
                local systemVoiceID = GetSystemVoiceID();
                self.validVoice[FALLBACK_VOICE_ID] = true;
                self.validVoice[systemVoiceID] = true;

                if #self.voices == 0 then
                    local voiceName = CallGetter(TTSSettings.GetVoiceOptionName, UNKNOWN_TEXT);
                    self.voices[1] = {
                        voiceID = systemVoiceID,
                        name = voiceName,
                    };
                end
            end
        end
        return self.voices
    end

    function TTSUtil:IsVoiceIDValid(voiceID)
        if not self.voices then
            self:GetAvailableVoices();
        end
        return voiceID and self.validVoice[voiceID]
    end

    function TTSUtil:ResolveVoiceID(voiceID)
        if not TTS_SUPPORTED then
            return FALLBACK_VOICE_ID
        end

        if voiceID and voiceID ~= FALLBACK_VOICE_ID and self:IsVoiceIDValid(voiceID) then
            return voiceID
        end

        local systemVoiceID = GetSystemVoiceID();
        if systemVoiceID ~= nil then
            return systemVoiceID
        end

        local voices = self:GetAvailableVoices();
        return voices[1] and voices[1].voiceID or FALLBACK_VOICE_ID
    end

    function TTSUtil:GetVoiceName(voiceID)
        voiceID = self:ResolveVoiceID(voiceID);
        if voiceID ~= nil then
            for _, data in ipairs(self:GetAvailableVoices()) do
                if data.voiceID == voiceID then
                    return data.name
                end
            end
        end

        return UNKNOWN_TEXT
    end

    function TTSUtil:GetVoiceNameByIndex(index)
        if index then
            for i, data in ipairs(self:GetAvailableVoices()) do
                if i == index then
                    return data.name
                end
            end
        end

        return UNKNOWN_TEXT
    end

    function TTSUtil:GetVoiceIndex(voiceID)
        voiceID = self:ResolveVoiceID(voiceID);
        if voiceID ~= nil then
            for index, data in ipairs(self:GetAvailableVoices()) do
                if data.voiceID == voiceID then
                    return index
                end
            end
        end
        return 1
    end

    function TTSUtil:GetFirstValidName(voiceID)
        if self:IsVoiceIDValid(voiceID) then
            return self:GetVoiceName(voiceID);
        end

        return self:GetVoiceName(self:ResolveVoiceID(FALLBACK_VOICE_ID))
    end

    function TTSUtil:GetDefaultVoiceA()
        local voiceID = GetDBValue("TTSVoiceMale");
        return self:ResolveVoiceID(voiceID)
    end

    function TTSUtil:GetDefaultVoiceB()
        local voiceID = GetDBValue("TTSVoiceFemale");
        return self:ResolveVoiceID(voiceID)
    end

    function TTSUtil:GetDefaultVoiceC()
        local voiceID = GetDBValue("TTSVoiceNarrator");
        return self:ResolveVoiceID(voiceID)
    end

    function TTSUtil:GetDefaultVoiceForBook()
        local voiceID = GetDBValue("BookTTSVoice");
        if (not voiceID) and TTS_USE_NARRATOR then
            voiceID = GetDBValue("TTSVoiceNarrator");
        end
        if (not voiceID) then
            voiceID = GetDBValue("TTSVoiceMale");
        end
        return self:ResolveVoiceID(voiceID)
    end

    function TTSUtil:OnUpdate_Process(elapsed)
        self.t = self.t + elapsed;
        if self.t > 0 then
            self:SetScript("OnUpdate", nil);
            self.t = nil;
            if self.pendingFunc then
                self.pendingFunc();
                self.pendingFunc = nil;
            end
        end
    end

    function TTSUtil:PlaySample(voiceID)
        if not TTS_SUPPORTED then
            return
        end

        self.contentSource = "sample";

        self:Clear();
        voiceID = self:ResolveVoiceID(voiceID or self:GetVoiceIDForNPC());

        self.pendingFunc = function()
            self:SpeakText({
                voiceID = voiceID,
                text = SAMPLE_TEXT,
                contentSource = "sample",
            });
        end

        self.t = -0.2;
        self:SetScript("OnUpdate", self.OnUpdate_Process);
    end

    addon.CallbackRegistry:Register("SettingsUI.Hide", function()
        TTSUtil.voices = nil;
    end);
end

do  --External Voiceover Provider
    local ExternalQueue = CreateFrame("Frame");
    do
        ExternalQueue:Hide();
        ExternalQueue.delay = 0.75;

        function ExternalQueue:Stop()
            self:Hide();
            self:SetScript("OnUpdate", nil);
            self.t = nil;
        end

        function ExternalQueue:Start()
            self.t = 0;
            self:SetScript("OnUpdate", self.OnUpdate);
            self:Show();
        end

        function ExternalQueue:OnUpdate(elapsed)
            self.t = self.t + elapsed;
            if self.t >= self.delay then
                self:Stop();
                TTSUtil:PlayVoiceoverExternal();
            end
        end
    end


    function TTSUtil:GetExternalVoiceoverName()
        --override
    end

    function TTSUtil:DoesExternalVoiceoverExist()
        --override
        return false
    end

    function TTSUtil:PlayVoiceoverExternal()
        --override
    end

    function TTSUtil:StopVoiceoverExternal()
        --override
    end

    function TTSUtil:IsPlayingVoiceoverExternal()
        --override
        --nil means no external voiceover addon
    end

    function TTSUtil:UpdateAutoPlayDelay()
        local delay = self.GetAutoPlayDelayExternal and self:GetAutoPlayDelayExternal();
        if (not delay) or type(delay) ~= "number" then
            delay = 0.75;
        end
        if delay < 0.5 then
            delay = 0.5;
        end
        ExternalQueue.delay = delay;
    end


    function TTSUtil:RequestPlayingVoiceoverExternal(fromAutoPlay)
        if fromAutoPlay then
            self:UpdateAutoPlayDelay();
            self:StopVoiceoverExternal();
            ExternalQueue:Start();
        else
            if self:IsPlayingVoiceoverExternal() then
                self:StopVoiceoverExternal();
            else
                self:PlayVoiceoverExternal();
            end
        end
    end

    function TTSUtil:RequestStoppingVoiceoverExternal(fromLeavingNPC)
        ExternalQueue:Stop();
        if (not fromLeavingNPC) or TTS_STOP_WHEN_LEAVING then
            self:StopVoiceoverExternal();
        end
    end


    function TTSButtonMixin:CheckExternalVoiceover(tooltip)
        local providerName = TTSUtil:GetExternalVoiceoverName();
        if providerName then
            tooltip:AddBlankLine();
            if TTSUtil:DoesExternalVoiceoverExist() then
                tooltip:AddLeftLine(L["VO Provider Format"]:format(providerName), 1, 0.82, 0);
            else
                tooltip:AddLeftLine(L["VO No File Format"]:format(providerName), 1.000, 0.125, 0.125);
            end
        end
    end
end

do  --CallbackRegistry
    local function OnHandleEvent(event)
        if TTSUtil.isEnabled then
            if TTS_AUTO_PLAY then
                TTSUtil:ReadCurrentDialogue(true);
            end
        end
    end
    CallbackRegistry:Register("DialogueUI.HandleEvent", OnHandleEvent);

    local function OnBookCached()
        if TTSUtil.isEnabled then
            if TTS_AUTO_PLAY then
                After(0.5, function()
                    addon.BookUI:SpeakTopContent();
                end);
            end
        end
    end
    CallbackRegistry:Register("BookUI.BookCached", OnBookCached);

    local function InteractionClosed()
        if TTSUtil.isEnabled then
            TTSUtil.previousSpeaker = nil;
            TTSUtil.previousTitle = nil;
            if TTS_STOP_WHEN_LEAVING then
                TTSUtil:StopLastTTS();
            end
        end
        TTSUtil:RequestStoppingVoiceoverExternal(true);
    end
    CallbackRegistry:Register("DialogueUI.Hide", InteractionClosed);


    local function Settings_TTSEnabled(dbValue)
        TTSUtil:EnableModule(dbValue == true);
    end
    CallbackRegistry:Register("SettingChanged.TTSEnabled", Settings_TTSEnabled);

    local function Settings_TTSAutoPlay(dbValue)
        TTS_AUTO_PLAY = dbValue == true;
    end
    CallbackRegistry:Register("SettingChanged.TTSAutoPlay", Settings_TTSAutoPlay);

    local function Settings_TTSAutoStop(dbValue)
        TTS_STOP_WHEN_LEAVING = dbValue == true;
    end
    CallbackRegistry:Register("SettingChanged.TTSAutoStop", Settings_TTSAutoStop);

    --"Stop reading old text when opening new dialog"
    local function Settings_TTSStopOnNew(dbValue)
        TTS_STOP_ON_NEW = dbValue == true;
    end
    CallbackRegistry:Register("SettingChanged.TTSStopOnNew", Settings_TTSStopOnNew);

    local function Settings_TTSVoice(dbValue, userInput)
        if userInput then
            local voiceID = dbValue;
            TTSUtil:PlaySample(voiceID);
        end
    end

    --"Use anrrator voice for quest titles, npc names, objectives and any text in <> in the body"
    local function Settings_TTSUseNarrator(dbValue)
        TTS_USE_NARRATOR = dbValue == true;
    end
    CallbackRegistry:Register("SettingChanged.TTSUseNarrator", Settings_TTSUseNarrator);

    CallbackRegistry:Register("SettingChanged.TTSVoiceMale", Settings_TTSVoice);
    CallbackRegistry:Register("SettingChanged.TTSVoiceFemale", Settings_TTSVoice);
    CallbackRegistry:Register("SettingChanged.TTSVoiceNarrator", Settings_TTSVoice);
    CallbackRegistry:Register("SettingChanged.BookTTSVoice", Settings_TTSVoice);

    local function Settings_TTSVolume(dbValue, userInput)
        local volume = dbValue and tonumber(dbValue) or 10;
        if volume < 1 then
            volume = 1;
        elseif volume > 10 then
            volume = 10;
        end
        volume = 10 * volume;
        TTSUtil.defaultVolume = volume;
        if userInput then
            TTSUtil:PlaySample();
        end
    end
    CallbackRegistry:Register("SettingChanged.TTSVolume", Settings_TTSVolume);

    local TTSRateValue = {
        [1] = 0,
        [2] = 1,
        [3] = 2,
        [4] = 4,
        [5] = 7,
        [6] = 10,
    };

    local function Settings_TTSRate(dbValue, userInput)
        local rate = dbValue or 1;
        if not TTSRateValue[rate] then
            rate = 1;
        end
        TTSUtil.defaultRate = TTSRateValue[rate];
        if userInput then
            TTSUtil:PlaySample();
        end
    end
    CallbackRegistry:Register("SettingChanged.TTSRate", Settings_TTSRate);

    local function Settings_TTSContentQuestTitle(dbValue, userInput)
        TTS_CONTENT_QUEST_TITLE = dbValue == true;
        if userInput then
            TTSUtil:Clear();
        end
    end
    CallbackRegistry:Register("SettingChanged.TTSContentQuestTitle", Settings_TTSContentQuestTitle);

    local function Settings_TTSContentSpeaker(dbValue, userInput)
        TTS_CONTENT_SPEAKER = dbValue == true;
        if userInput then
            TTSUtil:Clear();
        end
    end
    CallbackRegistry:Register("SettingChanged.TTSContentSpeaker", Settings_TTSContentSpeaker);

    --"Read Quest Objectives"
    local function Settings_TTSContentObjective(dbValue, userInput)
        TTS_CONTENT_OBJECTIVE = dbValue == true;
        if userInput then
            TTSUtil:Clear();
        end
    end
    CallbackRegistry:Register("SettingChanged.TTSContentObjective", Settings_TTSContentObjective);

    --"Skip recently read quest"
    local function Settings_TTSSkipRecent(dbValue, userInput)
        TTS_SKIP_RECENT = dbValue == true;
        if userInput then
            TTSUtil:Clear();
        end
    end
    CallbackRegistry:Register("SettingChanged.TTSSkipRecent", Settings_TTSSkipRecent);


    --Book
    local function BookUI_OnHide()
        TTSUtil:StopReadingBook();
    end
    CallbackRegistry:Register("BookUI.Hide", BookUI_OnHide);
end


do  --Temp Fix For FCF_GetCurrentFullScreenFrame missing on TBC
    if addon.IS_TBC and not _G.FCF_GetCurrentFullScreenFrame then
        _G.FCF_GetCurrentFullScreenFrame = function() end;
    end
end


--[[
do  --Debug for 12.0.5 VOICE_CHAT_TTS_PLAYBACK_FINISHED issue
    local f = CreateFrame("Frame");
    f:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_STARTED");
    f:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FAILED");
    f:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FINISHED");
    f:SetScript("OnEvent", function(self, event, ...)
        print(event, ...);
        if event == "VOICE_CHAT_TTS_PLAYBACK_FINISHED" then
            if self.callback then
                self.callback();
            end
        end
    end);

    -- SpeakText API is different on Retail/Classic
    local SpeakText;
    local tocVersion = select(4, GetBuildInfo());

    if tocVersion > 120000 then
        SpeakText = C_VoiceChat.SpeakText;
    else
        SpeakText = function(voiceID, text, rate, volume, overlap)
            local destination = Enum.VoiceTtsDestination.LocalPlayback;
            C_VoiceChat.SpeakText(voiceID, text, destination, rate, volume, overlap);
        end
    end

    -- FINISHED and FAILED won't fire when we interrupt the speech
    function TTSTest1()
        local voices = C_VoiceChat.GetTtsVoices();
        local voiceID = voices and voices[1].voiceID or 0;
        local text = TEXT_TO_SPEECH_SAMPLE_TEXT;
        local rate = 0;
        local volume = 100;
        local overlap = false;

        SpeakText(voiceID, text, rate, volume, overlap);

        C_Timer.After(1, function()
            print("C_VoiceChat.StopSpeakingText");
            C_VoiceChat.StopSpeakingText();
        end);
    end

    -- Game crashes when we StopSpeakingText on FINISHED
    function TTSTest2()
        local voices = C_VoiceChat.GetTtsVoices();
        local voiceID = voices and voices[1].voiceID or 0;
        local text = "fatality";
        local rate = 0;
        local volume = 100;
        local overlap = false;

        f.callback = C_VoiceChat.StopSpeakingText;
        SpeakText(voiceID, text, rate, volume, overlap);
    end
end
--]]
