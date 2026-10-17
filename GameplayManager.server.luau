--!strict
-- ServerScriptService > GameplayManager
-- Central authoritative server manager for Steal an Anime Egg:
--   1. Real pen assignment & ownership lifecycle (Pen 1..Pen 7)
--   2. 50-stud overhead display above pen: Player Avatar image & Name below in white with black border
--   3. Strength training area: Tagged with OwnerUserId & IsTraining (hidden for others UNTIL in use!)
--   4. Auto-training on stepping on dumbbell/pad & leave by jumping
--   5. World Eggs: Multiple size tiers (Small, Medium, Large, Giant) - bigger eggs require more Strength & slow player down!
--   6. RedLine egg claiming: Crossing RedLine deposits egg into player INVENTORY (not directly into pen)
--   7. Placing egg into pen: Player places egg from inventory onto pen platform slots
--   8. Non-colliding eggs & player characters (PhysicsService character collision group)
--   9. Hatched characters (Lee) strictly contained inside pen (boundary walls & AI clamp)
--  10. Authoritative 1,000 Money/sec income ticker

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")

-- Load Gameplay Configuration
local GameplayConfig
local okConfig, cfg = pcall(function()
	return require(ReplicatedStorage:WaitForChild("GameplayConfig", 3) :: any)
end)
if okConfig and cfg then
	GameplayConfig = cfg
else
	GameplayConfig = {
		Training = {
			AreaSize = Vector3.new(10, 0.4, 10),
			DefaultStrengthGain = 1,
			Cooldown = 0.8,
			JumpExitDebounce = 1.2,
			ExitJumpImpulse = 38,
			PadLabel = "🏋️ STRENGTH TRAINING",
		},
		Dumbbells = {
			dumbel1 = { Name = "Light Dumbbell", StrengthGain = 1, RequiredStrength = 0, Cooldown = 0.8, UpgradeCost = 5000 },
			dumbel2 = { Name = "Medium Dumbbell", StrengthGain = 5, RequiredStrength = 25, Cooldown = 0.8, UpgradeCost = 25000 },
			dumbel3 = { Name = "Heavy Dumbbell", StrengthGain = 20, RequiredStrength = 100, Cooldown = 0.8, UpgradeCost = 0 },
		},
		Eggs = {
			EggsPerSpawn = 10,
			Zone1SpawnCount = 10,
			Zone1RequiredStrength = 0,
			MaxPlacedCapacity = 30,
			BaseHatchDuration = 12,
			PromptAction = "Steal Egg",
			PromptObject = "Anime Egg",
			MaxSpawnAttempts = 15,
			BarrierSafetyBuffer = 5,
		},
		EggSizes = {
			Small = { Name = "Small Egg", Scale = 0.9, RequiredStrength = 0, SpeedMultiplier = 1.0, Weight = 40 },
			Medium = { Name = "Medium Egg", Scale = 1.35, RequiredStrength = 0, SpeedMultiplier = 0.75, Weight = 30 },
			Large = { Name = "Large Egg", Scale = 1.85, RequiredStrength = 0, SpeedMultiplier = 0.55, Weight = 20 },
			Giant = { Name = "Giant Egg", Scale = 2.4, RequiredStrength = 0, SpeedMultiplier = 0.38, Weight = 10 },
		},
		Pets = {
			BaseEquippedLimit = 6,
			MaxUpgradeLevel = 5,
			Lee = {
				Name = "Rock Lee",
				IncomePerSecond = 1000,
				WalkAnimationId = "",
				WalkSpeed = 10,
				MinWanderWait = 2,
				MaxWanderWait = 5,
			},
		},
		Pens = {
			OverheadHeightOffset = 50,
			MaxDisplayDistance = 350,
		},
	}
end

-- Ensure TrainingAction RemoteEvent exists for client jump input
local trainingActionRemote = ReplicatedStorage:FindFirstChild("TrainingAction") :: RemoteEvent?
if not trainingActionRemote then
	trainingActionRemote = Instance.new("RemoteEvent")
	trainingActionRemote.Name = "TrainingAction"
	trainingActionRemote.Parent = ReplicatedStorage
end

-- Ensure DropEggAction RemoteEvent exists for drop button & Q keybind
local dropEggRemote = ReplicatedStorage:FindFirstChild("DropEggAction") :: RemoteEvent?
if not dropEggRemote then
	dropEggRemote = Instance.new("RemoteEvent")
	dropEggRemote.Name = "DropEggAction"
	dropEggRemote.Parent = ReplicatedStorage
end

-- Ensure PlaceEggAtLocation RemoteEvent exists for tapping anywhere in pen to place egg
local placeEggAtLocationRemote = ReplicatedStorage:FindFirstChild("PlaceEggAtLocation") :: RemoteEvent?
if not placeEggAtLocationRemote then
	placeEggAtLocationRemote = Instance.new("RemoteEvent")
	placeEggAtLocationRemote.Name = "PlaceEggAtLocation"
	placeEggAtLocationRemote.Parent = ReplicatedStorage
end

-- Ensure UpgradeDumbbellAction RemoteEvent exists for sign button clicks
local upgradeDumbbellRemote = ReplicatedStorage:FindFirstChild("UpgradeDumbbellAction") :: RemoteEvent?
if not upgradeDumbbellRemote then
	upgradeDumbbellRemote = Instance.new("RemoteEvent")
	upgradeDumbbellRemote.Name = "UpgradeDumbbellAction"
	upgradeDumbbellRemote.Parent = ReplicatedStorage
end

-- Ensure UpgradePenAction RemoteEvent exists for pen upgrade sign interactions
local upgradePenRemote = ReplicatedStorage:FindFirstChild("UpgradePenAction") :: RemoteEvent?
if not upgradePenRemote then
	upgradePenRemote = Instance.new("RemoteEvent")
	upgradePenRemote.Name = "UpgradePenAction"
	upgradePenRemote.Parent = ReplicatedStorage
end

-- Cooldown and debounce trackers for client-triggered actions
local lastUpgradeTime: { [Player]: number } = {}
local lastPlaceTime: { [Player]: number } = {}
local lastDropTime: { [Player]: number } = {}
local lastPickupTime: { [Player]: number } = {}

--------------------------------------------------------------------------------
-- 1. NON-COLLIDING CHARACTERS SETUP (PHYSICSSERVICE)
--------------------------------------------------------------------------------
local CHAR_COLLISION_GROUP = "GameCharacters"
local PET_COLLISION_GROUP = "GamePets"
pcall(function()
	PhysicsService:RegisterCollisionGroup(CHAR_COLLISION_GROUP)
	PhysicsService:RegisterCollisionGroup(PET_COLLISION_GROUP)
	-- Player characters do not collide with other characters
	PhysicsService:CollisionGroupSetCollidable(CHAR_COLLISION_GROUP, CHAR_COLLISION_GROUP, false)
	-- Pets do not collide with player characters or other pets
	PhysicsService:CollisionGroupSetCollidable(PET_COLLISION_GROUP, CHAR_COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(CHAR_COLLISION_GROUP, PET_COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(PET_COLLISION_GROUP, PET_COLLISION_GROUP, false)
end)

local function makeCharacterNonColliding(char: Model)
	for _, desc in ipairs(char:GetDescendants()) do
		if desc:IsA("BasePart") then
			pcall(function()
				desc.CollisionGroup = CHAR_COLLISION_GROUP
			end)
		end
	end
	char.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			pcall(function()
				desc.CollisionGroup = CHAR_COLLISION_GROUP
			end)
		end
	end)
end

Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(makeCharacterNonColliding)
	if p.Character then
		makeCharacterNonColliding(p.Character)
	end
end)
for _, p in ipairs(Players:GetPlayers()) do
	if p.Character then
		makeCharacterNonColliding(p.Character)
	end
end

--------------------------------------------------------------------------------
-- 2. FLOATING NOTIFICATION / FEEDBACK HELPER
--------------------------------------------------------------------------------
local function showFloatingFeedback(position: Vector3, text: string, color: Color3)
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = position + Vector3.new(0, 1.5, 0)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = Workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(280, 48)
	bb.StudsOffset = Vector3.new(0, 1, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = part
	bb.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 20
	label.TextColor3 = color
	label.Text = text
	label.Parent = bb

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2.5
	stroke.Parent = label

	local targetCFrame = part.CFrame + Vector3.new(0, 2.5, 0)
	local tweenInfo = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(part, tweenInfo, { CFrame = targetCFrame })
	tween:Play()

	task.delay(0.6, function()
		if label and label.Parent then
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
	end)

	Debris:AddItem(part, 1.2)
end

--------------------------------------------------------------------------------
-- 3. PEN DISCOVERY, 50-STUD OVERHEAD AVATAR & TRAINING AREA SETUP
--------------------------------------------------------------------------------
type PenInfo = {
	Index: number,
	Model: Model,
	EggArea: BasePart,
	Sign: Model?,
	Owner: Player?,
	ForwardDir: Vector3,
	EntranceCenter: Vector3?,
	TrainingArea: Model?,
	TrainingPad: BasePart?,
	TrainingDumbbell: Model?,
	DumbbellTier: number?,
	UpgradeSign: Model?,
	PenSign: Model?,
	UpdateSignDisplay: (() -> ())?,
	UpdatePenUpgradeDisplay: (() -> ())?,
	PerformUpgrade: ((Player) -> ())?,
	OverheadGui: BillboardGui?,
	OverheadAvatar: ImageLabel?,
	OverheadLabel: TextLabel?,
	HomeMarkerAnchor: BasePart?,
	HomeMarkerGui: BillboardGui?,
	HomeMarkerLabel: TextLabel?,
	Slots: { [number]: { Type: string, Model: Model, HatchThread: thread? } },
	FenceVisuals: Folder?,
	VisualLevel: number?,
	DefaultFences: Folder?,
}

local pensList: { PenInfo } = {}
local playerPenMap: { [Player]: PenInfo } = {}

local applyPenVisualLevel: (PenInfo, number) -> ()
local configurePetCollisions: (Model) -> ()

-- Clean up legacy billboard attached to physical signs
local function cleanupPhysicalSign(signModel: Model?)
	if not signModel then return end
	for _, desc in ipairs(signModel:GetDescendants()) do
		if desc:IsA("BillboardGui") and (desc.Name == "PenSignGui" or desc.Name:find("Sign")) then
			desc:Destroy()
		end
	end
end

-- Create or update the 50-stud overhead player avatar image and name display
local function setupPenOverheadDisplay(penInfo: PenInfo)
	local cf, size = penInfo.Model:GetBoundingBox()
	local topY = cf.Position.Y + (size.Y / 2)
	local targetY = topY + GameplayConfig.Pens.OverheadHeightOffset -- Exactly 50 studs above top of pen!

	local existingAnchor = penInfo.Model:FindFirstChild("PenOverheadAnchor") :: BasePart?
	if existingAnchor then
		existingAnchor:Destroy()
	end

	cleanupPhysicalSign(penInfo.Sign)

	local anchor = Instance.new("Part")
	anchor.Name = "PenOverheadAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(cf.Position.X, targetY, cf.Position.Z)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Parent = penInfo.Model

	local bb = Instance.new("BillboardGui")
	bb.Name = "PenOverheadGui"
	bb.Size = UDim2.fromOffset(200, 130)
	bb.StudsOffset = Vector3.new(0, 0, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = GameplayConfig.Pens.MaxDisplayDistance
	bb.Adornee = anchor
	bb.Enabled = false -- Hidden when unowned
	bb.Parent = anchor

	-- 1. Circular Player Avatar Image at Top
	local avatarImg = Instance.new("ImageLabel")
	avatarImg.Name = "OwnerAvatarImage"
	avatarImg.AnchorPoint = Vector2.new(0.5, 0)
	avatarImg.Position = UDim2.new(0.5, 0, 0, 0)
	avatarImg.Size = UDim2.fromOffset(68, 68)
	avatarImg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	avatarImg.BackgroundTransparency = 0
	avatarImg.Image = ""
	avatarImg.Parent = bb

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatarImg

	local avatarStroke = Instance.new("UIStroke")
	avatarStroke.Color = Color3.fromRGB(0, 0, 0)
	avatarStroke.Thickness = 3
	avatarStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	avatarStroke.Parent = avatarImg

	-- 2. Player Name Below in White Font with Black Border
	local label = Instance.new("TextLabel")
	label.Name = "OwnerNameLabel"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 74)
	label.Size = UDim2.new(1, 0, 0, 34)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 22
	label.TextColor3 = Color3.fromRGB(255, 255, 255) -- White font
	label.Text = ""
	label.ClipsDescendants = false
	label.Parent = bb

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0) -- Black border
	stroke.Thickness = 3.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label

	penInfo.OverheadGui = bb
	penInfo.OverheadAvatar = avatarImg
	penInfo.OverheadLabel = label

	-- Floating Home Marker: positioned at topY + 12 studs (floating cleanly above pen fence, below 50-stud overhead avatar)
	local existingHomeAnchor = penInfo.Model:FindFirstChild("PenHomeMarkerAnchor") :: BasePart?
	if existingHomeAnchor then
		existingHomeAnchor:Destroy()
	end

	local homeAnchor = Instance.new("Part")
	homeAnchor.Name = "PenHomeMarkerAnchor"
	homeAnchor.Size = Vector3.new(0.5, 0.5, 0.5)
	homeAnchor.CFrame = CFrame.new(cf.Position.X, topY + 12, cf.Position.Z)
	homeAnchor.Transparency = 1
	homeAnchor.Anchored = true
	homeAnchor.CanCollide = false
	homeAnchor.CanTouch = false
	homeAnchor.CanQuery = false
	homeAnchor.Parent = penInfo.Model

	local homeGui = Instance.new("BillboardGui")
	homeGui.Name = "PenHomeMarkerGui"
	homeGui.Size = UDim2.fromOffset(140, 36)
	homeGui.StudsOffset = Vector3.new(0, 0, 0)
	homeGui.AlwaysOnTop = true
	homeGui.MaxDistance = 250
	homeGui.Adornee = homeAnchor
	homeGui.Enabled = false -- Hidden when unowned
	homeGui.Parent = homeAnchor

	local homeBadge = Instance.new("Frame")
	homeBadge.Name = "HomeBadge"
	homeBadge.Size = UDim2.fromScale(1, 1)
	homeBadge.BackgroundColor3 = Color3.fromRGB(35, 175, 75)
	homeBadge.BackgroundTransparency = 0.15
	homeBadge.Parent = homeGui

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)
	badgeCorner.Parent = homeBadge

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = Color3.fromRGB(0, 0, 0)
	badgeStroke.Thickness = 2.5
	badgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	badgeStroke.Parent = homeBadge

	local homeText = Instance.new("TextLabel")
	homeText.Name = "HomeText"
	homeText.Size = UDim2.fromScale(1, 1)
	homeText.BackgroundTransparency = 1
	homeText.Font = Enum.Font.FredokaOne
	homeText.TextSize = 16
	homeText.TextColor3 = Color3.fromRGB(255, 255, 255)
	homeText.Text = "🏠 YOUR PEN"
	homeText.Parent = homeBadge

	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(0, 0, 0)
	textStroke.Thickness = 2.5
	textStroke.Parent = homeText

	penInfo.HomeMarkerAnchor = homeAnchor
	penInfo.HomeMarkerGui = homeGui
	penInfo.HomeMarkerLabel = homeText
end

