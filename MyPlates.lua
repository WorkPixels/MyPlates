-- MyPlates.lua
-- Core engine for the custom nameplates (Forever / Classic Beta edition)

local addonName, MP = ...
_G.MyPlates = MP -- Export to global for Config

-- Localize high-frequency WoW API & Lua functions for speed
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitName = UnitName
local UnitLevel = UnitLevel
local UnitClassification = UnitClassification
local UnitIsUnit = UnitIsUnit
local UnitCanAttack = UnitCanAttack
local UnitReaction = UnitReaction
local UnitIsPlayer = UnitIsPlayer
local UnitIsTapDenied = UnitIsTapDenied
local UnitIsPVP = UnitIsPVP
local UnitFactionGroup = UnitFactionGroup
local UnitClass = UnitClass
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local GetRaidTargetIndex = GetRaidTargetIndex
local GetQuestDifficultyColor = GetQuestDifficultyColor
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local GetTime = GetTime
local floor, ceil, max = math.floor, math.ceil, math.max
local format = string.format

-- Pre-cached group unit tokens to avoid garbage collection churn in combat
local raidUnits = {}
for i = 1, 40 do raidUnits[i] = "raid" .. i end

local partyUnits = {}
for i = 1, 4 do partyUnits[i] = "party" .. i end

-- Detect Midnight / Forever engine (Classic Forever 1.60.x runs modern 12.x C-engine build >= 16001)
local versionStr, buildNum, dateStr, tocNum = GetBuildInfo()
local IS_MIDNIGHT_ENGINE = (_G.issecretvalue ~= nil) 
    or (tocNum and (tocNum >= 120000 or (tocNum < 20000 and tocNum >= 16001)))
    or (versionStr and string.find(versionStr, "^1%.60"))
    or (buildNum and tonumber(buildNum) and tonumber(buildNum) >= 70000)
    or false

MP.activePlates = {} -- Store active plates: [unit] = frame

-- Midnight / Forever C-Engine Native Aura Container Support
if C_AddOns and C_AddOns.LoadAddOn then
    pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
end

