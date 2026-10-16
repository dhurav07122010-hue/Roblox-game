--!strict
-- ==============================================================================
-- Steal An Anime Egg: Complete Gameplay Loop Setup Script
-- Run this in the Roblox Studio Command Bar (View -> Command Bar) to permanently
-- configure and install the entire gameplay loop in Edit Mode!
-- ==============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local ServerStorage = game:GetService("ServerStorage")

print("----------------------------------------------------------------------")
print("[Steal An Anime Egg] Installing Complete Gameplay Loop...")
print("----------------------------------------------------------------------")

-- 1. Create or Update ReplicatedStorage.GameplayConfig (ModuleScript)
local gameplayConfig = ReplicatedStorage:FindFirstChild("GameplayConfig") :: ModuleScript?
if not gameplayConfig then
	gameplayConfig = Instance.new("ModuleScript")
	gameplayConfig.Name = "GameplayConfig"
	gameplayConfig.Parent = ReplicatedStorage
end
gameplayConfig.Source = [===[--!strict
-- ReplicatedStorage > GameplayConfig
-- Central configuration for Steal an Anime Egg gameplay loop

local GameplayConfig = {}

-- ==============================================================================
-- 1. DUMBBELL & STRENGTH TRAINING CONFIGURATION
-- ==============================================================================
GameplayConfig.Training = {
	AreaSize = Vector3.new(10, 0.4, 10), -- 10x10 stud training area
	DefaultStrengthGain = 1,            -- Base Strength gain per lift
	Cooldown = 0.8,                     -- Auto-train interval in seconds
	JumpExitDebounce = 1.2,             -- Seconds debounce after jumping off before re-entering
	ExitJumpImpulse = 38,               -- Upward velocity impulse when jumping off
	PadLabel = "🏋️ STRENGTH TRAINING",
}

GameplayConfig.Dumbbells = {
	dumbel1 = {
		Name = "Light Dumbbell",
		PromptAction = "Train (+1 Strength)",
		StrengthGain = 1,
		RequiredStrength = 0,
		Cooldown = 0.8,
		UpgradeCost = 5000,
	},
	dumbel2 = {
		Name = "Medium Dumbbell",
		PromptAction = "Train (+5 Strength)",
		StrengthGain = 5,
		RequiredStrength = 25,
		Cooldown = 0.8,
		UpgradeCost = 25000,
	},
	dumbel3 = {
		Name = "Heavy Dumbbell",
		PromptAction = "Train (+20 Strength)",
		StrengthGain = 20,
		RequiredStrength = 100,
		Cooldown = 0.8,
		UpgradeCost = 0,
	},
}

-- ==============================================================================
-- 2. EGG SPAWNING & PLACEMENT LIMITS
-- ==============================================================================
GameplayConfig.Eggs = {
	EggsPerSpawn = 10,             -- Number of world eggs to spawn on each zone's 'egg spawn'
	Zone1SpawnCount = 10,          -- Fallback spawn count if zone areas are used
	Zone1RequiredStrength = 0,      -- No strength requirement needed to steal eggs
	MaxPlacedCapacity = 30,         -- Maximum 30 placed eggs/pets in player pen
	BaseHatchDuration = 12,        -- In seconds (Day: 12s, Night at 50x: ~0.24s)
	PromptAction = "Steal Egg",
	PromptObject = "Anime Egg",
	MaxSpawnAttempts = 15,         -- Number of retries to find a safe floor spawn position
	BarrierSafetyBuffer = 5,       -- Studs buffer around NightBarrier bounding box
}

-- Different Egg Sizes: Bigger = heavier (slower speed). NO strength requirement!
GameplayConfig.EggSizes = {
	Small = {
		Name = "Small Egg",
		Scale = 0.9,
		RequiredStrength = 0,
		SpeedMultiplier = 1.0,
		Weight = 40, -- 40% spawn chance
	},
	Medium = {
		Name = "Medium Egg",
		Scale = 1.35,
		RequiredStrength = 0,
		SpeedMultiplier = 0.75,
		Weight = 30, -- 30% spawn chance
	},
	Large = {
		Name = "Large Egg",
		Scale = 1.85,
		RequiredStrength = 0,
		SpeedMultiplier = 0.55,
		Weight = 20, -- 20% spawn chance
	},
	Giant = {
		Name = "Giant Egg",
		Scale = 2.4,
		RequiredStrength = 0,
		SpeedMultiplier = 0.38,
		Weight = 10, -- 10% spawn chance
	},
}

-- ==============================================================================
-- 3. CHARACTER / PET LIMITS & INCOME (LEE)
-- ==============================================================================
GameplayConfig.Pets = {
	BaseEquippedLimit = 6,          -- Normal unupgraded pen = 6 pets
	MaxUpgradeLevel = 5,            -- Levels L1 through L5 (L1=7, L2=8, L3=9, L4=10, L5=11)
	Lee = {
		Name = "Rock Lee",
		IncomePerSecond = 1000,     -- Generates exactly 1,000 Money per second
		WalkAnimationId = "",       -- Asset ID (empty if none exists; reported to user)
		WalkSpeed = 10,
		MinWanderWait = 2,
		MaxWanderWait = 5,
	},
}

-- ==============================================================================
-- 4. PEN OVERHEAD DISPLAY
-- ==============================================================================
GameplayConfig.Pens = {
	OverheadHeightOffset = 50,      -- Exactly 50 studs above top of pen bounding box
	MaxDisplayDistance = 350,       -- Visible from across the spawn area
}

return GameplayConfig
]===]
print("[+] Configured ReplicatedStorage.GameplayConfig")

-- 2. Update ServerScriptService.PlayerData (Script)
local playerDataScript = ServerScriptService:FindFirstChild("PlayerData") :: Script?
if not playerDataScript then
	playerDataScript = Instance.new("Script")
	playerDataScript.Name = "PlayerData"
	playerDataScript.Parent = ServerScriptService
