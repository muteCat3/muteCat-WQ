
local _, addon = ...

-----------------------------------------
-- Color Constants
-----------------------------------------
local colors = {
	timeCritical	= CreateColor(1, 0.2, 0.2, 1), -- Neon Red (<8h)
	timeMedium		= CreateColor(1, 1, 0, 1),   -- Neon Yellow (<24h)
	manaBlue		= CreateColor(0, 0.5, 1, 1), -- Mana Blue (>24h)
	elitePink		= CreateColor(1, 0.5, 1, 1), -- Elite Pink (Legacy Fallback)
	timeNone		= CreateColor(0.5, 0.5, 0.5, 1),
}

-----------------------------------------
-- Data Helpers
-----------------------------------------

--- Determines the pin color based on quest time remaining.
--- @param questID number
--- @return ColorMixin, boolean isActive
local function GetPinColor(questID)
    local timeLeftSeconds = C_TaskQuest.GetQuestTimeLeftSeconds(questID) or 0
    
    if timeLeftSeconds == 0 then
        -- Data Guard: If timer is 0 but quest info exists, it's likely still loading.
        -- Show Blue to prevent "missing ring" flicker during map transitions.
        if C_TaskQuest.GetQuestInfoByQuestID(questID) then
            return colors.manaBlue, true 
        end
        return GRAY_FONT_COLOR, false
    end

    if timeLeftSeconds < 8 * 3600 then
        return colors.timeCritical, true -- < 8h
    elseif timeLeftSeconds < 24 * 3600 then
        return colors.timeMedium, true   -- < 24h
    else
        return colors.manaBlue, true     -- > 24h
    end
end

-----------------------------------------
-- Pin Mixin: muteCatWQPinMixin
-----------------------------------------

local mapScale, parentScale, zoomFactor
addon:RegisterOptionCallback('mapScale', function(value) mapScale = value end)
addon:RegisterOptionCallback('parentScale', function(value) parentScale = value end)
addon:RegisterOptionCallback('zoomFactor', function(value) zoomFactor = value end)

muteCatWQPinMixin = CreateFromMixins(WorldMap_WorldQuestPinMixin)

--- Initial setup when the pin is created.
function muteCatWQPinMixin:OnLoad()
	WorldMap_WorldQuestPinMixin.OnLoad(self)

    -- Custom Ring System (Static Textures)
    local size = 22 -- Default Tight Fit
    
    -- Ring Background
    local RingBG = self:CreateTexture(nil, "OVERLAY", nil, 1)
    RingBG:SetPoint("CENTER")
    RingBG:SetSize(size, size) 
    RingBG:SetTexture("Interface\\AddOns\\muteCat WQ\\Images\\PoIRingBG.tga")
    RingBG:SetAlpha(1) 
    RingBG:SetBlendMode("ADD")
    self.RingBG = RingBG

    -- Active Ring Bar
    local Ring = self:CreateTexture(nil, "OVERLAY", nil, 2)
    Ring:SetPoint("CENTER")
    Ring:SetSize(size, size) 
    Ring:SetTexture("Interface\\AddOns\\muteCat WQ\\Images\\PoIRingBar.tga")
    Ring:SetAlpha(1) 
    self.Ring = Ring 

	-- Template Region Recreation
	local TrackedCheck = self:CreateTexture(nil, 'OVERLAY', nil, 7)
	TrackedCheck:SetPoint('BOTTOM', self, 'BOTTOMRIGHT', 0, -2)
	TrackedCheck:SetAtlas('worldquest-emissary-tracker-checkmark', true)
	TrackedCheck:Hide()
	self.TrackedCheck = TrackedCheck

	local TimeLowFrame = CreateFrame('Frame', nil, self)
	TimeLowFrame:SetPoint('CENTER', 9, -9)
	TimeLowFrame:SetSize(22, 22)
	TimeLowFrame:Hide()
	self.TimeLowFrame = TimeLowFrame

	local TimeLowIcon = TimeLowFrame:CreateTexture(nil, 'OVERLAY')
	TimeLowIcon:SetAllPoints()
	TimeLowIcon:SetAtlas('worldquest-icon-clock')
	TimeLowFrame.Icon = TimeLowIcon

	-- Reward Display (with Alpha Mask)
	local Reward = self:CreateTexture(nil, 'OVERLAY')
	Reward:SetPoint('CENTER', self.PushedTexture)
	Reward:SetSize(self:GetWidth() - 4, self:GetHeight() - 4)
	Reward:SetTexCoord(0.1, 0.9, 0.1, 0.9)
	self.Reward = Reward

	local RewardMask = self:CreateMaskTexture()
	RewardMask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]])
	RewardMask:SetAllPoints(Reward)
	Reward:AddMaskTexture(RewardMask)

    -- Additional Indicators
	local Indicator = self:CreateTexture(nil, 'OVERLAY', nil, 2)
	Indicator:SetPoint('CENTER', self, 'TOPLEFT', 4, -4)
	self.Indicator = Indicator

	local Reputation = self:CreateTexture(nil, 'OVERLAY', nil, 2)
	Reputation:SetPoint('CENTER', self, 'BOTTOM', 0, 2)
	Reputation:SetSize(10, 10)
	Reputation:SetAtlas('socialqueuing-icon-eye')
	Reputation:Hide()
	self.Reputation = Reputation

	local Bounty = self:CreateTexture(nil, 'OVERLAY', nil, 3)
	Bounty:SetAtlas('QuestNormal', true)
	Bounty:SetScale(0.65)
	Bounty:SetPoint('LEFT', self, 'RIGHT', -(Bounty:GetWidth() / 2), 0)
	self.Bounty = Bounty