local function updatePenOwnerDisplay(penInfo: PenInfo, owner: Player?)
	local ownerUserId = owner and owner.UserId or 0
	local ownerName = owner and owner.Name or ""
	local penLevel = (owner and _G.PlayerData and _G.PlayerData.getPenUpgradeLevel and _G.PlayerData.getPenUpgradeLevel(owner)) or 0
	penLevel = math.clamp(tonumber(penLevel) or 0, 0, 5)

	penInfo.Model:SetAttribute("OwnerUserId", ownerUserId)
	penInfo.Model:SetAttribute("OwnerName", ownerName)
	penInfo.Model:SetAttribute("PenUpgradeLevel", penLevel)
	penInfo.Model:SetAttribute("EquippedPetLimit", 6 + penLevel)

	if penInfo.TrainingArea then
		penInfo.TrainingArea:SetAttribute("OwnerUserId", ownerUserId)
		penInfo.TrainingArea:SetAttribute("OwnerName", ownerName)
		penInfo.TrainingArea:SetAttribute("DumbbellTier", penInfo.DumbbellTier or 1)
	end
	if penInfo.TrainingPad then
		penInfo.TrainingPad:SetAttribute("OwnerUserId", ownerUserId)
		penInfo.TrainingPad:SetAttribute("OwnerName", ownerName)
	end
	if penInfo.TrainingDumbbell then
		penInfo.TrainingDumbbell:SetAttribute("OwnerUserId", ownerUserId)
		penInfo.TrainingDumbbell:SetAttribute("OwnerName", ownerName)
		if owner then
			for _, p in ipairs(penInfo.TrainingDumbbell:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Transparency = 0
				end
			end
		end
	end
	if penInfo.UpgradeSign then
		penInfo.UpgradeSign:SetAttribute("OwnerUserId", ownerUserId)
		penInfo.UpgradeSign:SetAttribute("OwnerName", ownerName)
		for _, d in ipairs(penInfo.UpgradeSign:GetDescendants()) do
			if d:IsA("BasePart") then
				d:SetAttribute("OwnerUserId", ownerUserId)
				d:SetAttribute("OwnerName", ownerName)
			end
		end
	end
	if penInfo.PenSign then
		penInfo.PenSign:SetAttribute("OwnerUserId", ownerUserId)
		penInfo.PenSign:SetAttribute("OwnerName", ownerName)
		for _, d in ipairs(penInfo.PenSign:GetDescendants()) do
			if d:IsA("BasePart") then
				d:SetAttribute("OwnerUserId", ownerUserId)
				d:SetAttribute("OwnerName", ownerName)
			end
		end
	end

	if penInfo.UpdatePenUpgradeDisplay then
		penInfo.UpdatePenUpgradeDisplay()
	end

	if penInfo.OverheadGui and penInfo.OverheadLabel and penInfo.OverheadAvatar then
		if owner then
			local thumbUrl = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", owner.UserId)
			penInfo.OverheadAvatar.Image = thumbUrl
			penInfo.OverheadLabel.Text = owner.DisplayName
			penInfo.OverheadGui.Enabled = true
		else
			penInfo.OverheadAvatar.Image = ""
			penInfo.OverheadLabel.Text = ""
			penInfo.OverheadGui.Enabled = false
		end
	end

	if penInfo.HomeMarkerGui and penInfo.HomeMarkerLabel then
		if owner then
			penInfo.HomeMarkerLabel.Text = string.format("🏠 %s's Pen", owner.DisplayName)
			penInfo.HomeMarkerGui.Enabled = true
		else
			penInfo.HomeMarkerLabel.Text = ""
			penInfo.HomeMarkerGui.Enabled = false
		end
	end
end

--------------------------------------------------------------------------------
-- 4. AUTO-TRAINING & JUMP-TO-LEAVE SYSTEM
--------------------------------------------------------------------------------
type TrainingSession = {
	Pen: PenInfo,
	Active: boolean,
	Thread: thread?,
	StateConn: RBXScriptConnection?,
	JumpConn: RBXScriptConnection?,
}

local playerTrainingState: { [Player]: TrainingSession } = {}
local playerJumpExitTime: { [Player]: number } = {}

local function stopPlayerTraining(player: Player, jumped: boolean)
	local session = playerTrainingState[player]
	if not session then return end

	session.Active = false
	if session.Thread then
		task.cancel(session.Thread)
		session.Thread = nil
	end
	if session.StateConn then
		session.StateConn:Disconnect()
		session.StateConn = nil
	end
	if session.JumpConn then
		session.JumpConn:Disconnect()
		session.JumpConn = nil
	end

	playerTrainingState[player] = nil
	player:SetAttribute("IsTraining", false)

	-- Update Pen IsTraining attribute so other players' clients hide the pad/dumbbell again!
	if session.Pen then
		session.Pen.Model:SetAttribute("IsTraining", false)
		if session.Pen.TrainingArea then
			session.Pen.TrainingArea:SetAttribute("IsTraining", false)
		end
	end

	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			-- Restore player's normal WalkSpeed
			if _G.PlayerData and _G.PlayerData.applyWalkSpeed then
				_G.PlayerData.applyWalkSpeed(player)
			else
				hum.WalkSpeed = 16
			end
		end

		if jumped then
			playerJumpExitTime[player] = tick()
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				showFloatingFeedback(root.Position + Vector3.new(0, 2, 0), "💨 Jumped out!", Color3.fromRGB(255, 230, 80))
			end
		end
	end
end

local function startPlayerTraining(player: Player, penInfo: PenInfo)
	if penInfo.Owner ~= player then return end
	if playerTrainingState[player] then return end

	local now = tick()
	local lastExit = playerJumpExitTime[player] or 0
	local debounce = GameplayConfig.Training.JumpExitDebounce or 1.2
	if now - lastExit < debounce then
		return
	end

	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 then return end

	local pad = penInfo.TrainingPad
	if not pad then return end

	-- Lock walkspeed to 0 while training; player leaves by jumping
	hum.WalkSpeed = 0
	player:SetAttribute("IsTraining", true)

	-- Set Pen IsTraining attribute so other players' clients make the pad/dumbbell visible!
	penInfo.Model:SetAttribute("IsTraining", true)
	if penInfo.TrainingArea then
		penInfo.TrainingArea:SetAttribute("IsTraining", true)
	end

	local targetCenter = pad.Position + Vector3.new(0, 2.5, 0)
	local forward = penInfo.ForwardDir or Vector3.new(0, 0, 1)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = CFrame.lookAt(targetCenter, targetCenter + forward * 10)

	local session: TrainingSession = {
		Pen = penInfo,
		Active = true,
		Thread = nil,
		StateConn = nil,
		JumpConn = nil,
	}
	playerTrainingState[player] = session

	showFloatingFeedback(pad.Position + Vector3.new(0, 2.0, 0), "🏋️ Auto-Training! (Jump to leave)", Color3.fromRGB(80, 255, 120))

	-- 1. Automatic strength training loop (no tapping needed!)
	session.Thread = task.spawn(function()
		while session.Active and penInfo.Owner == player and player.Parent and hum.Health > 0 do
			local tier = penInfo.DumbbellTier or 1
			local gain = 1
			if tier == 1 then
				gain = (GameplayConfig.Dumbbells.dumbel1 and GameplayConfig.Dumbbells.dumbel1.StrengthGain) or 1
			elseif tier == 2 then
				gain = (GameplayConfig.Dumbbells.dumbel2 and GameplayConfig.Dumbbells.dumbel2.StrengthGain) or 5
			elseif tier == 3 then
				gain = (GameplayConfig.Dumbbells.dumbel3 and GameplayConfig.Dumbbells.dumbel3.StrengthGain) or 20
			end

			if _G.PlayerData and _G.PlayerData.addStrength then
				_G.PlayerData.addStrength(player, gain)
				showFloatingFeedback(pad.Position + Vector3.new(0, 2.8, 0), string.format("+%d Strength", gain), Color3.fromRGB(80, 255, 120))
			end
			task.wait(GameplayConfig.Training.Cooldown or 0.8)
		end
		if session.Active then
			stopPlayerTraining(player, false)
		end
	end)

	-- 2. Detect jumping to exit training
	session.StateConn = hum.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping then
			stopPlayerTraining(player, true)
		end
	end)

	session.JumpConn = hum.Jumping:Connect(function(isActive)
		if isActive then
			stopPlayerTraining(player, true)
		end
	end)
end

-- Client jump event trigger via RemoteEvent
trainingActionRemote.OnServerEvent:Connect(function(player: Player, action: any)
	if action == "Jump" and playerTrainingState[player] then
		stopPlayerTraining(player, true)
	end
end)

-- Forward declaration of placeEggFromInventory
local placeEggFromInventory: (player: Player, penInfo: PenInfo) -> boolean

local function getDumbbellPrototype(protoName: string): Model?
	local proto = Workspace:FindFirstChild(protoName) or ServerStorage:FindFirstChild(protoName)
	if not proto then
		for _, child in ipairs(Workspace:GetChildren()) do
			if child:IsA("Model") and child.Name:lower() == protoName:lower() then
				return child
			end
		end
		for _, child in ipairs(ServerStorage:GetChildren()) do
			if child:IsA("Model") and child.Name:lower() == protoName:lower() then
				return child
			end
		end
	end
	return (proto and proto:IsA("Model")) and proto or nil
end

local function getDumbbellUpgradeSignTemplate(tier: number): Model?
	local targetName = "dumbel up" .. tier
	local proto = Workspace:FindFirstChild(targetName) or ServerStorage:FindFirstChild(targetName)
	if not proto then
		for _, child in ipairs(Workspace:GetChildren()) do
			if child:IsA("Model") and child.Name:lower() == targetName:lower() then
				return child
			end
		end
		for _, child in ipairs(ServerStorage:GetChildren()) do
			if child:IsA("Model") and child.Name:lower() == targetName:lower() then
				return child
			end
		end
	end
	return (proto and proto:IsA("Model")) and proto or nil
end

local function getPenUpgradeSignTemplate(level: number): Model?
	local targetName = "pen up" .. level
	local proto = Workspace:FindFirstChild(targetName) or ServerStorage:FindFirstChild(targetName)
	if not proto then
		for _, child in ipairs(Workspace:GetChildren()) do
			if child:IsA("Model") and child.Name:lower() == targetName:lower() then
				return child
			end
		end
		for _, child in ipairs(ServerStorage:GetChildren()) do
			if child:IsA("Model") and child.Name:lower() == targetName:lower() then
				return child
			end
		end
	end
	return (proto and proto:IsA("Model")) and proto or nil
end

-- Ensures exactly one SurfaceGui exists on the sign board, placed strictly on the intended front face
local function setupSingleFrontSurfaceGui(boardPart: BasePart, targetApproachDir: Vector3)
	-- Remove any duplicate SurfaceGuis left from previous script runs or side clones
	local guis: { SurfaceGui } = {}
	for _, child in ipairs(boardPart:GetChildren()) do
		if child:IsA("SurfaceGui") then
			table.insert(guis, child)
		end
	end

	if #guis == 0 then return end

	-- Retain exactly one primary SurfaceGui and cleanly destroy all duplicate side GUIs
	local primarySg = guis[1]
	for i = 2, #guis do
		guis[i]:Destroy()
	end

	-- Determine which lateral face normal of the board part most closely faces the approaching player
	local cf = boardPart.CFrame
	local faces = {
		{ face = Enum.NormalId.Front, normal = cf.LookVector },
		{ face = Enum.NormalId.Back,  normal = -cf.LookVector },
		{ face = Enum.NormalId.Right, normal = cf.RightVector },
		{ face = Enum.NormalId.Left,  normal = -cf.RightVector },
	}

	local bestFace = Enum.NormalId.Front
	local bestDot = -math.huge
	for _, candidate in ipairs(faces) do
		local dot = candidate.normal:Dot(targetApproachDir)
		if dot > bestDot then
			bestDot = dot
			bestFace = candidate.face
		end
	end

	primarySg.Face = bestFace
	primarySg.Enabled = true
end

