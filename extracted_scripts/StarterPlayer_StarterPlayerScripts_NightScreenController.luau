-- Path: StarterPlayer.StarterPlayerScripts.NightScreenController
-- Class: LocalScript

--!strict
-- StarterPlayer > StarterPlayerScripts > NightScreenController
-- Synchronized screen notifications, 1-second black transition, and smooth client-side Day/Night animation
-- Visual rules:
--   1. The screen goes pitch black for exactly 1 second between the night teleportation
--      so players never see camera snaps or zone boundary pops.
--   2. Night changes only the sky; does NOT darken the map, terrain, eggs, or shops.
--   3. All GUI elements are dynamically verified and recovered on character spawn so they NEVER break.
--   4. "50x Hatch Speed" / "50x HATCH ACTIVE" announcement is completely removed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------
-- REMOTE EVENT RESOLVER (Supports NightZoneEvent & NightStateChanged)
--------------------------------------------------
local function getNightEvent(): RemoteEvent
	local event = ReplicatedStorage:FindFirstChild("NightZoneEvent") :: RemoteEvent?
	if not event then
		event = ReplicatedStorage:FindFirstChild("NightStateChanged") :: RemoteEvent?
	end
	if not event then
		event = ReplicatedStorage:WaitForChild("NightZoneEvent", 10) :: RemoteEvent?
	end
	if not event then
		event = ReplicatedStorage:WaitForChild("NightStateChanged", 5) :: RemoteEvent?
	end
	if not event then
		-- Fallback create
		event = Instance.new("RemoteEvent")
		event.Name = "NightZoneEvent"
		event.Parent = ReplicatedStorage
	end
	return event
end

local nightEvent = getNightEvent()

--------------------------------------------------
-- 1. FULLSCREEN BLACK OVERLAY (1-SECOND TRANSITION)
-- Dynamically ensured on demand so PlayerGui clears on character spawn never break it
--------------------------------------------------
local function getBlackFrame(): Frame
	local overlayGui = playerGui:FindFirstChild("NightBlackOverlay") :: ScreenGui?
	if not overlayGui then
		overlayGui = Instance.new("ScreenGui")
		overlayGui.Name = "NightBlackOverlay"
		overlayGui.IgnoreGuiInset = true
		overlayGui.ResetOnSpawn = false
		overlayGui.DisplayOrder = 999 -- Above all other GUIs
		overlayGui.Parent = playerGui
	end

	local black = overlayGui:FindFirstChild("BlackFrame") :: Frame?
	if not black then
		black = Instance.new("Frame")
		black.Name = "BlackFrame"
		black.Size = UDim2.fromScale(1, 1)
		black.Position = UDim2.fromScale(0, 0)
		black.BackgroundColor3 = Color3.new(0, 0, 0)
		black.BackgroundTransparency = 1
		black.BorderSizePixel = 0
		black.Visible = false
		black.Parent = overlayGui
	end

	return black
end

local function fadeBlack(frame: Frame, targetTransparency: number, duration: number): Tween
	frame.Visible = true
	local tween = TweenService:Create(
		frame,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = targetTransparency }
	)
	tween:Play()
	return tween
end

