-- ============================================================================
-- SGJ Experience Tracker Plugin
-- ============================================================================

local addonName, _ = ...

-- Container API moved to C_Container on newer clients
local GetContainerNumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetContainerItemLink = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink

-- 1. Session State Variables
local sessionStartTime = 0
local sessionStarted = false
local totalXPGainedSession = 0
local lastXP = 0
local lastMaxXP = 1
local lastRested = 0

-- Specific Tracking
local killCount = 0
local killXPTotal = 0
local killBaseXPTotal = 0 -- Kill XP with the rested bonus stripped out

local questCount = 0
local questXPTotal = 0

-- Gear Judge Integration State
local lockedUpgrades = {}   -- Bag upgrades you're too low level to equip
local readyQuests = { count = 0, xp = 0, upgrades = 0, hasXPData = false }
local bandShift = nil       -- Upcoming leveling weight-band change
local gearScore = nil       -- Current character score from the main addon

local function GetMaxLevel()
    if GetMaxPlayerLevel then return GetMaxPlayerLevel() end
    return 60
end

local function IsAtMaxLevel()
    return UnitLevel("player") >= GetMaxLevel()
end

local function GetCharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- Main addon (MSC) is a hard dependency, but it may not have weights until it finishes initializing
local function GetJudgeWeights()
    local MSC = _G.MSC
    if not MSC or not MSC.GetCurrentWeights then return nil end
    local ok, weights, specKey = pcall(MSC.GetCurrentWeights)
    if not ok or not weights then return nil end
    return weights, specKey
end

-- Builds a Lua pattern from a Blizzard format string (e.g. COMBATLOG_XPGAIN_FIRSTPERSON), so parsing works in every locale
local function FormatToPattern(fmt)
    if not fmt or fmt == "" then return nil end
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%%d%%%$s", "(.-)"):gsub("%%%%%d%%%$d", "(%%d+)") -- Positional (%1$s)
    p = p:gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
    return "^" .. p
end

local KILL_PATTERN = FormatToPattern(COMBATLOG_XPGAIN_FIRSTPERSON) or "^(.-) dies, you gain (%d+) experience"
local QUEST_PATTERN = FormatToPattern(ERR_QUEST_REWARD_EXP_I) or "^Experience gained: (%d+)"
local useTurnedInEvent = false

-- Global function to reset the tracker
function SGJ_ResetXPSession()
    sessionStartTime = GetTime()
    totalXPGainedSession = 0
    killCount = 0
    killXPTotal = 0
    killBaseXPTotal = 0
    questCount = 0
    questXPTotal = 0
    print("|cffa335ee[SGJ XP]|r Session Tracker Reset.")
    if SGJ_ExperienceBar then
        SGJ_ExperienceBar:GetScript("OnEvent")(SGJ_ExperienceBar, "PLAYER_XP_UPDATE")
    end
end

-- 2. Create the Main Frame
local SGJ_XP = CreateFrame("Frame", "SGJ_ExperienceBar", UIParent, "BackdropTemplate")
SGJ_XP:SetPoint("BOTTOM", 0, 150)
SGJ_XP:EnableMouse(true)
SGJ_XP:SetMovable(true)
SGJ_XP:RegisterForDrag("LeftButton")

-- Add the actual backdrop so we can control background color/opacity
SGJ_XP:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1
})
SGJ_XP:SetBackdropBorderColor(0, 0, 0, 1)

-- 3. Visuals: Status Bar Setup
SGJ_XP.RestedBar = CreateFrame("StatusBar", nil, SGJ_XP)
SGJ_XP.RestedBar:SetAllPoints()
SGJ_XP.RestedBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
SGJ_XP.RestedBar:GetStatusBarTexture():SetHorizTile(false)
SGJ_XP.RestedBar:SetFrameLevel(SGJ_XP:GetFrameLevel() + 1)

-- Quest turn-in projection: where the bar lands if you hand in every completed quest
SGJ_XP.QuestBar = CreateFrame("StatusBar", nil, SGJ_XP)
SGJ_XP.QuestBar:SetAllPoints()
SGJ_XP.QuestBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
SGJ_XP.QuestBar:GetStatusBarTexture():SetHorizTile(false)
SGJ_XP.QuestBar:SetFrameLevel(SGJ_XP.RestedBar:GetFrameLevel() + 1)

SGJ_XP.Bar = CreateFrame("StatusBar", nil, SGJ_XP)
SGJ_XP.Bar:SetAllPoints()
SGJ_XP.Bar:SetFrameLevel(SGJ_XP.QuestBar:GetFrameLevel() + 1)
SGJ_XP.Bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
SGJ_XP.Bar:GetStatusBarTexture():SetHorizTile(false)

-- 4. Visuals: Text Overlay
SGJ_XP.Text = SGJ_XP.Bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
SGJ_XP.Text:SetPoint("CENTER", SGJ_XP.Bar, "CENTER", 0, 0)
SGJ_XP.Text:SetShadowColor(0, 0, 0, 1)
SGJ_XP.Text:SetShadowOffset(1, -1)

-- 4b. Unlock Marker: icon of the best upgrade that unlocks at the next level
SGJ_XP.Unlock = CreateFrame("Frame", nil, SGJ_XP, "BackdropTemplate")
SGJ_XP.Unlock:SetPoint("LEFT", SGJ_XP, "RIGHT", 4, 0)
SGJ_XP.Unlock:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
SGJ_XP.Unlock:SetBackdropBorderColor(0.1, 1, 0.1, 1)
SGJ_XP.Unlock:EnableMouse(true)
SGJ_XP.Unlock.Icon = SGJ_XP.Unlock:CreateTexture(nil, "ARTWORK")
SGJ_XP.Unlock.Icon:SetPoint("TOPLEFT", 1, -1)
SGJ_XP.Unlock.Icon:SetPoint("BOTTOMRIGHT", -1, 1)
SGJ_XP.Unlock.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
SGJ_XP.Unlock.Arrow = SGJ_XP.Unlock:CreateTexture(nil, "OVERLAY")
SGJ_XP.Unlock.Arrow:SetSize(12, 12)
SGJ_XP.Unlock.Arrow:SetPoint("TOPRIGHT", 3, 3)
SGJ_XP.Unlock.Arrow:SetTexture("Interface\\AddOns\\SharpiesGearJudge\\Textures\\Upgrade.png")
SGJ_XP.Unlock:Hide()

-- 5. Create the Standalone Stats Box
local STATS_BOX_WIDTH = 300
local SGJ_Stats = CreateFrame("Frame", "SGJ_XPStatsBox", UIParent, "BackdropTemplate")
SGJ_Stats:SetSize(STATS_BOX_WIDTH, 215) -- Height follows the number of lines shown
SGJ_Stats:SetPoint("BOTTOMRIGHT", -50, 150)
SGJ_Stats:EnableMouse(true)
SGJ_Stats:SetMovable(true)
SGJ_Stats:RegisterForDrag("LeftButton")

-- Tooltip-style Background
SGJ_Stats:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
SGJ_Stats:SetBackdropColor(0, 0, 0, 0.8)
SGJ_Stats:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

SGJ_Stats.Title = SGJ_Stats:CreateFontString(nil, "OVERLAY", "GameFontNormal")
SGJ_Stats.Title:SetPoint("TOP", 0, -10)
SGJ_Stats.Title:SetText("SGJ Experience")

-- Tooltip-style double-line rows, created as needed (the box shows the same lines as the bar's tooltip)
SGJ_Stats.Lines = {}
local function GetStatsRow(i)
    if not SGJ_Stats.Lines[i] then
        local left = SGJ_Stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        left:SetJustifyH("LEFT")
        left:SetWordWrap(false)

        local right = SGJ_Stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        right:SetJustifyH("RIGHT")
        right:SetWordWrap(false)

        SGJ_Stats.Lines[i] = { left, right }
    end
    return SGJ_Stats.Lines[i][1], SGJ_Stats.Lines[i][2]
end

SGJ_Stats:SetScript("OnDragStart", function(self) if not SGJ_XP_DB.XPBarLocked and not InCombatLockdown() then self:StartMoving() end end)
SGJ_Stats:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    SGJ_XP_DB.StatsBoxPosition = {point, relativePoint, xOfs, yOfs}
end)