-- Create the 10x10 stud Strength Training Area in front of each player's pen
local function setupPenTrainingArea(penInfo: PenInfo)
	local eggArea = penInfo.EggArea
	local sign = penInfo.Sign
	if not eggArea or not sign then return end

	local signPart = (sign and sign:FindFirstChildWhichIsA("BasePart", true))
	local signPos = signPart and signPart.Position or sign:GetPivot().Position
	local eggPos = eggArea.Position

	-- Forward vector pointing out through the pen entrance
	local forward = penInfo.ForwardDir
	if not forward or forward.Magnitude < 0.1 then
		local dir = Vector3.new(signPos.X - eggPos.X, 0, signPos.Z - eggPos.Z)
		forward = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, 1)
		penInfo.ForwardDir = forward
	end

	-- Place training pad approximately 8 studs in front of the sign
	local targetCenter = signPos + forward * 8

	-- Raycast down to find ground surface height
	local rayOrigin = Vector3.new(targetCenter.X, signPos.Y + 10, targetCenter.Z)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = { penInfo.Model }
	local charsFolder = Workspace:FindFirstChild("characters")
	if charsFolder then table.insert(filterList, charsFolder) end
	rayParams.FilterDescendantsInstances = filterList

	local rayHit = Workspace:Raycast(rayOrigin, Vector3.new(0, -30, 0), rayParams)
	local groundY = rayHit and rayHit.Position.Y or (signPos.Y - 1.5)

	-- Clean up existing training area in pen if present
	local existingArea = penInfo.Model:FindFirstChild("StrengthTrainingArea")
	if existingArea then
		existingArea:Destroy()
	end

	local trainingFolder = Instance.new("Model")
	trainingFolder.Name = "StrengthTrainingArea"
	trainingFolder:SetAttribute("OwnerUserId", penInfo.Owner and penInfo.Owner.UserId or 0)
	trainingFolder:SetAttribute("OwnerName", penInfo.Owner and penInfo.Owner.Name or "")
	trainingFolder:SetAttribute("DumbbellTier", 1)
	trainingFolder:SetAttribute("IsTraining", false)
	trainingFolder.Parent = penInfo.Model
	penInfo.TrainingArea = trainingFolder

	-- 10 x 10 Training Pad (created invisible on server; client displays only for owner or when actively in use)
	local pad = Instance.new("Part")
	pad.Name = "TrainingPad"
	pad.Size = GameplayConfig.Training.AreaSize -- 10 x 0.4 x 10 studs
	pad.CFrame = CFrame.new(targetCenter.X, groundY + 0.2, targetCenter.Z)
	pad.Material = Enum.Material.SmoothPlastic
	pad.Color = Color3.fromRGB(34, 38, 48)
	pad.Anchored = true
	pad.CanCollide = true
	pad.Transparency = 1 -- Server creates invisible so other players never see it by default
	pad:SetAttribute("OwnerUserId", penInfo.Owner and penInfo.Owner.UserId or 0)
	pad:SetAttribute("OwnerName", penInfo.Owner and penInfo.Owner.Name or "")
	pad.Parent = trainingFolder
	penInfo.TrainingPad = pad

	-- Border Ring for visual clarity (created hidden on server)
	local border = Instance.new("SelectionBox")
	border.Name = "PadBorder"
	border.Color3 = Color3.fromRGB(255, 80, 80)
	border.LineThickness = 0.08
	border.Transparency = 1
	border.Adornee = nil
	border.Parent = pad

	-- Surface label on top face: "STRENGTH TRAINING"
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "TrainingSurfaceGui"
	surfaceGui.Face = Enum.NormalId.Top
	surfaceGui.LightInfluence = 0
	surfaceGui.AlwaysOnTop = false
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 16
	surfaceGui.Enabled = false -- Server creates disabled
	surfaceGui.Parent = pad

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 22
	label.TextColor3 = Color3.fromRGB(255, 90, 80)
	label.Text = GameplayConfig.Training.PadLabel
	label.Parent = surfaceGui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2.5
	stroke.Parent = label

	-- Default Dumbbell (Dumbel1 prototype)
	local dumbel1Prototype = getDumbbellPrototype("dumbel1")
	if dumbel1Prototype and dumbel1Prototype:IsA("Model") then
		local penDumbbell = dumbel1Prototype:Clone()
		penDumbbell.Name = "TrainingDumbbell"
		penDumbbell:SetAttribute("OwnerUserId", penInfo.Owner and penInfo.Owner.UserId or 0)
		penDumbbell:SetAttribute("OwnerName", penInfo.Owner and penInfo.Owner.Name or "")

		for _, p in ipairs(penDumbbell:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
				p.Transparency = 0 -- Keep the actual dumbbell visible to its owner
			end
		end

		penDumbbell:PivotTo(CFrame.new(targetCenter.X, groundY + 0.6, targetCenter.Z))
		penDumbbell.Parent = trainingFolder
		penInfo.TrainingDumbbell = penDumbbell
	end

	penInfo.DumbbellTier = 1
	penInfo.Model:SetAttribute("DumbbellTier", 1)

	-- Physical 3D Dumbbell Upgrade Sign placed beside the training pad using templates (dumbel up1 for Level 1->2, dumbel up2 for Level 2->3)
	local rightDir = Vector3.new(forward.Z, 0, -forward.X).Unit
	local signBasePos = targetCenter + rightDir * 6.5

	local currentSignModel: Model? = nil
	local dumbbellPrompt: ProximityPrompt? = nil
	local performDumbbellUpgrade: (Player) -> () -- forward declaration

	local function setupDumbbellUpgradeSign(tier: number)
		if currentSignModel and currentSignModel.Parent then
			currentSignModel:Destroy()
			currentSignModel = nil
		end

		local template = getDumbbellUpgradeSignTemplate(tier)
		if not template then
			template = getDumbbellUpgradeSignTemplate(1)
		end

		if not template then
			warn("[GameplayManager] No dumbbell upgrade sign template found for tier " .. tostring(tier))
			return
		end

		local cloned = template:Clone()
		cloned.Name = "TrainingUpgradeSign"
		cloned:SetAttribute("OwnerUserId", penInfo.Owner and penInfo.Owner.UserId or 0)
		cloned:SetAttribute("OwnerName", penInfo.Owner and penInfo.Owner.Name or "")
		cloned:SetAttribute("DumbbellTier", tier)

		local boardPart: BasePart? = nil
		local postPart: BasePart? = nil
		for _, child in ipairs(cloned:GetChildren()) do
			if child:IsA("BasePart") then
				if child:FindFirstChildWhichIsA("SurfaceGui") then
					boardPart = child
				else
					postPart = child
				end
			end
		end
		if not boardPart then
			boardPart = cloned:FindFirstChildWhichIsA("BasePart")
		end

		for _, p in ipairs(cloned:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = true
				p.CastShadow = true
				p.Transparency = 0
				p:SetAttribute("OwnerUserId", penInfo.Owner and penInfo.Owner.UserId or 0)
			end
		end

		cloned.PrimaryPart = boardPart or postPart or cloned:FindFirstChildWhichIsA("BasePart")
		local _, bSize = cloned:GetBoundingBox()
		local targetY = groundY + (bSize.Y / 2)
		local targetPos = Vector3.new(signBasePos.X, targetY, signBasePos.Z)

		local lookCF = CFrame.lookAt(targetPos, Vector3.new(targetCenter.X, targetY, targetCenter.Z))
		local rotCF = lookCF
		cloned:PivotTo(rotCF)

		if boardPart then
			local approachDir = (Vector3.new(targetCenter.X, targetY, targetCenter.Z) - targetPos).Unit
			setupSingleFrontSurfaceGui(boardPart, approachDir)
		end
		cloned.Parent = trainingFolder
		currentSignModel = cloned
		penInfo.UpgradeSign = cloned

		for idx, p in ipairs(cloned:GetDescendants()) do
			if p:IsA("BasePart") then
				local cd = Instance.new("ClickDetector")
				cd.Name = "DumbbellSignClickDetector_" .. idx
				cd.MaxActivationDistance = 14
				cd.Parent = p
				cd.MouseClick:Connect(function(player: Player)
					performDumbbellUpgrade(player)
				end)
			end
		end

		-- Remove any ProximityPrompts so no floating text appears; interaction is strictly via the 3D button on dumbel up1 and click detector
		for _, desc in ipairs(cloned:GetDescendants()) do
			if desc:IsA("ProximityPrompt") then
				desc:Destroy()
			end
		end
	end

	local function updateSignDisplay()
		local tier = penInfo.DumbbellTier or 1
		setupDumbbellUpgradeSign(tier)
	end

	penInfo.UpdateSignDisplay = updateSignDisplay
	updateSignDisplay()

	performDumbbellUpgrade = function(player: Player)
		local signPos = currentSignModel and currentSignModel:GetPivot().Position or (signBasePos + Vector3.new(0, 3, 0))
		if penInfo.Owner ~= player then
			showFloatingFeedback(signPos, "This is not your pen!", Color3.fromRGB(255, 75, 75))
			return
		end

		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not root or not hum or hum.Health <= 0 then return end

		local dist = (root.Position - signPos).Magnitude
		if dist > 25 then
			showFloatingFeedback(root.Position + Vector3.new(0, 2, 0), "Too far from upgrade sign!", Color3.fromRGB(255, 100, 100))
			return
		end

		local now = os.clock()
		local last = lastUpgradeTime[player] or 0
		if (now - last) < 0.5 then
			return
		end
		lastUpgradeTime[player] = now

		local tier = penInfo.DumbbellTier or 1
		if tier >= 3 then
			showFloatingFeedback(signPos + Vector3.new(0, 1.5, 0), "⭐ Dumbbell already at Max Level!", Color3.fromRGB(255, 200, 80))
			return
		end

		local cost = (tier == 1) and 5000 or 25000
		local nextProtoName = (tier == 1) and "dumbel2" or "dumbel3"
		local nextName = (tier == 1) and "Medium Dumbbell" or "Heavy Dumbbell"
		local nextGain = (tier == 1) and 5 or 20
		local reqStrength = (tier == 1) and 25 or 100

		local currentStrength = 0
		if _G.PlayerData and _G.PlayerData.getStrength then
			currentStrength = _G.PlayerData.getStrength(player)
		else
			local ls = player:FindFirstChild("leaderstats")
			local s = ls and ls:FindFirstChild("Strength") :: IntValue?
			if s then currentStrength = s.Value end
		end

		if currentStrength < reqStrength then
			showFloatingFeedback(signPos + Vector3.new(0, 1.5, 0),
				string.format("❌ Need %d Strength to upgrade! (Have: %d)", reqStrength, currentStrength),
				Color3.fromRGB(255, 75, 75))
			return
		end

		local currentMoney = 0
		if _G.PlayerData and _G.PlayerData.getMoney then
			currentMoney = _G.PlayerData.getMoney(player)
		else
			local ls = player:FindFirstChild("leaderstats")
			local m = ls and ls:FindFirstChild("Money") :: IntValue?
			if m then currentMoney = m.Value end
		end

		if currentMoney < cost then
			showFloatingFeedback(signPos + Vector3.new(0, 1.5, 0),
				string.format("❌ Need $%d to upgrade! (Have: $%d)", cost, currentMoney),
				Color3.fromRGB(255, 75, 75))
			return
		end

		if _G.PlayerData and _G.PlayerData.deductMoney then
			local success = _G.PlayerData.deductMoney(player, cost)
			if not success then return end
		else
			local ls = player:FindFirstChild("leaderstats")
			local m = ls and ls:FindFirstChild("Money") :: IntValue?
			if m then m.Value -= cost end
		end

		penInfo.DumbbellTier = tier + 1
		penInfo.Model:SetAttribute("DumbbellTier", penInfo.DumbbellTier)
		if penInfo.TrainingArea then
			penInfo.TrainingArea:SetAttribute("DumbbellTier", penInfo.DumbbellTier)
		end

		local proto = getDumbbellPrototype(nextProtoName)
		if proto and proto:IsA("Model") then
			if penInfo.TrainingDumbbell and penInfo.TrainingDumbbell.Parent then
				penInfo.TrainingDumbbell:Destroy()
			end
			local newDumbbell = proto:Clone()
			newDumbbell.Name = "TrainingDumbbell"
			newDumbbell:SetAttribute("OwnerUserId", penInfo.Owner and penInfo.Owner.UserId or 0)
			newDumbbell:SetAttribute("OwnerName", penInfo.Owner and penInfo.Owner.Name or "")
			for _, p in ipairs(newDumbbell:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Anchored = true
					p.CanCollide = false
					p.Transparency = 0
				end
			end
			newDumbbell:PivotTo(CFrame.new(targetCenter.X, groundY + 0.6, targetCenter.Z))
			newDumbbell.Parent = trainingFolder
			penInfo.TrainingDumbbell = newDumbbell
		end

		updateSignDisplay()

		showFloatingFeedback(signPos + Vector3.new(0, 2, 0),
			string.format("🎉 Upgraded to %s! (+%d Strength/tick)", nextName, nextGain),
			Color3.fromRGB(80, 255, 120))
	end

	penInfo.PerformUpgrade = performDumbbellUpgrade

	-- Auto-detect player stepping on training pad
	pad.Touched:Connect(function(hit)
		local char = hit.Parent
		if not char then return end
		local p = Players:GetPlayerFromCharacter(char)
		if p and p == penInfo.Owner then
			startPlayerTraining(p, penInfo)
		end
	end)

	-- Remove any floating button or ClickDetector on EggArea: egg placement is handled by tapping anywhere in pen
	local existingPlacePrompt = eggArea:FindFirstChild("PlaceEggPrompt")
	if existingPlacePrompt then
		existingPlacePrompt:Destroy()
	end
	local existingPlatformClick = eggArea:FindFirstChild("PlatformClickDetector")
	if existingPlatformClick then
		existingPlatformClick:Destroy()
	end
end

-- Connect remote event for clicking upgrade button on sign
upgradeDumbbellRemote.OnServerEvent:Connect(function(player: Player)
	local pen = playerPenMap[player]
	if pen and pen.PerformUpgrade then
		pen.PerformUpgrade(player)
	end
end)

upgradePenRemote.OnServerEvent:Connect(function(player: Player)
	local pen = playerPenMap[player]
	if pen and pen.PerformPenUpgrade then
		pen.PerformPenUpgrade(player)
	end
end)

-- Continuous proximity check for auto-training entry
task.spawn(function()
	while true do
		task.wait(0.2)
		for _, pen in ipairs(pensList) do
			local owner = pen.Owner
			local pad = pen.TrainingPad
			if owner and pad and not playerTrainingState[owner] then
				local char = owner.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					local distXZ = Vector2.new(root.Position.X - pad.Position.X, root.Position.Z - pad.Position.Z).Magnitude
					local distY = math.abs(root.Position.Y - pad.Position.Y)
					if distXZ <= 4.5 and distY <= 3.5 then
						startPlayerTraining(owner, pen)
					end
				end
			end
		end
	end
end)

-- Clean up any legacy containment barriers so players can walk freely into their pen without hitting invisible walls
local function setupPenContainmentBarriers(penInfo: PenInfo)
	local existing = penInfo.Model:FindFirstChild("PenContainmentWalls")
	if existing then
		existing:Destroy()
	end
end

-- Visual Pen Upgrade System: uses existing read-only templates Workspace["pen l1"] .. Workspace["pen l5"]
local function getPenTemplate(level: number): Model?
	local targetName = "pen l" .. level
	local direct = Workspace:FindFirstChild(targetName)
	if direct and direct:IsA("Model") then return direct end
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child.Name:lower() == targetName then
			return child
		end
	end
	return nil
end

-- Calculate axis-aligned bounding box from a list of instances/models using BasePart positions
local function getBoundingBoxOfInstances(instances: { Instance }): (Vector3, Vector3)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, inst in ipairs(instances) do
		for _, desc in ipairs(inst:GetDescendants()) do
			if desc:IsA("BasePart") then
				local p = desc.Position
				minX = math.min(minX, p.X)
				maxX = math.max(maxX, p.X)
				minY = math.min(minY, p.Y)
				maxY = math.max(maxY, p.Y)
				minZ = math.min(minZ, p.Z)
				maxZ = math.max(maxZ, p.Z)
			end
		end
		if inst:IsA("BasePart") then
			local p = inst.Position
			minX = math.min(minX, p.X)
			maxX = math.max(maxX, p.X)
			minY = math.min(minY, p.Y)
			maxY = math.max(maxY, p.Y)
			minZ = math.min(minZ, p.Z)
			maxZ = math.max(maxZ, p.Z)
		end
	end
	return Vector3.new(minX, minY, minZ), Vector3.new(maxX, maxY, maxZ)
end

-- Get the entrance center of a template (Workspace["pen l1"] .. Workspace["pen l5"])
-- All templates face +X, so their entrance is located at maxX
local function getTemplateEntranceCenter(template: Model): Vector3
	local fencePieces: { Instance } = {}
	for _, child in ipairs(template:GetChildren()) do
		local nameL = child.Name:lower()
		if child:IsA("Model") and (nameL == "pen" or nameL == "corner") then
			table.insert(fencePieces, child)
		end
	end
	if #fencePieces == 0 then
		for _, child in ipairs(template:GetChildren()) do
			if child:IsA("Model") and not child.Name:lower():find("sign") then
				table.insert(fencePieces, child)
			end
		end
	end
	local tMin, tMax = getBoundingBoxOfInstances(fencePieces)
	return Vector3.new(tMax.X, (tMin.Y + tMax.Y) / 2, (tMin.Z + tMax.Z) / 2)
end

-- Compute entrance center for a pen based on its fence bounding box and forward direction
local function getPenEntranceCenter(penInfo: PenInfo): Vector3
	local sourceFolder = (penInfo.DefaultFences and #penInfo.DefaultFences:GetChildren() > 0)
		and penInfo.DefaultFences
		or penInfo.FenceVisuals

	local instances: { Instance } = (sourceFolder and sourceFolder:GetChildren()) or {}
	if #instances == 0 and penInfo.Model then
		for _, child in ipairs(penInfo.Model:GetChildren()) do
			local nameL = child.Name:lower()
			if child:IsA("Model") and (nameL == "pen" or nameL == "corner") then
				table.insert(instances, child)
			end
		end
	end

	local pMin, pMax = getBoundingBoxOfInstances(instances)
	local fwd = penInfo.ForwardDir
	if fwd.X > 0.5 then
		return Vector3.new(pMax.X, (pMin.Y + pMax.Y) / 2, (pMin.Z + pMax.Z) / 2)
	elseif fwd.X < -0.5 then
		return Vector3.new(pMin.X, (pMin.Y + pMax.Y) / 2, (pMin.Z + pMax.Z) / 2)
	elseif fwd.Z > 0.5 then
		return Vector3.new((pMin.X + pMax.X) / 2, (pMin.Y + pMax.Y) / 2, pMax.Z)
	else
		return Vector3.new((pMin.X + pMax.X) / 2, (pMin.Y + pMax.Y) / 2, pMin.Z)
	end
end

-- Get rotation CFrame mapping template forward (+X) to pen forward direction
local function getRotationForForward(fwd: Vector3): CFrame
	if fwd.Z > 0.5 then
		-- +X to +Z: 90 deg clockwise around Y (yaw = -pi/2)
		return CFrame.Angles(0, -math.pi / 2, 0)
	elseif fwd.Z < -0.5 then
		-- +X to -Z: 90 deg counter-clockwise around Y (yaw = pi/2)
		return CFrame.Angles(0, math.pi / 2, 0)
	elseif fwd.X < -0.5 then
		-- +X to -X: 180 deg around Y (yaw = pi)
		return CFrame.Angles(0, math.pi, 0)
	else
		-- +X to +X: Identity
		return CFrame.new()
	end
end

applyPenVisualLevel = function(penInfo: PenInfo, targetLevel: number)
	targetLevel = math.floor(tonumber(targetLevel) or 0)

	local fenceFolder = penInfo.FenceVisuals
	if not fenceFolder or fenceFolder.Parent ~= penInfo.Model then
		fenceFolder = penInfo.Model:FindFirstChild("FenceVisuals") :: Folder?
		if not fenceFolder then
			fenceFolder = Instance.new("Folder")
			fenceFolder.Name = "FenceVisuals"
			fenceFolder.Parent = penInfo.Model
		end
		penInfo.FenceVisuals = fenceFolder
	end

	-- Level 0 restores the original base pen fence design
	if targetLevel <= 0 then
		if penInfo.VisualLevel == 0 and #fenceFolder:GetChildren() > 0 then
			return
		end
		fenceFolder:ClearAllChildren()
		if penInfo.DefaultFences and #penInfo.DefaultFences:GetChildren() > 0 then
			for _, child in ipairs(penInfo.DefaultFences:GetChildren()) do
				local clone = child:Clone()
				for _, desc in ipairs(clone:GetDescendants()) do
					if desc:IsA("BasePart") then
						desc.Anchored = true
						desc.CanCollide = true
					end
				end
				clone.Parent = fenceFolder
			end
		end
		penInfo.VisualLevel = 0
		penInfo.Model:SetAttribute("VisualPenLevel", 0)
		return
	end

	targetLevel = math.clamp(targetLevel, 1, 5)

	-- If already displaying this level with valid children, avoid redundant rebuilding
	if penInfo.VisualLevel == targetLevel and #fenceFolder:GetChildren() > 0 then
		return
	end

	local template = getPenTemplate(targetLevel)
	if not template then
		warn(string.format("[GameplayManager] Could not find visual template 'pen l%d' in Workspace!", targetLevel))
		return
	end

	local templateEntrance = getTemplateEntranceCenter(template)
	local penEntrance = penInfo.EntranceCenter
	if not penEntrance then
		penEntrance = getPenEntranceCenter(penInfo)
		penInfo.EntranceCenter = penEntrance
	end

	local rot = getRotationForForward(penInfo.ForwardDir)
	local deltaCF = CFrame.new(penEntrance) * rot * CFrame.new(-templateEntrance)

	-- Clear old fences safely; functional parts (EggArea, Sign, TrainingArea, eggs, pets) are untouched
	fenceFolder:ClearAllChildren()

	-- Clone only the visual fence pieces from the template (models named "pen" or "corner")
	for _, child in ipairs(template:GetChildren()) do
		local nameL = child.Name:lower()
		if child:IsA("Model") and (nameL == "pen" or nameL == "corner") then
			local clone = child:Clone()
			-- Directly transform each BasePart's CFrame to guarantee perfect alignment
			-- and avoid any PrimaryPart or Model pivot inconsistencies
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.CFrame = deltaCF * desc.CFrame
					desc.Anchored = true
					desc.CanCollide = true
				end
			end
			clone.Parent = fenceFolder
		elseif child:IsA("BasePart") and nameL ~= "sign" and not nameL:find("egg") then
			local clone = child:Clone()
			clone.CFrame = deltaCF * clone.CFrame
			clone.Anchored = true
			clone.CanCollide = true
			clone.Parent = fenceFolder
		end
	end

	penInfo.VisualLevel = targetLevel
	penInfo.Model:SetAttribute("VisualPenLevel", targetLevel)
	print(string.format("[GameplayManager] Applied visual fence Level %d to Pen %d", targetLevel, penInfo.Index))
end

-- Add a clickable pen-upgrade GUI to the existing sign beside each pen.
-- This only adds script-created UI/interactions; it does not reposition or rebuild the map.
local PEN_UPGRADE_COSTS = { 5000, 25000, 75000, 150000, 300000 }

local function setupPenUpgradeGui(penInfo: PenInfo)
	local sign = penInfo.Sign
	if not sign then
		warn(string.format("[GameplayManager] Pen %d has no sign model; skipping pen upgrade GUI.", penInfo.Index))
		return
	end

	local signParts: { BasePart } = {}
	if sign:IsA("BasePart") then
		table.insert(signParts, sign)
	else
		for _, desc in ipairs(sign:GetDescendants()) do
			if desc:IsA("BasePart") then
				table.insert(signParts, desc)
			end
		end
	end

	if #signParts == 0 then
		warn(string.format("[GameplayManager] Pen %d sign has no BasePart; skipping pen upgrade GUI.", penInfo.Index))
		return
	end

	local signPart: BasePart? = sign.PrimaryPart
	if not signPart then
		local bestScore = -math.huge
		for _, part in ipairs(signParts) do
			local area = part.Size.X * part.Size.Y + part.Size.Y * part.Size.Z + part.Size.X * part.Size.Z
			local score = area * 10 + part.Position.Y * 20
			if score > bestScore then
				bestScore = score
				signPart = part
			end
		end
	end
	if not signPart then
		signPart = signParts[1]
	end

	for _, p in ipairs(signParts) do
		for _, child in ipairs(p:GetChildren()) do
			if child.Name:match("^PenUpgradeGui") or child.Name:match("^PenUpgradeClick") or child.Name == "PenUpgradePrompt" then
				child:Destroy()
			end
		end
	end

	local currentPenSignModel: Model? = nil
	local penPrompt: ProximityPrompt? = nil
	local performPenUpgrade: (Player) -> () -- forward declaration

	local function setupOrUpdatePenSign(level: number)
		if currentPenSignModel and currentPenSignModel.Parent then
			currentPenSignModel:Destroy()
			currentPenSignModel = nil
		end

		local templateIndex = math.clamp(level <= 1 and 1 or level, 1, 5)
		local template = getPenUpgradeSignTemplate(templateIndex)
		if not template then
			template = getPenUpgradeSignTemplate(1)
		end

		if not template then
			warn("[GameplayManager] No pen upgrade sign template found for level " .. tostring(level))
			return
		end

		local cloned = template:Clone()
		cloned.Name = "PenUpgradeSign"
		cloned:SetAttribute("OwnerUserId", penInfo.Owner and penInfo.Owner.UserId or 0)
		cloned:SetAttribute("OwnerName", penInfo.Owner and penInfo.Owner.Name or "")
		cloned:SetAttribute("PenUpgradeLevel", level)

		local boardPart: BasePart? = nil
		local postPart: BasePart? = nil
		for _, child in ipairs(cloned:GetChildren()) do
			if child:IsA("BasePart") then
				if child:FindFirstChildWhichIsA("SurfaceGui") then
					boardPart = child
				else
					postPart = child
				end
			end
		end
		if not boardPart then
			boardPart = cloned:FindFirstChildWhichIsA("BasePart")
		end

		for _, p in ipairs(cloned:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = true
				p.CastShadow = true
				p.Transparency = 0
				p:SetAttribute("OwnerUserId", penInfo.Owner and penInfo.Owner.UserId or 0)
			end
		end

		cloned.PrimaryPart = boardPart or postPart or cloned:FindFirstChildWhichIsA("BasePart")
		cloned:PivotTo(signPart.CFrame)

		if boardPart then
			setupSingleFrontSurfaceGui(boardPart, penInfo.ForwardDir)
		end

		cloned.Parent = penInfo.Model
		currentPenSignModel = cloned
		penInfo.PenSign = cloned

		for _, p in ipairs(signParts) do
			p.Transparency = 1
			p.CanCollide = false
		end

		for idx, p in ipairs(cloned:GetDescendants()) do
			if p:IsA("BasePart") then
				local cd = Instance.new("ClickDetector")
				cd.Name = "PenSignClickDetector_" .. idx
				cd.MaxActivationDistance = 16
				cd.Parent = p
				cd.MouseClick:Connect(function(player: Player)
					performPenUpgrade(player)
				end)
			end
		end

		-- Remove any ProximityPrompts so no floating text appears; interaction is strictly via the 3D button on pen up1 and click detector
		for _, desc in ipairs(cloned:GetDescendants()) do
			if desc:IsA("ProximityPrompt") then
				desc:Destroy()
			end
		end
	end

	local function refresh()
		local level = (_G.PlayerData and _G.PlayerData.getPenUpgradeLevel and penInfo.Owner)
			and _G.PlayerData.getPenUpgradeLevel(penInfo.Owner) or (penInfo.Model:GetAttribute("PenUpgradeLevel") or 0)
		level = math.clamp(tonumber(level) or 0, 0, 5)
		setupOrUpdatePenSign(level)
	end

	performPenUpgrade = function(player: Player)
		local signPos = currentPenSignModel and currentPenSignModel:GetPivot().Position or signPart.Position
		if penInfo.Owner ~= player then
			showFloatingFeedback(signPos, "This is not your pen!", Color3.fromRGB(255, 75, 75))
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - signPos).Magnitude > 25 then return end
		local level = (_G.PlayerData and _G.PlayerData.getPenUpgradeLevel and _G.PlayerData.getPenUpgradeLevel(player))
			or (penInfo.Model:GetAttribute("PenUpgradeLevel") or 0)
		level = math.clamp(tonumber(level) or 0, 0, 5)
		if level >= 5 then
			showFloatingFeedback(signPos, "Pen is already at maximum level!", Color3.fromRGB(255, 205, 55))
			return
		end
		local cost = PEN_UPGRADE_COSTS[level + 1]
		if not _G.PlayerData or not _G.PlayerData.getMoney or not _G.PlayerData.deductMoney or not _G.PlayerData.setPenUpgradeLevel then
			warn("[GameplayManager] PlayerData pen upgrade API is unavailable.")
			return
		end
		if _G.PlayerData.getMoney(player) < cost then
			showFloatingFeedback(signPos, string.format("Need $%d to upgrade your pen!", cost), Color3.fromRGB(255, 75, 75))
			return
		end
		if not _G.PlayerData.deductMoney(player, cost) then return end
		local newLevel = level + 1
		if not _G.PlayerData.setPenUpgradeLevel(player, newLevel) then
			_G.PlayerData.addMoney(player, cost)
			return
		end
		penInfo.Model:SetAttribute("PenUpgradeLevel", newLevel)
		penInfo.Model:SetAttribute("EquippedPetLimit", 6 + newLevel)
		applyPenVisualLevel(penInfo, newLevel)
		refresh()
		showFloatingFeedback(signPos + Vector3.new(0, 2, 0),
			string.format("PEN UPGRADED! Level %d • Pet limit %d", newLevel, 6 + newLevel),
			Color3.fromRGB(80, 255, 120))
	end

	for idx, p in ipairs(signParts) do
		local click = Instance.new("ClickDetector")
		click.Name = "PenUpgradeClickDetector_" .. idx
		click.MaxActivationDistance = 16
		click.Parent = p
		click.MouseClick:Connect(performPenUpgrade)
	end

	penInfo.PerformPenUpgrade = performPenUpgrade
	penInfo.UpdatePenUpgradeDisplay = refresh
	refresh()
end

local function discoverPens()
	local spawnFolder = Workspace:WaitForChild("Spawn", 5)
	if not spawnFolder then return end
	local pensFolder = spawnFolder:WaitForChild("Pens", 5)
	if not pensFolder then return end

	pensList = {}
	for _, child in ipairs(pensFolder:GetChildren()) do
		if child:IsA("Model") and not child.Name:lower():find("pen%s*l") then
			local numStr = child.Name:match("%d+")
			if numStr then
				local index = tonumber(numStr) or 0
				local eggArea: BasePart? = nil
				local signModel: Model? = nil

				for _, desc in ipairs(child:GetDescendants()) do
					local nameL = desc.Name:lower()
					if desc:IsA("BasePart") and (nameL:find("egg%s*area") or nameL:find("eggarea")) then
						eggArea = desc
					elseif desc:IsA("Model") and nameL:find("sign") then
						signModel = desc
					end
				end

				if eggArea then
					local fenceFolder = child:FindFirstChild("FenceVisuals") :: Folder?
					if not fenceFolder then
						fenceFolder = Instance.new("Folder")
						fenceFolder.Name = "FenceVisuals"
						fenceFolder.Parent = child

						for _, item in ipairs(child:GetChildren()) do
							if item:IsA("Model") and (item.Name:lower() == "pen" or item.Name:lower() == "corner") then
								item.Parent = fenceFolder
							end
						end
					end

					local defaultFences = Instance.new("Folder")
					defaultFences.Name = "DefaultFences"
					for _, item in ipairs(fenceFolder:GetChildren()) do
						item:Clone().Parent = defaultFences
					end

					-- Determine true pen forward direction from eggArea to sign
					local forwardDir = Vector3.new(0, 0, 1)
					local signPart = (signModel and signModel:FindFirstChildWhichIsA("BasePart", true))
					if signPart and eggArea then
						local diff = signPart.Position - eggArea.Position
						if math.abs(diff.X) > math.abs(diff.Z) then
							forwardDir = if diff.X > 0 then Vector3.new(1, 0, 0) else Vector3.new(-1, 0, 0)
						else
							forwardDir = if diff.Z > 0 then Vector3.new(0, 0, 1) else Vector3.new(0, 0, -1)
						end
					end

					local penInfo: PenInfo = {
						Index = index,
						Model = child,
						EggArea = eggArea,
						Sign = signModel,
						Owner = nil,
						ForwardDir = forwardDir,
						EntranceCenter = nil,
						TrainingArea = nil,
						TrainingPad = nil,
						TrainingDumbbell = nil,
						OverheadGui = nil,
						OverheadAvatar = nil,
						OverheadLabel = nil,
						Slots = {},
						FenceVisuals = fenceFolder,
						VisualLevel = 0,
						DefaultFences = defaultFences,
					}
					penInfo.EntranceCenter = getPenEntranceCenter(penInfo)
					child:SetAttribute("VisualPenLevel", 0)
					table.insert(pensList, penInfo)
				end
			end
		end
	end

	table.sort(pensList, function(a, b)
		return a.Index < b.Index
	end)

	print(string.format("[GameplayManager] Discovered %d real pens in Workspace.Spawn.Pens", #pensList))

	-- Existing dumbel1, dumbel2, dumbel3 models remain safe and untouched in Workspace.
	-- Visual prototype hiding is handled client-side by StatsHUDController.

	-- Set up overhead display, training area and containment barriers for each real pen
	for _, p in ipairs(pensList) do
		setupPenOverheadDisplay(p)
		setupPenTrainingArea(p)
		setupPenUpgradeGui(p)
		setupPenContainmentBarriers(p)

		-- Ensure all existing and future pets inside the pen are strictly non-collidable
		for _, desc in ipairs(p.Model:GetDescendants()) do
			if desc:IsA("Model") and (desc:GetAttribute("PetType") or desc:FindFirstChildOfClass("Humanoid") or desc.Name:lower():find("lee")) then
				configurePetCollisions(desc)
			end
		end
		p.Model.DescendantAdded:Connect(function(desc)
			if desc:IsA("Model") and (desc:GetAttribute("PetType") or desc:FindFirstChildOfClass("Humanoid") or desc.Name:lower():find("lee")) then
				configurePetCollisions(desc)
			end
		end)
	end
end

local function getPlacedItemCount(penInfo: PenInfo): number
	local count = 0
	for _, slot in pairs(penInfo.Slots) do
		if slot and slot.Model and slot.Model.Parent then
			count += 1
		end
	end
	return count
end

local function findNextFreeSlotIndex(penInfo: PenInfo): number?
	for i = 1, GameplayConfig.Eggs.MaxPlacedCapacity do
		local slot = penInfo.Slots[i]
		if not slot or not slot.Model or not slot.Model.Parent then
			return i
		end
	end
	return nil
end

local function calculateSlotCFrame(eggArea: BasePart, slotIndex: number): CFrame
	local cols = 6
	local rows = 5

	local c = (slotIndex - 1) % cols
	local r = math.floor((slotIndex - 1) / cols)

	local usableWidth = eggArea.Size.X * 0.8
	local usableDepth = eggArea.Size.Z * 0.8

	local stepX = cols > 1 and (usableWidth / (cols - 1)) or 0
	local stepZ = rows > 1 and (usableDepth / (rows - 1)) or 0

	local offsetX = -usableWidth / 2 + c * stepX
	local offsetZ = -usableDepth / 2 + r * stepZ
	local offsetY = eggArea.Size.Y / 2 + 1.0

	return eggArea.CFrame * CFrame.new(offsetX, offsetY, offsetZ)
end

local function clearPenContents(penInfo: PenInfo)
	for slotIdx, slot in pairs(penInfo.Slots) do
		if slot.HatchThread then
			pcall(task.cancel, slot.HatchThread)
		end
		if slot.Model and slot.Model.Parent then
			slot.Model:Destroy()
		end
	end
	penInfo.Slots = {}

	-- Sweep any orphaned placed eggs or pets inside the pen model
	if penInfo.Model then
		for _, child in ipairs(penInfo.Model:GetChildren()) do
			local nameL = child.Name:lower()
			if nameL:match("^placedegg") or nameL:match("^lee_") or nameL:match("^rocklee") then
				child:Destroy()
			end
		end
	end
end

local function assignPenToPlayer(player: Player): PenInfo?
	for _, pen in ipairs(pensList) do
		if pen.Owner == nil then
			pen.Owner = player
			playerPenMap[player] = pen
			updatePenOwnerDisplay(pen, player)

			local savedLevel = 0
			if _G.PlayerData and _G.PlayerData.getPenUpgradeLevel then
				savedLevel = _G.PlayerData.getPenUpgradeLevel(player)
			else
				local attr = player:GetAttribute("PenUpgradeLevel")
				if typeof(attr) == "number" then
					savedLevel = attr
				end
			end
			savedLevel = math.clamp(tonumber(savedLevel) or 0, 0, 5)
			pen.Model:SetAttribute("PenUpgradeLevel", savedLevel)
			pen.Model:SetAttribute("EquippedPetLimit", 6 + savedLevel)
			applyPenVisualLevel(pen, savedLevel)
			if pen.UpdatePenUpgradeDisplay then
				pen.UpdatePenUpgradeDisplay()
			end

			player:GetAttributeChangedSignal("PenUpgradeLevel"):Connect(function()
				if pen.Owner == player then
					updatePenOwnerDisplay(pen, player)
					local lvl = player:GetAttribute("PenUpgradeLevel")
					if typeof(lvl) == "number" then
						lvl = math.clamp(math.floor(lvl), 0, 5)
						pen.Model:SetAttribute("PenUpgradeLevel", lvl)
						pen.Model:SetAttribute("EquippedPetLimit", 6 + lvl)
						applyPenVisualLevel(pen, lvl)
						if pen.UpdatePenUpgradeDisplay then
							pen.UpdatePenUpgradeDisplay()
						end
					end
				end
			end)
			print(string.format("[GameplayManager] Assigned Pen %d to player %s (PenUpgradeLevel: %d)", pen.Index, player.Name, savedLevel))
			return pen
		end
	end
	warn(string.format("[GameplayManager] No available pen for player %s!", player.Name))
	return nil
end

--------------------------------------------------------------------------------
-- 5. EGG CARRIAGE & REDLINE INVENTORY CLAIM SYSTEM
--------------------------------------------------------------------------------
type CarriedEggInfo = {
	Model: Model,
	EggData: {
		SizeTier: string,
		Scale: number,
		Name: string,
		SpeedMultiplier: number?,
		SourceZone: string?,
		HomeSpawnCFrame: CFrame?,
	},
	PickupTime: number,
}

local playerCarriedEgg: { [Player]: CarriedEggInfo } = {}

-- Forward declarations
local placeEggInPen: (Player, PenInfo, any?, CFrame?) -> boolean
local spawnZone1Eggs: () -> ()
local pickUpEgg: (Player, Model) -> ()
local findEggSpawnParts: () -> { BasePart }

local worldEggsFolder: Folder
local function getOrCreateWorldEggsFolder(): Folder
	local folder = Workspace:FindFirstChild("WorldEggs") :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "WorldEggs"
		folder.Parent = Workspace
	end
	return folder
end

local function getEggExtents(): Vector3
	local eggPrototype = Workspace:FindFirstChild("egg") :: Model?
	if eggPrototype then
		local _, size = eggPrototype:GetBoundingBox()
		return size
	end
	return Vector3.new(3, 4, 3)
end

-- Check if a position is inside the boundaries of a given zone
local function isPositionInsideZone(pos: Vector3, zoneName: string): boolean
	local zones = Workspace:FindFirstChild("Zones")
	local zoneModel = zones and zones:FindFirstChild(zoneName) or Workspace:FindFirstChild(zoneName)
	if not zoneModel then return false end
	local zoneArea = zoneModel:FindFirstChild("ZoneArea") :: BasePart?
	if zoneArea then
		local rel = zoneArea.CFrame:PointToObjectSpace(pos)
		return math.abs(rel.X) <= (zoneArea.Size.X / 2) + 2 and math.abs(rel.Z) <= (zoneArea.Size.Z / 2) + 2
	else
		local cf, size = zoneModel:GetBoundingBox()
		local rel = cf:PointToObjectSpace(pos)
		return math.abs(rel.X) <= (size.X / 2) + 2 and math.abs(rel.Z) <= (size.Z / 2) + 2
	end
end

local pendingEggRespawns: { [string]: thread } = {}

local function isWorldEggNear(pos: Vector3, maxDist: number?): boolean
	local dist = maxDist or 2.5
	if not worldEggsFolder then return false end
	for _, egg in ipairs(worldEggsFolder:GetChildren()) do
		if (egg:GetPivot().Position - pos).Magnitude <= dist then
			return true
		end
	end
	return false
end

-- Spawn a single world egg at specified CFrame with full size, hitbox, prompt & touch pickup
local function spawnSingleWorldEgg(sourceZone: string, spawnCF: CFrame, eggData: any): Model?
	worldEggsFolder = getOrCreateWorldEggsFolder()
	local eggPrototype = Workspace:FindFirstChild("egg") :: Model?
	if not eggPrototype then return nil end

	local scale = eggData.Scale or 1.0
	local tierKey = eggData.SizeTier or "Small"
	local tierName = eggData.Name or "Anime Egg"
	local speedMult = eggData.SpeedMultiplier or 1.0

	local newEgg = eggPrototype:Clone()
	newEgg.Name = "WorldEgg"

	for _, p in ipairs(newEgg:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = true
		end
	end

	if scale ~= 1.0 then
		pcall(function()
			newEgg:ScaleTo(scale)
		end)
	end

	newEgg:SetAttribute("SizeTier", tierKey)
	newEgg:SetAttribute("Scale", scale)
	newEgg:SetAttribute("RequiredStrength", 0) -- Anyone can steal any egg!
	newEgg:SetAttribute("SpeedMultiplier", speedMult)
	newEgg:SetAttribute("TierName", tierName)
	newEgg:SetAttribute("SourceZone", sourceZone)
	local originalHomeCF = (eggData and eggData.HomeSpawnCFrame) or spawnCF
	newEgg:SetAttribute("HomeSpawnCFrame", originalHomeCF)

	local rootHitbox = Instance.new("Part")
	rootHitbox.Name = "EggHitbox"
	rootHitbox.Size = Vector3.new(4 * scale, 5 * scale, 4 * scale)
	rootHitbox.Transparency = 1
	rootHitbox.Anchored = true
	rootHitbox.CanCollide = false
	rootHitbox.CanQuery = true
	rootHitbox.CanTouch = false
	rootHitbox.CFrame = newEgg:GetPivot()
	rootHitbox.Parent = newEgg
	newEgg.PrimaryPart = rootHitbox

	newEgg:PivotTo(spawnCF)
	newEgg.Parent = worldEggsFolder

	-- ProximityPrompt on hitbox (no floating text badge)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = tierName
	prompt.ActionText = "Steal Egg"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12 * math.max(1, scale * 0.8)
	prompt.RequiresLineOfSight = false
	prompt.Parent = rootHitbox

	prompt.Triggered:Connect(function(player: Player)
		pickUpEgg(player, newEgg)
	end)

	-- World eggs are collected ONLY by holding/triggering the ProximityPrompt.
	-- Touching an egg must never steal it automatically.
	rootHitbox.CanTouch = false
	for _, part in ipairs(newEgg:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanTouch = false
		end
	end

	return newEgg
end

-- Drop carried egg: returns to original place if in own zone; stays on ground if dropped outside!
local function dropCarriedEgg(player: Player)
	local carried = playerCarriedEgg[player]
	if not carried then return end

	local eggData = carried.EggData
	local sourceZone = eggData.SourceZone or "Zone1"
	local homeSpawnCF = eggData.HomeSpawnCFrame

	if carried.Model and carried.Model.Parent then
		carried.Model:Destroy()
	end
	playerCarriedEgg[player] = nil
	player:SetAttribute("CarryingEgg", false)

	-- Restore player's normal WalkSpeed
	if _G.PlayerData and _G.PlayerData.applyWalkSpeed then
		_G.PlayerData.applyWalkSpeed(player)
	else
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = 16 end
	end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local dropPos = root and root.Position or Vector3.zero

	local inOwnZone = isPositionInsideZone(dropPos, sourceZone)
	if inOwnZone then
		-- Returned to its original place/nest in its home zone
		if homeSpawnCF then
			local spawnKey = string.format("%.1f_%.1f_%.1f", homeSpawnCF.Position.X, homeSpawnCF.Position.Y, homeSpawnCF.Position.Z)
			if pendingEggRespawns[spawnKey] then
				pcall(task.cancel, pendingEggRespawns[spawnKey])
				pendingEggRespawns[spawnKey] = nil
			end
			if not isWorldEggNear(homeSpawnCF.Position, 2.0) then
				spawnSingleWorldEgg(sourceZone, homeSpawnCF, eggData)
			end
		else
			spawnZone1Eggs()
		end
		showFloatingFeedback(dropPos + Vector3.new(0, 2.5, 0),
			string.format("🥚 Returned to nest in %s! Normal speed restored.", sourceZone),
			Color3.fromRGB(255, 200, 80))
	else
		-- Dropped outside its zone: stays where dropped on the ground so anyone can pick it back up!
		local baseExtents = getEggExtents()
		local scale = eggData.Scale or 1.0
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		local filter = { worldEggsFolder }
		if player.Character then table.insert(filter, player.Character) end
		rayParams.FilterDescendantsInstances = filter

		local hit = Workspace:Raycast(dropPos + Vector3.new(0, 5, 0), Vector3.new(0, -30, 0), rayParams)
		local groundY = hit and hit.Position.Y or (dropPos.Y - 2.5)
		local groundCF = CFrame.new(dropPos.X, groundY + (baseExtents.Y * scale / 2) + 0.05, dropPos.Z)

		spawnSingleWorldEgg(sourceZone, groundCF, eggData)

		showFloatingFeedback(dropPos + Vector3.new(0, 2.5, 0),
			"🥚 Egg dropped on ground! Anyone can steal it.", Color3.fromRGB(80, 255, 120))
	end
end

-- Connect drop remote from client button or Q keybind
dropEggRemote.OnServerEvent:Connect(function(player: Player)
	if not playerCarriedEgg[player] then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	local now = os.clock()
	local last = lastDropTime[player] or 0
	if (now - last) < 0.3 then return end
	lastDropTime[player] = now

	dropCarriedEgg(player)
end)

-- Create an actual inventory item (Tool) in player's Backpack
local function giveEggTool(player: Player, eggData: { SizeTier: string, Scale: number, Name: string })
	local tool = Instance.new("Tool")
	tool.Name = eggData.Name or "Anime Egg"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("IsAnimeEgg", true)
	tool:SetAttribute("SizeTier", eggData.SizeTier)
	tool:SetAttribute("Scale", eggData.Scale)
	tool:SetAttribute("TierName", eggData.Name)
	tool:SetAttribute("ActivatedHooked", true)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.2, 1.6, 1.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local whiteModel = Workspace:FindFirstChild("egg") and Workspace.egg:FindFirstChild("white")
	if whiteModel then
		local eggVisual = whiteModel:Clone()
		eggVisual.Name = "EggVisual"
		pcall(function()
			eggVisual:ScaleTo(0.55 * (eggData.Scale or 1.0))
		end)
		for _, p in ipairs(eggVisual:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CanCollide = false
				p.CanTouch = false
				p.CanQuery = false
				p.Anchored = false
				p.Massless = true
				local w = Instance.new("WeldConstraint")
				w.Part0 = handle
				w.Part1 = p
				w.Parent = p
			end
		end
		eggVisual:PivotTo(handle.CFrame)
		eggVisual.Parent = tool
	else
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1.2, 1.6, 1.2)
		mesh.Parent = handle
		handle.Transparency = 0
		handle.Color = Color3.fromRGB(250, 245, 235)
	end

	-- Note: Egg placement is handled client-side via PlaceEggAtLocation RemoteEvent
	-- ensuring eggs appear exactly at the tapped/clicked position on the player's pen platform.

	tool.Parent = player.Backpack
end

-- Claim carried egg into player's INVENTORY at RedLine as a real item
local function claimCarriedEgg(player: Player): boolean
	local carried = playerCarriedEgg[player]
	if not carried then return false end

	local eggData = carried.EggData

	-- Clean up carried egg model
	if carried.Model and carried.Model.Parent then
		carried.Model:Destroy()
	end
	playerCarriedEgg[player] = nil
	player:SetAttribute("CarryingEgg", false)

	-- Restore player's normal WalkSpeed
	if _G.PlayerData and _G.PlayerData.applyWalkSpeed then
		_G.PlayerData.applyWalkSpeed(player)
	else
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = 16 end
	end

	-- Add egg item (Tool) to player's Backpack
	giveEggTool(player, eggData)

	-- Also record in PlayerData if available
	if _G.PlayerData and _G.PlayerData.addEggToInventory then
		_G.PlayerData.addEggToInventory(player, eggData)
	end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local feedbackPos = root and root.Position or Vector3.zero
	showFloatingFeedback(feedbackPos + Vector3.new(0, 3, 0),
		"🎉 EGG CLAIMED! Added to Backpack inventory item!",
		Color3.fromRGB(80, 255, 120))

	return true
end

-- Connect RedLine claim zone (strictly triggers on touching or crossing behind the line toward Spawn)
local function setupRedLineClaimTrigger()
	local zones = Workspace:FindFirstChild("Zones")
	local redLine = (zones and zones:FindFirstChild("RedLine") or Workspace:FindFirstChild("RedLine", true)) :: BasePart?
	if not redLine then
		warn("[GameplayManager] Warning: RedLine part not found in Workspace.Zones.RedLine!")
		return
	end

	local spawnFolder = Workspace:FindFirstChild("Spawn")
	local spawnPos = spawnFolder and spawnFolder:GetPivot().Position or Vector3.new(0, 0, 0)
	local spawnRel = redLine.CFrame:PointToObjectSpace(spawnPos)

	-- Identify which axis is walking thickness vs lateral doorway span
	local isSpanX = redLine.Size.X >= redLine.Size.Z
	local spawnFwd = isSpanX and spawnRel.Z or spawnRel.X
	local towardsSpawnSign = spawnFwd >= 0 and 1 or -1

	print(string.format("[GameplayManager] Connected RedLine claim trigger at %s (SpanAxis: %s, SpawnSign: %d)",
		tostring(redLine.Position), isSpanX and "X" or "Z", towardsSpawnSign))

	-- 1. Direct Touch on RedLine
	redLine.Touched:Connect(function(hit)
		local char = hit.Parent
		if not char then return end
		local player = Players:GetPlayerFromCharacter(char)
		if player and playerCarriedEgg[player] then
			claimCarriedEgg(player)
		end
	end)

	-- 2. Spatial object-space crossing check: NEVER triggers early deep inside Zone1!
	task.spawn(function()
		while true do
			task.wait(0.12)
			for player, _ in pairs(playerCarriedEgg) do
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and redLine and redLine.Parent then
					local rel = redLine.CFrame:PointToObjectSpace(root.Position)
					local halfSpan = isSpanX and ((redLine.Size.X / 2) + 4.0) or ((redLine.Size.Z / 2) + 4.0)
					local halfThick = isSpanX and ((redLine.Size.Z / 2) + 2.0) or ((redLine.Size.X / 2) + 2.0)
					local halfY = (redLine.Size.Y / 2) + 12.0

					local lat = isSpanX and rel.X or rel.Z
					local fwd = isSpanX and rel.Z or rel.X

					if math.abs(lat) <= halfSpan and math.abs(rel.Y) <= halfY then
						-- A: Standing directly on / touching the line
						if math.abs(fwd) <= halfThick then
							claimCarriedEgg(player)
						-- B: Crossed behind the line toward Spawn (up to 35 studs behind)
						elseif (fwd * towardsSpawnSign) > 0 and (fwd * towardsSpawnSign) <= 35 then
							claimCarriedEgg(player)
						end
					end
				end
			end
		end
	end)
end

-- Pick up egg from Zone with size-based weight slowdown and FULL model welding
pickUpEgg = function(player: Player, worldEgg: Model)
	if not worldEgg or not worldEgg.Parent then return end
	if worldEgg:GetAttribute("BeingPickedUp") then return end
	if playerCarriedEgg[player] then
		showFloatingFeedback(player.Character and player.Character:GetPivot().Position or Vector3.zero,
			"Already carrying an egg!", Color3.fromRGB(255, 200, 80))
		return
	end

	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return end

	local scale = worldEgg:GetAttribute("Scale") or 1.0
	local eggPos = worldEgg:GetPivot().Position
	local maxDist = 22 * math.max(1, scale)
	if (root.Position - eggPos).Magnitude > maxDist then
		return
	end

	local now = os.clock()
	local last = lastPickupTime[player] or 0
	if (now - last) < 0.35 then
		return
	end
	lastPickupTime[player] = now
	worldEgg:SetAttribute("BeingPickedUp", true)

	-- Egg size and weight attributes (No strength requirement - anyone can steal any egg!)
	local tierName = worldEgg:GetAttribute("TierName") or "Anime Egg"
	local scale = worldEgg:GetAttribute("Scale") or 1.0
	local speedMult = worldEgg:GetAttribute("SpeedMultiplier") or 1.0
	local sizeTier = worldEgg:GetAttribute("SizeTier") or "Small"
	local sourceZone = worldEgg:GetAttribute("SourceZone") or "Zone1"
	local homeSpawnCF = worldEgg:GetAttribute("HomeSpawnCFrame") or worldEgg:GetPivot()

	-- Remove the world egg from the zone
	worldEgg:Destroy()

	-- Create the visual egg carried above the player's head
	local carriedEgg = Instance.new("Model")
	carriedEgg.Name = "CarriedEgg"

	local whiteModel = Workspace:FindFirstChild("egg") and Workspace.egg:FindFirstChild("white")
	local visualModel: Instance
	if whiteModel then
		visualModel = whiteModel:Clone()
	else
		local eggPart = Instance.new("Part")
		eggPart.Size = Vector3.new(2, 2.8, 2)
		eggPart.Shape = Enum.PartType.Ball
		eggPart.Material = Enum.Material.SmoothPlastic
		eggPart.Color = Color3.fromRGB(250, 245, 235)
		visualModel = eggPart
	end

	if visualModel:IsA("Model") and scale ~= 1.0 then
		pcall(function()
			visualModel:ScaleTo(scale)
		end)
	end

	-- Center root anchor part to hold the egg firmly above the player's head
	local carryRoot = Instance.new("Part")
	carryRoot.Name = "CarryRoot"
	carryRoot.Size = Vector3.new(0.5, 0.5, 0.5)
	carryRoot.Transparency = 1
	carryRoot.CanCollide = false
	carryRoot.CanTouch = false
	carryRoot.CanQuery = false
	carryRoot.Anchored = false
	carryRoot.Massless = true
	carryRoot.CFrame = root.CFrame * CFrame.new(0, 3.2 * scale, 0)
	carryRoot.Parent = carriedEgg
	carriedEgg.PrimaryPart = carryRoot

	if visualModel:IsA("Model") then
		visualModel:PivotTo(carryRoot.CFrame)
	elseif visualModel:IsA("BasePart") then
		visualModel.CFrame = carryRoot.CFrame
	end
	visualModel.Parent = carriedEgg

	-- Weld EVERY part in visualModel to carryRoot so the WHOLE egg stays intact!
	for _, p in ipairs(visualModel:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Anchored = false
			p.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = carryRoot
			weld.Part1 = p
			weld.Parent = p
		end
	end
	if visualModel:IsA("BasePart") then
		visualModel.CanCollide = false
		visualModel.CanTouch = false
		visualModel.CanQuery = false
		visualModel.Anchored = false
		visualModel.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = carryRoot
		weld.Part1 = visualModel
		weld.Parent = visualModel
	end

	-- Weld carryRoot to player's HumanoidRootPart
	local rootWeld = Instance.new("WeldConstraint")
	rootWeld.Part0 = root
	rootWeld.Part1 = carryRoot
	rootWeld.Parent = carryRoot

	carriedEgg.Parent = char

	-- Apply weight slowdown based on egg size!
	local baseSpeed = 16
	if hum.WalkSpeed > 0 then
		baseSpeed = hum.WalkSpeed
	end
	local slowedSpeed = math.max(6, math.floor(baseSpeed * speedMult + 0.5))
	hum.WalkSpeed = slowedSpeed

	playerCarriedEgg[player] = {
		Model = carriedEgg,
		EggData = {
			SizeTier = sizeTier,
			Scale = scale,
			Name = tierName,
			SpeedMultiplier = speedMult,
			SourceZone = sourceZone,
			HomeSpawnCFrame = homeSpawnCF,
		},
		PickupTime = tick(),
	}
	player:SetAttribute("CarryingEgg", true)

	showFloatingFeedback(root.Position + Vector3.new(0, 2.5, 0),
		string.format("🥚 %s Picked Up! Speed slowed to %d! Run to Red Line or Press Q to Drop!", tierName, slowedSpeed),
		Color3.fromRGB(80, 255, 120))

	-- Clean up if character dies
	hum.Died:Connect(function()
		if playerCarriedEgg[player] then
			if carriedEgg.Parent then carriedEgg:Destroy() end
			playerCarriedEgg[player] = nil
			player:SetAttribute("CarryingEgg", false)
		end
	end)

	local spawnKey = string.format("%.1f_%.1f_%.1f", homeSpawnCF.Position.X, homeSpawnCF.Position.Y, homeSpawnCF.Position.Z)
	if pendingEggRespawns[spawnKey] then
		pcall(task.cancel, pendingEggRespawns[spawnKey])
		pendingEggRespawns[spawnKey] = nil
	end

	-- Respawn replacement world egg after 15s during Day (using saved HomeSpawnCFrame, strictly preventing duplicates)
	pendingEggRespawns[spawnKey] = task.delay(15, function()
		pendingEggRespawns[spawnKey] = nil
		if Lighting:GetAttribute("Phase") == "DAY" then
			worldEggsFolder = getOrCreateWorldEggsFolder()
			local eggSpawns = findEggSpawnParts()
			local maxAllowed = (#eggSpawns > 0 and (#eggSpawns * (GameplayConfig.Eggs.EggsPerSpawn or 10))) or (GameplayConfig.Eggs.Zone1SpawnCount or 15)
			if #worldEggsFolder:GetChildren() < maxAllowed then
				local targetCF = homeSpawnCF
				if targetCF and isWorldEggNear(targetCF.Position, 2.0) then
					return
				end
				if not targetCF and #eggSpawns > 0 then
					local baseExtents = getEggExtents()
					targetCF = getSpawnCFrameOnEggSpawn(eggSpawns[math.random(1, #eggSpawns)], baseExtents * scale)
				end
				if targetCF and not isWorldEggNear(targetCF.Position, 2.0) then
					local tierKey, tierData = pickRandomEggTier()
					local eggScale = tierData.Scale or 1.0
					spawnSingleWorldEgg(sourceZone or "Zone1", targetCF, {
						SizeTier = tierKey,
						Scale = eggScale,
						Name = tierData.Name,
						SpeedMultiplier = tierData.SpeedMultiplier,
					})
				end
			end
		end
	end)
end

local function releasePlayerPen(player: Player)
	if playerCarriedEgg[player] then
		if playerCarriedEgg[player].Model and playerCarriedEgg[player].Model.Parent then
			playerCarriedEgg[player].Model:Destroy()
		end
		playerCarriedEgg[player] = nil
		player:SetAttribute("CarryingEgg", false)
	end

	local pen = playerPenMap[player]
	if pen then
		stopPlayerTraining(player, false)
		clearPenContents(pen)
		pen.DumbbellTier = 1
		pen.Model:SetAttribute("DumbbellTier", 1)
		pen.Model:SetAttribute("PenUpgradeLevel", 0)
		pen.Model:SetAttribute("EquippedPetLimit", 6)
		applyPenVisualLevel(pen, 0)
		if pen.UpdateSignDisplay then
			pen.UpdateSignDisplay()
		end
		if pen.UpdatePenUpgradeDisplay then
			pen.UpdatePenUpgradeDisplay()
		end
		local dumbel1Prototype = getDumbbellPrototype("dumbel1")
		if dumbel1Prototype and pen.TrainingArea and pen.TrainingDumbbell and pen.TrainingPad then
			pen.TrainingDumbbell:Destroy()
			local penDumbbell = dumbel1Prototype:Clone()
			penDumbbell.Name = "TrainingDumbbell"
			penDumbbell:SetAttribute("OwnerUserId", 0)
			penDumbbell:SetAttribute("OwnerName", "")
			for _, p in ipairs(penDumbbell:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Anchored = true
					p.CanCollide = false
					p.Transparency = 0
				end
			end
			penDumbbell:PivotTo(CFrame.new(pen.TrainingPad.Position.X, pen.TrainingPad.Position.Y + 0.4, pen.TrainingPad.Position.Z))
			penDumbbell.Parent = pen.TrainingArea
			pen.TrainingDumbbell = penDumbbell
		end
		pen.Owner = nil
		playerPenMap[player] = nil
		updatePenOwnerDisplay(pen, nil)
		print(string.format("[GameplayManager] Released Pen %d from player %s", pen.Index, player.Name))
	end
end

--------------------------------------------------------------------------------
-- 6. LEE COLLISION & PEN CONTAINMENT (NEVER LEAVE PEN!)
--------------------------------------------------------------------------------
local leePrototype = Workspace:WaitForChild("characters"):WaitForChild("lee") :: Model

local function applySinglePetPartSettings(part: BasePart)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	pcall(function()
		part.CollisionGroup = PET_COLLISION_GROUP
	end)

	if not part:GetAttribute("PetCollisionHooked") then
		part:SetAttribute("PetCollisionHooked", true)
		part:GetPropertyChangedSignal("CanCollide"):Connect(function()
			if part.CanCollide then
				part.CanCollide = false
			end
		end)
		part:GetPropertyChangedSignal("CanTouch"):Connect(function()
			if part.CanTouch then
				part.CanTouch = false
			end
		end)
		part:GetPropertyChangedSignal("CanQuery"):Connect(function()
			if part.CanQuery then
				part.CanQuery = false
			end
		end)
	end
end

configurePetCollisions = function(pet: Model)
	for _, desc in ipairs(pet:GetDescendants()) do
		if desc:IsA("BasePart") then
			applySinglePetPartSettings(desc)
		end
	end

	pet.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			applySinglePetPartSettings(desc)
		end
	end)
end

-- Configure the character prototype as well
configurePetCollisions(leePrototype)

-- Strictly keep Rock Lee inside the pen's egg area bounds using object-space calculations
local function startLeeWanderingAI(lee: Model, penInfo: PenInfo)
	local humanoid = lee:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local rootPart = lee:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart then return end

	local eggArea = penInfo.EggArea
	local halfX = math.max(2, (eggArea.Size.X / 2) - 2.5)
	local halfZ = math.max(2, (eggArea.Size.Z / 2) - 2.5)

	-- 1. Continuous high-frequency containment clamp (0.15s loop)
	task.spawn(function()
		while lee.Parent and penInfo.Owner and humanoid.Health > 0 do
			local rel = eggArea.CFrame:PointToObjectSpace(rootPart.Position)
			local clampedX = math.clamp(rel.X, -halfX, halfX)
			local clampedZ = math.clamp(rel.Z, -halfZ, halfZ)

			if math.abs(rel.X - clampedX) > 0.5 or math.abs(rel.Z - clampedZ) > 0.5 then
				local fixedWorld = eggArea.CFrame:PointToWorldSpace(Vector3.new(clampedX, 1.5, clampedZ))
				lee:PivotTo(CFrame.new(fixedWorld) * CFrame.Angles(0, math.rad(rootPart.Orientation.Y), 0))
			end
			task.wait(0.15)
		end
	end)

	-- 2. Wandering loop inside local pen object space
	task.spawn(function()
		while lee.Parent and penInfo.Owner and humanoid.Health > 0 do
			local waitTime = math.random(GameplayConfig.Pets.Lee.MinWanderWait, GameplayConfig.Pets.Lee.MaxWanderWait)
			task.wait(waitTime)

			if not lee.Parent or not penInfo.Owner then break end

			-- Pick strictly clamped waypoint in pen local space
			local rx = (math.random() * 2 - 1) * halfX
			local rz = (math.random() * 2 - 1) * halfZ
			local targetPos = eggArea.CFrame:PointToWorldSpace(Vector3.new(rx, 1.5, rz))

			humanoid.WalkSpeed = GameplayConfig.Pets.Lee.WalkSpeed
			humanoid:MoveTo(targetPos)

			-- Wait for move to finish with a safe 5-second timeout
			local moveDone = false
			local conn: RBXScriptConnection?
			conn = humanoid.MoveToFinished:Connect(function()
				moveDone = true
			end)
			local elapsed = 0
			while not moveDone and elapsed < 5 do
				if not lee.Parent or not penInfo.Owner or humanoid.Health <= 0 then break end
				task.wait(0.2)
				elapsed += 0.2
			end
			if conn then conn:Disconnect() end
		end
	end)
end

--------------------------------------------------------------------------------
-- 7. EGG HATCHING & PLACEMENT FROM INVENTORY
--------------------------------------------------------------------------------
local function hatchSlot(penInfo: PenInfo, slotIndex: number)
	local slot = penInfo.Slots[slotIndex]
	if not slot or slot.Type ~= "Egg" or not slot.Model or not slot.Model.Parent then
		return
	end

	local owner = penInfo.Owner
	if not owner then return end

	local maxPets = (_G.PlayerData and _G.PlayerData.getEquippedPetLimit and _G.PlayerData.getEquippedPetLimit(owner))
		or (penInfo.Model:GetAttribute("EquippedPetLimit") or 6)

	local currentPets = 0
	for _, s in pairs(penInfo.Slots) do
		if s and s.Type == "Pet" and s.Model and s.Model.Parent then
			currentPets += 1
		end
	end

	if currentPets >= maxPets then
		local slotCFrame = calculateSlotCFrame(penInfo.EggArea, slotIndex)
		showFloatingFeedback(slotCFrame.Position + Vector3.new(0, 2, 0),
			string.format("Pet limit reached (%d/%d)! Upgrade pen to hatch more pets.", currentPets, maxPets),
			Color3.fromRGB(255, 120, 80))
		task.delay(3, function()
			if penInfo.Slots[slotIndex] and penInfo.Slots[slotIndex].Type == "Egg" then
				hatchSlot(penInfo, slotIndex)
			end
		end)
		return
	end

	local eggModel = slot.Model
	local eggPivot = eggModel and eggModel:GetPivot()
	local eggPos = eggPivot and eggPivot.Position or calculateSlotCFrame(penInfo.EggArea, slotIndex).Position

	if eggModel then
		eggModel:Destroy()
	end

	local newLee = leePrototype:Clone()
	newLee.Name = string.format("Lee_%s_%d", owner.Name, slotIndex)
	newLee:SetAttribute("OwnerUserId", owner.UserId)
	newLee:SetAttribute("PetType", "Lee")
	newLee:SetAttribute("SlotIndex", slotIndex)

	configurePetCollisions(newLee)

	local hum = newLee:FindFirstChildOfClass("Humanoid")
	if hum and not hum:FindFirstChildOfClass("Animator") then
		local anim = Instance.new("Animator")
		anim.Parent = hum
	end

	local spawnY = penInfo.EggArea.Position.Y + (penInfo.EggArea.Size.Y / 2) + 1.5
	newLee:PivotTo(CFrame.new(eggPos.X, spawnY, eggPos.Z))
	newLee.Parent = penInfo.Model

	slot.Type = "Pet"
	slot.Model = newLee
	slot.HatchThread = nil

	showFloatingFeedback(eggPos, "✨ Rock Lee Hatched!", Color3.fromRGB(255, 230, 80))
	startLeeWanderingAI(newLee, penInfo)
end

-- Checks whether a candidate platform spot is clear of overlapping placed eggs
local function isPlatformSpotClear(penInfo: PenInfo, testX: number, testZ: number, candidateRadius: number): boolean
	local eggArea = penInfo.EggArea
	for _, slot in pairs(penInfo.Slots) do
		if slot and slot.Type == "Egg" and slot.Model and slot.Model.Parent then
			local existingLocal = eggArea.CFrame:PointToObjectSpace(slot.Model:GetPivot().Position)
			local existingScale = tonumber(slot.Model:GetAttribute("Scale")) or 1.0
			local existingRadius = math.max(1.8, 2.2 * existingScale)
			local minDist = candidateRadius + existingRadius + 0.3
			local dx = testX - existingLocal.X
			local dz = testZ - existingLocal.Z
			if (dx * dx + dz * dz) < (minDist * minDist) then
				return false
			end
		end
	end
	return true
end

-- Searches for a nearby free spot on the pen platform, starting at (targetX, targetZ) and spiraling outward
local function findNearbyFreePlatformSpot(penInfo: PenInfo, targetX: number, targetZ: number, candidateRadius: number): (number?, number?)
	local eggArea = penInfo.EggArea
	local halfX = eggArea.Size.X / 2
	local halfZ = eggArea.Size.Z / 2
	local marginX = math.max(1.2, candidateRadius * 0.7)
	local marginZ = math.max(1.2, candidateRadius * 0.7)
	local usableX = math.max(1, halfX - marginX)
	local usableZ = math.max(1, halfZ - marginZ)

	local startX = math.clamp(targetX, -usableX, usableX)
	local startZ = math.clamp(targetZ, -usableZ, usableZ)

	if isPlatformSpotClear(penInfo, startX, startZ, candidateRadius) then
		return startX, startZ
	end

	local searchStep = 1.2
	local maxRadius = math.max(halfX, halfZ) * 1.8
	for r = searchStep, maxRadius, searchStep do
		local angleSteps = math.max(8, math.floor(2 * math.pi * r / searchStep))
		local angleDelta = (2 * math.pi) / angleSteps
		for i = 0, angleSteps - 1 do
			local theta = i * angleDelta
			local cx = startX + r * math.cos(theta)
			local cz = startZ + r * math.sin(theta)
			if math.abs(cx) <= usableX and math.abs(cz) <= usableZ then
				if isPlatformSpotClear(penInfo, cx, cz, candidateRadius) then
					return cx, cz
				end
			end
		end
	end

	return nil, nil
end

-- Place an egg from the player's inventory onto their pen platform (at clicked location or free spot)
placeEggInPen = function(player: Player, penInfo: PenInfo, eggData: any?, customCFrame: CFrame?): boolean
	local currentCount = getPlacedItemCount(penInfo)
	if currentCount >= GameplayConfig.Eggs.MaxPlacedCapacity then
		print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 7] Server placement rejected: Pen #%d capacity reached (%d/%d) for %s",
			penInfo.Index, currentCount, GameplayConfig.Eggs.MaxPlacedCapacity, player.Name))
		showFloatingFeedback(player.Character and player.Character:GetPivot().Position or penInfo.EggArea.Position,
			"❌ Pen Full! (30/30 Eggs placed)", Color3.fromRGB(255, 75, 75))
		return false
	end

	local slotIndex = findNextFreeSlotIndex(penInfo)
	if not slotIndex then
		print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 7] Server placement rejected: No available slot index in Pen #%d for %s",
			penInfo.Index, player.Name))
		return false
	end

	local eggArea = penInfo.EggArea
	local scale = (eggData and tonumber(eggData.Scale)) or 1.0

	local targetCFrame = customCFrame
	if not targetCFrame then
		targetCFrame = calculateSlotCFrame(eggArea, slotIndex)
	end

	local eggPrototype = Workspace:FindFirstChild("egg")
	if not eggPrototype then
		print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 7] Server placement rejected: Workspace.egg prototype model not found for %s", player.Name))
		return false
	end

	local placedEgg = eggPrototype:Clone()
	placedEgg.Name = string.format("PlacedEgg_%d", slotIndex)

	-- Ensure all parts in placed egg are completely NON-COLLIDABLE and non-blocking
	for _, p in ipairs(placedEgg:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
		end
	end

	if scale ~= 1.0 then
		pcall(function()
			placedEgg:ScaleTo(scale)
		end)
	end
	placedEgg:SetAttribute("Scale", scale)

	-- Calculate exact height using pen surface and egg model bounds, so the egg rests flush on the platform
	local bbCF, bbSize = placedEgg:GetBoundingBox()
	local pivotPos = placedEgg:GetPivot().Position
	local bottomRelPivot = (bbCF.Position.Y - (bbSize.Y / 2)) - pivotPos.Y
	local platformTopY = eggArea.Position.Y + (eggArea.Size.Y / 2)
	local correctedY = (platformTopY + 0.02) - bottomRelPivot

	local finalCF = CFrame.new(targetCFrame.Position.X, correctedY, targetCFrame.Position.Z) * (targetCFrame - targetCFrame.Position)
	placedEgg:PivotTo(finalCF)
	placedEgg.Parent = penInfo.Model

	local primary = placedEgg.PrimaryPart or placedEgg:FindFirstChildWhichIsA("BasePart", true)
	local hatchLabel: TextLabel? = nil
	if primary then
		local bb = Instance.new("BillboardGui")
		bb.Name = "HatchGui"
		bb.Size = UDim2.fromOffset(150, 32)
		bb.StudsOffset = Vector3.new(0, 3 * scale, 0)
		bb.AlwaysOnTop = true
		bb.Adornee = primary
		bb.Parent = primary

		hatchLabel = Instance.new("TextLabel")
		hatchLabel.Size = UDim2.fromScale(1, 1)
		hatchLabel.BackgroundTransparency = 1
		hatchLabel.Font = Enum.Font.FredokaOne
		hatchLabel.TextSize = 14
		hatchLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		hatchLabel.Text = "🥚 Hatching: 12s"
		hatchLabel.Parent = bb

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(0, 0, 0)
		stroke.Thickness = 2
		stroke.Parent = hatchLabel
	end

	local slotData = {
		Type = "Egg",
		Model = placedEgg,
		HatchThread = nil,
	}
	penInfo.Slots[slotIndex] = slotData

	slotData.HatchThread = task.spawn(function()
		local duration = GameplayConfig.Eggs.BaseHatchDuration
		local remaining = duration

		while remaining > 0 and placedEgg.Parent and penInfo.Owner == player do
			local mult = Lighting:GetAttribute("HatchSpeedMultiplier") or 1
			if typeof(mult) ~= "number" or mult < 1 then mult = 1 end

			if hatchLabel and hatchLabel.Parent then
				hatchLabel.Text = string.format("🥚 Hatching: %ds", math.max(0, math.ceil(remaining)))
				hatchLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			end

			task.wait(0.2)
			remaining -= (0.2 * mult)
		end

		if placedEgg.Parent and penInfo.Owner == player then
			hatchSlot(penInfo, slotIndex)
		end
	end)

	local eggName = (eggData and eggData.Name) or "Egg"
	print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 7] Server placement SUCCESS: Egg '%s' placed in Pen #%d at (%.1f, %.1f, %.1f) in slot %d for %s",
		eggName, penInfo.Index, finalCF.Position.X, finalCF.Position.Y, finalCF.Position.Z, slotIndex, player.Name))
	showFloatingFeedback(targetCFrame.Position, string.format("+1 %s Placed!", eggName), Color3.fromRGB(120, 255, 120))
	return true
end

placeEggFromInventory = function(player: Player, penInfo: PenInfo): boolean
	if penInfo.Owner ~= player then
		showFloatingFeedback(penInfo.EggArea.Position, "This is not your pen!", Color3.fromRGB(255, 75, 75))
		return false
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return false end

	local dist = (root.Position - penInfo.EggArea.Position).Magnitude
	local maxDist = math.max(30, penInfo.EggArea.Size.Magnitude / 2 + 10)
	if dist > maxDist then
		showFloatingFeedback(root.Position + Vector3.new(0, 2.5, 0), "Too far from pen platform!", Color3.fromRGB(255, 100, 100))
		return false
	end

	local currentPlaced = getPlacedItemCount(penInfo)
	if currentPlaced >= GameplayConfig.Eggs.MaxPlacedCapacity then
		showFloatingFeedback(penInfo.EggArea.Position + Vector3.new(0, 2, 0),
			"❌ Pen Full! (30/30 Eggs placed)", Color3.fromRGB(255, 75, 75))
		return false
	end

	local eggTool: Tool? = nil
	if player.Character then
		for _, item in ipairs(player.Character:GetChildren()) do
			if item:IsA("Tool") and (item:GetAttribute("IsAnimeEgg") == true or item.Name:lower():find("egg")) then
				eggTool = item
				break
			end
		end
	end

	local eggData: any? = nil
	if eggTool then
		eggData = {
			SizeTier = eggTool:GetAttribute("SizeTier") or "Small",
			Scale = tonumber(eggTool:GetAttribute("Scale")) or 1.0,
			Name = eggTool:GetAttribute("TierName") or eggTool.Name,
		}
	elseif playerCarriedEgg[player] then
		local c = playerCarriedEgg[player]
		eggData = {
			SizeTier = (c.EggData and c.EggData.SizeTier) or "Small",
			Scale = tonumber(c.EggData and c.EggData.Scale) or 1.0,
			Name = (c.EggData and c.EggData.Name) or "Anime Egg",
		}
	end

	if not eggData then
		showFloatingFeedback(penInfo.EggArea.Position + Vector3.new(0, 2, 0),
			"Equip or carry an egg to place it!", Color3.fromRGB(255, 200, 80))
		return false
	end

	local placed = placeEggInPen(player, penInfo, eggData)
	if placed then
		if eggTool and eggTool.Parent then
			eggTool:Destroy()
		end
		if _G.PlayerData and _G.PlayerData.removeEggFromInventory then
			_G.PlayerData.removeEggFromInventory(player, eggData)
		end
		if playerCarriedEgg[player] then
			if playerCarriedEgg[player].Model and playerCarriedEgg[player].Model.Parent then
				playerCarriedEgg[player].Model:Destroy()
			end
			playerCarriedEgg[player] = nil
			player:SetAttribute("CarryingEgg", false)
			if _G.PlayerData and _G.PlayerData.applyWalkSpeed then
				_G.PlayerData.applyWalkSpeed(player)
			else
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if hum then hum.WalkSpeed = 16 end
			end
		end
		return true
	end
	return false
end

-- Connect PlaceEggAtLocation RemoteEvent (Tap anywhere in pen to place egg!)
placeEggAtLocationRemote.OnServerEvent:Connect(function(player: Player, hitPosition: any, clientTool: any?)
	-- Checkpoint 4: Server receives event and identifies player's pen
	if typeof(hitPosition) ~= "Vector3" then
		print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 4] Server rejected: Invalid hitPosition type (%s) from %s", typeof(hitPosition), player.Name))
		return
	end

	local pen = playerPenMap[player]
	if not pen then
		print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 4] Server rejected: Player %s does not own a pen", player.Name))
		showFloatingFeedback(player.Character and player.Character:GetPivot().Position or Vector3.zero,
			"You don't own a pen yet!", Color3.fromRGB(255, 80, 80))
		return
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 4] Server rejected: Player %s character missing or dead", player.Name))
		return
	end

	-- Per-player rate limit: 0.15s allows rapid intentional clicks without duplicate packets
	local now = os.clock()
	local last = lastPlaceTime[player] or 0
	if (now - last) < 0.15 then
		print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 4] Server rejected: Rate limit (%.3fs < 0.15s) for %s", now - last, player.Name))
		return
	end
	lastPlaceTime[player] = now

	print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 4] Server received event from %s. Identified Pen #%d", player.Name, pen.Index))

	-- Checkpoint 5: Server validates hit position and identifies egg Tool or carried egg
	local penCF, penSize = pen.Model:GetBoundingBox()
	local playerPenRel = penCF:PointToObjectSpace(root.Position)
	local isPlayerInsidePen = (math.abs(playerPenRel.X) <= (penSize.X / 2) + 20.0) and (math.abs(playerPenRel.Z) <= (penSize.Z / 2) + 20.0)
	local playerDist = (root.Position - pen.EggArea.Position).Magnitude
	if not isPlayerInsidePen and playerDist > 120 then
		print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 5] Server rejected: Player %s too far from pen (dist: %.1f > 120)", player.Name, playerDist))
		showFloatingFeedback(root.Position + Vector3.new(0, 2.5, 0), "Too far from your pen!", Color3.fromRGB(255, 100, 100))
		return
	end

	local eggArea = pen.EggArea
	local rel = eggArea.CFrame:PointToObjectSpace(hitPosition)
	local halfX = eggArea.Size.X / 2
	local halfZ = eggArea.Size.Z / 2
	local halfY = eggArea.Size.Y / 2

	-- Confirm the player is tapping the actual pen surface, not just a point with similar X/Z at another height
	local heightDelta = math.abs(rel.Y - halfY)
	if heightDelta > 4.5 or math.abs(rel.X) > (halfX + 2.5) or math.abs(rel.Z) > (halfZ + 2.5) then
		print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 5] Server rejected: Hit pos not on pen platform! Rel: (%.1f, %.1f, %.1f), PlatformSize: (%.1f, %.1f, %.1f), HeightDelta: %.1f",
			rel.X, rel.Y, rel.Z, eggArea.Size.X, eggArea.Size.Y, eggArea.Size.Z, heightDelta))
		showFloatingFeedback(hitPosition, "Tap inside your pen platform to place this egg!", Color3.fromRGB(255, 200, 80))
		return
	end

	-- Check pen capacity BEFORE consuming any egg
	local currentPlaced = getPlacedItemCount(pen)
	if currentPlaced >= GameplayConfig.Eggs.MaxPlacedCapacity then
		print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 5] Server rejected: Pen #%d is full (%d/%d)",
			pen.Index, currentPlaced, GameplayConfig.Eggs.MaxPlacedCapacity))
		showFloatingFeedback(eggArea.Position + Vector3.new(0, 2, 0),
			string.format("❌ Pen Full! (%d/%d Eggs placed)", currentPlaced, GameplayConfig.Eggs.MaxPlacedCapacity),
			Color3.fromRGB(255, 75, 75))
		return
	end

	-- Strictly identify the SELECTED egg:
	-- Must be an equipped Tool with attribute IsAnimeEgg == true OR an active carried egg
	local eggTool: Tool? = nil
	if clientTool and typeof(clientTool) == "Instance" and clientTool:IsA("Tool") then
		if clientTool.Parent == char and clientTool:GetAttribute("IsAnimeEgg") == true then
			eggTool = clientTool
		end
	end

	-- Fallback to any actively equipped egg tool currently in player.Character
	if not eggTool and char then
		for _, item in ipairs(char:GetChildren()) do
			if item:IsA("Tool") and item:GetAttribute("IsAnimeEgg") == true then
				eggTool = item
				break
			end
		end
	end

	local eggData: any? = nil
	if eggTool then
		eggData = {
			SizeTier = eggTool:GetAttribute("SizeTier") or "Small",
			Scale = tonumber(eggTool:GetAttribute("Scale")) or 1.0,
			Name = eggTool:GetAttribute("TierName") or eggTool.Name,
		}
	elseif playerCarriedEgg[player] then
		local c = playerCarriedEgg[player]
		eggData = {
			SizeTier = (c.EggData and c.EggData.SizeTier) or "Small",
			Scale = tonumber(c.EggData and c.EggData.Scale) or 1.0,
			Name = (c.EggData and c.EggData.Name) or "Anime Egg",
		}
	end

	-- If the player has neither an equipped egg tool nor a carried egg, refuse placement!
	-- Never silently grab an unselected egg from inventory!
	if not eggData then
		local hasBackpackEgg = false
		local bp = player:FindFirstChild("Backpack")
		if bp then
			for _, item in ipairs(bp:GetChildren()) do
				if item:IsA("Tool") and item:GetAttribute("IsAnimeEgg") == true then
					hasBackpackEgg = true
					break
				end
			end
		end
		if not hasBackpackEgg and _G.PlayerData and _G.PlayerData.getEggInventoryCount then
			hasBackpackEgg = (_G.PlayerData.getEggInventoryCount(player) > 0)
		end

		if hasBackpackEgg then
			print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 5] Server rejected: Player %s has eggs in backpack but none equipped in hand", player.Name))
			showFloatingFeedback(hitPosition, "Equip an egg from your backpack to place it!", Color3.fromRGB(255, 200, 80))
		else
			print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 5] Server rejected: Player %s has no eggs to place", player.Name))
			showFloatingFeedback(hitPosition, "You have no eggs to place!", Color3.fromRGB(255, 200, 80))
		end
		return
	end

	print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 5] Hit pos validated. Egg identified: %s (Tier: %s, Scale: %.2f, Source: %s)",
		eggData.Name, eggData.SizeTier, eggData.Scale, eggTool and ("Tool:" .. eggTool.Name) or "CarriedEgg"))

	local scale = tonumber(eggData.Scale) or 1.0
	local baseExtents = getEggExtents()
	local eggExtents = baseExtents * scale

	-- Convert target position into EggArea local coordinate space and clamp to safe bounds
	local marginX = math.max(0.8, (eggExtents.X / 2) + 0.2)
	local marginZ = math.max(0.8, (eggExtents.Z / 2) + 0.2)
	local usableX = math.max(0.5, halfX - marginX)
	local usableZ = math.max(0.5, halfZ - marginZ)
	local clampedX = math.clamp(rel.X, -usableX, usableX)
	local clampedZ = math.clamp(rel.Z, -usableZ, usableZ)

	-- Check if spot is occupied
	local candidateRadius = math.max(1.8, 2.2 * scale)
	local finalX, finalZ = clampedX, clampedZ
	local isClear = isPlatformSpotClear(pen, clampedX, clampedZ, candidateRadius)

	if not isClear then
		-- Minimal adjustment: slight nudge up to 1.5 studs around tapped location
		local adjusted = false
		local testOffsets = {
			Vector2.new(1.5, 0), Vector2.new(-1.5, 0),
			Vector2.new(0, 1.5), Vector2.new(0, -1.5),
			Vector2.new(1.2, 1.2), Vector2.new(-1.2, 1.2),
			Vector2.new(1.2, -1.2), Vector2.new(-1.2, -1.2),
		}
		for _, off in ipairs(testOffsets) do
			local tx = math.clamp(clampedX + off.X, -usableX, usableX)
			local tz = math.clamp(clampedZ + off.Y, -usableZ, usableZ)
			if isPlatformSpotClear(pen, tx, tz, candidateRadius) then
				finalX, finalZ = tx, tz
				adjusted = true
				break
			end
		end

		if not adjusted then
			print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 7] Server placement rejected: Location (%.1f, %.1f) is occupied by another egg", clampedX, clampedZ))
			showFloatingFeedback(hitPosition, "⚠️ Spot is occupied! Tap an open area.", Color3.fromRGB(255, 180, 60))
			return
		end
	end

	-- Calculate the correct height using pen surface and egg model bounds so egg rests on platform
	local localY = halfY + (eggExtents.Y / 2) + 0.02
	local worldPos = eggArea.CFrame:PointToWorldSpace(Vector3.new(finalX, localY, finalZ))
	local randYaw = math.rad(math.random(0, 360))
	local targetCFrame = CFrame.new(worldPos) * CFrame.Angles(0, randYaw, 0)

	-- Checkpoint 6: Server attempts placeEggInPen
	print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 6] Server attempting placeEggInPen for %s at (%.1f, %.1f, %.1f)",
		player.Name, worldPos.X, worldPos.Y, worldPos.Z))

	local placed = placeEggInPen(player, pen, eggData, targetCFrame)
	if placed then
		-- Only consume the egg and clear carried state AFTER placeEggInPen succeeds!
		if eggTool and eggTool.Parent then
			eggTool:Destroy()
		end
		if _G.PlayerData and _G.PlayerData.removeEggFromInventory then
			_G.PlayerData.removeEggFromInventory(player, eggData)
		end
		if playerCarriedEgg[player] then
			if playerCarriedEgg[player].Model and playerCarriedEgg[player].Model.Parent then
				playerCarriedEgg[player].Model:Destroy()
			end
			playerCarriedEgg[player] = nil
			player:SetAttribute("CarryingEgg", false)
			if _G.PlayerData and _G.PlayerData.applyWalkSpeed then
				_G.PlayerData.applyWalkSpeed(player)
			else
				if hum then hum.WalkSpeed = 16 end
			end
		end
		showFloatingFeedback(worldPos + Vector3.new(0, 2.5, 0), "🥚 Egg Placed!", Color3.fromRGB(80, 255, 120))
	else
		print(string.format("[EGG_PLACE_DEBUG] [Checkpoint 7] Server placement rejected: placeEggInPen returned false for %s", player.Name))
	end
