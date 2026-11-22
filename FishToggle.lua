-- FishToggle: a minimap button that swaps your weapons for a fishing pole and back.
--   Left-click   equip the best fishing pole in your bags / put your weapons back on
--   Right-click  cast Fishing
--   Drag         move the button around the minimap
--   Space        while the pole is on: cast Fishing, and press again to catch the fish
--                (/fishtoggle space turns this on/off)
-- The weapons you wore are remembered per character, also across logouts.

local MAIN = INVSLOT_MAINHAND or 16
local OFF = INVSLOT_OFFHAND or 17
local WEAPON_CLASS = Enum.ItemClass and Enum.ItemClass.Weapon or 2
local POLE_SUBCLASS = Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole or 20
local FISHING_SPELL = 7620
local SWAP_SETTLE = 1.5	-- seconds to ignore equipment events while a swap is in progress

local db, char
local swapping = false

local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local EquipItemByName = C_Item and C_Item.EquipItemByName or EquipItemByName
local GetNumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetItemLink = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
local GetSpellName = C_Spell and C_Spell.GetSpellName or function(id) return (GetSpellInfo(id)) end

local function Print(msg)
	print("|cff40c0ffFishToggle:|r " .. msg)
end

-- ** Gear **

local function IsPole(item)
	if not item then return false end
	local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(item)
	return classID == WEAPON_CLASS and subclassID == POLE_SUBCLASS
end

local function PoleEquipped()
	return IsPole(GetInventoryItemID("player", MAIN))
end

-- Highest item level pole in the bags (better poles have higher item level)
local function FindPole()
	local best, bestLevel
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, GetNumSlots(bag) or 0 do
			local link = GetItemLink(bag, slot)
			if link and IsPole(link) then
				local level = select(4, GetItemInfo(link)) or 0
				if not best or level > bestLevel then
					best, bestLevel = link, level
				end
			end
		end
	end
	return best
end

-- Called on equipment changes: whatever is worn while no pole is equipped are the normal weapons
local function RememberWeapons()
	if swapping or not char or PoleEquipped() then return end
	char.main = GetInventoryItemLink("player", MAIN)
	char.off = GetInventoryItemLink("player", OFF)
end

local UpdateButton

local function EndSwap(check)
	C_Timer.After(SWAP_SETTLE, function()
		swapping = false
		RememberWeapons()
		if check then check() end
		UpdateButton()
	end)
end

local function StartFishing()
	local pole = FindPole()
	if not pole then
		Print("no fishing pole in your bags.")
		return
	end
	RememberWeapons()
	swapping = true
	EquipItemByName(pole, MAIN)
	EndSwap(function()
		if not PoleEquipped() then Print("could not equip the fishing pole.") end
	end)
end

local function StopFishing()
	if not char.main and not char.off then
		Print("don't know your weapons yet - equip them by hand once, then this button can swap back.")
		return
	end
	swapping = true
	if char.main then EquipItemByName(char.main, MAIN) end
	-- the off hand has to wait until the main hand is in place (a two-handed pole blocks it)
	if char.off then
		C_Timer.After(0.4, function() EquipItemByName(char.off, OFF) end)
	end
	EndSwap(function()
		if PoleEquipped() then
			Print("could not find your weapons in your bags.")
		end
	end)
end

local function Toggle()
	if swapping then return end
	if PoleEquipped() then StopFishing() else StartFishing() end
end

-- ** Overlay **
-- A banner that is shown exactly while Space is bound to fishing. Drag it to move it.

