-- ============================================================================
-- SGJ Experience Tracker Plugin
-- ============================================================================

local addonName, _ = ...

-- 1. Session State Variables
local sessionStartTime = 0
local totalXPGainedSession = 0
local lastXP = 0

-- Specific Tracking
local killCount = 0
local killXPTotal = 0

local questCount = 0
local questXPTotal = 0

-- Global function to reset the tracker
function SGJ_ResetXPSession()
    sessionStartTime = GetTime()
    totalXPGainedSession = 0
    killCount = 0
    killXPTotal = 0
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

SGJ_XP.Bar = CreateFrame("StatusBar", nil, SGJ_XP)
SGJ_XP.Bar:SetAllPoints()
SGJ_XP.Bar:SetFrameLevel(SGJ_XP.RestedBar:GetFrameLevel() + 1)
SGJ_XP.Bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
SGJ_XP.Bar:GetStatusBarTexture():SetHorizTile(false)

-- 4. Visuals: Text Overlay
SGJ_XP.Text = SGJ_XP.Bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
SGJ_XP.Text:SetPoint("CENTER", SGJ_XP.Bar, "CENTER", 0, 0)
SGJ_XP.Text:SetShadowColor(0, 0, 0, 1)
SGJ_XP.Text:SetShadowOffset(1, -1)

-- 5. Create the Standalone Stats Box
local SGJ_Stats = CreateFrame("Frame", "SGJ_XPStatsBox", UIParent, "BackdropTemplate")
SGJ_Stats:SetSize(240, 160) -- Wider and taller to match a tooltip
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

-- Helper function to create Tooltip-style Double Lines
local function CreateDoubleLine(yOffset)
    local left = SGJ_Stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    left:SetPoint("TOPLEFT", 10, yOffset)
    left:SetJustifyH("LEFT")
    
    local right = SGJ_Stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    right:SetPoint("TOPRIGHT", -10, yOffset)
    right:SetJustifyH("RIGHT")
    
    return left, right
end

-- Create the rows (Spacing them out visually like the tooltip)
SGJ_Stats.Lines = {}
SGJ_Stats.Lines[1] = {CreateDoubleLine(-30)} -- Current XP
SGJ_Stats.Lines[2] = {CreateDoubleLine(-45)} -- Remaining
-- Blank space (-60)
SGJ_Stats.Lines[3] = {CreateDoubleLine(-70)} -- Session Time
SGJ_Stats.Lines[4] = {CreateDoubleLine(-85)} -- Overall XP/Hr
SGJ_Stats.Lines[5] = {CreateDoubleLine(-100)} -- Time to Level
-- Blank space (-115)
SGJ_Stats.Lines[6] = {CreateDoubleLine(-125)} -- Kills
SGJ_Stats.Lines[7] = {CreateDoubleLine(-140)} -- Quests

SGJ_Stats:SetScript("OnDragStart", function(self) if not SGJ_XP_DB.XPBarLocked and not InCombatLockdown() then self:StartMoving() end end)
SGJ_Stats:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    SGJ_XP_DB.StatsBoxPosition = {point, relativePoint, xOfs, yOfs}
end)

-- Create 7 lines for rich data display
SGJ_Stats.L1 = SGJ_Stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); SGJ_Stats.L1:SetPoint("TOPLEFT", 10, -28)
SGJ_Stats.L2 = SGJ_Stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); SGJ_Stats.L2:SetPoint("TOPLEFT", 10, -43)
SGJ_Stats.L3 = SGJ_Stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); SGJ_Stats.L3:SetPoint("TOPLEFT", 10, -58)
SGJ_Stats.L4 = SGJ_Stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); SGJ_Stats.L4:SetPoint("TOPLEFT", 10, -78) -- Extra gap for readability
SGJ_Stats.L5 = SGJ_Stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); SGJ_Stats.L5:SetPoint("TOPLEFT", 10, -93)
SGJ_Stats.L6 = SGJ_Stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); SGJ_Stats.L6:SetPoint("TOPLEFT", 10, -108)
SGJ_Stats.L7 = SGJ_Stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); SGJ_Stats.L7:SetPoint("TOPLEFT", 10, -123)

SGJ_Stats:SetScript("OnDragStart", function(self) if not SGJ_XP_DB.XPBarLocked and not InCombatLockdown() then self:StartMoving() end end)
SGJ_Stats:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    SGJ_XP_DB.StatsBoxPosition = {point, relativePoint, xOfs, yOfs}
end)

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
        -- The player leveled up
        local gained = (maxXP - lastXP) + currentXP
        totalXPGainedSession = totalXPGainedSession + gained
    end
    
    lastXP = currentXP
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

