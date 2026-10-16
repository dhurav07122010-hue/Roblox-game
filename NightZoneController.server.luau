--!strict
-- ServerScriptService > NightZoneController
-- Manages Zone1 NightBarrier, player eviction, and Day/Night zone synchronization
-- Features:
--   1. Smooth centered appearing animation: scales from 5% to 100% full size over 1.0s (Quad Out)
--   2. Smooth disappearing animation: retracts upward from bottom to top over 1.5s (Quad In)
--   3. Timer updates never interrupt or overwrite active animations
-- Aligned to India Standard Time (IST, UTC+05:30) with configurable Reference Epoch (5-min repeating cycle)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local zonesFolder = workspace:WaitForChild("Zones")
local redLine = zonesFolder:WaitForChild("RedLine") :: BasePart

local BARRIER_ZONE_NAMES = {
	Zone1 = true,
}

local APPEAR_TIME = 1.0  -- Exactly 1 second appearing animation
local RETRACT_TIME = 1.5 -- Exactly 1.5 seconds retracting animation
local PIXELS_PER_STUD = 14

-- Global Clock Configuration (IST Aligned 5-Min Cycle)
local IST_OFFSET_SECONDS = 19800
local REFERENCE_EPOCH_UTC = 1704090600 -- Jan 1, 2024 at 12:00:00 PM IST (Noon IST)
local DAY_DURATION = 290               -- 290 seconds (4 minutes 50 seconds)
local NIGHT_DURATION = 10              -- 10 seconds total
local COUNTDOWN_DURATION = 3           -- Final 3 seconds of night
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

local barriers: { [string]: BasePart } = {}
local originalBarrierProperties: {
	[BasePart]: {
		Size: Vector3,
		CFrame: CFrame,
		Material: Enum.Material,
		Color: Color3,
	}
} = {}

local barrierTextLabels: { [BasePart]: { TextLabel } } = {}
local transitionToken = 0
local lastState: string? = nil

-- Create or find ReplicatedStorage Events for client alerts
local nightEvent = ReplicatedStorage:FindFirstChild("NightZoneEvent") :: RemoteEvent?
if not nightEvent then
	nightEvent = Instance.new("RemoteEvent")
	nightEvent.Name = "NightZoneEvent"
	nightEvent.Parent = ReplicatedStorage
end
local nightStateChanged = ReplicatedStorage:FindFirstChild("NightStateChanged") :: RemoteEvent?

local function broadcastNightEvent(action: string, param: any?)
	if nightEvent then
		nightEvent:FireAllClients(action, param)
	end
	if nightStateChanged then
		nightStateChanged:FireAllClients(action, param)
	end
end

--------------------------------------------------
-- GEOMETRY & ZONE DETECTION HELPERS
--------------------------------------------------

local function getZoneArea(zone: Instance): BasePart?
	local area = zone:FindFirstChild("ZoneArea", true)
	if area and area:IsA("BasePart") then
		return area
	end
	area = zone:FindFirstChild("Area", true)
	if area and area:IsA("BasePart") then
		return area
	end
	for _, child in ipairs(zone:GetChildren()) do
		if child:IsA("BasePart") and child.Name:lower():find("area") then
			return child
		end
	end
	return nil
end

local function getBarrier(zone: Instance): BasePart?
	local barrier = zone:FindFirstChild("NightBarrier", true)
	if barrier and barrier:IsA("BasePart") then
		return barrier
	end
	return nil
end

local function pointInsidePart(part: BasePart, point: Vector3): boolean
	local cframe = part.CFrame
	local size = part.Size
	local rel = cframe:PointToObjectSpace(point)
	return math.abs(rel.X) <= (size.X / 2 + 2)
		and math.abs(rel.Z) <= (size.Z / 2 + 2)
		and (rel.Y >= -size.Y / 2 - 2 and rel.Y <= size.Y / 2 + 30) -- Generous height tolerance so jumping players are caught!
end

--------------------------------------------------
-- SURFACEGUI DISPLAY SETUP
--------------------------------------------------

