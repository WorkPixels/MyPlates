-- Config.lua
-- Options panel for MyPlates configuration

local addonName, MP = ...

-- Create configuration panel frame
local panel = CreateFrame("Frame", "MyPlatesOptionsFrame", UIParent)
panel.name = "MyPlates"

-- Register with Settings API (Dragonflight/TWW/Classic 1.15+ modern system)
local category
if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
else
    -- Fallback for older legacy client API if ever needed
    InterfaceOptions_AddCategory(panel)
end

-- Centralized registry to refresh every control when the panel is shown or reset
local refreshFuncs = {}
local function RegisterRefresh(fn)
    table.insert(refreshFuncs, fn)
end

local function RefreshAllControls()
    if not MP.db then
        if MP.InitDB then MP:InitDB() end
    end
    for _, fn in ipairs(refreshFuncs) do
        pcall(fn)
    end
end
MP.RefreshConfigControls = RefreshAllControls

panel:SetScript("OnShow", RefreshAllControls)
panel.refresh = RefreshAllControls

-- Header Titles
local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -18)
title:SetText("MyPlates Configuration")

local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
desc:SetText("Fully customizable nameplates. Adjust font sizes, bar textures, class colors, and target highlights in real time.")

-- Helpers to create widgets programmatically without relying on deprecated XML templates

local function CreateCheckbox(parent, label, settingKey, tooltipText, x, y)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    
    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    text:SetText(label)
    cb.text = text
    
    cb:SetScript("OnClick", function(self)
        MP.db[settingKey] = self:GetChecked()
        MP:ApplyAllSettings()
    end)
    
    RegisterRefresh(function()
        local val = MP.db and MP.db[settingKey]
        if val == nil and MP.defaults then val = MP.defaults[settingKey] end
        cb:SetChecked(val and true or false)
    end)
    
    return cb
end

local function CreateSlider(parent, label, settingKey, minVal, maxVal, step, x, y)
    local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(180, 16)
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    
    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 }
    })
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    
    -- Labels
    local titleText = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 3)
    titleText:SetText(label)
    
    local valueText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("BOTTOMRIGHT", slider, "TOPLEFT", 180, 3)
    
    slider:SetScript("OnValueChanged", function(self, value)
        if self.isSettingValue then return end
        value = math.floor(value / step + 0.5) * step
        valueText:SetText(tostring(value))
        MP.db[settingKey] = value
        MP:ApplyAllSettings()
    end)
    
    RegisterRefresh(function()
        slider.isSettingValue = true
        local currentVal = (MP.db and MP.db[settingKey])
        if currentVal == nil and MP.defaults then currentVal = MP.defaults[settingKey] end
        if currentVal == nil then currentVal = minVal end
        slider:SetValue(currentVal)
        slider.isSettingValue = false
        valueText:SetText(tostring(currentVal))
    end)
    
    return slider
end

local function CreateColorSwatch(parent, label, settingKey, defaultColor, x, y)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(22, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    
    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetSize(24, 24)
    border:SetPoint("CENTER")
    border:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    border:SetVertexColor(0.2, 0.2, 0.2, 1)
    
    local swatch = btn:CreateTexture(nil, "OVERLAY")
    swatch:SetSize(20, 20)
    swatch:SetPoint("CENTER")
    swatch:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    btn.swatch = swatch
    
    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    text:SetText(label)
    
    local function UpdateColor(r, g, b)
        swatch:SetVertexColor(r, g, b, 1)
        MP.db[settingKey] = { r = r, g = g, b = b, a = 1 }
        MP:ApplyAllSettings()
    end
    
    RegisterRefresh(function()
        local c = (MP.db and MP.db[settingKey]) or (MP.defaults and MP.defaults[settingKey]) or defaultColor
        swatch:SetVertexColor(c.r, c.g, c.b, 1)
    end)
    
    btn:SetScript("OnClick", function()
        local c = (MP.db and MP.db[settingKey]) or (MP.defaults and MP.defaults[settingKey]) or defaultColor
        local prevR, prevG, prevB = c.r, c.g, c.b
        
        if ColorPickerFrame.SetupColorPickerAndShow then
            local info = {
                r = prevR,
                g = prevG,
                b = prevB,
                hasOpacity = false,
                swatchFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    UpdateColor(r, g, b)
                end,
                cancelFunc = function(prev)
                    local r = (prev and prev.r) or prevR
                    local g = (prev and prev.g) or prevG
                    local b = (prev and prev.b) or prevB
                    UpdateColor(r, g, b)
                end,
            }
            ColorPickerFrame:SetupColorPickerAndShow(info)
        else
            ColorPickerFrame.func = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                UpdateColor(r, g, b)
            end
            ColorPickerFrame.cancelFunc = function()
                UpdateColor(prevR, prevG, prevB)
            end
            ColorPickerFrame.hasOpacity = false
            if ColorPickerFrame.SetColorRGB then
                ColorPickerFrame:SetColorRGB(prevR, prevG, prevB)
            end
            ColorPickerFrame:Show()
        end
    end)
    
    return btn, UpdateColor
end

-- =========================================================================
-- Column 1: Sizing & Dimensions (X = 20)
-- =========================================================================
local section1 = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
section1:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -58)
section1:SetText("Sizing & Font Sizes")

