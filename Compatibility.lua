-- Dialogue UI - Ascension legacy compatibility layer
-- Target: original WoW 3.3.5a (build 12340 / Interface 30300)

local addonName, addon = ...

addon = addon or {}
addon.Legacy = addon.Legacy or {}
addon.IS_LEGACY_ASCENSION = true

local Legacy = addon.Legacy
local _G = _G
local type = type
local pairs = pairs
local ipairs = ipairs
local select = select
local tonumber = tonumber
local tostring = tostring
local floor = math.floor
local insert = table.insert
local remove = table.remove
local unpack = unpack


-- Build addon-private facades for Blizzard namespaces.  Reading through to a
-- genuine native namespace is safe, but adding compatibility members to that
-- shared global table can taint unrelated FrameXML and other addons.
local function CreatePrivateNamespace(nativeNamespace)
    local facade = {}
    if type(nativeNamespace) == "table" then
        for key, value in pairs(nativeNamespace) do
            facade[key] = value
        end
        setmetatable(facade, {__index = nativeNamespace})
    end
    return facade
end


-- --------------------------------------------------------------------------
-- General helpers introduced after 3.3.5
-- --------------------------------------------------------------------------

if not Mixin then
    function Mixin(object, ...)
        for i = 1, select("#", ...) do
            local mixin = select(i, ...)
            if mixin then
                for key, value in pairs(mixin) do
                    object[key] = value
                end
            end
        end
        return object
    end
end

if not CreateFromMixins then
    function CreateFromMixins(...)
        return Mixin({}, ...)
    end
end

-- Never manufacture Blizzard's global securecallfunction.  A Lua-defined
-- replacement is insecure and can taint protected action buttons, logout, and
-- other secure FrameXML paths merely because they resolve that global.  Keep
-- the fallback private to this addon instead.
Legacy.SafeCall = securecallfunction or function(func, ...)
    if type(func) == "function" then
        return func(...)
    end
end

if not GetTimePreciseSec and GetTime then
    GetTimePreciseSec = GetTime
end

if not GetPhysicalScreenSize then
    function GetPhysicalScreenSize()
        if GetScreenWidth and GetScreenHeight then
            return GetScreenWidth(), GetScreenHeight()
        end

        local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        local width = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 1024
        local height = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 768
        return width * scale, height * scale
    end
end

if not BreakUpLargeNumbers then
    function BreakUpLargeNumbers(value)
        local number = tonumber(value) or 0
        local sign = number < 0 and "-" or ""
        local integer = tostring(floor(math.abs(number) + 0.5))
        local grouped

        repeat
            integer, grouped = string.gsub(integer, "^(%d+)(%d%d%d)", "%1,%2")
        until grouped == 0

        return sign .. integer
    end
end

if not FormatLargeNumber then
    FormatLargeNumber = BreakUpLargeNumbers
end

if not StripHyperlinks then
    function StripHyperlinks(text)
        text = tostring(text or "")
        text = string.gsub(text, "|H[^|]+|h([^|]*)|h", "%1")
        text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
        text = string.gsub(text, "|r", "")
        return text
    end
end

if not CreateColor then
    local LegacyColorMixin = {}

    function LegacyColorMixin:GetRGB()
        return self.r, self.g, self.b
    end

    function LegacyColorMixin:GetRGBA()
        return self.r, self.g, self.b, self.a
    end

    function LegacyColorMixin:SetRGB(r, g, b)
        self.r, self.g, self.b = r, g, b
    end

    function LegacyColorMixin:SetRGBA(r, g, b, a)
        self.r, self.g, self.b, self.a = r, g, b, a
    end

    function LegacyColorMixin:GenerateHexColor()
        local function Byte(value)
            value = math.max(0, math.min(1, tonumber(value) or 0))
            return floor(value * 255 + 0.5)
        end
        return string.format("%02x%02x%02x%02x", Byte(self.a), Byte(self.r), Byte(self.g), Byte(self.b))
    end

    function CreateColor(r, g, b, a)
        return Mixin({r = r or 0, g = g or 0, b = b or 0, a = a == nil and 1 or a}, LegacyColorMixin)
    end
end

if not CreateVector2D then
    local LegacyVector2DMixin = {}

    function LegacyVector2DMixin:GetXY()
        return self.x, self.y
    end

    function CreateVector2D(x, y)
        return Mixin({x = x or 0, y = y or 0, X = x or 0, Y = y or 0}, LegacyVector2DMixin)
    end
end

if not CreateVector3D then
    local LegacyVector3DMixin = {}

    function LegacyVector3DMixin:GetXYZ()
        return self.x, self.y, self.z
    end

    function CreateVector3D(x, y, z)
        return Mixin({x = x or 0, y = y or 0, z = z or 0}, LegacyVector3DMixin)
    end
end

if not GetMouseFoci and GetMouseFocus then
    function GetMouseFoci()
        local focus = GetMouseFocus()
        if focus then
            return {focus}
        end
        return {}
    end
end

if not IsUnitModelReadyForUI then
    function IsUnitModelReadyForUI(unit)
        return not UnitExists or UnitExists(unit)
    end
end


-- --------------------------------------------------------------------------
-- UI object method fallbacks
-- --------------------------------------------------------------------------

local NativeCreateFrame = CreateFrame

local function SetShownFallback(self, shown)
    if shown then
        self:Show()
    else
        self:Hide()
    end
end

local function SetSizeFallback(self, width, height)
    self:SetWidth(width)
    self:SetHeight(height)
end

local function NoOperation()
end

local function AttachRegionCompatibility(region)
    if not region then
        return region
    end

    if not region.SetShown then
        region.SetShown = SetShownFallback
    end
    if not region.SetSize then
        region.SetSize = SetSizeFallback
    end
    -- Retail Texture:SetTexture accepts wrap/filter arguments after a file.
    -- The 3.3.5 signature does not; retain the legacy numeric color overload.
    if region.SetTexture and not region.__DialogueUILegacySetTexture then
        region.__DialogueUILegacySetTexture = region.SetTexture
        region.SetTexture = function(self, texture, second, third, fourth)
            if type(texture) == "number" and type(second) == "number" and type(third) == "number" then
                return self.__DialogueUILegacySetTexture(self, texture, second, third, fourth)
            elseif type(texture) == "number" then
                -- Retail file IDs are not accepted by this client's texture
                -- loader. Static cases are mapped at their call sites; keep a
                -- visible fallback for any server-supplied modern ID.
                return self.__DialogueUILegacySetTexture(self, "Interface\\Icons\\INV_Misc_QuestionMark")
            end
            return self.__DialogueUILegacySetTexture(self, texture)
        end
    end
    if not region.SetTexelSnappingBias then
        region.SetTexelSnappingBias = NoOperation
    end
    if not region.SetSnapToPixelGrid then
        region.SetSnapToPixelGrid = NoOperation
    end
    if not region.SetTextureSliceMode then
        region.SetTextureSliceMode = NoOperation
    end
    if not region.SetTextureSliceMargins then
        region.SetTextureSliceMargins = NoOperation
    end
    if not region.ClearTextureSlice then
        region.ClearTextureSlice = NoOperation
    end
    if not region.SetAtlas then
        region.SetAtlas = function(self)
            self:SetTexture(nil)
        end
    end
    if not region.AddMaskTexture then
        region.AddMaskTexture = NoOperation
    end
    if not region.RemoveMaskTexture then
        region.RemoveMaskTexture = NoOperation
    end
    if not region.SetColorTexture and region.SetTexture and region.SetVertexColor then
        region.SetColorTexture = function(self, r, g, b, a)
            self:SetTexture("Interface\\Buttons\\WHITE8X8")
            self:SetVertexColor(r or 1, g or 1, b or 1, a == nil and 1 or a)
        end
    end
    if region.SetGradientAlpha and not region.__DialogueUILegacySetGradient then
        region.__DialogueUILegacySetGradient = region.SetGradient
        region.SetGradient = function(self, orientation, minColor, maxColor, ...)
            if type(minColor) == "table" and type(maxColor) == "table" then
                local minR, minG, minB, minA = minColor:GetRGBA()
                local maxR, maxG, maxB, maxA = maxColor:GetRGBA()
                return self:SetGradientAlpha(orientation, minR, minG, minB, minA, maxR, maxG, maxB, maxA)
            elseif self.__DialogueUILegacySetGradient then
                return self.__DialogueUILegacySetGradient(self, orientation, minColor, maxColor, ...)
            end
        end
    end
    if not region.GetUnboundedStringWidth and region.GetStringWidth then
        region.GetUnboundedStringWidth = region.GetStringWidth
    end
    if not region.GetUnboundedStringHeight and region.GetStringHeight then
        region.GetUnboundedStringHeight = region.GetStringHeight
    end
    if not region.GetWrappedWidth and region.GetStringWidth then
        region.GetWrappedWidth = region.GetStringWidth
    end
    if not region.GetWrappedHeight and region.GetStringHeight then
        region.GetWrappedHeight = region.GetStringHeight
    end
    if not region.GetNumLines and region.GetStringHeight and region.GetFont then
        region.GetNumLines = function(self)
            local _, fontHeight = self:GetFont()
            local stringHeight = self:GetStringHeight() or 0
            fontHeight = tonumber(fontHeight) or 0
            if stringHeight <= 0 then
                return 0
            elseif fontHeight <= 0 then
                return 1
            end
            local spacing = self.GetSpacing and tonumber(self:GetSpacing()) or 0
            spacing = spacing or 0
            return math.max(1, floor((stringHeight + spacing) / (fontHeight + spacing) + 0.5))
        end
    end
    if not region.IsTruncated and region.GetStringWidth and region.GetWidth then
        region.IsTruncated = function(self)
            local maxLines = self.__DialogueUIMaxLines or 0
            if maxLines > 0 and self.GetStringHeight and self.GetFont then
                local _, fontHeight = self:GetFont()
                fontHeight = tonumber(fontHeight) or 0
                if fontHeight > 0 then
                    local textScale = self.GetTextScale and tonumber(self:GetTextScale()) or 1
                    local lineHeight = fontHeight * (textScale or 1)
                    local renderedHeight = self:GetStringHeight() or 0
                    local lineCount = math.max(1, math.floor((renderedHeight + lineHeight - 0.5) / lineHeight))
                    if lineCount > maxLines then
                        return true
                    end
                end
            end
            local width = self:GetWidth() or 0
            if width > 0 and self:GetStringWidth() > width + 0.5 then
                return true
            end
            -- Wrapped text can fit horizontally while still being clipped by
            -- an explicit one-/two-line height. Include the rendered vertical
            -- extent so long localized titles still trigger autoscaling.
            if self.GetStringHeight and self.GetHeight then
                local height = self:GetHeight() or 0
                return height > 0 and self:GetStringHeight() > height + 0.5
            end
            return false
        end
    end
    if not region.SetTextScale and region.GetFont and (region.SetTextHeight or region.SetFont) then
        region.SetTextScale = function(self, scale)
            scale = tonumber(scale) or 1
            local file, currentSize, flags = self:GetFont()
            if file and currentSize then
                self.__DialogueUITextScale = scale
                if self.SetTextHeight then
                    -- SetTextHeight is native on 3.3.5 and scales the rendered
                    -- glyphs without changing GetFont's base point size. This
                    -- preserves Retail's GetFont/GetTextScale contract.
                    self:SetTextHeight(currentSize * scale)
                else
                    local oldScale = self.__DialogueUITextAppliedScale or 1
                    local baseSize = currentSize / oldScale
                    self.__DialogueUITextAppliedScale = scale
                    self:SetFont(file, baseSize * scale, flags)
                end
            end
        end
    end
    if not region.GetTextScale and region.GetFont then
        region.GetTextScale = function(self)
            return self.__DialogueUITextScale or 1
        end
    end
    if not region.SetMaxLines and region.SetHeight then
        region.SetMaxLines = function(self, maxLines)
            maxLines = math.max(0, floor(tonumber(maxLines) or 0))
            self.__DialogueUIMaxLines = maxLines
            if maxLines > 0 and self.GetFont then
                local _, fontHeight = self:GetFont()
                fontHeight = tonumber(fontHeight) or 0
                if fontHeight > 0 then
                    local spacing = self.GetSpacing and tonumber(self:GetSpacing()) or 0
                    spacing = spacing or 0
                    self:SetHeight(maxLines * fontHeight + math.max(0, maxLines - 1) * spacing)
                end
            elseif maxLines == 0 then
                self:SetHeight(0)
            end
        end
    end
    if not region.GetMaxLines then
        region.GetMaxLines = function(self) return self.__DialogueUIMaxLines or 0 end
    end
    if not region.SetSpacing then
        region.SetSpacing = NoOperation
    end
    if not region.GetSpacing then
        region.GetSpacing = function() return 0 end
    end
    if not region.SetNonSpaceWrap then
        region.SetNonSpaceWrap = NoOperation
    end
    if not region.SetIndentedWordWrap then
        region.SetIndentedWordWrap = NoOperation
    end

    return region