end)

--------------------------------------------------------------------------------
-- 8. SERVER-SIDE ZONE1 FLOOR EGG SPAWNING (STRICT FLOOR & SIZE TIERS)
--------------------------------------------------------------------------------

-- Check if candidate position overlaps NightBarrier horizontal footprint + buffer
local function isOverlappingNightBarrier(pos: Vector3, eggExtents: Vector3, barrier: BasePart): boolean
	local rel = barrier.CFrame:PointToObjectSpace(pos)
	local buffer = GameplayConfig.Eggs.BarrierSafetyBuffer or 5
	local halfX = (barrier.Size.X / 2) + (eggExtents.X / 2) + buffer
	local halfZ = (barrier.Size.Z / 2) + (eggExtents.Z / 2) + buffer

	return math.abs(rel.X) <= halfX and math.abs(rel.Z) <= halfZ
end

-- Validate and find safe ground position strictly on Zone1 floor, never on NightBarrier or roofs
local function findSafeZone1FloorSpawn(zoneArea: BasePart, barrier: BasePart?, eggExtents: Vector3): Vector3?
	local zone1 = zoneArea.Parent
	local halfX = (zoneArea.Size.X / 2) - 8
	local halfZ = (zoneArea.Size.Z / 2) - 8
	local rayTopY = zoneArea.Position.Y + 25
	local rayBottomY = zoneArea.Position.Y - 25

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = true -- Raycast only hits solid collidable floor surfaces!

	local filterList: { Instance } = { worldEggsFolder, zoneArea }
	if barrier then
		table.insert(filterList, barrier)
	end
	local charsFolder = Workspace:FindFirstChild("characters")
	if charsFolder then
		table.insert(filterList, charsFolder)
	end
	if zone1 then
		for _, child in ipairs(zone1:GetChildren()) do
			if child:IsA("Model") then
				table.insert(filterList, child)
			end
		end
	end
	rayParams.FilterDescendantsInstances = filterList

	for attempt = 1, GameplayConfig.Eggs.MaxSpawnAttempts do
		local rx = (math.random() * 2 - 1) * halfX
		local rz = (math.random() * 2 - 1) * halfZ
		local candidateXZ = zoneArea.Position + Vector3.new(rx, 0, rz)

		-- 1. Exclude NightBarrier 2D area completely
		if barrier and isOverlappingNightBarrier(candidateXZ, eggExtents, barrier) then
			continue
		end

		-- 2. Raycast down to find the true Zone1 floor
		local rayOrigin = Vector3.new(candidateXZ.X, rayTopY, candidateXZ.Z)
		local rayDir = Vector3.new(0, rayBottomY - rayTopY, 0)
		local hit = Workspace:Raycast(rayOrigin, rayDir, rayParams)

		if hit and hit.Instance then
			local hitPart = hit.Instance
			if not hitPart.CanCollide then
				continue
			end
			if barrier and (hitPart == barrier or hitPart:IsDescendantOf(barrier)) then
				continue
			end
			if hitPart == zoneArea or hitPart:IsDescendantOf(zoneArea) then
				continue
			end

			-- Check for flat ground (floor surface normal facing up)
			if hit.Normal.Y < 0.8 then
				continue
			end

			-- Safe spawn position resting flush on the zone ground floor
			local spawnPos = hit.Position + Vector3.new(0, eggExtents.Y / 2 + 0.02, 0)

			if barrier and isOverlappingNightBarrier(spawnPos, eggExtents, barrier) then
				continue
			end

			-- 3. Full bounding box obstacle check
			local overlapParams = OverlapParams.new()
			overlapParams.FilterType = Enum.RaycastFilterType.Exclude
			overlapParams.FilterDescendantsInstances = { worldEggsFolder, hitPart }
			local overlapping = Workspace:GetPartBoundsInBox(CFrame.new(spawnPos), eggExtents, overlapParams)

			local hasObstacle = false
			for _, part in ipairs(overlapping) do
				if part.CanCollide and part ~= hitPart and (barrier and part ~= barrier) then
					hasObstacle = true
					break
				end
			end

			if not hasObstacle then
				return spawnPos
			end
		end
	end

	warn("[GameplayManager] Warning: Could not find valid spawn position on Zone1 floor after retries.")
	return nil