CreateSlider(panel, "Health Bar Width", "width", 80, 220, 5, 20, -88)
CreateSlider(panel, "Health Bar Height", "height", 6, 32, 1, 20, -132)
CreateSlider(panel, "Cast Bar Height", "castHeight", 6, 24, 1, 20, -176)
CreateSlider(panel, "Name Font Size", "fontSizeName", 8, 20, 1, 20, -220)
CreateSlider(panel, "Health Font Size", "fontSizeHealth", 8, 22, 1, 20, -264)
CreateSlider(panel, "Level & Threat Font Size", "fontSizeLevel", 8, 22, 1, 20, -308)
CreateSlider(panel, "Debuff Font Size", "fontSizeDebuff", 7, 20, 1, 20, -352)
CreateSlider(panel, "Debuff Icon Size", "debuffSize", 14, 48, 1, 20, -396)
CreateSlider(panel, "Max Distance (Yards)", "maxDistance", 20, 41, 1, 20, -440)

-- =========================================================================
-- Column 2: Style, Textures & Highlights (X = 230)
-- =========================================================================
local section2 = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
section2:SetPoint("TOPLEFT", panel, "TOPLEFT", 230, -58)
section2:SetText("Style & Textures")

CreateCheckbox(panel, "Show Cast Bars", "showCastBar", nil, 230, -82)
CreateCheckbox(panel, "Show Level & Classification", "showLevel", nil, 230, -106)
CreateCheckbox(panel, "Show Elite / Rare Dragon", "showEliteDragon", nil, 230, -130)

-- Bar Texture Cycling
local textures = {
    { name = "Flat", path = "Interface\\ChatFrame\\ChatFrameBackground" },
    { name = "Classic", path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { name = "Smooth", path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
    { name = "Raid", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { name = "Minimal", path = "Interface\\Buttons\\WHITE8X8" },
}

local function GetTextureName(path)
    for _, t in ipairs(textures) do
        if t.path == path then
            return t.name
        end
    end
    return "Flat"
end

local texLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
texLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 230, -160)
texLabel:SetText("Bar Texture:")

local texValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
texValue:SetPoint("LEFT", texLabel, "RIGHT", 6, 0)

local cycleTexBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
cycleTexBtn:SetSize(110, 22)
cycleTexBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 230, -182)
cycleTexBtn:SetText("Cycle Texture")

cycleTexBtn:SetScript("OnClick", function()
    local currIndex = 1
    for i, t in ipairs(textures) do
        if t.path == MP.db.barTexture then
            currIndex = i
            break
        end
    end
    local nextIndex = (currIndex % #textures) + 1
    MP.db.barTexture = textures[nextIndex].path
    texValue:SetText(textures[nextIndex].name)
    MP:ApplyAllSettings()
end)

RegisterRefresh(function()
    local curTex = (MP.db and MP.db.barTexture) or (MP.defaults and MP.defaults.barTexture)
    texValue:SetText(GetTextureName(curTex))
end)

-- Font selection controls
local fonts = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.ttf" },
    { name = "Skurri", path = "Fonts\\skurri.ttf" }
}

local function GetFontName(path)
    for _, f in ipairs(fonts) do
        if f.path == path then
            return f.name
        end
    end
    return "Friz Quadrata"
end

local fontLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
fontLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 230, -214)
fontLabel:SetText("Active Font:")

local fontValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
fontValue:SetPoint("LEFT", fontLabel, "RIGHT", 6, 0)

local cycleBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
cycleBtn:SetSize(110, 22)
cycleBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 230, -236)
cycleBtn:SetText("Cycle Font")

cycleBtn:SetScript("OnClick", function()
    local currIndex = 1
    for i, f in ipairs(fonts) do
        if f.path == MP.db.fontPath then
            currIndex = i
            break
        end
    end
    local nextIndex = (currIndex % #fonts) + 1
    MP.db.fontPath = fonts[nextIndex].path
    fontValue:SetText(fonts[nextIndex].name)
    MP:ApplyAllSettings()
end)

RegisterRefresh(function()
    local curFont = (MP.db and MP.db.fontPath) or (MP.defaults and MP.defaults.fontPath)
    fontValue:SetText(GetFontName(curFont))
end)

-- Target Highlight Controls
local sectionTarget = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sectionTarget:SetPoint("TOPLEFT", panel, "TOPLEFT", 230, -270)
sectionTarget:SetText("Target Highlights")

CreateCheckbox(panel, "Target Glow Border", "targetGlow", nil, 230, -292)
CreateSlider(panel, "Glow Thickness", "glowThickness", 1, 8, 1, 230, -336)
CreateCheckbox(panel, "Target Brackets (» «)", "targetBrackets", nil, 230, -366)

-- Target Glow Color Swatch & Presets
local swatchBtn, updateGlowColor = CreateColorSwatch(panel, "Custom Glow Color", "targetGlowColor", { r = 1, g = 1, b = 0 }, 230, -396)

local presetColors = {
    { r = 1, g = 1, b = 0 },         -- Yellow
    { r = 1, g = 0.2, b = 0.2 },     -- Red
    { r = 0, g = 0.8, b = 1 },       -- Cyan
    { r = 0.2, g = 1, b = 0.2 },     -- Green
    { r = 0.8, g = 0.3, b = 1 },     -- Purple
    { r = 1, g = 1, b = 1 },         -- White
    { r = 1, g = 0.5, b = 0 },       -- Orange
}

local presetLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
presetLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 230, -426)
presetLabel:SetText("Presets:")

