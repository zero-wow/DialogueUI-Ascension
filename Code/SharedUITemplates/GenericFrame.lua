local _, addon = ...
local API = addon.API;
local TemplateAPI = addon.TemplateAPI;


do  --DUIGenericTitledFrameMixin
    DUIGenericTitledFrameMixin = {};

    -- Retail renders this frame through TextureSlice.  Stock 3.3.5 does not
    -- have that renderer, so split the original 512x512 frame texture into
    -- nine ordinary textures.  This preserves the 80px parchment border
    -- instead of stretching one square over the whole settings window.
    local function CreateLegacyNineSlice(parent)
        local edgeSize = 80;
        local innerStart = 80/512;
        local innerEnd = 432/512;
        local pieces = {};
        local controller = {pieces = pieces, parent = parent};

        local function CreatePiece(left, right, top, bottom)
            local texture = parent:CreateTexture(nil, "BACKGROUND");
            texture:SetTexCoord(left, right, top, bottom);
            tinsert(pieces, texture);
            return texture
        end

        local topLeft = CreatePiece(0, innerStart, 0, innerStart);
        local top = CreatePiece(innerStart, innerEnd, 0, innerStart);
        local topRight = CreatePiece(innerEnd, 1, 0, innerStart);
        local left = CreatePiece(0, innerStart, innerStart, innerEnd);
        local center = CreatePiece(innerStart, innerEnd, innerStart, innerEnd);
        local right = CreatePiece(innerEnd, 1, innerStart, innerEnd);
        local bottomLeft = CreatePiece(0, innerStart, innerEnd, 1);
        local bottom = CreatePiece(innerStart, innerEnd, innerEnd, 1);
        local bottomRight = CreatePiece(innerEnd, 1, innerEnd, 1);

        topLeft:SetSize(edgeSize, edgeSize);
        topRight:SetSize(edgeSize, edgeSize);
        bottomLeft:SetSize(edgeSize, edgeSize);
        bottomRight:SetSize(edgeSize, edgeSize);

        top:SetPoint("TOPLEFT", topLeft, "TOPRIGHT");
        top:SetPoint("BOTTOMRIGHT", topRight, "BOTTOMLEFT");
        bottom:SetPoint("TOPLEFT", bottomLeft, "TOPRIGHT");
        bottom:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMLEFT");
        left:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT");
        left:SetPoint("BOTTOMRIGHT", bottomLeft, "TOPRIGHT");
        right:SetPoint("TOPLEFT", topRight, "BOTTOMLEFT");
        right:SetPoint("BOTTOMRIGHT", bottomRight, "TOPRIGHT");
        center:SetPoint("TOPLEFT", top, "BOTTOMLEFT");
        center:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT");

        function controller:SetTexture(file)
            self.textureFile = file;
            for _, texture in ipairs(pieces) do
                texture:SetTexture(file);
            end
        end

        function controller:SetOffset(offset)
            topLeft:ClearAllPoints();
            topLeft:SetPoint("TOPLEFT", parent, "TOPLEFT", -offset, offset);
            topRight:ClearAllPoints();
            topRight:SetPoint("TOPRIGHT", parent, "TOPRIGHT", offset, offset);
            bottomLeft:ClearAllPoints();
            bottomLeft:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -offset, -offset);
            bottomRight:ClearAllPoints();
            bottomRight:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", offset, -offset);
        end

        function controller:Show()
            self.shown = true;
            for _, texture in ipairs(pieces) do
                texture:Show();
            end
        end

        function controller:Hide()
            self.shown = false;
            for _, texture in ipairs(pieces) do
                texture:Hide();
            end
        end

        function controller:IsShown()
            return self.shown == true
        end

        controller:SetOffset(16);
        return controller
    end
    addon.CreateLegacyNineSlice = CreateLegacyNineSlice;

    function DUIGenericTitledFrameMixin:UpdatePixel()
        if API.UpdateTextureSliceScale then
            API.UpdateTextureSliceScale(self.Background);
        end

        local pixelOffset = self.pixelOffset;   --Drop Shadow
        -- Texture regions do not expose GetEffectiveScale on 3.3.5.  They
        -- inherit the owning frame's effective scale, so query the frame.
        local scale = self:GetEffectiveScale()
        local offset = API.GetPixelForScale(scale, pixelOffset);
        self.Background:ClearAllPoints();
        self.Background:SetPoint("TOPLEFT", self, "TOPLEFT", -offset, offset);
        self.Background:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", offset, -offset);
        if self.LegacyNineSlice and self.LegacyNineSlice:IsShown() then
            self.LegacyNineSlice:SetOffset(offset);
        end
    end

    local TEXTURE_LOOKUP = {
        [1] = { --Settings Background: Brown    (Minimal Size: 480*480 px)
            file = "Interface/AddOns/DialogueUI-Ascension/Art/Theme_Brown/GenericFrame-Tiled-Large.tga",
            legacyFile = "Interface\\AddOns\\DialogueUI-Ascension\\Art\\Theme_Brown\\GenericFrame-Tiled-Large.tga",
            offset = 16,
            margins = {80, 80, 80, 80},
        },

        [2] = { --Settings Background: Dark     (Minimal Size: 480*480 px)
            file = "Interface/AddOns/DialogueUI-Ascension/Art/Theme_Dark/GenericFrame-Tiled-Large.tga",
            legacyFile = "Interface\\AddOns\\DialogueUI-Ascension\\Art\\Theme_Dark\\GenericFrame-Tiled-Large.tga",
            offset = 16,
            margins = {80, 80, 80, 80},
        },

        HelpTip1 = { --Help Tip
            file = "Interface/AddOns/DialogueUI-Ascension/Art/Theme_Shared/HelpTip.tga",
            legacyFile = "Interface\\AddOns\\DialogueUI-Ascension\\Art\\Theme_Shared\\HelpTip.tga",
            offset = 8,
            margins = {40, 24, 40, 24},
            texCoords = {0, 256/512, 0, 104/512},
        },

        HelpTip2 = { --Help Tip
            file = "Interface/AddOns/DialogueUI-Ascension/Art/Theme_Shared/HelpTip.tga",
            legacyFile = "Interface\\AddOns\\DialogueUI-Ascension\\Art\\Theme_Shared\\HelpTip.tga",
            offset = 8,
            margins = {40, 24, 40, 24},
            texCoords = {0, 256/512, 104/512, 208/512},
        },
    };

    function DUIGenericTitledFrameMixin:SetTheme(themeID)
        if not (themeID and TEXTURE_LOOKUP[themeID]) then
            themeID = 1;
        end
        if themeID ~= self.themeID then
            self.themeID = themeID;
            local info = TEXTURE_LOOKUP[themeID];

            if addon.IS_LEGACY_ASCENSION and type(themeID) == "number" then
                if not self.LegacyNineSlice then
                    self.LegacyNineSlice = CreateLegacyNineSlice(self);
                end
                self.Background:Hide();
                self.LegacyNineSlice:SetTexture(info.legacyFile);
                self.LegacyNineSlice:Show();
            else
                if self.LegacyNineSlice then
                    self.LegacyNineSlice:Hide();
                end
                self.Background:Show();
                self.Background:SetTexture(addon.IS_LEGACY_ASCENSION and info.legacyFile or info.file);
                if info.texCoords then
                    self.Background:SetTexCoord(info.texCoords[1], info.texCoords[2], info.texCoords[3], info.texCoords[4]);
                else
                    self.Background:SetTexCoord(0, 1, 0, 1);
                end
                if self.Background.SetTextureSliceMargins then
                    self.Background:SetTextureSliceMargins(info.margins[1], info.margins[2], info.margins[3], info.margins[4]);
                end
            end
            self.pixelOffset = info.offset;
            self:UpdatePixel();
        end
    end

    function DUIGenericTitledFrameMixin:OnLoad()
        --For frame anchor
        self.RealArea = self.Background;
        self.EffectiveArea = self;

        self:SetTheme(1);
    end
end