end

-- Pick a random egg size tier based on configurable weights
local function pickRandomEggTier()
	local r = math.random(1, 100)
	if r <= 10 then
		return "Giant", GameplayConfig.EggSizes.Giant
	elseif r <= 30 then
		return "Large", GameplayConfig.EggSizes.Large
	elseif r <= 60 then
		return "Medium", GameplayConfig.EggSizes.Medium
	else
		return "Small", GameplayConfig.EggSizes.Small
	end
end

-- Find all 'egg spawn' parts strictly inside Zone1
findEggSpawnParts = function(): { BasePart }
	local spawns: { BasePart } = {}
	local zones = Workspace:FindFirstChild("Zones")
	local zone1 = zones and zones:FindFirstChild("Zone1") or Workspace:FindFirstChild("Zone1")
	if zone1 then
		for _, desc in ipairs(zone1:GetDescendants()) do
			if desc.Name:lower():match("egg%s*spawn") then
				if desc:IsA("BasePart") then
					if not table.find(spawns, desc) then
						table.insert(spawns, desc)
					end
				elseif desc:IsA("Model") then
					local part = desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart")
					if part and not table.find(spawns, part) then
						table.insert(spawns, part)
					end
				end
			end
		end
	end
	return spawns
end

local function getSpawnCFrameOnEggSpawn(spawnPart: BasePart, eggExtents: Vector3): CFrame
	local size = spawnPart.Size
	local halfX = math.max(0.5, (size.X / 2) - 1.5)
	local halfZ = math.max(0.5, (size.Z / 2) - 1.5)
	local rx = (math.random() * 2 - 1) * halfX
	local rz = (math.random() * 2 - 1) * halfZ
	local localPos = Vector3.new(rx, (size.Y / 2) + (eggExtents.Y / 2) + 0.1, rz)
	local worldPos = spawnPart.CFrame:PointToWorldSpace(localPos)
	local randYaw = math.rad(math.random(0, 360))
	return CFrame.new(worldPos) * CFrame.Angles(0, randYaw, 0)