local function setupSurfaceGuiOnFace(barrier: BasePart, face: Enum.NormalId, suffix: string): TextLabel
	local guiName = "NightBarrierSurfaceGui_" .. suffix
	local surfaceGui = barrier:FindFirstChild(guiName) :: SurfaceGui?
	if not surfaceGui then
		surfaceGui = Instance.new("SurfaceGui")
		surfaceGui.Name = guiName
		surfaceGui.Face = face
		surfaceGui.LightInfluence = 0
		surfaceGui.AlwaysOnTop = false
		surfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		surfaceGui.ResetOnSpawn = false
		surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surfaceGui.PixelsPerStud = PIXELS_PER_STUD
		surfaceGui.Parent = barrier
	else
		surfaceGui.Face = face
		surfaceGui.LightInfluence = 0
		surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surfaceGui.PixelsPerStud = PIXELS_PER_STUD
	end

	local textLabel = surfaceGui:FindFirstChild("CountdownLabel") :: TextLabel?
	if not textLabel then
		textLabel = Instance.new("TextLabel")
		textLabel.Name = "CountdownLabel"
		textLabel.Size = UDim2.fromScale(1, 1)
		textLabel.Position = UDim2.fromScale(0, 0)
		textLabel.BackgroundTransparency = 1
		textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		textLabel.Font = Enum.Font.GothamBlack
		textLabel.TextScaled = true
		textLabel.TextWrapped = true
		textLabel.RichText = true
		textLabel.Text = "🌙 NIGHT"
		textLabel.Parent = surfaceGui

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Color = Color3.fromRGB(0, 0, 0)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = textLabel
	end

	local constraint = textLabel:FindFirstChildOfClass("UITextSizeConstraint")
	if not constraint then
		constraint = Instance.new("UITextSizeConstraint")
		constraint.Parent = textLabel
	end
	constraint.MinTextSize = 24
	constraint.MaxTextSize = 400

	return textLabel
end

local function createBarrierDisplays(barrier: BasePart)
	local labelFront = setupSurfaceGuiOnFace(barrier, Enum.NormalId.Front, "Front")
	local labelBack = setupSurfaceGuiOnFace(barrier, Enum.NormalId.Back, "Back")
	barrierTextLabels[barrier] = { labelFront, labelBack }
end

local function setupBarriers()
	for _, zone in ipairs(zonesFolder:GetChildren()) do
		if zone:IsA("Folder") or zone:IsA("Model") then
			if BARRIER_ZONE_NAMES[zone.Name] then
				local barrier = getBarrier(zone)
				if barrier then
					barriers[zone.Name] = barrier

					if not originalBarrierProperties[barrier] then
						originalBarrierProperties[barrier] = {
							Size = barrier.Size,
							CFrame = barrier.CFrame,
							Material = barrier.Material,
							Color = barrier.Color,
						}
					end

					createBarrierDisplays(barrier)
				else
					warn("[NightZoneController] NightBarrier missing in " .. zone.Name)
				end
			end
		end
	end
end

--------------------------------------------------
-- BARRIER VISIBILITY AND COLLISION LOGIC
--------------------------------------------------

local function setBarrierGuisEnabled(barrier: BasePart, enabled: boolean)
	local fg = barrier:FindFirstChild("NightBarrierSurfaceGui_Front") :: SurfaceGui?
	if fg then fg.Enabled = enabled end
	local bg = barrier:FindFirstChild("NightBarrierSurfaceGui_Back") :: SurfaceGui?
	if bg then bg.Enabled = enabled end
	local leg = barrier:FindFirstChild("NightBarrierSurfaceGui") :: SurfaceGui?
	if leg then leg.Enabled = false end
end

-- Immediately hides the barrier during Day (Transparency = 1, CanCollide = false)
local function hideBarriersImmediately()
	for _, barrier in pairs(barriers) do
		local original = originalBarrierProperties[barrier]
		if original and barrier.Parent then
			barrier.Size = original.Size
			barrier.CFrame = original.CFrame
			barrier.Transparency = 1        -- Completely invisible
			barrier.CanCollide = false      -- Freely passable
			barrier.CanTouch = false
			barrier.CanQuery = false
			setBarrierGuisEnabled(barrier, false)
		end
	end
end