-- Classic zone reference levels (base fishing difficulty + 95), matching
-- OpenMap/Data/Forever/Fishing.lua; source: cmangos/classic-db.
-- These are catch-rate targets, not the minimum skill needed to cast.
-- Custom Forever zones and individual waters may have different requirements.
local zoneFishingLevel = {
	[1411] = 25, [1412] = 25, [1413] = 75,
	[1416] = 225, [1417] = 225, [1420] = 25, [1421] = 75,
	[1422] = 300, [1423] = 425, [1424] = 150, [1425] = 300,
	[1426] = 25, [1428] = 425, [1429] = 25, [1430] = 425,
	[1431] = 150, [1432] = 75, [1433] = 150, [1434] = 225,
	[1435] = 225, [1436] = 75, [1437] = 150, [1438] = 25,
	[1439] = 75, [1440] = 150, [1441] = 225, [1442] = 150,
	[1443] = 225, [1444] = 300, [1445] = 225, [1446] = 300,
	[1447] = 300, [1448] = 300, [1449] = 300, [1450] = 300,
	[1451] = 425, [1452] = 425, [1453] = 75, [1454] = 75,
	[1455] = 75, [1456] = 75, [1457] = 75, [1458] = 75,
}

local function FishingSkill()
	-- Forever's structured profession API includes equipped and temporary bonuses.
	if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
		local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(356)
		if info and info.skillLevel and info.skillLevel > 0 and info.skillModifier then
			return info.skillLevel, info.skillModifier
		end
	end
	if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
		local info = C_SkillInfo.GetSkillLineInfoByID(356)
		if info and info.rank and info.rank > 0 and info.modifier then
			return info.rank, info.modifier
		end
	end
	if GetProfessions and GetProfessionInfo then
		local _, _, _, fishing = GetProfessions()
		if fishing then
			local _, _, rank, _, _, _, _, bonus = GetProfessionInfo(fishing)
			return rank, bonus or 0
		end
	end
	return nil, nil
end

local function FishingZoneLevel()
	if not C_Map or not C_Map.GetBestMapForUnit then return end
	-- Do not consult the map currently being browsed by the player.
	local mapID = C_Map.GetBestMapForUnit("player")
	return mapID and zoneFishingLevel[mapID]
end

local overlay = CreateFrame("Frame", "FishToggleOverlay", UIParent, "BackdropTemplate")
overlay:SetSize(340, 72)
overlay:SetFrameStrata("HIGH")
overlay:SetClampedToScreen(true)
overlay:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
overlay:SetBackdropColor(0, 0.08, 0.16, 0.85)
overlay:SetBackdropBorderColor(0.25, 0.75, 1)
overlay:SetMovable(true)
overlay:EnableMouse(true)
overlay:RegisterForDrag("LeftButton")
overlay:Hide()

local overlayIcon = overlay:CreateTexture(nil, "ARTWORK")
overlayIcon:SetSize(34, 34)
overlayIcon:SetPoint("LEFT", 8, 0)
overlayIcon:SetTexture("Interface\\Icons\\Trade_Fishing")
overlayIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local overlayTitle = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
overlayTitle:SetPoint("TOPLEFT", overlay, "TOPLEFT", 50, -8)
overlayTitle:SetText("Fishing active")
overlayTitle:SetTextColor(0.4, 0.8, 1)

local overlayHint = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
overlayHint:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 50, 8)

local overlaySkill = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
overlaySkill:SetPoint("TOPLEFT", overlayTitle, "BOTTOMLEFT", 0, -5)

local function UpdateFishingSkill()
	local rank, bonus = FishingSkill()
	local level = FishingZoneLevel()
	local text = string.format("%s + %s / %s", rank or "?", bonus or "?", level or "?")
	if overlaySkill:GetText() ~= text then overlaySkill:SetText(text) end
end

-- Only runs while the banner is visible. Polling also catches lure expiration
-- and bonus changes that do not produce an equipment-change event.
local skillElapsed = 0
overlay:SetScript("OnUpdate", function(_, elapsed)
	skillElapsed = skillElapsed + elapsed
	if skillElapsed >= 0.5 then
		skillElapsed = 0
		UpdateFishingSkill()
	end
end)

-- the border pulses while the bobber is out, so you know the next Space press catches
local pulse = overlay:CreateAnimationGroup()
pulse:SetLooping("BOUNCE")
local fade = pulse:CreateAnimation("Alpha")
fade:SetFromAlpha(1)
fade:SetToAlpha(0.55)
fade:SetDuration(0.6)

overlay:SetScript("OnDragStart", overlay.StartMoving)
overlay:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, relPoint, x, y = self:GetPoint()
	db.overlayPoint = { point, relPoint, x, y }