end

local function AttachFrameCompatibility(frame, frameType)
    if not frame then
        return frame
    end
    if frame.__DialogueUILegacyCompatible then
        return frame
    end
    frame.__DialogueUILegacyCompatible = true

    AttachRegionCompatibility(frame)

    if not frame.SetClipsChildren then
        frame.SetClipsChildren = NoOperation
    end
    if not frame.SetFlattensRenderLayers then
        frame.SetFlattensRenderLayers = NoOperation
    end
    if not frame.SetIgnoreParentAlpha then
        frame.SetIgnoreParentAlpha = NoOperation
    end
    if not frame.SetIgnoreParentScale then
        frame.SetIgnoreParentScale = NoOperation
    end
    if not frame.SetPropagateKeyboardInput then
        frame.SetPropagateKeyboardInput = NoOperation
    end
    if not frame.ClearHighlightText and frame.HighlightText then
        frame.ClearHighlightText = function(self)
            self:HighlightText(0, 0)
        end
    end
    if not frame.IsMouseMotionFocus and frame.IsMouseOver then
        frame.IsMouseMotionFocus = frame.IsMouseOver
    end
    if not frame.IsFocused and frame.IsMouseOver then
        frame.IsFocused = frame.IsMouseOver
    end
    if not frame.EnableGamePadButton then
        frame.EnableGamePadButton = NoOperation
    end
    if not frame.EnableGamePadStick then
        frame.EnableGamePadStick = NoOperation
    end
    if not frame.SetFixedFrameLevel then
        frame.SetFixedFrameLevel = NoOperation
    end
    if not frame.SetFixedFrameStrata then
        frame.SetFixedFrameStrata = NoOperation
    end
    if not frame.SetUseParentLevel then
        frame.SetUseParentLevel = NoOperation
    end
    if not frame.SetUsingParentLevel then
        frame.SetUsingParentLevel = NoOperation
    end
    if not frame.SetToplevel then
        frame.SetToplevel = NoOperation
    end
    if not frame.EnableMouseMotion and frame.EnableMouse then
        frame.EnableMouseMotion = frame.EnableMouse
    end
    if not frame.SetEnabled then
        frame.SetEnabled = function(self, enabled)
            if enabled and self.Enable then
                self:Enable()
            elseif (not enabled) and self.Disable then
                self:Disable()
            elseif self.EnableMouse then
                self:EnableMouse(enabled)
            end
        end
    end
    if not frame.SetResizeBounds and frame.SetMinResize then
        frame.SetResizeBounds = function(self, minWidth, minHeight, maxWidth, maxHeight)
            self:SetMinResize(minWidth, minHeight)
            if maxWidth and maxHeight and self.SetMaxResize then
                self:SetMaxResize(maxWidth, maxHeight)
            end
        end
    end

    -- This client raises a Lua error for unknown event names instead of simply
    -- ignoring them. Retail modules contain several feature-specific events,
    -- so make registrations capability-safe for frames created by this addon.
    if frame.RegisterEvent and not frame.__DialogueUILegacyRegisterEvent then
        frame.__DialogueUILegacyRegisterEvent = frame.RegisterEvent
        frame.RegisterEvent = function(self, event)
            if Legacy.RegisterPseudoEvent and Legacy.RegisterPseudoEvent(self, event) then
                return true
            end
            local ok, registered = pcall(self.__DialogueUILegacyRegisterEvent, self, event)
            if ok then
                return registered
            end
            return false
        end
    end
    if frame.UnregisterEvent and not frame.__DialogueUILegacyUnregisterEvent then
        frame.__DialogueUILegacyUnregisterEvent = frame.UnregisterEvent
        frame.UnregisterEvent = function(self, event)
            if Legacy.UnregisterPseudoEvent and Legacy.UnregisterPseudoEvent(self, event) then
                return true
            end
            local ok, result = pcall(self.__DialogueUILegacyUnregisterEvent, self, event)
            if ok then
                return result
            end
            return false
        end
    end
    if frame.UnregisterAllEvents and not frame.__DialogueUILegacyUnregisterAllEvents then
        frame.__DialogueUILegacyUnregisterAllEvents = frame.UnregisterAllEvents
        frame.UnregisterAllEvents = function(self)
            if Legacy.UnregisterAllPseudoEvents then
                Legacy.UnregisterAllPseudoEvents(self)
            end
            return self.__DialogueUILegacyUnregisterAllEvents(self)
        end
    end
    if frame.IsEventRegistered and not frame.__DialogueUILegacyIsEventRegistered then
        frame.__DialogueUILegacyIsEventRegistered = frame.IsEventRegistered
        frame.IsEventRegistered = function(self, event)
            if Legacy.IsPseudoEventRegistered and Legacy.IsPseudoEventRegistered(self, event) then
                return true
            end
            return self.__DialogueUILegacyIsEventRegistered(self, event)
        end
    end
    -- Unknown script handler names (notably every GamePad handler and
    -- OnModelLoaded) also raise on the legacy client. Keep ordinary handlers
    -- intact while making optional Retail-only scripts capability-safe.
    if frame.SetScript and not frame.__DialogueUILegacySetScript then
        frame.__DialogueUILegacySetScript = frame.SetScript
        frame.SetScript = function(self, scriptType, handler)
            local ok, result = pcall(self.__DialogueUILegacySetScript, self, scriptType, handler)
            if ok then
                return result
            end
            return false
        end
    end
    if not frame.RegisterUnitEvent and frame.RegisterEvent then
        frame.RegisterUnitEvent = function(self, event)
            return self:RegisterEvent(event)
        end
    end

    if frame.CreateTexture and not frame.__DialogueUILegacyCreateTexture then
        frame.__DialogueUILegacyCreateTexture = frame.CreateTexture
        frame.CreateTexture = function(self, ...)
            return AttachRegionCompatibility(self.__DialogueUILegacyCreateTexture(self, ...))
        end
    end

    if frame.CreateFontString and not frame.__DialogueUILegacyCreateFontString then
        frame.__DialogueUILegacyCreateFontString = frame.CreateFontString
        frame.CreateFontString = function(self, ...)
            return AttachRegionCompatibility(self.__DialogueUILegacyCreateFontString(self, ...))
        end
    end

    if not frame.CreateMaskTexture and frame.CreateTexture then
        frame.CreateMaskTexture = function(self, name, layer, template, subLevel)
            local texture = self:CreateTexture(name, layer, template, subLevel)
            texture:Hide()
            return texture
        end
    end

    local isModel = frameType == "Model" or frameType == "PlayerModel" or frameType == "DressUpModel"
    if isModel then
        if not frame.SetAnimation and frame.SetSequence then
            frame.SetAnimation = frame.SetSequence
        end
        if not frame.SetCameraID and frame.SetCamera then
            frame.SetCameraID = frame.SetCamera
        end
        if not frame.SetModelByCreatureDisplayID and frame.SetDisplayInfo then
            frame.SetModelByCreatureDisplayID = frame.SetDisplayInfo
        end
        if not frame.SetModelByFileID and frame.SetModel then
            frame.SetModelByFileID = frame.SetModel
        end
        if not frame.SetModelAlpha and frame.SetAlpha then
            frame.SetModelAlpha = frame.SetAlpha
        end
        if not frame.SetModelDrawLayer then
            frame.SetModelDrawLayer = NoOperation
        end
        if not frame.SetKeepModelOnHide then
            frame.SetKeepModelOnHide = NoOperation
        end
        if not frame.SetParticlesEnabled then
            frame.SetParticlesEnabled = NoOperation
        end
        if not frame.SetPreferModelCollisionBounds then
            frame.SetPreferModelCollisionBounds = NoOperation
        end
        if not frame.SetAutoDress then
            frame.SetAutoDress = NoOperation
        end
        if not frame.SetDoBlend then
            frame.SetDoBlend = NoOperation
        end
        if not frame.UseModelCenterToTransform then
            frame.UseModelCenterToTransform = NoOperation
        end
        if not frame.SetPitch then
            frame.SetPitch = NoOperation
        end
        if not frame.SetRoll then
            frame.SetRoll = NoOperation
        end
        if not frame.FreezeAnimation then
            frame.FreezeAnimation = function(self, animation, variation, frameTime)
                if self.SetSequence then
                    self:SetSequence(animation or 0)
                end
                if self.SetSequenceTime then
                    self:SetSequenceTime(animation or 0, frameTime or 0)
                end
            end
        end
        if not frame.SetUseTransmogChoices then
            frame.SetUseTransmogChoices = NoOperation
        end
        if not frame.SetUseTransmogSkin then
            frame.SetUseTransmogSkin = NoOperation
        end
        if not frame.SetItem and frame.TryOn then
            frame.SetItem = function(self, item)
                return self:TryOn(item)
            end
        end
    end

    return frame
