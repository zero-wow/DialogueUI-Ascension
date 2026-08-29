local VERSION_TEXT = "v1.0.5 d - WotLK r2";
local VERSION_DATE = 1787400000;


local addonName, addon = ...
local CreateFrame = addon.Legacy.CreateFrame or CreateFrame;
local C_AddOns = addon.Legacy.C_AddOns or C_AddOns;

local L = {};       --Locale
local API = {};     --Custom APIs used by this addon
local DB;

addon.L = L;
addon.API = API;
addon.VERSION_TEXT = VERSION_TEXT;

local DefaultValues = {
    Theme = 1,
    FrameSize = 2,
    FontSizeBase = 1,
    FontText = "default",
    FontNumber = "default",
    FrameOrientation = 2,                       --1:Left  2:Right(Default)
    -- Hiding UIParent uses protected visibility state on Wrath.  An insecure
    -- addon changing it can taint action buttons (including ElvUI) and other
    -- protected actions, so the legacy port deliberately leaves it enabled.
    HideUI = false,
        ShowChatWindow = true,
        HideOutlineSparkles = true,
        HideUnitNames = false,
    ShowCopyTextButton = false,
    ShowNPCNameOnPage = false,
    MarkHighestSellPrice = false,
    QuestTypeText = false,
    SimplifyCurrencyReward = false,
    UseRoleplayName = false,
    UseBlizzardTooltip = false,

    CameraMovement = 1,                         --0:OFF  1:Zoom-In  2:Horizontal
    CameraChangeFov = true,
    CameraMovement1MaintainPosition = false,
    CameraMovement2MaintainPosition = true,
    CameraMovementMountedCamera = true,
    CameraMovementDisableInstance = false,
    CameraZoomMultiplier = 1,                   --The smaller the further

    InputDevice = 1,                            --1:K&M  2:XBOX  3.PS  4.Mobile
    UseCustomBindings = false,
    PrimaryControlKey = 1,                      --1: Space  2:Interact Key
    ScrollDownThenAcceptQuest = false,
    EscapeToDeclineQuest = false,
    RightClickToCloseUI = true,
    CycleRewardHotkeyEnabled = false,           --Press Tab to cycle through choosable rewards
    DisableHotkeyForTeleport = false,           --Disable gossip hotkey when select teleportation
    GamePadClickFirstObject = false,            --If true, when starting a new interaction, pressing PAD1 will click the first object
    EmulateSwipe = true,
    MobileDeviceMode = false,

    WidgetManagerDummy = true,                  --Doesn't control anything, used as a trigger
    AutoQuestPopup = true,
    QuestItemDisplay = false,
        QuestItemDisplayHideSeen = false,
        QuestItemDisplayDynamicFrameStrata = false,
    QuickSlotQuestReward = false,
    AutoCompleteQuest = false,
        QuickSlotUseHotkey = true,
    AutoSelectGossip = false,
    ForceGossip = false,
        ForceGossipSkipGameObject = false,
    ShowDialogHint = true,
    DisableDUIInInstance = false,

    NameplateDialogEnabled = false,             --Experimental. Not in the settings

    DisableUIMotion = false,

    TTSEnabled = false,
        TTSUseHotkey = true,    --Default key R
        TTSAutoPlay = false,
            TTSSkipRecent = false,              --Skip recently read texts
            TTSAutoPlayDelay = false,           --Add a delay before starting auto play in case the NPC is speaking
        TTSAutoStop = true,     --Stop when leaving
        TTSStopOnNew = true,    --Stop when reading new quest
        TTSVoiceMale = 0,       --0: System default
        TTSVoiceFemale = 0,
        TTSUseNarrator = false,
            TTSVoiceNarrator = 0,
        TTSVolume = 10,
        TTSRate = 0,
            TTSContentSpeaker = false,
            TTSContentQuestTitle = true,
            TTSContentObjective = false,

    --Book Settings
    BookUIEnabled = true,
        BookUISize = 1,
        BookKeepUIOpen = false,
        BookShowLocation = false,
        BookUIItemDescription = false,      --Show source item's description on top of the UI
        BookDarkenScreen = true,
        BookTTSVoice = 0,
        BookTTSClickToRead = true,

    --Not shown in the Settings. Accessible by other means
    TooltipShowItemComparison = false,          --Tooltip
    TTSReadTranslation = false,                 --Read original text or translation. Controlled by TTSButton modifier key
    TranslatorShowOriginalText = true,          --If true, display both original text and the translation
    MuteTargetLostSound = true,                 --Mute target lost sound caused by hiding UI. Accessed through command only: /run DialogueUI_DB.MuteTargetLostSound = false

    --WidgetManagerPosition = {x, y}
    --QuestItemDisplayPosition = {x, y}
    --QuickSlotPosition = {x, y}


    --Deprecated:
    --WarbandCompletedQuest = true,         --Always ON
};

