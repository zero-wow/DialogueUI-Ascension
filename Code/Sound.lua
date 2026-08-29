local _, addon = ...
local C_Timer = addon.Legacy.C_Timer or C_Timer;
local API = addon.API;

local PlaySoundFileAPI = type(_G.PlaySoundFile) == "function" and _G.PlaySoundFile or nil;
local PlaySoundAPI = type(_G.PlaySound) == "function" and _G.PlaySound or nil;

--[[
local SoundPanel = CreateFrame("Frame");

function SoundPanel:OnUpdate(elapsed)
    self.t = self.t + elapsed;
    if self.t > 0.1 then
        self.t = 0;
        self:Unlock();
    end
end

function SoundPanel:Start()
    if not self.isPlaying then
        self.isPlaying = true;
        self.t = 0;
        self:SetScript("OnUpdate", self.OnUpdate);
    end
end

function SoundPanel:Unlock()
    self.isPlaying = nil;
    self:SetScript("OnUpdate", nil);
end

--]]

local PATH = "Interface/AddOns/DialogueUI-Ascension/Sound/";
local SOUNDS = {
    DIALOG_OPTION_CLICK = "paper-collect-1.mp3",
    DIALOG_OPTION_ENTER = "paper-collect-2.mp3",
    QUEST_TEXT_SHOW = "page-turn-1.mp3",
};

-- Ascension's documented PlaySound API accepts legacy string names, not Retail
-- numeric SOUNDKIT IDs.
local LEGACY_SOUND = {
    ["SOUNDKIT.IG_QUEST_LIST_OPEN"] = "igQuestListOpen",
    ["CHECKBOX_ON"] = "igMainMenuOptionCheckBoxOn",
    ["CHECKBOX_OFF"] = "igMainMenuOptionCheckBoxOff",
};

local function PlaySound(name)
    local fileName = SOUNDS[name];
    if fileName and PlaySoundFileAPI then
        -- The 3.3.5 API has no sound-channel argument.
        pcall(PlaySoundFileAPI, PATH..fileName);
    else
        local legacyName = LEGACY_SOUND[name];
        if legacyName and PlaySoundAPI then
            pcall(PlaySoundAPI, legacyName);
        end
    end
end
addon.PlaySound = PlaySound;


do  --Mute Target Lost Sound while interacting with NPC     --Mute UI open/close sound briefly
    --https://wago.tools/db2/SoundKitEntry?filter[SoundKitID]=684&page=1&sort[SoundKitID]=asc
    --local soundKitID = (SOUNDKIT and SOUNDKIT.INTERFACE_SOUND_LOST_TARGET_UNIT) or 684;

    local SHOULD_MUTE_FILE = true;
    local SOUND_FILE_ID = 567520;
    local MuteSoundFileAPI = type(_G.MuteSoundFile) == "function" and _G.MuteSoundFile or nil;
    local UnmuteSoundFileAPI = type(_G.UnmuteSoundFile) == "function" and _G.UnmuteSoundFile or nil;
    local CAN_MUTE_FILES = MuteSoundFileAPI and UnmuteSoundFileAPI;
    local targetLostSoundMuted = false;

    local function TryMuteSoundFile(soundFileID)
        if not CAN_MUTE_FILES then
            return false
        end
        return pcall(MuteSoundFileAPI, soundFileID);
    end

    local function TryUnmuteSoundFile(soundFileID)
        if not CAN_MUTE_FILES then
            return false
        end
        return pcall(UnmuteSoundFileAPI, soundFileID);
    end

    local function MuteTargetLostSound()
        if SHOULD_MUTE_FILE and not targetLostSoundMuted then
            targetLostSoundMuted = TryMuteSoundFile(SOUND_FILE_ID);
        end
    end

    local function UnmuteTargetLostSound()
        if targetLostSoundMuted then
            TryUnmuteSoundFile(SOUND_FILE_ID);
            targetLostSoundMuted = false;
        end
    end

    addon.CallbackRegistry:Register("DialogueUI.Show", MuteTargetLostSound);
    addon.CallbackRegistry:Register("DialogueUI.Hide", UnmuteTargetLostSound);


    local function BrieflyMuteUIOpenHideSound()
        --SOUNDKIT.IG_MAINMENU_OPEN, SOUNDKIT.IG_MAINMENU_CLOSE
        if not CAN_MUTE_FILES then
            return false
        end

        local s1, s2 = 567490, 567464;
        local muted1 = TryMuteSoundFile(s1);
        local muted2 = TryMuteSoundFile(s2);

        local function Unmute()
            if muted1 then
                TryUnmuteSoundFile(s1);
            end
            if muted2 then
                TryUnmuteSoundFile(s2);
            end
        end

        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0.03, Unmute);
        else
            Unmute();
        end

        return muted1 or muted2
    end
    API.BrieflyMuteUIOpenHideSound = BrieflyMuteUIOpenHideSound;


    local function Settings_MuteTargetLostSound(dbValue)
        if dbValue == false then
            SHOULD_MUTE_FILE = false;
            UnmuteTargetLostSound();
        else
            SHOULD_MUTE_FILE = true;
        end
    end
    addon.CallbackRegistry:Register("SettingChanged.MuteTargetLostSound", Settings_MuteTargetLostSound);
end