end

-- NativeCreateFrame constructs inherited XML children and regions before it
-- returns. Walk the completed object tree so deferred template instances get
-- the same compatibility methods as their Lua-created root.
local function AttachDialogueUIObjectTree(root, rootType)
    local visited = {}
    local attached = 0

    local function AttachObjectTree(frame, knownType)
        if not frame or visited[frame] or attached >= 4096 then
            return
        end
        visited[frame] = true
        attached = attached + 1

        local objectType = knownType or "Frame"
        if not knownType and frame.GetObjectType then
            local ok, detectedType = pcall(frame.GetObjectType, frame)
            if ok and detectedType then
                objectType = detectedType
            end
        end
        AttachFrameCompatibility(frame, objectType)

        if frame.GetRegions then
            local regions = {frame:GetRegions()}
            for _, region in ipairs(regions) do
                AttachRegionCompatibility(region)
            end
        end

        if frame.GetChildren then
            local children = {frame:GetChildren()}
            for _, child in ipairs(children) do
                AttachObjectTree(child)
            end
        end
    end

    AttachObjectTree(root, rootType)
    return root
end

local LegacyTemplateLineLimits = {
    DUIDialogItemButtonTemplate = {"Name", 2},
    DUIDialogSmallItemButtonTemplate = {"Name", 1},
    DUIDialogHeaderWidgetTemplate = {"ButtonText", 1},
    DUIDialogSettingsArrowOptionTemplate = {"ValueText", 1},
    DUIDialogSettingsDropdownButtonTemplate = {"ValueText", 1},
    DUIDialogSettingsKeybindingTemplate = {"ValueText", 1},
    DUIItemActionButtonTemplate = {"ButtonText", 1},
}

local function ApplyLegacyTemplateLineLimit(frame, template)
    local data = template and LegacyTemplateLineLimits[template]
    local fontString = data and frame and frame[data[1]]
    if fontString and fontString.SetMaxLines then
        fontString:SetMaxLines(data[2])
    end
end

local function DialogueUICreateFrame(frameType, ...)
    -- ModelScene and Actor do not exist in the 3.3.5 renderer. Calls into that
    -- feature are disabled in API.lua; this guard prevents a client parser error
    -- if an optional path tries to instantiate one anyway.
    if frameType == "ModelScene" or frameType == "Actor" then
        return nil
    end
    local _, _, template = ...
    if type(template) == "string" and string.find(template, "SecureActionButtonTemplate", 1, true) then
        -- Secure frames must retain their native methods.  Replacing SetScript,
        -- RegisterEvent, CreateTexture, etc. on one of these frames taints the
        -- protected action path and can spill into action-bar addons.
        return NativeCreateFrame(frameType, ...)
    end
    local frame = AttachDialogueUIObjectTree(NativeCreateFrame(frameType, ...), frameType)
    ApplyLegacyTemplateLineLimit(frame, template)
    return frame
end

Legacy.AttachFrameCompatibility = AttachFrameCompatibility
Legacy.AttachRegionCompatibility = AttachRegionCompatibility
Legacy.NativeCreateFrame = NativeCreateFrame
Legacy.CreateFrame = DialogueUICreateFrame

-- GLOBAL_MOUSE_DOWN/UP were introduced after 3.3.5. Emulate their edge
-- semantics from the documented mouse-button state API so outside-click
-- dismissal, swipe scrolling, dropdowns and widget dragging remain functional.
do
    -- Some 3.3.5-derived clients backport QUEST_TURNED_IN. Prefer their real
    -- event and payload when available; Ascension 12340 throws for the name,
    -- so it continues to use the verified legacy synthesis below.
    local NativeQuestTurnedInAvailable = false
    do
        local probe = NativeCreateFrame("Frame")
        NativeQuestTurnedInAvailable = pcall(probe.RegisterEvent, probe, "QUEST_TURNED_IN")
        if NativeQuestTurnedInAvailable then
            probe:UnregisterEvent("QUEST_TURNED_IN")
        end
    end

    local PseudoListeners = {
        GLOBAL_MOUSE_DOWN = setmetatable({}, {__mode = "k"}),
        GLOBAL_MOUSE_UP = setmetatable({}, {__mode = "k"}),
        QUEST_TURNED_IN = setmetatable({}, {__mode = "k"}),
    }
    local MousePseudoEvents = {
        GLOBAL_MOUSE_DOWN = true,
        GLOBAL_MOUSE_UP = true,
    }
    local MouseButtons = {"LeftButton", "RightButton", "MiddleButton"}
    local ButtonState = {}
    local MouseListenerCount = 0
    local MouseDispatcher = AttachFrameCompatibility(NativeCreateFrame("Frame"), "Frame")

    local function GetButtonState(button)
        local ok, down = pcall(IsMouseButtonDown, button)
        return ok and down and true or false
    end

    local function Dispatch(event, ...)
        for frame in pairs(PseudoListeners[event]) do
            local handler = frame.GetScript and frame:GetScript("OnEvent")
            if handler then
                local ok, message = pcall(handler, frame, event, ...)
                if not ok and geterrorhandler then
                    geterrorhandler()(message)
                end
            end
        end
    end

    local function PollMouseButtons()
        for _, button in ipairs(MouseButtons) do
            local down = GetButtonState(button)
            if down ~= ButtonState[button] then
                ButtonState[button] = down
                Dispatch(down and "GLOBAL_MOUSE_DOWN" or "GLOBAL_MOUSE_UP", button)
            end
        end
    end

    local function StartPolling()
        for _, button in ipairs(MouseButtons) do
            ButtonState[button] = GetButtonState(button)
        end
        MouseDispatcher:SetScript("OnUpdate", PollMouseButtons)
    end

    local function StopPollingIfIdle()
        if MouseListenerCount <= 0 then
            MouseListenerCount = 0
            MouseDispatcher:SetScript("OnUpdate", nil)
        end
    end

    function Legacy.RegisterPseudoEvent(frame, event)
        if event == "QUEST_TURNED_IN" and NativeQuestTurnedInAvailable then
            return false
        end
        local listeners = PseudoListeners[event]
        if not listeners then
            return false
        end
        if not listeners[frame] then
            listeners[frame] = true
            if MousePseudoEvents[event] then
                MouseListenerCount = MouseListenerCount + 1
                if MouseListenerCount == 1 then
                    StartPolling()
                end
            end
        end
        return true
    end

    function Legacy.UnregisterPseudoEvent(frame, event)
        if event == "QUEST_TURNED_IN" and NativeQuestTurnedInAvailable then
            return false
        end
        local listeners = PseudoListeners[event]
        if not listeners then
            return false
        end
        if listeners[frame] then
            listeners[frame] = nil
            if MousePseudoEvents[event] then
                MouseListenerCount = MouseListenerCount - 1
                StopPollingIfIdle()
            end
        end
        return true
    end

    function Legacy.UnregisterAllPseudoEvents(frame)
        for event, listeners in pairs(PseudoListeners) do
            if listeners[frame] then
                listeners[frame] = nil
                if MousePseudoEvents[event] then
                    MouseListenerCount = MouseListenerCount - 1
                end
            end
        end
        StopPollingIfIdle()
    end

    function Legacy.IsPseudoEventRegistered(frame, event)
        if event == "QUEST_TURNED_IN" and NativeQuestTurnedInAvailable then
            return false
        end
        return PseudoListeners[event] and PseudoListeners[event][frame] or false
    end

    function Legacy.DispatchPseudoEvent(event, ...)
        if event == "QUEST_TURNED_IN" and NativeQuestTurnedInAvailable then
            return false
        end
        if PseudoListeners[event] then
            Dispatch(event, ...)
            return true
        end
        return false
    end
end

-- XML-created objects bypass the Lua CreateFrame wrapper. Attach the same
-- fallbacks once this addon's XML has finished constructing, before the later
-- ADDON_LOADED handlers initialize settings and live UI behavior.
local XMLCompatibilityFrame = AttachFrameCompatibility(NativeCreateFrame("Frame"), "Frame")
XMLCompatibilityFrame:RegisterEvent("ADDON_LOADED")
XMLCompatibilityFrame:SetScript("OnEvent", function(self, event, loadedName)
    if loadedName ~= addonName then
        return
    end

    self:UnregisterEvent(event)
    local rootNames = {"DUIQuestFrame", "DUIBookFrame", "DUIDialogSettings"}
    for _, rootName in ipairs(rootNames) do
        AttachDialogueUIObjectTree(_G[rootName])
    end

    local portraitName = _G.DUIQuestFrame
        and _G.DUIQuestFrame.FrontFrame
        and _G.DUIQuestFrame.FrontFrame.QuestPortrait
        and _G.DUIQuestFrame.FrontFrame.QuestPortrait.Name
    if portraitName and portraitName.SetMaxLines then
        portraitName:SetMaxLines(2)
    end
end)


-- --------------------------------------------------------------------------
-- Enum values referenced while files are loading
-- --------------------------------------------------------------------------

local NativeEnum = type(_G.Enum) == "table" and _G.Enum or nil
local Enum = CreatePrivateNamespace(NativeEnum)

local function CreatePrivateEnum(name, defaults)
    local nativeValues = NativeEnum and type(NativeEnum[name]) == "table" and NativeEnum[name] or nil
    local values = CreatePrivateNamespace(nativeValues)
    for key, value in pairs(defaults) do
        if not nativeValues or nativeValues[key] == nil then
            values[key] = value
        end
    end
    return values
end

Enum.PlayerInteractionType = CreatePrivateEnum("PlayerInteractionType", {Gossip = 3, QuestGiver = 4})
Enum.QuestFrequency = CreatePrivateEnum("QuestFrequency", {Default = 0, Daily = 1, Weekly = 2, ResetByScheduler = 3})
Enum.QuestTag = CreatePrivateEnum("QuestTag", {Dungeon = 81, Raid = 62, Raid10 = 88, Raid25 = 89})
Enum.QuestTagType = CreatePrivateEnum("QuestTagType", {})
Enum.QuestRewardContextFlags = CreatePrivateEnum("QuestRewardContextFlags", {})
Enum.GarrisonFollowerType = CreatePrivateEnum("GarrisonFollowerType", {FollowerType_9_0_GarrisonFollower = 123})
Enum.VoiceTtsDestination = CreatePrivateEnum("VoiceTtsDestination", {LocalPlayback = 1})
Enum.TooltipDataLineType = CreatePrivateEnum("TooltipDataLineType", {SellPrice = 11})
Enum.TooltipComparisonMethod = CreatePrivateEnum("TooltipComparisonMethod", {WithBagOffHandItem = 3})
Enum.QuestCompleteSpellType = CreatePrivateEnum("QuestCompleteSpellType", {
    LegacyBehavior = 0,
    Follower = 1,
    Companion = 2,
    Tradeskill = 3,
    Ability = 4,
    Aura = 5,
    Spell = 6,
    Unlock = 7,
    QuestlineUnlock = 8,
    QuestlineReward = 9,
    QuestlineUnlockPart = 10,
    PossibleReward = 11,
})
Legacy.Enum = Enum