--------------------------------------------------
-- 2. ANNOUNCEMENT / COUNTDOWN SCREEN GUI
-- Dynamically ensured on demand
--------------------------------------------------
local function getAnnouncementElements(): (Frame, TextLabel, TextLabel)
	local countdownGui = playerGui:FindFirstChild("NightCountdownGui") :: ScreenGui?
	if not countdownGui then
		countdownGui = Instance.new("ScreenGui")
		countdownGui.Name = "NightCountdownGui"
		countdownGui.IgnoreGuiInset = true
		countdownGui.ResetOnSpawn = false
		countdownGui.DisplayOrder = 100
		countdownGui.Parent = playerGui
	end

	local container = countdownGui:FindFirstChild("AnnouncementContainer") :: Frame?
	if not container then
		container = Instance.new("Frame")
		container.Name = "AnnouncementContainer"
		container.AnchorPoint = Vector2.new(0.5, 0)
		container.Position = UDim2.new(0.5, 0, 0.08, 0)
		container.Size = UDim2.fromOffset(360, 95)
		container.BackgroundTransparency = 1
		container.Visible = false
		container.Parent = countdownGui
	end

	local title = container:FindFirstChild("Title") :: TextLabel?
	if not title then
		title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, 0, 0, 36)
		title.BackgroundTransparency = 1
		title.Text = "🌙 NIGHT HAS FALLEN"
		title.TextColor3 = Color3.fromRGB(255, 255, 255)
		title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		title.TextStrokeTransparency = 0
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.Parent = container

		local titleStroke = Instance.new("UIStroke")
		titleStroke.Color = Color3.fromRGB(0, 0, 0)
		titleStroke.Thickness = 2.5
		titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		titleStroke.Parent = title
	end

	local subtitle = container:FindFirstChild("Subtitle") :: TextLabel?
	if not subtitle then
		subtitle = Instance.new("TextLabel")
		subtitle.Name = "Subtitle"
		subtitle.Position = UDim2.fromOffset(0, 40)
		subtitle.Size = UDim2.new(1, 0, 0, 50)
		subtitle.BackgroundTransparency = 1
		subtitle.TextColor3 = Color3.fromRGB(255, 220, 70)
		subtitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		subtitle.TextStrokeTransparency = 0
		subtitle.Font = Enum.Font.GothamBlack
		subtitle.TextScaled = true
		subtitle.Text = "ZONES CLOSED"
		subtitle.Parent = container

		local subStroke = Instance.new("UIStroke")
		subStroke.Color = Color3.fromRGB(0, 0, 0)
		subStroke.Thickness = 2.5
		subStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		subStroke.Parent = subtitle
	end

	return container, title, subtitle
end

--------------------------------------------------
local SoundService = game:GetService("SoundService")

--------------------------------------------------
-- 3. CLIENT-SIDE SMOOTH DAY/NIGHT LIGHTING ANIMATION (60/120 FPS)
-- Ground illumination remains 100% full daylight brightness (never darkens).
-- Atmosphere haze set to 0 during night to prevent hollow horizon gap.
--------------------------------------------------
local currentClientLightingTween: Tween? = nil
local currentClientAtmoTween: Tween? = nil

local function playCountdownSound(step: number)
	local sound = Instance.new("Sound")
	sound.Name = "DayCountdownSound"
	if step == 0 then
		-- Day arrived / GO!
		sound.SoundId = "rbxasset://sounds/bell.wav"
		sound.Volume = 0.7
		sound.PlaybackSpeed = 1.2
	else
		-- 3, 2, 1 ticks
		sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
		sound.Volume = 0.7
		sound.PlaybackSpeed = 1.0 + (3 - step) * 0.2
	end
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	task.delay(2.5, function()
		if sound and sound.Parent then
			sound:Destroy()
		end
	end)
end

local function animateClientLighting(isNight: boolean)
	if currentClientLightingTween then
		currentClientLightingTween:Cancel()
	end
	if currentClientAtmoTween then
		currentClientAtmoTween:Cancel()
	end

	local tweenInfo = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local targetClockTime = 14.25 -- Ground sunlight remains bright daylight
	local targetBrightness = 2.2
	local targetAmbient = Color3.fromRGB(135, 135, 140)
	local targetOutdoor = Color3.fromRGB(140, 145, 155)
	local targetColorShift = Color3.fromRGB(255, 250, 242)
	local targetExposure = 0.05

	currentClientLightingTween = TweenService:Create(Lighting, tweenInfo, {
		ClockTime = targetClockTime,
		Brightness = targetBrightness,
		Ambient = targetAmbient,
		OutdoorAmbient = targetOutdoor,
		ColorShift_Top = targetColorShift,
		ExposureCompensation = targetExposure,
	})
	currentClientLightingTween:Play()

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		local targetColor = isNight and Color3.fromRGB(20, 20, 45) or Color3.fromRGB(195, 215, 235)
		local targetDecay = isNight and Color3.fromRGB(15, 15, 30) or Color3.fromRGB(105, 120, 140)
		local targetHaze = isNight and 0.0 or 0.45 -- Zero haze eliminates hollow horizon ring

		currentClientAtmoTween = TweenService:Create(atmosphere, tweenInfo, {
			Density = isNight and 0.20 or 0.28,
			Offset = 0.25,
			Color = targetColor,
			Decay = targetDecay,
			Haze = targetHaze,
			Glare = isNight and 0.0 or 0.1,
		})
		currentClientAtmoTween:Play()
	end
end

--------------------------------------------------
-- 4. TRANSITION SEQUENCES
--------------------------------------------------
local sequenceId = 0