local InheritExistingValues = {
    --Newly added systems may copy the the dbValue of similar system: BookUI/DialogueUI frame size, Book/Dialogue voice
    --If the new dbValue doesn't exisit and the existing dbValue isn't the default value, use the new default value
    {"BookUISize", "FrameSize"},
    {"BookTTSVoice", "TTSVoiceNarrator"},
    {"BookTTSVoice", "TTSVoiceMale"},
    {"BookTTSVoice", "TTSVoiceFemale"},
};

local TutorialFlags = {
    --Saved in the DB, prefix: Tutorial_
    --e.g. Tutorial_OpenSettings = true
    "OpenSettings",
    "WarbandCompletedQuest",
};

local function GetDBValue(dbKey)
    return DB[dbKey]
end
addon.GetDBValue = GetDBValue;

local function SetDBValue(dbKey, value, userInput)
    if addon.IS_LEGACY_ASCENSION then
        -- The build-12340 client has no GamePad input surface and exposes no
        -- readable camera zoom, so these two Retail modes cannot be selected
        -- safely even when carried over by an existing SavedVariables file.
        if dbKey == "InputDevice" then
            value = 1;
        elseif dbKey == "CameraMovement" then
            value = 0;
        elseif dbKey == "HideUI" then
            value = false;
        end
    end
    DB[dbKey] = value;
    addon.CallbackRegistry:Trigger("SettingChanged."..dbKey, value, userInput);
end
addon.SetDBValue = SetDBValue;