-- --------------------------------------------------------------------------
-- Minimal callback registry used by modern shared UI code
-- --------------------------------------------------------------------------

local NativeEventRegistry = type(_G.EventRegistry) == "table" and _G.EventRegistry or nil
local EventRegistry

-- Native EventRegistry methods keep internal state on their original object,
-- so retain that object by reference when its complete contract is available.
-- Never add fallback members to Blizzard's shared registry.
if NativeEventRegistry
    and type(NativeEventRegistry.RegisterCallback) == "function"
    and type(NativeEventRegistry.UnregisterCallback) == "function"
    and type(NativeEventRegistry.TriggerEvent) == "function"
then
    EventRegistry = NativeEventRegistry
else
    EventRegistry = {callbacks = {}, hooks = {}}

    function EventRegistry:RegisterCallback(event, callback, owner)
        if type(callback) ~= "function" then
            return
        end

        local callbacks = self.callbacks[event]
        if not callbacks then
            callbacks = {}
            self.callbacks[event] = callbacks
        end
        insert(callbacks, {callback = callback, owner = owner})

        if event == "SetItemRef" and not self.hooks.SetItemRef and hooksecurefunc and SetItemRef then
            self.hooks.SetItemRef = true
            hooksecurefunc("SetItemRef", function(...)
                EventRegistry:TriggerEvent("SetItemRef", ...)
            end)
        end
    end

    function EventRegistry:UnregisterCallback(event, owner)
        local callbacks = self.callbacks[event]
        if not callbacks then
            return
        end

        for i = #callbacks, 1, -1 do
            if callbacks[i].owner == owner then
                remove(callbacks, i)
            end
        end
    end

    function EventRegistry:TriggerEvent(event, ...)
        local callbacks = self.callbacks[event]
        if not callbacks then
            return
        end

        for _, entry in ipairs(callbacks) do
            entry.callback(entry.owner, ...)
        end
    end
end
Legacy.EventRegistry = EventRegistry


-- --------------------------------------------------------------------------
-- Timer namespace
-- --------------------------------------------------------------------------

local C_Timer = CreatePrivateNamespace(_G.C_Timer)

if not (C_Timer.After and C_Timer.NewTimer and C_Timer.NewTicker) then
    local TimerFrame = AttachFrameCompatibility(NativeCreateFrame("Frame"), "Frame")
    local callbacks = {}

    local function ReportTimerError(message)
        if geterrorhandler then
            geterrorhandler()(message)
        end
    end

    local function CreateLegacyTimer(seconds, callback, iterations, passTimer)
        if type(callback) ~= "function" then
            return
        end

        local duration = math.max(tonumber(seconds) or 0, 0)
        local timer = {
            duration = duration,
            remaining = duration,
            callback = callback,
            iterations = iterations,
            passTimer = passTimer,
            cancelled = false,
        }

        function timer:Cancel()
            self.cancelled = true
        end

        function timer:IsCancelled()
            return self.cancelled
        end

        insert(callbacks, timer)
        TimerFrame:Show()
        return timer
    end

    TimerFrame:SetScript("OnUpdate", function(self, elapsed)
        for i = #callbacks, 1, -1 do
            local timer = callbacks[i]
            if timer.cancelled then
                remove(callbacks, i)
            else
                timer.remaining = timer.remaining - elapsed
            end

            if not timer.cancelled and timer.remaining <= 0 then
                local repeats = timer.iterations == nil or timer.iterations > 1
                if repeats then
                    if timer.iterations then
                        timer.iterations = timer.iterations - 1
                    end
                    timer.remaining = timer.remaining + math.max(timer.duration, 0.01)
                    if timer.remaining <= 0 then
                        timer.remaining = math.max(timer.duration, 0.01)
                    end
                else
                    remove(callbacks, i)
                    timer.cancelled = true
                end

                local ok, message
                if timer.passTimer then
                    ok, message = pcall(timer.callback, timer)
                else
                    ok, message = pcall(timer.callback)
                end
                if not ok then
                    ReportTimerError(message)
                end

                if repeats and timer.cancelled and callbacks[i] == timer then
                    remove(callbacks, i)
                end
            end
        end

        if #callbacks == 0 then
            self:Hide()
        end
    end)
    TimerFrame:Hide()

    if not C_Timer.After then
        function C_Timer.After(seconds, callback)
            CreateLegacyTimer(seconds, callback, 1, false)
        end
    end

    if not C_Timer.NewTimer then
        function C_Timer.NewTimer(seconds, callback)
            return CreateLegacyTimer(seconds, callback, 1, true)
        end
    end

    if not C_Timer.NewTicker then
        function C_Timer.NewTicker(seconds, callback, iterations)
            if iterations ~= nil then
                iterations = math.floor(tonumber(iterations) or 0)
                if iterations < 1 then
                    local timer = CreateLegacyTimer(seconds, callback, 1, true)
                    if timer then
                        timer:Cancel()
                    end
                    return timer
                end
            end
            return CreateLegacyTimer(seconds, callback, iterations, true)
        end
    end
end

Legacy.C_Timer = C_Timer


-- --------------------------------------------------------------------------
-- AddOn and CVar namespaces
-- --------------------------------------------------------------------------

local C_AddOns = CreatePrivateNamespace(_G.C_AddOns)
C_AddOns.GetAddOnMetadata = C_AddOns.GetAddOnMetadata or GetAddOnMetadata or function() end
C_AddOns.IsAddOnLoaded = C_AddOns.IsAddOnLoaded or IsAddOnLoaded or function() return false end
C_AddOns.LoadAddOn = C_AddOns.LoadAddOn or LoadAddOn or function() return nil, "MISSING" end
C_AddOns.GetAddOnInfo = C_AddOns.GetAddOnInfo or GetAddOnInfo or function() end
C_AddOns.GetNumAddOns = C_AddOns.GetNumAddOns or GetNumAddOns or function() return 0 end
Legacy.C_AddOns = C_AddOns

local C_CVar = CreatePrivateNamespace(_G.C_CVar)
C_CVar.GetCVar = C_CVar.GetCVar or GetCVar or function() end
C_CVar.SetCVar = C_CVar.SetCVar or SetCVar or NoOperation
C_CVar.GetCVarBool = C_CVar.GetCVarBool or function(name)
    local value = C_CVar.GetCVar(name)
    return value == true or value == 1 or value == "1"
end
Legacy.C_CVar = C_CVar


-- --------------------------------------------------------------------------
-- Item, bag, spell, currency, and map namespaces
-- --------------------------------------------------------------------------

local function GetItemID(item)
    if type(item) == "number" then
        return item
    elseif type(item) == "string" then
        return tonumber(string.match(item, "item:(%d+)")) or tonumber(item)
    end
end

local C_Item = CreatePrivateNamespace(_G.C_Item)
C_Item.GetItemInfo = C_Item.GetItemInfo or GetItemInfo or function() end
C_Item.GetItemCount = C_Item.GetItemCount or GetItemCount or function() return 0 end
C_Item.GetItemIDForItemInfo = C_Item.GetItemIDForItemInfo or GetItemID
C_Item.GetItemIconByID = C_Item.GetItemIconByID or function(item)
    return GetItemInfo and select(10, GetItemInfo(item))
end
C_Item.GetItemNameByID = C_Item.GetItemNameByID or function(item)
    return GetItemInfo and GetItemInfo(item)
end
C_Item.GetItemQualityByID = C_Item.GetItemQualityByID or function(item)
    return GetItemInfo and select(3, GetItemInfo(item))
end
C_Item.GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo or function(item)
    return GetItemInfo and select(4, GetItemInfo(item)) or 0
end
C_Item.IsEquippableItem = C_Item.IsEquippableItem or IsEquippableItem or function() return false end
C_Item.IsEquippedItem = C_Item.IsEquippedItem or IsEquippedItem or function() return false end
C_Item.IsDressableItemByID = C_Item.IsDressableItemByID or IsDressableItem
C_Item.IsCosmeticItem = C_Item.IsCosmeticItem or function() return false end
C_Item.IsDecorItem = C_Item.IsDecorItem or function() return false end
C_Item.RequestLoadItemDataByID = C_Item.RequestLoadItemDataByID or NoOperation
C_Item.GetItemIDByGUID = C_Item.GetItemIDByGUID or function() end
C_Item.GetItemLinkByGUID = C_Item.GetItemLinkByGUID or function() end
C_Item.GetItemInfoInstant = C_Item.GetItemInfoInstant or GetItemInfoInstant

if not C_Item.GetItemInfoInstant then
    function C_Item.GetItemInfoInstant(item)
        local itemID = GetItemID(item)
        local itemName, itemLink, quality, itemLevel, requiredLevel, itemType, itemSubType, stackCount, equipLoc, icon
        if GetItemInfo then
            itemName, itemLink, quality, itemLevel, requiredLevel, itemType, itemSubType, stackCount, equipLoc, icon = GetItemInfo(item)
        end
        return itemID, itemType, itemSubType, equipLoc, icon, nil, nil
    end
end
Legacy.C_Item = C_Item

local C_Container = CreatePrivateNamespace(_G.C_Container)
C_Container.GetContainerNumSlots = C_Container.GetContainerNumSlots or GetContainerNumSlots or function() return 0 end
C_Container.GetContainerItemID = C_Container.GetContainerItemID or GetContainerItemID or function() end
C_Container.GetItemCooldown = C_Container.GetItemCooldown or GetItemCooldown or function() return 0, 0, 0 end

if not C_Container.GetContainerItemInfo then
    function C_Container.GetContainerItemInfo(bagID, slotID)
        if not GetContainerItemInfo then
            return
        end

        local iconFileID, stackCount, isLocked, quality, isReadable, hasLoot, hyperlink = GetContainerItemInfo(bagID, slotID)
        if not iconFileID and not hyperlink then
            return
        end

        return {
            iconFileID = iconFileID,
            stackCount = stackCount or 0,
            isLocked = isLocked,
            quality = quality,
            isReadable = isReadable,
            hasLoot = hasLoot,
            hyperlink = hyperlink,
            itemID = C_Container.GetContainerItemID(bagID, slotID),
        }
    end
end

if not C_Container.GetContainerItemQuestInfo then
    function C_Container.GetContainerItemQuestInfo(bagID, slotID)
        if not GetContainerItemQuestInfo then
            return
        end
        local isQuestItem, questID, isActive = GetContainerItemQuestInfo(bagID, slotID)
        if not isQuestItem and not questID then
            return
        end
        return {isQuestItem = isQuestItem, questID = questID, isActive = isActive}
    end
end
Legacy.C_Container = C_Container

local C_Spell = CreatePrivateNamespace(_G.C_Spell)
C_Spell.DoesSpellExist = C_Spell.DoesSpellExist or function(spellID)
    return spellID and GetSpellInfo and GetSpellInfo(spellID) ~= nil or false