-- Shows the barrier solid and visible at full size immediately (used for steady state / mid-cycle join)
local function showBarriersImmediate(text: string)
	for _, barrier in pairs(barriers) do
		local original = originalBarrierProperties[barrier]
		if original and barrier.Parent then
			barrier.Size = original.Size
			barrier.CFrame = original.CFrame
			barrier.Transparency = 0        -- Fully visible
			barrier.CanCollide = true       -- Solid wall
			barrier.CanTouch = true
			barrier.CanQuery = true
			barrier.Material = Enum.Material.SmoothPlastic
			barrier.Color = Color3.fromRGB(245, 245, 245)

			setBarrierGuisEnabled(barrier, true)

			local labels = barrierTextLabels[barrier]
			if labels then
				for _, lbl in ipairs(labels) do
					lbl.Text = text
				end
			end
		end
	end
end

-- Updates ONLY the text displayed on the barriers without touching size, CFrame, or collision
local function updateBarrierTextOnly(text: string)
	for _, barrier in pairs(barriers) do
		local labels = barrierTextLabels[barrier]
		if labels then
			for _, lbl in ipairs(labels) do
				lbl.Text = text
			end
		end
	end
end

--------------------------------------------------
-- 1. NIGHTBARRIER APPEARING ANIMATION (1.0s, 5% -> 100%)
--------------------------------------------------
-- Starts at 5% size, perfectly centered at final CFrame, and scales smoothly to full size
local function appearBarriers(text: string)
	transitionToken += 1
	local myToken = transitionToken

	for _, barrier in pairs(barriers) do
		local original = originalBarrierProperties[barrier]
		if original and barrier.Parent then
			-- Start at ~5% dimensions, centered at original CFrame
			local smallSize = original.Size * 0.05
			barrier.Size = smallSize
			barrier.CFrame = original.CFrame
			barrier.Transparency = 0
			barrier.CanCollide = true
			barrier.CanTouch = true
			barrier.CanQuery = true
			barrier.Material = Enum.Material.SmoothPlastic
			barrier.Color = Color3.fromRGB(245, 245, 245)

			setBarrierGuisEnabled(barrier, true)
			local labels = barrierTextLabels[barrier]
			if labels then
				for _, lbl in ipairs(labels) do
					lbl.Text = text
				end
			end

			-- Smooth centered expansion to original full size over exactly 1 second
			local tweenInfo = TweenInfo.new(
				APPEAR_TIME,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			)

			local tween = TweenService:Create(barrier, tweenInfo, {
				Size = original.Size,
				CFrame = original.CFrame,
				Transparency = 0,
			})

			tween:Play()

			task.delay(APPEAR_TIME, function()
				if myToken ~= transitionToken then
					return
				end
				if barrier.Parent then
					barrier.Size = original.Size
					barrier.CFrame = original.CFrame
				end
			end)
		end
	end
end

--------------------------------------------------
-- 2. ORIGINAL RETRACT BARRIERS DISAPPEARING ANIMATION (1.5s, Quad In)
--------------------------------------------------
-- Shrinks upward from bottom to top, disappearing at daybreak
local function retractBarriers()
	transitionToken += 1
	local myToken = transitionToken

	for _, barrier in pairs(barriers) do
		local original = originalBarrierProperties[barrier]
		if original and barrier.Parent then
			local originalSize = original.Size
			local originalCFrame = original.CFrame

			-- Base stays grounded while height shrinks upward to 0.05
			local targetSize = Vector3.new(originalSize.X, 0.05, originalSize.Z)
			local bottomY = originalCFrame.Position.Y - (originalSize.Y / 2)
			local targetY = bottomY + (targetSize.Y / 2)

			local targetCFrame = CFrame.new(
				originalCFrame.Position.X,
				targetY,
				originalCFrame.Position.Z
			) * originalCFrame.Rotation

			-- Disable collision immediately so players can pass through as it retracts
			barrier.CanCollide = false
			barrier.CanTouch = false
			barrier.CanQuery = false

			local tweenInfo = TweenInfo.new(
				RETRACT_TIME,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)

			local tween = TweenService:Create(barrier, tweenInfo, {
				Size = targetSize,
				CFrame = targetCFrame,
				Transparency = 1,
			})

			tween:Play()

			task.delay(RETRACT_TIME, function()
				if myToken ~= transitionToken then
					return
				end
				if barrier.Parent then
					barrier.Size = original.Size
					barrier.CFrame = originalCFrame
					barrier.Transparency = 1        -- 100% invisible during Day
					barrier.CanCollide = false      -- Non-collidable during Day
					barrier.CanTouch = false
					barrier.CanQuery = false
					setBarrierGuisEnabled(barrier, false)
				end
			end)
		end
	end