end)

local function PositionOverlay()
	overlay:ClearAllPoints()
	local p = db.overlayPoint
	if p then
		overlay:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		overlay:SetPoint("TOP", UIParent, "TOP", 0, -140)
	end
end

local channeling = false

local function ShowOverlay(active)
	if not active then
		pulse:Stop()
		overlay:Hide()
		return
	end
	if channeling then
		overlayHint:SetText("|cffffd100Space|r: catch the fish (wait for the splash)")
		if not pulse:IsPlaying() then pulse:Play() end
	else
		overlayHint:SetText("|cffffd100Space|r: cast Fishing")
		pulse:Stop()
		overlay:SetAlpha(1)
	end
	UpdateFishingSkill()
	overlay:Show()
end

-- ** Space bar fishing **
-- While the pole is on, Space clicks the minimap button with the right button (= cast Fishing).
-- While Fishing is channeling, Space interacts with the soft-targeted bobber (= catch the fish).
-- When the pole comes off, the override is cleared and Space jumps again.

local KEY = "SPACE"
local bindOwner = CreateFrame("Frame")
local bindPending = false
local fishingName

local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar
local SetCVar = C_CVar and C_CVar.SetCVar or SetCVar

-- Soft targeting has to reach the bobber, which lands well out in front of you.
-- { name, value, exact }: exact = set to this value, otherwise raise to at least this value.
local CVARS = {
	{ "softTargetInteract", 3, true },	-- 3 = any (Enum.SoftTargetEnableFlags.Any)
	{ "SoftTargetInteractArc", 2 },
	{ "SoftTargetInteractRange", 30 },
	-- Let the client anchor its interaction gear to the targeted bobber in 3D.
	{ "SoftTargetIconInteract", 1, true },
	{ "SoftTargetIconGameObject", 1, true },
}

-- The original values are kept in db.cvars until restored, so they survive a logout with the pole on
local function ApplyCVars()
	db.cvars = db.cvars or {}
	for _, c in ipairs(CVARS) do
		local name, want, exact = c[1], c[2], c[3]
		local current = tonumber(GetCVar(name))
		if current and ((exact and current ~= want) or (not exact and current < want)) then
			if db.cvars[name] == nil then db.cvars[name] = current end
			SetCVar(name, tostring(want))
		end
	end
end

local function RestoreCVars()
	if not db.cvars then return end
	for name, old in pairs(db.cvars) do SetCVar(name, tostring(old)) end
	db.cvars = nil
end

local function IsFishingSpell(spellID)
	if spellID == FISHING_SPELL then return true end
	fishingName = fishingName or GetSpellName(FISHING_SPELL)
	return spellID and fishingName and GetSpellName(spellID) == fishingName
end

-- Bindings and these CVars can't be changed in combat; the update waits for PLAYER_REGEN_ENABLED
local function UpdateBinding()
	if not db then return end
	if InCombatLockdown() then
		bindPending = true
		return
	end
	bindPending = false
	ClearOverrideBindings(bindOwner)
	if not db.space or not PoleEquipped() then
		RestoreCVars()
		ShowOverlay(false)
		return
	end
	ApplyCVars()
	if channeling then
		SetOverrideBinding(bindOwner, true, KEY, "INTERACTTARGET")
	else
		SetOverrideBindingClick(bindOwner, true, KEY, "FishToggleMinimapButton", "RightButton")
	end
	ShowOverlay(true)
end

-- ** Minimap button **
-- A secure button so right-click can cast Fishing; left-click is handled by our own code.

local button = CreateFrame("Button", "FishToggleMinimapButton", Minimap, "SecureActionButtonTemplate")
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
-- both, so the secure cast works whatever the "cast on key down" setting is; our toggle only reacts on release
button:RegisterForClicks("AnyUp", "AnyDown")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local background = button:CreateTexture(nil, "BACKGROUND")
background:SetSize(20, 20)
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
background:SetPoint("TOPLEFT", 7, -5)

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetSize(20, 20)
icon:SetPoint("TOPLEFT", 7, -5)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