local HAS_AURA_CONTAINER = (C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate")) and true or false

local function HasAuraContainerSupport()
    if HAS_AURA_CONTAINER then return true end
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") then
        HAS_AURA_CONTAINER = true
        return true
    end
    return false
end

-- Default settings table
MP.defaults = {
    width = 100,
    height = 14,
    castHeight = 10,
    fontSizeName = 10,
    fontSizeHealth = 10,
    fontSizeLevel = 10,
    fontSizeDebuff = 10,
    debuffSize = 20,
    maxDistance = 41,
    
    showCastBar = true,
    showLevel = true,
    showEliteDragon = true,
    barTexture = "Interface\\ChatFrame\\ChatFrameBackground",
    fontPath = "Fonts\\FRIZQT__.TTF",
    
    targetGlow = true,
    glowThickness = 1,
    targetBrackets = true,
    targetGlowColor = { r = 1, g = 1, b = 0, a = 1 },
    
    useClassColors = true,
    useClassColorsEnemy = true,
    useClassColorsFriendly = true,
    useReactionColors = true,
    
    enableThreat = true,
    tankMode = true,
    showDebuffs = true,
    maxDebuffs = 5,
    onlyPlayerDebuffs = true,
    stackingPlates = true,
    
    enableDotKill = true,
    includeGroupDots = true,
    dotLethalSkull = true,
    dotLethalBar = true,
    dotLethalPrediction = true,
    dotLethalHpText = true,
}

-- Baseline assignment so MP.db is never nil
MP.db = MP.defaults

MP.textures = {
    { name = "Flat", path = "Interface\\ChatFrame\\ChatFrameBackground" },
    { name = "Classic", path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { name = "Smooth", path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
    { name = "Raid", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { name = "Minimal", path = "Interface\\Buttons\\WHITE8X8" },
}

function MP:GetBarTexture()
    return (MP.db and MP.db.barTexture) or "Interface\\ChatFrame\\ChatFrameBackground"
end

function MP:GetTargetGlowColor()
    local c = MP.db and MP.db.targetGlowColor
    if c and c.r and c.g and c.b then
        return c.r, c.g, c.b, c.a or 1
    end
    return 1, 1, 0, 1
end

-- DoT Tracking Cache & Tick Rates
MP.dotTickCache = {}
MP.dotTickRates = {
    ["Flame Shock"] = 3.0,
    ["Rend"] = 3.0,
    ["Deep Wounds"] = 3.0,
    ["Corruption"] = 3.0,
    ["Curse of Agony"] = 2.0,
    ["Immolate"] = 3.0,
    ["Siphon Life"] = 3.0,
    ["Unstable Affliction"] = 3.0,
    ["Seed of Corruption"] = 3.0,
    ["Drain Life"] = 1.0,
    ["Drain Soul"] = 3.0,
    ["Shadow Word: Pain"] = 3.0,
    ["Vampiric Touch"] = 3.0,
    ["Devouring Plague"] = 3.0,
    ["Holy Fire"] = 2.0,
    ["Mind Flay"] = 1.0,
    ["Moonfire"] = 3.0,
    ["Insect Swarm"] = 2.0,
    ["Rip"] = 2.0,
    ["Rake"] = 3.0,
    ["Lacerate"] = 3.0,
    ["Serpent Sting"] = 3.0,
    ["Immolation Trap"] = 2.0,
    ["Black Arrow"] = 2.0,
    ["Rupture"] = 2.0,
    ["Garrote"] = 3.0,
    ["Deadly Poison"] = 3.0,
    ["Ignite"] = 2.0,
    ["Pyroblast"] = 3.0,
    ["Fireball"] = 3.0,
    ["Consecration"] = 1.0,
}

-- Baseline tick damage defaults per spell (prevents overestimating before first combat log tick)
MP.defaultDotTicks = {
    -- Warrior
    ["Rend"] = 26,
    ["Deep Wounds"] = 45,
    -- Shaman
    ["Flame Shock"] = 120,
    -- Rogue
    ["Deadly Poison"] = 30,
    ["Garrote"] = 45,
    ["Rupture"] = 55,
    -- Hunter
    ["Serpent Sting"] = 65,
    ["Immolation Trap"] = 50,
    ["Black Arrow"] = 60,
    -- Warlock
    ["Corruption"] = 90,
    ["Curse of Agony"] = 65,
    ["Immolate"] = 80,
    ["Siphon Life"] = 45,
    ["Unstable Affliction"] = 90,
    ["Seed of Corruption"] = 80,
    ["Drain Life"] = 60,
    ["Drain Soul"] = 80,
    -- Priest
    ["Shadow Word: Pain"] = 95,
    ["Vampiric Touch"] = 85,
    ["Devouring Plague"] = 90,
    ["Holy Fire"] = 55,
    ["Mind Flay"] = 70,
    -- Druid
    ["Moonfire"] = 45,
    ["Insect Swarm"] = 40,
    ["Rip"] = 65,
    ["Rake"] = 35,
    ["Lacerate"] = 35,
    -- Mage
    ["Ignite"] = 60,
    ["Pyroblast"] = 50,
    ["Fireball"] = 30,
    -- Paladin
    ["Consecration"] = 40,
}

-- Initialize database helper
function MP:InitDB()
    if not _G.MyPlatesDB then
        _G.MyPlatesDB = {}
    end
    MP.db = _G.MyPlatesDB
    -- Merge defaults for missing values
    for k, v in pairs(MP.defaults) do
        if MP.db[k] == nil then
            if type(v) == "table" then
                local copy = {}
                for subK, subV in pairs(v) do copy[subK] = subV end
                MP.db[k] = copy
            else
                MP.db[k] = v
            end
        end
    end
    
    if not _G.MyPlatesDB.dotTickCache then
        _G.MyPlatesDB.dotTickCache = {}
    end
    MP.dotTickCache = _G.MyPlatesDB.dotTickCache
end
local InitDB = function() MP:InitDB() end
InitDB()

-- Helper: Detect secret / protected values (WoW 12.0+ / Midnight / Forever security system)
local issecretvalue = _G.issecretvalue
local function IsSecret(v)
    if issecretvalue then
        local ok, isSec = pcall(issecretvalue, v)
        if ok and isSec then return true end
    end
    -- Fallback checks in case issecretvalue is absent or incomplete
    local ok1 = pcall(function() if v then end end)
    if not ok1 then return true end
    if v == nil then return false end
    local ok2 = pcall(function() return v == v end)
    if not ok2 then return true end
    return false
end

-- Helper: Call an API safely and return nil if it throws or returns a secret value
local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, res = pcall(fn, ...)
    if ok and not IsSecret(res) then
        return res
    end
    return nil
end

-- Helper: Measure FontString width safely without inspecting text or triggering secret comparisons
local function GetSafeStringWidth(fontString)
    if not fontString then return 0 end
    if fontString.IsShown then
        local okShown, shown = pcall(fontString.IsShown, fontString)
        if okShown and not IsSecret(shown) and shown == false then
            return 0
        end
    end
    local ok, w = pcall(fontString.GetStringWidth, fontString)
    if ok and not IsSecret(w) and type(w) == "number" and w > 0 then
        return w
    end
    return 0
end

-- Dynamic health bar width: automatically lengthens the plate if text is wide so level, threat, and health never overlap
function MP:UpdatePlateWidth(frame)
    if not frame or not frame.unit then return end
    local baseWidth = MP.db.width or 100
    
    local leftWidth = 0
    if MP.db.showLevel then
        leftWidth = GetSafeStringWidth(frame.levelText)
    end
    
    local threatWidth = 0
    if MP.db.enableThreat then
        threatWidth = GetSafeStringWidth(frame.threatText)
    end
    
    local hpWidth = GetSafeStringWidth(frame.hpText)
    
    -- Margins: 3px borders + ~6px gap between each text element (18px with threat, 8px without)
    local gap = (threatWidth > 0) and 18 or 8
    local requiredWidth = math.ceil(leftWidth + threatWidth + hpWidth + gap)
    
    local targetWidth = math.max(baseWidth, requiredWidth)
    if frame:GetWidth() ~= targetWidth then
        frame:SetWidth(targetWidth)
        if frame.aurasFrame then
            frame.aurasFrame:SetWidth(targetWidth)
        end
        if frame.auraContainer then
            frame.auraContainer:SetWidth(targetWidth)
        end
    end
    
    MP:UpdateThreatAnchor(frame)
end

-- Center threat text between level text and health text without dual-anchoring (prevents truncation)
function MP:UpdateThreatAnchor(frame)
    if not frame or not frame.threatText or not frame.healthBar then return end
    
    local leftWidth = 0
    if MP.db.showLevel then
        leftWidth = GetSafeStringWidth(frame.levelText)
    end
    
    local hpWidth = GetSafeStringWidth(frame.hpText)
    
    -- Exact midpoint between levelText and hpText relative to healthBar center
    local xOffset = math.floor((leftWidth - hpWidth) / 2)
    frame.threatText:ClearAllPoints()
    frame.threatText:SetPoint("CENTER", frame.healthBar, "CENTER", xOffset, 0)
    frame.threatText:SetJustifyH("CENTER")
end

-- Helper: Normalize threat percentage (scaledPct is 0-100; rawPct 255 is byte representation of 100%)
local function NormalizePct(scaledPct, rawPct)
    if scaledPct and not IsSecret(scaledPct) then
        if scaledPct == 255 then return 100 end
        return scaledPct
    end
    if rawPct and not IsSecret(rawPct) then
        if rawPct == 255 then return 100 end
        return rawPct
    end
    return 0
end

-- Helper: Get threat situation safely guarded against secret values and targeting proxy
local function SafeThreat(unit)
    local checkUnit = unit
    if SafeCall(UnitIsUnit, unit, "target") then
        checkUnit = "target"
    end
    
    local status, isTanking, scaledPct, rawPct
    
    -- Priority 1: UnitThreatSituation returns status integer (0, 1, 2, 3) cleanly without secret taint
    local okStatus, uStatus, uScaled, uRaw = pcall(UnitThreatSituation, "player", checkUnit)
    if (not okStatus or uStatus == nil) and checkUnit ~= unit then
        okStatus, uStatus, uScaled, uRaw = pcall(UnitThreatSituation, "player", unit)
    end
    if okStatus and uStatus ~= nil and not IsSecret(uStatus) then
        status = uStatus
        scaledPct = (uScaled and not IsSecret(uScaled)) and uScaled or nil
        rawPct = (uRaw and not IsSecret(uRaw)) and uRaw or nil
    end
    
    -- Priority 2: Query UnitDetailedThreatSituation for percentage details
    local okDet, dtTanking, dtStatus, dtScaled, dtRaw = pcall(UnitDetailedThreatSituation, "player", checkUnit)
    if (not okDet or (dtStatus == nil and dtScaled == nil)) and checkUnit ~= unit then
        okDet, dtTanking, dtStatus, dtScaled, dtRaw = pcall(UnitDetailedThreatSituation, "player", unit)
    end
    if okDet then
        if not IsSecret(dtTanking) then
            isTanking = dtTanking
        end
        if status == nil and dtStatus ~= nil and not IsSecret(dtStatus) then
            status = dtStatus
        end
        if not IsSecret(dtScaled) and dtScaled ~= nil then
            scaledPct = dtScaled
        end
        if not IsSecret(dtRaw) and dtRaw ~= nil then
            rawPct = dtRaw
        end
    end
    
    if isTanking == nil and status ~= nil then
        isTanking = (status == 3)
    end
    
    return isTanking, status, scaledPct, rawPct
end

-- Helper: Check if aura caster is the player or player's pet
local function IsPlayerSource(src, isMine)
    if isMine == true or isMine == 1 then return true end
    if IsSecret(src) or not src then return false end
    if src == "player" or src == "pet" or src == "vehicle" then return true end
    local isPlayer = SafeCall(UnitIsUnit, src, "player")
    if isPlayer then return true end
    local isPet = SafeCall(UnitIsUnit, src, "pet")
    if isPet then return true end
    return false
end

-- Aura Engine: scans harmful auras using standard WoW APIs (C_UnitAuras and classic fallbacks)
local function GetUnitAuraList(unit)
    if not unit then return {} end
    local auras = {}
    
    -- Method 1: C_UnitAuras.GetUnitAuras (Modern WoW / Midnight / Forever API - primary method matching Plater)
    if C_UnitAuras and C_UnitAuras.GetUnitAuras then
        local ok, list = pcall(C_UnitAuras.GetUnitAuras, unit, "HARMFUL")
        if not ok or type(list) ~= "table" or #list == 0 then
            local sortRule = (Enum and Enum.UnitAuraSortRule and Enum.UnitAuraSortRule.Expiration) or nil
            ok, list = pcall(C_UnitAuras.GetUnitAuras, unit, "HARMFUL", nil, sortRule)
        end
        if ok and type(list) == "table" and #list > 0 then
            for _, a in ipairs(list) do
                if a then
                    table.insert(auras, {
                        name = a.name,
                        icon = a.icon or a.iconFileID,
                        applications = a.applications or a.charges,
                        dispelName = a.dispelName,
                        duration = a.duration,
                        expirationTime = a.expirationTime,
                        sourceUnit = a.sourceUnit,
                        spellId = a.spellId,
                        auraInstanceID = a.auraInstanceID,
                        isFromPlayerOrPlayerPet = (a.isFromPlayerOrPlayerPet == true or a.isPlayerAura == true),
                        canApplyAura = a.canApplyAura,
                    })
                end
            end
            if #auras > 0 then return auras end
        end
    end
    
    -- Methods 2-5: Manual aura slot scanning (Classic engines only; skipped on Midnight to avoid taint exceptions)
    local shouldSkipManualScan = false
    if IS_MIDNIGHT_ENGINE and C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local okSec, isSec = pcall(C_Secrets.ShouldAurasBeSecret)
        if okSec and isSec then
            shouldSkipManualScan = true
        end
    end
    
    if not shouldSkipManualScan then
        -- Method 2: C_UnitAuras.GetAuraDataByIndex (standard WoW API)
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            for i = 1, 40 do
                local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
                if not ok or not aura then break end
                table.insert(auras, {
                    name = aura.name,
                    icon = aura.iconFileID or aura.icon,
                    applications = aura.applications or aura.charges,
                    dispelName = aura.dispelName,
                    duration = aura.duration,
                    expirationTime = aura.expirationTime,
                    sourceUnit = aura.sourceUnit,
                    spellId = aura.spellId,
                    auraInstanceID = aura.auraInstanceID,
                    isFromPlayerOrPlayerPet = (aura.isFromPlayerOrPlayerPet == true or aura.isPlayerAura == true),
                    canApplyAura = aura.canApplyAura,
                })
            end
            if #auras > 0 then return auras end
        end
        
        -- Method 3: Classic UnitDebuff
        if UnitDebuff then
            for i = 1, 40 do
                local ok, n, ic, c, dt, d, exp, src, steal, showPers, sId, canApply, isBoss, castByPl = pcall(UnitDebuff, unit, i)
                if not ok or n == nil then break end
                table.insert(auras, {
                    name = n,
                    icon = ic,
                    applications = c,
                    dispelName = dt,
                    duration = d,
                    expirationTime = exp,
                    sourceUnit = src,
                    isStealable = steal,
                    nameplateShowPersonal = showPers,
                    spellId = sId,
                    canApplyAura = canApply,
                    isBossAura = isBoss,
                    isFromPlayerOrPlayerPet = (castByPl == true or castByPl == 1),
                })
            end
            if #auras > 0 then return auras end
        end
        
        -- Method 4: Classic UnitAura
        if UnitAura then
            for i = 1, 40 do
                local ok, n, ic, c, dt, d, exp, src, steal, showPers, sId, canApply, isBoss, castByPl = pcall(UnitAura, unit, i, "HARMFUL")
                if not ok or n == nil then break end
                table.insert(auras, {
                    name = n,
                    icon = ic,
                    applications = c,
                    dispelName = dt,
                    duration = d,
                    expirationTime = exp,
                    sourceUnit = src,
                    isStealable = steal,
                    nameplateShowPersonal = showPers,
                    spellId = sId,
                    canApplyAura = canApply,
                    isBossAura = isBoss,
                    isFromPlayerOrPlayerPet = (castByPl == true or castByPl == 1),
                })
            end
            if #auras > 0 then return auras end
        end
        
        -- Method 5: C_UnitAuras.GetAuraSlots + GetAuraDataBySlot
        if C_UnitAuras and C_UnitAuras.GetAuraSlots and C_UnitAuras.GetAuraDataBySlot then
            local continuationToken
            local guard = 0
            repeat
                guard = guard + 1
                if guard > 10 then break end
                local slots = { pcall(C_UnitAuras.GetAuraSlots, unit, "HARMFUL", 40, continuationToken) }
                if not slots[1] then break end
                continuationToken = slots[2]
                for i = 3, #slots do
                    local slot = slots[i]
                    if slot then
                        local okAura, aura = pcall(C_UnitAuras.GetAuraDataBySlot, unit, slot)
                        if okAura and aura then
                            table.insert(auras, {
                                name = aura.name,
                                icon = aura.iconFileID or aura.icon,
                                applications = aura.applications or aura.charges,
                                dispelName = aura.dispelName,
                                duration = aura.duration,
                                expirationTime = aura.expirationTime,
                                sourceUnit = aura.sourceUnit,
                                spellId = aura.spellId,
                                auraInstanceID = aura.auraInstanceID,
                                isFromPlayerOrPlayerPet = (aura.isFromPlayerOrPlayerPet == true or aura.isPlayerAura == true),
                                canApplyAura = aura.canApplyAura,
                            })
                        end
                    end
                end
            until continuationToken == nil
            if #auras > 0 then return auras end
        end
    end
    
    return auras
end

-- Cache player's known spells from the spellbook for infallible aura identification
local playerSpells = {}

local function SeedClassSpells()
    local _, class = UnitClass("player")
    if class == "PALADIN" then
        playerSpells["consecration"] = true
        playerSpells["consecrate"] = true
        playerSpells["seal of fury"] = true
        playerSpells["judgement of fury"] = true
        playerSpells["fury"] = true
        playerSpells["taunt"] = true
        playerSpells["judgement"] = true
        playerSpells["judgement of the crusader"] = true
        playerSpells["judgement of light"] = true
        playerSpells["judgement of wisdom"] = true
        playerSpells["judgement of justice"] = true
        playerSpells["hammer of justice"] = true
        playerSpells["repentance"] = true
        playerSpells["turn undead"] = true
        playerSpells["turn evil"] = true
        playerSpells["holy wrath"] = true
        playerSpells["exorcism"] = true
        playerSpells["vindication"] = true
        playerSpells["avenger's shield"] = true
        playerSpells["shield of the righteous"] = true
        playerSpells["crusader strike"] = true
        playerSpells["righteous fury"] = true
    elseif class == "WARRIOR" then
        playerSpells["rend"] = true
        playerSpells["sunder armor"] = true
        playerSpells["hamstring"] = true
        playerSpells["thunder clap"] = true
        playerSpells["demoralizing shout"] = true
        playerSpells["mortal strike"] = true
        playerSpells["taunt"] = true
        playerSpells["mocking blow"] = true
        playerSpells["concussion blow"] = true
        playerSpells["disarm"] = true
    elseif class == "PRIEST" then
        playerSpells["shadow word: pain"] = true
        playerSpells["holy fire"] = true
        playerSpells["mind flay"] = true
        playerSpells["vampiric touch"] = true
        playerSpells["devouring plague"] = true
        playerSpells["psychic scream"] = true
        playerSpells["shackle undead"] = true
        playerSpells["silence"] = true
    elseif class == "WARLOCK" then
        playerSpells["corruption"] = true
        playerSpells["curse of agony"] = true
        playerSpells["curse of weakness"] = true
        playerSpells["curse of the elements"] = true
        playerSpells["curse of recklessness"] = true
        playerSpells["curse of shadow"] = true
        playerSpells["curse of tongues"] = true
        playerSpells["immolate"] = true
        playerSpells["siphon life"] = true
        playerSpells["drain life"] = true
        playerSpells["drain soul"] = true
        playerSpells["drain mana"] = true
        playerSpells["fear"] = true
        playerSpells["howl of terror"] = true
        playerSpells["banish"] = true
        playerSpells["death coil"] = true
    elseif class == "MAGE" then
        playerSpells["frostbolt"] = true
        playerSpells["fireball"] = true
        playerSpells["fire blast"] = true
        playerSpells["pyroblast"] = true
        playerSpells["scorch"] = true
        playerSpells["ignite"] = true
        playerSpells["frost nova"] = true
        playerSpells["cone of cold"] = true
        playerSpells["blizzard"] = true
        playerSpells["polymorph"] = true
        playerSpells["slow"] = true
        playerSpells["flamestrike"] = true
    elseif class == "ROGUE" then
        playerSpells["rupture"] = true
        playerSpells["garrote"] = true
        playerSpells["deadly poison"] = true
        playerSpells["crippling poison"] = true
        playerSpells["wound poison"] = true
        playerSpells["mind-numbing poison"] = true
        playerSpells["gouge"] = true
        playerSpells["kidney shot"] = true
        playerSpells["cheap shot"] = true
        playerSpells["blind"] = true
        playerSpells["expose armor"] = true
        playerSpells["kick"] = true
    elseif class == "DRUID" then
        playerSpells["moonfire"] = true
        playerSpells["insect swarm"] = true
        playerSpells["rake"] = true
        playerSpells["rip"] = true
        playerSpells["faerie fire"] = true
        playerSpells["faerie fire (feral)"] = true
        playerSpells["entangling roots"] = true
        playerSpells["hibernate"] = true
        playerSpells["demoralizing roar"] = true
        playerSpells["bash"] = true
        playerSpells["pounce"] = true
    elseif class == "SHAMAN" then
        playerSpells["flame shock"] = true
        playerSpells["frost shock"] = true
        playerSpells["earth shock"] = true
        playerSpells["stormstrike"] = true
    elseif class == "HUNTER" then
        playerSpells["serpent sting"] = true
        playerSpells["hunter's mark"] = true
        playerSpells["concussive shot"] = true
        playerSpells["wing clip"] = true
        playerSpells["viper sting"] = true
        playerSpells["scorpid sting"] = true
        playerSpells["freezing trap"] = true
        playerSpells["immolation trap"] = true
        playerSpells["frost trap"] = true
    end
end

local function CachePlayerSpells()
    wipe(playerSpells)
    SeedClassSpells()
    
    -- Method 1: Classic GetNumSpellTabs & GetSpellTabInfo
    if GetNumSpellTabs then
        local okTabs, numTabs = pcall(GetNumSpellTabs)
        if okTabs and numTabs then
            for tab = 1, numTabs do
                local okInfo, name, texture, offset, numSpells = pcall(GetSpellTabInfo, tab)
                if okInfo and offset and numSpells then
                    for s = offset + 1, offset + numSpells do
                        local okName, spellName = pcall(GetSpellBookItemName, s, BOOKTYPE_SPELL or "spell")
                        if okName and spellName then
                            playerSpells[spellName] = true
                            playerSpells[strlower(spellName)] = true
                        end
                    end
                end
            end
        end
    end
    
    -- Method 2: Iterate spellbook slots directly (works across Classic, Wrath, Dragonflight, Midnight)
    for s = 1, 500 do
        local found = false
        if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
            local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
            local ok, itemInfo = pcall(C_SpellBook.GetSpellBookItemInfo, s, bank)
            if ok and itemInfo then
                found = true
                local spellName = itemInfo.name
                if not spellName and itemInfo.spellID then
                    if C_Spell and C_Spell.GetSpellInfo then
                        local sInfo = SafeCall(C_Spell.GetSpellInfo, itemInfo.spellID)
                        if sInfo then spellName = sInfo.name end
                    elseif GetSpellInfo then
                        spellName = SafeCall(GetSpellInfo, itemInfo.spellID)
                    end
                end
                if spellName then
                    playerSpells[spellName] = true
                    playerSpells[strlower(spellName)] = true
                end
            end
        end
        
        if GetSpellBookItemName then
            local ok, spellName = pcall(GetSpellBookItemName, s, BOOKTYPE_SPELL or "spell")
            if ok and spellName then
                found = true
                playerSpells[spellName] = true
                playerSpells[strlower(spellName)] = true
            end
        end
        
        if not found and s > 200 then
            break
        end
    end
end

-- Immediately cache player spells on load
CachePlayerSpells()

-- Player Aura verification (strictly matches player spells, tokens, and native flags)
local function IsAuraFromPlayer(aura, unit)
    if not aura then return false end
    
    -- 0. Modern C-Engine filter check via C_UnitAuras.IsAuraFilteredOutByInstanceID (Plater Midnight architecture)
    if C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID and aura.auraInstanceID then
        local checkUnits = { unit, "target" }
        for _, u in ipairs(checkUnits) do
            if u and SafeCall(UnitExists, u) then
                local okF, isFiltered = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, u, aura.auraInstanceID, "HARMFUL|PLAYER")
                if okF and not IsSecret(isFiltered) then
                    if isFiltered == false then
                        return true -- C-Engine confirms this aura was applied by player!
                    end
                end
            end
        end
    end
    
    -- 1. Check caster sourceUnit token
    local src = aura.sourceUnit
    if src and not IsSecret(src) and type(src) == "string" and src ~= "" then
        if src == "player" or src == "pet" or src == "vehicle" then
            return true
        end
        local myName = UnitName("player")
        if myName and src == myName then return true end
        local myGUID = UnitGUID("player")
        if myGUID and src == myGUID then return true end
        local ok, isPlayer = pcall(UnitIsUnit, src, "player")
        if ok and isPlayer == true then return true end
        local okPet, isPet = pcall(UnitIsUnit, src, "pet")
        if okPet and isPet == true then return true end
        
        -- If source is explicitly another player or party/raid member, reject
        if src == "target" or string.find(src, "party") or string.find(src, "raid") then
            return false
        end
    end
    
    -- 2. Native caster boolean flags
    if aura.isFromPlayerOrPlayerPet == true or aura.isPlayerAura == true then
        return true
    end
    
    -- 3. canApplyAura flag
    if aura.canApplyAura == true then
        return true
    end
    
    -- 4. Check spellId against known player spells via C engine
    local sId = aura.spellId
    if sId and not IsSecret(sId) and type(sId) == "number" and sId > 0 then
        if IsPlayerSpell and SafeCall(IsPlayerSpell, sId) then return true end
        if IsSpellKnown and SafeCall(IsSpellKnown, sId) then return true end
        if C_SpellBook and C_SpellBook.IsSpellKnown then
            local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
            if SafeCall(C_SpellBook.IsSpellKnown, sId, bank) then return true end
        end
    end
    
    -- 5. Spellbook & class matching (handles ground AoEs like Consecration, custom seals, judgements)
    local auraName = aura.name
    if auraName and not IsSecret(auraName) then
        local lower = strlower(auraName)
        if playerSpells[auraName] or playerSpells[lower] then
            return true
        end
        if string.find(lower, "consecrat") and (playerSpells["consecration"] or playerSpells["consecrate"]) then
            return true
        end
        if string.find(lower, "fury") and (playerSpells["seal of fury"] or playerSpells["judgement of fury"] or playerSpells["fury"]) then
            return true
        end
        if (string.find(lower, "judgement") or string.find(lower, "seal of")) then
            for spellName in pairs(playerSpells) do
                local sLower = strlower(spellName)
                local suffix = string.match(sLower, "seal of (.+)") or string.match(sLower, "judgement of (.+)")
                if suffix and string.find(lower, suffix) then
                    return true
                end
            end
        end
    end
    
    -- 6. In Midnight / Forever engine, nameplate aura queries return only relevant unit debuffs
    -- When sourceUnit is nil/restricted (Blizzard secret protection), do not drop debuffs unless explicitly from someone else
    if IS_MIDNIGHT_ENGINE then
        return true
    end
    
    return false
end

-- Suppress Blizzard's default nameplate frames cleanly and permanently (matching Plater's architecture)
local HOOKED_BLIZZARD_PLATEFRAMES = {}

local function SuppressBlizzardUnitFrame(self)
    if not self or self:IsForbidden() then return end
    
    if not InCombatLockdown() then
        if self:IsProtected() then
            pcall(self.ClearAllPoints, self)
            pcall(self.SetParent, self, nil)
            if self.HealthBarsContainer then
                pcall(self.HealthBarsContainer.ClearAllPoints, self.HealthBarsContainer)
            end
        else
            pcall(self.Hide, self)
        end
    end
    
    pcall(self.SetAlpha, self, 0)
    if self.HealthBarsContainer then
        pcall(self.HealthBarsContainer.SetAlpha, self.HealthBarsContainer, 0)
        if self.HealthBarsContainer.healthBar then
            pcall(self.HealthBarsContainer.healthBar.SetAlpha, self.HealthBarsContainer.healthBar, 0)
        end
    end
    if self.healthBar then
        pcall(self.healthBar.SetAlpha, self.healthBar, 0)
    end
    if self.castBar then
        pcall(self.castBar.SetAlpha, self.castBar, 0)
    end
    
    pcall(function() self:UnregisterAllEvents() end)
    if self.HealthBarsContainer and self.HealthBarsContainer.healthBar then
        pcall(function() self.HealthBarsContainer.healthBar:UnregisterAllEvents() end)
    end
    if self.castBar then
        pcall(function() self.castBar:UnregisterAllEvents() end)
    end
    if CompactUnitFrame_UnregisterEvents then
        pcall(CompactUnitFrame_UnregisterEvents, self)
        if self.HealthBarsContainer and self.HealthBarsContainer.healthBar then
            pcall(CompactUnitFrame_UnregisterEvents, self.HealthBarsContainer.healthBar)
        end
        if self.castBar then
            pcall(CompactUnitFrame_UnregisterEvents, self.castBar)
        end
    end
end

local function HookAndSuppressBlizzardFrame(frame)
    if not frame or frame:IsForbidden() then return end
    local id = tostring(frame)
    if not HOOKED_BLIZZARD_PLATEFRAMES[id] then
        HOOKED_BLIZZARD_PLATEFRAMES[id] = true
        hooksecurefunc(frame, "Show", SuppressBlizzardUnitFrame)
        hooksecurefunc(frame, "SetAlpha", function(self, alpha)
            if alpha and alpha > 0 then
                pcall(self.SetAlpha, self, 0)
            end
        end)
    end
    SuppressBlizzardUnitFrame(frame)
end

local function HideBlizzardPlate(namePlate)
    if not namePlate or namePlate:IsForbidden() then return end
    if namePlate.SetClipsChildren then
        pcall(namePlate.SetClipsChildren, namePlate, false)
    end
    if namePlate.UnitFrame then
        HookAndSuppressBlizzardFrame(namePlate.UnitFrame)
    end
    if namePlate.unitFrame and namePlate.unitFrame ~= namePlate.mpFrame then
        HookAndSuppressBlizzardFrame(namePlate.unitFrame)
    end
    for _, child in ipairs({ namePlate:GetChildren() }) do
        if child ~= namePlate.mpFrame and not child:IsForbidden() then
            if child.HealthBarsContainer or child.healthBar or child.castBar then
                HookAndSuppressBlizzardFrame(child)
            else
                if not child:IsProtected() and not InCombatLockdown() then pcall(child.Hide, child) end
                pcall(child.SetAlpha, child, 0)
            end
        end
    end
end

-- Resolve threat colors based on status, percentage, and tank/DPS role
function MP:GetThreatColor(status, pct, tankMode, isLead)
    local hasPct = pct and not IsSecret(pct)
    if tankMode then
        -- Tank Mode: Green is secure aggro, Red is no aggro
        if isLead then
            if status == 2 or (hasPct and pct <= 0) then
                return 0.9, 0.6, 0   -- Orange (deficit or about to lose aggro)
            elseif hasPct and pct <= 15 then
                return 0.9, 0.8, 0.2 -- Yellow (warning: 2nd place within 15% of your threat)
            elseif status == 3 then
                return 0.2, 0.8, 0.2 -- Green (healthy lead ahead)
            else
                return 0.9, 0.2, 0.2 -- Red (no aggro)
            end
        else
            if status == 3 then
                return 0.2, 0.8, 0.2 -- Green (secure aggro)
            elseif status == 2 then
                return 0.9, 0.6, 0   -- Orange (losing aggro)
            elseif status == 1 or (hasPct and pct >= 100) then
                return 0.9, 0.8, 0.2 -- Yellow/Orange (gaining aggro back)
            else
                return 0.9, 0.2, 0.2 -- Red (no aggro)
            end
        end
    else
        -- DPS Mode: Green is safe, Red is danger
        if status == 3 or status == 2 then
            return 0.9, 0.2, 0.2 -- Red (you have aggro)
        elseif status == 1 or (hasPct and pct >= 100) then
            return 0.9, 0.6, 0   -- Orange (warning - about to pull aggro)
        elseif hasPct and pct >= 80 then
            return 0.9, 0.8, 0.2 -- Yellow (approaching aggro)
        else
            return 0.2, 0.8, 0.2 -- Green (safe)
        end
    end
end

-- Helper: Parse debuff tooltip for exact periodic damage
local scanTooltip
local function GetDebuffTooltipDamage(unit, index, spellId, auraInstanceID)
    -- Modern WoW / Midnight C_TooltipInfo API
    if C_TooltipInfo then
        local data
        if auraInstanceID and C_TooltipInfo.GetUnitAuraByAuraInstanceID then
            local ok, d = pcall(C_TooltipInfo.GetUnitAuraByAuraInstanceID, unit, auraInstanceID)
            if ok and d then data = d end
        end
        if not data and index and C_TooltipInfo.GetUnitDebuff then
            local ok, d = pcall(C_TooltipInfo.GetUnitDebuff, unit, index)
            if ok and d then data = d end
        end
        if not data and spellId and C_TooltipInfo.GetSpellByID then
            local ok, d = pcall(C_TooltipInfo.GetSpellByID, spellId)
            if ok and d then data = d end
        end
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                local text = line.leftText
                if text and type(text) == "string" and not IsSecret(text) then
                    local dmg, dur = text:match("(%d+)[%s%a]*damage over (%d+)%s*sec")
                    if not dmg then dmg, dur = text:match("for (%d+) damage over (%d+)%s*sec") end
                    if not dmg then dmg, dur = text:match("Bleeding for (%d+) damage over (%d+)%s*sec") end
                    if not dmg then dmg = text:match("Bleeding for (%d+)") end
                    if not dmg then dmg = text:match("(%d+)%s*[%a%s]*damage") end
                    if dmg then
                        local dVal = tonumber(dmg)
                        if dVal and dVal > 0 then
                            return dVal, tonumber(dur)
                        end
                    end
                end
            end
        end
    end
    
    -- Classic GameTooltip scanning fallback
    if not scanTooltip and CreateFrame then
        local ok, tip = pcall(CreateFrame, "GameTooltip", "MyPlatesScanTooltip", nil, "GameTooltipTemplate")
        if ok and tip then
            scanTooltip = tip
            scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
        end
    end
    if scanTooltip and index then
        scanTooltip:ClearLines()
        local ok = pcall(scanTooltip.SetUnitDebuff, scanTooltip, unit, index)
        if ok then
            local numLines = scanTooltip:NumLines()
            if numLines and numLines > 1 then
                for i = 2, numLines do
                    local fs = _G["MyPlatesScanTooltipTextLeft" .. i]
                    if fs then
                        local text = fs:GetText()
                        if text and type(text) == "string" and not IsSecret(text) then
                            local dmg, dur = text:match("(%d+)[%s%a]*damage over (%d+)%s*sec")
                            if not dmg then dmg, dur = text:match("for (%d+) damage over (%d+)%s*sec") end
                            if not dmg then dmg, dur = text:match("Bleeding for (%d+) damage over (%d+)%s*sec") end
                            if not dmg then dmg = text:match("Bleeding for (%d+)") end
                            if not dmg then dmg = text:match("(%d+)%s*[%a%s]*damage") end
                            if dmg then
                                local dVal = tonumber(dmg)
                                if dVal and dVal > 0 then
                                    return dVal, tonumber(dur)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

-- Calculate total remaining DoT damage on unit from player
function MP:GetUnitDoTDamage(unit)
    if not unit then return 0 end
    local totalDmg = 0
    local now = GetTime()
    
    local auras = GetUnitAuraList(unit)
    
    for i, a in ipairs(auras or {}) do
        local isAllowed = a.isFromPlayerOrPlayerPet or (a.sourceUnit == "player") or (a.sourceUnit == "pet") or IsAuraFromPlayer(a, unit)
        if not isAllowed and MP.db.includeGroupDots and a.sourceUnit and not IsSecret(a.sourceUnit) then
            local s = a.sourceUnit
            if type(s) == "string" and (s == "party1" or s == "party2" or s == "party3" or s == "party4" or s:match("^party") or s:match("^raid")) then
                isAllowed = true
            elseif UnitInParty and SafeCall(UnitInParty, s) then
                isAllowed = true
            elseif UnitInRaid and SafeCall(UnitInRaid, s) then
                isAllowed = true
            end
        end
        if isAllowed and a.expirationTime and not IsSecret(a.expirationTime) and a.expirationTime > now then
            local timeLeft = a.expirationTime - now
            local name = a.name
            local spellId = a.spellId
            local hasSafeName = name and not IsSecret(name) and type(name) == "string"
            local hasSafeSpellId = spellId and not IsSecret(spellId) and type(spellId) == "number"
            
            local tickRate = (hasSafeName and MP.dotTickRates[name]) or (hasSafeSpellId and MP.dotTickRates[spellId]) or 3.0
            local remainingTicks = math.ceil(timeLeft / tickRate)
            
            local tickAmount = (hasSafeSpellId and MP.dotTickCache[spellId]) or (hasSafeName and MP.dotTickCache[name])
            
            -- If not yet in cache, inspect debuff tooltip for exact periodic damage
            if (not tickAmount or tickAmount <= 0) then
                local tipDmg, tipDur = GetDebuffTooltipDamage(unit, i, spellId, a.auraInstanceID)
                if tipDmg and tipDmg > 0 then
                    local d = (tipDur and tipDur > 0) and tipDur or a.duration
                    if d and d > 0 then
                        local totalTicks = math.max(1, math.floor(d / tickRate + 0.5))
                        tickAmount = math.floor(tipDmg / totalTicks)
                        if tickAmount > 0 then
                            if hasSafeName then MP.dotTickCache[name] = tickAmount end
                            if hasSafeSpellId then MP.dotTickCache[spellId] = tickAmount end
                        end
                    end
                end
            end
            
            -- Calibrated fallback per spell (avoids massive overestimates)
            if not tickAmount or tickAmount <= 0 then
                tickAmount = (hasSafeSpellId and MP.defaultDotTicks[spellId]) or (hasSafeName and MP.defaultDotTicks[name]) or math.floor((UnitLevel("player") or 60) * 0.5)
            end
            
            if tickAmount and not IsSecret(tickAmount) and tickAmount > 0 and remainingTicks > 0 then
                local isStackingSpell = hasSafeName and (name == "Deadly Poison" or name == "Lacerate" or name == "Searing Flames")
                local stackCount = (isStackingSpell and a.applications and not IsSecret(a.applications) and a.applications > 1) and a.applications or 1
                totalDmg = totalDmg + (remainingTicks * tickAmount * stackCount)
            end
        end
    end
    
    return totalDmg
end

-- Update lethal DoT prediction and visuals
function MP:UpdateDoTLethal(frame)
    if not frame or not frame.unit or not MP.db.enableDotKill then
        frame.isDotLethal = false
        if frame.lethalSkull then frame.lethalSkull:Hide() end
        if frame.dotPredictionBar then frame.dotPredictionBar:Hide() end
        if frame.hpText then frame.hpText:SetTextColor(1, 1, 1) end
        return false
    end
    
    local unit = frame.unit
    local hp = SafeCall(UnitHealth, unit)
    local maxHp = SafeCall(UnitHealthMax, unit)
    if (not hp or not maxHp or hp <= 0 or maxHp <= 0) and SafeCall(UnitIsUnit, unit, "target") then
        hp = SafeCall(UnitHealth, "target")
        maxHp = SafeCall(UnitHealthMax, "target")
    end
    
    if not hp or hp <= 0 or not maxHp or maxHp <= 0 then
        -- Modern WoW / Midnight fallback via UnitHealthPercent
        if UnitHealthPercent then
            local curve = CurveConstants and CurveConstants.ScaleTo100
            local okP, hpPct = pcall(UnitHealthPercent, unit, false, curve)
            if (not okP or not hpPct) and SafeCall(UnitIsUnit, unit, "target") then
                okP, hpPct = pcall(UnitHealthPercent, "target", false, curve)
            end
            if okP and hpPct and type(hpPct) == "number" and not IsSecret(hpPct) and hpPct > 0 then
                local mHp = frame.lastKnownMaxHp or (frame.healthBar and frame.healthBar.lastKnownMaxHp)
                if not mHp or mHp <= 0 then
                    local mobLevel = SafeCall(UnitLevel, unit) or 70
                    mHp = mobLevel * 50
                end
                maxHp = mHp
                hp = math.floor(maxHp * (hpPct / 100))
            end
        end
    end
    
    if not hp or hp <= 0 or not maxHp or maxHp <= 0 then
        frame.isDotLethal = false
        if frame.lethalSkull then frame.lethalSkull:Hide() end
        if frame.dotPredictionBar then frame.dotPredictionBar:Hide() end
        if frame.hpText then frame.hpText:SetTextColor(1, 1, 1) end
        return false
    end
    
    local dotDmg = MP:GetUnitDoTDamage(unit)
    local isLethal = (dotDmg >= hp) and (dotDmg > 0)
    frame.isDotLethal = isLethal
    
    -- 1. Skull Marker (💀 next to unit name)
    if frame.lethalSkull then
        if isLethal and MP.db.dotLethalSkull then
            frame.lethalSkull:Show()
        else
            frame.lethalSkull:Hide()
        end
    end
    
    -- 2. DoT Prediction Bar (Ghost overlay on health bar)
    if frame.dotPredictionBar then
        if dotDmg > 0 and MP.db.dotLethalPrediction then
            local barWidth = frame.healthBar:GetWidth()
            local curHpRatio = math.max(0, math.min(1, hp / maxHp))
            local predRatio = math.max(0, math.min(curHpRatio, dotDmg / maxHp))
            local rightOffset = curHpRatio * barWidth
            local predWidth = predRatio * barWidth
            
            frame.dotPredictionBar:ClearAllPoints()
            frame.dotPredictionBar:SetPoint("TOPRIGHT", frame.healthBar, "TOPLEFT", rightOffset, 0)
            frame.dotPredictionBar:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMLEFT", rightOffset, 0)
            frame.dotPredictionBar:SetWidth(math.max(1, predWidth))
            
            if isLethal then
                frame.dotPredictionBar:SetVertexColor(0.85, 0.25, 0.95, 0.65)
            else
                frame.dotPredictionBar:SetVertexColor(0.7, 0.3, 0.85, 0.35)
            end
            frame.dotPredictionBar:Show()
        else
            frame.dotPredictionBar:Hide()
        end
    end
    
    -- 3. Health Text Color
    if isLethal and MP.db.dotLethalHpText then
        frame.hpText:SetTextColor(0.95, 0.4, 1.0)
    else
        frame.hpText:SetTextColor(1, 1, 1)
    end
    
    return isLethal
end

-- Color updates based on class/reaction/threat
function MP:UpdateHealthColor(frame)
    local unit = frame.unit
    if not unit then return end
    
    -- Check if target will die to active player DoTs
    if MP.db.enableDotKill and MP.db.dotLethalBar and frame.isDotLethal then
        frame.healthBar:SetStatusBarColor(0.85, 0.25, 0.95)
        return
    end
    
    local isPlayer = SafeCall(UnitIsPlayer, unit)
    local isTapDenied = SafeCall(UnitIsTapDenied, unit)
    
    -- Tapped/Claimed by another player
    if not isPlayer and isTapDenied then
        frame.healthBar:SetStatusBarColor(0.5, 0.5, 0.5) -- Grey
        return
    end
    
    -- 1. Class coloring for players (Friendly and Enemy)
    if isPlayer then
        local isFriend = SafeCall(UnitIsFriend, "player", unit)
        local useClass = false
        if isFriend then
            useClass = (MP.db.useClassColorsFriendly ~= false) and (MP.db.useClassColors ~= false)
        else
            useClass = (MP.db.useClassColorsEnemy ~= false) and (MP.db.useClassColors ~= false)
        end
        
        if useClass then
            local _, class = SafeCall(UnitClass, unit)
            local color = class and RAID_CLASS_COLORS[class]
            if color then
                frame.healthBar:SetStatusBarColor(color.r, color.g, color.b)
                return
            end
        end
    end
    
    -- 2. Threat coloring (enemy NPCs & in combat)
    if MP.db.enableThreat and SafeCall(UnitCanAttack, "player", unit) and not isPlayer then
        local ok, status = pcall(UnitThreatSituation, "player", unit)
        if (not ok or status == nil) and SafeCall(UnitIsUnit, unit, "target") then
            ok, status = pcall(UnitThreatSituation, "player", "target")
        end
        if ok and status ~= nil and not IsSecret(status) then
            local r, g, b = MP:GetThreatColor(status, nil, MP.db.tankMode, false)
            frame.healthBar:SetStatusBarColor(r, g, b)
            return
        end
    end

    -- 3. Reaction coloring for NPCs (or players without class colors)
    if MP.db.useReactionColors then
        local reaction = SafeCall(UnitReaction, unit, "player")
        if reaction then
            if reaction >= 5 then
                frame.healthBar:SetStatusBarColor(0.2, 0.8, 0.2) -- Green
                return
            elseif reaction == 4 then
                frame.healthBar:SetStatusBarColor(0.9, 0.8, 0.2) -- Yellow
                return
            elseif reaction <= 3 then
                frame.healthBar:SetStatusBarColor(0.9, 0.2, 0.2) -- Red
                return
            end
        end
    end
    
    -- Fallback
    frame.healthBar:SetStatusBarColor(0.7, 0.7, 0.7)
end

-- Get highest threat percentage among other group members relative to player/tank
function MP:GetHighestGroupThreat(unit)
    local maxPct = 0
    local checkUnit = SafeCall(UnitIsUnit, unit, "target") and "target" or unit
    
    local function CheckUnitThreat(groupUnit)
        if groupUnit and not SafeCall(UnitIsUnit, groupUnit, "player") and SafeCall(UnitExists, groupUnit) then
            local ok, isTanking, status, scaledPct, rawPct = pcall(UnitDetailedThreatSituation, groupUnit, checkUnit)
            if not ok or status == nil then
                local ok2, uStatus, uScaled, uRaw = pcall(UnitThreatSituation, groupUnit, checkUnit)
                if (not ok2 or uStatus == nil) and checkUnit ~= unit then
                    ok2, uStatus, uScaled, uRaw = pcall(UnitThreatSituation, groupUnit, unit)
                end
                if ok2 and uStatus ~= nil then
                    scaledPct = uScaled
                    rawPct = uRaw
                end
            end
            local pct = NormalizePct(scaledPct, rawPct)
            if pct and pct > 100 then
                pct = 100
            end
            if pct and pct > maxPct then
                maxPct = pct
            end
        end
    end
    
    if IsInRaid() then
        local num = GetNumGroupMembers() or 0
        for i = 1, num do
            CheckUnitThreat(raidUnits[i])
            CheckUnitThreat("raidpet" .. i)
        end
    elseif IsInGroup() then
        local num = GetNumSubgroupMembers() or 0
        for i = 1, num do
            CheckUnitThreat(partyUnits[i])
            CheckUnitThreat("partypet" .. i)
        end
    end
    
    if HasPetUI() and SafeCall(UnitExists, "pet") then
        CheckUnitThreat("pet")
    end
    
    return maxPct
end

-- Update threat status and percentage
function MP:UpdateThreat(frame)
    local unit = frame.unit
    if not unit then return end
    
    -- First update health color
    MP:UpdateHealthColor(frame)
    
    -- Sync raid icon state
    MP:UpdateRaidIcon(frame)
    
    -- Sync threat percentage display
    if not MP.db.enableThreat then
        frame.threatText:SetText("")
        return
    end
    
    if SafeCall(UnitCanAttack, "player", unit) then
        local isTanking, status, scaledPercentage, rawPercentage = SafeThreat(unit)
        
        if status ~= nil and not IsSecret(status) then
            local displayPercentage = 0
            local isLead = false
            local tanking = (not IsSecret(isTanking)) and isTanking
            
            if tanking or status == 3 or status == 2 then
                -- When holding aggro, calculate your lead ahead of the #2 group member
                local secondThreat = MP:GetHighestGroupThreat(unit)
                if secondThreat and not IsSecret(secondThreat) and secondThreat > 0 then
                    displayPercentage = 100 - secondThreat
                    isLead = true
                else
                    -- Solo or nobody else has threat: blank text like TBC!
                    displayPercentage = 0
                    isLead = false
                end
            else
                -- We don't hold aggro, show our threat percentage relative to the tank
                displayPercentage = NormalizePct(scaledPercentage, rawPercentage)
                isLead = false
            end
            
            if isLead or (displayPercentage and displayPercentage > 0) then
                if displayPercentage > 130 then
                    displayPercentage = 130
                elseif displayPercentage < -130 then
                    displayPercentage = -130
                end
                
                if isLead then
                    if displayPercentage >= 0 then
                        frame.threatText:SetText(format("+%d%%", floor(displayPercentage)))
                    else
                        frame.threatText:SetText(format("%d%%", floor(displayPercentage)))
                    end
                else
                    frame.threatText:SetText(format("%d%%", floor(displayPercentage)))
                end
                
                local r, g, b = MP:GetThreatColor(status, displayPercentage, MP.db.tankMode, isLead)
                frame.threatText:SetTextColor(r, g, b)
                MP:UpdatePlateWidth(frame)
                return
            end
        else
            -- Secret fallback: if status is secret or unavailable, try normalized threat percentage
            local pctVal = NormalizePct(scaledPercentage, rawPercentage)
            if pctVal and pctVal > 0 then
                if pctVal > 130 then pctVal = 130 end
                local okSet = pcall(frame.threatText.SetFormattedText, frame.threatText, "%d%%", pctVal)
                if not okSet then
                    pcall(frame.threatText.SetText, frame.threatText, pctVal)
                end
                frame.threatText:SetTextColor(0.9, 0.8, 0.2)
                MP:UpdatePlateWidth(frame)
                return
            end
        end
    end
    frame.threatText:SetText("")
    MP:UpdatePlateWidth(frame)
end

-- Update health and health text
function MP:UpdateHealth(frame)
    local unit = frame.unit
    if not unit then return end
    
    local okHp, hp = pcall(UnitHealth, unit)
    local okMax, maxHp = pcall(UnitHealthMax, unit)
    
    if not okHp or not okMax then
        frame.hpText:SetText("")
        return
    end
    if (not IsSecret(hp) and not hp) or (not IsSecret(maxHp) and not maxHp) then
        frame.hpText:SetText("")
        return
    end
    
    -- Status bars accept secret values natively in modern WoW C engine
    pcall(frame.healthBar.SetMinMaxValues, frame.healthBar, 0, maxHp)
    pcall(frame.healthBar.SetValue, frame.healthBar, hp)
    
    local isTarget = SafeCall(UnitIsUnit, unit, "target")
    local displaySet = false
    
    -- Priority 1: If this plate is our target, query "target" for reliable non-secret health numbers
    if isTarget then
        local tHp = SafeCall(UnitHealth, "target")
        local tMax = SafeCall(UnitHealthMax, "target")
        if tHp and tMax and not IsSecret(tHp) and not IsSecret(tMax) and tMax > 0 then
            frame.lastKnownMaxHp = tMax
            frame.lastKnownHp = tHp
            local percent = floor((tHp / tMax) * 100)
            if tHp >= 1000000 then
                frame.hpText:SetText(format("%.1fM (%d%%)", tHp / 1000000, percent))
            elseif tHp >= 1000 then
                frame.hpText:SetText(format("%.1fk (%d%%)", tHp / 1000, percent))
            else
                frame.hpText:SetText(format("%d (%d%%)", tHp, percent))
            end
            displaySet = true
        end
    end
    
    -- Priority 2: If hp and maxHp on unit are non-secret numbers, format normally
    if not displaySet and not IsSecret(hp) and not IsSecret(maxHp) and hp and maxHp then
        local percent = maxHp > 0 and floor((hp / maxHp) * 100) or 0
        if hp >= 1000000 then
            frame.hpText:SetText(format("%.1fM (%d%%)", hp / 1000000, percent))
        elseif hp >= 1000 then
            frame.hpText:SetText(format("%.1fk (%d%%)", hp / 1000, percent))
        else
            frame.hpText:SetText(format("%d (%d%%)", hp, percent))
        end
        displaySet = true
    end
    
    -- Priority 3: Fallback for secret hp value - pass directly into native C display sink
    if not displaySet and hp then
        local displayFormatted = false
        if UnitHealthPercent then
            local curve = CurveConstants and CurveConstants.ScaleTo100
            local okP, hpPct = pcall(UnitHealthPercent, unit, false, curve)
            if (not okP or not hpPct) and isTarget then
                okP, hpPct = pcall(UnitHealthPercent, "target", false, curve)
            end
            if okP and hpPct then
                local okFmt = pcall(frame.hpText.SetFormattedText, frame.hpText, "%s (%.0f%%)", hp, hpPct)
                if okFmt then
                    displayFormatted = true
                end
            end
        end
        if not displayFormatted then
            local okFmt = pcall(frame.hpText.SetFormattedText, frame.hpText, "%s", hp)
            if not okFmt then
                pcall(frame.hpText.SetText, frame.hpText, hp)
            end
        end
    end
    
    MP:UpdateDoTLethal(frame)
    MP:UpdateThreat(frame)
    MP:UpdatePlateWidth(frame)
end

-- Update name text
function MP:UpdateName(frame)
    local unit = frame.unit
    if not unit then return end
    local name = UnitName(unit)
    if not IsSecret(name) and name then
        frame.nameText:SetText(name)
    elseif IsSecret(name) then
        local ok = pcall(frame.nameText.SetText, frame.nameText, name)
        if not ok then frame.nameText:SetText("") end
    else
        frame.nameText:SetText("")
    end
end

-- Update level, classification, and dragon icon
function MP:UpdateLevel(frame)
    local unit = frame.unit
    if not unit then return end
    
    local classification = SafeCall(UnitClassification, unit)
    if IsSecret(classification) then
        classification = nil
    end
    
    -- Dragon Icon update
    if MP.db.showEliteDragon and classification and (classification == "elite" or classification == "rareelite" or classification == "rare" or classification == "worldboss") then
        local dragonTex = "Interface\\AddOns\\MyPlates\\textures\\eliteDragon.tga"
        if classification == "rare" then
            dragonTex = "Interface\\AddOns\\MyPlates\\textures\\rareDragon.tga"
        elseif classification == "rareelite" or classification == "worldboss" then
            dragonTex = "Interface\\AddOns\\MyPlates\\textures\\rareEliteDragon.tga"
        end
        frame.dragonIcon:SetTexture(dragonTex)
        frame.dragonIcon:Show()
    else
        frame.dragonIcon:Hide()
    end
    
    if not MP.db.showLevel then
        frame.levelText:SetText("")
        MP:UpdateThreatAnchor(frame)
        MP:UpdatePlateWidth(frame)
        return
    end
    
    local level = SafeCall(UnitLevel, unit)
    if IsSecret(level) or not level then
        frame.levelText:SetText("")
        MP:UpdateThreatAnchor(frame)
        MP:UpdatePlateWidth(frame)
        return
    end
    
    local suffix = ""
    if classification == "elite" or classification == "rareelite" then
        suffix = "+"
    elseif classification == "worldboss" then
        suffix = "B"
    end
    
    if level == -1 then
        frame.levelText:SetText("??")
        frame.levelText:SetTextColor(1, 0, 0)
    else
        local color = GetQuestDifficultyColor(level)
        frame.levelText:SetText(tostring(level) .. suffix)
        if color then
            frame.levelText:SetTextColor(color.r, color.g, color.b)
        else
            frame.levelText:SetTextColor(1, 1, 1)
        end
    end
    MP:UpdateThreatAnchor(frame)
    MP:UpdatePlateWidth(frame)
end

-- Update raid target icons
function MP:UpdateRaidIcon(frame)
    local unit = frame.unit
    if not unit then return end
    
    local index
    if SafeCall(UnitIsUnit, unit, "target") then
        index = SafeCall(GetRaidTargetIndex, "target")
    elseif SafeCall(UnitIsUnit, unit, "mouseover") then
        index = SafeCall(GetRaidTargetIndex, "mouseover")
    else
        index = SafeCall(GetRaidTargetIndex, unit)
    end
    
    if not IsSecret(index) and index and index >= 1 and index <= 8 then
        if frame.raidIcon.currentIndex ~= index then
            local left = ((index - 1) % 4) * 0.25
            local right = left + 0.25
            local top = floor((index - 1) / 4) * 0.25
            local bottom = top + 0.25
            
            frame.raidIcon:SetTexCoord(left, right, top, bottom)
            frame.raidIcon.currentIndex = index
        end
        
        -- Adjust position dynamically based on targeting status
        local isTarget = SafeCall(UnitIsUnit, unit, "target")
        local targetOffset = (isTarget and MP.db.targetBrackets) and 22 or 8
        if frame.raidIcon.currentOffset ~= targetOffset then
            frame.raidIcon:ClearAllPoints()
            frame.raidIcon:SetPoint("LEFT", frame.healthBar, "RIGHT", targetOffset, 0)
            frame.raidIcon.currentOffset = targetOffset
        end
        
        if not frame.raidIcon:IsShown() then
            frame.raidIcon:Show()
        end
    else
        if frame.raidIcon:IsShown() then
            frame.raidIcon:Hide()
            frame.raidIcon.currentIndex = nil
        end
    end
end

-- Update target highlights (glow/brackets)
function MP:UpdateTargetHighlight(frame)
    local unit = frame.unit
    if not unit then return end
    
    local isTarget = SafeCall(UnitIsUnit, unit, "target")
    
    if isTarget then
        local gr, gg, gb, ga = MP:GetTargetGlowColor()
        frame.targetGlow:SetBackdropBorderColor(gr, gg, gb, ga)
        frame.leftBracket:SetTextColor(gr, gg, gb)
        frame.rightBracket:SetTextColor(gr, gg, gb)

        if MP.db.targetGlow then
            frame.targetGlow:Show()
        else
            frame.targetGlow:Hide()
        end
        
        if MP.db.targetBrackets then
            local leftOffset = -6
            if frame.dragonIcon and frame.dragonIcon:IsShown() then
                leftOffset = -22
            end
            frame.leftBracket:ClearAllPoints()
            frame.leftBracket:SetPoint("RIGHT", frame.healthBar, "LEFT", leftOffset, 0)
            frame.leftBracket:Show()
            frame.rightBracket:Show()
        else
            frame.leftBracket:Hide()
            frame.rightBracket:Hide()
        end
    else
        frame.targetGlow:Hide()
        frame.leftBracket:Hide()
        frame.rightBracket:Hide()
    end
end

-- Cast bar OnUpdate handler (smooth progress + throttled font rasterization)
local function CastBar_OnUpdate(self, elapsed)
    if self.isSecretTimes then
        local currentTime = GetTime() * 1000
        pcall(self.SetValue, self, currentTime)
        self.timeText:SetText("")
        return
    end
    
    if not self.endTime or IsSecret(self.endTime) then
        self:Hide()
        self:SetScript("OnUpdate", nil)
        return
    end
    
    local currentTime = GetTime() * 1000
    if currentTime >= self.endTime then
        self:Hide()
        self:SetScript("OnUpdate", nil)
        return
    end
    
    local progress = self.channeling and (self.endTime - currentTime) or (currentTime - self.startTime)
    if not IsSecret(progress) then
        self:SetValue(progress / 1000)
    end
    
    -- Throttled font rasterization (20 updates/sec max instead of per-frame churn)
    self.timeThrottle = (self.timeThrottle or 0) - elapsed
    if self.timeThrottle <= 0 then
        self.timeThrottle = 0.05
        local remaining = (self.endTime - currentTime) / 1000
        if not IsSecret(remaining) then
            self.timeText:SetText(format("%.1f", max(0, remaining)))
        else
            self.timeText:SetText("")
        end
    end
end

-- Start cast bar display
function MP:StartCast(frame, unit)
    if not MP.db.showCastBar or not frame or not frame.castBar then
        return
    end
    if not unit then
        frame.castBar:Hide()
        frame.castBar:SetScript("OnUpdate", nil)
        return
    end
    
    local isTarget = SafeCall(UnitIsUnit, unit, "target")
    local checkUnit = isTarget and "target" or unit
    
    local okCast, name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible = pcall(UnitCastingInfo, checkUnit)
    local channeling = false
    
    local hasCast = okCast and (IsSecret(name) or name ~= nil)
    if not hasCast and checkUnit ~= unit then
        okCast, name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible = pcall(UnitCastingInfo, unit)
        hasCast = okCast and (IsSecret(name) or name ~= nil)
    end
    
    if not hasCast then
        local okChan, cName, cText, cTexture, cStartTimeMS, cEndTimeMS, cIsTradeSkill, cNotInterruptible = pcall(UnitChannelInfo, checkUnit)
        local hasChan = okChan and (IsSecret(cName) or cName ~= nil)
        if not hasChan and checkUnit ~= unit then
            okChan, cName, cText, cTexture, cStartTimeMS, cEndTimeMS, cIsTradeSkill, cNotInterruptible = pcall(UnitChannelInfo, unit)
            hasChan = okChan and (IsSecret(cName) or cName ~= nil)
        end
        if hasChan then
            name, text, texture, startTimeMS, endTimeMS, isTradeSkill, notInterruptible = cName, cText, cTexture, cStartTimeMS, cEndTimeMS, cIsTradeSkill, cNotInterruptible
            channeling = true
            hasCast = true
        end
    end
    
    if not hasCast then
        frame.castBar:Hide()
        frame.castBar:SetScript("OnUpdate", nil)
        return
    end
    
    local castBar = frame.castBar
    castBar.channeling = channeling
    
    -- Set spell name text (FontString:SetText natively handles secret strings)
    if IsSecret(name) then
        pcall(castBar.text.SetText, castBar.text, name)
    else
        castBar.text:SetText(name or "")
    end
    
    -- Set spell icon texture
    if not IsSecret(texture) and texture then
        castBar.icon:SetTexture(texture)
    elseif IsSecret(texture) then
        pcall(castBar.icon.SetTexture, castBar.icon, texture)
    end
    
    -- Status bar color for uninterruptible casts
    local isShielded = not IsSecret(notInterruptible) and notInterruptible
    if isShielded then
        castBar:SetStatusBarColor(0.6, 0.6, 0.6) -- Gray for uninterruptible
    else
        castBar:SetStatusBarColor(1, 0.7, 0) -- Gold/Yellow for normal
    end
    
    -- Handle timing & progress animation
    local secretTimes = IsSecret(startTimeMS) or IsSecret(endTimeMS) or not startTimeMS or not endTimeMS
    castBar.isSecretTimes = secretTimes
    
    if not secretTimes and startTimeMS and endTimeMS then
        local duration = (endTimeMS - startTimeMS) / 1000
        if duration > 0 then
            castBar.startTime = startTimeMS
            castBar.endTime = endTimeMS
            castBar.duration = duration
            castBar:SetMinMaxValues(0, duration)
            castBar:SetValue(channeling and duration or 0)
        else
            castBar.startTime = startTimeMS
            castBar.endTime = endTimeMS
            castBar:SetMinMaxValues(0, 1)
            castBar:SetValue(0)
        end
    else
        -- Secret timestamps: pass directly to native C display sinks
        pcall(castBar.SetMinMaxValues, castBar, startTimeMS, endTimeMS)
        pcall(castBar.SetValue, castBar, channeling and endTimeMS or startTimeMS)
    end
    
    castBar:SetScript("OnUpdate", CastBar_OnUpdate)
    castBar:Show()
end

function MP:StopCast(frame)
    if frame and frame.castBar then
        frame.castBar:Hide()
        frame.castBar:SetScript("OnUpdate", nil)
    end
end

-- Static Debuff Icon OnUpdate handler (throttles font rasterization)
local function DebuffIcon_OnUpdate(self, elapsed)
    if IsSecret(self.expirationTime) or not self.expirationTime then
        self.cooldown:SetText("")
        self:SetScript("OnUpdate", nil)
        self.lastSec = nil
        return
    end
    
    local remaining = self.expirationTime - GetTime()
    if remaining <= 0 then
        self.cooldown:SetText("")
        self:SetScript("OnUpdate", nil)
        self.lastSec = nil
        return
    end
    
    local sec = ceil(remaining)
    if sec ~= self.lastSec then
        self.lastSec = sec
        if sec > 60 then
            self.cooldown:SetText(format("%dm", ceil(sec / 60)))
        else
            self.cooldown:SetText(format("%d", sec))
        end
    end
end

-- Ground AoE and Custom Ability tracking (handles non-aura effects like Consecration and custom seals)
MP.activeConsecration = nil
MP.activeTargetSpells = {}

local function DelayCall(delay, callback)
    if C_Timer and C_Timer.After then
        pcall(C_Timer.After, delay, callback)
    else
        local timerFrame = CreateFrame("Frame")
        local total = 0
        timerFrame:SetScript("OnUpdate", function(self, elapsed)
            total = total + elapsed
            if total >= delay then
                self:SetScript("OnUpdate", nil)
                pcall(callback)
            end
        end)
    end
end

-- Resolve target nameplate custom frame directly via C engine and activePlates
function MP:GetTargetPlateFrame()
    if not UnitExists("target") then return nil end
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local np = SafeCall(C_NamePlate.GetNamePlateForUnit, "target")
        if np and np.mpFrame then return np.mpFrame end
    end
    for npUnit, npFrame in pairs(MP.activePlates) do
        if SafeCall(UnitIsUnit, npUnit, "target") then
            return npFrame
        end
    end
    return nil
end

-- Update unit debuffs / auras (all active nameplates, multi-target support)
-- Update unit debuffs / auras (all active nameplates, multi-target support)
function MP:UpdateDebuffs(frame)
    local unit = frame.unit
    if not unit then return end
    
    if not MP.db.showDebuffs then
        if frame.auraContainer then
            frame.auraContainer:SetEnabled(false)
            frame.auraContainer:Hide()
            frame.auraContainer.mpUnit = nil
        end
        if frame.aurasFrame then
            frame.aurasFrame:Hide()
        end
        if frame.auraIcons then
            for i = 1, 5 do
                local iconFrame = frame.auraIcons[i]
                if iconFrame then
                    iconFrame:Hide()
                    iconFrame:SetScript("OnUpdate", nil)
                    iconFrame.lastSec = nil
                end
            end
        end
        return
    end
    
    local targetFrame = MP:GetTargetPlateFrame()
    local isTarget = (frame == targetFrame) or SafeCall(UnitIsUnit, unit, "target")
    
    -- 1. Modern Midnight / Forever C-Engine Native AuraContainer
    if frame.auraContainer then
        if frame.auraContainer.mpUnit ~= unit or not frame.auraContainer:IsEnabled() then
            frame.auraContainer.mpUnit = unit
            frame.auraContainer:SetUnit(unit)
            frame.auraContainer:SetEnabled(true)
            frame.auraContainer:Show()
        elseif frame.auraContainer.UpdateAllAuras then
            frame.auraContainer:UpdateAllAuras()
            frame.auraContainer:Show()
        end
    end
    
    local now = GetTime()
    local customAuras = {}
    
    -- Consecration tracking (ground AoE)
    if MP.activeConsecration and now < MP.activeConsecration.expirationTime then
        local canAttack = SafeCall(UnitCanAttack, "player", unit) or (UnitReaction(unit, "player") and UnitReaction(unit, "player") <= 4) or isTarget
        if canAttack then
            table.insert(customAuras, {
                name = MP.activeConsecration.name or "Consecration",
                icon = MP.activeConsecration.icon or 135926,
                duration = MP.activeConsecration.duration,
                expirationTime = MP.activeConsecration.expirationTime,
                applications = 1,
            })
        end
    end
    
    -- Target Spells (e.g. Seal/Judgement of Fury, /mptest)
    local tSpell = nil
    if isTarget and MP.activeTargetJudgement and now < MP.activeTargetJudgement.expirationTime then
        tSpell = MP.activeTargetJudgement
    end
    if not tSpell then
        local unitGUID = SafeCall(UnitGUID, unit)
        if unitGUID and not IsSecret(unitGUID) and MP.activeTargetSpells then
            tSpell = MP.activeTargetSpells[unitGUID]
        end
    end
    if not tSpell and isTarget and MP.activeTargetSpells then
        local targetGUID = SafeCall(UnitGUID, "target")
        if targetGUID and not IsSecret(targetGUID) then
            tSpell = MP.activeTargetSpells[targetGUID]
        end
    end
    if tSpell and now < tSpell.expirationTime then
        table.insert(customAuras, {
            name = tSpell.name or "Seal of Fury",
            icon = tSpell.icon or 135964,
            duration = tSpell.duration,
            expirationTime = tSpell.expirationTime,
            applications = 1,
        })
    end
    
    -- If native C-Engine AuraContainer is active, frame.aurasFrame ONLY displays custom tracked abilities
    -- If native AuraContainer is not available (classic legacy fallback), it also scans GetUnitAuraList
    local displayAuras = {}
    if frame.auraContainer then
        displayAuras = customAuras
        if frame.aurasFrame then
            frame.aurasFrame:ClearAllPoints()
            local dSize = MP.db.debuffSize or 18
            frame.aurasFrame:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 16 + dSize + 2)
        end
    else
        local auras = GetUnitAuraList(unit)
        if not auras then auras = {} end
        
        for _, ca in ipairs(customAuras) do
            table.insert(displayAuras, ca)
        end
        for _, a in ipairs(auras) do
            local shouldShow = true
            if MP.db.onlyPlayerDebuffs then
                shouldShow = IsAuraFromPlayer(a, unit)
            end
            if shouldShow then
                table.insert(displayAuras, a)
            end
        end
        if frame.aurasFrame then
            frame.aurasFrame:ClearAllPoints()
            frame.aurasFrame:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 16)
        end
    end
    
    local activeDebuffs = 0
    local maxLimit = MP.db.maxDebuffs or 5
    if maxLimit > 5 then maxLimit = 5 end
    
    for _, aura in ipairs(displayAuras) do
        if activeDebuffs >= maxLimit then break end
        
        activeDebuffs = activeDebuffs + 1
        local iconFrame = frame.auraIcons and frame.auraIcons[activeDebuffs]
        if iconFrame then
            local icon = aura.icon or aura.iconFileID
            if not icon and aura.spellId and not IsSecret(aura.spellId) then
                if C_Spell and C_Spell.GetSpellTexture then
                    icon = SafeCall(C_Spell.GetSpellTexture, aura.spellId)
                elseif GetSpellTexture then
                    icon = SafeCall(GetSpellTexture, aura.spellId)
                end
            end
            if not icon and aura.name and not IsSecret(aura.name) then
                if GetSpellTexture then
                    icon = SafeCall(GetSpellTexture, aura.name)
                end
            end
            if not icon then
                icon = 134400
            end
            iconFrame.texture:SetTexture(icon)
            iconFrame.texture:Show()
            if iconFrame.border then iconFrame.border:Show() end
            
            local count = aura.applications
            if count and not IsSecret(count) and type(count) == "number" and count > 1 then
                iconFrame.count:SetText(count)
                iconFrame.count:Show()
            else
                iconFrame.count:SetText("")
            end
            
            local exp = aura.expirationTime
            local dur = aura.duration
            local isSecExp = IsSecret(exp)
            local isSecDur = IsSecret(dur)
            
            if not isSecExp and not isSecDur and exp and dur and exp > 0 and dur > 0 then
                iconFrame.expirationTime = exp
                iconFrame.duration = dur
                iconFrame.lastSec = nil
                DebuffIcon_OnUpdate(iconFrame, 0)
                iconFrame:SetScript("OnUpdate", DebuffIcon_OnUpdate)
                iconFrame.cooldown:Show()
            else
                iconFrame.cooldown:SetText("")
                iconFrame:SetScript("OnUpdate", nil)
                iconFrame.lastSec = nil
            end
            
            iconFrame:Show()
        end
    end
    
    if activeDebuffs > 0 then
        if frame.aurasFrame then frame.aurasFrame:Show() end
    else
        if frame.aurasFrame then frame.aurasFrame:Hide() end
    end
    
    -- Hide extra icons
    if frame.auraIcons then
        for i = activeDebuffs + 1, 5 do
            local iconFrame = frame.auraIcons[i]
            if iconFrame then
                iconFrame:Hide()
                iconFrame:SetScript("OnUpdate", nil)
                iconFrame.lastSec = nil
            end
        end
    end
    MP:UpdateDoTLethal(frame)
    MP:UpdateHealthColor(frame)