end

--------------------------------------------------
-- PLAYER EVICTION (ZONES -> REDLINE)
--------------------------------------------------

local function getPlayerZone(player: Player): Instance?
	local character = player.Character
	if not character then return nil end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end

	for _, zone in ipairs(zonesFolder:GetChildren()) do
		if zone:IsA("Folder") or zone:IsA("Model") then
			local area = getZoneArea(zone)
			if area and pointInsidePart(area, root.Position) then
				return zone
			end
		end
	end
	return nil
end

local function teleportPlayersFromZones()
	for _, player in ipairs(Players:GetPlayers()) do
		local zone = getPlayerZone(player)
		if zone then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local offset = Vector3.new(math.random(-4, 4), 4, math.random(-4, 4))
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				character:PivotTo(redLine.CFrame + offset)
			end
		end
	end
end

--------------------------------------------------
-- TIME FORMATTER HELPER (M:SS)
--------------------------------------------------

local function formatTimer(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%d:%02d", minutes, secs)
end

--------------------------------------------------
-- SYNCHRONIZED STATE CONTROLLER & JOIN HANDLER
--------------------------------------------------

setupBarriers()

-- Initialize immediately to match the current real-world IST-aligned phase
local initialState = getCycleState()
lastState = initialState.eventState

if initialState.eventState == "DAY" then
	hideBarriersImmediately()
elseif initialState.eventState == "NIGHT" then
	-- Mid-cycle join: if within first 1.0s of night, animate appear; otherwise show solid immediately
	local nightElapsed = initialState.elapsed - DAY_DURATION
	if nightElapsed < APPEAR_TIME then
		appearBarriers("🌙 NIGHT: " .. formatTimer(initialState.timeRemaining))
	else
		showBarriersImmediate("🌙 NIGHT: " .. formatTimer(initialState.timeRemaining))
	end
else
	showBarriersImmediate("☀️ DAY IN: " .. formatTimer(initialState.timeRemaining))
end

-- Ensure newly joining players receive the current global state immediately
Players.PlayerAdded:Connect(function(player: Player)
	local current = getCycleState()
	if current.eventState == "NIGHT" then
		nightEvent:FireClient(player, "NightStarted", current.timeRemaining)
	elseif current.eventState == "COUNTDOWN" then
		nightEvent:FireClient(player, "DayCountdown", current.timeRemaining)
	elseif current.eventState == "DAY" then
		nightEvent:FireClient(player, "DayStarted")
	end
end)

while true do
	local current = getCycleState()
	local state = current.eventState

	if state ~= lastState then
		lastState = state

		if state == "NIGHT" then
			-- 1. Notify clients immediately to start 1-second black transition
			broadcastNightEvent("NightStarted", 10)

			-- 2. Animate NightBarrier from 5% to full size over 1.0 second
			appearBarriers("🌙 NIGHT: 0:10")

			-- 3. Teleport players at 0.35s while their screen is completely black
			task.delay(0.35, function()
				teleportPlayersFromZones()
			end)

		elseif state == "COUNTDOWN" then
			updateBarrierTextOnly("☀️ DAY IN: 0:03")
			broadcastNightEvent("DayCountdown", 3)

		elseif state == "DAY" then
			-- 2. Play original 1.5s Quad In upward retraction disappearing animation
			retractBarriers()
			broadcastNightEvent("DayStarted")
		end
	end

	-- Continuously refresh dynamic countdown text without interrupting size/position tweens
	if state == "NIGHT" then
		updateBarrierTextOnly("🌙 NIGHT: " .. formatTimer(current.timeRemaining))
	elseif state == "COUNTDOWN" then
		updateBarrierTextOnly("☀️ DAY IN: " .. formatTimer(current.timeRemaining))
	end

	task.wait(0.1)
end
