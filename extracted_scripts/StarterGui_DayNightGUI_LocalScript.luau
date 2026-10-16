-- Path: StarterGui.DayNightGUI.LocalScript
-- Class: LocalScript

--!strict
-- StarterGui > DayNightGUI > LocalScript
-- Redesigned Compact Borderless Day/Night HUD Timer for Steal an Anime Egg
-- Continuous Real-World UTC Wall Clock: never restarts on join, never resets to 4:00
-- Layout: Bottom-right corner (150x36), readable white text with black outline
-- Gradient: Lighter charcoal-black horizontal gradient
--   Left & right edges: lighter charcoal (RGB 78, 78, 78) with subtle transparency
--   Center: slightly darker charcoal (RGB 48, 48, 48) for contrast and readability
-- Absolutely NO container borders, outer strokes, or rectangular outlines

local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local gui = script.Parent :: ScreenGui
if gui:IsA("ScreenGui") then
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 15
	gui.IgnoreGuiInset = false
end

--------------------------------------------------
-- UNIVERSAL DETERMINISTIC IST-ALIGNED CLOCK CALCULATION
--------------------------------------------------
local IST_OFFSET_SECONDS = 19800
local REFERENCE_EPOCH_UTC = 1704090600 -- Jan 1, 2024 at 12:00:00 PM IST (Noon IST)
local DAY_DURATION = 290               -- 290 seconds (4 minutes 50 seconds)
local NIGHT_DURATION = 10              -- 10 seconds total
local COUNTDOWN_DURATION = 3           -- Final 3 seconds of the 10s night
local CYCLE_DURATION = DAY_DURATION + NIGHT_DURATION -- 300 seconds (5 minutes)

local function getUniversalUtcTime(): number
	local success, serverTime = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if success and typeof(serverTime) == "number" and serverTime > 1700000000 then
		return serverTime
	end
	return DateTime.now().UnixTimestampMillis / 1000
end

local function getCycleState(timestamp: number?)
	local now = timestamp or getUniversalUtcTime()
	local elapsed = (now - REFERENCE_EPOCH_UTC) % CYCLE_DURATION
	if elapsed < 0 then
		elapsed += CYCLE_DURATION
	end

	local phase: string
	local eventState: string
	local timeRemaining: number

	if elapsed < DAY_DURATION then
		phase = "DAY"
		eventState = "DAY"
		timeRemaining = DAY_DURATION - elapsed
	elseif elapsed < (DAY_DURATION + NIGHT_DURATION - COUNTDOWN_DURATION) then
		phase = "NIGHT"
		eventState = "NIGHT"
		timeRemaining = CYCLE_DURATION - elapsed
	else
		phase = "NIGHT"
		eventState = "COUNTDOWN"
		timeRemaining = CYCLE_DURATION - elapsed
	end

	return {
		now = now,
		elapsed = elapsed,
		phase = phase,
		eventState = eventState,
		timeRemaining = timeRemaining,
	}
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%d:%02d", minutes, secs)
end

-- 1. Remove unwanted legacy TimerLabel and stray "nowhere" labels safely
local legacyTimer = gui:FindFirstChild("TimerLabel")
if legacyTimer then
	legacyTimer:Destroy()
end

local function purgeNowhereLabels()
	if not player then return end
	local pgui = player:FindFirstChild("PlayerGui")
	if not pgui then return end

	for _, sg in ipairs(pgui:GetChildren()) do
		if sg:IsA("ScreenGui") then
			for _, desc in ipairs(sg:GetDescendants()) do
				if desc:IsA("TextLabel") then
					local txt = desc.Text:lower():gsub("%s+", "")
					if txt == "nowhere" or desc.Name:lower() == "nowhere" then
						desc:Destroy()
					end
				end
			end
		end
	end
end

purgeNowhereLabels()
if player then
	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		purgeNowhereLabels()
	end)
end

-- 2. Ensure single instance of the timer frame without duplication
local CONTAINER_NAME = "DayNightTimerBar"
local existingContainer = gui:FindFirstChild(CONTAINER_NAME)
if existingContainer then
	existingContainer:Destroy()
end

