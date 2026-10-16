--!strict
-- StarterPlayer > StarterPlayerScripts > StatsHUDController
-- Redesigned Bottom-Left Stats Counters & Client Gameplay Controller:
--   1. Compact Outlined Counters (Speed 👟, Money 💵, Strength 🏋️) - sized sleek & unobtrusive
--   2. Strict Dumbbell Visibility: Other players' dumbbells are hidden; visible ONLY to owner
--   3. Instant Jump-To-Exit Training Handler via UserInputService

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local SCREEN_GUI_NAME = "StatsHUD"
local CONTAINER_NAME = "StatsHUDContainer"

--------------------------------------------------------------------------------
-- 1. COMPACT NUMBER FORMATTING (SIMULATOR STYLE: K, M, B, T, Qa, etc.)
--------------------------------------------------------------------------------
local SUFFIXES = {
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd"
}

local function formatCompactStat(value: number): string
	if value < 0 then
		return "-" .. formatCompactStat(-value)
	end
	if value < 1000 then
		return tostring(math.floor(value))
	end

	local exp = math.floor(math.log(value, 10) / 3)
	local index = exp + 1

	if index > #SUFFIXES then
		index = #SUFFIXES
		exp = #SUFFIXES - 1
	end

	local divisor = 10 ^ (exp * 3)
	local scaled = math.floor((value / divisor) * 10) / 10
	local suffix = SUFFIXES[index]

	if scaled == math.floor(scaled) then
		return string.format("%.0f%s", scaled, suffix)
	else
		return string.format("%.1f%s", scaled, suffix)
	end
end

--------------------------------------------------------------------------------
-- 2. CLEANUP DUPLICATE OLD STAT DISPLAYS
--------------------------------------------------------------------------------
local function cleanupDuplicateStatDisplays()
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and child.Name ~= SCREEN_GUI_NAME then
			local nameL = child.Name:lower()
			if nameL == "oldstatshud" or nameL == "stathud" or nameL == "statscounters" then
				child:Destroy()
			end
		end
	end
end

--------------------------------------------------------------------------------
-- 3. BUILD THE THREE STAT COUNTERS (SLEEK COMPACT SIMULATOR STYLE)
--------------------------------------------------------------------------------
local function buildStatsHUD(): (ScreenGui, TextLabel, TextLabel, TextLabel)
	-- Remove old instance to prevent duplicates
	local existing = playerGui:FindFirstChild(SCREEN_GUI_NAME)
	if existing then
		existing:Destroy()
	end
	cleanupDuplicateStatDisplays()

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = SCREEN_GUI_NAME
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 15
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = playerGui

	-- Pinned neatly to bottom-left corner, sized a bit smaller for a sleek look
	local container = Instance.new("Frame")
	container.Name = CONTAINER_NAME
	container.AnchorPoint = Vector2.new(0, 1)
	container.Position = UDim2.new(0, 20, 1, -20)
	container.Size = UDim2.fromOffset(195, 96) -- Clean compact sizing (~25% smaller)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ClipsDescendants = false
	container.Parent = screenGui

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	listLayout.Parent = container

	-- Helper to create each stat row matching the reference screenshot
	local function createStatRow(order: number, iconEmoji: string, defaultText: string, textColor: Color3): TextLabel
		local row = Instance.new("Frame")
		row.Name = "Row_" .. tostring(order)
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, 26) -- Compact row height
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.ClipsDescendants = false
		row.Parent = container

		-- Icon (Left)
		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "Icon"
		iconLabel.AnchorPoint = Vector2.new(0, 0.5)
		iconLabel.Position = UDim2.new(0, 0, 0.5, 0)
		iconLabel.Size = UDim2.fromOffset(26, 26)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Font = Enum.Font.FredokaOne
		iconLabel.TextSize = 20
		iconLabel.Text = iconEmoji
		iconLabel.Parent = row

		local iconStroke = Instance.new("UIStroke")
		iconStroke.Color = Color3.fromRGB(0, 0, 0)
		iconStroke.Thickness = 2.0
		iconStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		iconStroke.Parent = iconLabel

		-- Stat Value (Right of Icon)
		local valueLabel = Instance.new("TextLabel")
		valueLabel.Name = "Value"
		valueLabel.AnchorPoint = Vector2.new(0, 0.5)
		valueLabel.Position = UDim2.new(0, 32, 0.5, 0)
		valueLabel.Size = UDim2.new(1, -32, 1, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Font = Enum.Font.FredokaOne
		pcall(function()
			valueLabel.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic)
		end)
		valueLabel.TextSize = 22 -- Sleek readable size
		valueLabel.TextColor3 = textColor
		valueLabel.TextXAlignment = Enum.TextXAlignment.Left
		valueLabel.TextYAlignment = Enum.TextYAlignment.Center
		valueLabel.Text = defaultText
		valueLabel.ClipsDescendants = false
		valueLabel.Parent = row

		-- Thick black outline matching the screenshot
		local textStroke = Instance.new("UIStroke")
		textStroke.Color = Color3.fromRGB(0, 0, 0)
		textStroke.Thickness = 2.8
		textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		textStroke.Parent = valueLabel

		return valueLabel
	end

	-- 1. Speed (Running shoe icon, bright cyan: 108.9B style)
	local speedLabel = createStatRow(1, "👟", "16", Color3.fromRGB(48, 229, 255))

	-- 2. Money (Cash stack icon, bright lime green: $27.7Qa style)
	local moneyLabel = createStatRow(2, "💵", "$0", Color3.fromRGB(40, 240, 60))

	-- 3. Strength (Dumbbell icon, bright energetic red)
	local strengthLabel = createStatRow(3, "🏋️", "0", Color3.fromRGB(255, 65, 65))

	return screenGui, speedLabel, moneyLabel, strengthLabel
