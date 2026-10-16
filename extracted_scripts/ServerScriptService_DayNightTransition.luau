-- Path: ServerScriptService.DayNightTransition
-- Class: Script

--!strict
-- ServerScriptService > DayNightTransition
-- Handles smooth visual environment transitions between Day and Night for Steal an Anime Egg
-- Visual style: Accurately replicates "Steal an Egg" daytime and nighttime appearances.
-- Daytime: Sunny, vibrant anime simulator palette with bright blue horizon and clear visibility.
-- Nighttime: Atmospheric starry anime night sky.
-- Crucial rule: ONLY the sky changes! The map, terrain, buildings, shops, eggs, and barriers NEVER darken.
-- Ambient, outdoor ambient, and brightness remain 100% full daylight brightness.
-- Atmosphere haze is set to 0 during night to prevent any hollow horizon gap.
-- Integrated with 290s Day / 10s Night global cycle (300s / 5-min total cycle aligned to IST).

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local TRANSITION_SECONDS = 1.5

-- Global Clock Configuration (290s Day, 10s Night = 300s Cycle aligned to IST)
local REFERENCE_EPOCH_UTC = 1704090600 -- Jan 1, 2024 at 12:00:00 PM IST
local DAY_DURATION = 290               -- 290 seconds (4 minutes 50 seconds)
local NIGHT_DURATION = 10              -- 10 seconds total
local CYCLE_DURATION = DAY_DURATION + NIGHT_DURATION -- 300 seconds (5 minutes)

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")

local currentTween: Tween? = nil
local currentAtmosphereTween: Tween? = nil
local currentPhase: string? = nil

--------------------------------------------------------------------------------
-- LIGHTING & ATMOSPHERE PALETTES
--------------------------------------------------------------------------------
-- Rule: Ground illumination stays full daylight bright so the world never darkens!
local BASE_LIGHTING = {
	ClockTime = 14.25,
	Brightness = 2.2,
	Ambient = Color3.fromRGB(135, 135, 140),
	OutdoorAmbient = Color3.fromRGB(140, 145, 155),
	ColorShift_Top = Color3.fromRGB(255, 250, 242),
	ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	ExposureCompensation = 0.05,
}

local DAY_ATMOSPHERE = {
	Density = 0.28,
	Offset = 0.25,
	Color = Color3.fromRGB(195, 215, 235),
	Decay = Color3.fromRGB(105, 120, 140),
	Glare = 0.1,
	Haze = 0.45,
}

local NIGHT_ATMOSPHERE = {
	Density = 0.20,
	Offset = 0.25,
	Color = Color3.fromRGB(20, 20, 45),
	Decay = Color3.fromRGB(15, 15, 30),
	Glare = 0.0,
	Haze = 0.0, -- Zero haze eliminates any hollow horizon ring or washed-out bowl gap
}

-- Public verified skybox textures
local DAY_SKY_TEXTURES = {
	SkyboxBk = "rbxassetid://6444884337",
	SkyboxDn = "rbxassetid://6444884785",
	SkyboxFt = "rbxassetid://6444884337",
	SkyboxLf = "rbxassetid://6444884337",
	SkyboxRt = "rbxassetid://6444884337",
	SkyboxUp = "rbxassetid://6412503613",
}

local NIGHT_SKY_TEXTURES = {
	SkyboxBk = "rbxassetid://15536110634",
	SkyboxDn = "rbxassetid://15536112543",
	SkyboxFt = "rbxassetid://15536116141",
	SkyboxLf = "rbxassetid://15536114370",
	SkyboxRt = "rbxassetid://15536118762",
	SkyboxUp = "rbxassetid://15536117282",
}

local function applySkyTextures(isNight: boolean)
	local tex = isNight and NIGHT_SKY_TEXTURES or DAY_SKY_TEXTURES
	for _, child in Lighting:GetChildren() do
		if child:IsA("Sky") then
			child.CelestialBodiesShown = true
			child.SunAngularSize = isNight and 0 or 11 -- Hide sun disk during starry night
			child.SkyboxBk = tex.SkyboxBk
			child.SkyboxDn = tex.SkyboxDn
			child.SkyboxFt = tex.SkyboxFt
			child.SkyboxLf = tex.SkyboxLf
			child.SkyboxRt = tex.SkyboxRt
			child.SkyboxUp = tex.SkyboxUp
		end
	end
end