end

--- Main refresh function called by the map canvas.
function muteCatWQPinMixin:RefreshVisuals()
	WorldMap_WorldQuestPinMixin.RefreshVisuals(self)

    -- [1] Immediate Reset to prevent flicker
	self.Display.Icon:Hide()
    self.TimeLowFrame:Hide()

    local questID = self.questID
    if not questID then return end

    -- [2] Load Data Guard
    local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
	local currencyRewards = C_QuestLog.GetQuestRewardCurrencies(questID)
    local hasItem = GetNumQuestLogRewards(questID) > 0
    local hasCurrency = #currencyRewards > 0
    local hasMoney = GetQuestLogRewardMoney(questID) > 0

    if not tagInfo then
        -- Silent wait: Hide custom elements if the previous quest data is still on the frame
        self.Ring:Hide()
        self.RingBG:Hide()
        self.Reward:Hide()
        C_QuestLog.RequestQuestRewards(questID)
        return
    end

	-- [3] Handle Scaling
	local mapID = self:GetMap():GetMapID()
	if mapID == 947 then
		self:SetScalingLimits(1, parentScale / 2, (parentScale / 2) + zoomFactor)
	elseif addon:IsParentMap(mapID) then
		self:SetScalingLimits(1, parentScale, parentScale + zoomFactor)
	else
		self:SetScalingLimits(1, mapScale, mapScale + zoomFactor)
	end

	-- [4] Marker Visuals
    local isElite = tagInfo.isElite
	if self:IsSelected() then
		self.NormalTexture:SetAtlas('worldquest-questmarker-epic-supertracked', true)
	else
		self.NormalTexture:SetAtlas('worldquest-questmarker-epic', true)
	end

    -- [5] Ring Customization
    local color, isActive = GetPinColor(questID)
    self.RingBG:SetVertexColor(color:GetRGB())
    self.Ring:SetVertexColor(color:GetRGB())
    
    if isElite then
        self.RingBG:SetTexture("Interface\\AddOns\\muteCat WQ\\Images\\PoIRingBGElite.tga")
        self.Ring:SetTexture("Interface\\AddOns\\muteCat WQ\\Images\\PoIRingBarElite.tga")
        self.RingBG:SetSize(27, 27) 
        self.Ring:SetSize(27, 27)
        self.RingBG:SetAlpha(1)
        self.Ring:SetAlpha(1)
        self.RingBG:SetBlendMode("BLEND") 
        self.Ring:SetBlendMode("BLEND")
    else
        self.RingBG:SetTexture("Interface\\AddOns\\muteCat WQ\\Images\\PoIRingBG.tga")
        self.Ring:SetTexture("Interface\\AddOns\\muteCat WQ\\Images\\PoIRingBar.tga")
        self.RingBG:SetSize(22, 22)
        self.Ring:SetSize(22, 22)
        self.RingBG:SetAlpha(1)
        self.Ring:SetAlpha(1)
        self.RingBG:SetBlendMode("BLEND")
        self.Ring:SetBlendMode("BLEND")
    end

    self.RingBG:SetShown(isActive)
    self.Ring:SetShown(isActive)

    -- [6] Reward Selection
    local showReward = false
	if hasItem then
		local _, texture, _, _, _, itemID = GetQuestLogRewardInfo(1, questID)
		if C_Item.IsAnimaItemByID(itemID) then texture = 3528287 end
		self.Reward:SetTexture(texture)
		showReward = true
	elseif hasCurrency then
		self.Reward:SetTexture(currencyRewards[1].texture)
		showReward = true
	elseif hasMoney then
		self.Reward:SetTexture([[Interface\Icons\INV_MISC_COIN_01]])
		showReward = true
	end
    
    self.Reward:SetShown(showReward)
    self.Display.Icon:SetShown(not showReward and tagInfo ~= nil)

	-- [7] Type Indicators (PvP, Profession, etc)
    local hasIndicator = false
    local factionGroup = UnitFactionGroup('player')
    local factionAtlas = factionGroup == 'Horde' and 'worldquest-icon-horde' or 'worldquest-icon-alliance'

    if tagInfo.worldQuestType == Enum.QuestTagType.PvP then
        self.Indicator:SetAtlas('Warfronts-BaseMapIcons-Empty-Barracks-Minimap')
        self.Indicator:SetSize(18, 18)
        hasIndicator = true
    elseif tagInfo.worldQuestType == Enum.QuestTagType.PetBattle then
        self.Indicator:SetAtlas('WildBattlePetCapturable')
        self.Indicator:SetSize(10, 10)
        hasIndicator = true
    elseif tagInfo.worldQuestType == Enum.QuestTagType.Profession then
        self.Indicator:SetAtlas(WORLD_QUEST_ICONS_BY_PROFESSION[tagInfo.tradeskillLineID] or 'worldquest-icon-engineering')
        self.Indicator:SetSize(10, 10)
        hasIndicator = true
    elseif tagInfo.worldQuestType == Enum.QuestTagType.Dungeon then
        self.Indicator:SetAtlas('Dungeon')
        self.Indicator:SetSize(20, 20)
        hasIndicator = true
    elseif tagInfo.worldQuestType == Enum.QuestTagType.Raid then
        self.Indicator:SetAtlas('Raid')
        self.Indicator:SetSize(20, 20)
        hasIndicator = true
    elseif tagInfo.worldQuestType == Enum.QuestTagType.Invasion then
        self.Indicator:SetAtlas('worldquest-icon-burninglegion')
        self.Indicator:SetSize(10, 10)
        hasIndicator = true
    elseif tagInfo.worldQuestType == Enum.QuestTagType.FactionAssault then
        self.Indicator:SetAtlas(factionAtlas)
        self.Indicator:SetSize(10, 10)
        hasIndicator = true
    end
    self.Indicator:SetShown(hasIndicator)

	-- [8] Extra States (Bounty, Watched Rep)
	local bountyID = self.dataProvider:GetBountyInfo()
	self.Bounty:SetShown(bountyID and C_QuestLog.IsQuestCriteriaForBounty(questID, bountyID))

	local _, factionID = C_TaskQuest.GetQuestInfoByQuestID(questID)
    local isWatched = false
	if factionID then
		local factInfo = C_Reputation.GetFactionDataByID(factionID)
		isWatched = factInfo and factInfo.isWatched
	end
    self.Reputation:SetShown(isWatched)
end

function muteCatWQPinMixin:AddIconWidgets()
	-- Cleaned: Removed blizzard default glows
end

function muteCatWQPinMixin:SetPassThroughButtons()
	-- Bug workaround for map interactions
end