end

--------------------------------------------------------------------------------
-- 4. REAL-TIME STAT BINDINGS & LIVE UPDATES
--------------------------------------------------------------------------------
local screenGui, speedValLabel, moneyValLabel, strengthValLabel = buildStatsHUD()

-- Speed listener: displays player's true base speed stat, ignoring carrying slowdown!
local function updateSpeed()
	local speedNum = player:GetAttribute("BaseSpeed")
	if typeof(speedNum) ~= "number" or speedNum <= 0 then
		speedNum = 16
	end
	if speedValLabel and speedValLabel.Parent then
		speedValLabel.Text = formatCompactStat(speedNum)
	end
end

player:GetAttributeChangedSignal("BaseSpeed"):Connect(updateSpeed)
updateSpeed()

-- Money & Strength leaderstats listener
local function hookLeaderstats()
	local stats = player:WaitForChild("leaderstats", 10) :: Folder?
	if not stats then return end

	local strVal = stats:WaitForChild("Strength", 5) :: IntValue?
	if strVal and strengthValLabel and strengthValLabel.Parent then
		strengthValLabel.Text = formatCompactStat(strVal.Value)
		strVal:GetPropertyChangedSignal("Value"):Connect(function()
			strengthValLabel.Text = formatCompactStat(strVal.Value)
		end)
	end

	local monVal = stats:WaitForChild("Money", 5) :: IntValue?
	if monVal and moneyValLabel and moneyValLabel.Parent then
		moneyValLabel.Text = "$" .. formatCompactStat(monVal.Value)
		monVal:GetPropertyChangedSignal("Value"):Connect(function()
			moneyValLabel.Text = "$" .. formatCompactStat(monVal.Value)
		end)
	end
end

task.spawn(hookLeaderstats)

--------------------------------------------------------------------------------
-- 5. TRAINING AREA & DUMBBELL VISIBILITY
-- Other players' training pads, borders, text, and dumbbells MUST be invisible.
-- They should ONLY appear to other players if the owner is actively using it!
-- The owner sees their own pad/dumbbell.
--------------------------------------------------------------------------------
local function getAllPens(): { Model }
	local pens: { Model } = {}
	local spawnFolder = Workspace:FindFirstChild("Spawn")
	local pensFolder = spawnFolder and spawnFolder:FindFirstChild("Pens")
	if pensFolder then
		for _, c in ipairs(pensFolder:GetChildren()) do
			if c:IsA("Model") and not table.find(pens, c) then
				table.insert(pens, c)
			end
		end
	end
	for _, c in ipairs(Workspace:GetChildren()) do
		if c:IsA("Model") and c.Name:lower():match("pen%s*%d") and not c.Name:lower():match("pen%s*l") then
			if not table.find(pens, c) then
				table.insert(pens, c)
			end
		end
	end
	return pens