-- Shift-Click to Reset (same as the bar)
SGJ_Stats:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" and IsShiftKeyDown() then
        SGJ_ResetXPSession()
    end
end)

-- 6. Level-Up Alert ("Ding!" gear check)
local SGJ_Ding = CreateFrame("Button", "SGJ_XPDingAlert", UIParent, "BackdropTemplate")
SGJ_Ding:SetSize(320, 60)
SGJ_Ding:SetPoint("BOTTOM", SGJ_XP, "TOP", 0, 12)
SGJ_Ding:SetFrameStrata("HIGH")
SGJ_Ding:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
SGJ_Ding:SetBackdropColor(0, 0, 0, 0.9)
SGJ_Ding:SetBackdropBorderColor(1, 0.82, 0, 1)
SGJ_Ding.Title = SGJ_Ding:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
SGJ_Ding.Title:SetPoint("TOP", 0, -10)
SGJ_Ding.Body = SGJ_Ding:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
SGJ_Ding.Body:SetPoint("TOP", SGJ_Ding.Title, "BOTTOM", 0, -6)
SGJ_Ding.Body:SetWidth(300)
SGJ_Ding.Body:SetJustifyH("CENTER")
SGJ_Ding.Hint = SGJ_Ding:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
SGJ_Ding.Hint:SetPoint("BOTTOM", 0, 8)
SGJ_Ding.Hint:SetText("Click to open bags  -  Right-click to dismiss")
SGJ_Ding:RegisterForClicks("LeftButtonUp", "RightButtonUp")
SGJ_Ding:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        if OpenAllBags then OpenAllBags() end
    end
    self:Hide()
end)
SGJ_Ding:Hide()

-- === Milestone Ticks Engine ===
SGJ_XP.TickFrames = {}
local function UpdateTicks()
    if not SGJ_XP then return end

    local width = SGJ_XP:GetWidth()
    local height = SGJ_XP:GetHeight()
    local numSegments = 20 -- Classic WoW uses 20 bubbles/brackets per level
    local step = width / numSegments

    for i = 1, numSegments - 1 do
        if not SGJ_XP.TickFrames[i] then
            local t = SGJ_XP.Bar:CreateTexture(nil, "OVERLAY")
            t:SetWidth(1)
            SGJ_XP.TickFrames[i] = t
        end

        local tick = SGJ_XP.TickFrames[i]
        tick:SetColorTexture(unpack(SGJ_XP_DB.TickColor))
        tick:SetHeight(height)
        tick:ClearAllPoints()
        tick:SetPoint("LEFT", SGJ_XP.Bar, "LEFT", step * i, 0)

        if SGJ_XP_DB and SGJ_XP_DB.ShowTicks then
            tick:Show()
        else
            tick:Hide()
        end
    end

    -- Keep the unlock marker square with the bar
    local size = math.max(12, math.min(28, height))
    SGJ_XP.Unlock:SetSize(size, size)
end

