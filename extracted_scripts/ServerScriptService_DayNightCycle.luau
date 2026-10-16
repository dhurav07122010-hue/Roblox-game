-- Path: ServerScriptService.DayNightCycle
-- Class: Script

--!strict
-- ServerScriptService > DayNightCycle
-- Authoritative, deterministic global Day/Night cycle controller for Steal an Anime Egg
-- Perfectly synchronized to real-world clock: 5-minute repeating cycle (12:00, 12:05, 12:10, etc.)
-- Aligned to India Standard Time (IST, UTC+05:30) with configurable Reference Epoch
-- Schedule continues mathematically 24/7 across all servers even with zero servers online.
-- Cycle: 300 seconds total (Day = 290s [4:50], Night = 10s total, final 3s = Countdown [Day in: 0:03])

local Lighting = game:GetService("Lighting")

-- ============================================================================
-- GLOBAL CLOCK CONFIGURATION (INDIA STANDARD TIME ALIGNED)
-- ============================================================================
-- IST Offset from UTC: +05:30 = 5 hours 30 minutes = 19,800 seconds
local IST_OFFSET_SECONDS = 5 * 3600 + 30 * 60 -- 19800 seconds

-- PERMANENT REFERENCE EPOCH:
-- Anchored to January 1, 2024 at 12:00:00 PM IST (Noon IST).
-- In UTC, this corresponds to January 1, 2024 at 06:30:00 AM UTC (timestamp: 1704090600).
-- At this exact anchor instant and every 5 minutes thereafter (:00, :05, :10, :15, ...),
-- a Day phase begins at Day: 4:50.
local REFERENCE_EPOCH_UTC = 1704090600

-- Cycle durations (in seconds): Day 290s (4:50), Night 10s (final 3s countdown), Total 300s (5m)
local DAY_DURATION = 290       -- 290 seconds (4 minutes 50 seconds)
local NIGHT_DURATION = 10      -- 10 seconds total
local COUNTDOWN_DURATION = 3   -- Final 3 seconds of the 10s night ("Day in: 0:03" -> "0:01")
local CYCLE_DURATION = 300     -- Total repeating cycle (290 + 10 = 300s = 5 minutes)

-- High-precision real-world UTC time provider
-- Independent of server uptime, player joins, or local time zones
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
	local hatchMultiplier: number

	if elapsed < DAY_DURATION then
		-- Phase 1: DAY (0s to 290s: Day: 4:50 down to Day: 0:01)
		phase = "DAY"
		eventState = "DAY"
		timeRemaining = DAY_DURATION - elapsed
		hatchMultiplier = 1

	elseif elapsed < (DAY_DURATION + NIGHT_DURATION - COUNTDOWN_DURATION) then
		-- Phase 2: NIGHT NORMAL (290s to 297s = first 7s of night: Night: 0:10 down to Night: 0:04)
		phase = "NIGHT"
		eventState = "NIGHT"
		timeRemaining = CYCLE_DURATION - elapsed
		hatchMultiplier = 50

	else
		-- Phase 3: NIGHT COUNTDOWN (297s to 300s = final 3s of night: Day in: 0:03 down to Day in: 0:01)
		phase = "NIGHT"
		eventState = "COUNTDOWN"
		timeRemaining = CYCLE_DURATION - elapsed
		hatchMultiplier = 1
	end

	return {
		now = now,
		elapsed = elapsed,
		phase = phase,
		eventState = eventState,
		timeRemaining = timeRemaining,
		hatchMultiplier = hatchMultiplier,
		phaseEndTime = now + timeRemaining,
	}
end

-- Initialize Lighting attributes immediately on server load
local initial = getCycleState()
Lighting:SetAttribute("ReferenceEpochUtc", REFERENCE_EPOCH_UTC)
Lighting:SetAttribute("IstOffsetSeconds", IST_OFFSET_SECONDS)
Lighting:SetAttribute("CycleDuration", CYCLE_DURATION)
Lighting:SetAttribute("DayDuration", DAY_DURATION)
Lighting:SetAttribute("NightDuration", NIGHT_DURATION)
Lighting:SetAttribute("CountdownDuration", COUNTDOWN_DURATION)
Lighting:SetAttribute("Phase", initial.phase)
Lighting:SetAttribute("EventState", initial.eventState)
Lighting:SetAttribute("PhaseEndTime", initial.phaseEndTime)
Lighting:SetAttribute("HatchSpeedMultiplier", initial.hatchMultiplier)

print(string.format("[DayNightCycle] IST Aligned 5-Min Clock (Anchor: Jan 1 2024 12:00PM IST). Elapsed=%.2fs, State=%s, Remaining=%.2fs",
	initial.elapsed, initial.eventState, initial.timeRemaining))

while true do
	local state = getCycleState()

	Lighting:SetAttribute("Phase", state.phase)
	Lighting:SetAttribute("EventState", state.eventState)
	Lighting:SetAttribute("PhaseEndTime", state.phaseEndTime)
	Lighting:SetAttribute("HatchSpeedMultiplier", state.hatchMultiplier)

	task.wait(0.1)
end