end

local function updateTrainingAreaVisibility()
	local myUserId = player.UserId
	local pens = getAllPens()

	for _, pen in ipairs(pens) do
		local ownerId = pen:GetAttribute("OwnerUserId") or 0
		local isOwner = (myUserId ~= 0 and ownerId ~= 0 and ownerId == myUserId)
		local isBeingUsed = (pen:GetAttribute("IsTraining") == true)
		-- Visible to owner always, and visible to other players ONLY if owner is actively using it!
		local shouldBeVisible = isOwner or isBeingUsed

		local trainingArea = pen:FindFirstChild("StrengthTrainingArea")
		for _, desc in ipairs(pen:GetDescendants()) do
			local nameL = desc.Name:lower()
			local isPartOfTraining = (trainingArea and desc:IsDescendantOf(trainingArea))
				or desc.Name == "StrengthTrainingArea"
				or nameL:find("training")
				or nameL:find("dumbel")
				or nameL:find("upgrade")
				or nameL:find("sign")

			if isPartOfTraining then
				if desc:IsA("BasePart") then
					desc.Transparency = shouldBeVisible and 0 or 1
					desc.CanCollide = shouldBeVisible and isOwner
				elseif desc:IsA("Decal") or desc:IsA("Texture") then
					desc.Transparency = shouldBeVisible and 0 or 1
				elseif desc:IsA("SelectionBox") then
					desc.Transparency = shouldBeVisible and 0 or 1
					desc.Adornee = shouldBeVisible and desc.Parent or nil
				elseif desc:IsA("Highlight") then
					desc.Enabled = shouldBeVisible
				elseif desc:IsA("SurfaceGui") or desc:IsA("BillboardGui") then
					desc.Enabled = shouldBeVisible
				elseif desc:IsA("ProximityPrompt") then
					desc.Enabled = shouldBeVisible
				elseif desc:IsA("ClickDetector") then
					desc.MaxActivationDistance = shouldBeVisible and 14 or 0
				elseif desc:IsA("Beam") or desc:IsA("ParticleEmitter") or desc:IsA("Trail") then
					desc.Enabled = shouldBeVisible
				end
			end
		end
	end

	-- Also hide any loose prototype dumbbells in Workspace
	for _, name in ipairs({"dumbel1", "dumbel2", "dumbel3", "Dumbel1", "Dumbel2", "Dumbel3"}) do
		local proto = Workspace:FindFirstChild(name)
		if proto and proto:IsA("Model") then
			for _, desc in ipairs(proto:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.Transparency = 1
					desc.CanCollide = false
				end
			end
		end
	end
end

task.spawn(function()
	task.wait(0.3)
	local function hookPen(pen: Model)
		pen:GetAttributeChangedSignal("OwnerUserId"):Connect(updateTrainingAreaVisibility)
		pen:GetAttributeChangedSignal("IsTraining"):Connect(updateTrainingAreaVisibility)
		pen.DescendantAdded:Connect(function()
			task.wait(0.05)
			updateTrainingAreaVisibility()
		end)
	end

	for _, pen in ipairs(getAllPens()) do
		hookPen(pen)
	end

	local spawnFolder = Workspace:FindFirstChild("Spawn")
	local pensFolder = spawnFolder and spawnFolder:FindFirstChild("Pens")
	if pensFolder then
		pensFolder.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				hookPen(child)
				updateTrainingAreaVisibility()
			end
		end)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child:IsA("Model") and child.Name:lower():match("pen%s*%d") then
			hookPen(child)
			updateTrainingAreaVisibility()
		end
	end)

	updateTrainingAreaVisibility()

	-- Periodic sync fallback ensures 100% visual consistency
	while true do
		task.wait(1.0)
		updateTrainingAreaVisibility()
	end
end)

--------------------------------------------------------------------------------
-- 6. JUMP TO LEAVE AUTO-TRAINING (INPUT LISTENER)
--------------------------------------------------------------------------------
local trainingRemote: RemoteEvent? = nil
local function getTrainingRemote(): RemoteEvent?
	if trainingRemote and trainingRemote.Parent then
		return trainingRemote
	end
	trainingRemote = ReplicatedStorage:FindFirstChild("TrainingAction") :: RemoteEvent?
	return trainingRemote
end