end

spawnZone1Eggs = function()
	worldEggsFolder = getOrCreateWorldEggsFolder()

	local baseExtents = getEggExtents()
	local eggSpawnParts = findEggSpawnParts()

	local zones = Workspace:FindFirstChild("Zones")
	local zone1 = zones and zones:FindFirstChild("Zone1") or Workspace:FindFirstChild("Zone1")
	local barrier: BasePart? = nil
	local barrierInstance = (zone1 and zone1:FindFirstChild("NightBarrier", true))
		or Workspace:FindFirstChild("NightBarrier", true)
	if barrierInstance and barrierInstance:IsA("BasePart") then
		barrier = barrierInstance
	end
	local zoneArea: BasePart? = nil
	if zone1 then
		local areaInstance = zone1:FindFirstChild("ZoneArea", true) or zone1:FindFirstChild("Area", true)
		if areaInstance and areaInstance:IsA("BasePart") then
			zoneArea = areaInstance
		end
	end

	if #eggSpawnParts > 0 then
		local eggsPerSpawn = GameplayConfig.Eggs.EggsPerSpawn or 10

		for _, spawnPart in ipairs(eggSpawnParts) do
			local existingCount = 0
			local halfX = spawnPart.Size.X / 2
			local halfZ = spawnPart.Size.Z / 2
			local halfY = spawnPart.Size.Y / 2
			for _, egg in ipairs(worldEggsFolder:GetChildren()) do
				local localP = spawnPart.CFrame:PointToObjectSpace(egg:GetPivot().Position)
				if math.abs(localP.X) <= (halfX + 0.2) and math.abs(localP.Z) <= (halfZ + 0.2) and math.abs(localP.Y - halfY) <= 4.0 then
					existingCount += 1
				end
			end

			local needed = math.max(0, eggsPerSpawn - existingCount)
			for _ = 1, needed do
				local tierKey, tierData = pickRandomEggTier()
				local scale = tierData.Scale or 1.0
				local eggExtents = baseExtents * scale

				-- Keep eggs strictly on valid designated spawn part; if blocked by barrier, retry locally or skip!
				-- Never fall back to scattering eggs across the whole Zone1 floor.
				local spawnCF: CFrame? = nil
				for _ = 1, 8 do
					local testCF = getSpawnCFrameOnEggSpawn(spawnPart, eggExtents)
					local blocked = (barrier and isOverlappingNightBarrier(testCF.Position, eggExtents, barrier))
					if not blocked and not isWorldEggNear(testCF.Position, 2.0) then
						spawnCF = testCF
						break
					end
				end

				if spawnCF then
					spawnSingleWorldEgg("Zone1", spawnCF, {
						SizeTier = tierKey,
						Scale = scale,
						Name = tierData.Name,
						SpeedMultiplier = tierData.SpeedMultiplier,
						HomeSpawnCFrame = spawnCF,
					})
				end
			end
		end
	else
		-- Fallback to Zone1 floor
		if not zoneArea then return end

		local targetCount = GameplayConfig.Eggs.Zone1SpawnCount or 15
		local currentCount = #worldEggsFolder:GetChildren()
		local needed = math.max(0, targetCount - currentCount)

		for _ = 1, needed do
			local tierKey, tierData = pickRandomEggTier()
			local scale = tierData.Scale or 1.0
			local eggExtents = baseExtents * scale

			local spawnPos = findSafeZone1FloorSpawn(zoneArea, barrier, eggExtents)
			if spawnPos then
				spawnSingleWorldEgg("Zone1", CFrame.new(spawnPos), {
					SizeTier = tierKey,
					Scale = scale,
					Name = tierData.Name,
					SpeedMultiplier = tierData.SpeedMultiplier,
				})
			end
		end
	end
