local addonName, addon = ...;

-- Keep a small, account-wide history of this addon's own Lua errors.  This is
-- intentionally independent of BugSack/Swatter and always chains the existing
-- error handler so it does not hide the normal error dialog or another addon's
-- diagnostics.
local MAX_ERRORS = 12;
local MAX_STACK_CHARS = 3000;
local ERROR_MARKER = "DialogueUI-Ascension";
local RUNTIME_BUILD = "1.0.5-d-ascension.17";

local type = type;
local tostring = tostring;
local tinsert = table.insert;
local tremove = table.remove;
local concat = table.concat;
local format = string.format;
local find = string.find;
local sub = string.sub;
local GetTime = GetTime;
local debugstack = debugstack;

local function GetStore()
    if type(DialogueUI_Diagnostics) ~= "table" then
        DialogueUI_Diagnostics = {};
    end

    local store = DialogueUI_Diagnostics;
    if type(store.errors) ~= "table" then
        store.errors = {};
    end
    store.version = 1;
    return store;
end

local function CaptureError(message)
    message = tostring(message);
    if not find(message, ERROR_MARKER, 1, true) then
        return;
    end

    local stack = "(stack unavailable)";
    if type(debugstack) == "function" then
        local ok, result = pcall(debugstack, 3, 20, 20);
        if ok and type(result) == "string" then
            stack = sub(result, 1, MAX_STACK_CHARS);
        end
    end

    local errors = GetStore().errors;
    tinsert(errors, {
        time = GetTime and GetTime() or 0,
        message = message,
        stack = stack,
    });

    while #errors > MAX_ERRORS do
        tremove(errors, 1);
    end
end

local function BuildReport()
    local errors = GetStore().errors;
    local lines = {
        "Dialogue UI - Ascension diagnostic report",
        "Addon: "..addonName,
        "Runtime build: "..RUNTIME_BUILD,
        "Cached TOC version: "..tostring(GetAddOnMetadata and GetAddOnMetadata(addonName, "Version") or "unknown"),
        "Recorded errors: "..#errors,
        "",
    };

    local dialogue = addon.DialogueUI or _G.DUIQuestFrame;
    local settings = addon.SettingsUI or _G.DUIDialogSettings;
    local state = addon.GetInteractionDebugState and addon.GetInteractionDebugState() or nil;
    local function DescribeFrame(label, frame)
        if not frame then
            return "  "..label..": missing";
        end
        local alpha = frame.GetEffectiveAlpha and frame:GetEffectiveAlpha() or frame:GetAlpha();
        return format("  %s: present; shown=%s; alpha=%.2f; size=%.0fx%.0f",
            label, tostring(frame:IsShown()), tonumber(alpha) or 0,
            tonumber(frame:GetWidth()) or 0, tonumber(frame:GetHeight()) or 0);
    end

    tinsert(lines, "Runtime status:");
    tinsert(lines, DescribeFrame("Quest frame", dialogue)
        .."; loading="..tostring(dialogue and dialogue.isGameLoading or false));
    tinsert(lines, DescribeFrame("Settings frame", settings));
    tinsert(lines, "  UI parent alpha="..format("%.2f", UIParent:GetAlpha()));
    local parchment = dialogue and dialogue.LegacyParchment;
    if parchment then
        local pieces = parchment.pieces or {};
        local first = pieces[1];
        local firstShown = first and first.IsShown and first:IsShown();
        local firstTexture = first and first.GetTexture and first:GetTexture();
        local firstAlpha = first and first.GetAlpha and first:GetAlpha();
        local firstWidth = first and first.GetWidth and first:GetWidth();
        local firstHeight = first and first.GetHeight and first:GetHeight();
        local parent = parchment.parent;
        tinsert(lines, "  Legacy parchment: pieces="..#pieces
            .."; shown="..tostring(parchment:IsShown())
            .."; firstShown="..tostring(firstShown)
            .."; texture="..tostring(firstTexture or parchment.textureFile));
        tinsert(lines, "    first alpha="..tostring(firstAlpha)
            .."; size="..format("%.0fx%.0f", tonumber(firstWidth) or 0, tonumber(firstHeight) or 0)
            .."; owner="..tostring(parent and parent.GetName and parent:GetName() or parent));
    else
        tinsert(lines, "  Legacy parchment: missing");
    end
    if state then
        tinsert(lines, "  Takeover active="..tostring(state.takeoverActive)
            .."; external handler="..tostring(state.handledExternally));
        tinsert(lines, "  Last interaction: "..tostring(state.lastEvent or "none")
            .." ("..tostring(state.lastResult or "not received")..")");
    end
    tinsert(lines, "");

    if #errors == 0 then
        tinsert(lines, "No DialogueUI-Ascension Lua errors have been recorded in this account.");
    else
        for i, entry in ipairs(errors) do
            tinsert(lines, format("[%d] client time %.3f", i, tonumber(entry.time) or 0));
            tinsert(lines, entry.message or "(missing error message)");
            tinsert(lines, entry.stack or "(missing stack)");
            tinsert(lines, "");
        end
    end

    return concat(lines, "\n");
end

local function ShowReport()
    local report = BuildReport();
    local clipboard = addon.Clipboard;
    if clipboard and clipboard.ShowContent then
        clipboard:ShowContent(report);
        local editBox = clipboard.EditBox;
        if editBox then
            if editBox.SetFocus then
                editBox:SetFocus();
            end
            if editBox.HighlightText then
                editBox:HighlightText();
            end
        end
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("Dialogue UI diagnostics: the report UI has not loaded yet. Run /duierrors again after login.");
    end
end

local function ClearReport()
    GetStore().errors = {};
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("Dialogue UI diagnostics cleared.");
    end
end

SLASH_DIALOGUEUIERRORS1 = "/duierrors";
SlashCmdList.DIALOGUEUIERRORS = function(message)
    if message and string.lower(message) == "clear" then
        ClearReport();
    else
        ShowReport();
    end
end;

addon.Diagnostics = {
    CaptureError = CaptureError,
    BuildReport = BuildReport,
    Clear = ClearReport,
};

-- Replacing the handler is the only client-supported way to observe Lua
-- errors.  Keep the previous handler intact and protect this recorder so a
-- malformed report can never suppress the original error path.
if type(geterrorhandler) == "function" and type(seterrorhandler) == "function" then
    local previousHandler = geterrorhandler();
    local handlingError = false;

    seterrorhandler(function(message)
        if not handlingError then
            handlingError = true;
            pcall(CaptureError, message);
            handlingError = false;
        end

        if previousHandler then
            return previousHandler(message);
        end
    end);
end
