-- Path: ServerScriptService.PlayerSpeed
-- Class: Script

--!strict
-- ServerScriptService > PlayerSpeed
-- Environment, Atmosphere, and Sound Controller for Steal an Anime Egg
-- Note: Player WalkSpeed is authoritatively managed by ServerScriptService.PlayerData to support purchased Speed Tiers
-- Protection rule: Does NOT create, delete, move, or modify any Workspace objects, models, parts, or Terrain children.

local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

--------------------------------------------------------------------------------
-- 1. STEAL AN EGG LIGHTING & ATMOSPHERE SETUP (LIGHTING SERVICE ONLY)
--------------------------------------------------------------------------------
local function setupEnvironment()
	-- Clean up legacy/conflicting sky if present within Lighting service
	local realisticSky = Lighting:FindFirstChild("Realistic Sky")
	if realisticSky and realisticSky:IsA("Sky") then
		realisticSky:Destroy()
	end

	-- Base Lighting properties (Steal An Egg daytime sunny simulator palette)
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(135, 135, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 145, 155)
	Lighting.ClockTime = 14.25
	Lighting.GeographicLatitude = 0
	Lighting.ColorShift_Top = Color3.fromRGB(255, 250, 242)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.ExposureCompensation = 0.05
	Lighting.FogEnd = 100000
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2

	-- Atmosphere (within Lighting service only)
	local atmosphere = Lighting:FindFirstChildWhichIsA("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "Atmosphere"
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(195, 215, 235)
	atmosphere.Decay = Color3.fromRGB(105, 120, 140)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 0.45

	-- Bloom (within Lighting service only)
	local bloom = Lighting:FindFirstChildWhichIsA("BloomEffect")
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "Bloom"
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0.35
	bloom.Size = 24
	bloom.Threshold = 1.6
	bloom.Enabled = true

	-- SunRays (within Lighting service only)
	local sunRays = Lighting:FindFirstChildWhichIsA("SunRaysEffect")
	if not sunRays then
		sunRays = Instance.new("SunRaysEffect")
		sunRays.Name = "SunRays"
		sunRays.Parent = Lighting
	end
	sunRays.Intensity = 0.05
	sunRays.Spread = 0.65
	sunRays.Enabled = true

	-- DepthOfField (kept disabled for simulator visual clarity)
	local dof = Lighting:FindFirstChildWhichIsA("DepthOfFieldEffect")
	if dof then
		dof.Enabled = false
	end

	-- ColorCorrection (within Lighting service only - boost vibrancy and saturation for anime palette)
	local cc = Lighting:FindFirstChildWhichIsA("ColorCorrectionEffect")
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "ColorCorrection"
		cc.Parent = Lighting
	end
	cc.Brightness = 0.02
	cc.Contrast = 0.06
	cc.Saturation = 0.18
	cc.TintColor = Color3.fromRGB(255, 255, 255)
	cc.Enabled = true

	print("[EnvironmentManager] Steal An Egg sky, lighting, and atmosphere configured strictly in Lighting service.")
end

--------------------------------------------------
-- 2. BACKGROUND MUSIC SYSTEM (SOUNDSERVICE ONLY)
--------------------------------------------------
local MUSIC_ASSET_ID = "rbxassetid://1843404009" -- Roblox Official APM "Happy Song" (Cheerful Simulator Theme)
local MUSIC_VOLUME = 0.35

local function setupBackgroundMusic()
	local bgm = SoundService:FindFirstChild("BackgroundMusic") :: Sound?
	if bgm then
		if not bgm.IsPlaying and bgm.SoundId ~= "" then
			pcall(function() bgm:Play() end)
		end
		bgm.Ended:Connect(function()
			if not bgm.IsPlaying and bgm.SoundId ~= "" then
				pcall(function() bgm:Play() end)
			end
		end)
		return
	end

	bgm = Instance.new("Sound")
	bgm.Name = "BackgroundMusic"
	bgm.Parent = SoundService
	bgm.SoundId = MUSIC_ASSET_ID
	bgm.Volume = MUSIC_VOLUME
	bgm.Looped = true
	bgm.RollOffMode = Enum.RollOffMode.InverseTapered

	if not bgm.IsPlaying then
		pcall(function() bgm:Play() end)
	end

	bgm.Ended:Connect(function()
		if not bgm.IsPlaying then
			pcall(function() bgm:Play() end)
		end
	end)
end

-- Initialize environment and audio strictly within Lighting and SoundService
setupEnvironment()
setupBackgroundMusic()