UserInputService.JumpRequest:Connect(function()
	if player:GetAttribute("IsTraining") == true then
		local remote = getTrainingRemote()
		if remote then
			remote:FireServer("Jump")
		end
	end
end)

--------------------------------------------------------------------------------
-- 7. DROP CARRIED EGG BUTTON & KEYBIND (Q)
--------------------------------------------------------------------------------
local dropButton = Instance.new("TextButton")
dropButton.Name = "DropEggButton"
dropButton.AnchorPoint = Vector2.new(0.5, 1)
dropButton.Position = UDim2.new(0.5, 0, 1, -25)
dropButton.Size = UDim2.fromOffset(180, 52)
dropButton.BackgroundColor3 = Color3.fromRGB(235, 50, 50)
dropButton.Font = Enum.Font.FredokaOne
dropButton.TextSize = 18
dropButton.TextColor3 = Color3.fromRGB(255, 255, 255)
dropButton.Text = "🗑️ DROP EGG\n[Press Q]"
dropButton.AutoButtonColor = true
dropButton.Visible = false
dropButton.Parent = screenGui

local dropCorner = Instance.new("UICorner")
dropCorner.CornerRadius = UDim.new(0, 10)
dropCorner.Parent = dropButton

local dropStroke = Instance.new("UIStroke")
dropStroke.Color = Color3.fromRGB(0, 0, 0)
dropStroke.Thickness = 2.8
dropStroke.Parent = dropButton

local function updateDropButtonVisibility()
	local carrying = (player:GetAttribute("CarryingEgg") == true)
	dropButton.Visible = carrying
end

player:GetAttributeChangedSignal("CarryingEgg"):Connect(updateDropButtonVisibility)
updateDropButtonVisibility()

local function triggerDropEgg()
	if player:GetAttribute("CarryingEgg") == true then
		local remote = ReplicatedStorage:FindFirstChild("DropEggAction") :: RemoteEvent?
		if remote then
			remote:FireServer()
		end
	end
end

dropButton.MouseButton1Click:Connect(triggerDropEgg)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Q then
		triggerDropEgg()
	end
end)

--------------------------------------------------------------------------------
-- 8. TAP / CLICK ANYWHERE IN PEN TO PLACE EGG TOOL
--------------------------------------------------------------------------------
local placeEggRemote = ReplicatedStorage:FindFirstChild("PlaceEggAtLocation") :: RemoteEvent?
if not placeEggRemote then
	placeEggRemote = Instance.new("RemoteEvent")
	placeEggRemote.Name = "PlaceEggAtLocation"
	placeEggRemote.Parent = ReplicatedStorage
end

local function handleTapToPlace(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local char = player.Character
		local tool = char and char:FindFirstChildWhichIsA("Tool")
		if tool and tool:GetAttribute("IsAnimeEgg") == true then
			local mouse = player:GetMouse()
			if mouse and mouse.Hit then
				local remote = ReplicatedStorage:FindFirstChild("PlaceEggAtLocation") :: RemoteEvent?
				if remote then
					remote:FireServer(mouse.Hit.Position)
				end
			end
		end
	end
end

UserInputService.InputBegan:Connect(handleTapToPlace)

--------------------------------------------------------------------------------
-- 9. DUMBBELL UPGRADE SIGN BUTTON (CLICK BUTTON DIRECTLY ON SIGN)
--------------------------------------------------------------------------------
local upgradeDumbbellRemote = ReplicatedStorage:FindFirstChild("UpgradeDumbbellAction") :: RemoteEvent?
if not upgradeDumbbellRemote then
	upgradeDumbbellRemote = Instance.new("RemoteEvent")
	upgradeDumbbellRemote.Name = "UpgradeDumbbellAction"
	upgradeDumbbellRemote.Parent = ReplicatedStorage
end

local function hookUpgradeButton(desc: Instance)
	if desc:IsA("TextButton") and desc.Name == "UpgradeButton" then
		desc.Activated:Connect(function()
			upgradeDumbbellRemote:FireServer()
		end)
	end
end

for _, desc in ipairs(Workspace:GetDescendants()) do
	hookUpgradeButton(desc)
end
Workspace.DescendantAdded:Connect(hookUpgradeButton)

print("[StatsHUD] Compact HUD, Dumbbell visibility isolation, Drop Button, Tap-to-place & Jump-to-leave active.")


