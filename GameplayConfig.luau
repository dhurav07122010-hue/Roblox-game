--!strict
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
