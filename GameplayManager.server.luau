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

--------------------------------------------------------------------------------
-- 1. NON-COLLIDING CHARACTERS SETUP (PHYSICSSERVICE)
--------------------------------------------------------------------------------
local CHAR_COLLISION_GROUP = "GameCharacters"
pcall(function()
	PhysicsService:RegisterCollisionGroup(CHAR_COLLISION_GROUP)
	PhysicsService:CollisionGroupSetCollidable(CHAR_COLLISION_GROUP, CHAR_COLLISION_GROUP, false)
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
	TrainingArea: Model?,
	TrainingPad: BasePart?,
	TrainingDumbbell: Model?,
	DumbbellTier: number?,
	UpgradeSign: Model?,
	UpdateSignDisplay: (() -> ())?,
	PerformUpgrade: ((Player) -> ())?,
	OverheadGui: BillboardGui?,
	OverheadAvatar: ImageLabel?,
	OverheadLabel: TextLabel?,
	Slots: { [number]: { Type: string, Model: Model, HatchThread: thread? } },
}

local pensList: { PenInfo } = {}
local playerPenMap: { [Player]: PenInfo } = {}

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
end

local function updatePenOwnerDisplay(penInfo: PenInfo, owner: Player?)
	local ownerUserId = owner and owner.UserId or 0
	penInfo.Model:SetAttribute("OwnerUserId", ownerUserId)

	if penInfo.TrainingArea then
		penInfo.TrainingArea:SetAttribute("OwnerUserId", ownerUserId)
	end
	if penInfo.TrainingPad then
		penInfo.TrainingPad:SetAttribute("OwnerUserId", ownerUserId)
	end
	if penInfo.TrainingDumbbell then
		penInfo.TrainingDumbbell:SetAttribute("OwnerUserId", ownerUserId)
	end
	if penInfo.UpgradeSign then
		penInfo.UpgradeSign:SetAttribute("OwnerUserId", ownerUserId)
		for _, d in ipairs(penInfo.UpgradeSign:GetDescendants()) do
			if d:IsA("BasePart") then
				d:SetAttribute("OwnerUserId", ownerUserId)
			end
		end
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
				local impulseY = GameplayConfig.Training.ExitJumpImpulse or 38
				root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, impulseY, root.AssemblyLinearVelocity.Z)
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
		if newState == Enum.HumanoidStateType.Jumping or newState == Enum.HumanoidStateType.Freefall then
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

