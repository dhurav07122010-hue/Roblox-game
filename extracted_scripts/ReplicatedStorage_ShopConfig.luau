-- Path: ReplicatedStorage.ShopConfig
-- Class: ModuleScript

--!strict
-- ReplicatedStorage > ShopConfig
-- Shared configuration for Speed Tiers and Trail stats (Clean-slate version)
-- Obsolete coin prices and old card UI mappings have been removed.

local Config = {
	-- SpeedTiers[i] defines Tier i WalkSpeed
	SpeedTiers = {
		{ WalkSpeed = 50  }, -- Tier I:   Starter Pace
		{ WalkSpeed = 75  }, -- Tier II:  Swift Runner
		{ WalkSpeed = 100 }, -- Tier III: Supersonic
		{ WalkSpeed = 150 }, -- Tier IV:  Lightning Sprint
		{ WalkSpeed = 225 }, -- Tier V:   Anime Flash
		{ WalkSpeed = 350 }, -- Tier VI:  Divine Godspeed
	},
	MAX_SPEED_TIER = 6,

	-- Trails: identifier, display name, and strength training multiplier
	Trails = {
		{ id = "basic_white",   name = "Basic White Trail",   multiplier = 1.0 },
		{ id = "electric_gold", name = "Electric Gold Trail", multiplier = 1.2 },
		{ id = "cyan",          name = "Cyan Lightning",      multiplier = 1.5 },
		{ id = "anime_fire",    name = "Anime Flame Trail",   multiplier = 2.0 },
		{ id = "rainbow",       name = "Rainbow Sparkle",     multiplier = 3.0 },
		{ id = "void",          name = "Void Godspeed Trail", multiplier = 5.0 },
	},
	BASIC_TRAIL_ID = "basic_white",
}

return Config