end

-- Reset world eggs strictly at the Night transition (pen eggs preserved!)
local function resetWorldEggsOnNight()
	worldEggsFolder = getOrCreateWorldEggsFolder()
	print("[GameplayManager] Night transition triggered! Resetting Zone1 world eggs...")
	worldEggsFolder:ClearAllChildren()
	spawnZone1Eggs()
end

--------------------------------------------------------------------------------
-- 9. AUTHORITATIVE LEE INCOME DISTRIBUTION (1,000 MONEY / SECOND)
--------------------------------------------------------------------------------
local function startIncomeTicker()
	task.spawn(function()
		while true do
			task.wait(1.0)
			for player, pen in pairs(playerPenMap) do
				if player and player.Parent and pen then
					local leeCount = 0
					for slotIdx, slot in pairs(pen.Slots) do
						if slot and slot.Type == "Pet" then
							if slot.Model and slot.Model.Parent then
								leeCount += 1
							else
								pen.Slots[slotIdx] = nil
							end
						end
					end

					if leeCount > 0 and _G.PlayerData and _G.PlayerData.addMoney then
						local income = leeCount * GameplayConfig.Pets.Lee.IncomePerSecond
						_G.PlayerData.addMoney(player, income)
					end
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- 10. INITIALIZATION & LIFECYCLE HOOKS
--------------------------------------------------------------------------------
discoverPens()
setupRedLineClaimTrigger()
spawnZone1Eggs()
startIncomeTicker()

-- Night phase transition listener for world egg reset
Lighting:GetAttributeChangedSignal("Phase"):Connect(function()
	local phase = Lighting:GetAttribute("Phase")
	if phase == "NIGHT" then
		resetWorldEggsOnNight()
	end
end)

-- Restored egg tools in Backpack are handled client-side via PlaceEggAtLocation RemoteEvent
local function setupPlayerEggToolHook(player: Player)
	-- No server-side click hijacking; placement is strictly freeform via PlaceEggAtLocation remote
end

-- Player join/leave lifecycle
Players.PlayerAdded:Connect(function(player: Player)
	assignPenToPlayer(player)
	setupPlayerEggToolHook(player)
end)

for _, p in ipairs(Players:GetPlayers()) do
	assignPenToPlayer(p)
	setupPlayerEggToolHook(p)
end

Players.PlayerRemoving:Connect(function(player: Player)
	stopPlayerTraining(player, false)
	playerJumpExitTime[player] = nil
	lastUpgradeTime[player] = nil
	lastPlaceTime[player] = nil
	lastDropTime[player] = nil
	lastPickupTime[player] = nil
	releasePlayerPen(player)
end)

print("[GameplayManager] Complete gameplay loop with Egg Inventory, Size Tiers, RedLine Claim & Containment active!")