-- Updates the Standalone Stats Box
local function UpdateStatsBox()
    local level = UnitLevel("player")
    if level >= 70 or not SGJ_XP_DB.ShowStatsBox then
        SGJ_Stats:Hide()
        return
    else
        SGJ_Stats:Show()
    end

    local current, maxXP, remaining, xpPerHour, timeToLevelStr, avgKillXP, killsToLevel, avgQuestXP, questsToLevel, timePlayed = GetXPData()
    
    -- Title Color matches the Normal Bar setting
    local r, g, b = unpack(SGJ_XP_DB.NormalColor or {0.6, 0.2, 0.9})
    SGJ_Stats.Title:SetTextColor(r, g, b)

    -- Session Time formatting
    local h = math.floor(timePlayed)
    local m = math.floor((timePlayed - h) * 60)
    local s = math.floor(((timePlayed - h) * 3600) % 60)

    -- Row 1: Current XP (White)
    SGJ_Stats.Lines[1][1]:SetText("Current XP:"); SGJ_Stats.Lines[1][1]:SetTextColor(1, 1, 1)
    SGJ_Stats.Lines[1][2]:SetText(string.format("%d / %d", current, maxXP)); SGJ_Stats.Lines[1][2]:SetTextColor(1, 1, 1)

    -- Row 2: Remaining (White)
    SGJ_Stats.Lines[2][1]:SetText("Remaining:"); SGJ_Stats.Lines[2][1]:SetTextColor(1, 1, 1)
    SGJ_Stats.Lines[2][2]:SetText(tostring(remaining)); SGJ_Stats.Lines[2][2]:SetTextColor(1, 1, 1)

    -- Row 3: Session Time (Light Grey)
    SGJ_Stats.Lines[3][1]:SetText("Session Time:"); SGJ_Stats.Lines[3][1]:SetTextColor(0.8, 0.8, 0.8)
    SGJ_Stats.Lines[3][2]:SetText(string.format("%dh %02dm %02ds", h, m, s)); SGJ_Stats.Lines[3][2]:SetTextColor(0.8, 0.8, 0.8)

    -- Row 4: XP / Hour (Green)
    SGJ_Stats.Lines[4][1]:SetText("Overall XP / Hour:"); SGJ_Stats.Lines[4][1]:SetTextColor(0.2, 1, 0.2)
    SGJ_Stats.Lines[4][2]:SetText(string.format("%.0f", xpPerHour)); SGJ_Stats.Lines[4][2]:SetTextColor(1, 1, 1)

    -- Row 5: Time to Level (Blue)
    SGJ_Stats.Lines[5][1]:SetText("Est. Time to Level:"); SGJ_Stats.Lines[5][1]:SetTextColor(0.2, 0.8, 1)
    SGJ_Stats.Lines[5][2]:SetText(timeToLevelStr); SGJ_Stats.Lines[5][2]:SetTextColor(1, 1, 1)

    -- Row 6: Kills (Gold / Grey)
    if killCount > 0 then
        SGJ_Stats.Lines[6][1]:SetText(string.format("Kills (%d tracked):", killCount)); SGJ_Stats.Lines[6][1]:SetTextColor(1, 0.8, 0)
        SGJ_Stats.Lines[6][2]:SetText(string.format("~%d to level", killsToLevel)); SGJ_Stats.Lines[6][2]:SetTextColor(1, 1, 1)
    else
        SGJ_Stats.Lines[6][1]:SetText("Kills:"); SGJ_Stats.Lines[6][1]:SetTextColor(0.5, 0.5, 0.5)
        SGJ_Stats.Lines[6][2]:SetText("Need data..."); SGJ_Stats.Lines[6][2]:SetTextColor(1, 1, 1)
    end

    -- Row 7: Quests (Gold / Grey)
    if questCount > 0 then
        SGJ_Stats.Lines[7][1]:SetText(string.format("Quests (%d tracked):", questCount)); SGJ_Stats.Lines[7][1]:SetTextColor(1, 0.8, 0)
        SGJ_Stats.Lines[7][2]:SetText(string.format("~%d to level", questsToLevel)); SGJ_Stats.Lines[7][2]:SetTextColor(1, 1, 1)
    else
        SGJ_Stats.Lines[7][1]:SetText("Quests:"); SGJ_Stats.Lines[7][1]:SetTextColor(0.5, 0.5, 0.5)
        SGJ_Stats.Lines[7][2]:SetText("Need data..."); SGJ_Stats.Lines[7][2]:SetTextColor(1, 1, 1)
    end
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