for i, col in ipairs(presetColors) do
    local pb = CreateFrame("Button", nil, panel)
    pb:SetSize(18, 18)
    pb:SetPoint("LEFT", presetLabel, "RIGHT", 6 + (i - 1) * 22, 0)
    
    local pborder = pb:CreateTexture(nil, "BACKGROUND")
    pborder:SetSize(20, 20)
    pborder:SetPoint("CENTER")
    pborder:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    pborder:SetVertexColor(0.2, 0.2, 0.2, 1)
    
    local pfill = pb:CreateTexture(nil, "OVERLAY")
    pfill:SetSize(16, 16)
    pfill:SetPoint("CENTER")
    pfill:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    pfill:SetVertexColor(col.r, col.g, col.b, 1)
    
    pb:SetScript("OnClick", function()
        updateGlowColor(col.r, col.g, col.b)
    end)
end

-- =========================================================================
-- Column 3: Colors & Threat (X = 450)
-- =========================================================================
local section3 = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
section3:SetPoint("TOPLEFT", panel, "TOPLEFT", 450, -58)
section3:SetText("Colors & Threat")

CreateCheckbox(panel, "Class Colors (Enemy)", "useClassColorsEnemy", nil, 450, -82)
CreateCheckbox(panel, "Class Colors (Friendly)", "useClassColorsFriendly", nil, 450, -106)
CreateCheckbox(panel, "Reaction Colors (NPCs)", "useReactionColors", nil, 450, -130)

local sectionThreat = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sectionThreat:SetPoint("TOPLEFT", panel, "TOPLEFT", 450, -164)
sectionThreat:SetText("Threat & Debuffs")

CreateCheckbox(panel, "Enable Threat Coloring", "enableThreat", nil, 450, -188)
CreateCheckbox(panel, "Tank Mode (Threat Lead)", "tankMode", nil, 450, -212)
CreateCheckbox(panel, "Show Target Debuffs", "showDebuffs", nil, 450, -236)
CreateCheckbox(panel, "Show Only My Debuffs", "onlyPlayerDebuffs", nil, 450, -260)
CreateCheckbox(panel, "Stacking Nameplates", "stackingPlates", nil, 450, -284)

local sectionDot = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sectionDot:SetPoint("TOPLEFT", panel, "TOPLEFT", 450, -316)
sectionDot:SetText("DoT Death Prediction")

CreateCheckbox(panel, "Enable DoT Kill Prediction", "enableDotKill", nil, 450, -338)
CreateCheckbox(panel, "Include Group Member DoTs", "includeGroupDots", nil, 450, -360)
CreateCheckbox(panel, "Show Skull Marker", "dotLethalSkull", nil, 450, -382)
CreateCheckbox(panel, "Change Health Bar Color", "dotLethalBar", nil, 450, -404)
CreateCheckbox(panel, "DoT Prediction Overlay Bar", "dotLethalPrediction", nil, 450, -426)
CreateCheckbox(panel, "Color Health Text", "dotLethalHpText", nil, 450, -448)

-- =========================================================================
-- Reset to Defaults Logic
-- =========================================================================
local function ResetToDefaults()
    if not MP.db then MP.db = {} end
    wipe(MP.db)
    for k, v in pairs(MP.defaults) do
        if type(v) == "table" then
            local copy = {}
            for subK, subV in pairs(v) do copy[subK] = subV end
            MP.db[k] = copy
        else
            MP.db[k] = v
        end
    end
    MP:ApplyAllSettings()
    RefreshAllControls()
    print("|cffffd100MyPlates|r: Settings reset to defaults.")
end

panel.default = ResetToDefaults

local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
btn:SetSize(140, 24)
btn:SetText("Reset Defaults")
btn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 20, 20)
btn:SetScript("OnClick", ResetToDefaults)

-- Slash Commands registration to open the options panel
SLASH_MYPLATES1 = "/mp"
SLASH_MYPLATES2 = "/myplates"
SlashCmdList["MYPLATES"] = function()
    RefreshAllControls()
    if category then
        if Settings and Settings.OpenToCategory then
            local catID = (category.GetID and category:GetID()) or category.ID or category
            Settings.OpenToCategory(catID)
        end
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel.name)
        InterfaceOptionsFrame_OpenToCategory(panel.name)
    end
end

-- Initialize controls immediately so values are ready from the start
RefreshAllControls()