local function UpdatePosition()
	local angle = math.rad(db.angle or 200)
	local radius = Minimap:GetWidth() / 2 + 10
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- Shows the fishing icon normally, and your weapon's icon while fishing (that is what a click gives you)
UpdateButton = function()
	if PoleEquipped() then
		local weapon = char and char.main
		icon:SetTexture(weapon and C_Item.GetItemIconByID(weapon) or "Interface\\Icons\\INV_Sword_04")
	else
		icon:SetTexture("Interface\\Icons\\Trade_Fishing")
	end
end

local lastDrag = 0

button:SetScript("OnDragStart", function(self)
	if InCombatLockdown() then return end	-- a secure button can't move in combat
	self:SetScript("OnUpdate", function()
		if InCombatLockdown() then
			self:SetScript("OnUpdate", nil)
			return
		end
		local mx, my = Minimap:GetCenter()
		local scale = Minimap:GetEffectiveScale()
		local px, py = GetCursorPosition()
		db.angle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
		UpdatePosition()
	end)
end)

button:SetScript("OnDragStop", function(self)
	self:SetScript("OnUpdate", nil)
	lastDrag = GetTime()
end)

button:HookScript("OnClick", function(_, mouseButton, down)
	if mouseButton == "LeftButton" and not down and GetTime() - lastDrag > 0.2 then Toggle() end
end)

button:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("FishToggle")
	if PoleEquipped() then
		GameTooltip:AddLine("Fishing pole equipped", 0.4, 1, 0.4)
		GameTooltip:AddDoubleLine("Left-click", "Equip your weapons", 1, 0.82, 0, 1, 1, 1)
	else
		GameTooltip:AddDoubleLine("Left-click", "Equip fishing pole", 1, 0.82, 0, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine("Right-click", "Cast Fishing", 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine("Drag", "Move button", 1, 0.82, 0, 1, 1, 1)
	if db and db.space then
		GameTooltip:AddDoubleLine("Space (pole on)", "Cast / catch fish", 1, 0.82, 0, 1, 1, 1)
	end
	if char and char.main then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Your weapons:", 0.7, 0.7, 0.7)
		GameTooltip:AddLine(char.main)
		if char.off then GameTooltip:AddLine(char.off) end
	end
	GameTooltip:Show()
end)
button:SetScript("OnLeave", GameTooltip_Hide)

-- ** Events **

-- Secure attributes and positioning can't be changed in combat (e.g. a /reload mid-fight)
local function SetupSecure()
	button:SetAttribute("type2", "spell")	-- right-click casts Fishing, any rank, by name
	button:SetAttribute("spell2", GetSpellName(FISHING_SPELL) or "Fishing")
	UpdatePosition()
end

local securePending = false

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1, _, spellID)
	if event == "PLAYER_LOGIN" then
		FishToggleDB = FishToggleDB or {}
		FishToggleCharDB = FishToggleCharDB or {}
		db, char = FishToggleDB, FishToggleCharDB
		if db.space == nil then db.space = true end
		PositionOverlay()

		if InCombatLockdown() then
			securePending = true
		else
			SetupSecure()
		end
		RememberWeapons()
		UpdateButton()
		UpdateBinding()

		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
		self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
		self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
	elseif event == "PLAYER_REGEN_ENABLED" then
		if securePending then
			securePending = false
			SetupSecure()
		end
		if bindPending then UpdateBinding() end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" and (arg1 == MAIN or arg1 == OFF) then
		RememberWeapons()
		UpdateButton()
		UpdateBinding()
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" and IsFishingSpell(spellID) then
		channeling = true
		UpdateBinding()
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" and channeling then
		channeling = false
		UpdateBinding()
	end
end)

SLASH_FISHTOGGLE1 = "/fishtoggle"
SlashCmdList.FISHTOGGLE = function(msg)
	if not db then return end
	if msg:lower():match("^%s*space") then
		db.space = not db.space
		UpdateBinding()
		Print("Space for cast / catch is now " .. (db.space and "|cff40ff40on|r" or "|cffff4040off|r") .. ".")
	else
		Print("/fishtoggle space - turn Space for cast / catch on or off")
	end
end