end

-- Setup/Re-apply all visual configurations to existing custom plates
function MP:ApplyAllSettings()
    SetCVar("nameplateMotion", MP.db.stackingPlates and 1 or 0)
    SetCVar("nameplateMaxDistance", MP.db.maxDistance or 41)
    for _, namePlate in ipairs(C_NamePlate.GetNamePlates()) do
        HideBlizzardPlate(namePlate)
        local frame = namePlate.mpFrame
        if frame then
            frame:SetSize(MP.db.width, MP.db.height)
            frame.healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
            frame.healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
            
            -- Bar Texture
            local barTex = MP:GetBarTexture()
            frame.healthBar:SetStatusBarTexture(barTex)
            frame.castBar:SetStatusBarTexture(barTex)
            if frame.dotPredictionBar then
                frame.dotPredictionBar:SetTexture(barTex)
            end
            
            -- Fonts & Anchors
            local fontPath = MP.db.fontPath or "Fonts\\FRIZQT__.TTF"
            local fSizeName = MP.db.fontSizeName or 11
            local fSizeLevel = MP.db.fontSizeLevel or 10
            local fSizeHealth = MP.db.fontSizeHealth or fSizeLevel
            local fSizeDebuff = MP.db.fontSizeDebuff or 11
            
            frame.nameText:SetFont(fontPath, fSizeName, "OUTLINE")
            if frame.lethalSkull then
                local skullSize = math.max(12, fSizeName + 2)
                frame.lethalSkull:SetSize(skullSize, skullSize)
            end
            frame.levelText:SetFont(fontPath, fSizeLevel, "OUTLINE")
            frame.levelText:ClearAllPoints()
            frame.levelText:SetPoint("LEFT", frame.healthBar, "LEFT", 3, 0)
            frame.threatText:SetFont(fontPath, fSizeLevel, "OUTLINE")
            frame.hpText:SetFont(fontPath, fSizeHealth, "OUTLINE")
            frame.hpText:ClearAllPoints()
            frame.hpText:SetPoint("RIGHT", frame.healthBar, "RIGHT", -3, 0)
            MP:UpdateThreatAnchor(frame)
            frame.leftBracket:SetFont(fontPath, 16, "OUTLINE")
            frame.rightBracket:SetFont(fontPath, 16, "OUTLINE")
            frame.castBar.text:SetFont(fontPath, 9, "OUTLINE")
            frame.castBar.timeText:SetFont(fontPath, 9, "OUTLINE")
            for i = 1, 5 do
                if frame.auraIcons[i] then
                    frame.auraIcons[i].count:SetFont(fontPath, fSizeDebuff, "OUTLINE")
                    frame.auraIcons[i].cooldown:SetFont(fontPath, fSizeDebuff, "OUTLINE")
                end
            end
            
            -- Cast bar sizes
            frame.castBar:SetHeight(MP.db.castHeight)
            frame.castBar.icon:SetSize(MP.db.castHeight + 4, MP.db.castHeight + 4)
            
            -- Debuff sizing
            local dSize = MP.db.debuffSize or 28
            if frame.auraContainer then
                frame.auraContainer:SetSize(MP.db.width, dSize)
                local filterStr = MP.db.onlyPlayerDebuffs and "HARMFUL|PLAYER" or "HARMFUL"
                if frame.auraContainer.SetAuraGroupFilterString then
                    pcall(frame.auraContainer.SetAuraGroupFilterString, frame.auraContainer, "debuffs", filterStr)
                end
                if frame.auraContainer.SetAuraGroupMaxFrameCount then
                    pcall(frame.auraContainer.SetAuraGroupMaxFrameCount, frame.auraContainer, "debuffs", MP.db.maxDebuffs or 5)
                end
                local layout = {
                    elementSpacing = 2,
                    lineSpacing = 2,
                    elementWidth = dSize,
                    elementHeight = dSize,
                    maximumLineSize = (MP.db.width or 120) + 100,
                }
                if frame.auraContainer.SetAuraGroupLayout then
                    pcall(frame.auraContainer.SetAuraGroupLayout, frame.auraContainer, "debuffs", layout)
                end
                if frame.auraContainer.auraButtons then
                    for _, btn in ipairs(frame.auraContainer.auraButtons) do
                        btn:SetSize(dSize, dSize)
                        if btn.Border then btn.Border:SetSize(dSize, dSize) end
                        if btn.Count then btn.Count:SetFont(fontPath, fSizeDebuff, "OUTLINE") end
                        if btn.TimerText then btn.TimerText:SetFont(fontPath, fSizeDebuff, "OUTLINE") end
                    end
                end
            end
            frame.aurasFrame:SetSize(MP.db.width, dSize)
            frame.aurasFrame:ClearAllPoints()
            if frame.auraContainer then
                frame.aurasFrame:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 16 + dSize + 2)
            else
                frame.aurasFrame:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 16)
            end
            for i = 1, 5 do
                if frame.auraIcons[i] then
                    frame.auraIcons[i]:SetSize(dSize, dSize)
                    if frame.auraIcons[i].count then frame.auraIcons[i].count:SetFont(fontPath, fSizeDebuff, "OUTLINE") end
                    if frame.auraIcons[i].cooldown then frame.auraIcons[i].cooldown:SetFont(fontPath, fSizeDebuff, "OUTLINE") end
                    if i > 1 then
                        frame.auraIcons[i]:ClearAllPoints()
                        frame.auraIcons[i]:SetPoint("LEFT", frame.auraIcons[i-1], "RIGHT", 2, 0)
                    end
                end
            end
            
            -- Target Glow size, thickness, and color
            local offset = 1 + MP.db.glowThickness
            frame.targetGlow:ClearAllPoints()
            frame.targetGlow:SetPoint("TOPLEFT", frame, "TOPLEFT", -offset, offset)
            frame.targetGlow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offset, -offset)
            frame.targetGlow:SetBackdrop({
                edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeSize = MP.db.glowThickness,
            })
            local gr, gg, gb, ga = MP:GetTargetGlowColor()
            frame.targetGlow:SetBackdropBorderColor(gr, gg, gb, ga)
            frame.leftBracket:SetTextColor(gr, gg, gb)
            frame.rightBracket:SetTextColor(gr, gg, gb)
            
            MP:UpdateAll(frame)
        end
    end