-- Updates the Visual Bar
local function UpdateBar()
    UpdateStatsBox() -- Ensure the box always updates alongside the bar
    
    local level = UnitLevel("player")
    if level >= 70 or not SGJ_XP_DB.ShowXPBar then
        SGJ_XP:Hide()
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
end

-- Global function to reset the tracker
function SGJ_ResetXPSession()
    sessionStartTime = GetTime()
    totalXPGainedSession = 0
    print("|cffa335ee[SGJ XP]|r Session Tracker Reset.")
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
SGJ_XP:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("SGJ Experience", unpack(SGJ_XP_DB.NormalColor))

    local current, maxXP, remaining, xpPerHour, timeToLevelStr, avgKillXP, killsToLevel, avgQuestXP, questsToLevel, timePlayed = GetXPData()

    GameTooltip:AddDoubleLine("Current XP:", string.format("%d / %d", current, maxXP), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Remaining:", remaining, 1, 1, 1, 1, 1, 1)
    local restedXP = GetXPExhaustion() or 0
    if restedXP > 0 then
        GameTooltip:AddDoubleLine("Rested XP:", string.format("%d (%.1f%%)", restedXP, (restedXP / maxXP) * 100), 0.2, 0.4, 1.0, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Overall XP / Hour:", string.format("%.0f", xpPerHour), 0.2, 1, 0.2, 1, 1, 1)
    GameTooltip:AddDoubleLine("Est. Time to Level:", timeToLevelStr, 0.2, 0.8, 1, 1, 1, 1)
    GameTooltip:AddLine(" ")
    
    if killCount > 0 then
        GameTooltip:AddDoubleLine(string.format("Kills (%d tracked):", killCount), string.format("~%d to level", killsToLevel), 1, 0.8, 0, 1, 1, 1)
    else
        GameTooltip:AddDoubleLine("Kills:", "Need data...", 0.5, 0.5, 0.5, 1, 1, 1)
    end
    
    if questCount > 0 then
        GameTooltip:AddDoubleLine(string.format("Quests (%d tracked):", questCount), string.format("~%d to level", questsToLevel), 1, 0.8, 0, 1, 1, 1)
    else
        GameTooltip:AddDoubleLine("Quests:", "Need data...", 0.5, 0.5, 0.5, 1, 1, 1)
    end

    GameTooltip:Show()
end)

SGJ_XP:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

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
SGJ_XP:RegisterEvent("PLAYER_REGEN_DISABLED")
SGJ_XP:RegisterEvent("PLAYER_REGEN_ENABLED")

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
            if SGJ_XP_DB.ShowXPBar == nil then SGJ_XP_DB.ShowXPBar = true end
            if SGJ_XP_DB.ShowStatsBox == nil then SGJ_XP_DB.ShowStatsBox = false end
            
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
        sessionStartTime = GetTime()
        lastXP = UnitXP("player") or 0
        UpdateBlizzardBarVisibility()
        UpdateBar()
        
    elseif event == "PLAYER_XP_UPDATE" then
        TrackXPGains()
        UpdateBar()
        
    elseif event == "PLAYER_LEVEL_UP" or event == "UPDATE_EXHAUSTION" then
        UpdateBar()
        
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local text = ... 
        local gainedXP = string.match(text, "(%d+) experience")
        if gainedXP then
            local amount = tonumber(gainedXP)
            killXPTotal = killXPTotal + amount
            killCount = killCount + 1
        end
        
    elseif event == "CHAT_MSG_SYSTEM" then
        local text = ...
        -- Quest XP usually comes through system messages. We check both common string patterns.
        local gainedXP = string.match(text, "Experience gained: (%d+)")
        if not gainedXP then 
            gainedXP = string.match(text, "gain (%d+) experience") 
        end
        
        if gainedXP then
            local amount = tonumber(gainedXP)
            questXPTotal = questXPTotal + amount
            questCount = questCount + 1
        end
		
    elseif event == "PLAYER_REGEN_DISABLED" then
        if SGJ_XP_DB.HideInCombat then
            SGJ_XP:Hide()
            SGJ_Stats:Hide()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        UpdateBar() -- Handles showing both safely
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

    -- Create the 2x2 Color Grid
    -- Left Column
    local cNormal = CreateColorSwatch("Normal Bar Color", "NormalColor", OpacitySlider, 0, -25, UpdateBar)
    local cTicks = CreateColorSwatch("Milestone Ticks", "TickColor", cNormal, 0, -15, UpdateTicks)
    
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