-- 3. Main Bottom-Right Container (Small, Clean, Absolutely Borderless)
local container = Instance.new("Frame")
container.Name = CONTAINER_NAME
container.AnchorPoint = Vector2.new(1, 1)
container.Position = UDim2.new(1, -20, 1, -20)
container.Size = UDim2.fromOffset(150, 36)
container.BackgroundColor3 = Color3.fromRGB(48, 48, 48)
container.BorderSizePixel = 0
container.ClipsDescendants = false
container.Parent = gui

-- Rounded corners
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = container

-- Subtle horizontal charcoal gradient:
-- Left edge: light charcoal RGB(78, 78, 78) with subtle transparency
-- Middle: slightly darker charcoal RGB(48, 48, 48) for high contrast
-- Right edge: light charcoal RGB(78, 78, 78) with subtle transparency
local bgGradient = Instance.new("UIGradient")
bgGradient.Rotation = 0 -- Horizontal gradient
bgGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0.0, Color3.fromRGB(78, 78, 78)), -- Lighter charcoal edge
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(48, 48, 48)), -- Darker charcoal center
	ColorSequenceKeypoint.new(1.0, Color3.fromRGB(78, 78, 78)), -- Lighter charcoal edge
})
bgGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0.0, 0.35), -- Subtle translucent edge
	NumberSequenceKeypoint.new(0.5, 0.15), -- Darker for contrast & readability
	NumberSequenceKeypoint.new(1.0, 0.35), -- Subtle translucent edge
})
bgGradient.Parent = container

-- ABSOLUTELY NO BORDERS: No UIStroke added to container

-- 4. Day / Night Icon with black outline
local iconLabel = Instance.new("TextLabel")
iconLabel.Name = "DayNightIcon"
iconLabel.AnchorPoint = Vector2.new(0, 0.5)
iconLabel.Position = UDim2.new(0, 8, 0.5, 0)
iconLabel.Size = UDim2.fromOffset(20, 20)
iconLabel.BackgroundTransparency = 1
iconLabel.Font = Enum.Font.GothamBold
iconLabel.TextScaled = true
iconLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
iconLabel.Parent = container

local iconStroke = Instance.new("UIStroke")
iconStroke.Color = Color3.fromRGB(0, 0, 0)
iconStroke.Thickness = 2
iconStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
iconStroke.Parent = iconLabel

-- 5. Timer Text Label (Small, clear white text with black text outline)
local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "TimerText"
timerLabel.AnchorPoint = Vector2.new(0, 0.5)
timerLabel.Position = UDim2.new(0, 34, 0.5, 0)
timerLabel.Size = UDim2.new(1, -38, 1, 0)
timerLabel.BackgroundTransparency = 1
timerLabel.Font = Enum.Font.GothamBold
timerLabel.TextSize = 14
timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
timerLabel.TextScaled = false
timerLabel.TextXAlignment = Enum.TextXAlignment.Left
timerLabel.TextYAlignment = Enum.TextYAlignment.Center
timerLabel.Parent = container

local textStroke = Instance.new("UIStroke")
textStroke.Color = Color3.fromRGB(0, 0, 0)
textStroke.Thickness = 2
textStroke.Transparency = 0
textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
textStroke.Parent = timerLabel

-- 6. Immediate Initialization from the True Global Schedule (Never defaults to 4:00)
local function applyCurrentState()
	local state = getCycleState()
	if state.eventState == "COUNTDOWN" then
		iconLabel.Text = "☀️"
		timerLabel.Text = "Day in: " .. formatTime(state.timeRemaining)
	elseif state.eventState == "NIGHT" then
		iconLabel.Text = "🌙"
		timerLabel.Text = "Night: " .. formatTime(state.timeRemaining)
	else
		iconLabel.Text = "☀️"
		timerLabel.Text = "Day: " .. formatTime(state.timeRemaining)
	end
end

applyCurrentState()

--------------------------------------------------
-- RENDERSTEPPED SYNCHRONIZED UPDATE
--------------------------------------------------
local renderConnection: RBXScriptConnection? = nil

renderConnection = RunService.RenderStepped:Connect(function()
	if not container.Parent then
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
		return
	end

	applyCurrentState()
end)

script.Destroying:Connect(function()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end)