end
C_Spell.RequestLoadSpellData = C_Spell.RequestLoadSpellData or NoOperation
C_Spell.GetSpellInfo = C_Spell.GetSpellInfo or function(spellID)
    if not GetSpellInfo then
        return
    end
    -- Ascension's documented 3.3.5 tuple keeps the legacy power fields in
    -- slots 4-6; casting time and ranges are slots 7-9.
    local name, rank, iconID, powerCost, isFunnel, powerType, castTime, minRange, maxRange = GetSpellInfo(spellID)
    if not name then
        return
    end
    return {name = name, rank = rank, iconID = iconID, castTime = castTime, minRange = minRange, maxRange = maxRange, spellID = spellID}
end
Legacy.C_Spell = C_Spell

C_CurrencyInfo = C_CurrencyInfo or {}
C_CurrencyInfo.GetCurrencyInfo = C_CurrencyInfo.GetCurrencyInfo or function(currencyID)
    if not GetCurrencyInfo then
        return
    end
    local name, amount, icon = GetCurrencyInfo(currencyID)
    if not name then
        return
    end
    return {name = name, quantity = amount or 0, iconFileID = icon, icon = icon}
end
C_CurrencyInfo.GetCurrencyContainerInfo = C_CurrencyInfo.GetCurrencyContainerInfo or function() end
C_CurrencyInfo.GetFactionGrantedByCurrency = C_CurrencyInfo.GetFactionGrantedByCurrency or function() end
C_CurrencyInfo.GetCoinTextureString = C_CurrencyInfo.GetCoinTextureString or GetCoinTextureString or function(money)
    return GetCoinText and GetCoinText(money) or tostring(money or 0)
end

local C_Map = CreatePrivateNamespace(_G.C_Map)
C_Map.GetBestMapForUnit = C_Map.GetBestMapForUnit or function(unit)
    if SetMapToCurrentZone then
        SetMapToCurrentZone()
    end
    return GetCurrentMapAreaID and GetCurrentMapAreaID()
end
C_Map.GetPlayerMapPosition = C_Map.GetPlayerMapPosition or function(uiMapID, unit)
    if not GetPlayerMapPosition then
        return
    end
    local x, y = GetPlayerMapPosition(unit or "player")
    if x and y then
        return CreateVector2D(x, y)
    end
end
C_Map.GetMapInfo = C_Map.GetMapInfo or function(uiMapID)
    local name = GetMapNameByID and GetMapNameByID(uiMapID)
    if name then
        return {mapID = uiMapID, name = name}
    end
end
C_Map.GetAreaInfo = C_Map.GetAreaInfo or function(areaID)
    return GetMapNameByID and GetMapNameByID(areaID)
end
C_Map.GetWorldPosFromMapPos = C_Map.GetWorldPosFromMapPos or function() end
C_Map.GetMapWorldSize = C_Map.GetMapWorldSize or function() return 0, 0 end
Legacy.C_Map = C_Map


-- --------------------------------------------------------------------------
-- Quest log namespace
-- --------------------------------------------------------------------------

local function NormalizeBoolean(value)
    return value == true or value == 1
end

local NativeGetQuestLogIndexByID = _G.GetQuestLogIndexByID
local QuestTitleCache = {}
Legacy.QuestTitleCache = QuestTitleCache

local function GetQuestLogEntry(index)
    if not GetQuestLogTitle or not index then
        return
    end

    local title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily, questID = GetQuestLogTitle(index)
    if not title then
        return
    end

    local normalizedQuestID = tonumber(questID) or 0
    if normalizedQuestID > 0 then
        QuestTitleCache[normalizedQuestID] = title
    end

    return {
        title = title,
        level = level or 0,
        questTag = questTag,
        suggestedGroup = suggestedGroup or 0,
        isHeader = NormalizeBoolean(isHeader),
        isCollapsed = NormalizeBoolean(isCollapsed),
        isComplete = NormalizeBoolean(isComplete),
        frequency = NormalizeBoolean(isDaily) and 1 or 0,
        isDaily = NormalizeBoolean(isDaily),
        questID = normalizedQuestID,
        isTask = false,
        isBounty = false,
        isStory = false,
        isAutoComplete = false,
        isHidden = false,
    }
end

local function FindQuestLogIndexByID(questID)
    questID = tonumber(questID)
    if not questID or questID <= 0 then
        return
    end

    local numEntries = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
    for index = 1, numEntries do
        local info = GetQuestLogEntry(index)
        if info and info.questID == questID then
            return index
        end
    end
end

local function FindQuestLogIndexByTitle(title)
    if type(title) ~= "string" or title == "" then
        return
    end

    local numEntries = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
    for index = 1, numEntries do
        local info = GetQuestLogEntry(index)
        if info and not info.isHeader and info.title == title then
            return index
        end
    end
end

local C_QuestLog = CreatePrivateNamespace(_G.C_QuestLog)
C_QuestLog.GetLogIndexForQuestID = C_QuestLog.GetLogIndexForQuestID or NativeGetQuestLogIndexByID or FindQuestLogIndexByID
C_QuestLog.GetNumQuestLogEntries = C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries or function() return 0, 0 end
C_QuestLog.GetInfo = C_QuestLog.GetInfo or GetQuestLogEntry
C_QuestLog.GetQuestIDForLogIndex = C_QuestLog.GetQuestIDForLogIndex or function(index)
    local info = GetQuestLogEntry(index)
    return info and info.questID or 0
end
C_QuestLog.GetMaxNumQuestsCanAccept = C_QuestLog.GetMaxNumQuestsCanAccept or function() return 25 end
C_QuestLog.RequestLoadQuestByID = C_QuestLog.RequestLoadQuestByID or NoOperation
C_QuestLog.GetTitleForQuestID = C_QuestLog.GetTitleForQuestID or function(questID)
    if GetTitleForQuestID then
        local title = GetTitleForQuestID(questID)
        if title and title ~= "" then
            return title
        end
    end
    local info = GetQuestLogEntry(FindQuestLogIndexByID(questID))
    return info and info.title or QuestTitleCache[questID]
end
C_QuestLog.GetQuestInfo = C_QuestLog.GetQuestInfo or C_QuestLog.GetTitleForQuestID
C_QuestLog.IsOnQuest = C_QuestLog.IsOnQuest or function(questID)
    return FindQuestLogIndexByID(questID) ~= nil
end
C_QuestLog.ReadyForTurnIn = C_QuestLog.ReadyForTurnIn or function(questID)
    local info = GetQuestLogEntry(FindQuestLogIndexByID(questID))
    return info and info.isComplete or false
end
C_QuestLog.IsQuestTrivial = C_QuestLog.IsQuestTrivial or function(questID)
    local info = GetQuestLogEntry(FindQuestLogIndexByID(questID))
    local greenRange = GetQuestGreenRange and GetQuestGreenRange() or 5
    local playerLevel = UnitLevel and UnitLevel("player") or 1
    return info and info.level > 0 and info.level <= playerLevel - greenRange or false
end
C_QuestLog.IsQuestTask = C_QuestLog.IsQuestTask or function() return false end
C_QuestLog.IsWorldQuest = C_QuestLog.IsWorldQuest or function() return false end
C_QuestLog.IsAccountQuest = C_QuestLog.IsAccountQuest or function() return false end
C_QuestLog.IsQuestFlaggedCompletedOnAccount = C_QuestLog.IsQuestFlaggedCompletedOnAccount or function() return false end
C_QuestLog.QuestCanHaveWarModeBonus = C_QuestLog.QuestCanHaveWarModeBonus or function() return false end
C_QuestLog.QuestHasQuestSessionBonus = C_QuestLog.QuestHasQuestSessionBonus or function() return false end
C_QuestLog.AddQuestWatch = C_QuestLog.AddQuestWatch or AddQuestWatch or NoOperation
C_QuestLog.RemoveQuestWatch = C_QuestLog.RemoveQuestWatch or RemoveQuestWatch or NoOperation

local CompletedQuests = {}

local function RefreshCompletedQuests()
    if GetQuestsCompleted then
        local completed = {}
        GetQuestsCompleted(completed)
        CompletedQuests = completed
    end
end

C_QuestLog.IsQuestFlaggedCompleted = C_QuestLog.IsQuestFlaggedCompleted or function(questID)
    return CompletedQuests[questID] == true or CompletedQuests[questID] == 1
end

C_QuestLog.GetQuestTagInfo = C_QuestLog.GetQuestTagInfo or function(questID)
    local info = GetQuestLogEntry(FindQuestLogIndexByID(questID))
    local tag = info and info.questTag
    if type(tag) ~= "string" then
        return
    end

    local lowered = string.lower(tag)
    if string.find(lowered, "dungeon", 1, true) then
        return {tagID = Enum.QuestTag.Dungeon, tagName = tag}
    elseif string.find(lowered, "raid", 1, true) then
        return {tagID = Enum.QuestTag.Raid, tagName = tag}
    end
end
Legacy.C_QuestLog = C_QuestLog


-- --------------------------------------------------------------------------
-- Gossip and quest-page bridge
-- --------------------------------------------------------------------------

local Interaction = {
    gossip = false,
    quest = false,
    questPhase = nil,
    pendingQuestID = nil,
    pendingQuestTitle = nil,
    currentQuestID = nil,
    currentQuestTitle = nil,
    rewardRequested = false,
    rewardQuestID = nil,
    rewardQuestTitle = nil,
    rewardToken = 0,
    lastTurnedInQuestID = nil,
    lastTurnedInTime = nil,
    gossipOptions = {},
    activeQuests = {},
    availableQuests = {},
    greetingActiveQuests = {},
    greetingAvailableQuests = {},
}
Legacy.Interaction = Interaction

local function HashText(text)
    local hash = 5381
    text = tostring(text or "")
    for index = 1, string.len(text) do
        hash = math.fmod(hash * 33 + string.byte(text, index), 400000000)
    end
    return 1500000000 + hash
end

local function GetNPCIdentity()
    if UnitGUID then
        local guid = UnitGUID("npc")
        if guid then
            return guid
        end
    end
    if UnitName then
        return UnitName("npc") or ""
    end
    return ""
end

local function MakeSyntheticQuestID(title, listType, index)
    return HashText(table.concat({GetNPCIdentity(), listType or "quest", tostring(index or 0), title or ""}, ":"))
end

local function FindLikelyQuestID(values, firstIndex, lastIndex)
    for index = lastIndex, firstIndex, -1 do
        local value = values[index]
        if type(value) == "number" and value > 255 and value == floor(value) then
            return value
        end
    end
end

local function FindFirstString(values, firstIndex, lastIndex)
    for index = firstIndex, lastIndex do
        if type(values[index]) == "string" and values[index] ~= "" then
            return values[index]
        end
    end
end