end

-- Update all aspects of a custom frame
function MP:UpdateAll(frame)
    MP:UpdateHealth(frame)
    MP:UpdateName(frame)
    MP:UpdateLevel(frame)
    MP:UpdateTargetHighlight(frame)
    MP:UpdateRaidIcon(frame)
    MP:StartCast(frame, frame.unit)
    MP:UpdateDebuffs(frame)
    MP:UpdateDoTLethal(frame)
    MP:UpdatePlateWidth(frame)
end

-- Create the custom frame structure attached to default nameplates
local function CreateCustomPlate(namePlate)
    if namePlate.SetClipsChildren then
        pcall(namePlate.SetClipsChildren, namePlate, false)
    end
    
    local frame = CreateFrame("Frame", nil, namePlate)
    if frame.SetClipsChildren then
        pcall(frame.SetClipsChildren, frame, false)
    end
    frame:SetSize(MP.db.width, MP.db.height)
    frame:SetPoint("CENTER", namePlate, "CENTER", 0, 0)
    frame:SetFrameLevel(namePlate:GetFrameLevel() + 20)
    frame:EnableMouse(false)
    namePlate.mpFrame = frame
    
    local fontPath = MP.db.fontPath or "Fonts\\FRIZQT__.TTF"
    
    -- Health Bar Background
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bg:SetVertexColor(0, 0, 0, 0.75)
    bg:SetAllPoints(frame)
    frame.bg = bg
    
    -- Health Bar statusbar
    local health = CreateFrame("StatusBar", nil, frame)
    health:SetStatusBarTexture(MP:GetBarTexture())
    health:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    health:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    health:SetFrameLevel(frame:GetFrameLevel() + 1)
    frame.healthBar = health
    
    -- DoT Damage Prediction Overlay Bar (Ghost bar on the health bar)
    local dotBar = health:CreateTexture(nil, "ARTWORK", nil, 2)
    dotBar:SetTexture(MP:GetBarTexture())
    dotBar:SetVertexColor(0.85, 0.25, 0.95, 0.5)
    dotBar:Hide()
    frame.dotPredictionBar = dotBar
    
    local fSizeLevel = MP.db.fontSizeLevel or 10
    local fSizeHealth = MP.db.fontSizeHealth or fSizeLevel

    -- Name Text (Centered above)
    local nameText = frame:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(fontPath, MP.db.fontSizeName or 11, "OUTLINE")
    nameText:SetPoint("BOTTOM", health, "TOP", 0, 4)
    nameText:SetTextColor(1, 1, 1)
    frame.nameText = nameText
    
    -- Lethal DoT Skull Marker (Raid skull icon next to unit name)
    local lethalSkull = frame:CreateTexture(nil, "OVERLAY")
    local skullSize = math.max(12, (MP.db.fontSizeName or 11) + 2)
    lethalSkull:SetSize(skullSize, skullSize)
    lethalSkull:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    lethalSkull:SetTexCoord(0.75, 1.0, 0.25, 0.5)
    lethalSkull:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
    lethalSkull:Hide()
    frame.lethalSkull = lethalSkull
    
    -- Level Text (Left inside health bar)
    local levelText = health:CreateFontString(nil, "OVERLAY")
    levelText:SetFont(fontPath, fSizeLevel, "OUTLINE")
    levelText:SetPoint("LEFT", health, "LEFT", 3, 0)
    levelText:SetJustifyH("LEFT")
    frame.levelText = levelText
    
    -- Health value text (Right inside health bar)
    local hpText = health:CreateFontString(nil, "OVERLAY")
    hpText:SetFont(fontPath, fSizeHealth, "OUTLINE")
    hpText:SetPoint("RIGHT", health, "RIGHT", -3, 0)
    hpText:SetJustifyH("RIGHT")
    frame.hpText = hpText
    
    -- Threat Text (Centered between Level and Health)
    local threatText = health:CreateFontString(nil, "OVERLAY")
    threatText:SetFont(fontPath, fSizeLevel, "OUTLINE")
    threatText:SetJustifyH("CENTER")
    threatText:SetWordWrap(false)
    frame.threatText = threatText
    MP:UpdateThreatAnchor(frame)
    
    -- Elite / Rare Dragon decoration on the left
    local dragon = health:CreateTexture(nil, "OVERLAY", nil, 7)
    dragon:SetSize(40, 40)
    dragon:SetPoint("CENTER", health, "LEFT", -2, 0)
    dragon:SetTexCoord(1, 0, 0, 1) -- Face dragon right towards the bar
    dragon:Hide()
    frame.dragonIcon = dragon
    
    -- Raid Target Icon
    local raidIcon = health:CreateTexture(nil, "OVERLAY")
    raidIcon:SetSize(20, 20)
    raidIcon:SetPoint("LEFT", health, "RIGHT", 8, 0)
    raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    raidIcon:Hide()
    frame.raidIcon = raidIcon
    
    local gr, gg, gb, ga = MP:GetTargetGlowColor()

    -- Target Glow border
    local glow = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    local offset = 1 + MP.db.glowThickness
    glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -offset, offset)
    glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offset, -offset)
    glow:SetBackdrop({
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = MP.db.glowThickness,
    })
    glow:SetBackdropBorderColor(gr, gg, gb, ga)
    glow:Hide()
    frame.targetGlow = glow
    
    -- Target bracket FontStrings (sleek » and « target markers)
    local leftBracket = frame:CreateFontString(nil, "OVERLAY")
    leftBracket:SetFont(fontPath, 16, "OUTLINE")
    leftBracket:SetText("»")
    leftBracket:SetPoint("RIGHT", health, "LEFT", -6, 0)
    leftBracket:SetTextColor(gr, gg, gb)
    leftBracket:Hide()
    frame.leftBracket = leftBracket

    local rightBracket = frame:CreateFontString(nil, "OVERLAY")
    rightBracket:SetFont(fontPath, 16, "OUTLINE")
    rightBracket:SetText("«")
    rightBracket:SetPoint("LEFT", health, "RIGHT", 6, 0)
    rightBracket:SetTextColor(gr, gg, gb)
    rightBracket:Hide()
    frame.rightBracket = rightBracket
    
    -- Cast Bar
    local cast = CreateFrame("StatusBar", nil, frame)
    cast:SetStatusBarTexture(MP:GetBarTexture())
    cast:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -4)
    cast:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -4)
    cast:SetHeight(MP.db.castHeight)
    cast:SetFrameLevel(frame:GetFrameLevel() + 2)
    cast:Hide()
    frame.castBar = cast

    local castBG = cast:CreateTexture(nil, "BACKGROUND")
    castBG:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    castBG:SetVertexColor(0, 0, 0, 0.75)
    castBG:SetAllPoints(cast)
    cast.bg = castBG

    local castIcon = cast:CreateTexture(nil, "OVERLAY")
    castIcon:SetSize(MP.db.castHeight + 4, MP.db.castHeight + 4)
    castIcon:SetPoint("RIGHT", cast, "LEFT", -4, 0)
    cast.icon = castIcon

    local castText = cast:CreateFontString(nil, "OVERLAY")
    castText:SetFont(fontPath, 9, "OUTLINE")
    castText:SetPoint("LEFT", cast, "LEFT", 3, 0)
    castText:SetTextColor(1, 1, 1)
    cast.text = castText

    local castTime = cast:CreateFontString(nil, "OVERLAY")
    castTime:SetFont(fontPath, 9, "OUTLINE")
    castTime:SetPoint("RIGHT", cast, "RIGHT", -3, 0)
    castTime:SetTextColor(1, 1, 1)
    cast.timeText = castTime
    
    -- Modern Midnight / Forever C-Engine AuraContainer (bypasses Lua taint & secret value restrictions)
    if HasAuraContainerSupport() then
        local ok, container = pcall(function()
            local cName = "MyPlatesAuraContainer" .. tostring(frame:GetName() or "") .. tostring(math.random(1000, 9999))
            local c = CreateFrame("AuraContainer", cName, frame, "CustomAuraContainerTemplate")
            c.auraButtons = {}
            local dSize = MP.db.debuffSize or 28
            c:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 16)
            c:SetSize(MP.db.width or 120, dSize)
            c:SetFrameStrata(frame:GetFrameStrata())
            c:SetFrameLevel(frame:GetFrameLevel() + 25)
            if c.SetClipsChildren then
                pcall(c.SetClipsChildren, c, false)
            end
            
            local layout = {
                elementSpacing = 2,
                lineSpacing = 2,
                elementWidth = dSize,
                elementHeight = dSize,
                maximumLineSize = (MP.db.width or 120) + 100,
            }
            
            local sortMethod = 0
            if _G.AuraContainerSortMethod then
                sortMethod = _G.AuraContainerSortMethod.Expiration or _G.AuraContainerSortMethod.Default or 0
            elseif Enum and Enum.AuraContainerSortMethod then
                sortMethod = Enum.AuraContainerSortMethod.Expiration or 0
            end
            
            local sortDir = 0
            if _G.AuraContainerSortDirection then
                sortDir = _G.AuraContainerSortDirection.Normal or 0
            elseif Enum and Enum.AuraContainerSortDirection then
                sortDir = Enum.AuraContainerSortDirection.Normal or 0
            end
            
            local groupOptions = {
                maxFrameCount = MP.db.maxDebuffs or 5,
                sortMethod = sortMethod,
                sortDirection = sortDir,
                layout = layout,
                initializeFrame = function(button)
                    table.insert(c.auraButtons, button)
                    local s = MP.db.debuffSize or 28
                    button:SetSize(s, s)
                    button:EnableMouse(false)
                    if button.EnableMouseMotion then button:EnableMouseMotion(false) end
                    
                    if not button.Icon then
                        local icon = button:CreateTexture(nil, "ARTWORK")
                        icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
                        icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
                        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        button.Icon = icon
                        if button.SetIcon then button:SetIcon(icon) end
                    end
                    
                    if not button.Border then
                        local border = button:CreateTexture(nil, "BACKGROUND")
                        border:SetAllPoints(button)
                        border:SetColorTexture(0, 0, 0, 1)
                        button.Border = border
                    end
                    
                    if not button.Cooldown then
                        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
                        cd:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
                        cd:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
                        cd:EnableMouse(false)
                        if cd.EnableMouseMotion then cd:EnableMouseMotion(false) end
                        cd:SetHideCountdownNumbers(true)
                        cd:SetDrawBling(false)
                        cd:SetDrawSwipe(true)
                        button.Cooldown = cd
                        if button.SetDurationCooldown then button:SetDurationCooldown(cd) end
                    end
                    
                    local fSize = MP.db.fontSizeDebuff or 11
                    if not button.CountFrame then
                        local cf = CreateFrame("Frame", nil, button)
                        cf:SetAllPoints(button)
                        cf:EnableMouse(false)
                        if cf.EnableMouseMotion then cf:EnableMouseMotion(false) end
                        local count = cf:CreateFontString(nil, "OVERLAY")
                        count:SetFont(fontPath, fSize, "OUTLINE")
                        count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -1)
                        count:SetTextColor(1, 1, 1)
                        button.CountFrame = cf
                        button.Count = count
                        if button.SetApplicationCount then button:SetApplicationCount(count) end
                    end
                    
                    if not button.TimerText then
                        local timer = button:CreateFontString(nil, "OVERLAY")
                        timer:SetFont(fontPath, fSize, "OUTLINE")
                        timer:SetPoint("CENTER", button, "CENTER", 0, 0)
                        timer:SetTextColor(1, 1, 0)
                        button.TimerText = timer
                        local hasDuration = false
                        if button.SetDurationText then
                            local okDur = pcall(button.SetDurationText, button, timer, {})
                            if okDur then hasDuration = true end
                        end
                        if not hasDuration and button.Cooldown then
                            button.Cooldown:SetHideCountdownNumbers(false)
                        end
                    end
                end,
            }
            
            local filterStr = MP.db.onlyPlayerDebuffs and "HARMFUL|PLAYER" or "HARMFUL"
            c:AddAuraGroup("debuffs", filterStr, groupOptions)
            if c.SetAuraGroupLayout then
                pcall(c.SetAuraGroupLayout, c, "debuffs", layout)
            end
            if c.SetFlowLayoutAnchorPoint then
                pcall(c.SetFlowLayoutAnchorPoint, c, "BOTTOMLEFT")
            end
            local hDir = (AnchorUtil and AnchorUtil.FlowDirection and AnchorUtil.FlowDirection.Right) or 0
            local vDir = (AnchorUtil and AnchorUtil.FlowDirection and AnchorUtil.FlowDirection.Up) or 1
            if c.SetFlowLayoutGrowthDirection then
                pcall(c.SetFlowLayoutGrowthDirection, c, hDir, vDir)
            end
            if c.SetFlowLayoutMaximumLineSize then
                pcall(c.SetFlowLayoutMaximumLineSize, c, (MP.db.width or 120) + 60)
            end
            
            c:SetEnabled(false)
            c:Hide()
            return c
        end)
        if ok and container then
            frame.auraContainer = container
        end
    end
    
    -- Auras Frame (custom tracked abilities / classic fallback)
    local auras = CreateFrame("Frame", nil, frame)
    local dSize = MP.db.debuffSize or 18
    if frame.auraContainer then
        auras:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 16 + dSize + 2)
    else
        auras:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 16)
    end
    auras:SetSize(MP.db.width, MP.db.debuffSize or 20)
    auras:SetFrameStrata(frame:GetFrameStrata())
    auras:SetFrameLevel(frame:GetFrameLevel() + 25)
    if auras.SetClipsChildren then
        pcall(auras.SetClipsChildren, auras, false)
    end
    frame.aurasFrame = auras
    
    frame.auraIcons = {}
    for i = 1, 5 do
        local iconFrame = CreateFrame("Frame", nil, auras)
        iconFrame:SetSize(MP.db.debuffSize or 20, MP.db.debuffSize or 20)
        iconFrame:SetFrameStrata(auras:GetFrameStrata())
        iconFrame:SetFrameLevel(auras:GetFrameLevel() + i)
        if iconFrame.SetClipsChildren then
            pcall(iconFrame.SetClipsChildren, iconFrame, false)
        end
        if i == 1 then
            iconFrame:SetPoint("BOTTOMLEFT", auras, "BOTTOMLEFT", 0, 0)
        else
            iconFrame:SetPoint("LEFT", frame.auraIcons[i-1], "RIGHT", 2, 0)
        end
        
        -- Black 1px border background behind texture
        local border = iconFrame:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints(iconFrame)
        border:SetColorTexture(0, 0, 0, 1)
        iconFrame.border = border

        local texture = iconFrame:CreateTexture(nil, "ARTWORK")
        texture:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
        texture:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        iconFrame.texture = texture

        local fSizeDebuff = MP.db.fontSizeDebuff or 11
        local count = iconFrame:CreateFontString(nil, "OVERLAY")
        count:SetFont(fontPath, fSizeDebuff, "OUTLINE")
        count:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 1, -1)
        count:SetTextColor(1, 1, 1)
        iconFrame.count = count

        local cooldown = iconFrame:CreateFontString(nil, "OVERLAY")
        cooldown:SetFont(fontPath, fSizeDebuff, "OUTLINE")
        cooldown:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
        cooldown:SetTextColor(1, 1, 0)
        iconFrame.cooldown = cooldown

        iconFrame:Hide()
        frame.auraIcons[i] = iconFrame
    end