end
playerDataScript.Source = [===[--!strict
-- ServerScriptService > PlayerData
-- Authoritative player progression (Strength, Money, Pen Upgrade Level, Speed Tier, Trail inventory & visual rendering)
-- DataStore: PlayerProgression_v1 (Uses consistent string keys: tostring(userId))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local ServerStorage = game:GetService("ServerStorage")

local ShopConfig = require(ReplicatedStorage.ShopConfig)

local DATA_STORE_NAME = "PlayerProgression_v1"
local SessionStore: DataStore? = nil

local initOk, initErr = pcall(function()
	SessionStore = DataStoreService:GetDataStore(DATA_STORE_NAME)
end)
if initOk and SessionStore then
	print(string.format("[PlayerData] Connected to DataStore '%s'.", DATA_STORE_NAME))
else
	warn(string.format("[PlayerData] WARNING: Unable to connect to DataStore '%s' (%s). Studio API access may be disabled. Session memory will be used.", DATA_STORE_NAME, tostring(initErr)))
end

-- Session fallback keeps the game playable if DataStore is unavailable
local sessionMemory: { [string]: any } = {}

local DEFAULT_DATA = {
	Strength = 0,
	Money = 0,
	PenUpgradeLevel = 0,
	SpeedTier = 1,
	Trail = "basic_white",
	OwnedTrails = { "basic_white" },
	EggInventory = {},
}

-- Runtime state keyed by player
local data = {} :: { [Player]: any }

--------------------------------------------------
-- ONE-TIME CLEANUP OF OBSOLETE SHOPS & REMOTES
--------------------------------------------------

for _, remoteName in ipairs({"BuySpeedUpgrade", "EquipTrail", "GetShopState", "ShopStateChanged"}) do
	local r = ReplicatedStorage:FindFirstChild(remoteName)
	if r then
		-- Keep or reuse if needed, don't crash
	end
end

--------------------------------------------------
-- DATASTORE PERSISTENCE (STRING KEY: tostring(userId))
--------------------------------------------------

-- Track whether player cloud profile was loaded successfully (used to prevent overwrite on failure)
local dataLoadedSuccessfully: { [Player]: boolean } = {}

local function loadData(userId: number): (boolean, any)
	local key = tostring(userId)
	if not SessionStore then
		warn(string.format("[PlayerData] DataStore unavailable. Checking session memory fallback for user %s (key: '%s')", tostring(userId), key))
		local mem = sessionMemory[key]
		return false, mem
	end

	local maxRetries = 3
	local attempt = 0
	local lastErr: any = nil

	while attempt < maxRetries do
		attempt += 1
		local ok, res = pcall(function()
			return SessionStore:GetAsync(key)
		end)
		if ok then
			if type(res) == "table" then
				print(string.format("[PlayerData] Successfully loaded profile for user %s (attempt %d, key: '%s')", tostring(userId), attempt, key))
				return true, res
			else
				print(string.format("[PlayerData] No existing profile found for user %s (key: '%s') - initializing new player defaults", tostring(userId), key))
				return true, nil
			end
		else
			lastErr = res
			warn(string.format("[PlayerData] DataStore GetAsync attempt %d failed for user %s (key: '%s'): %s", attempt, tostring(userId), key, tostring(res)))
			if attempt < maxRetries then
				task.wait(attempt * 1.5)
			end
		end
	end

	-- All cloud attempts failed! Check session memory fallback
	local mem = sessionMemory[key]
	if mem then
		warn(string.format("[PlayerData] Recovered user %s data from server session memory fallback", key))
		return false, mem
	end

	return false, nil
end

local function saveData(userId: number, saved: any): boolean
	local key = tostring(userId)
	local saveSuccess = false

	if SessionStore then
		local maxRetries = 2
		local attempt = 0
		while attempt < maxRetries do
			attempt += 1
			local ok, err = pcall(function()
				SessionStore:SetAsync(key, saved)
			end)
			if ok then
				print(string.format("[PlayerData] Successfully saved profile for user %s (key: '%s')", tostring(userId), key))
				saveSuccess = true
				break
			else
				warn(string.format("[PlayerData] DataStore SetAsync attempt %d failed for user %s (key: '%s'): %s", attempt, tostring(userId), key, tostring(err)))
				if attempt < maxRetries then
					task.wait(1.5)
				end
			end
		end
	else
		warn(string.format("[PlayerData] DataStore unavailable (API access disabled). Saving user %s data to session memory only", key))
	end

	sessionMemory[key] = saved
	return saveSuccess
end

local function sanitize(raw: any): any
	local d = {}
	d.Strength = math.max(0, math.floor(tonumber(raw.Strength) or 0))
	d.Money = math.max(0, math.floor(tonumber(raw.Money) or 0))
	d.PenUpgradeLevel = math.clamp(math.floor(tonumber(raw.PenUpgradeLevel) or 0), 0, 5)
	d.SpeedTier = math.clamp(math.floor(tonumber(raw.SpeedTier) or 1), 1, ShopConfig.MAX_SPEED_TIER)
	local owned = {}
	if type(raw.OwnedTrails) == "table" then
		for _, id in ipairs(raw.OwnedTrails) do
			if type(id) == "string" then owned[id] = true end
		end
	end
	owned[ShopConfig.BASIC_TRAIL_ID] = true
	d.OwnedTrails = owned
	d.Trail = type(raw.Trail) == "string" and owned[raw.Trail] and raw.Trail or ShopConfig.BASIC_TRAIL_ID

	local eggs = {}
	if type(raw.EggInventory) == "table" then
		for _, e in ipairs(raw.EggInventory) do
			if type(e) == "table" and type(e.SizeTier) == "string" then
				table.insert(eggs, {
					SizeTier = e.SizeTier,
					Scale = tonumber(e.Scale) or 1.0,
					Name = tostring(e.Name or "Anime Egg"),
				})
			end
		end
	end
	d.EggInventory = eggs

	return d
end

--------------------------------------------------
-- SPEED TIER ENFORCEMENT (AUTHORITATIVE)
--------------------------------------------------

local function applyWalkSpeed(player: Player)
	local d = data[player]
	if not d or not d.SpeedTier then return end
	local tierConfig = ShopConfig.SpeedTiers[d.SpeedTier]
	if not tierConfig then return end

	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 4) :: Humanoid?

	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.WalkSpeed = tierConfig.WalkSpeed
	end
	player:SetAttribute("BaseSpeed", tierConfig.WalkSpeed)
end

--------------------------------------------------
-- TRAIL VISUAL ATTACHMENT SYSTEM
--------------------------------------------------

local TRAIL_VISUALS: { [string]: {
	Colors: ColorSequence,
	LightEmission: number,
	Transparency: NumberSequence,
	Lifetime: number,
} } = {
	basic_white = {
		Colors = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
		LightEmission = 0.6,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 1.0),
		}),
		Lifetime = 0.45,
	},
	electric_gold = {
		Colors = ColorSequence.new(
			Color3.fromRGB(255, 240, 70),
			Color3.fromRGB(255, 175, 20)
		),
		LightEmission = 0.9,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1.0),
		}),
		Lifetime = 0.5,
	},
	cyan = {
		Colors = ColorSequence.new(
			Color3.fromRGB(50, 235, 255),
			Color3.fromRGB(0, 140, 255)
		),
		LightEmission = 0.95,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1.0),
		}),
		Lifetime = 0.5,
	},
	anime_fire = {
		Colors = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 80)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 130, 20)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 30, 10)),
		}),
		LightEmission = 1.0,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1.0),
		}),
		Lifetime = 0.55,
	},
	rainbow = {
		Colors = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 50, 50)),
			ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 180, 40)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 240, 50)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(50, 240, 80)),
			ColorSequenceKeypoint.new(0.8, Color3.fromRGB(40, 180, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 60, 255)),
		}),
		LightEmission = 0.95,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1.0),
		}),
		Lifetime = 0.55,
	},
	void = {
		Colors = ColorSequence.new(
			Color3.fromRGB(180, 40, 255),
			Color3.fromRGB(70, 10, 160)
		),
		LightEmission = 0.85,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1.0),
		}),
		Lifetime = 0.6,
	},
}

local function removeCharacterTrail(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		for _, child in ipairs(root:GetChildren()) do
			if child.Name == "PlayerTrail" or child.Name == "TrailAttachment0" or child.Name == "TrailAttachment1" then
				child:Destroy()
			end
		end
	end
end

local function applyTrail(player: Player)
	local d = data[player]
	if not d then return end

	local character = player.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		or character:WaitForChild("HumanoidRootPart", 4) :: BasePart?
	if not root then return end

	removeCharacterTrail(character)

	local trailId = d.Trail
	if not trailId then return end

	local visual = TRAIL_VISUALS[trailId] or TRAIL_VISUALS[ShopConfig.BASIC_TRAIL_ID]
	if not visual then return end

	local att0 = Instance.new("Attachment")
	att0.Name = "TrailAttachment0"
	att0.Position = Vector3.new(0, 0.85, 0)
	att0.Parent = root

	local att1 = Instance.new("Attachment")
	att1.Name = "TrailAttachment1"
	att1.Position = Vector3.new(0, -0.85, 0)
	att1.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = "PlayerTrail"
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Color = visual.Colors
	trail.Transparency = visual.Transparency
	trail.LightEmission = visual.LightEmission
	trail.LightInfluence = 0
	trail.Lifetime = visual.Lifetime
	trail.MinLength = 0.1
	trail.FaceCamera = true
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.0),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	trail.Parent = root
end

--------------------------------------------------
-- LEADERSTATS (STRENGTH & MONEY)
--------------------------------------------------

local function setupLeaderstats(player: Player): (IntValue, IntValue)
	local stats = player:FindFirstChild("leaderstats") :: Folder?
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end

	local oldCoins = stats:FindFirstChild("Coins")
	if oldCoins then
		oldCoins:Destroy()
	end

	local strength = stats:FindFirstChild("Strength") :: IntValue?
	if not strength then
		strength = Instance.new("IntValue")
		strength.Name = "Strength"
		strength.Parent = stats
	end

	local money = stats:FindFirstChild("Money") :: IntValue?
	if not money then
		money = Instance.new("IntValue")
		money.Name = "Money"
		money.Parent = stats
	end

	return strength, money
end

--------------------------------------------------
-- EGG INVENTORY PERSISTENCE & TOOL RESTORATION
--------------------------------------------------

-- Create physical egg Tool for Backpack
local function createEggTool(eggData: any): Tool
	local tool = Instance.new("Tool")
	tool.Name = eggData.Name or "Anime Egg"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("IsAnimeEgg", true)
	tool:SetAttribute("SizeTier", eggData.SizeTier or "Small")
	tool:SetAttribute("Scale", tonumber(eggData.Scale) or 1.0)
	tool:SetAttribute("TierName", eggData.Name or "Anime Egg")

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
			eggVisual:ScaleTo(0.55 * (tonumber(eggData.Scale) or 1.0))
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

	return tool
end

