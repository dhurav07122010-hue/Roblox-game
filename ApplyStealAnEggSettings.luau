--!strict
-- ==============================================================================
-- Steal An Egg: Sky, Lighting, Atmosphere, and Music Studio Setup Script
-- Run this in the Roblox Studio Command Bar (View -> Command Bar) to permanently
-- configure edit-mode properties in your place Explorer hierarchy!
-- ==============================================================================

local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local Terrain = Workspace.Terrain

print("----------------------------------------------------------------------")
print("[Steal An Egg Setup] Applying Sky, Lighting, Atmosphere, and Music...")
print("----------------------------------------------------------------------")

--------------------------------------------------------------------------------
-- 1. CLEANUP CONFLICTING & STRAY OBJECTS
--------------------------------------------------------------------------------
-- Remove legacy/conflicting skybox so the vibrant anime skybox is active
local realisticSky = Lighting:FindFirstChild("Realistic Sky")
if realisticSky then
	realisticSky:Destroy()
	print("[-] Removed conflicting 'Realistic Sky'")
end

-- Clean stray post-processing effects sitting in Workspace
for _, strayName in ipairs({"Bloom", "Blur", "SunRays"}) do
	local stray = Workspace:FindFirstChild(strayName)
	if stray and (stray:IsA("PostEffect") or stray:IsA("BlurEffect") or stray:IsA("BloomEffect") or stray:IsA("SunRaysEffect")) then
		stray:Destroy()
		print("[-] Removed stray workspace effect: " .. strayName)
	end
end

--------------------------------------------------------------------------------
-- 2. LIGHTING CONFIGURATION
--------------------------------------------------------------------------------
-- ShadowMap provides crisp, clean real-time shadows with high performance on PC & Mobile
Lighting.Technology = Enum.Technology.ShadowMap
Lighting.Brightness = 2.2
Lighting.Ambient = Color3.fromRGB(135, 135, 140)
Lighting.OutdoorAmbient = Color3.fromRGB(140, 145, 155)
Lighting.ClockTime = 14.25 -- 2:15 PM (clean midday sun)
Lighting.GeographicLatitude = 0
Lighting.ColorShift_Top = Color3.fromRGB(255, 250, 242)
Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
Lighting.EnvironmentDiffuseScale = 1
Lighting.EnvironmentSpecularScale = 1
Lighting.ExposureCompensation = 0.05
Lighting.FogEnd = 100000
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.2

print("[+] Lighting properties configured")

--------------------------------------------------------------------------------
-- 3. SKYBOX CONFIGURATION
--------------------------------------------------------------------------------
local sky = Lighting:FindFirstChildWhichIsA("Sky")
if not sky then
	sky = Instance.new("Sky")
	sky.Name = "Sky"
	sky.Parent = Lighting
end
sky.SkyboxBk = "rbxassetid://6444884337"
sky.SkyboxDn = "rbxassetid://6444884785"
sky.SkyboxFt = "rbxassetid://6444884337"
sky.SkyboxLf = "rbxassetid://6444884337"
sky.SkyboxRt = "rbxassetid://6444884337"
sky.SkyboxUp = "rbxassetid://6412503613"
sky.SunTextureId = "rbxassetid://6196665106"
sky.MoonTextureId = "rbxassetid://6444320592"
sky.SunAngularSize = 11
sky.MoonAngularSize = 11
sky.StarCount = 3000
sky.CelestialBodiesShown = true

print("[+] Skybox confirmed: stylized anime/simulator sky")

--------------------------------------------------------------------------------
-- 4. ATMOSPHERE CONFIGURATION
--------------------------------------------------------------------------------
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

print("[+] Atmosphere configured")

--------------------------------------------------------------------------------
-- 5. POST-PROCESSING EFFECTS
--------------------------------------------------------------------------------
-- Bloom: Gentle shimmer on bright eggs/neon without glare
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

-- SunRays: Subtle golden sunbeams
local sunRays = Lighting:FindFirstChildWhichIsA("SunRaysEffect")
if not sunRays then
	sunRays = Instance.new("SunRaysEffect")
	sunRays.Name = "SunRays"
	sunRays.Parent = Lighting
end
sunRays.Intensity = 0.05
sunRays.Spread = 0.65
sunRays.Enabled = true

-- DepthOfField: Kept disabled for gameplay visual clarity
local dof = Lighting:FindFirstChildWhichIsA("DepthOfFieldEffect")
if dof then
	dof.Enabled = false
end

-- ColorCorrection: Rich vibrancy and saturation matching Steal An Egg's anime palette
local cc = Lighting:FindFirstChildWhichIsA("ColorCorrectionEffect")
if not cc then
	local wsCC = Workspace:FindFirstChild("ColorCorrection")
	if wsCC and wsCC:IsA("ColorCorrectionEffect") then
		wsCC.Parent = Lighting
		cc = wsCC
	else
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "ColorCorrection"
		cc.Parent = Lighting
	end
end
cc.Brightness = 0.02
cc.Contrast = 0.06
cc.Saturation = 0.18
cc.TintColor = Color3.fromRGB(255, 255, 255)
cc.Enabled = true

print("[+] Post-processing effects configured (Bloom, SunRays, ColorCorrection)")

--------------------------------------------------------------------------------
-- 6. VOLUMETRIC CLOUDS (Terrain)
--------------------------------------------------------------------------------
local clouds = Terrain:FindFirstChildWhichIsA("Clouds")
if not clouds then
	clouds = Instance.new("Clouds")
	clouds.Name = "Clouds"
	clouds.Parent = Terrain
end
clouds.Cover = 0.55
clouds.Density = 0.45
clouds.Color = Color3.fromRGB(255, 255, 255)
clouds.Enabled = true

print("[+] Volumetric Clouds configured in Terrain")

--------------------------------------------------------------------------------
-- 7. BACKGROUND MUSIC (SoundService & StarterPlayerScripts)
--------------------------------------------------------------------------------
local MUSIC_ID = "rbxassetid://1843404009" -- Roblox Official APM: "Happy Song" (Playful Simulator Theme)
local MUSIC_VOL = 0.35

local bgm = SoundService:FindFirstChild("BackgroundMusic") :: Sound?
if not bgm then
	bgm = Instance.new("Sound")
	bgm.Name = "BackgroundMusic"
	bgm.Parent = SoundService
end
bgm.SoundId = MUSIC_ID
bgm.Volume = MUSIC_VOL
bgm.Looped = true
bgm.RollOffMode = Enum.RollOffMode.InverseTapered
bgm.SoundGroup = nil

-- Create or update client MusicController in StarterPlayerScripts
local clientMusicScript = StarterPlayerScripts:FindFirstChild("MusicController") :: LocalScript?
if not clientMusicScript then
	clientMusicScript = Instance.new("LocalScript")
	clientMusicScript.Name = "MusicController"
	clientMusicScript.Parent = StarterPlayerScripts
end
clientMusicScript.Source = [=[--!strict
-- Client Music Controller
-- Ensures smooth, looping background music playback without restarting when respawning

local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local bgm = SoundService:WaitForChild("BackgroundMusic", 10) :: Sound?
if bgm then
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({bgm})
		end)
		if not bgm.IsPlaying then
			bgm:Play()
		end
		bgm.Ended:Connect(function()
			if not bgm.IsPlaying then
				bgm:Play()
			end
		end)
	end)
end
]=]

print("[+] Background music setup in SoundService and StarterPlayerScripts")
print("----------------------------------------------------------------------")
print("[Steal An Egg Setup] SUCCESS! All settings applied to place hierarchy.")
print("----------------------------------------------------------------------")
