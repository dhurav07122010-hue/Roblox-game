--!strict
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

local function loadData(userId: number): (boolean, any)
	local key = tostring(userId)
	if SessionStore then
		local ok, res = pcall(function()
			return SessionStore:GetAsync(key)
		end)
		if ok then
			if type(res) == "table" then
				print(string.format("[PlayerData] Successfully loaded profile for user %s (key: '%s')", tostring(userId), key))
				return true, res
			else
				print(string.format("[PlayerData] No existing profile found for user %s (key: '%s') - initializing new player defaults", tostring(userId), key))
				return true, nil
			end
		else
			warn(string.format("[PlayerData] DataStore GetAsync ERROR for user %s (key: '%s'): %s", tostring(userId), key, tostring(res)))
			local mem = sessionMemory[key]
			if mem then
				warn(string.format("[PlayerData] Recovered user %s data from server session memory fallback", key))
				return false, mem
			end
			return false, nil
		end
	else
		warn(string.format("[PlayerData] DataStore unavailable. Checking session memory fallback for user %s (key: '%s')", tostring(userId), key))
		local mem = sessionMemory[key]
		return false, mem
	end
end

local function saveData(userId: number, saved: any): boolean
	local key = tostring(userId)
	local saveSuccess = false
	if SessionStore then
		local ok, err = pcall(function()
			SessionStore:SetAsync(key, saved)
		end)
		if ok then
			print(string.format("[PlayerData] Successfully saved profile for user %s (key: '%s')", tostring(userId), key))
			saveSuccess = true
		else
			warn(string.format("[PlayerData] DataStore SetAsync ERROR for user %s (key: '%s'): %s", tostring(userId), key, tostring(err)))
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
-- PLAYER LIFECYCLE
--------------------------------------------------

local function onPlayerAdded(player: Player)
	local ok, loaded = loadData(player.UserId)
	if ok and loaded and type(loaded) == "table" then
		data[player] = sanitize(loaded)
	elseif not ok and loaded and type(loaded) == "table" then
		data[player] = sanitize(loaded)
	else
		if not ok then
			warn(string.format("[PlayerData] NOTICE: DataStore load failed for user %s (%d). Applying default session profile.", player.Name, player.UserId))
		end
		data[player] = sanitize(DEFAULT_DATA)
	end

	local strength, money = setupLeaderstats(player)
	strength.Value = data[player].Strength
	money.Value = data[player].Money
	player:SetAttribute("EggCount", #data[player].EggInventory)
	player:SetAttribute("BaseSpeed", 16)

	player.CharacterAdded:Connect(function(character)
		task.defer(function()
			applyWalkSpeed(player)
			applyTrail(player)
		end)
	end)

	if player.Character then
		task.defer(function()
			applyWalkSpeed(player)
			applyTrail(player)
		end)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	onPlayerAdded(p)
end

local function onPlayerRemoving(player: Player)
	local d = data[player]
	if d then
		local arr = {}
		for id in pairs(d.OwnedTrails) do table.insert(arr, id) end
		saveData(player.UserId, {
			Strength = d.Strength,
			Money = d.Money,
			PenUpgradeLevel = d.PenUpgradeLevel,
			SpeedTier = d.SpeedTier,
			Trail = d.Trail,
			OwnedTrails = arr,
		})
	end
	data[player] = nil
end
Players.PlayerRemoving:Connect(onPlayerRemoving)

game:BindToClose(function()
	for p, d in pairs(data) do
		local arr = {}
		for id in pairs(d.OwnedTrails) do table.insert(arr, id) end
		saveData(p.UserId, {
			Strength = d.Strength,
			Money = d.Money,
			PenUpgradeLevel = d.PenUpgradeLevel,
			SpeedTier = d.SpeedTier,
			Trail = d.Trail,
			OwnedTrails = arr,
		})
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
	removeEggFromInventory = function(player: Player, index: number?): any
		local d = data[player]
		if not d or type(d.EggInventory) ~= "table" or #d.EggInventory == 0 then
			return nil
		end
		local idx = index or #d.EggInventory
		local egg = table.remove(d.EggInventory, idx)
		player:SetAttribute("EggCount", #d.EggInventory)
		return egg
	end,
	getEggInventoryCount = function(player: Player): number
		local d = data[player]
		return (d and type(d.EggInventory) == "table") and #d.EggInventory or 0
	end,
}

print("[PlayerData] Initialized with Strength, Money, Speed, and Pen Level systems active.")