-- Safely restore egg tools into Backpack without creating any duplicates
local function restoreEggTools(player: Player)
	local d = data[player]
	if not d or type(d.EggInventory) ~= "table" then return end
	local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 4)
	if not backpack then return end

	-- Find all existing egg tools currently in Backpack or equipped in Character
	local existingTools: { Tool } = {}
	for _, item in ipairs(backpack:GetChildren()) do
		if item:IsA("Tool") and item:GetAttribute("IsAnimeEgg") == true then
			table.insert(existingTools, item)
		end
	end
	if player.Character then
		for _, item in ipairs(player.Character:GetChildren()) do
			if item:IsA("Tool") and item:GetAttribute("IsAnimeEgg") == true then
				table.insert(existingTools, item)
			end
		end
	end

	-- Only create tools if the player is missing them
	if #existingTools < #d.EggInventory then
		for i = #existingTools + 1, #d.EggInventory do
			local eggData = d.EggInventory[i]
			if eggData then
				local tool = createEggTool(eggData)
				tool.Parent = backpack
			end
		end
	elseif #existingTools > #d.EggInventory then
		-- If there are excess duplicate tools, clean them up
		for i = #d.EggInventory + 1, #existingTools do
			existingTools[i]:Destroy()
		end
	end

	player:SetAttribute("EggCount", #d.EggInventory)
end

-- Gather current egg inventory from held tools or fallback to memory
local function serializeEggInventory(player: Player): { any }
	-- EggInventory is the authoritative server-side record. Tools are only its
	-- physical representation; using them as the source of truth can silently
	-- drop saved eggs when a Backpack/Character update is in flight.
	local d = data[player]
	local eggs = {}
	if not d or type(d.EggInventory) ~= "table" then
		return eggs
	end

	for _, e in ipairs(d.EggInventory) do
		if type(e) == "table" then
			table.insert(eggs, {
				SizeTier = tostring(e.SizeTier or "Small"),
				Scale = tonumber(e.Scale) or 1.0,
				Name = tostring(e.Name or "Anime Egg"),
			})
		end
	end
	return eggs
end

--------------------------------------------------
-- PLAYER LIFECYCLE & PERSISTENCE SAFETY
--------------------------------------------------

local saveInProgress: { [Player]: boolean } = {}

local function savePlayerData(player: Player): boolean
	-- Serialize writes per player so autosave, leave, and shutdown cannot
	-- complete out of order and overwrite a newer snapshot with an older one.
	local waitElapsed = 0
	while saveInProgress[player] and waitElapsed < 10 do
		task.wait(0.1)
		waitElapsed += 0.1
	end

	local d = data[player]
	if not d then return false end

	-- CRITICAL: Refuse to overwrite valid cloud data if load had failed.
	if dataLoadedSuccessfully[player] == false then
		warn(string.format("[PlayerData] OVERWRITE PROTECTION ACTIVE for user %s (%d). Skipping DataStore save to prevent progress wipe.", player.Name, player.UserId))
		return false
	end

	saveInProgress[player] = true
	local ok, result = pcall(function()
		local arr = {}
		for id in pairs(d.OwnedTrails) do table.insert(arr, id) end
		local eggList = serializeEggInventory(player)
		return saveData(player.UserId, {
			Strength = d.Strength,
			Money = d.Money,
			PenUpgradeLevel = d.PenUpgradeLevel,
			SpeedTier = d.SpeedTier,
			Trail = d.Trail,
			OwnedTrails = arr,
			EggInventory = eggList,
		})
	end)
	saveInProgress[player] = nil

	if not ok then
		warn(string.format("[PlayerData] Unexpected error while saving %s: %s", player.Name, tostring(result)))
		return false
	end
	return result == true
end

local function onPlayerAdded(player: Player)
	local ok, loaded = loadData(player.UserId)
	if ok then
		dataLoadedSuccessfully[player] = true
		if loaded and type(loaded) == "table" then
			data[player] = sanitize(loaded)
		else
			-- Genuinely new player with no prior cloud profile
			data[player] = sanitize(DEFAULT_DATA)
		end
	else
		-- Cloud load failed!
		if loaded and type(loaded) == "table" then
			-- Successfully recovered from server session memory
			dataLoadedSuccessfully[player] = true
			data[player] = sanitize(loaded)
		else
			-- Complete DataStore failure! Enable overwrite protection
			dataLoadedSuccessfully[player] = false
			data[player] = sanitize(DEFAULT_DATA)
			warn(string.format("[PlayerData] CRITICAL: DataStore load failed for user %s (%d). Overwrite protection active - cloud saving disabled for this session.", player.Name, player.UserId))
		end
	end

	local strength, money = setupLeaderstats(player)
	strength.Value = data[player].Strength
	money.Value = data[player].Money
	player:SetAttribute("EggCount", #data[player].EggInventory)

	local tierConfig = ShopConfig.SpeedTiers[data[player].SpeedTier]
	player:SetAttribute("BaseSpeed", tierConfig and tierConfig.WalkSpeed or 16)
	player:SetAttribute("PenUpgradeLevel", data[player].PenUpgradeLevel or 0)
	player:SetAttribute("EquippedPetLimit", 6 + math.clamp(data[player].PenUpgradeLevel or 0, 0, 5))

	player.CharacterAdded:Connect(function(character)
		task.defer(function()
			applyWalkSpeed(player)
			applyTrail(player)
			restoreEggTools(player)
		end)
	end)

	if player.Character then
		task.defer(function()
			applyWalkSpeed(player)
			applyTrail(player)
			restoreEggTools(player)
		end)
	else
		task.defer(function()
			restoreEggTools(player)
		end)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	onPlayerAdded(p)
end

local function onPlayerRemoving(player: Player)
	savePlayerData(player)
	data[player] = nil
	dataLoadedSuccessfully[player] = nil
end
Players.PlayerRemoving:Connect(onPlayerRemoving)

game:BindToClose(function()
	local activeSaves = 0
	for p, _ in pairs(data) do
		activeSaves += 1
		task.spawn(function()
			pcall(savePlayerData, p)
			activeSaves -= 1
		end)
	end
	local elapsed = 0
	while activeSaves > 0 and elapsed < 25 do
		task.wait(0.1)
		elapsed += 0.1
	end
end)

--------------------------------------------------
-- RELIABLE AUTOSAVE SYSTEM (EVERY 120s STAGGERED)
--------------------------------------------------
task.spawn(function()
	while true do
		task.wait(120)
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Parent and data[p] and dataLoadedSuccessfully[p] ~= false then
				task.spawn(function()
					savePlayerData(p)
				end)
				task.wait(0.5) -- Stagger saves across players to stay well within DataStore budget
			end
		end
	end
end)

--------------------------------------------------
-- EXTERNAL API (STRENGTH, MONEY, SPEED, & PENS)
--------------------------------------------------

local TRAIL_MULT = {} :: { [Player]: number }
local function recomputeTrailMult(player: Player)
	local d = data[player]
	if not d then return end
	local m = 1.0
	for _, t in ipairs(ShopConfig.Trails) do
		if t.id == d.Trail then m = t.multiplier break end
	end
	TRAIL_MULT[player] = m
end

_G.PlayerData = {
	getData = function(player: Player): any
		return data[player]
	end,
	getTrailMultiplier = function(player: Player): number
		recomputeTrailMult(player)
		return TRAIL_MULT[player] or 1.0
	end,
	addStrength = function(player: Player, amount: number): boolean
		local d = data[player]
		if not d then return false end
		amount = math.floor(amount)
		if amount <= 0 then return false end
		d.Strength += amount
		local stat = player:FindFirstChild("leaderstats") and player:FindFirstChild("leaderstats"):FindFirstChild("Strength") :: IntValue?
		if stat then stat.Value = d.Strength end
		return true
	end,
	getStrength = function(player: Player): number
		local d = data[player]
		return d and d.Strength or 0
	end,
	addMoney = function(player: Player, amount: number): boolean
		local d = data[player]
		if not d then return false end
		amount = math.floor(amount)
		if amount <= 0 then return false end
		d.Money += amount
		local stat = player:FindFirstChild("leaderstats") and player:FindFirstChild("leaderstats"):FindFirstChild("Money") :: IntValue?
		if stat then stat.Value = d.Money end
		return true
	end,
	getMoney = function(player: Player): number
		local d = data[player]
		return d and d.Money or 0
	end,
	deductMoney = function(player: Player, amount: number): boolean
		local d = data[player]
		if not d then return false end
		amount = math.floor(amount)
		if amount <= 0 then return false end
		if d.Money < amount then return false end
		d.Money -= amount
		local stat = player:FindFirstChild("leaderstats") and player:FindFirstChild("leaderstats"):FindFirstChild("Money") :: IntValue?
		if stat then stat.Value = d.Money end
		return true
	end,
	getPenUpgradeLevel = function(player: Player): number
		local d = data[player]
		return d and d.PenUpgradeLevel or 0
	end,
	setPenUpgradeLevel = function(player: Player, level: number): boolean
		local d = data[player]
		if not d then return false end
		d.PenUpgradeLevel = math.clamp(math.floor(level), 0, 5)
		player:SetAttribute("PenUpgradeLevel", d.PenUpgradeLevel)
		player:SetAttribute("EquippedPetLimit", 6 + d.PenUpgradeLevel)
		return true
	end,
	getEquippedPetLimit = function(player: Player): number
		local d = data[player]
		local level = d and d.PenUpgradeLevel or 0
		-- Normal unupgraded pen = 6 pets; each upgrade level +1 up to Pen L5 = 11 pets
		return 6 + math.clamp(level, 0, 5)
	end,
	applyWalkSpeed = function(player: Player)
		applyWalkSpeed(player)
	end,
	setSpeedTier = function(player: Player, tier: number): boolean
		local d = data[player]
		if not d then return false end
		tier = math.clamp(math.floor(tier), 1, ShopConfig.MAX_SPEED_TIER)
		d.SpeedTier = tier
		applyWalkSpeed(player)
		return true
	end,
	setTrail = function(player: Player, trailId: string): boolean
		local d = data[player]
		if not d then return false end
		d.Trail = trailId
		d.OwnedTrails[trailId] = true
		applyTrail(player)
		return true
	end,
	getEggInventory = function(player: Player): { any }
		local d = data[player]
		return (d and d.EggInventory) or {}
	end,
	addEggToInventory = function(player: Player, eggData: any): boolean
		local d = data[player]
		if not d then return false end
		if type(d.EggInventory) ~= "table" then
			d.EggInventory = {}
		end
		table.insert(d.EggInventory, eggData)
		player:SetAttribute("EggCount", #d.EggInventory)
		return true
	end,
	removeEggFromInventory = function(player: Player, target: any?): any
		local d = data[player]
		if not d or type(d.EggInventory) ~= "table" or #d.EggInventory == 0 then
			return nil
		end
		local removeIdx = nil
		if type(target) == "number" then
			removeIdx = math.clamp(target, 1, #d.EggInventory)
		elseif type(target) == "table" and target.Name then
			for i, egg in ipairs(d.EggInventory) do
				if egg.Name == target.Name and (not target.SizeTier or egg.SizeTier == target.SizeTier) then
					removeIdx = i
					break
				end
			end
		end
		-- Never consume a different egg when the requested egg cannot be
		-- matched. A failed match is safer than silently deleting inventory.
		if not removeIdx then
			warn("[PlayerData] Refused to remove egg: no matching inventory entry for " .. player.Name)
			return nil
		end
		local egg = table.remove(d.EggInventory, removeIdx)
		player:SetAttribute("EggCount", #d.EggInventory)
		return egg
	end,
	getEggInventoryCount = function(player: Player): number
		local d = data[player]
		return (d and type(d.EggInventory) == "table") and #d.EggInventory or 0
	end,
	createEggTool = createEggTool,
	restoreEggTools = restoreEggTools,
	savePlayerData = savePlayerData,
	isDataLoaded = function(player: Player): boolean
		return dataLoadedSuccessfully[player] == true
	end,
}

print("[PlayerData] Initialized with Strength, Money, Speed, and Pen Level systems active.")
]===]
print("[+] Configured ServerScriptService.PlayerData (Strength, Money, Pen Upgrade & Limits)")

-- 3. Create or Update ServerScriptService.GameplayManager (Script)
local gameplayManagerScript = ServerScriptService:FindFirstChild("GameplayManager") :: Script?
if not gameplayManagerScript then
	gameplayManagerScript = Instance.new("Script")
	gameplayManagerScript.Name = "GameplayManager"
	gameplayManagerScript.Parent = ServerScriptService
end
gameplayManagerScript.Source = [===[--!strict
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

-- Cooldown and debounce trackers for client-triggered actions
local lastUpgradeTime: { [Player]: number } = {}
local lastPlaceTime: { [Player]: number } = {}
local lastDropTime: { [Player]: number } = {}
local lastPickupTime: { [Player]: number } = {}

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
	UpdatePenUpgradeDisplay: (() -> ())?,
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

		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not root or not hum or hum.Health <= 0 then return end

		local dist = (root.Position - board.Position).Magnitude
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
			showFloatingFeedback(board.Position + Vector3.new(0, 1.5, 0), "⭐ Dumbbell already at Max Level!", Color3.fromRGB(255, 200, 80))
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
			showFloatingFeedback(board.Position + Vector3.new(0, 1.5, 0),
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

-- Add a clickable pen-upgrade GUI to the existing sign beside each pen.
-- This only adds script-created UI/interactions; it does not reposition or rebuild the map.
local PEN_UPGRADE_COSTS = { 5000, 25000, 75000, 150000, 300000 }

local function setupPenUpgradeGui(penInfo: PenInfo)
	local sign = penInfo.Sign
	if not sign then
		warn(string.format("[GameplayManager] Pen %d has no sign model; skipping pen upgrade GUI.", penInfo.Index))
		return
	end

	local signPart: BasePart? = sign.PrimaryPart
	if not signPart then
		local bestArea = 0
		for _, desc in ipairs(sign:GetDescendants()) do
			if desc:IsA("BasePart") then
				local area = desc.Size.X * desc.Size.Y + desc.Size.Y * desc.Size.Z + desc.Size.X * desc.Size.Z
				if area > bestArea then
					bestArea = area
					signPart = desc
				end
			end
		end
	end
	if not signPart then
		warn(string.format("[GameplayManager] Pen %d sign has no BasePart; skipping pen upgrade GUI.", penInfo.Index))
		return
	end

	for _, child in ipairs(signPart:GetChildren()) do
		if child.Name:match("^PenUpgradeGui") or child.Name == "PenUpgradeClickDetector" then
			child:Destroy()
		end
	end

	local levelLabels: { TextLabel } = {}
	local actionLabels: { TextLabel } = {}

	local function createGuiOnFace(face: Enum.NormalId, suffix: string)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "PenUpgradeGui_" .. suffix
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 32
		gui.LightInfluence = 0
		gui.AlwaysOnTop = true
		gui.Parent = signPart

		local frame = Instance.new("Frame")
		frame.Name = "Panel"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromRGB(25, 29, 40)
		frame.BorderSizePixel = 0
		frame.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 195, 0)
		stroke.Thickness = 3
		stroke.Parent = frame

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, -8, 0.28, 0)
		title.Position = UDim2.new(0, 4, 0.02, 0)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.FredokaOne
		title.TextScaled = true
		title.TextColor3 = Color3.fromRGB(255, 205, 55)
		title.Text = "PEN UPGRADE"
		title.Parent = frame

		local levelLabel = Instance.new("TextLabel")
		levelLabel.Name = "Level"
		levelLabel.Size = UDim2.new(1, -8, 0.25, 0)
		levelLabel.Position = UDim2.new(0, 4, 0.30, 0)
		levelLabel.BackgroundTransparency = 1
		levelLabel.Font = Enum.Font.FredokaOne
		levelLabel.TextScaled = true
		levelLabel.TextColor3 = Color3.new(1, 1, 1)
		levelLabel.Parent = frame
		table.insert(levelLabels, levelLabel)

		local actionLabel = Instance.new("TextLabel")
		actionLabel.Name = "Action"
		actionLabel.Size = UDim2.new(1, -8, 0.34, 0)
		actionLabel.Position = UDim2.new(0, 4, 0.57, 0)
		actionLabel.BackgroundColor3 = Color3.fromRGB(46, 180, 92)
		actionLabel.Font = Enum.Font.FredokaOne
		actionLabel.TextScaled = true
		actionLabel.TextColor3 = Color3.new(1, 1, 1)
		actionLabel.Parent = frame
		local actionCorner = Instance.new("UICorner")
		actionCorner.CornerRadius = UDim.new(0, 6)
		actionCorner.Parent = actionLabel
		table.insert(actionLabels, actionLabel)

		local hint = Instance.new("TextLabel")
		hint.Name = "Hint"
		hint.Size = UDim2.new(1, -8, 0.10, 0)
		hint.Position = UDim2.new(0, 4, 0.90, 0)
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.GothamBold
		hint.TextScaled = true
		hint.TextColor3 = Color3.fromRGB(210, 210, 210)
		hint.Text = "CLICK SIGN TO UPGRADE"
		hint.Parent = frame
	end

	createGuiOnFace(Enum.NormalId.Front, "Front")
	createGuiOnFace(Enum.NormalId.Back, "Back")

	local click = Instance.new("ClickDetector")
	click.Name = "PenUpgradeClickDetector"
	click.MaxActivationDistance = 16
	click.Parent = signPart

	local function refresh()
		local level = (_G.PlayerData and _G.PlayerData.getPenUpgradeLevel and penInfo.Owner)
			and _G.PlayerData.getPenUpgradeLevel(penInfo.Owner) or (penInfo.Model:GetAttribute("PenUpgradeLevel") or 0)
		level = math.clamp(tonumber(level) or 0, 0, 5)

		local levelText: string
		if penInfo.Owner then
			levelText = string.format("LEVEL %d  •  PET LIMIT %d", level, 6 + level)
		else
			levelText = "UNCLAIMED PEN"
		end

		local actionText: string
		local actionColor: Color3
		if level >= 5 then
			actionText = "MAX LEVEL"
			actionColor = Color3.fromRGB(90, 100, 115)
		else
			actionText = string.format("UPGRADE  $%d", PEN_UPGRADE_COSTS[level + 1])
			actionColor = Color3.fromRGB(46, 180, 92)
		end

		for _, lbl in ipairs(levelLabels) do
			lbl.Text = levelText
		end
		for _, act in ipairs(actionLabels) do
			act.Text = actionText
			act.BackgroundColor3 = actionColor
		end
	end

	local function performPenUpgrade(player: Player)
		if penInfo.Owner ~= player then
			showFloatingFeedback(signPart.Position, "This is not your pen!", Color3.fromRGB(255, 75, 75))
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - signPart.Position).Magnitude > 25 then return end
		local level = (_G.PlayerData and _G.PlayerData.getPenUpgradeLevel and _G.PlayerData.getPenUpgradeLevel(player))
			or (penInfo.Model:GetAttribute("PenUpgradeLevel") or 0)
		level = math.clamp(tonumber(level) or 0, 0, 5)
		if level >= 5 then
			showFloatingFeedback(signPart.Position, "Pen is already at maximum level!", Color3.fromRGB(255, 205, 55))
			return
		end
		local cost = PEN_UPGRADE_COSTS[level + 1]
		if not _G.PlayerData or not _G.PlayerData.getMoney or not _G.PlayerData.deductMoney or not _G.PlayerData.setPenUpgradeLevel then
			warn("[GameplayManager] PlayerData pen upgrade API is unavailable.")
			return
		end
		if _G.PlayerData.getMoney(player) < cost then
			showFloatingFeedback(signPart.Position, string.format("Need $%d to upgrade your pen!", cost), Color3.fromRGB(255, 75, 75))
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
		refresh()
		showFloatingFeedback(signPart.Position + Vector3.new(0, 2, 0),
			string.format("PEN UPGRADED! Level %d • Pet limit %d", newLevel, 6 + newLevel),
			Color3.fromRGB(80, 255, 120))
	end

	click.MouseClick:Connect(performPenUpgrade)
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

	-- Existing dumbel1, dumbel2, dumbel3 models remain safe and untouched in Workspace.
	-- Visual prototype hiding is handled client-side by StatsHUDController.

	-- Set up overhead display, training area and containment barriers for each real pen
	for _, p in ipairs(pensList) do
		setupPenOverheadDisplay(p)
		setupPenTrainingArea(p)
		setupPenUpgradeGui(p)
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
			player:GetAttributeChangedSignal("PenUpgradeLevel"):Connect(function()
				if pen.Owner == player then
					updatePenOwnerDisplay(pen, player)
				end
			end)
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
	newEgg:SetAttribute("HomeSpawnCFrame", spawnCF)

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

	-- Respawn replacement world egg after 15s during Day (only if below total capacity)
	task.delay(15, function()
		if Lighting:GetAttribute("Phase") == "DAY" then
			worldEggsFolder = getOrCreateWorldEggsFolder()
			local eggSpawns = findEggSpawnParts()
			local maxAllowed = (#eggSpawns > 0 and (#eggSpawns * (GameplayConfig.Eggs.EggsPerSpawn or 10))) or (GameplayConfig.Eggs.Zone1SpawnCount or 15)
			if #worldEggsFolder:GetChildren() < maxAllowed then
				local tierKey, tierData = pickRandomEggTier()
				local scale = tierData.Scale or 1.0
				local targetCF = homeSpawnCF
				if not targetCF and #eggSpawns > 0 then
					local baseExtents = getEggExtents()
					targetCF = getSpawnCFrameOnEggSpawn(eggSpawns[math.random(1, #eggSpawns)], baseExtents * scale)
				end
				if targetCF then
					spawnSingleWorldEgg(sourceZone or "Zone1", targetCF, {
						SizeTier = tierKey,
						Scale = scale,
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
		if pen.UpdateSignDisplay then
			pen.UpdateSignDisplay()
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
	if player:FindFirstChild("Backpack") then
		for _, item in ipairs(player.Backpack:GetChildren()) do
			if item:IsA("Tool") and item:GetAttribute("IsAnimeEgg") == true then
				eggTool = item
				break
			end
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
			Scale = tonumber(eggTool:GetAttribute("Scale")) or 1.0,
			Name = eggTool:GetAttribute("TierName") or "Anime Egg",
		}
	elseif _G.PlayerData and _G.PlayerData.getEggInventory and #_G.PlayerData.getEggInventory(player) > 0 then
		local inv = _G.PlayerData.getEggInventory(player)
		local rawEgg = inv[#inv]
		if rawEgg then
			eggData = {
				SizeTier = rawEgg.SizeTier or "Small",
				Scale = tonumber(rawEgg.Scale) or 1.0,
				Name = rawEgg.Name or "Anime Egg",
			}
		end
	end

	if not eggData then
		showFloatingFeedback(penInfo.EggArea.Position + Vector3.new(0, 2, 0),
			"No eggs in inventory! Steal one from a zone!", Color3.fromRGB(255, 200, 80))
		return false
	end

	local placed = placeEggInPen(player, penInfo, eggData)
	if placed then
		if eggTool then
			eggTool:Destroy()
		end
		if _G.PlayerData and _G.PlayerData.removeEggFromInventory then
			_G.PlayerData.removeEggFromInventory(player, eggData)
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

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return end

	local playerDist = (root.Position - pen.EggArea.Position).Magnitude
	local maxAllowedDist = math.max(35, pen.EggArea.Size.Magnitude / 2 + 15)
	if playerDist > maxAllowedDist then
		showFloatingFeedback(root.Position + Vector3.new(0, 2.5, 0), "Too far from your pen!", Color3.fromRGB(255, 100, 100))
		return
	end

	local now = os.clock()
	local last = lastPlaceTime[player] or 0
	if (now - last) < 0.35 then
		return
	end
	lastPlaceTime[player] = now

	local eggArea = pen.EggArea
	local rel = eggArea.CFrame:PointToObjectSpace(hitPosition)
	local halfX = (eggArea.Size.X / 2) + 2.5
	local halfZ = (eggArea.Size.Z / 2) + 2.5

	-- Check if click is anywhere in or on the pen platform
	if math.abs(rel.X) > halfX or math.abs(rel.Z) > halfZ then
		showFloatingFeedback(hitPosition, "Tap inside your pen platform to place this egg!", Color3.fromRGB(255, 200, 80))
		return
	end

	-- Check pen capacity BEFORE consuming any egg
	local currentPlaced = getPlacedItemCount(pen)
	if currentPlaced >= GameplayConfig.Eggs.MaxPlacedCapacity then
		showFloatingFeedback(eggArea.Position + Vector3.new(0, 2, 0),
			"❌ Pen Full! (30/30 Eggs placed)", Color3.fromRGB(255, 75, 75))
		return
	end

	-- Clamp within usable margins
	local usableX = math.max(1, (eggArea.Size.X / 2) - 2.0)
	local usableZ = math.max(1, (eggArea.Size.Z / 2) - 2.0)
	local clampedX = math.clamp(rel.X, -usableX, usableX)
	local clampedZ = math.clamp(rel.Z, -usableZ, usableZ)

	-- Find egg tool or inventory egg
	local eggTool: Tool? = nil
	if player:FindFirstChild("Backpack") then
		for _, item in ipairs(player.Backpack:GetChildren()) do
			if item:IsA("Tool") and item:GetAttribute("IsAnimeEgg") == true then
				eggTool = item
				break
			end
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
			Scale = tonumber(eggTool:GetAttribute("Scale")) or 1.0,
			Name = eggTool:GetAttribute("TierName") or "Anime Egg",
		}
	elseif _G.PlayerData and _G.PlayerData.getEggInventory and #_G.PlayerData.getEggInventory(player) > 0 then
		local inv = _G.PlayerData.getEggInventory(player)
		local rawEgg = inv[#inv]
		if rawEgg then
			eggData = {
				SizeTier = rawEgg.SizeTier or "Small",
				Scale = tonumber(rawEgg.Scale) or 1.0,
				Name = rawEgg.Name or "Anime Egg",
			}
		end
	end

	if not eggData then
		showFloatingFeedback(eggArea.Position + Vector3.new(0, 2, 0),
			"No eggs in inventory! Steal one from a zone!", Color3.fromRGB(255, 200, 80))
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
		end
		if _G.PlayerData and _G.PlayerData.removeEggFromInventory then
			_G.PlayerData.removeEggFromInventory(player, eggData)
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

	local baseExtents = getEggExtents()
	local eggSpawnParts = findEggSpawnParts()

	if #eggSpawnParts > 0 then
		local eggsPerSpawn = GameplayConfig.Eggs.EggsPerSpawn or 10

		for _, spawnPart in ipairs(eggSpawnParts) do
			-- Resolve the actual zone containing this spawn part instead of using
			-- the first ancestor Model (which may be a decorative sub-model).
			local zoneContainer: Instance? = nil
			local zones = Workspace:FindFirstChild("Zones")
			if zones then
				for _, zone in ipairs(zones:GetChildren()) do
					if spawnPart:IsDescendantOf(zone) then
						zoneContainer = zone
						break
					end
				end
			end
			local zoneName = zoneContainer and zoneContainer.Name or "Zone1"
			local barrier: BasePart? = nil
			local barrierInstance = (zoneContainer and zoneContainer:FindFirstChild("NightBarrier", true))
				or Workspace:FindFirstChild("NightBarrier", true)
			if barrierInstance and barrierInstance:IsA("BasePart") then
				barrier = barrierInstance
			end
			local zoneArea: BasePart? = nil
			if zoneContainer then
				local areaInstance = zoneContainer:FindFirstChild("ZoneArea", true) or zoneContainer:FindFirstChild("Area", true)
				if areaInstance and areaInstance:IsA("BasePart") then
					zoneArea = areaInstance
				end
			end

			local existingCount = 0
			for _, egg in ipairs(worldEggsFolder:GetChildren()) do
				if (egg:GetPivot().Position - spawnPart.Position).Magnitude < math.max(spawnPart.Size.Magnitude, 15) then
					existingCount += 1
				end
			end

			local needed = math.max(0, eggsPerSpawn - existingCount)
			for _ = 1, needed do
				local tierKey, tierData = pickRandomEggTier()
				local scale = tierData.Scale or 1.0
				local eggExtents = baseExtents * scale
				local spawnCF: CFrame? = getSpawnCFrameOnEggSpawn(spawnPart, eggExtents)

				-- Named spawn parts used to bypass the fallback floor safety check.
				-- If one overlaps a NightBarrier, move the egg to a safe floor point;
				-- if no safe point can be found, skip this spawn rather than spawning
				-- an egg on top of the barrier.
				if barrier and isOverlappingNightBarrier(spawnCF.Position, eggExtents, barrier) then
					local safePos = zoneArea and findSafeZone1FloorSpawn(zoneArea, barrier, eggExtents)
					spawnCF = safePos and CFrame.new(safePos) or nil
				end

				if spawnCF then
					spawnSingleWorldEgg(zoneName, spawnCF, {
						SizeTier = tierKey,
						Scale = scale,
						Name = tierData.Name,
						SpeedMultiplier = tierData.SpeedMultiplier,
					})
				end
			end
		end
	else
		-- Fallback to Zone1 floor
		local zones = Workspace:FindFirstChild("Zones")
		local zone1 = zones and zones:FindFirstChild("Zone1") or Workspace:FindFirstChild("Zone1")
		local zoneArea = zone1 and (zone1:FindFirstChild("ZoneArea", true) or zone1:FindFirstChild("Area", true)) :: BasePart?
		local barrier = (zone1 and zone1:FindFirstChild("NightBarrier", true))
			or (Workspace:FindFirstChild("NightBarrier", true)) :: BasePart?
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
	lastUpgradeTime[player] = nil
	lastPlaceTime[player] = nil
	lastDropTime[player] = nil
	lastPickupTime[player] = nil
	releasePlayerPen(player)
end)

print("[GameplayManager] Complete gameplay loop with Egg Inventory, Size Tiers, RedLine Claim & Containment active!")
]===]
print("[+] Configured ServerScriptService.GameplayManager (Pens, Eggs, Dumbbells, Lee Income & Wandering)")

-- 4. Create or Update StarterPlayerScripts.StatsHUDController (LocalScript)
local statsHudScript = StarterPlayerScripts:FindFirstChild("StatsHUDController") :: LocalScript?
if not statsHudScript then
	statsHudScript = Instance.new("LocalScript")
	statsHudScript.Name = "StatsHUDController"
	statsHudScript.Parent = StarterPlayerScripts
end
statsHudScript.Source = [===[--!strict
-- StarterPlayer > StarterPlayerScripts > StatsHUDController
-- Redesigned Bottom-Left Stats Counters & Client Gameplay Controller:
--   1. Compact Outlined Counters (Speed 👟, Money 💵, Strength 🏋️) - sized sleek & unobtrusive
--   2. Strict Dumbbell Visibility: Other players' dumbbells are hidden; visible ONLY to owner
--   3. Instant Jump-To-Exit Training Handler via UserInputService

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local SCREEN_GUI_NAME = "StatsHUD"
local CONTAINER_NAME = "StatsHUDContainer"

--------------------------------------------------------------------------------
-- 1. COMPACT NUMBER FORMATTING (SIMULATOR STYLE: K, M, B, T, Qa, etc.)
--------------------------------------------------------------------------------
local SUFFIXES = {
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd"
}

local function formatCompactStat(value: number): string
	if value < 0 then
		return "-" .. formatCompactStat(-value)
	end
	if value < 1000 then
		return tostring(math.floor(value))
	end

	local exp = math.floor(math.log(value, 10) / 3)
	local index = exp + 1

	if index > #SUFFIXES then
		index = #SUFFIXES
		exp = #SUFFIXES - 1
	end

	local divisor = 10 ^ (exp * 3)
	local scaled = math.floor((value / divisor) * 10) / 10
	local suffix = SUFFIXES[index]

	if scaled == math.floor(scaled) then
		return string.format("%.0f%s", scaled, suffix)
	else
		return string.format("%.1f%s", scaled, suffix)
	end
end

--------------------------------------------------------------------------------
-- 2. CLEANUP DUPLICATE OLD STAT DISPLAYS
--------------------------------------------------------------------------------
local function cleanupDuplicateStatDisplays()
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and child.Name ~= SCREEN_GUI_NAME then
			local nameL = child.Name:lower()
			if nameL == "oldstatshud" or nameL == "stathud" or nameL == "statscounters" then
				child:Destroy()
			end
		end
	end
end

--------------------------------------------------------------------------------
-- 3. BUILD THE THREE STAT COUNTERS (SLEEK COMPACT SIMULATOR STYLE)
--------------------------------------------------------------------------------
local function buildStatsHUD(): (ScreenGui, TextLabel, TextLabel, TextLabel)
	-- Remove old instance to prevent duplicates
	local existing = playerGui:FindFirstChild(SCREEN_GUI_NAME)
	if existing then
		existing:Destroy()
	end
	cleanupDuplicateStatDisplays()

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = SCREEN_GUI_NAME
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 15
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = playerGui

	-- Pinned neatly to bottom-left corner, sized a bit smaller for a sleek look
	local container = Instance.new("Frame")
	container.Name = CONTAINER_NAME
	container.AnchorPoint = Vector2.new(0, 1)
	container.Position = UDim2.new(0, 20, 1, -20)
	container.Size = UDim2.fromOffset(195, 96) -- Clean compact sizing (~25% smaller)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ClipsDescendants = false
	container.Parent = screenGui

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	listLayout.Parent = container

	-- Helper to create each stat row matching the reference screenshot
	local function createStatRow(order: number, iconEmoji: string, defaultText: string, textColor: Color3): TextLabel
		local row = Instance.new("Frame")
		row.Name = "Row_" .. tostring(order)
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, 26) -- Compact row height
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.ClipsDescendants = false
		row.Parent = container

		-- Icon (Left)
		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "Icon"
		iconLabel.AnchorPoint = Vector2.new(0, 0.5)
		iconLabel.Position = UDim2.new(0, 0, 0.5, 0)
		iconLabel.Size = UDim2.fromOffset(26, 26)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Font = Enum.Font.FredokaOne
		iconLabel.TextSize = 20
		iconLabel.Text = iconEmoji
		iconLabel.Parent = row

		local iconStroke = Instance.new("UIStroke")
		iconStroke.Color = Color3.fromRGB(0, 0, 0)
		iconStroke.Thickness = 2.0
		iconStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		iconStroke.Parent = iconLabel

		-- Stat Value (Right of Icon)
		local valueLabel = Instance.new("TextLabel")
		valueLabel.Name = "Value"
		valueLabel.AnchorPoint = Vector2.new(0, 0.5)
		valueLabel.Position = UDim2.new(0, 32, 0.5, 0)
		valueLabel.Size = UDim2.new(1, -32, 1, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Font = Enum.Font.FredokaOne
		pcall(function()
			valueLabel.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic)
		end)
		valueLabel.TextSize = 22 -- Sleek readable size
		valueLabel.TextColor3 = textColor
		valueLabel.TextXAlignment = Enum.TextXAlignment.Left
		valueLabel.TextYAlignment = Enum.TextYAlignment.Center
		valueLabel.Text = defaultText
		valueLabel.ClipsDescendants = false
		valueLabel.Parent = row

		-- Thick black outline matching the screenshot
		local textStroke = Instance.new("UIStroke")
		textStroke.Color = Color3.fromRGB(0, 0, 0)
		textStroke.Thickness = 2.8
		textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		textStroke.Parent = valueLabel

		return valueLabel
	end

	-- 1. Speed (Running shoe icon, bright cyan: 108.9B style)
	local speedLabel = createStatRow(1, "👟", "16", Color3.fromRGB(48, 229, 255))

	-- 2. Money (Cash stack icon, bright lime green: $27.7Qa style)
	local moneyLabel = createStatRow(2, "💵", "$0", Color3.fromRGB(40, 240, 60))

	-- 3. Strength (Dumbbell icon, bright energetic red)
	local strengthLabel = createStatRow(3, "🏋️", "0", Color3.fromRGB(255, 65, 65))

	return screenGui, speedLabel, moneyLabel, strengthLabel
end

--------------------------------------------------------------------------------
-- 4. REAL-TIME STAT BINDINGS & LIVE UPDATES
--------------------------------------------------------------------------------
local screenGui, speedValLabel, moneyValLabel, strengthValLabel = buildStatsHUD()

-- Speed listener: displays player's true base speed stat, ignoring carrying slowdown!
local function updateSpeed()
	local speedNum = player:GetAttribute("BaseSpeed")
	if typeof(speedNum) ~= "number" or speedNum <= 0 then
		speedNum = 16
	end
	if speedValLabel and speedValLabel.Parent then
		speedValLabel.Text = formatCompactStat(speedNum)
	end
end

player:GetAttributeChangedSignal("BaseSpeed"):Connect(updateSpeed)
updateSpeed()

-- Money & Strength leaderstats listener
local function hookLeaderstats()
	local stats = player:WaitForChild("leaderstats", 10) :: Folder?
	if not stats then return end

	local strVal = stats:WaitForChild("Strength", 5) :: IntValue?
	if strVal and strengthValLabel and strengthValLabel.Parent then
		strengthValLabel.Text = formatCompactStat(strVal.Value)
		strVal:GetPropertyChangedSignal("Value"):Connect(function()
			strengthValLabel.Text = formatCompactStat(strVal.Value)
		end)
	end

	local monVal = stats:WaitForChild("Money", 5) :: IntValue?
	if monVal and moneyValLabel and moneyValLabel.Parent then
		moneyValLabel.Text = "$" .. formatCompactStat(monVal.Value)
		monVal:GetPropertyChangedSignal("Value"):Connect(function()
			moneyValLabel.Text = "$" .. formatCompactStat(monVal.Value)
		end)
	end
end

task.spawn(hookLeaderstats)

--------------------------------------------------------------------------------
-- 5. TRAINING AREA & DUMBBELL VISIBILITY
-- Other players' training pads, borders, text, and dumbbells MUST be invisible.
-- They should ONLY appear to other players if the owner is actively using it!
-- The owner sees their own pad/dumbbell. Ordinary pen signs are NOT hidden.
--------------------------------------------------------------------------------
local function getAllPens(): { Model }
	local pens: { Model } = {}
	local spawnFolder = Workspace:FindFirstChild("Spawn")
	local pensFolder = spawnFolder and spawnFolder:FindFirstChild("Pens")
	if pensFolder then
		for _, c in ipairs(pensFolder:GetChildren()) do
			if c:IsA("Model") and not table.find(pens, c) then
				table.insert(pens, c)
			end
		end
	end
	for _, c in ipairs(Workspace:GetChildren()) do
		if c:IsA("Model") and c.Name:lower():match("pen%s*%d") and not c.Name:lower():match("pen%s*l") then
			if not table.find(pens, c) then
				table.insert(pens, c)
			end
		end
	end
	return pens
end

local penTrainingCache: { [Model]: { folder: Instance?, items: { Instance } } } = {}

local function applyItemVisibility(desc: Instance, shouldBeVisible: boolean, isOwner: boolean)
	if desc:IsA("BasePart") then
		desc.Transparency = shouldBeVisible and 0 or 1
		local isPad = desc.Name == "TrainingPad"
		desc.CanCollide = isPad and shouldBeVisible and isOwner
	elseif desc:IsA("Decal") or desc:IsA("Texture") then
		desc.Transparency = shouldBeVisible and 0 or 1
	elseif desc:IsA("SelectionBox") then
		desc.Transparency = shouldBeVisible and 0 or 1
		desc.Adornee = shouldBeVisible and desc.Parent or nil
	elseif desc:IsA("Highlight") then
		desc.Enabled = shouldBeVisible
	elseif desc:IsA("SurfaceGui") or desc:IsA("BillboardGui") then
		desc.Enabled = shouldBeVisible
	elseif desc:IsA("ProximityPrompt") then
		desc.Enabled = shouldBeVisible and isOwner
	elseif desc:IsA("ClickDetector") then
		desc.MaxActivationDistance = (shouldBeVisible and isOwner) and 14 or 0
	elseif desc:IsA("Beam") or desc:IsA("ParticleEmitter") or desc:IsA("Trail") then
		desc.Enabled = shouldBeVisible
	end
end

local function updatePenTrainingVisibility(pen: Model)
	local cache = penTrainingCache[pen]
	if not cache then return end

	local myUserId = player.UserId
	local ownerId = pen:GetAttribute("OwnerUserId") or 0
	local ownerName = pen:GetAttribute("OwnerName") or ""
	local isOwner = (myUserId ~= 0 and ownerId ~= 0 and ownerId == myUserId) or (ownerName ~= "" and ownerName == player.Name)
	local isBeingUsed = (pen:GetAttribute("IsTraining") == true)
	local shouldBeVisible = isOwner or isBeingUsed

	for _, item in ipairs(cache.items) do
		if item and item.Parent then
			applyItemVisibility(item, shouldBeVisible, isOwner)
		end
	end
end

local function rebuildPenTrainingCache(pen: Model)
	local trainingArea = pen:FindFirstChild("StrengthTrainingArea")
	local items: { Instance } = {}

	if trainingArea then
		table.insert(items, trainingArea)
		for _, desc in ipairs(trainingArea:GetDescendants()) do
			table.insert(items, desc)
		end
	end

	-- Only check explicit training items if somehow outside folder (ordinary pen signs are never touched)
	for _, child in ipairs(pen:GetChildren()) do
		if child.Name == "TrainingPad" or child.Name == "TrainingDumbbell" or child.Name == "TrainingUpgradeSign" then
			if not table.find(items, child) then
				table.insert(items, child)
				for _, d in ipairs(child:GetDescendants()) do
					table.insert(items, d)
				end
			end
		end
	end

	penTrainingCache[pen] = {
		folder = trainingArea,
		items = items,
	}

	updatePenTrainingVisibility(pen)
end

local function hookPen(pen: Model)
	rebuildPenTrainingCache(pen)

	pen:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		updatePenTrainingVisibility(pen)
	end)
	pen:GetAttributeChangedSignal("OwnerName"):Connect(function()
		updatePenTrainingVisibility(pen)
	end)
	pen:GetAttributeChangedSignal("IsTraining"):Connect(function()
		updatePenTrainingVisibility(pen)
	end)
	pen:GetAttributeChangedSignal("DumbbellTier"):Connect(function()
		task.defer(function()
			rebuildPenTrainingCache(pen)
		end)
	end)

	local function hookTrainingArea(ta: Instance)
		ta.DescendantAdded:Connect(function()
			task.defer(function()
				rebuildPenTrainingCache(pen)
			end)
		end)
		ta.DescendantRemoving:Connect(function()
			task.defer(function()
				rebuildPenTrainingCache(pen)
			end)
		end)
	end

	local currentArea = pen:FindFirstChild("StrengthTrainingArea")
	if currentArea then
		hookTrainingArea(currentArea)
	end

	pen.ChildAdded:Connect(function(child)
		if child.Name == "StrengthTrainingArea" or child.Name == "TrainingPad"
			or child.Name == "TrainingDumbbell" or child.Name == "TrainingUpgradeSign" then
			if child.Name == "StrengthTrainingArea" then
				hookTrainingArea(child)
			end
			task.defer(function()
				rebuildPenTrainingCache(pen)
			end)
		end
	end)
end

local function hideLooseDumbbell(model: Instance)
	if model:IsA("Model") then
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Transparency = 1
				desc.CanCollide = false
			end
		end
	end
end

local function hideWorkspacePrototypes()
	for _, name in ipairs({"dumbel1", "dumbel2", "dumbel3", "Dumbel1", "Dumbel2", "Dumbel3"}) do
		local proto = Workspace:FindFirstChild(name)
		if proto then
			hideLooseDumbbell(proto)
		end
	end
end

task.spawn(function()
	task.wait(0.2)
	hideWorkspacePrototypes()

	Workspace.ChildAdded:Connect(function(child)
		local nameL = child.Name:lower()
		if nameL == "dumbel1" or nameL == "dumbel2" or nameL == "dumbel3" then
			hideLooseDumbbell(child)
		elseif child:IsA("Model") and nameL:match("pen%s*%d") then
			hookPen(child)
		end
	end)

	for _, pen in ipairs(getAllPens()) do
		hookPen(pen)
	end

	task.spawn(function()
		local spawnFolder = Workspace:WaitForChild("Spawn", 8)
		local pensFolder = spawnFolder and spawnFolder:WaitForChild("Pens", 8)
		if pensFolder then
			for _, child in ipairs(pensFolder:GetChildren()) do
				if child:IsA("Model") then
					hookPen(child)
				end
			end
			pensFolder.ChildAdded:Connect(function(child)
				if child:IsA("Model") then
					hookPen(child)
				end
			end)
		end
	end)
end)

--------------------------------------------------------------------------------
-- 6. JUMP TO LEAVE AUTO-TRAINING (INPUT LISTENER)
--------------------------------------------------------------------------------
local trainingRemote: RemoteEvent? = nil
local function getTrainingRemote(): RemoteEvent?
	if trainingRemote and trainingRemote.Parent then
		return trainingRemote
	end
	trainingRemote = ReplicatedStorage:FindFirstChild("TrainingAction") :: RemoteEvent?
	return trainingRemote
end

UserInputService.JumpRequest:Connect(function()
	if player:GetAttribute("IsTraining") == true then
		local remote = getTrainingRemote()
		if remote then
			remote:FireServer("Jump")
		end
	end
end)

--------------------------------------------------------------------------------
-- 7. DROP CARRIED EGG BUTTON & KEYBIND (Q)
--------------------------------------------------------------------------------
local dropButton = Instance.new("TextButton")
dropButton.Name = "DropEggButton"
dropButton.AnchorPoint = Vector2.new(0.5, 1)
dropButton.Position = UDim2.new(0.5, 0, 1, -25)
dropButton.Size = UDim2.fromOffset(180, 52)
dropButton.BackgroundColor3 = Color3.fromRGB(235, 50, 50)
dropButton.Font = Enum.Font.FredokaOne
dropButton.TextSize = 18
dropButton.TextColor3 = Color3.fromRGB(255, 255, 255)
dropButton.Text = "🗑️ DROP EGG\n[Press Q]"
dropButton.AutoButtonColor = true
dropButton.Visible = false
dropButton.Parent = screenGui

local dropCorner = Instance.new("UICorner")
dropCorner.CornerRadius = UDim.new(0, 10)
dropCorner.Parent = dropButton

local dropStroke = Instance.new("UIStroke")
dropStroke.Color = Color3.fromRGB(0, 0, 0)
dropStroke.Thickness = 2.8
dropStroke.Parent = dropButton

local function updateDropButtonVisibility()
	local carrying = (player:GetAttribute("CarryingEgg") == true)
	dropButton.Visible = carrying
end

player:GetAttributeChangedSignal("CarryingEgg"):Connect(updateDropButtonVisibility)
updateDropButtonVisibility()

local function triggerDropEgg()
	if player:GetAttribute("CarryingEgg") == true then
		local remote = ReplicatedStorage:FindFirstChild("DropEggAction") :: RemoteEvent?
		if remote then
			remote:FireServer()
		end
	end
end

dropButton.MouseButton1Click:Connect(triggerDropEgg)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Q then
		triggerDropEgg()
	end
end)

--------------------------------------------------------------------------------
-- 8. TAP / CLICK ANYWHERE IN PEN TO PLACE EGG TOOL
--------------------------------------------------------------------------------
local placeEggRemote = ReplicatedStorage:FindFirstChild("PlaceEggAtLocation") :: RemoteEvent?
if not placeEggRemote then
	placeEggRemote = Instance.new("RemoteEvent")
	placeEggRemote.Name = "PlaceEggAtLocation"
	placeEggRemote.Parent = ReplicatedStorage
end

local function handleTapToPlace(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local char = player.Character
		local tool = char and char:FindFirstChildWhichIsA("Tool")
		if tool and tool:GetAttribute("IsAnimeEgg") == true then
			local mouse = player:GetMouse()
			if mouse and mouse.Hit then
				local remote = ReplicatedStorage:FindFirstChild("PlaceEggAtLocation") :: RemoteEvent?
				if remote then
					remote:FireServer(mouse.Hit.Position)
				end
			end
		end
	end
end

UserInputService.InputBegan:Connect(handleTapToPlace)

--------------------------------------------------------------------------------
-- 9. DUMBBELL UPGRADE SIGN BUTTON (CLICK BUTTON DIRECTLY ON SIGN)
--------------------------------------------------------------------------------
local upgradeDumbbellRemote = ReplicatedStorage:FindFirstChild("UpgradeDumbbellAction") :: RemoteEvent?
if not upgradeDumbbellRemote then
	upgradeDumbbellRemote = Instance.new("RemoteEvent")
	upgradeDumbbellRemote.Name = "UpgradeDumbbellAction"
	upgradeDumbbellRemote.Parent = ReplicatedStorage
end

local function hookUpgradeButton(desc: Instance)
	if desc:IsA("TextButton") and desc.Name == "UpgradeButton" then
		desc.Activated:Connect(function()
			upgradeDumbbellRemote:FireServer()
		end)
	end
end

for _, pen in ipairs(getAllPens()) do
	for _, desc in ipairs(pen:GetDescendants()) do
		hookUpgradeButton(desc)
	end
end
Workspace.DescendantAdded:Connect(hookUpgradeButton)

print("[StatsHUD] Compact HUD, Dumbbell visibility isolation, Drop Button, Tap-to-place & Jump-to-leave active.")


]===]
print("[+] Configured StarterPlayerScripts.StatsHUDController (Bottom-Left Speed, Strength, Money HUD)")

-- 5. Clean up old ShopInteractionController if deprecated
local oldShopCtrl = StarterPlayerScripts:FindFirstChild("ShopInteractionController")
if oldShopCtrl and oldShopCtrl:IsA("LocalScript") then
	oldShopCtrl:Destroy()
	print("[-] Cleaned up deprecated ShopInteractionController")
end

-- 6. Clean up obsolete RoCodeTrash in ServerStorage
local trash = ServerStorage:FindFirstChild("RoCodeTrash")
if trash then
	trash:Destroy()
	print("[-] Removed obsolete ServerStorage.RoCodeTrash")
end

print("----------------------------------------------------------------------")
print("[Steal An Anime Egg] SUCCESS! Complete gameplay loop installed in Explorer.")
print("  - Pens 1..7: Automated assignment, egg platforms & 30-capacity grid.")
print("  - Dumbbells: Dumbel1, Dumbel2, Dumbel3 training interactions active.")
print("  - Eggs: Zone1 spawning & Night-transition reset.")
print("  - Hatching & Lee: Rock Lee hatched, non-colliding, wandering & 1,000 Money/sec.")
print("  - UI: Bottom-left live Speed, Strength, and Money counters active.")
print("----------------------------------------------------------------------")
