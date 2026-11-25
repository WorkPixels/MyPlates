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

local function OpenColorPickerForSetting(settingKey, defaultColor, updateFn)
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
                updateFn(r, g, b)
            end,
            cancelFunc = function(prev)
                local r = (prev and prev.r) or prevR
                local g = (prev and prev.g) or prevG
                local b = (prev and prev.b) or prevB
                updateFn(r, g, b)
            end,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        ColorPickerFrame.func = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            updateFn(r, g, b)
        end
        ColorPickerFrame.cancelFunc = function()
            updateFn(prevR, prevG, prevB)
        end
        ColorPickerFrame.hasOpacity = false
        if ColorPickerFrame.SetColorRGB then
            ColorPickerFrame:SetColorRGB(prevR, prevG, prevB)
        end
        ColorPickerFrame:Show()
    end
end

local function CreateColorSwatch(parent, label, settingKey, defaultColor, x, y, boxSize, fontTemplate)
    local size = boxSize or 22
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    
    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetSize(size + 2, size + 2)
    border:SetPoint("CENTER")
    border:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    border:SetVertexColor(0.2, 0.2, 0.2, 1)
    
    local swatch = btn:CreateTexture(nil, "OVERLAY")
    swatch:SetSize(size - 2, size - 2)
    swatch:SetPoint("CENTER")
    swatch:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    btn.swatch = swatch
    
    local text = btn:CreateFontString(nil, "OVERLAY", fontTemplate or "GameFontNormal")
    text:SetPoint("LEFT", btn, "RIGHT", boxSize and 5 or 8, 0)
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
        OpenColorPickerForSetting(settingKey, defaultColor, UpdateColor)
    end)
    
    return btn, UpdateColor
end

local function CreateMiniColorSwatch(parent, label, settingKey, defaultColor, x, y)
    return CreateColorSwatch(parent, label, settingKey, defaultColor, x, y, 16, "GameFontNormalSmall")
end

-- Scrollable container for options columns
local okScroll, scroll = pcall(CreateFrame, "ScrollFrame", "MyPlatesOptionsScrollFrame", panel, "UIPanelScrollFrameTemplate")
if not okScroll or not scroll then
    scroll = CreateFrame("ScrollFrame", "MyPlatesOptionsScrollFrame", panel)
end
scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -56)
scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 12)
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll() or 0
    local maxScroll = self:GetVerticalScrollRange() or 0
    local nextScroll = math.max(0, math.min(maxScroll, cur - (delta * 28)))
    self:SetVerticalScroll(nextScroll)
end)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(630, 580)
scroll:SetScrollChild(content)

-- =========================================================================
-- Column 1: Sizing, Scale & Brightness (X = 20)
-- =========================================================================
local section1 = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
section1:SetPoint("TOPLEFT", content, "TOPLEFT", 20, -8)
section1:SetText("Sizing, Scale & Brightness")

CreateSlider(content, "Health Bar Width", "width", 80, 220, 5, 20, -36)
CreateSlider(content, "Health Bar Height", "height", 6, 32, 1, 20, -74)
CreateSlider(content, "Cast Bar Height", "castHeight", 6, 24, 1, 20, -112)
CreateSlider(content, "Name Font Size", "fontSizeName", 8, 20, 1, 20, -150)
CreateSlider(content, "Health Font Size", "fontSizeHealth", 8, 22, 1, 20, -188)
CreateSlider(content, "Level & Threat Font Size", "fontSizeLevel", 8, 22, 1, 20, -226)
CreateSlider(content, "Debuff Font Size", "fontSizeDebuff", 7, 20, 1, 20, -264)
CreateSlider(content, "Debuff Icon Size", "debuffSize", 14, 48, 1, 20, -302)
CreateSlider(content, "Max Distance (Yards)", "maxDistance", 20, 41, 1, 20, -340)
CreateSlider(content, "Non-Target Brightness (%)", "nonTargetAlpha", 40, 100, 5, 20, -378)
CreateSlider(content, "Target Plate Scale (%)", "targetScale", 100, 135, 5, 20, -416)
CreateSlider(content, "Threat Snapshot Fade (s)", "threatSnapshotDuration", 3, 10, 1, 20, -454)

-- =========================================================================
-- Column 2: Style, Textures & Highlights (X = 230)
-- =========================================================================
local section2 = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
section2:SetPoint("TOPLEFT", content, "TOPLEFT", 230, -8)
section2:SetText("Style & Textures")

CreateCheckbox(content, "Show Cast Bars", "showCastBar", nil, 230, -32)
CreateCheckbox(content, "Show Level & Classification", "showLevel", nil, 230, -56)
CreateCheckbox(content, "Show Elite / Rare Dragon", "showEliteDragon", nil, 230, -80)
CreateCheckbox(content, "Blizzard Default Style", "blizzStyle", nil, 230, -104)

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

local texLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
texLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 230, -134)
texLabel:SetText("Bar Texture:")

local texValue = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
texValue:SetPoint("LEFT", texLabel, "RIGHT", 6, 0)

local cycleTexBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
cycleTexBtn:SetSize(110, 22)
cycleTexBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 230, -156)
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

local fontLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
fontLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 230, -188)
fontLabel:SetText("Active Font:")

local fontValue = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
fontValue:SetPoint("LEFT", fontLabel, "RIGHT", 6, 0)

local cycleBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
cycleBtn:SetSize(110, 22)
cycleBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 230, -210)
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
local sectionTarget = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sectionTarget:SetPoint("TOPLEFT", content, "TOPLEFT", 230, -244)
sectionTarget:SetText("Target Highlights")

CreateCheckbox(content, "Target Glow Border", "targetGlow", nil, 230, -266)
CreateSlider(content, "Glow Thickness", "glowThickness", 1, 8, 1, 230, -308)
CreateCheckbox(content, "Target Brackets (» «)", "targetBrackets", nil, 230, -338)

-- Target Glow Color Swatch & Presets
local swatchBtn, updateGlowColor = CreateColorSwatch(content, "Custom Glow Color", "targetGlowColor", { r = 1, g = 1, b = 0 }, 230, -368)

local presetColors = {
    { r = 1, g = 1, b = 0 },         -- Yellow
    { r = 1, g = 0.2, b = 0.2 },     -- Red
    { r = 0, g = 0.8, b = 1 },       -- Cyan
    { r = 0.2, g = 1, b = 0.2 },     -- Green
    { r = 0.8, g = 0.3, b = 1 },     -- Purple
    { r = 1, g = 1, b = 1 },         -- White
    { r = 1, g = 0.5, b = 0 },       -- Orange
}

local presetLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
presetLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 230, -398)
presetLabel:SetText("Presets:")

for i, col in ipairs(presetColors) do
    local pb = CreateFrame("Button", nil, content)
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

-- Target-of-Target & Alerts Section
local sectionAlerts = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sectionAlerts:SetPoint("TOPLEFT", content, "TOPLEFT", 230, -430)
sectionAlerts:SetText("Target-of-Target & Alerts")

CreateCheckbox(content, "Show Target of Target", "showTargetOfTarget", nil, 230, -452)
CreateCheckbox(content, "Hide ToT When Targeting You", "totHideSelf", nil, 230, -476)
CreateCheckbox(content, "Flash Border on Aggro Alert", "aggroLossFlash", nil, 230, -500)
CreateCheckbox(content, "Show Combo Points", "showComboPoints", nil, 230, -524)

-- =========================================================================
-- Column 3: Colors & Threat (X = 450)
-- =========================================================================
local section3 = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
section3:SetPoint("TOPLEFT", content, "TOPLEFT", 450, -8)
section3:SetText("Colors & Threat")

CreateCheckbox(content, "Class Colors (Enemy)", "useClassColorsEnemy", nil, 450, -32)
CreateCheckbox(content, "Class Colors (Friendly)", "useClassColorsFriendly", nil, 450, -56)
CreateCheckbox(content, "Reaction Colors (NPCs)", "useReactionColors", nil, 450, -80)

local sectionThreat = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sectionThreat:SetPoint("TOPLEFT", content, "TOPLEFT", 450, -114)
sectionThreat:SetText("Threat & Debuffs")

CreateCheckbox(content, "Enable Threat Coloring", "enableThreat", nil, 450, -138)
CreateCheckbox(content, "Tank Mode (Threat Lead)", "tankMode", nil, 450, -162)
CreateCheckbox(content, "Threat Snapshots (*)", "threatSnapshots", nil, 450, -186)

local threatColLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
threatColLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 450, -212)
threatColLabel:SetText("Threat Colors:")

CreateMiniColorSwatch(content, "Safe", "threatColorSecure", { r = 0.2, g = 0.8, b = 0.2 }, 450, -230)
CreateMiniColorSwatch(content, "Warn", "threatColorWarning", { r = 0.9, g = 0.6, b = 0.0 }, 508, -230)
CreateMiniColorSwatch(content, "Danger", "threatColorDanger", { r = 0.9, g = 0.2, b = 0.2 }, 568, -230)

CreateCheckbox(content, "Show Target Debuffs", "showDebuffs", nil, 450, -258)
CreateCheckbox(content, "Show Only My Debuffs", "onlyPlayerDebuffs", nil, 450, -282)
CreateCheckbox(content, "Stacking Nameplates", "stackingPlates", nil, 450, -306)

local sectionDot = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sectionDot:SetPoint("TOPLEFT", content, "TOPLEFT", 450, -338)
sectionDot:SetText("DoT Death Prediction")

CreateCheckbox(content, "Enable DoT Kill Prediction", "enableDotKill", nil, 450, -360)
CreateCheckbox(content, "Include Group Member DoTs", "includeGroupDots", nil, 450, -382)
CreateCheckbox(content, "Show Skull Marker", "dotLethalSkull", nil, 450, -404)
CreateCheckbox(content, "Change Health Bar Color", "dotLethalBar", nil, 450, -426)
CreateCheckbox(content, "DoT Prediction Overlay Bar", "dotLethalPrediction", nil, 450, -448)
CreateCheckbox(content, "Color Health Text", "dotLethalHpText", nil, 450, -470)

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
btn:SetSize(130, 24)
btn:SetText("Reset Defaults")
btn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -20, -18)
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