local function applyPhase(phase: string, animate: boolean)
	if phase == currentPhase then
		return
	end
	currentPhase = phase

	if currentTween then
		currentTween:Cancel()
		currentTween = nil
	end
	if currentAtmosphereTween then
		currentAtmosphereTween:Cancel()
		currentAtmosphereTween = nil
	end

	local isNight = (phase == "NIGHT" or phase == "COUNTDOWN")
	local targetAtmosphere = isNight and NIGHT_ATMOSPHERE or DAY_ATMOSPHERE

	-- Ground lighting always remains at BASE_LIGHTING (never darkens)
	Lighting.Brightness = BASE_LIGHTING.Brightness
	Lighting.Ambient = BASE_LIGHTING.Ambient
	Lighting.OutdoorAmbient = BASE_LIGHTING.OutdoorAmbient
	Lighting.ColorShift_Top = BASE_LIGHTING.ColorShift_Top
	Lighting.ColorShift_Bottom = BASE_LIGHTING.ColorShift_Bottom
	Lighting.ExposureCompensation = BASE_LIGHTING.ExposureCompensation
	Lighting.ClockTime = BASE_LIGHTING.ClockTime

	if animate then
		local tweenInfo = TweenInfo.new(
			TRANSITION_SECONDS,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		)

		if atmosphere then
			currentAtmosphereTween = TweenService:Create(atmosphere, tweenInfo, targetAtmosphere)
			currentAtmosphereTween:Play()
		end

		if sunRays then
			TweenService:Create(sunRays, tweenInfo, { Intensity = isNight and 0.0 or 0.05 }):Play()
		end
		if bloom then
			TweenService:Create(bloom, tweenInfo, { Intensity = 0.35, Threshold = 1.6 }):Play()
		end
		if colorCorrection then
			TweenService:Create(colorCorrection, tweenInfo, {
				Brightness = 0.02,
				Contrast = 0.06,
				Saturation = 0.18,
				TintColor = Color3.fromRGB(255, 255, 255)
			}):Play()
		end

		applySkyTextures(isNight)
	else
		-- Instant setup for server boot or mid-cycle catch-up
		if atmosphere then
			atmosphere.Density = targetAtmosphere.Density
			atmosphere.Offset = targetAtmosphere.Offset
			atmosphere.Color = targetAtmosphere.Color
			atmosphere.Decay = targetAtmosphere.Decay
			atmosphere.Haze = targetAtmosphere.Haze
			atmosphere.Glare = targetAtmosphere.Glare
		end

		if sunRays then
			sunRays.Intensity = isNight and 0.0 or 0.05
		end
		if bloom then
			bloom.Intensity = 0.35
			bloom.Threshold = 1.6
		end
		if colorCorrection then
			colorCorrection.Brightness = 0.02
			colorCorrection.Contrast = 0.06
			colorCorrection.Saturation = 0.18
			colorCorrection.TintColor = Color3.fromRGB(255, 255, 255)
		end

		applySkyTextures(isNight)
	end
end

local function getUniversalUtcTime(): number
	local success, serverTime = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if success and typeof(serverTime) == "number" and serverTime > 1700000000 then
		return serverTime
	end
	return DateTime.now().UnixTimestampMillis / 1000
end

local function getExpectedPhase(): string
	local now = getUniversalUtcTime()
	local elapsed = (now - REFERENCE_EPOCH_UTC) % CYCLE_DURATION
	if elapsed < 0 then
		elapsed += CYCLE_DURATION
	end
	if elapsed < DAY_DURATION then
		return "DAY"
	else
		return "NIGHT"
	end
end

-- Initialize immediately to match the true global UTC phase
local initialPhase = getExpectedPhase()
applyPhase(initialPhase, false)

-- Synchronize with global phase attribute changes
Lighting:GetAttributeChangedSignal("Phase"):Connect(function()
	local phase = Lighting:GetAttribute("Phase")
	if phase == "DAY" or phase == "NIGHT" then
		applyPhase(phase, true)
	end
end)

-- Polling watchdog: guarantees transitions are never missed
task.spawn(function()
	while true do
		task.wait(0.2)
		local p = Lighting:GetAttribute("Phase") or getExpectedPhase()
		if p ~= currentPhase and (p == "DAY" or p == "NIGHT") then
			applyPhase(p, true)
		end
	end
end)

print(string.format("[DayNightTransition] Sky-only transition active: %s (Cycle: %ds Day, %ds Night, Total %ds)",
	initialPhase, DAY_DURATION, NIGHT_DURATION, CYCLE_DURATION))