end

-- Global Event Frame
local f = CreateFrame("Frame")
local function SafeRegister(event)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" and (IS_MIDNIGHT_ENGINE or _G.issecretvalue ~= nil) then
        return
    end
    pcall(f.RegisterEvent, f, event)
end

SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_LOGIN")
SafeRegister("PLAYER_ENTERING_WORLD")
SafeRegister("SPELLS_CHANGED")
SafeRegister("NAME_PLATE_UNIT_ADDED")
SafeRegister("NAME_PLATE_UNIT_REMOVED")
SafeRegister("PLAYER_TARGET_CHANGED")
SafeRegister("RAID_TARGET_UPDATE")
SafeRegister("UNIT_HEALTH")
SafeRegister("UNIT_MAXHEALTH")
SafeRegister("UNIT_NAME_UPDATE")
SafeRegister("UNIT_THREAT_LIST_UPDATE")
SafeRegister("UNIT_THREAT_SITUATION_UPDATE")
SafeRegister("UNIT_AURA")
SafeRegister("UNIT_SPELLCAST_START")
SafeRegister("UNIT_SPELLCAST_STOP")
SafeRegister("UNIT_SPELLCAST_FAILED")
SafeRegister("UNIT_SPELLCAST_INTERRUPTED")
SafeRegister("UNIT_SPELLCAST_DELAYED")
SafeRegister("UNIT_SPELLCAST_CHANNEL_START")
SafeRegister("UNIT_SPELLCAST_CHANNEL_UPDATE")
SafeRegister("UNIT_SPELLCAST_CHANNEL_STOP")
SafeRegister("UNIT_SPELLCAST_SUCCEEDED")
SafeRegister("DISPLAY_SIZE_CHANGED")
SafeRegister("UI_SCALE_CHANGED")
if not IS_MIDNIGHT_ENGINE and not _G.issecretvalue then
    SafeRegister("COMBAT_LOG_EVENT_UNFILTERED")