local function FindBoolean(values, firstIndex, lastIndex, preferredIndex)
    local preferred = values[preferredIndex]
    if type(preferred) == "boolean" then
        return preferred
    end
    for index = firstIndex, lastIndex do
        if type(values[index]) == "boolean" then
            return values[index]
        end
    end
    return false
end

-- 3.3.5 Texture:SetTexture accepts paths, not Retail file IDs. Use art that
-- ships with this addon so every legacy gossip type has a guaranteed icon.
local LegacyGossipIconPath = "Interface/AddOns/DialogueUI-Ascension/Art/Icons/"
local GossipTypeIcon = {
    gossip = LegacyGossipIconPath.."Gossip.tga",
    vendor = LegacyGossipIconPath.."Buy.tga",
    trainer = LegacyGossipIconPath.."Trainer.tga",
    taxi = LegacyGossipIconPath.."Gossip.tga",
    banker = LegacyGossipIconPath.."Gossip.tga",
    auctioneer = LegacyGossipIconPath.."Gossip.tga",
    innkeeper = LegacyGossipIconPath.."Innkeeper.tga",
    battlemaster = LegacyGossipIconPath.."LFG.tga",
    binder = LegacyGossipIconPath.."Innkeeper.tga",
    healer = LegacyGossipIconPath.."Gossip.tga",
    tabard = LegacyGossipIconPath.."Gossip.tga",
    stablepet = LegacyGossipIconPath.."Stablemaster.tga",
}

local KnownGossipTypes = {}
for gossipType in pairs(GossipTypeIcon) do
    KnownGossipTypes[gossipType] = true
end
KnownGossipTypes.spiritguide = true
KnownGossipTypes.petitioner = true
KnownGossipTypes.talentwipe = true
KnownGossipTypes.armorer = true

local function ParseGossipOptionRecord(values, firstIndex, lastIndex, orderIndex)
    local name = FindFirstString(values, firstIndex, lastIndex)
    if not name then
        return
    end

    local gossipType = "gossip"
    for index = firstIndex, lastIndex do
        if type(values[index]) == "string" then
            local candidate = string.lower(values[index])
            if KnownGossipTypes[candidate] then
                gossipType = candidate
                break
            end
        end
    end

    return {
        name = name,
        orderIndex = orderIndex,
        gossipOptionID = orderIndex,
        icon = GossipTypeIcon[gossipType] or GossipTypeIcon.gossip,
        flags = 0,
        status = 0,
        legacyType = gossipType,
    }
end