local function LoadTutorials()
    --Tutorial Flags (nil means haven't shown)

    for _, flag in pairs(TutorialFlags) do
        local dbKey = "Tutorial_"..flag;

        if DB[dbKey] == nil then
            addon.CallbackRegistry:Trigger("Tutorial."..flag);
        end
    end
end

local function LoadDatabase()
    DialogueUI_DB = DialogueUI_DB or {};
    DB = DialogueUI_DB;

    DialogueUI_Saves = DialogueUI_Saves or {};

    local type = type;

    for _, v in ipairs(InheritExistingValues) do
        if DB[v[1]] == nil then
            if DB[v[2]] ~= nil and DB[v[2]] ~= DefaultValues[v[2]] then
                DB[v[1]] = DB[v[2]];
            end
        end
    end

    for dbKey, defaultValue in pairs(DefaultValues) do
        --Some settings are inter-connected so we load all values first
        if DB[dbKey] == nil or type(DB[dbKey]) ~= type(defaultValue) then
            DB[dbKey] = defaultValue;
        end
    end

    local validNumericValues = {
        Theme = {[1] = true, [2] = true},
        FrameSize = {[0] = true, [1] = true, [2] = true, [3] = true},
        FontSizeBase = {[0] = true, [1] = true, [2] = true, [3] = true},
        FrameOrientation = {[1] = true, [2] = true},
        BookUISize = {[0] = true, [1] = true, [2] = true, [3] = true},
        CameraMovement = {[0] = true, [1] = true, [2] = true},
        CameraZoomMultiplier = {[1] = true, [2] = true, [3] = true, [4] = true, [5] = true},
        InputDevice = {[1] = true, [2] = true, [3] = true, [4] = true},
        PrimaryControlKey = {[0] = true, [1] = true, [2] = true},
        TTSRate = {[0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true},
        TTSVolume = {[1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true},
    };
    for dbKey, allowed in pairs(validNumericValues) do
        if not allowed[DB[dbKey]] then
            DB[dbKey] = DefaultValues[dbKey];
        end
    end

    if addon.IS_LEGACY_ASCENSION then
        DB.InputDevice = 1;
        DB.CameraMovement = 0;
        DB.HideUI = false;
    end

    for dbKey, defaultValue in pairs(DefaultValues) do
        SetDBValue(dbKey, DB[dbKey]);
    end

    if not DB.installTime or type(DB.installTime) ~= "number" then
        DB.installTime = VERSION_DATE;
    end

    DefaultValues = nil;
    InheritExistingValues = nil;

    LoadTutorials();

    addon.CallbackRegistry:Trigger("ADDON_LOADED", DB);
end

local function SetTutorialRead(tutorialFlag)
    local dbKey = "Tutorial_"..tutorialFlag;
    DB[dbKey] = true;
end
addon.SetTutorialRead = SetTutorialRead;


local EL = CreateFrame("Frame");
EL:RegisterEvent("ADDON_LOADED");
EL:RegisterEvent("PLAYER_ENTERING_WORLD");
if not addon.IS_LEGACY_ASCENSION then
    EL:RegisterEvent("LOADING_SCREEN_DISABLED");
end

EL:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            self:UnregisterEvent(event);
            LoadDatabase();
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        --Keybindings are loaded after this
        self:UnregisterEvent(event);

        local dbKey = "PrimaryControlKey";
        SetDBValue(dbKey, DB[dbKey]);

        addon.CallbackRegistry:Trigger("PLAYER_ENTERING_WORLD");
        if addon.IS_LEGACY_ASCENSION then
            -- LOADING_SCREEN_DISABLED did not exist in 3.3.5.  The first
            -- PLAYER_ENTERING_WORLD is its reliable legacy equivalent here.
            addon.CallbackRegistry:Trigger("InitialLoadingComplete");
        end
    elseif event == "LOADING_SCREEN_DISABLED" then
        self:UnregisterEvent(event);
        addon.CallbackRegistry:Trigger("InitialLoadingComplete");
    end
end);


do
    local currentToCVersion = select(4, GetBuildInfo());
    if not currentToCVersion then
        print("API Changed: GetBuildInfo()")
        currentToCVersion = 999999;
    end
    currentToCVersion = tonumber(currentToCVersion);

    local function IsToCVersionEqualOrNewerThan(targetVersion)
        return currentToCVersion >= targetVersion
    end
    addon.IsToCVersionEqualOrNewerThan = IsToCVersionEqualOrNewerThan;

    addon.IS_CLASSIC = not IsToCVersionEqualOrNewerThan(100000);
    addon.IS_CATA = currentToCVersion >= 40400 and currentToCVersion < 50000;
    addon.IS_MIDNIGHT = currentToCVersion >= 120000;
    addon.IS_TBC = C_AddOns.GetAddOnMetadata(addonName, "X-Expansion") == "TBC";
    addon.IS_VANILLA = C_AddOns.GetAddOnMetadata(addonName, "X-Expansion") == "VANILLA";
end


local function GetDBBool(dbKey)
    if DB then
        return DB[dbKey] == true
    end
end
addon.GetDBBool = GetDBBool;


local function FlipDBBool(dbKey, userInput)
    if DB then
        SetDBValue(dbKey, not GetDBBool(dbKey), userInput)
    end
end
addon.FlipDBBool = FlipDBBool;


local function IsDBValue(dbKey, value)
    if DB then
        return DB[dbKey] == value
    end
end
addon.IsDBValue = IsDBValue;


local function ResetTutorials()
    for _, flag in pairs(TutorialFlags) do
        local dbKey = "Tutorial_"..flag;
        DB[dbKey] = nil;
    end
end
addon.ResetTutorials = ResetTutorials;




do
    DialogueUIAPI = {};
end