-- 1-second black transition during night teleportation + brief announcement banner
local function runNightTransition()
	sequenceId += 1
	local myId = sequenceId

	-- Start smooth 2.0s client-side lighting transition
	animateClientLighting(true)

	local black = getBlackFrame()
	black.BackgroundTransparency = 1
	black.Visible = true

	-- Step 1: Smoothly fade screen to black over 0.25s
	fadeBlack(black, 0, 0.25)
	task.wait(0.25)
	if myId ~= sequenceId then return end

	-- Step 2: Screen is fully black for 0.40s.
	-- Server teleports zone players at 0.35s while completely masked in black!
	task.wait(0.40)
	if myId ~= sequenceId then return end

	-- Step 3: Smoothly fade screen back from black over 0.35s (Total black overlay duration: 1.0s)
	fadeBlack(black, 1, 0.35)
	task.delay(0.35, function()
		if myId == sequenceId and black.BackgroundTransparency >= 0.99 then
			black.Visible = false
		end
	end)

	-- Present clean announcement banner
	local container, title, subtitle = getAnnouncementElements()
	title.Text = "🌙 NIGHT HAS FALLEN"
	title.TextColor3 = Color3.fromRGB(215, 230, 255)
	subtitle.Text = "ZONES CLOSED"
	subtitle.TextColor3 = Color3.fromRGB(255, 220, 70)
	container.Visible = true

	task.wait(2.0)
	if myId ~= sequenceId then return end

	container.Visible = false
end

-- 3-second center-screen countdown before Day begins
local function runDayCountdown(seconds: number)
	sequenceId += 1
	local myId = sequenceId

	seconds = math.clamp(math.floor(tonumber(seconds) or 3), 1, 10)

	local container, title, subtitle = getAnnouncementElements()
	container.Visible = true
	title.Text = "☀️ DAY IN"
	title.TextColor3 = Color3.fromRGB(255, 240, 200)

	for i = seconds, 1, -1 do
		if myId ~= sequenceId then return end
		subtitle.Text = string.format("0:0%d", i)
		subtitle.TextColor3 = Color3.fromRGB(255, 220, 50)
		playCountdownSound(i)
		task.wait(1.0)
	end

	if myId ~= sequenceId then return end

	title.Text = "☀️ DAY HAS ARRIVED!"
	subtitle.Text = "GO!"
	subtitle.TextColor3 = Color3.fromRGB(120, 255, 120)
	playCountdownSound(0)

	task.wait(0.6)
	if myId ~= sequenceId then return end

	container.Visible = false
end

local function cleanupAll()
	sequenceId += 1
	local myId = sequenceId

	-- Start smooth 2.0s client-side lighting transition to Day
	animateClientLighting(false)

	local container = playerGui:FindFirstChild("NightCountdownGui") and playerGui.NightCountdownGui:FindFirstChild("AnnouncementContainer")
	if container and container:IsA("Frame") then
		container.Visible = false
	end

	local black = playerGui:FindFirstChild("NightBlackOverlay") and playerGui.NightBlackOverlay:FindFirstChild("BlackFrame")
	if black and black:IsA("Frame") then
		fadeBlack(black, 1, 0.2)
		task.delay(0.2, function()
			if myId == sequenceId and black.BackgroundTransparency >= 0.99 then
				black.Visible = false
			end
		end)
	end
end

-- Hook remote events
local function hookEvent(ev: RemoteEvent)
	ev.OnClientEvent:Connect(function(action: string, param: any)
		if action == "NightStarted" then
			task.spawn(runNightTransition)
		elseif action == "DayCountdown" then
			task.spawn(runDayCountdown, tonumber(param) or 3)
		elseif action == "DayStarted" then
			cleanupAll()
		end
	end)
end

hookEvent(nightEvent)

local nightStateChanged = ReplicatedStorage:FindFirstChild("NightStateChanged") :: RemoteEvent?
if nightStateChanged and nightStateChanged ~= nightEvent then
	hookEvent(nightStateChanged)
end

-- Initial check on load
local initialPhase = Lighting:GetAttribute("Phase")
if initialPhase == "NIGHT" then
	animateClientLighting(true)
else
	animateClientLighting(false)
end

-- Watch Phase attribute on client as secondary trigger
Lighting:GetAttributeChangedSignal("Phase"):Connect(function()
	local phase = Lighting:GetAttribute("Phase")
	if phase == "NIGHT" then
		animateClientLighting(true)
	elseif phase == "DAY" then
		animateClientLighting(false)
	end
end)