local function BuildGossipOptions()
    local count = GetNumGossipOptions and GetNumGossipOptions() or 0
    local values = GetGossipOptions and {GetGossipOptions()} or {}
    local result = {}
    local stride = count > 0 and floor(#values / count) or 0

    if stride < 1 and #values > 0 then
        stride = 2
        count = floor(#values / stride)
    end

    for index = 1, count do
        local firstIndex = (index - 1) * stride + 1
        local lastIndex = math.min(#values, firstIndex + stride - 1)
        local data = ParseGossipOptionRecord(values, firstIndex, lastIndex, index)
        if data then
            result[#result + 1] = data
        end
    end

    Interaction.gossipOptions = result
    return result
end

local function GetNativeGossipQuestIDs(getter)
    if type(getter) ~= "function" then
        return
    end
    local ok, ids = pcall(getter)
    if ok and type(ids) == "table" then
        return ids
    end
end

local function BuildGossipQuestList(active)
    local count
    local values
    local listType
    local standardStride
    local nativeQuestIDs
    local completedQuestIDs

    if active then
        count = GetNumGossipActiveQuests and GetNumGossipActiveQuests() or 0
        values = GetGossipActiveQuests and {GetGossipActiveQuests()} or {}
        listType = "gossip-active"
        standardStride = 4
        nativeQuestIDs = GetNativeGossipQuestIDs(GetActiveGossipQuestIds)
        local completedIDs = GetNativeGossipQuestIDs(GetCompleteGossipQuestIds)
        if completedIDs then
            completedQuestIDs = {}
            for _, completedQuestID in ipairs(completedIDs) do
                completedQuestID = tonumber(completedQuestID)
                if completedQuestID and completedQuestID > 0 then
                    completedQuestIDs[completedQuestID] = true
                end
            end
        end
    else
        count = GetNumGossipAvailableQuests and GetNumGossipAvailableQuests() or 0
        values = GetGossipAvailableQuests and {GetGossipAvailableQuests()} or {}
        listType = "gossip-available"
        standardStride = 5
        nativeQuestIDs = GetNativeGossipQuestIDs(GetAvailableGossipQuestIds)
    end

    local result = {}
    local stride = count > 0 and floor(#values / count) or 0
    if stride < 1 and #values > 0 then
        stride = standardStride
        count = floor(#values / stride)
    end

    for index = 1, count do
        local firstIndex = (index - 1) * stride + 1
        local lastIndex = math.min(#values, firstIndex + stride - 1)
        local title = FindFirstString(values, firstIndex, lastIndex)
        if title then
            local level = tonumber(values[firstIndex + 1]) or 0
            local questID = nativeQuestIDs and tonumber(nativeQuestIDs[index]) or nil
            if not questID or questID <= 0 then
                questID = FindLikelyQuestID(values, firstIndex, lastIndex)
            end
            if active and (not questID or questID <= 0) then
                local logIndex = FindQuestLogIndexByTitle(title)
                local logInfo = GetQuestLogEntry(logIndex)
                questID = logInfo and logInfo.questID > 0 and logInfo.questID or questID
            end
            questID = questID or MakeSyntheticQuestID(title, listType, index)

            local data = {
                title = title,
                level = level,
                questLevel = level,
                questID = questID,
                orderIndex = index,
                index = index,
                isTrivial = FindBoolean(values, firstIndex, lastIndex, firstIndex + 2),
                frequency = 0,
                repeatable = false,
                isComplete = false,
                isLegendary = false,
                isIgnored = false,
            }

            if active then
                if completedQuestIDs and questID and questID > 0 then
                    data.isComplete = completedQuestIDs[questID] == true
                else
                    data.isComplete = FindBoolean(values, firstIndex, lastIndex, firstIndex + 3)
                end
            else
                local daily = FindBoolean(values, firstIndex, lastIndex, firstIndex + 3)
                data.frequency = daily and 1 or 0
                data.isDaily = daily
                data.repeatable = FindBoolean(values, firstIndex, lastIndex, firstIndex + 4)
            end

            result[#result + 1] = data
        end
    end

    if active then
        Interaction.activeQuests = result
    else
        Interaction.availableQuests = result
    end
    return result
end

local function GetQuestByID(list, questID)
    for _, questInfo in ipairs(list or {}) do
        if questInfo.questID == questID then
            return questInfo
        end
    end
end

local function RememberSelectedQuest(questInfo)
    if questInfo then
        Interaction.pendingQuestID = questInfo.questID
        Interaction.pendingQuestTitle = questInfo.title
        Interaction.currentQuestID = questInfo.questID
        Interaction.currentQuestTitle = questInfo.title
        QuestTitleCache[questInfo.questID] = questInfo.title
    end
end

-- Keep the Retail-shaped gossip facade private. Publishing it as the global
-- C_GossipInfo changes capability detection and return contracts for legacy
-- addons. Reuse a genuine server namespace, but never manufacture a global.
local NativeC_GossipInfo = type(_G.C_GossipInfo) == "table" and _G.C_GossipInfo or nil
local C_GossipInfo = NativeC_GossipInfo and setmetatable({}, {__index = NativeC_GossipInfo}) or {}
Legacy.C_GossipInfo = C_GossipInfo
C_GossipInfo.GetText = C_GossipInfo.GetText or GetGossipText or function() return "" end
C_GossipInfo.GetOptions = C_GossipInfo.GetOptions or BuildGossipOptions
C_GossipInfo.GetActiveQuests = C_GossipInfo.GetActiveQuests or function() return BuildGossipQuestList(true) end
C_GossipInfo.GetAvailableQuests = C_GossipInfo.GetAvailableQuests or function() return BuildGossipQuestList(false) end
C_GossipInfo.CloseGossip = C_GossipInfo.CloseGossip or CloseGossip or NoOperation
C_GossipInfo.ForceGossip = C_GossipInfo.ForceGossip or ForceGossip or function() return false end
C_GossipInfo.GetFriendshipReputation = C_GossipInfo.GetFriendshipReputation or function() end
C_GossipInfo.GetFriendshipReputationRanks = C_GossipInfo.GetFriendshipReputationRanks or function() end

C_GossipInfo.SelectOptionByIndex = C_GossipInfo.SelectOptionByIndex or function(index, text, confirm)
    local data = Interaction.gossipOptions[index]
    local optionText = text or data and data.name
    if SelectGossipOption then
        return SelectGossipOption(index, optionText, confirm)
    end
end

C_GossipInfo.SelectOption = C_GossipInfo.SelectOption or function(gossipOptionID, text, confirm)
    return C_GossipInfo.SelectOptionByIndex(tonumber(gossipOptionID) or 0, text, confirm)
end

C_GossipInfo.SelectActiveQuest = C_GossipInfo.SelectActiveQuest or function(questID)
    local questInfo = GetQuestByID(Interaction.activeQuests, questID)
    if not questInfo then
        BuildGossipQuestList(true)
        questInfo = GetQuestByID(Interaction.activeQuests, questID)
    end
    if questInfo then
        RememberSelectedQuest(questInfo)
        if SelectGossipActiveQuest then
            return SelectGossipActiveQuest(questInfo.index)
        end
    end
end

C_GossipInfo.SelectAvailableQuest = C_GossipInfo.SelectAvailableQuest or function(questID)
    local questInfo = GetQuestByID(Interaction.availableQuests, questID)
    if not questInfo then
        BuildGossipQuestList(false)
        questInfo = GetQuestByID(Interaction.availableQuests, questID)
    end
    if questInfo then
        RememberSelectedQuest(questInfo)
        if SelectGossipAvailableQuest then
            return SelectGossipAvailableQuest(questInfo.index)
        end
    end
end

local NativeSelectActiveQuest = SelectActiveQuest
local NativeSelectAvailableQuest = SelectAvailableQuest
local NativeGetActiveTitle = GetActiveTitle
local NativeGetAvailableTitle = GetAvailableTitle
local NativeGetAvailableQuestInfo = GetAvailableQuestInfo

local function BuildGreetingQuestList(active)
    local count = active and (GetNumActiveQuests and GetNumActiveQuests() or 0) or (GetNumAvailableQuests and GetNumAvailableQuests() or 0)
    local result = {}

    for index = 1, count do
        local title
        local isComplete = false
        local isTrivial = false
        local level = 0
        local frequency = 0
        local repeatable = false

        if active then
            local values = NativeGetActiveTitle and {NativeGetActiveTitle(index)} or {}
            title = FindFirstString(values, 1, #values)
            isComplete = FindBoolean(values, 1, #values, 2)
            level = tonumber(GetActiveLevel and GetActiveLevel(index)) or tonumber(values[2]) or 0
        else
            local values = NativeGetAvailableTitle and {NativeGetAvailableTitle(index)} or {}
            title = FindFirstString(values, 1, #values)
            level = tonumber(GetAvailableLevel and GetAvailableLevel(index)) or tonumber(values[2]) or 0

            local nativeInfo = NativeGetAvailableQuestInfo and {NativeGetAvailableQuestInfo(index)} or {}
            if type(nativeInfo[1]) == "boolean" then
                isTrivial = nativeInfo[1]
            elseif IsAvailableQuestTrivial then
                isTrivial = not not IsAvailableQuestTrivial(index)
            else
                isTrivial = FindBoolean(values, 1, #values, 3)
            end
            if type(nativeInfo[2]) == "boolean" then
                frequency = nativeInfo[2] and 1 or 0
            elseif type(nativeInfo[2]) == "number" then
                frequency = nativeInfo[2]
            else
                frequency = FindBoolean(values, 1, #values, 4) and 1 or 0
            end
            if type(nativeInfo[3]) == "boolean" then
                repeatable = nativeInfo[3]
            else
                repeatable = FindBoolean(values, 1, #values, 5)
            end
        end

        if title then
            local questID
            if active then
                local info = GetQuestLogEntry(FindQuestLogIndexByTitle(title))
                questID = info and info.questID > 0 and info.questID
            end
            questID = questID or MakeSyntheticQuestID(title, active and "greeting-active" or "greeting-available", index)

            result[#result + 1] = {
                title = title,
                questID = questID,
                index = index,
                level = level,
                isComplete = isComplete,
                isTrivial = isTrivial,
                frequency = frequency,
                repeatable = repeatable,
            }
        end
    end

    if active then
        Interaction.greetingActiveQuests = result
    else
        Interaction.greetingAvailableQuests = result
    end
    return result
end

if NativeSelectActiveQuest then
    function Legacy.SelectActiveQuest(index, ...)
        local list = BuildGreetingQuestList(true)
        RememberSelectedQuest(list[index])
        return NativeSelectActiveQuest(index, ...)
    end
end

if NativeSelectAvailableQuest then
    function Legacy.SelectAvailableQuest(index, ...)
        local list = BuildGreetingQuestList(false)
        RememberSelectedQuest(list[index])
        return NativeSelectAvailableQuest(index, ...)
    end
end

-- Expose normalized greeting functions only through this addon's namespace.
-- The original legacy globals keep their native boolean tuple for Immersion
-- and other 3.3.5 addons; Ascension custom records remain tuple-tolerant here.
function Legacy.GetAvailableTitle(index)
    local list = BuildGreetingQuestList(false)
    return list[index] and list[index].title
end

function Legacy.GetActiveTitle(index)
    local list = BuildGreetingQuestList(true)
    local info = list[index]
    if info then
        return info.title, info.isComplete
    end
end

function Legacy.GetAvailableQuestInfo(index)
    local list = BuildGreetingQuestList(false)
    local info = list[index]
    if not info then
        return false, 0, false, false, 0
    end
    return info.isTrivial, info.frequency or 0, info.repeatable, false, info.questID
end

function Legacy.GetActiveQuestID(index)
    local list = BuildGreetingQuestList(true)
    return list[index] and list[index].questID or 0
end

local function ResolveCurrentQuest()
    local title = GetTitleText and GetTitleText()
    if type(title) ~= "string" or title == "" then
        return Interaction.currentQuestID
    end

    if Interaction.pendingQuestTitle == title and Interaction.pendingQuestID then
        Interaction.currentQuestID = Interaction.pendingQuestID
        Interaction.currentQuestTitle = title
        QuestTitleCache[Interaction.currentQuestID] = title
        return Interaction.currentQuestID
    end

    local info = GetQuestLogEntry(FindQuestLogIndexByTitle(title))
    if info and info.questID > 0 then
        Interaction.currentQuestID = info.questID
    else
        Interaction.currentQuestID = MakeSyntheticQuestID(title, "current", 0)
    end
    Interaction.currentQuestTitle = title
    QuestTitleCache[Interaction.currentQuestID] = title
    return Interaction.currentQuestID
end

Legacy.GetQuestID = _G.GetQuestID
if not Legacy.GetQuestID then
    function Legacy.GetQuestID()
        return ResolveCurrentQuest() or 0
    end
end

local function IsSyntheticQuestID(questID)
    questID = tonumber(questID)
    return questID and questID >= 1500000000
end

local function DispatchLegacyQuestTurnedIn(questID, questTitle, allowSynthetic)
    questID = tonumber(questID)
    if not questID or questID <= 0 then
        return false
    end

    if IsSyntheticQuestID(questID) then
        if not allowSynthetic then
            return false
        end
    elseif FindQuestLogIndexByID(questID) then
        -- QUEST_FINISHED can also mean that a reward page was merely closed.
        -- A real turn-in removes the quest from the log, so wait for that
        -- transition before emitting the Retail-shaped completion event.
        return false
    end

    -- QUEST_FINISHED can arrive after the reward timeout on private servers.
    -- Treat a repeat dispatch for the same quest in the same short lifecycle
    -- as already handled so alerts and flyouts are not duplicated.
    local now = GetTime and GetTime() or 0
    if Interaction.lastTurnedInQuestID == questID
        and Interaction.lastTurnedInTime
        and now - Interaction.lastTurnedInTime < 3
    then
        Interaction.rewardRequested = false
        return true
    end

    if questTitle and questTitle ~= "" then
        QuestTitleCache[questID] = questTitle
    end
    Interaction.rewardRequested = false
    Interaction.lastTurnedInQuestID = questID
    Interaction.lastTurnedInTime = now
    RefreshCompletedQuests()
    if Legacy.DispatchPseudoEvent then
        Legacy.DispatchPseudoEvent("QUEST_TURNED_IN", questID, 0, 0)
    end
    return true
end
Legacy.DispatchQuestTurnedIn = DispatchLegacyQuestTurnedIn

-- DialogueUI calls this immediately before the native GetQuestReward API. It
-- keeps the Blizzard global untouched while still providing a verified
-- fallback for servers that omit QUEST_FINISHED after scripted turn-ins.
function Legacy.MarkQuestRewardRequested()
    Interaction.rewardRequested = true
    Interaction.rewardQuestID = ResolveCurrentQuest()
    Interaction.rewardQuestTitle = Interaction.currentQuestTitle
    Interaction.rewardToken = Interaction.rewardToken + 1
    local rewardToken = Interaction.rewardToken
    local questID = Interaction.rewardQuestID
    local questTitle = Interaction.rewardQuestTitle

    C_Timer.After(0.75, function()
        if Interaction.rewardRequested and Interaction.rewardToken == rewardToken then
            if not DispatchLegacyQuestTurnedIn(questID, questTitle, false) then
                Interaction.rewardRequested = false
            end
        end
    end)
end

if not GetNumQuestCurrencies then
    function GetNumQuestCurrencies() return 0 end
end
if not GetNumRewardCurrencies then
    function GetNumRewardCurrencies() return 0 end
end
if not GetQuestCurrencyInfo then
    function GetQuestCurrencyInfo() end
end
if not GetQuestCurrencyID then
    function GetQuestCurrencyID() end
end
if not IsQuestItemHidden then
    -- Retail returns the numeric flag consumed by DialogueUI (0 = visible).
    function IsQuestItemHidden() return 0 end
end
if not GetQuestPortraitGiver then
    function GetQuestPortraitGiver() end
end
if not IsSpellKnownOrOverridesKnown then
    function IsSpellKnownOrOverridesKnown(spellID)
        return IsSpellKnown and IsSpellKnown(spellID) or false
    end
end
if not IsCharacterNewlyBoosted then
    function IsCharacterNewlyBoosted() return false end
end

C_QuestInfoSystem = C_QuestInfoSystem or {}
local RewardSpellCache = {}

local function GetRewardSpellData()
    if not GetRewardSpell then
        return
    end

    local texture, name, isTradeskillSpell, isSpellLearned = GetRewardSpell()
    if not texture and not name then
        return
    end

    local link = GetQuestSpellLink and GetQuestSpellLink()
    local spellID = link and tonumber(string.match(link, "spell:(%d+)")) or HashText(name or tostring(texture))
    local data = {
        texture = texture,
        name = name,
        isTradeskillSpell = isTradeskillSpell,
        isSpellLearned = isSpellLearned,
        type = Enum.QuestCompleteSpellType.LegacyBehavior,
    }
    RewardSpellCache[spellID] = data
    return spellID, data
end

C_QuestInfoSystem.GetQuestRewardSpells = C_QuestInfoSystem.GetQuestRewardSpells or function()
    local spellID = GetRewardSpellData()
    if spellID then
        return {spellID}
    end
    return {}
end
C_QuestInfoSystem.GetQuestRewardSpellInfo = C_QuestInfoSystem.GetQuestRewardSpellInfo or function(questID, spellID)
    return RewardSpellCache[spellID] or select(2, GetRewardSpellData())
end

C_PlayerInteractionManager = C_PlayerInteractionManager or {}
C_PlayerInteractionManager.IsInteractingWithNpcOfType = C_PlayerInteractionManager.IsInteractingWithNpcOfType or function(interactionType)
    if interactionType == Enum.PlayerInteractionType.Gossip then
        return Interaction.gossip
    elseif interactionType == Enum.PlayerInteractionType.QuestGiver then
        return Interaction.quest
    end
    return false
end


-- --------------------------------------------------------------------------
-- Optional namespaces which are referenced directly by loaded files
-- --------------------------------------------------------------------------

C_EventUtils = C_EventUtils or {}
C_EventUtils.IsEventValid = C_EventUtils.IsEventValid or function() return false end

C_PlayerInfo = C_PlayerInfo or {}
C_PlayerInfo.GetAlternateFormInfo = C_PlayerInfo.GetAlternateFormInfo or function() return false, false end
C_PlayerInfo.GetGlidingInfo = C_PlayerInfo.GetGlidingInfo or function() return false, false end

C_UnitAuras = C_UnitAuras or {}
C_UnitAuras.WantsAlteredForm = C_UnitAuras.WantsAlteredForm or function() return false end
C_UnitAuras.GetAuraDataByIndex = C_UnitAuras.GetAuraDataByIndex or function(unit, index, filter)
    if not UnitAura then
        return
    end
    local name, icon, count, debuffType, duration, expirationTime, source, isStealable, shouldConsolidate, spellID = UnitAura(unit, index, filter)
    if not name then
        return
    end
    return {
        name = name,
        icon = icon,
        applications = count or 0,
        dispelName = debuffType,
        duration = duration or 0,
        expirationTime = expirationTime,
        sourceUnit = source,
        isStealable = isStealable,
        shouldConsolidate = shouldConsolidate,
        spellId = spellID,
    }
end

C_MountJournal = C_MountJournal or {}
C_MountJournal.GetMountFromSpell = C_MountJournal.GetMountFromSpell or function() end
C_MountJournal.GetMountFromItem = C_MountJournal.GetMountFromItem or function() end
C_MountJournal.GetMountInfoByID = C_MountJournal.GetMountInfoByID or function() end
C_MountJournal.GetMountInfoExtraByID = C_MountJournal.GetMountInfoExtraByID or function() end

C_TaskQuest = C_TaskQuest or {}
C_TaskQuest.GetQuestInfoByQuestID = C_TaskQuest.GetQuestInfoByQuestID or function(questID)
    return C_QuestLog.GetTitleForQuestID(questID)
end
C_TaskQuest.GetQuestTimeLeftSeconds = C_TaskQuest.GetQuestTimeLeftSeconds or function() end

C_Reputation = C_Reputation or {}
C_Reputation.GetFactionDataByID = C_Reputation.GetFactionDataByID or function() end
C_Reputation.IsAccountWideReputation = C_Reputation.IsAccountWideReputation or function() return false end
C_Reputation.IsFactionParagon = C_Reputation.IsFactionParagon or function() return false end
C_Reputation.IsFactionParagonForCurrentPlayer = C_Reputation.IsFactionParagonForCurrentPlayer or function() return false end
C_Reputation.IsMajorFaction = C_Reputation.IsMajorFaction or function() return false end
C_Reputation.GetFactionParagonInfo = C_Reputation.GetFactionParagonInfo or function() end

C_MajorFactions = C_MajorFactions or {}
C_MajorFactions.GetMajorFactionData = C_MajorFactions.GetMajorFactionData or function() end
C_MajorFactions.HasMaximumRenown = C_MajorFactions.HasMaximumRenown or function() return false end


-- Preserve the custom Ascension TTS namespaces when present, but make file
-- loading safe on installations where the extension is disabled.
-- Do not manufacture C_VoiceChat/C_TTSSettings on clients that lack them.
-- DialogueUI's TTS module capability-checks the native Ascension extension;
-- fake namespace tables make unrelated addons incorrectly enable TTS paths.


-- --------------------------------------------------------------------------
-- Ascension interaction exclusions and lifecycle tracking
-- --------------------------------------------------------------------------

-- These helpers are supplied by Ascension's Extensions.dll and are not part
-- of the stock 3.3.5 API.  Use them as a positive client capability check so
-- Ascension-only NPC exceptions never suppress legitimate dialog on another
-- Wrath server merely because it uses Interface 30300.
local HasAscensionGossipExtensions = type(_G.GetActiveGossipQuestIds) == "function"
    and type(_G.GetAvailableGossipQuestIds) == "function"
Legacy.HasAscensionGossipExtensions = HasAscensionGossipExtensions

local ExcludedNPCs = {
    ["Hero's Call Board"] = true,
    ["Warchief's Command Board"] = true,
    ["Outlaw's Contract Board"] = true,
    ["Silas Darkmoon"] = true,
    ["Burth"] = true,
    ["Professor Thaddeus Paleo"] = true,
    ["Chromie"] = true,
    ["Stony Tark"] = true,
    ["Battlemaster Tressa"] = true,
    ["Blood Keeper Rozok"] = true,
    ["Theresa"] = true,
    ["Marazz"] = true,
    ["Ameer Greatluck"] = true,
}

local function NormalizeLabel(text)
    if type(text) ~= "string" then
        return ""
    end
    return string.gsub(string.gsub(string.lower(text), "[%s%p]+", " "), "^%s*(.-)%s*$", "%1")
end

local function IsExcludedLabel(text)
    if ExcludedNPCs[text] then
        return true
    end
    local normalized = NormalizeLabel(text)
    return normalized == "hero s call board"
        or normalized == "warchief s command board"
        or normalized == "outlaw s contract board"
end

local function FrameContainsExcludedLabel(frame)
    if not frame then
        return false
    end

    if frame.IsVisible then
        if not frame:IsVisible() then
            return false
        end
    elseif not frame.IsShown or not frame:IsShown() then
        return false
    end

    if frame.GetEffectiveAlpha and frame:GetEffectiveAlpha() <= 0.01 then
        return false
    end

    if frame.GetName then
        local name = frame:GetName()
        if type(name) == "string" then
            local lowered = string.lower(name)
            if string.find(lowered, "callboard", 1, true) or string.find(lowered, "commandboard", 1, true) then
                return true
            end
        end
    end

    if frame.GetRegions then
        local regions = {frame:GetRegions()}
        for _, region in ipairs(regions) do
            if region and region.GetText and IsExcludedLabel(region:GetText()) then
                return true
            end
        end
    end
    return false
end

function Legacy.IsExcludedInteraction()
    if not HasAscensionGossipExtensions then
        return false
    end

    local npcName = UnitName and UnitName("npc")
    if IsExcludedLabel(npcName) then
        return true
    end

    local likelyFrames = {
        _G.CallBoardUI,
        _G.HerosCallBoardFrame,
        _G.HeroCallBoardFrame,
        _G.HerosCallBoard,
        _G.HeroCallBoard,
        _G.CallBoardFrame,
        _G.CallboardFrame,
    }
    for _, frame in ipairs(likelyFrames) do
        if FrameContainsExcludedLabel(frame) then
            return true
        end
    end

    -- Ascension's board can be created late and its global name has changed
    -- between launcher revisions. Scan only visible frames and stop at a hard
    -- ceiling so quest events from that custom UI can never be mistaken for a
    -- normal NPC conversation.
    if EnumerateFrames then
        local frame = EnumerateFrames()
        local scanned = 0
        while frame and scanned < 10000 do
            if FrameContainsExcludedLabel(frame) then
                return true
            end
            frame = EnumerateFrames(frame)
            scanned = scanned + 1
        end
    end

    return false
end

local LifecycleFrame = AttachFrameCompatibility(NativeCreateFrame("Frame"), "Frame")
local LifecycleEvents = {
    "GOSSIP_SHOW",
    "GOSSIP_CLOSED",
    "QUEST_GREETING",
    "QUEST_DETAIL",
    "QUEST_PROGRESS",
    "QUEST_COMPLETE",
    "QUEST_FINISHED",
    "QUEST_ACCEPTED",
    "QUEST_ITEM_UPDATE",
    "QUEST_LOG_UPDATE",
    "QUEST_QUERY_COMPLETE",
    "PLAYER_ENTERING_WORLD",
}

for _, event in ipairs(LifecycleEvents) do
    LifecycleFrame:RegisterEvent(event)
end

LifecycleFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "GOSSIP_SHOW" then
        local preserveRewardCheck = Interaction.questPhase == "complete" and Interaction.rewardRequested
        Interaction.gossip = true
        Interaction.quest = false
        Interaction.questPhase = "gossip"
        Interaction.currentQuestID = nil
        Interaction.currentQuestTitle = nil
        Interaction.pendingQuestID = nil
        Interaction.pendingQuestTitle = nil
        if not preserveRewardCheck then
            Interaction.rewardRequested = false
            Interaction.rewardToken = Interaction.rewardToken + 1
        end
        BuildGossipOptions()
        BuildGossipQuestList(true)
        BuildGossipQuestList(false)
    elseif event == "GOSSIP_CLOSED" then
        Interaction.gossip = false
    elseif event == "QUEST_GREETING" then
        local preserveRewardCheck = Interaction.questPhase == "complete" and Interaction.rewardRequested
        Interaction.gossip = false
        Interaction.quest = true
        Interaction.questPhase = "greeting"
        Interaction.currentQuestID = nil
        Interaction.currentQuestTitle = nil
        if not preserveRewardCheck then
            Interaction.rewardRequested = false
            Interaction.rewardToken = Interaction.rewardToken + 1
        end
        BuildGreetingQuestList(true)
        BuildGreetingQuestList(false)
    elseif event == "QUEST_DETAIL" then
        Interaction.gossip = false
        Interaction.quest = true
        Interaction.questPhase = "detail"
        Interaction.rewardRequested = false
        Interaction.rewardToken = Interaction.rewardToken + 1
        ResolveCurrentQuest()
    elseif event == "QUEST_PROGRESS" then
        Interaction.gossip = false
        Interaction.quest = true
        Interaction.questPhase = "progress"
        Interaction.rewardRequested = false
        Interaction.rewardToken = Interaction.rewardToken + 1
        ResolveCurrentQuest()
    elseif event == "QUEST_COMPLETE" then
        Interaction.gossip = false
        Interaction.quest = true
        Interaction.questPhase = "complete"
        Interaction.rewardRequested = false
        Interaction.rewardQuestID = nil
        Interaction.rewardQuestTitle = nil
        Interaction.rewardToken = Interaction.rewardToken + 1
        ResolveCurrentQuest()
    elseif event == "QUEST_ACCEPTED" then
        local questLogIndex, questID = ...
        local info
        if questID and tonumber(questID) and tonumber(questID) > 0 then
            info = GetQuestLogEntry(FindQuestLogIndexByID(questID))
        elseif questLogIndex and tonumber(questLogIndex) then
            info = GetQuestLogEntry(tonumber(questLogIndex))
        end
        if info and info.questID > 0 then
            Interaction.currentQuestID = info.questID
            Interaction.currentQuestTitle = info.title
            Interaction.pendingQuestID = info.questID
            Interaction.pendingQuestTitle = info.title
        end
        Interaction.questPhase = "accepted"
        Interaction.rewardRequested = false
        Interaction.rewardToken = Interaction.rewardToken + 1
    elseif event == "QUEST_FINISHED" then
        local finishedPhase = Interaction.questPhase
        local questID = Interaction.rewardQuestID or Interaction.currentQuestID
        local questTitle = Interaction.rewardQuestTitle or Interaction.currentQuestTitle
        local rewardRequested = Interaction.rewardRequested

        Interaction.quest = false
        Interaction.questPhase = nil
        Interaction.currentQuestID = nil
        Interaction.currentQuestTitle = nil
        Interaction.pendingQuestID = nil
        Interaction.pendingQuestTitle = nil
        Interaction.rewardRequested = false
        Interaction.rewardQuestID = nil
        Interaction.rewardQuestTitle = nil
        Interaction.rewardToken = Interaction.rewardToken + 1

        if finishedPhase == "complete" and questID then
            if not DispatchLegacyQuestTurnedIn(questID, questTitle, rewardRequested) then
                C_Timer.After(0.25, function()
                    DispatchLegacyQuestTurnedIn(questID, questTitle, rewardRequested)
                end)
            end
        end
    elseif event == "QUEST_QUERY_COMPLETE" or event == "PLAYER_ENTERING_WORLD" then
        RefreshCompletedQuests()
        if event == "PLAYER_ENTERING_WORLD" and QueryQuestsCompleted then
            QueryQuestsCompleted()
        end
    end
end)