end

-- Multi-client safe spell name and texture resolvers
local function ResolveSpellNameAndID(...)
    local name, id
    -- Step 1: Find spellID number
    for i = 1, select("#", ...) do
        local val = select(i, ...)
        if type(val) == "number" and val > 0 then
            id = val
            break
        end
    end
    -- Step 2: Resolve name from spellID
    if id then
        if C_Spell and C_Spell.GetSpellName then
            local ok, n = pcall(C_Spell.GetSpellName, id)
            if ok and n and type(n) == "string" and n ~= "" then name = n end
        end
        if not name and C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, id)
            if ok and type(info) == "table" and info.name and info.name ~= "" then name = info.name end
        end
        if not name and GetSpellInfo then
            local ok, n = pcall(GetSpellInfo, id)
            if ok and type(n) == "string" and n ~= "" then name = n end
        end
    end
    -- Step 3: If no name found from ID, search string arguments for non-GUID names
    if not name then
        for i = 1, select("#", ...) do
            local val = select(i, ...)
            if type(val) == "string" and val ~= "player" and val ~= "pet" and val ~= "target" and val ~= "" and not string.find(val, "Cast%-") and not string.find(val, "Player%-") and not string.find(val, "0x") then
                name = val
                break
            end
        end
    end
    return name, id