-- Create the 10x10 stud Strength Training Area in front of each player's pen
local function setupPenTrainingArea(penInfo: PenInfo)
	local eggArea = penInfo.EggArea
	local sign = penInfo.Sign
	if not eggArea or not sign then return end

	local signPos = sign:GetPivot().Position
	local eggPos = eggArea.Position

	-- Forward vector pointing out through the pen entrance
	local dir = Vector3.new(signPos.X - eggPos.X, 0, signPos.Z - eggPos.Z)
	local forward = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, 1)
	penInfo.ForwardDir = forward

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
	local dumbel1Prototype = (ServerStorage:FindFirstChild("dumbel1") or Workspace:FindFirstChild("dumbel1")) :: Model?
	if dumbel1Prototype and dumbel1Prototype:IsA("Model") then
		local penDumbbell = dumbel1Prototype:Clone()
		penDumbbell.Name = "TrainingDumbbell"
		penDumbbell:SetAttribute("OwnerUserId", penInfo.Owner and penInfo.Owner.UserId or 0)

		for _, p in ipairs(penDumbbell:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
				p.Transparency = 1 -- Server creates invisible; client reveals only for owner or when in use
			end
		end

		penDumbbell:PivotTo(CFrame.new(targetCenter.X, groundY + 0.6, targetCenter.Z))
		penDumbbell.Parent = trainingFolder
		penInfo.TrainingDumbbell = penDumbbell
	end

	penInfo.DumbbellTier = 1
	penInfo.Model:SetAttribute("DumbbellTier", 1)

	-- Physical 3D Dumbbell Upgrade Sign placed beside the training pad
	local rightDir = Vector3.new(forward.Z, 0, -forward.X).Unit
	local signBasePos = targetCenter + rightDir * 6.5

	local upgradeSign = Instance.new("Model")
	upgradeSign.Name = "TrainingUpgradeSign"
	upgradeSign:SetAttribute("OwnerUserId", penInfo.Owner and penInfo.Owner.UserId or 0)
	upgradeSign.Parent = trainingFolder
	penInfo.UpgradeSign = upgradeSign

	local post = Instance.new("Part")
	post.Name = "TrainingSignPost"
	post.Size = Vector3.new(0.8, 5.5, 0.8)
	post.CFrame = CFrame.new(signBasePos.X, groundY + 2.75, signBasePos.Z)
	post.Material = Enum.Material.Wood
	post.Color = Color3.fromRGB(115, 75, 45)
	post.Anchored = true
	post.CanCollide = true
	post.Transparency = 0
	post:SetAttribute("OwnerUserId", penInfo.Owner and penInfo.Owner.UserId or 0)
	post.Parent = upgradeSign

	local board = Instance.new("Part")
	board.Name = "TrainingSignBoard"
	board.Size = Vector3.new(4.6, 3.2, 0.5)
	board.CFrame = CFrame.lookAt(Vector3.new(signBasePos.X, groundY + 4.5, signBasePos.Z), Vector3.new(targetCenter.X, groundY + 4.5, targetCenter.Z))
	board.Material = Enum.Material.SmoothPlastic
	board.Color = Color3.fromRGB(24, 28, 36)
	board.Anchored = true
	board.CanCollide = true
	board.Transparency = 0
	board:SetAttribute("OwnerUserId", penInfo.Owner and penInfo.Owner.UserId or 0)
	board.Parent = upgradeSign

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.Name = "UpgradeClickDetector"
	clickDetector.MaxActivationDistance = 14
	clickDetector.Parent = board

	local function createSignGui(face: Enum.NormalId)
		local sg = Instance.new("SurfaceGui")
		sg.Name = "UpgradeSurfaceGui_" .. face.Name
		sg.Face = face
		sg.LightInfluence = 0
		sg.AlwaysOnTop = false
		sg.PixelsPerStud = 30
		sg.Enabled = true
		sg.Parent = board

		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
		frame.BorderSizePixel = 0
		frame.Parent = sg

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 195, 0)
		stroke.Thickness = 3
		stroke.Parent = frame

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, 0, 0.24, 0)
		title.Position = UDim2.new(0, 0, 0.04, 0)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.FredokaOne
		title.TextSize = 20
		title.TextColor3 = Color3.fromRGB(255, 200, 50)
		title.Text = "🏋️ DUMBBELL UPGRADE"
		title.Parent = frame

		local currentLabel = Instance.new("TextLabel")
		currentLabel.Name = "CurrentLabel"
		currentLabel.Size = UDim2.new(1, 0, 0.20, 0)
		currentLabel.Position = UDim2.new(0, 0, 0.28, 0)
		currentLabel.BackgroundTransparency = 1
		currentLabel.Font = Enum.Font.FredokaOne
		currentLabel.TextSize = 16
		currentLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
		currentLabel.Text = "Current: Light (+1 Str/tick)"
		currentLabel.Parent = frame

		-- Prominent interactive button on the sign board (no floating prompt!)
		local upgradeBtn = Instance.new("TextButton")
		upgradeBtn.Name = "UpgradeButton"
		upgradeBtn.Size = UDim2.new(0.90, 0, 0.38, 0)
		upgradeBtn.Position = UDim2.new(0.05, 0, 0.50, 0)
		upgradeBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
		upgradeBtn.AutoButtonColor = true
		upgradeBtn.Font = Enum.Font.FredokaOne
		upgradeBtn.TextSize = 18
		upgradeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		upgradeBtn.Text = "UPGRADE ($5,000)"
		upgradeBtn.Active = true
		upgradeBtn.Parent = frame

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0.25, 0)
		btnCorner.Parent = upgradeBtn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Color = Color3.fromRGB(0, 0, 0)
		btnStroke.Thickness = 2.5
		btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		btnStroke.Parent = upgradeBtn

		local hintLabel = Instance.new("TextLabel")
		hintLabel.Name = "HintLabel"
		hintLabel.Size = UDim2.new(1, 0, 0.12, 0)
		hintLabel.Position = UDim2.new(0, 0, 0.88, 0)
		hintLabel.BackgroundTransparency = 1
		hintLabel.Font = Enum.Font.FredokaOne
		hintLabel.TextSize = 11
		hintLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
		hintLabel.Text = "[Click button on sign to upgrade]"
		hintLabel.Parent = frame

		return currentLabel, upgradeBtn
	end

	local curL1, btnL1 = createSignGui(Enum.NormalId.Front)
	local curL2, btnL2 = createSignGui(Enum.NormalId.Back)

	local function updateSignDisplay()
		local tier = penInfo.DumbbellTier or 1
		local curText = ""
		local btnText = ""
		local btnColor = Color3.fromRGB(46, 204, 113)

		if tier == 1 then
			curText = "Current: Light (+1 Str/tick)"
			btnText = "UPGRADE TO MEDIUM ($5,000)"
			btnColor = Color3.fromRGB(46, 204, 113)
		elseif tier == 2 then
			curText = "Current: Medium (+5 Str/tick)"
			btnText = "UPGRADE TO HEAVY ($25,000)"
			btnColor = Color3.fromRGB(46, 204, 113)
		else
			curText = "Current: Heavy (+20 Str/tick)"
			btnText = "⭐ MAX LEVEL REACHED ⭐"
			btnColor = Color3.fromRGB(100, 110, 125)
		end

		curL1.Text = curText
		curL2.Text = curText
		btnL1.Text = btnText
		btnL2.Text = btnText
		btnL1.BackgroundColor3 = btnColor
		btnL2.BackgroundColor3 = btnColor
	end

	penInfo.UpdateSignDisplay = updateSignDisplay
	updateSignDisplay()

	local function performDumbbellUpgrade(player: Player)
		if penInfo.Owner ~= player then
			showFloatingFeedback(board.Position, "This is not your pen!", Color3.fromRGB(255, 75, 75))
			return
		end

		local tier = penInfo.DumbbellTier or 1
		if tier >= 3 then
			showFloatingFeedback(board.Position + Vector3.new(0, 1.5, 0), "⭐ Dumbbell already at Max Level!", Color3.fromRGB(255, 200, 80))
			return
		end

		local cost = (tier == 1) and 5000 or 25000
		local nextProtoName = (tier == 1) and "dumbel2" or "dumbel3"
		local nextName = (tier == 1) and "Medium Dumbbell" or "Heavy Dumbbell"
		local nextGain = (tier == 1) and 5 or 20

		local currentMoney = 0
		if _G.PlayerData and _G.PlayerData.getMoney then
			currentMoney = _G.PlayerData.getMoney(player)
		else
			local ls = player:FindFirstChild("leaderstats")
			local m = ls and ls:FindFirstChild("Money") :: IntValue?
			if m then currentMoney = m.Value end
		end

		if currentMoney < cost then
			showFloatingFeedback(board.Position + Vector3.new(0, 1.5, 0),
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

		local proto = (ServerStorage:FindFirstChild(nextProtoName) or Workspace:FindFirstChild(nextProtoName)) :: Model?
		if proto and proto:IsA("Model") then
			if penInfo.TrainingDumbbell and penInfo.TrainingDumbbell.Parent then
				penInfo.TrainingDumbbell:Destroy()
			end
			local newDumbbell = proto:Clone()
			newDumbbell.Name = "TrainingDumbbell"
			newDumbbell:SetAttribute("OwnerUserId", penInfo.Owner and penInfo.Owner.UserId or 0)
			for _, p in ipairs(newDumbbell:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Anchored = true
					p.CanCollide = false
					p.Transparency = 1
				end
			end
			newDumbbell:PivotTo(CFrame.new(targetCenter.X, groundY + 0.6, targetCenter.Z))
			newDumbbell.Parent = trainingFolder
			penInfo.TrainingDumbbell = newDumbbell
		end

		updateSignDisplay()

		showFloatingFeedback(board.Position + Vector3.new(0, 2, 0),
			string.format("🎉 Upgraded to %s! (+%d Strength/tick)", nextName, nextGain),
			Color3.fromRGB(80, 255, 120))
	end

	penInfo.PerformUpgrade = performDumbbellUpgrade
	clickDetector.MouseClick:Connect(performDumbbellUpgrade)

	-- Auto-detect player stepping on training pad
	pad.Touched:Connect(function(hit)
		local char = hit.Parent
		if not char then return end
		local p = Players:GetPlayerFromCharacter(char)
		if p and p == penInfo.Owner then
			startPlayerTraining(p, penInfo)
		end
	end)

	-- Also setup ProximityPrompt on EggArea to place eggs from inventory
	local existingPlacePrompt = eggArea:FindFirstChild("PlaceEggPrompt")
	if not existingPlacePrompt then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PlaceEggPrompt"
		prompt.ObjectText = "Pen Platform"
		prompt.ActionText = "Place Egg from Inventory"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Parent = eggArea

		prompt.Triggered:Connect(function(player: Player)
			if penInfo.Owner == player then
				placeEggFromInventory(player, penInfo)
			else
				showFloatingFeedback(eggArea.Position, "This is not your pen!", Color3.fromRGB(255, 75, 75))
			end
		end)
	end
end

-- Connect remote event for clicking upgrade button on sign
upgradeDumbbellRemote.OnServerEvent:Connect(function(player: Player)
	local pen = playerPenMap[player]
	if pen and pen.PerformUpgrade then
		pen.PerformUpgrade(player)
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

-- Physical invisible barrier walls around EggArea to prevent characters from escaping pen
local function setupPenContainmentBarriers(penInfo: PenInfo)
	local eggArea = penInfo.EggArea
	if not eggArea then return end

	local existing = penInfo.Model:FindFirstChild("PenContainmentWalls")
	if existing then existing:Destroy() end

	local folder = Instance.new("Model")
	folder.Name = "PenContainmentWalls"

	local sizeX = eggArea.Size.X
	local sizeZ = eggArea.Size.Z
	local wallHeight = 18
	local wallThickness = 1.0

	local wallConfigs = {
		{ Offset = Vector3.new(0, wallHeight / 2, sizeZ / 2 + wallThickness / 2), Size = Vector3.new(sizeX + wallThickness * 2, wallHeight, wallThickness) },
		{ Offset = Vector3.new(0, wallHeight / 2, -sizeZ / 2 - wallThickness / 2), Size = Vector3.new(sizeX + wallThickness * 2, wallHeight, wallThickness) },
		{ Offset = Vector3.new(sizeX / 2 + wallThickness / 2, wallHeight / 2, 0), Size = Vector3.new(wallThickness, wallHeight, sizeZ) },
		{ Offset = Vector3.new(-sizeX / 2 - wallThickness / 2, wallHeight / 2, 0), Size = Vector3.new(wallThickness, wallHeight, sizeZ) },
	}

	for i, cfg in ipairs(wallConfigs) do
		local wall = Instance.new("Part")
		wall.Name = "BarrierWall_" .. i
		wall.Size = cfg.Size
		wall.CFrame = eggArea.CFrame * CFrame.new(cfg.Offset)
		wall.Transparency = 1
		wall.CanCollide = true
		wall.Anchored = true
		wall.CanTouch = false
		wall.CanQuery = false
		wall.Parent = folder
	end

	folder.Parent = penInfo.Model
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
					local penInfo: PenInfo = {
						Index = index,
						Model = child,
						EggArea = eggArea,
						Sign = signModel,
						Owner = nil,
						ForwardDir = Vector3.new(0, 0, 1),
						TrainingArea = nil,
						TrainingPad = nil,
						TrainingDumbbell = nil,
						OverheadGui = nil,
						OverheadAvatar = nil,
						OverheadLabel = nil,
						Slots = {},
					}
					table.insert(pensList, penInfo)
				end
			end
		end
	end

	table.sort(pensList, function(a, b)
		return a.Index < b.Index
	end)

	print(string.format("[GameplayManager] Discovered %d real pens in Workspace.Spawn.Pens", #pensList))

	-- Secure prototype dumbbells in ServerStorage so they do not show loose in Workspace
	for _, name in ipairs({"dumbel1", "dumbel2", "dumbel3", "Dumbel1", "Dumbel2", "Dumbel3"}) do
		local proto = Workspace:FindFirstChild(name)
		if proto and proto:IsA("Model") then
			proto.Parent = ServerStorage
			print(string.format("[GameplayManager] Moved prototype '%s' to ServerStorage", name))
		end
	end

	-- Set up overhead display, training area and containment barriers for each real pen
	for _, p in ipairs(pensList) do
		setupPenOverheadDisplay(p)
		setupPenTrainingArea(p)
		setupPenContainmentBarriers(p)
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
			task.cancel(slot.HatchThread)
		end
		if slot.Model and slot.Model.Parent then
			slot.Model:Destroy()
		end
	end
	penInfo.Slots = {}
end

local function assignPenToPlayer(player: Player): PenInfo?
	for _, pen in ipairs(pensList) do
		if pen.Owner == nil then
			pen.Owner = player
			playerPenMap[player] = pen
			updatePenOwnerDisplay(pen, player)
			print(string.format("[GameplayManager] Assigned Pen %d to player %s", pen.Index, player.Name))
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
			p.CanTouch = true
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
	newEgg:SetAttribute("HomeSpawnCFrame", spawnCF)

	local rootHitbox = Instance.new("Part")
	rootHitbox.Name = "EggHitbox"
	rootHitbox.Size = Vector3.new(4 * scale, 5 * scale, 4 * scale)
	rootHitbox.Transparency = 1
	rootHitbox.Anchored = true
	rootHitbox.CanCollide = false
	rootHitbox.CanQuery = true
	rootHitbox.CanTouch = true
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

	local function onEggTouched(hit: BasePart)
		local char = hit.Parent
		if not char then return end
		local player = Players:GetPlayerFromCharacter(char)
		if player and not playerCarriedEgg[player] then
			pickUpEgg(player, newEgg)
		end
	end

	rootHitbox.Touched:Connect(onEggTouched)
	for _, p in ipairs(newEgg:GetDescendants()) do
		if p:IsA("BasePart") and p ~= rootHitbox then
			p.Touched:Connect(onEggTouched)
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
			spawnSingleWorldEgg(sourceZone, homeSpawnCF, eggData)
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

	-- Place egg when clicking with tool equipped near pen platform
	tool.Activated:Connect(function()
		local pen = playerPenMap[player]
		if not pen then
			showFloatingFeedback(player.Character and player.Character:GetPivot().Position or Vector3.zero,
				"You don't own a pen yet!", Color3.fromRGB(255, 80, 80))
			return
		end

		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then return end

		local dist = (root.Position - pen.EggArea.Position).Magnitude
		local maxDist = math.max(25, pen.EggArea.Size.Magnitude / 2 + 10)
		if dist > maxDist then
			showFloatingFeedback(root.Position + Vector3.new(0, 2.5, 0),
				"Go to your pen platform to place this egg!", Color3.fromRGB(255, 200, 80))
			return
		end

		local currentCount = getPlacedItemCount(pen)
		if currentCount >= GameplayConfig.Eggs.MaxPlacedCapacity then
			showFloatingFeedback(root.Position + Vector3.new(0, 2.5, 0),
				"❌ Pen Full! (30/30 Eggs placed)", Color3.fromRGB(255, 75, 75))
			return
		end

		local placed = placeEggInPen(player, pen, eggData)
		if placed then
			tool:Destroy()
			if _G.PlayerData and _G.PlayerData.removeEggFromInventory then
				_G.PlayerData.removeEggFromInventory(player, eggData)
			end
		end
	end)

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

	-- Respawn replacement world egg after 15s during Day
	task.delay(15, function()
		if Lighting:GetAttribute("Phase") == "DAY" then
			spawnZone1Eggs()
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
		if pen.UpdateSignDisplay then
			pen.UpdateSignDisplay()
		end
		local dumbel1Prototype = (ServerStorage:FindFirstChild("dumbel1") or Workspace:FindFirstChild("dumbel1")) :: Model?
		if dumbel1Prototype and pen.TrainingArea and pen.TrainingDumbbell and pen.TrainingPad then
			pen.TrainingDumbbell:Destroy()
			local penDumbbell = dumbel1Prototype:Clone()
			penDumbbell.Name = "TrainingDumbbell"
			penDumbbell:SetAttribute("OwnerUserId", 0)
			for _, p in ipairs(penDumbbell:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Anchored = true
					p.CanCollide = false
					p.Transparency = 1
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

local function configurePetCollisions(pet: Model)
	for _, desc in ipairs(pet:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
			desc.Anchored = false
			pcall(function()
				desc.CollisionGroup = CHAR_COLLISION_GROUP
			end)
		end
	end
end

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

			humanoid.MoveToFinished:Wait()
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

	local slotCFrame = calculateSlotCFrame(penInfo.EggArea, slotIndex)
	local eggModel = slot.Model

	eggModel:Destroy()

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

	newLee:PivotTo(slotCFrame + Vector3.new(0, 1.5, 0))
	newLee.Parent = penInfo.Model

	slot.Type = "Pet"
	slot.Model = newLee
	slot.HatchThread = nil

	showFloatingFeedback(slotCFrame.Position, "✨ Rock Lee Hatched!", Color3.fromRGB(255, 230, 80))
	startLeeWanderingAI(newLee, penInfo)
end

-- Place an egg from the player's inventory onto their pen platform (at clicked location or next slot)
placeEggInPen = function(player: Player, penInfo: PenInfo, eggData: any?, customCFrame: CFrame?): boolean
	local currentCount = getPlacedItemCount(penInfo)
	if currentCount >= GameplayConfig.Eggs.MaxPlacedCapacity then
		showFloatingFeedback(player.Character and player.Character:GetPivot().Position or penInfo.EggArea.Position,
			"❌ Pen Full! (30/30 Eggs placed)", Color3.fromRGB(255, 75, 75))
		return false
	end

	local slotIndex = findNextFreeSlotIndex(penInfo)
	if not slotIndex then return false end

	local eggArea = penInfo.EggArea
	local scale = (eggData and tonumber(eggData.Scale)) or 1.0

	local targetCFrame = customCFrame
	if not targetCFrame then
		targetCFrame = calculateSlotCFrame(eggArea, slotIndex)
	end

	local eggPrototype = Workspace:FindFirstChild("egg")
	if not eggPrototype then return false end

	local placedEgg = eggPrototype:Clone()
	placedEgg.Name = string.format("PlacedEgg_%d", slotIndex)

	-- Ensure all parts in placed egg are completely NON-COLLIDABLE
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

	placedEgg:PivotTo(targetCFrame)
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
				if mult >= 50 then
					hatchLabel.Text = string.format("🌙 50x FAST: %.1fs", remaining)
					hatchLabel.TextColor3 = Color3.fromRGB(150, 220, 255)
				else
					hatchLabel.Text = string.format("🥚 Hatching: %ds", math.ceil(remaining))
					hatchLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				end
			end

			task.wait(0.2)
			remaining -= (0.2 * mult)
		end

		if placedEgg.Parent and penInfo.Owner == player then
			hatchSlot(penInfo, slotIndex)
		end
	end)

	local eggName = (eggData and eggData.Name) or "Egg"
	showFloatingFeedback(targetCFrame.Position, string.format("+1 %s Placed!", eggName), Color3.fromRGB(120, 255, 120))
	return true
end

placeEggFromInventory = function(player: Player, penInfo: PenInfo): boolean
	local eggTool: Tool? = nil
	for _, item in ipairs(player.Backpack:GetChildren()) do
		if item:IsA("Tool") and item:GetAttribute("IsAnimeEgg") == true then
			eggTool = item
			break
		end
	end
	if not eggTool and player.Character then
		local item = player.Character:FindFirstChildWhichIsA("Tool")
		if item and item:GetAttribute("IsAnimeEgg") == true then
			eggTool = item
		end
	end

	local eggData: any? = nil
	if eggTool then
		eggData = {
			SizeTier = eggTool:GetAttribute("SizeTier") or "Small",
			Scale = eggTool:GetAttribute("Scale") or 1.0,
			Name = eggTool:GetAttribute("TierName") or "Anime Egg",
		}
	elseif _G.PlayerData and _G.PlayerData.getEggInventoryCount and _G.PlayerData.getEggInventoryCount(player) > 0 then
		eggData = _G.PlayerData.removeEggFromInventory(player)
	end

	if not eggData then
		showFloatingFeedback(penInfo.EggArea.Position + Vector3.new(0, 2, 0),
			"No eggs in inventory! Steal one from a zone!", Color3.fromRGB(255, 200, 80))
		return false
	end

	local currentPlaced = getPlacedItemCount(penInfo)
	if currentPlaced >= GameplayConfig.Eggs.MaxPlacedCapacity then
		showFloatingFeedback(penInfo.EggArea.Position + Vector3.new(0, 2, 0),
			"❌ Pen Full! (30/30 Eggs placed)", Color3.fromRGB(255, 75, 75))
		return false
	end

	local placed = placeEggInPen(player, penInfo, eggData)
	if placed then
		if eggTool then
			eggTool:Destroy()
			if _G.PlayerData and _G.PlayerData.removeEggFromInventory then
				_G.PlayerData.removeEggFromInventory(player)
			end
		end
		return true
	end
	return false
end

-- Connect PlaceEggAtLocation RemoteEvent (Tap anywhere in pen to place egg!)
placeEggAtLocationRemote.OnServerEvent:Connect(function(player: Player, hitPosition: any)
	if typeof(hitPosition) ~= "Vector3" then return end

	local pen = playerPenMap[player]
	if not pen then
		showFloatingFeedback(player.Character and player.Character:GetPivot().Position or Vector3.zero,
			"You don't own a pen yet!", Color3.fromRGB(255, 80, 80))
		return
	end

	local eggArea = pen.EggArea
	local rel = eggArea.CFrame:PointToObjectSpace(hitPosition)
	local halfX = (eggArea.Size.X / 2) + 2.5
	local halfZ = (eggArea.Size.Z / 2) + 2.5

	-- Check if click is anywhere in or on the pen platform
	if math.abs(rel.X) > halfX or math.abs(rel.Z) > halfZ then
		showFloatingFeedback(hitPosition, "Tap inside your pen platform to place this egg!", Color3.fromRGB(255, 200, 80))
		return
	end

	-- Clamp within usable margins
	local usableX = math.max(1, (eggArea.Size.X / 2) - 2.0)
	local usableZ = math.max(1, (eggArea.Size.Z / 2) - 2.0)
	local clampedX = math.clamp(rel.X, -usableX, usableX)
	local clampedZ = math.clamp(rel.Z, -usableZ, usableZ)

	-- Find egg tool or inventory egg
	local eggTool: Tool? = nil
	for _, item in ipairs(player.Backpack:GetChildren()) do
		if item:IsA("Tool") and item:GetAttribute("IsAnimeEgg") == true then
			eggTool = item
			break
		end
	end
	if not eggTool and player.Character then
		local item = player.Character:FindFirstChildWhichIsA("Tool")
		if item and item:GetAttribute("IsAnimeEgg") == true then
			eggTool = item
		end
	end

	local eggData: any? = nil
	if eggTool then
		eggData = {
			SizeTier = eggTool:GetAttribute("SizeTier") or "Small",
			Scale = eggTool:GetAttribute("Scale") or 1.0,
			Name = eggTool:GetAttribute("TierName") or "Anime Egg",
		}
	elseif _G.PlayerData and _G.PlayerData.getEggInventoryCount and _G.PlayerData.getEggInventoryCount(player) > 0 then
		eggData = _G.PlayerData.removeEggFromInventory(player)
	end

	if not eggData then
		showFloatingFeedback(eggArea.Position + Vector3.new(0, 2, 0),
			"No eggs in inventory! Steal one from a zone!", Color3.fromRGB(255, 200, 80))
		return
	end

	local currentPlaced = getPlacedItemCount(pen)
	if currentPlaced >= GameplayConfig.Eggs.MaxPlacedCapacity then
		showFloatingFeedback(eggArea.Position + Vector3.new(0, 2, 0),
			"❌ Pen Full! (30/30 Eggs placed)", Color3.fromRGB(255, 75, 75))
		return
	end

	local scale = eggData.Scale or 1.0
	local targetY = eggArea.Size.Y / 2 + 1.0
	local randYaw = math.rad(math.random(0, 360))
	local targetCFrame = eggArea.CFrame * CFrame.new(clampedX, targetY, clampedZ) * CFrame.Angles(0, randYaw, 0)

	local placed = placeEggInPen(player, pen, eggData, targetCFrame)
	if placed then
		if eggTool then
			eggTool:Destroy()
			if _G.PlayerData and _G.PlayerData.removeEggFromInventory then
				_G.PlayerData.removeEggFromInventory(player)
			end
		end
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

-- Find all 'egg spawn' parts placed in any zone
local function findEggSpawnParts(): { BasePart }
	local spawns: { BasePart } = {}
	local function checkContainer(container: Instance)
		for _, desc in ipairs(container:GetDescendants()) do
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

	local zones = Workspace:FindFirstChild("Zones")
	if zones then
		checkContainer(zones)
	end
	for _, obj in ipairs(Workspace:GetChildren()) do
		if obj:IsA("Model") and obj.Name:lower():match("zone") then
			checkContainer(obj)
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
	worldEggsFolder:ClearAllChildren()

	local baseExtents = getEggExtents()
	local eggSpawnParts = findEggSpawnParts()

	if #eggSpawnParts > 0 then
		print(string.format("[GameplayManager] Spawning eggs on %d zone 'egg spawn' parts...", #eggSpawnParts))
		local eggsPerSpawn = GameplayConfig.Eggs.EggsPerSpawn or 10

		for _, spawnPart in ipairs(eggSpawnParts) do
			local zoneParent = spawnPart:FindFirstAncestorWhichIsA("Model")
			local zoneName = (zoneParent and zoneParent.Name) or "Zone1"

			for _ = 1, eggsPerSpawn do
				local tierKey, tierData = pickRandomEggTier()
				local scale = tierData.Scale or 1.0
				local eggExtents = baseExtents * scale
				local spawnCF = getSpawnCFrameOnEggSpawn(spawnPart, eggExtents)

				spawnSingleWorldEgg(zoneName, spawnCF, {
					SizeTier = tierKey,
					Scale = scale,
					Name = tierData.Name,
					SpeedMultiplier = tierData.SpeedMultiplier,
				})
			end
		end
	else
		-- Fallback to Zone1 floor
		local zones = Workspace:FindFirstChild("Zones")
		local zone1 = zones and zones:FindFirstChild("Zone1") or Workspace:FindFirstChild("Zone1")
		local zoneArea = zone1 and zone1:FindFirstChild("ZoneArea") :: BasePart?
		local barrier = zone1 and zone1:FindFirstChild("NightBarrier") :: BasePart?
		if not zoneArea then return end

		local targetCount = GameplayConfig.Eggs.Zone1SpawnCount or 15
		for _ = 1, targetCount do
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
					for _, slot in pairs(pen.Slots) do
						if slot and slot.Type == "Pet" and slot.Model and slot.Model.Parent then
							leeCount += 1
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

-- Hook restored egg tools in Backpack so they can be placed
local function setupPlayerEggToolHook(player: Player)
	local function checkItem(item: Instance)
		if item:IsA("Tool") and item:GetAttribute("IsAnimeEgg") == true and not item:GetAttribute("ActivatedHooked") then
			item:SetAttribute("ActivatedHooked", true)
			item.Activated:Connect(function()
				local pen = playerPenMap[player]
				if not pen then return end
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not root then return end
				local dist = (root.Position - pen.EggArea.Position).Magnitude
				local maxDist = math.max(25, pen.EggArea.Size.Magnitude / 2 + 10)
				if dist <= maxDist then
					local currentCount = getPlacedItemCount(pen)
					if currentCount < GameplayConfig.Eggs.MaxPlacedCapacity then
						local eggData = {
							SizeTier = item:GetAttribute("SizeTier") or "Small",
							Scale = item:GetAttribute("Scale") or 1.0,
							Name = item:GetAttribute("TierName") or "Anime Egg",
						}
						local placed = placeEggInPen(player, pen, eggData)
						if placed then
							item:Destroy()
							if _G.PlayerData and _G.PlayerData.removeEggFromInventory then
								_G.PlayerData.removeEggFromInventory(player, eggData)
							end
						end
					end
				end
			end)
		end
	end

	local function hookBackpack(backpack: Instance)
		for _, child in ipairs(backpack:GetChildren()) do
			checkItem(child)
		end
		backpack.ChildAdded:Connect(checkItem)
	end

	local bp = player:FindFirstChild("Backpack")
	if bp then hookBackpack(bp) end
	player.ChildAdded:Connect(function(c)
		if c.Name == "Backpack" then hookBackpack(c) end
	end)
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
	releasePlayerPen(player)
end)

print("[GameplayManager] Complete gameplay loop with Egg Inventory, Size Tiers, RedLine Claim & Containment active!")