-- Safely opens the WoW Color Picker across different client versions
local function OpenColorPicker(defaultR, defaultG, defaultB, defaultA, callback)
    local function OnColorChanged()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        local a = defaultA

        -- Safely grab Alpha depending on which WoW Engine is running
        if ColorPickerFrame.HasOpacity then
            a = ColorPickerFrame:GetColorAlpha()
        elseif OpacitySliderFrame then
            a = OpacitySliderFrame:GetValue()
        end

        -- Fallback just in case Blizzard returns nil
        if not a then a = 1.0 end

        callback(r, g, b, a)
    end

    local function OnColorCanceled(previousValues)
        local r, g, b, a = unpack(previousValues)
        callback(r, g, b, a)
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        -- Modern Engine (Dragonflight / TBC Anniversary)
        local info = {
            r = defaultR, g = defaultG, b = defaultB, opacity = defaultA,
            hasOpacity = true,
            swatchFunc = OnColorChanged,
            opacityFunc = OnColorChanged,
            cancelFunc = function() OnColorCanceled({defaultR, defaultG, defaultB, defaultA}) end,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        -- Legacy Engine (Fallback)
        ColorPickerFrame.func = OnColorChanged
        ColorPickerFrame.opacityFunc = OnColorChanged
        ColorPickerFrame.cancelFunc = OnColorCanceled
        ColorPickerFrame.previousValues = {defaultR, defaultG, defaultB, defaultA}
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = defaultA
        ColorPickerFrame:SetColorRGB(defaultR, defaultG, defaultB)
        ColorPickerFrame:Show()
    end
end
-- ============================================================================
-- Core Logic Functions
-- ============================================================================

-- Function to handle the default Blizzard Bar safely across client versions
local function UpdateBlizzardBarVisibility()
    if not SGJ_XP_DB then return end

    -- Modern Client Backend (Dragonflight / TBC Anniversary)
    if StatusTrackingBarManager then
        if SGJ_XP_DB.HideBlizzardXP then
            StatusTrackingBarManager:Hide()
        else
            StatusTrackingBarManager:Show()
        end

    -- Older Client Backend (Fallback)
    elseif MainMenuExpBar then
        if SGJ_XP_DB.HideBlizzardXP then
            MainMenuExpBar:UnregisterAllEvents()
            MainMenuExpBar:Hide()
            if ReputationWatchBar then ReputationWatchBar:UnregisterAllEvents(); ReputationWatchBar:Hide() end
            if ExhaustionTick then ExhaustionTick:UnregisterAllEvents(); ExhaustionTick:Hide() end
        else
            MainMenuExpBar:RegisterEvent("PLAYER_ENTERING_WORLD")
            MainMenuExpBar:RegisterEvent("PLAYER_XP_UPDATE")
            MainMenuExpBar:RegisterEvent("PLAYER_LEVEL_UP")
            MainMenuExpBar:RegisterEvent("UPDATE_EXHAUSTION")
            if ReputationWatchBar then ReputationWatchBar:RegisterEvent("UPDATE_FACTION") end
            if ExhaustionTick then
                ExhaustionTick:RegisterEvent("PLAYER_ENTERING_WORLD")
                ExhaustionTick:RegisterEvent("PLAYER_XP_UPDATE")
                ExhaustionTick:RegisterEvent("UPDATE_EXHAUSTION")
                ExhaustionTick:RegisterEvent("PLAYER_LEVEL_UP")
            end
            TextStatusBar_UpdateTextString(MainMenuExpBar)
            MainMenuExpBar_Update()
        end
    end
end

-- Tracks XP math safely across level-ups
local function TrackXPGains()
    local currentXP = UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 1

    if currentXP > lastXP then
        local gained = currentXP - lastXP
        totalXPGainedSession = totalXPGainedSession + gained
    elseif currentXP < lastXP then
        -- The player leveled up: finish the old level using ITS max, not the new one
        local gained = (lastMaxXP - lastXP) + currentXP
        totalXPGainedSession = totalXPGainedSession + gained
    end

    lastXP = currentXP
    lastMaxXP = maxXP
end

-- ============================================================================
-- Gear Judge Integration
-- ============================================================================

-- Runs fn after `delay` seconds, restarting the countdown if called again first
local debounceTimers = {}
local function Debounce(key, delay, fn)
    if debounceTimers[key] then debounceTimers[key]:Cancel() end
    debounceTimers[key] = C_Timer.NewTimer(delay, function()
        debounceTimers[key] = nil
        fn()
    end)
end

-- Armor subclass each class trains at 40 (3 = Mail, 4 = Plate). The main addon's usable check treats
-- level 40 as "trained", so looking ahead from below 40 needs its own check.
local ARMOR_TRAINED_AT_40 = { WARRIOR = 4, PALADIN = 4, SHAMAN = 3, HUNTER = 3 }

-- Returns the score gain if SGJ judges `link` an upgrade, else nil.
-- `assumeUsable` skips the usable check for armor you'll train later.
local function GetUpgradeDelta(link, weights, specKey, assumeUsable)
    local MSC = _G.MSC
    local itemName, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
    if not itemName or not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP" then return nil end
    if not assumeUsable and not MSC.IsItemUsable(link) then return nil end
    local compSlot = MSC.GetComparisonSlot(link, equipLoc, weights, specKey)
    if not compSlot then return nil end
    local newScore, oldScore = MSC:EvaluateUpgrade(link, compSlot, weights, specKey)
    if newScore and oldScore and newScore > (oldScore + 0.1) then
        return newScore - oldScore
    end
    return nil
end

-- Scans bags for upgrades with a level requirement above `fromLevel`.
-- Items you can now equip go in `ready`, the rest in `locked`. Both sorted soonest / biggest first.
local function ScanBagUpgrades(fromLevel)
    local locked, ready = {}, {}
    local weights, specKey = GetJudgeWeights()
    if not weights then return locked, ready end
    local level = UnitLevel("player")
    local _, playerClass = UnitClass("player")
    local trainedArmor = ARMOR_TRAINED_AT_40[playerClass]

    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, _, _, minLevel, _, subTypeName, _, _, icon, _, classID, subClassID = GetItemInfo(link)
                -- Mail/Plate you can't wear until you train it at 40 unlocks at 40, whatever its own requirement
                local needsTraining = trainedArmor and fromLevel < 40 and classID == 4 and subClassID == trainedArmor
                local unlockLevel = minLevel and (needsTraining and math.max(minLevel, 40) or minLevel)
                if unlockLevel and unlockLevel > fromLevel then
                    local ok, delta = pcall(GetUpgradeDelta, link, weights, specKey, needsTraining and level < 40)
                    if ok and delta then
                        local entry = { link = link, icon = icon, minLevel = unlockLevel, delta = delta }
                        if needsTraining then entry.train = subTypeName end
                        table.insert(unlockLevel <= level and ready or locked, entry)
                    end
                end
            end
        end
    end

    local function Sort(a, b)
        if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
        return a.delta > b.delta
    end
    table.sort(locked, Sort)
    table.sort(ready, Sort)
    return locked, ready
end

-- Finds the leveling weight band you're about to move into (within 2 levels) and what changes.
-- Uses the class's raw LevelingWeights, so it's a preview: talents and caps still adjust the final numbers.
local function GetUpcomingBandShift()
    local MSC = _G.MSC
    local cls = MSC and MSC.CurrentClass
    if not cls or not cls.LevelingWeights then return nil end
    local _, specKey = GetJudgeWeights()
    if type(specKey) ~= "string" then return nil end

    local prefix, hi = specKey:match("^(.-)_%d+_(%d+)$")
    if not prefix or not cls.LevelingWeights[specKey] then return nil end
    hi = tonumber(hi)

    local levelsAway = (hi + 1) - UnitLevel("player")
    if levelsAway < 1 or levelsAway > 2 then return nil end

    local nextKey
    for key in pairs(cls.LevelingWeights) do
        local p, lo = key:match("^(.-)_(%d+)_%d+$")
        if p == prefix and tonumber(lo) == hi + 1 then nextKey = key; break end
    end
    if not nextKey then
        -- Some chains change name between bands (Paladin DPS: Leveling_41_51 -> Leveling_Ret_52_59).
        -- Use the profile that starts at the next band without continuing a chain of its own.
        local candidates = {}
        for key in pairs(cls.LevelingWeights) do
            local p, lo = key:match("^(.-)_(%d+)_%d+$")
            if p and tonumber(lo) == hi + 1 then
                local continuesChain = false
                for other in pairs(cls.LevelingWeights) do
                    local op, ohi = other:match("^(.-)_%d+_(%d+)$")
                    if op == p and tonumber(ohi) == hi then continuesChain = true; break end
                end
                if not continuesChain then table.insert(candidates, key) end
            end
        end
        if #candidates == 1 then nextKey = candidates[1] end
    end
    if not nextKey then return nil end

    local cur, nxt = cls.LevelingWeights[specKey], cls.LevelingWeights[nextKey]
    local changes, seen = {}, {}
    local function Compare(stat)
        if seen[stat] then return end
        seen[stat] = true
        local a, b = cur[stat] or 0, nxt[stat] or 0
        if a ~= b then
            table.insert(changes, { stat = stat, from = a, to = b, rel = math.abs(b - a) / math.max(a, b) })
        end
    end
    for stat in pairs(cur) do Compare(stat) end
    for stat in pairs(nxt) do Compare(stat) end
    if #changes == 0 then return nil end -- Some bands are copies of the last; nothing to warn about
    table.sort(changes, function(x, y) return x.rel > y.rel end)

    local pretty = (MSC.PrettyNames and MSC.PrettyNames[nextKey]) or (cls.PrettyNames and cls.PrettyNames[nextKey]) or nextKey
    return { levelsAway = levelsAway, level = hi + 1, name = pretty, changes = changes }
end

local function FormatWeightChange(c)
    local name = _G.MSC.GetCleanStatName(c.stat)
    if c.to == 0 then return name .. ": |cffff5555no longer valued|r" end
    if c.from == 0 then return name .. ": |cff55ff55now valued|r (" .. c.to .. ")" end
    local color = (c.to > c.from) and "|cff55ff55" or "|cffff5555"
    return string.format("%s: %s -> %s%s|r", name, c.from, color, c.to)
end

-- Sums completed quests in the log: XP (when the client exposes it) and rewards SGJ judges as upgrades.
-- Quests under collapsed headers aren't visible to the API, so they're skipped.
local lastQuestScanEnd = 0
local function ScanReadyQuests()
    local result = { count = 0, xp = 0, upgrades = 0, hasXPData = false }
    if not GetNumQuestLogEntries or not GetQuestLogTitle then return result end
    local weights, specKey = GetJudgeWeights()

    local prevSelection = GetQuestLogSelection and GetQuestLogSelection() or 0
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local _, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
        if not isHeader and isComplete == 1 then
            result.count = result.count + 1
            SelectQuestLogEntry(i)

            if GetQuestLogRewardXP then
                local ok, xp = pcall(GetQuestLogRewardXP)
                if ok and xp then
                    result.xp = result.xp + xp
                    result.hasXPData = true
                end
            end

            -- A choice counts once even if several choices are upgrades
            if weights then
                local hasUpgrade = false
                for _, rewardType in ipairs({ "choice", "reward" }) do
                    local num = (rewardType == "choice") and GetNumQuestLogChoices() or GetNumQuestLogRewards()
                    for j = 1, (num or 0) do
                        local link = GetQuestLogItemLink(rewardType, j)
                        if link then
                            local ok, delta = pcall(GetUpgradeDelta, link, weights, specKey)
                            if ok and delta then hasUpgrade = true end
                        end
                    end
                end
                if hasUpgrade then result.upgrades = result.upgrades + 1 end
            end
        end
    end
    SelectQuestLogEntry(prevSelection)
    lastQuestScanEnd = GetTime()
    return result
end

local function RefreshGearScore()
    local MSC = _G.MSC
    local weights, specKey = GetJudgeWeights()
    if not weights or not MSC.GetEquippedGear or not MSC.GetCachedCharacterScore then return end
    local ok, score = pcall(function()
        return MSC:GetCachedCharacterScore(MSC:GetEquippedGear(), weights, specKey)
    end)
    if not ok or not score then return end
    gearScore = score

    -- Per-level log. Re-baselines when the weight profile changes so the delta never compares two scales.
    SGJ_XP_DB.ScoreLog = SGJ_XP_DB.ScoreLog or {}
    local charKey = GetCharKey()
    SGJ_XP_DB.ScoreLog[charKey] = SGJ_XP_DB.ScoreLog[charKey] or {}
    local level = UnitLevel("player")
    local entry = SGJ_XP_DB.ScoreLog[charKey][level]
    if not entry or entry.spec ~= specKey then
        entry = { start = score, spec = specKey }
        SGJ_XP_DB.ScoreLog[charKey][level] = entry
    end
    entry.last = score
end

local function GetGearScoreGainThisLevel()
    local log = SGJ_XP_DB.ScoreLog and SGJ_XP_DB.ScoreLog[GetCharKey()]
    local entry = log and log[UnitLevel("player")]
    if not entry or not entry.last then return 0 end
    return entry.last - entry.start
end

-- Calculates all tracking math so both the tooltip and the Box can use it
local function GetXPData()
    local currentXP = UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 1
    local remainingXP = maxXP - currentXP

    local timePlayed = (GetTime() - sessionStartTime) / 3600
    local xpPerHour = (timePlayed > 0) and (totalXPGainedSession / timePlayed) or 0

    local timeToLevelStr = "Need data..."
    if xpPerHour > 0 then
        local hoursToLevel = remainingXP / xpPerHour
        local h = math.floor(hoursToLevel)
        local m = math.floor((hoursToLevel - h) * 60)
        timeToLevelStr = string.format("%dh %dm", h, m)
    end

    -- Calculate Averages
    local avgKillXP = (killCount > 0) and (killXPTotal / killCount) or 0
    local avgQuestXP = (questCount > 0) and (questXPTotal / questCount) or 0

    local killsToLevel = (avgKillXP > 0) and math.ceil(remainingXP / avgKillXP) or 0
    local questsToLevel = (avgQuestXP > 0) and math.ceil(remainingXP / avgQuestXP) or 0

    return currentXP, maxXP, remainingXP, xpPerHour, timeToLevelStr, avgKillXP, killsToLevel, avgQuestXP, questsToLevel, timePlayed
end

-- Rested XP doubles kill XP until the pool is spent, so it covers 2x its size in earned XP
local function GetRestedPlan(remainingXP)
    local restedXP = GetXPExhaustion() or 0
    if restedXP <= 0 then return nil end
    local coverage = (remainingXP > 0) and math.min(1, (restedXP * 2) / remainingXP) or 0
    local avgBase = (killCount > 0) and (killBaseXPTotal / killCount) or 0
    local kills = (avgBase > 0) and math.ceil(restedXP / avgBase) or nil
    return restedXP, coverage, kills
end

local function FormatQuestLine()
    local maxXP = UnitXPMax("player") or 1
    local noun = (readyQuests.count == 1) and "quest" or "quests"
    if readyQuests.hasXPData then
        return string.format("%d %s = %.0f%% of a level", readyQuests.count, noun, (readyQuests.xp / maxXP) * 100)
    end
    return string.format("%d %s", readyQuests.count, noun)
end

-- Builds the lines shown in both the bar's tooltip and the stats box, so the two always match.
-- Entries: { left, right, lr, lg, lb, rr, rg, rb } for a double line, { text, r, g, b, single = true }, or { blank = true }.
local function BuildInfoLines()
    local lines = {}
    local function Double(left, right, lr, lg, lb, rr, rg, rb)
        table.insert(lines, { left, tostring(right), lr, lg, lb, rr or 1, rg or 1, rb or 1 })
    end
    local function Single(text, r, g, b) table.insert(lines, { text, nil, r, g, b, single = true }) end
    local function Blank() table.insert(lines, { blank = true }) end

    local current, maxXP, remaining, xpPerHour, timeToLevelStr, avgKillXP, killsToLevel, avgQuestXP, questsToLevel, timePlayed = GetXPData()

    Double("Current XP:", string.format("%d / %d", current, maxXP), 1, 1, 1)
    Double("Remaining:", remaining, 1, 1, 1)
    local restedXP, coverage, restedKills = GetRestedPlan(remaining)
    if restedXP then
        Double("Rested XP:", string.format("%d (%.1f%%)", restedXP, (restedXP / maxXP) * 100), 0.2, 0.4, 1.0)
        local plan = string.format("Covers %.0f%% of this level", coverage * 100)
        if restedKills then plan = plan .. string.format(" (~%d kills)", restedKills) end
        Single(plan, 0.6, 0.7, 1.0)
    end
    Blank()

    local h = math.floor(timePlayed)
    local m = math.floor((timePlayed - h) * 60)
    local sec = math.floor(((timePlayed - h) * 3600) % 60)
    Double("Session Time:", string.format("%dh %02dm %02ds", h, m, sec), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    Double("Overall XP / Hour:", string.format("%.0f", xpPerHour), 0.2, 1, 0.2)
    Double("Est. Time to Level:", timeToLevelStr, 0.2, 0.8, 1)
    Blank()

    if killCount > 0 then
        Double(string.format("Kills (%d tracked):", killCount), string.format("~%d to level", killsToLevel), 1, 0.8, 0)
    else
        Double("Kills:", "Need data...", 0.5, 0.5, 0.5)
    end

    if questCount > 0 then
        Double(string.format("Quests (%d tracked):", questCount), string.format("~%d to level", questsToLevel), 1, 0.8, 0)
    else
        Double("Quests:", "Need data...", 0.5, 0.5, 0.5)
    end

    -- Completed quests waiting in the log
    if readyQuests.count > 0 then
        Blank()
        Double("Ready to Turn In:", FormatQuestLine(), 1, 0.82, 0)
        if readyQuests.hasXPData and readyQuests.xp >= remaining then
            Single("Turning these in will level you up!", 0.2, 1, 0.2)
        end
        if readyQuests.upgrades > 0 then
            Single(string.format("%d of them reward%s an upgrade", readyQuests.upgrades, readyQuests.upgrades == 1 and "s" or ""), 0.2, 1, 0.2)
        end
    end

    -- Level-locked upgrades in your bags
    if SGJ_XP_DB.ShowUnlocks and #lockedUpgrades > 0 then
        Blank()
        Single("Upgrades Waiting in Your Bags", 0.2, 1, 0.2)
        for i = 1, math.min(5, #lockedUpgrades) do
            local item = lockedUpgrades[i]
            local right = string.format("Lvl %d  |cff55ff55+%.1f|r", item.minLevel, item.delta)
            if item.train then right = string.format("Train %s at %d  |cff55ff55+%.1f|r", item.train, item.minLevel, item.delta) end
            Double(item.link, right, 1, 1, 1)
        end
        if #lockedUpgrades > 5 then
            Single(string.format("...and %d more", #lockedUpgrades - 5), 0.6, 0.6, 0.6)
        end
    end

    -- Upcoming weight profile change
    if SGJ_XP_DB.ShowBandWarning and bandShift then
        Blank()
        local when = (bandShift.levelsAway == 1) and "next level" or string.format("in %d levels", bandShift.levelsAway)
        Single(string.format("Stat Weights Change at %d (%s)", bandShift.level, when), 1, 0.5, 0)
        Single("Likely profile: " .. bandShift.name, 0.8, 0.8, 0.8)
        for i = 1, math.min(4, #bandShift.changes) do
            Single("  " .. FormatWeightChange(bandShift.changes[i]), 1, 1, 1)
        end
        Single("Items that are close calls now may re-rank.", 0.6, 0.6, 0.6)
    end

    -- Gear score progress
    if gearScore then
        Blank()
        local gain = GetGearScoreGainThisLevel()
        local gainColor = (gain > 0) and "|cff55ff55" or "|cff999999"
        Double("Gear Score:", string.format("%.1f  %s(%+.1f this level)|r", gearScore, gainColor, gain), 0.6, 0.8, 1)
    end

    Blank()
    Single("Shift-click to reset the session", 0.5, 0.5, 0.5)
    return lines
end

-- Updates the Standalone Stats Box
local function UpdateStatsBox()
    if IsAtMaxLevel() or not SGJ_XP_DB.ShowStatsBox then
        SGJ_Stats:Hide()
        return
    else
        SGJ_Stats:Show()
    end

    -- Title Color matches the Normal Bar setting
    local r, g, b = unpack(SGJ_XP_DB.NormalColor or {0.6, 0.2, 0.9})
    SGJ_Stats.Title:SetTextColor(r, g, b)

    local lines = BuildInfoLines()
    local inner = STATS_BOX_WIDTH - 20
    local y = -30
    for i, entry in ipairs(lines) do
        local left, right = GetStatsRow(i)
        left:ClearAllPoints(); right:ClearAllPoints()
        left:SetText(""); right:SetText("")
        if entry.blank then
            y = y - 8
        else
            left:SetPoint("TOPLEFT", 10, y)
            right:SetPoint("TOPRIGHT", -10, y)
            left:SetTextColor(entry[3], entry[4], entry[5])
            if entry.single then
                left:SetWidth(inner)
                left:SetText(entry[1])
            else
                -- Right side sizes to its text (capped); the left side gets the rest and truncates
                right:SetWidth(0)
                right:SetText(entry[2])
                right:SetTextColor(entry[6], entry[7], entry[8])
                local rightWidth = math.min(right:GetStringWidth(), inner * 0.65)
                right:SetWidth(rightWidth)
                left:SetWidth(math.max(40, inner - rightWidth - 8))
                left:SetText(entry[1])
            end
            y = y - 15
        end
    end

    -- Clear rows left over from a longer update
    for i = #lines + 1, #SGJ_Stats.Lines do
        SGJ_Stats.Lines[i][1]:SetText("")
        SGJ_Stats.Lines[i][2]:SetText("")
    end
    SGJ_Stats:SetHeight(-y + 10)
end

-- Makes the timers tick in real-time (Throttled to 1 update per second)
local timerUpdateDelay = 0
SGJ_Stats:SetScript("OnUpdate", function(self, elapsed)
    if not self:IsShown() then return end

    timerUpdateDelay = timerUpdateDelay + elapsed
    if timerUpdateDelay >= 1.0 then
        UpdateStatsBox()
        timerUpdateDelay = 0
    end
end)

local function UpdateUnlockMarker()
    local nextLevel = UnitLevel("player") + 1
    local item = lockedUpgrades[1]
    if SGJ_XP_DB.ShowUnlocks and SGJ_XP:IsShown() and item and item.minLevel == nextLevel then
        SGJ_XP.Unlock.Icon:SetTexture(item.icon)
        SGJ_XP.Unlock:Show()
    else
        SGJ_XP.Unlock:Hide()
    end
end

-- Updates the Visual Bar
local function UpdateBar()
    UpdateStatsBox() -- Ensure the box always updates alongside the bar

    if IsAtMaxLevel() or not SGJ_XP_DB.ShowXPBar then
        SGJ_XP:Hide()
        SGJ_XP.Unlock:Hide()
        return
    else
        SGJ_XP:Show()
    end

    local currXP = UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 1
    local restedXP = GetXPExhaustion() or 0

    SGJ_XP.Bar:SetMinMaxValues(0, maxXP)
    SGJ_XP.Bar:SetValue(currXP)
    SGJ_XP.RestedBar:SetMinMaxValues(0, maxXP)
    SGJ_XP.RestedBar:SetValue(math.min(maxXP, currXP + restedXP))
    if restedXP > 0 then
        SGJ_XP.Bar:SetStatusBarColor(unpack(SGJ_XP_DB.RestedColor))
        local r, g, b, a = unpack(SGJ_XP_DB.RestedColor)
        SGJ_XP.RestedBar:SetStatusBarColor(r, g, b, (a or 1) * 0.4)
        SGJ_XP.RestedBar:Show()
    else
        SGJ_XP.Bar:SetStatusBarColor(unpack(SGJ_XP_DB.NormalColor))
        SGJ_XP.RestedBar:Hide()
    end

    if SGJ_XP_DB.ShowQuestProjection and readyQuests.xp > 0 then
        SGJ_XP.QuestBar:SetMinMaxValues(0, maxXP)
        SGJ_XP.QuestBar:SetValue(math.min(maxXP, currXP + readyQuests.xp))
        SGJ_XP.QuestBar:SetStatusBarColor(unpack(SGJ_XP_DB.QuestColor))
        SGJ_XP.QuestBar:Show()
    else
        SGJ_XP.QuestBar:Hide()
    end

    local pct = (maxXP > 0) and ((currXP / maxXP) * 100) or 0
    local formatMode = SGJ_XP_DB and SGJ_XP_DB.XPTextFormat or "BOTH"

    if formatMode == "RAW" then
        SGJ_XP.Text:SetText(string.format("%d / %d", currXP, maxXP))
    elseif formatMode == "PERCENT" then
        SGJ_XP.Text:SetText(string.format("%.1f%%", pct))
    elseif formatMode == "BOTH" then
        SGJ_XP.Text:SetText(string.format("%d / %d  (%.1f%%)", currXP, maxXP, pct))
    else
        SGJ_XP.Text:SetText("")
    end
    SGJ_XP.Text:SetTextColor(unpack(SGJ_XP_DB.TextColor))

    UpdateUnlockMarker()
end

-- Rescans everything that depends on the main addon's scoring
local function RefreshGearData()
    if InCombatLockdown() then return end
    lockedUpgrades = ScanBagUpgrades(UnitLevel("player"))
    bandShift = GetUpcomingBandShift()
    RefreshGearScore()
    UpdateBar()
end

local function RefreshQuestData()
    if InCombatLockdown() then return end
    readyQuests = ScanReadyQuests()
    UpdateBar()
end

-- Level-up gear check: runs once the main addon has re-detected the new level's profile
local function RunDingCheck(oldLevel, newLevel)
    local MSC = _G.MSC
    if MSC and MSC.BumpScoringRevision then MSC:BumpScoringRevision() end
    local locked, ready = ScanBagUpgrades(oldLevel)
    lockedUpgrades = locked
    bandShift = GetUpcomingBandShift()
    RefreshGearScore()
    UpdateBar()

    if not SGJ_XP_DB.DingAlert then return end

    local unspent = UnitCharacterPoints and UnitCharacterPoints("player") or 0
    local lines = {}
    if #ready > 0 then
        table.insert(lines, string.format("|cff55ff55%d upgrade%s now equippable|r", #ready, #ready > 1 and "s" or ""))
        print(string.format("|cffa335ee[SGJ XP]|r Ding! Level %d unlocked these upgrades in your bags:", newLevel))
        local trainNeeded
        for _, item in ipairs(ready) do
            local note = item.train and string.format("  |cffffd100(train %s first)|r", item.train) or ""
            print(string.format("   %s  |cff55ff55(+%.1f)|r%s", item.link, item.delta, note))
            trainNeeded = trainNeeded or item.train
        end
        if trainNeeded then
            table.insert(lines, string.format("|cffffd100Visit your trainer to learn %s|r", trainNeeded))
        end
    end
    if unspent and unspent > 0 then
        table.insert(lines, string.format("|cffffd100%d unspent talent point%s|r (talents change your weights)", unspent, unspent > 1 and "s" or ""))
    end
    if #lines == 0 then return end

    SGJ_Ding.Title:SetText(string.format("Ding! Level %d", newLevel))
    SGJ_Ding.Body:SetText(table.concat(lines, "\n"))
    SGJ_Ding:SetHeight(50 + SGJ_Ding.Body:GetStringHeight() + 14)
    SGJ_Ding:ClearAllPoints()
    if SGJ_XP:IsShown() then
        SGJ_Ding:SetPoint("BOTTOM", SGJ_XP, "TOP", 0, 12)
    elseif SGJ_Stats:IsShown() then
        SGJ_Ding:SetPoint("BOTTOM", SGJ_Stats, "TOP", 0, 8)
    else
        SGJ_Ding:SetPoint("TOP", UIParent, "TOP", 0, -150)
    end
    SGJ_Ding:Show()
    C_Timer.After(15, function() SGJ_Ding:Hide() end)
end

-- Bar tooltip (same lines as the stats box)
local function ShowXPTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine("SGJ Experience", unpack(SGJ_XP_DB.NormalColor))
    for _, entry in ipairs(BuildInfoLines()) do
        if entry.blank then
            GameTooltip:AddLine(" ")
        elseif entry.single then
            GameTooltip:AddLine(entry[1], entry[3], entry[4], entry[5])
        else
            GameTooltip:AddDoubleLine(entry[1], entry[2], entry[3], entry[4], entry[5], entry[6], entry[7], entry[8])
        end
    end
    GameTooltip:Show()
end

-- ============================================================================
-- Script & Event Handlers
-- ============================================================================

-- Dragging Frame
SGJ_XP:SetScript("OnDragStart", function(self)
    if not SGJ_XP_DB.XPBarLocked and not InCombatLockdown() then
        self:StartMoving()
    end
end)

SGJ_XP:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    SGJ_XP_DB.Position = {point, relativePoint, xOfs, yOfs}
end)

-- Tooltip Display
SGJ_XP:SetScript("OnEnter", ShowXPTooltip)
SGJ_XP:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

SGJ_XP.Unlock:SetScript("OnEnter", function(self)
    local item = lockedUpgrades[1]
    if not item then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetHyperlink(item.link)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format("Unlocks at level %d: |cff55ff55+%.1f|r score", item.minLevel, item.delta), 0.2, 1, 0.2)
    if item.train then GameTooltip:AddLine(string.format("Train %s at your class trainer first", item.train), 1, 0.82, 0) end
    GameTooltip:Show()
end)
SGJ_XP.Unlock:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

-- Click Actions (Shift-Click to Reset)
SGJ_XP:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" and IsShiftKeyDown() then
        SGJ_ResetXPSession()
    end
end)

-- Main Event Router
SGJ_XP:RegisterEvent("ADDON_LOADED")
SGJ_XP:RegisterEvent("PLAYER_ENTERING_WORLD")
SGJ_XP:RegisterEvent("PLAYER_XP_UPDATE")
SGJ_XP:RegisterEvent("PLAYER_LEVEL_UP")
SGJ_XP:RegisterEvent("UPDATE_EXHAUSTION")
SGJ_XP:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
SGJ_XP:RegisterEvent("CHAT_MSG_SYSTEM")
SGJ_XP:RegisterEvent("PLAYER_REGEN_DISABLED")
SGJ_XP:RegisterEvent("PLAYER_REGEN_ENABLED")
SGJ_XP:RegisterEvent("BAG_UPDATE_DELAYED")
SGJ_XP:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
SGJ_XP:RegisterEvent("QUEST_LOG_UPDATE")
SGJ_XP:RegisterEvent("CHARACTER_POINTS_CHANGED")
-- QUEST_TURNED_IN carries the exact XP; older clients fall back to parsing chat
useTurnedInEvent = pcall(SGJ_XP.RegisterEvent, SGJ_XP, "QUEST_TURNED_IN")

SGJ_XP:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            -- Initialize Database Variables (With New Additions)
            SGJ_XP_DB = SGJ_XP_DB or {}
            if SGJ_XP_DB.XPBarWidth == nil then SGJ_XP_DB.XPBarWidth = 400 end
            if SGJ_XP_DB.XPBarHeight == nil then SGJ_XP_DB.XPBarHeight = 18 end
            if SGJ_XP_DB.XPBarLocked == nil then SGJ_XP_DB.XPBarLocked = false end
            if SGJ_XP_DB.HideBlizzardXP == nil then SGJ_XP_DB.HideBlizzardXP = false end
            if SGJ_XP_DB.XPTextFormat == nil then SGJ_XP_DB.XPTextFormat = "BOTH" end
            if SGJ_XP_DB.BgOpacity == nil then SGJ_XP_DB.BgOpacity = 0.5 end
            if SGJ_XP_DB.HideInCombat == nil then SGJ_XP_DB.HideInCombat = false end
            if SGJ_XP_DB.ShowTicks == nil then SGJ_XP_DB.ShowTicks = true end
            if SGJ_XP_DB.NormalColor == nil then SGJ_XP_DB.NormalColor = {0.6, 0.2, 0.9, 1.0} end -- Purple
            if SGJ_XP_DB.RestedColor == nil then SGJ_XP_DB.RestedColor = {0.2, 0.4, 1.0, 1.0} end -- Blue
            if SGJ_XP_DB.TickColor == nil then SGJ_XP_DB.TickColor = {0.0, 0.0, 0.0, 0.8} end     -- Black
            if SGJ_XP_DB.TextColor == nil then SGJ_XP_DB.TextColor = {1.0, 1.0, 1.0, 1.0} end     -- White
            if SGJ_XP_DB.QuestColor == nil then SGJ_XP_DB.QuestColor = {1.0, 0.82, 0.0, 0.45} end -- Translucent Gold
            if SGJ_XP_DB.ShowXPBar == nil then SGJ_XP_DB.ShowXPBar = true end
            if SGJ_XP_DB.ShowStatsBox == nil then SGJ_XP_DB.ShowStatsBox = false end
            if SGJ_XP_DB.ShowUnlocks == nil then SGJ_XP_DB.ShowUnlocks = true end
            if SGJ_XP_DB.DingAlert == nil then SGJ_XP_DB.DingAlert = true end
            if SGJ_XP_DB.ShowBandWarning == nil then SGJ_XP_DB.ShowBandWarning = true end
            if SGJ_XP_DB.ShowQuestProjection == nil then SGJ_XP_DB.ShowQuestProjection = true end

            -- Apply Saved Data
            SGJ_XP:SetSize(SGJ_XP_DB.XPBarWidth, SGJ_XP_DB.XPBarHeight)
            SGJ_XP:SetBackdropColor(0, 0, 0, SGJ_XP_DB.BgOpacity)
            SGJ_Stats:SetBackdropColor(0, 0, 0, SGJ_XP_DB.BgOpacity) -- Apply opacity to the new box
            UpdateTicks()

            -- Load XP Bar Position
            if SGJ_XP_DB.Position then
                SGJ_XP:ClearAllPoints()
                local p = SGJ_XP_DB.Position
                SGJ_XP:SetPoint(p[1], UIParent, p[2], p[3], p[4])
            end

            -- Load Stats Box Position
            if SGJ_XP_DB.StatsBoxPosition then
                SGJ_Stats:ClearAllPoints()
                local p = SGJ_XP_DB.StatsBoxPosition
                SGJ_Stats:SetPoint(p[1], UIParent, p[2], p[3], p[4])
            end
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Fires on every loading screen; only the first one starts the session
        if not sessionStarted then
            sessionStarted = true
            sessionStartTime = GetTime()
        end
        lastXP = UnitXP("player") or 0
        lastMaxXP = UnitXPMax("player") or 1
        lastRested = GetXPExhaustion() or 0
        UpdateBlizzardBarVisibility()
        UpdateBar()
        -- Give the main addon time to detect the spec before scoring
        Debounce("gear", 3, RefreshGearData)
        Debounce("quests", 3, RefreshQuestData)

    elseif event == "PLAYER_XP_UPDATE" then
        TrackXPGains()
        UpdateBar()

    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = ...
        local oldLevel = UnitLevel("player")
        newLevel = tonumber(newLevel) or (oldLevel + 1)
        if oldLevel >= newLevel then oldLevel = newLevel - 1 end
        UpdateBar()
        -- UnitLevel still reports the old level during this event
        C_Timer.After(1.5, function() RunDingCheck(oldLevel, newLevel) end)

    elseif event == "UPDATE_EXHAUSTION" then
        lastRested = GetXPExhaustion() or 0
        UpdateBar()

    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local text = ...
        local _, gainedXP = string.match(text, KILL_PATTERN)
        local amount = tonumber(gainedXP)
        if amount then
            -- Rested kills print "(+N exp Rested bonus)"; strip it so rested math uses base XP
            local base = amount
            local bonus = tonumber((text:match("%((.-)%)") or ""):match("(%d+)") or "")
            if bonus and lastRested > 0 and bonus < amount then base = amount - bonus end
            killXPTotal = killXPTotal + amount
            killBaseXPTotal = killBaseXPTotal + base
            killCount = killCount + 1
        end
        lastRested = GetXPExhaustion() or 0

    elseif event == "QUEST_TURNED_IN" then
        local _, xpReward = ...
        xpReward = tonumber(xpReward)
        if xpReward and xpReward > 0 then
            questXPTotal = questXPTotal + xpReward
            questCount = questCount + 1
        end
        Debounce("gear", 1, RefreshGearData) -- Rewards land in your bags

    elseif event == "CHAT_MSG_SYSTEM" then
        if useTurnedInEvent then return end
        local text = ...
        local gainedXP = string.match(text, QUEST_PATTERN)
        if gainedXP then
            local amount = tonumber(gainedXP)
            questXPTotal = questXPTotal + amount
            questCount = questCount + 1
        end

    elseif event == "BAG_UPDATE_DELAYED" then
        Debounce("gear", 1, RefreshGearData)

    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "CHARACTER_POINTS_CHANGED" then
        Debounce("gear", 1, RefreshGearData)

    elseif event == "QUEST_LOG_UPDATE" then
        -- Our own scan selects quest log entries; ignore the echo so we don't loop
        if GetTime() - lastQuestScanEnd < 0.5 then return end
        Debounce("quests", 1, RefreshQuestData)

    elseif event == "PLAYER_REGEN_DISABLED" then
        if SGJ_XP_DB.HideInCombat then
            SGJ_XP:Hide()
            SGJ_XP.Unlock:Hide()
            SGJ_Stats:Hide()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        UpdateBar() -- Handles showing both safely
        -- Catch up on anything skipped while in combat
        Debounce("gear", 1, RefreshGearData)
        Debounce("quests", 1, RefreshQuestData)
    end
end)

-- ============================================================================
-- SGJ Dynamic Tab Integration
-- ============================================================================

local function BuildXPOptionsTab(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 40, -30)
    title:SetText("Experience Tracker Options")
    title:SetTextColor(1, 0.82, 0)

    -- 1. Lock Checkbox
    local LockBox = CreateFrame("CheckButton", nil, f, "ChatConfigCheckButtonTemplate")
    LockBox:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)
    LockBox.Text:SetText("Lock Frames"); LockBox.Text:SetTextColor(0.9, 0.9, 0.9)
    LockBox:SetChecked(SGJ_XP_DB.XPBarLocked)
    LockBox:SetScript("OnClick", function(self) SGJ_XP_DB.XPBarLocked = self:GetChecked() end)

    -- 2. Hide Blizzard Bar Checkbox
    local HideBlizzBox = CreateFrame("CheckButton", nil, f, "ChatConfigCheckButtonTemplate")
    HideBlizzBox:SetPoint("TOPLEFT", LockBox, "BOTTOMLEFT", 0, -10) -- Fixed Spacing
    HideBlizzBox.Text:SetText("Hide Blizzard XP Bar"); HideBlizzBox.Text:SetTextColor(0.9, 0.9, 0.9)
    HideBlizzBox:SetChecked(SGJ_XP_DB.HideBlizzardXP)
    HideBlizzBox:SetScript("OnClick", function(self) SGJ_XP_DB.HideBlizzardXP = self:GetChecked(); UpdateBlizzardBarVisibility() end)

	-- Show XP Bar Toggle
    local ShowBarBox = CreateFrame("CheckButton", nil, f, "ChatConfigCheckButtonTemplate")
    ShowBarBox:SetPoint("TOPLEFT", HideBlizzBox, "BOTTOMLEFT", 0, -10) -- Fixed Spacing
    ShowBarBox.Text:SetText("Show Main XP Bar"); ShowBarBox.Text:SetTextColor(0.9, 0.9, 0.9)
    ShowBarBox:SetChecked(SGJ_XP_DB.ShowXPBar)
    ShowBarBox:SetScript("OnClick", function(self) SGJ_XP_DB.ShowXPBar = self:GetChecked(); UpdateBar() end)

    -- Show Stats Box Toggle
    local ShowStatsBox = CreateFrame("CheckButton", nil, f, "ChatConfigCheckButtonTemplate")
    ShowStatsBox:SetPoint("TOPLEFT", ShowBarBox, "BOTTOMLEFT", 0, -10) -- Fixed Spacing
    ShowStatsBox.Text:SetText("Show Standalone Stats Box"); ShowStatsBox.Text:SetTextColor(0.9, 0.9, 0.9)
    ShowStatsBox:SetChecked(SGJ_XP_DB.ShowStatsBox)
    ShowStatsBox:SetScript("OnClick", function(self) SGJ_XP_DB.ShowStatsBox = self:GetChecked(); UpdateBar() end)

    -- 3. NEW: Auto-Hide in Combat Checkbox
    local CombatBox = CreateFrame("CheckButton", nil, f, "ChatConfigCheckButtonTemplate")
    CombatBox:SetPoint("TOPLEFT", ShowStatsBox, "BOTTOMLEFT", 0, -10) -- Fixed Spacing
    CombatBox.Text:SetText("Auto-Hide During Combat"); CombatBox.Text:SetTextColor(0.9, 0.9, 0.9)
    CombatBox:SetChecked(SGJ_XP_DB.HideInCombat)
    CombatBox:SetScript("OnClick", function(self) SGJ_XP_DB.HideInCombat = self:GetChecked() end)

    -- 4. NEW: Milestone Ticks Checkbox
    local TicksBox = CreateFrame("CheckButton", nil, f, "ChatConfigCheckButtonTemplate")
    TicksBox:SetPoint("TOPLEFT", CombatBox, "BOTTOMLEFT", 0, -10)
    TicksBox.Text:SetText("Show 20-Segment Brackets (Classic Style)"); TicksBox.Text:SetTextColor(0.9, 0.9, 0.9)
    TicksBox:SetChecked(SGJ_XP_DB.ShowTicks)
    TicksBox:SetScript("OnClick", function(self)
        SGJ_XP_DB.ShowTicks = self:GetChecked()
        UpdateTicks() -- Redraws immediately
    end)

    -- Gear Judge Integration (right column)
    local gearTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gearTitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 300, -6)
    gearTitle:SetText("Gear Judge Integration")
    gearTitle:SetTextColor(1, 0.82, 0)

    local function CreateGearToggle(label, dbKey, anchor, onChange)
        local box = CreateFrame("CheckButton", nil, f, "ChatConfigCheckButtonTemplate")
        box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
        box.Text:SetText(label); box.Text:SetTextColor(0.9, 0.9, 0.9)
        box:SetChecked(SGJ_XP_DB[dbKey])
        box:SetScript("OnClick", function(self)
            SGJ_XP_DB[dbKey] = self:GetChecked()
            if onChange then onChange() end
        end)
        return box
    end

    local UnlocksBox = CreateGearToggle("Show Level-Locked Upgrades", "ShowUnlocks", gearTitle, UpdateBar)
    local DingBox = CreateGearToggle("Level-Up Gear Alert", "DingAlert", UnlocksBox)
    local BandBox = CreateGearToggle("Warn Before Weights Change", "ShowBandWarning", DingBox)
    CreateGearToggle("Show Quest Turn-In Projection", "ShowQuestProjection", BandBox, UpdateBar)

    -- 5. Cycle Text Format Button
    local FormatBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    FormatBtn:SetSize(140, 25)
    FormatBtn:SetPoint("TOPLEFT", TicksBox, "BOTTOMLEFT", 0, -20)
    local formatCycle = {"BOTH", "RAW", "PERCENT", "NONE"}

    local function UpdateFormatBtn() FormatBtn:SetText("Text: " .. (SGJ_XP_DB.XPTextFormat or "BOTH")) end
    UpdateFormatBtn()

    FormatBtn:SetScript("OnClick", function()
        local current = SGJ_XP_DB.XPTextFormat
        local nextIdx = 1
        for i, v in ipairs(formatCycle) do if v == current then nextIdx = (i % #formatCycle) + 1 break end end
        SGJ_XP_DB.XPTextFormat = formatCycle[nextIdx]
        UpdateFormatBtn(); UpdateBar()
    end)

    -- 6. Width Slider
    local WidthSlider = CreateFrame("Slider", "SGJ_XPWidthSlider", f, "OptionsSliderTemplate")
    WidthSlider:SetPoint("TOPLEFT", FormatBtn, "BOTTOMLEFT", 0, -40)
    WidthSlider:SetMinMaxValues(100, 1000); WidthSlider:SetValueStep(5); WidthSlider:SetObeyStepOnDrag(true)
    _G[WidthSlider:GetName() .. 'Low']:SetText('100'); _G[WidthSlider:GetName() .. 'High']:SetText('1000')
    _G[WidthSlider:GetName() .. 'Text']:SetText('Bar Width: ' .. SGJ_XP_DB.XPBarWidth .. 'px')
    WidthSlider:SetValue(SGJ_XP_DB.XPBarWidth)

    WidthSlider:SetScript("OnValueChanged", function(self, value)
        _G[self:GetName() .. 'Text']:SetText('Bar Width: ' .. value .. 'px')
        if SGJ_ExperienceBar then
            SGJ_ExperienceBar:SetWidth(value)
            UpdateTicks() -- Redraw the brackets so they space out evenly!
        end
        SGJ_XP_DB.XPBarWidth = value
    end)

    -- 7. Height Slider
    local HeightSlider = CreateFrame("Slider", "SGJ_XPHeightSlider", f, "OptionsSliderTemplate")
    HeightSlider:SetPoint("TOPLEFT", WidthSlider, "BOTTOMLEFT", 0, -40)
    HeightSlider:SetMinMaxValues(5, 50); HeightSlider:SetValueStep(1); HeightSlider:SetObeyStepOnDrag(true)
    _G[HeightSlider:GetName() .. 'Low']:SetText('5'); _G[HeightSlider:GetName() .. 'High']:SetText('50')
    _G[HeightSlider:GetName() .. 'Text']:SetText('Bar Height: ' .. SGJ_XP_DB.XPBarHeight .. 'px')
    HeightSlider:SetValue(SGJ_XP_DB.XPBarHeight)

    HeightSlider:SetScript("OnValueChanged", function(self, value)
        _G[self:GetName() .. 'Text']:SetText('Bar Height: ' .. value .. 'px')
        if SGJ_ExperienceBar then
            SGJ_ExperienceBar:SetHeight(value)
            UpdateTicks() -- Make the bracket lines stretch to fit the new height
        end
        SGJ_XP_DB.XPBarHeight = value
    end)

    -- 8. NEW: Background Opacity Slider
    local OpacitySlider = CreateFrame("Slider", "SGJ_XPOpacitySlider", f, "OptionsSliderTemplate")
    OpacitySlider:SetPoint("TOPLEFT", HeightSlider, "BOTTOMLEFT", 0, -40)
    OpacitySlider:SetMinMaxValues(0, 1); OpacitySlider:SetValueStep(0.1); OpacitySlider:SetObeyStepOnDrag(true)
    _G[OpacitySlider:GetName() .. 'Low']:SetText('0%'); _G[OpacitySlider:GetName() .. 'High']:SetText('100%')
    _G[OpacitySlider:GetName() .. 'Text']:SetText('Background Opacity: ' .. (SGJ_XP_DB.BgOpacity * 100) .. '%')
    OpacitySlider:SetValue(SGJ_XP_DB.BgOpacity)

    OpacitySlider:SetScript("OnValueChanged", function(self, value)
        _G[self:GetName() .. 'Text']:SetText('Background Opacity: ' .. (value * 100) .. '%')
        if SGJ_ExperienceBar then SGJ_ExperienceBar:SetBackdropColor(0, 0, 0, value) end
        SGJ_XP_DB.BgOpacity = value
    end)

	-- Helper function to create uniform color buttons
    local function CreateColorSwatch(name, dbKey, anchorFrame, xOff, yOff, updateAction)
        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(20, 20)
        btn:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", xOff, yOff)

        -- The solid color square
        btn.ColorTex = btn:CreateTexture(nil, "BACKGROUND")
        btn.ColorTex:SetAllPoints()
        btn.ColorTex:SetColorTexture(unpack(SGJ_XP_DB[dbKey]))

        -- The Blizzard border for swatches
        btn.Border = btn:CreateTexture(nil, "OVERLAY")
        btn.Border:SetTexture("Interface\\ChatFrame\\ChatFrameColorSwatch")
        btn.Border:SetPoint("CENTER")
        btn.Border:SetSize(24, 24)

        btn.Text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        btn.Text:SetPoint("LEFT", btn, "RIGHT", 5, 0)
        btn.Text:SetText(name)

        btn:SetScript("OnClick", function()
            local r, g, b, a = unpack(SGJ_XP_DB[dbKey])
            OpenColorPicker(r, g, b, a, function(newR, newG, newB, newA)
                -- Save it
                SGJ_XP_DB[dbKey] = {newR, newG, newB, newA}
                -- Update the button visually
                btn.ColorTex:SetColorTexture(newR, newG, newB, newA)
                -- Trigger the live update on the bar
                updateAction()
            end)
        end)
        return btn
    end

    -- Create the Color Grid
    -- Left Column
    local cNormal = CreateColorSwatch("Normal Bar Color", "NormalColor", OpacitySlider, 0, -25, UpdateBar)
    local cTicks = CreateColorSwatch("Milestone Ticks", "TickColor", cNormal, 0, -15, UpdateTicks)
    CreateColorSwatch("Quest Turn-In Color", "QuestColor", cTicks, 0, -15, UpdateBar)

    -- Right Column
    local cRested = CreateColorSwatch("Rested Bar Color", "RestedColor", OpacitySlider, 150, -25, UpdateBar)
    local cText = CreateColorSwatch("Text Color", "TextColor", cRested, 0, -15, UpdateBar)

    _G.MSC.ViewXPTracker = f
end

-- Wait for the core addon to load, then inject our tab
local TabInjector = CreateFrame("Frame")
TabInjector:RegisterEvent("PLAYER_LOGIN")
TabInjector:SetScript("OnEvent", function()
    if _G.MSC and _G.MSC.RegisterPluginTab then
        -- Adds a 5th button to your main sidebar!
        _G.MSC.RegisterPluginTab(
            "XP Tracker",                                   -- Hover text for the sidebar button
            "Interface\\Icons\\Spell_Holy_MagicalSentry",   -- Uses the cool purple magic eye icon
            BuildXPOptionsTab,                              -- The function we just wrote above
            "ViewXPTracker"                                 -- The string key linking to the frame
        )
    end
end)