end

local function GetSpellTextureSafe(spellID, spellName)
    if spellID and type(spellID) == "number" then
        if C_Spell and C_Spell.GetSpellTexture then
            local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
            if ok and tex then return tex end
        end
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
            if ok and type(info) == "table" and (info.iconID or info.originalIconID) then
                return info.iconID or info.originalIconID
            end
        end
        if GetSpellTexture then
            local ok, tex = pcall(GetSpellTexture, spellID)
            if ok and tex then return tex end
        end
    end
    if spellName and GetSpellTexture then
        local ok, tex = pcall(GetSpellTexture, spellName)
        if ok and tex then return tex end
    end
    return nil
end

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local arg1 = ...
        if arg1 == addonName then
            InitDB()
            CachePlayerSpells()
        end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        MP.playerGUID = UnitGUID("player")
        CachePlayerSpells()
        -- Apply baseline CVars for nameplate stacking and scaling consistency
        SetCVar("nameplateShowAll", 1)
        SetCVar("nameplateSelectedScale", 1.0)
        SetCVar("nameplateMinScale", 1.0)
        SetCVar("nameplateMaxScale", 1.0)
        SetCVar("nameplateMotion", MP.db.stackingPlates and 1 or 0)
        SetCVar("nameplateOverlapV", 1.4)
        SetCVar("nameplateOverlapH", 0.8)
        SetCVar("nameplateMaxDistance", MP.db.maxDistance or 41)
        
        -- Hook any plates already visible at logon
        for _, namePlate in ipairs(C_NamePlate.GetNamePlates()) do
            HideBlizzardPlate(namePlate)
            local unit = namePlate.namePlateUnitToken or (namePlate.UnitFrame and namePlate.UnitFrame.unit) or (namePlate.GetUnit and namePlate:GetUnit())
            if unit then
                f:GetScript("OnEvent")(f, "NAME_PLATE_UNIT_ADDED", unit)
            end
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        local namePlate = C_NamePlate.GetNamePlateForUnit(unit)
        if namePlate and not namePlate:IsForbidden() then
            HideBlizzardPlate(namePlate)
            
            -- Setup our custom frame overlays
            if not namePlate.mpFrame then
                CreateCustomPlate(namePlate)
            end
            
            local frame = namePlate.mpFrame
            frame.unit = unit
            MP.activePlates[unit] = frame
            frame:Show()
            MP:UpdateAll(frame)
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        local frame = MP.activePlates[unit]
        if frame then
            frame:Hide()
            MP:StopCast(frame)
            if frame.auraContainer then
                frame.auraContainer:SetEnabled(false)
                frame.auraContainer:Hide()
                frame.auraContainer.mpUnit = nil
            end
            if frame.aurasFrame then
                frame.aurasFrame:Hide()
            end
            if frame.auraIcons then
                for i = 1, 5 do
                    local icon = frame.auraIcons[i]
                    if icon then
                        icon:Hide()
                        icon:SetScript("OnUpdate", nil)
                        icon.lastSec = nil
                    end
                end
            end
            frame.unit = nil
            MP.activePlates[unit] = nil
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if not UnitExists("target") then
            MP.activeTargetJudgement = nil
        end
        for _, frame in pairs(MP.activePlates) do
            MP:UpdateTargetHighlight(frame)
            MP:UpdateRaidIcon(frame)
            MP:UpdateHealth(frame)
            MP:UpdateThreat(frame)
            MP:UpdateDebuffs(frame)
            if frame.unit and SafeCall(UnitIsUnit, frame.unit, "target") then
                MP:StartCast(frame, frame.unit)
            else
                MP:StopCast(frame)
            end
        end
    elseif event == "RAID_TARGET_UPDATE" then
        for _, frame in pairs(MP.activePlates) do
            MP:UpdateRaidIcon(frame)
        end
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        local unit = ...
        local frame = MP.activePlates[unit]
        if frame then
            MP:UpdateHealth(frame)
        elseif unit == "target" then
            for npUnit, npFrame in pairs(MP.activePlates) do
                if SafeCall(UnitIsUnit, npUnit, "target") then
                    MP:UpdateHealth(npFrame)
                end
            end
        end
    elseif event == "UNIT_NAME_UPDATE" then
        local unit = ...
        local frame = MP.activePlates[unit]
        if frame then
            MP:UpdateName(frame)
        end
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        local unit = ...
        if unit and MP.activePlates[unit] then
            MP:UpdateThreat(MP.activePlates[unit])
        else
            for _, frame in pairs(MP.activePlates) do
                MP:UpdateThreat(frame)
            end
        end
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit and MP.activePlates[unit] then
            MP:UpdateDebuffs(MP.activePlates[unit])
        elseif unit == "target" then
            for npUnit, npFrame in pairs(MP.activePlates) do
                if SafeCall(UnitIsUnit, npUnit, "target") then
                    MP:UpdateDebuffs(npFrame)
                end
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit = ...
        if unit == "player" or unit == "pet" then
            local spellName, actualSpellID = ResolveSpellNameAndID(...)
            local now = GetTime()
            if spellName then
                local lower = strlower(spellName)
                if string.find(lower, "consecrat") then
                    local tex = GetSpellTextureSafe(actualSpellID, spellName) or 135926
                    MP.activeConsecration = {
                        name = spellName,
                        icon = tex,
                        duration = 8,
                        expirationTime = now + 8,
                    }
                    DelayCall(8.1, function()
                        if MP.activeConsecration and GetTime() >= MP.activeConsecration.expirationTime then
                            MP.activeConsecration = nil
                            for _, npFrame in pairs(MP.activePlates) do
                                MP:UpdateDebuffs(npFrame)
                            end
                        end
                    end)
                elseif string.find(lower, "fury") or string.find(lower, "judg") or string.find(lower, "seal") or string.find(lower, "taunt") then
                    local tex = GetSpellTextureSafe(actualSpellID, spellName) or 135964
                    local dur = 10
                    MP.activeTargetJudgement = {
                        name = spellName,
                        icon = tex,
                        duration = dur,
                        expirationTime = now + dur,
                    }
                    DelayCall(dur + 0.1, function()
                        if MP.activeTargetJudgement and GetTime() >= MP.activeTargetJudgement.expirationTime then
                            MP.activeTargetJudgement = nil
                            for _, npFrame in pairs(MP.activePlates) do
                                MP:UpdateDebuffs(npFrame)
                            end
                        end
                    end)
                    if UnitExists("target") then
                        local tGUID = SafeCall(UnitGUID, "target")
                        if tGUID and not IsSecret(tGUID) then
                            MP.activeTargetSpells[tGUID] = {
                                name = spellName,
                                icon = tex,
                                duration = dur,
                                expirationTime = now + dur,
                            }
                            DelayCall(dur + 0.1, function()
                                if MP.activeTargetSpells and MP.activeTargetSpells[tGUID] and GetTime() >= MP.activeTargetSpells[tGUID].expirationTime then
                                    MP.activeTargetSpells[tGUID] = nil
                                    for _, npFrame in pairs(MP.activePlates) do
                                        MP:UpdateDebuffs(npFrame)
                                    end
                                end
                            end)
                        end
                    end
                end
            end
            
            for npUnit, npFrame in pairs(MP.activePlates) do
                MP:UpdateDebuffs(npFrame)
            end
        end
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        local unit = ...
        if unit then
            local frame = MP.activePlates[unit]
            if frame then
                MP:StartCast(frame, unit)
            elseif unit == "target" then
                for npUnit, npFrame in pairs(MP.activePlates) do
                    if SafeCall(UnitIsUnit, npUnit, "target") then
                        MP:StartCast(npFrame, "target")
                    end
                end
            end
        end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local unit = ...
        if unit then
            local frame = MP.activePlates[unit]
            if frame then
                MP:StopCast(frame)
            elseif unit == "target" then
                for npUnit, npFrame in pairs(MP.activePlates) do
                    if SafeCall(UnitIsUnit, npUnit, "target") then
                        MP:StopCast(npFrame)
                    end
                end
            end
        end
    elseif event == "SPELLS_CHANGED" then
        CachePlayerSpells()
        for _, frame in pairs(MP.activePlates) do
            MP:UpdateDebuffs(frame)
        end
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        for _, namePlate in ipairs(C_NamePlate.GetNamePlates()) do
            HideBlizzardPlate(namePlate)
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID
        if CombatLogGetCurrentEventInfo then
            timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID = CombatLogGetCurrentEventInfo()
        else
            timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID = ...
        end
        
        if eventType == "SPELL_PERIODIC_DAMAGE" and sourceGUID then
            local isMyDot = sourceGUID == (MP.playerGUID or UnitGUID("player"))
            local isGroupDot = false
            if not isMyDot and MP.db.includeGroupDots then
                if IsInRaid() then
                    for g = 1, (GetNumGroupMembers() or 0) do
                        if UnitGUID("raid" .. g) == sourceGUID or UnitGUID("raidpet" .. g) == sourceGUID then
                            isGroupDot = true
                            break
                        end
                    end
                elseif IsInGroup() then
                    for g = 1, (GetNumSubgroupMembers() or 0) do
                        if UnitGUID("party" .. g) == sourceGUID or UnitGUID("partypet" .. g) == sourceGUID then
                            isGroupDot = true
                            break
                        end
                    end
                end
            end
            
            if isMyDot or isGroupDot then
                local spellId, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical
                if CombatLogGetCurrentEventInfo then
                    spellId, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical = select(12, CombatLogGetCurrentEventInfo())
                else
                    spellId, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical = select(12, ...)
                end
                
                local tickVal = (amount or 0) + (absorbed or 0)
                if tickVal > 0 then
                    if critical then
                        tickVal = math.floor(tickVal / 2)
                    end
                    if spellName then
                        MP.dotTickCache[spellName] = tickVal
                        if isMyDot and _G.MyPlatesDB then
                            if not _G.MyPlatesDB.dotTickCache then _G.MyPlatesDB.dotTickCache = {} end
                            _G.MyPlatesDB.dotTickCache[spellName] = tickVal
                        end
                    end
                    if spellId then
                        MP.dotTickCache[spellId] = tickVal
                        if isMyDot and _G.MyPlatesDB then
                            if not _G.MyPlatesDB.dotTickCache then _G.MyPlatesDB.dotTickCache = {} end
                            _G.MyPlatesDB.dotTickCache[spellId] = tickVal
                        end
                    end
                
                if destGUID then
                    for unit, plateFrame in pairs(MP.activePlates) do
                        if SafeCall(UnitGUID, unit) == destGUID then
                            MP:UpdateDoTLethal(plateFrame)
                            MP:UpdateHealthColor(plateFrame)
                            break
                        end
                    end
                end
            end
        end
    end
end
end)

-- Periodic ticker for active plates (only ticks when custom non-native spell timers are active or on legacy engine)
local tickerElapsed = 0
f:SetScript("OnUpdate", function(self, elapsed)
    tickerElapsed = tickerElapsed + elapsed
    if tickerElapsed >= 0.25 then
        tickerElapsed = 0
        local hasCustomSpells = (MP.activeConsecration ~= nil) or (MP.activeTargetJudgement ~= nil)
        if hasCustomSpells or not HasAuraContainerSupport() then
            for _, frame in pairs(MP.activePlates) do
                if frame and frame.unit and frame:IsShown() then
                    MP:UpdateDebuffs(frame)
                end
            end
        end
    end
end)

SLASH_MYPLATESDEBUG1 = "/mpdebug"
SlashCmdList["MYPLATESDEBUG"] = function(msg)
    print("|cff00ff00[MyPlates Plater-Engine Debug]|r")
    print(string.format("  Engine: IS_MIDNIGHT_ENGINE=%s (version=%s, build=%s, toc=%s)",
        IS_MIDNIGHT_ENGINE and "|cff00ff00YES|r" or "|cffff0000NO|r",
        tostring(versionStr), tostring(buildNum), tostring(tocNum)))
    print(string.format("  Native AuraContainer Support: %s", HasAuraContainerSupport() and "|cff00ff00YES|r" or "|cffff0000NO|r"))
    local spellCount = 0
    for _ in pairs(playerSpells) do spellCount = spellCount + 1 end
    print(string.format("  Cached Player Spells: %d (Consecration=%s, Fury=%s)",
        spellCount, tostring(playerSpells["consecration"] or playerSpells["consecrate"]),
        tostring(playerSpells["seal of fury"] or playerSpells["judgement of fury"] or playerSpells["fury"])))
    print("  C_UnitAuras.GetUnitAuras:", (C_UnitAuras and C_UnitAuras.GetUnitAuras) and "|cff00ff00YES|r" or "|cffff0000NO|r")
    print("  activeConsecration:", MP.activeConsecration and ("|cff00ff00Active (" .. math.max(0, math.floor(MP.activeConsecration.expirationTime - GetTime())) .. "s)|r") or "None")
    print("  activeTargetJudgement:", MP.activeTargetJudgement and ("|cff00ff00Active (" .. math.max(0, math.floor(MP.activeTargetJudgement.expirationTime - GetTime())) .. "s)|r") or "None")
    print("  Active Registered Plates:", tostring(#C_NamePlate.GetNamePlates()))
    
    if not UnitExists("target") then
        print("|cffff0000[MyPlates Debug]|r No target selected! Target a mob to test.")
        return
    end
    local tName = UnitName("target")
    local tReact = UnitReaction("target", "player")
    local tCombat = UnitAffectingCombat("target")
    print(string.format("|cff00ff00Target:|r %s | Reaction: %s | InCombat: %s | CanAttack: %s",
        tostring(tName), tostring(tReact), tostring(tCombat), tostring(UnitCanAttack("player", "target"))))
    print("|cff00ff00showDebuffs:|r", tostring(MP.db.showDebuffs), "|cff00ff00onlyPlayerDebuffs:|r", tostring(MP.db.onlyPlayerDebuffs))
    
    local targetFrame = MP:GetTargetPlateFrame()
    print("|cff00ff00Target plate registered:|r", targetFrame and "|cff00ff00YES|r" or "|cffff0000NO (Press 'V' to show plates)|r")
    if targetFrame then
        if targetFrame.auraContainer then
            print(string.format("  |cff00ff00Target auraContainer:|r exists=YES, enabled=%s, shown=%s, unit=%s",
                tostring(targetFrame.auraContainer:IsEnabled()),
                tostring(targetFrame.auraContainer:IsShown()),
                tostring(targetFrame.auraContainer.mpUnit)))
        else
            print("  |cffff0000Target auraContainer:|r None (using fallback frame)")
        end
        print("|cff00ff00aurasFrame shown:|r", targetFrame.aurasFrame and targetFrame.aurasFrame:IsShown() and "|cff00ff00YES|r" or "|cffff0000NO|r")
        for i = 1, 5 do
            local icon = targetFrame.auraIcons and targetFrame.auraIcons[i]
            if icon then
                print(string.format("  Icon #%d shown: %s (size: %s, layer: %s)", i, icon:IsShown() and "|cff00ff00YES|r" or "|cffff0000NO|r", tostring(icon:GetWidth()), tostring(icon:GetFrameLevel())))
            end
        end
    end
end

SLASH_MYPLATESTEST1 = "/mptest"
SlashCmdList["MYPLATESTEST"] = function(msg)
    if not UnitExists("target") then
        print("|cffff0000[MyPlates Test]|r Target a mob first, then type /mptest.")
        return
    end
    
    local targetPlate = MP:GetTargetPlateFrame()
    if not targetPlate then
        print("|cffff0000[MyPlates Test]|r Target plate not found on screen! Please press 'V' in-game to toggle enemy nameplates ON and face the target.")
    else
        print("|cff00ff00[MyPlates Test]|r Target nameplate found! Injecting 15s test debuff icon...")
    end
    
    MP.activeTargetJudgement = {
        name = "Test Debuff",
        icon = 135964, -- Paladin Judgement texture
        duration = 15,
        expirationTime = GetTime() + 15,
    }
    
    if targetPlate then
        MP:UpdateDebuffs(targetPlate)
        local aShown = targetPlate.aurasFrame and targetPlate.aurasFrame:IsShown()
        local iShown = targetPlate.auraIcons and targetPlate.auraIcons[1] and targetPlate.auraIcons[1]:IsShown()
        print(string.format("|cff00ff00[MyPlates Test]|r aurasFrame: %s | icon1: %s (size: %s)",
            aShown and "|cff00ff00SHOWN|r" or "|cffff0000HIDDEN|r",
            iShown and "|cff00ff00SHOWN|r" or "|cffff0000HIDDEN|r",
            tostring(MP.db.debuffSize)))
    end
    
    for _, frame in pairs(MP.activePlates) do
        MP:UpdateDebuffs(frame)
    end
end
