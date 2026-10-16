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
-- The owner sees their own pad/dumbbell. Ordinary pen signs are NOT hidden.
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

local penTrainingCache: { [Model]: { folder: Instance?, items: { Instance } } } = {}

local function applyItemVisibility(desc: Instance, shouldBeVisible: boolean, isOwner: boolean)
	if desc:IsA("BasePart") then
		desc.Transparency = shouldBeVisible and 0 or 1
		local isPad = desc.Name == "TrainingPad"
		desc.CanCollide = isPad and shouldBeVisible and isOwner
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
		desc.Enabled = shouldBeVisible and isOwner
	elseif desc:IsA("ClickDetector") then
		desc.MaxActivationDistance = (shouldBeVisible and isOwner) and 14 or 0
	elseif desc:IsA("Beam") or desc:IsA("ParticleEmitter") or desc:IsA("Trail") then
		desc.Enabled = shouldBeVisible
	end
end

local function updatePenTrainingVisibility(pen: Model)
	local cache = penTrainingCache[pen]
	if not cache then return end

	local myUserId = player.UserId
	local ownerId = pen:GetAttribute("OwnerUserId") or 0
	local ownerName = pen:GetAttribute("OwnerName") or ""
	local isOwner = (myUserId ~= 0 and ownerId ~= 0 and ownerId == myUserId) or (ownerName ~= "" and ownerName == player.Name)
	-- Strict: pen up sign, dumbbell sign, dumbbell, and training pad appear ONLY to owner!
	local shouldBeVisible = isOwner

	for _, item in ipairs(cache.items) do
		if item and item.Parent then
			applyItemVisibility(item, shouldBeVisible, isOwner)
		end
	end
end

local function rebuildPenTrainingCache(pen: Model)
	local trainingArea = pen:FindFirstChild("StrengthTrainingArea")
	local items: { Instance } = {}

	if trainingArea then
		table.insert(items, trainingArea)
		for _, desc in ipairs(trainingArea:GetDescendants()) do
			table.insert(items, desc)
		end
	end

	-- Strict Owner Isolation: Pen upgrade signs, training upgrade signs, dumbbells, and pads appear ONLY to the owner
	for _, child in ipairs(pen:GetChildren()) do
		local nameL = child.Name:lower()
		if child.Name == "TrainingPad" or child.Name == "TrainingDumbbell" or child.Name == "TrainingUpgradeSign"
			or child.Name == "PenUpgradeSign" or nameL:find("dumbel%s*up") or nameL:find("pen%s*up") then
			if not table.find(items, child) then
				table.insert(items, child)
				for _, d in ipairs(child:GetDescendants()) do
					table.insert(items, d)
				end
			end
		end
	end

	penTrainingCache[pen] = {
		folder = trainingArea,
		items = items,
	}

	updatePenTrainingVisibility(pen)
end

local function hookPen(pen: Model)
	rebuildPenTrainingCache(pen)

	pen:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		updatePenTrainingVisibility(pen)
	end)
	pen:GetAttributeChangedSignal("OwnerName"):Connect(function()
		updatePenTrainingVisibility(pen)
	end)
	pen:GetAttributeChangedSignal("IsTraining"):Connect(function()
		updatePenTrainingVisibility(pen)
	end)
	pen:GetAttributeChangedSignal("DumbbellTier"):Connect(function()
		task.defer(function()
			rebuildPenTrainingCache(pen)
		end)
	end)
	pen:GetAttributeChangedSignal("PenUpgradeLevel"):Connect(function()
		task.defer(function()
			rebuildPenTrainingCache(pen)
		end)
	end)

	local function hookTrainingArea(ta: Instance)
		ta.DescendantAdded:Connect(function()
			task.defer(function()
				rebuildPenTrainingCache(pen)
			end)
		end)
		ta.DescendantRemoving:Connect(function()
			task.defer(function()
				rebuildPenTrainingCache(pen)
			end)
		end)
	end

	local currentArea = pen:FindFirstChild("StrengthTrainingArea")
	if currentArea then
		hookTrainingArea(currentArea)
	end

	pen.ChildAdded:Connect(function(child)
		local nameL = child.Name:lower()
		if child.Name == "StrengthTrainingArea" or child.Name == "TrainingPad"
			or child.Name == "TrainingDumbbell" or child.Name == "TrainingUpgradeSign"
			or child.Name == "PenUpgradeSign" or nameL:find("dumbel%s*up") or nameL:find("pen%s*up") then
			if child.Name == "StrengthTrainingArea" then
				hookTrainingArea(child)
			end
			task.defer(function()
				rebuildPenTrainingCache(pen)
			end)
		end
	end)
end

local function hideLooseTemplate(model: Instance)
	if model:IsA("Model") then
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Transparency = 1
				desc.CanCollide = false
			elseif desc:IsA("SurfaceGui") then
				desc.Enabled = false
			elseif desc:IsA("GuiObject") then
				desc.Visible = false
			end
		end
	end
end

local function hideWorkspacePrototypes()
	for _, name in ipairs({
		"dumbel1", "dumbel2", "dumbel3", "Dumbel1", "Dumbel2", "Dumbel3",
		"dumbel up1", "dumbel up2", "dumbel up3", "dumbel up4", "dumbel up5",
		"pen up1", "pen up2", "pen up3", "pen up4", "pen up5",
	}) do
		local proto = Workspace:FindFirstChild(name)
		if proto then
			hideLooseTemplate(proto)
		end
	end
end

task.spawn(function()
	task.wait(0.2)
	hideWorkspacePrototypes()

	Workspace.ChildAdded:Connect(function(child)
		local nameL = child.Name:lower()
		if nameL == "dumbel1" or nameL == "dumbel2" or nameL == "dumbel3" or nameL:find("dumbel up") or nameL:find("pen up") then
			hideLooseTemplate(child)
		elseif child:IsA("Model") and nameL:match("pen%s*%d") then
			hookPen(child)
		end
	end)

	for _, pen in ipairs(getAllPens()) do
		hookPen(pen)
	end

	task.spawn(function()
		local spawnFolder = Workspace:WaitForChild("Spawn", 8)
		local pensFolder = spawnFolder and spawnFolder:WaitForChild("Pens", 8)
		if pensFolder then
			for _, child in ipairs(pensFolder:GetChildren()) do
				if child:IsA("Model") then
					hookPen(child)
				end
			end
			pensFolder.ChildAdded:Connect(function(child)
				if child:IsA("Model") then
					hookPen(child)
				end
			end)
		end
	end)
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

local function hookEggToolClient(item: Instance)
	if item:IsA("Tool") and item:GetAttribute("IsAnimeEgg") == true then
		if not item:GetAttribute("ClientActivatedHooked") then
			item:SetAttribute("ClientActivatedHooked", true)
			item.Activated:Connect(function()
				local mouse = player:GetMouse()
				if mouse and mouse.Hit then
					placeEggRemote:FireServer(mouse.Hit.Position)
				end
			end)
		end
	end
end

local function hookBackpackClient(backpack: Instance)
	for _, child in ipairs(backpack:GetChildren()) do
		hookEggToolClient(child)
	end
	backpack.ChildAdded:Connect(hookEggToolClient)
end

local function hookCharacterClient(char: Model)
	for _, child in ipairs(char:GetChildren()) do
		hookEggToolClient(child)
	end
	char.ChildAdded:Connect(hookEggToolClient)
end

if player.Character then
	hookCharacterClient(player.Character)
end
player.CharacterAdded:Connect(hookCharacterClient)

local bp = player:FindFirstChild("Backpack")
if bp then
	hookBackpackClient(bp)
end
player.ChildAdded:Connect(function(c)
	if c.Name == "Backpack" then
		hookBackpackClient(c)
	end
end)

local function isGuiAtScreenPoint(screenX: number, screenY: number): boolean
	local pGui = player:FindFirstChild("PlayerGui")
	if not pGui then return false end
	local guis = pGui:GetGuiObjectsAtPosition(screenX, screenY)
	for _, g in ipairs(guis) do
		if g:IsA("GuiButton") or (g:IsA("Frame") and g.Active) or (g:IsA("TextBox") and g.Visible) then
			return true
		end
	end
	return false
end

local function firePlaceEggAtScreenPoint(screenX: number, screenY: number)
	if isGuiAtScreenPoint(screenX, screenY) then
		return
	end

	local hitPos: Vector3? = nil
	local mouse = player:GetMouse()
	if mouse and mouse.Hit then
		hitPos = mouse.Hit.Position
	elseif Workspace.CurrentCamera then
		local unitRay = Workspace.CurrentCamera:ScreenPointToRay(screenX, screenY)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		if player.Character then
			rayParams.FilterDescendantsInstances = { player.Character }
		end
		local rayHit = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, rayParams)
		if rayHit then
			hitPos = rayHit.Position
		end
	end

	if hitPos then
		placeEggRemote:FireServer(hitPos)
	end
end

-- 1. Direct Mouse Button 1 Down (Reliable desktop world click without gameProcessed suppression)
local clientMouse = player:GetMouse()
clientMouse.Button1Down:Connect(function()
	local mPos = UserInputService:GetMouseLocation()
	if not isGuiAtScreenPoint(mPos.X, mPos.Y) then
		if clientMouse.Hit then
			placeEggRemote:FireServer(clientMouse.Hit.Position)
		end
	end
end)

-- 2. Touch Tap (Reliable mobile / tablet tap)
UserInputService.TouchTap:Connect(function(touchPositions, _gameProcessed)
	local pos = touchPositions[1]
	if pos then
		firePlaceEggAtScreenPoint(pos.X, pos.Y)
	end
end)

-- 3. Touch InputBegan fallback
UserInputService.InputBegan:Connect(function(input, _gameProcessed)
	if input.UserInputType == Enum.UserInputType.Touch and input.Position then
		firePlaceEggAtScreenPoint(input.Position.X, input.Position.Y)
	end
end)

--------------------------------------------------------------------------------
-- 9. DUMBBELL UPGRADE SIGN BUTTON (CLICK BUTTON DIRECTLY ON SIGN)
--------------------------------------------------------------------------------
local upgradeDumbbellRemote = ReplicatedStorage:FindFirstChild("UpgradeDumbbellAction") :: RemoteEvent?
if not upgradeDumbbellRemote then
	upgradeDumbbellRemote = Instance.new("RemoteEvent")
	upgradeDumbbellRemote.Name = "UpgradeDumbbellAction"
	upgradeDumbbellRemote.Parent = ReplicatedStorage
end

local upgradePenRemote = ReplicatedStorage:FindFirstChild("UpgradePenAction") :: RemoteEvent?
if not upgradePenRemote then
	upgradePenRemote = Instance.new("RemoteEvent")
	upgradePenRemote.Name = "UpgradePenAction"
	upgradePenRemote.Parent = ReplicatedStorage
end

local function hookUpgradeButton(desc: Instance)
	if desc:IsA("GuiButton") and not desc:GetAttribute("UpgradeHooked") then
		local isPen = false
		local isDumbbell = false

		if desc.Name == "PenUpgradeButton" then
			isPen = true
		elseif desc.Name == "UpgradeButton" then
			local model = desc:FindFirstAncestorOfClass("Model")
			if model and (model.Name:lower():find("dumbel") or model.Name == "TrainingUpgradeSign") then
				isDumbbell = true
			elseif model and (model.Name:lower():find("pen") or model.Name == "PenUpgradeSign") then
				isPen = true
			else
				isDumbbell = true
			end
		end

		local model = desc:FindFirstAncestorOfClass("Model")
		if model then
			local mName = model.Name:lower()
			if mName:find("pen up") or mName:find("penupgrade") then
				isPen = true
			elseif mName:find("dumbel") or mName:find("trainingupgradesign") then
				isDumbbell = true
			end
		end

		if desc.Parent then
			for _, sibling in ipairs(desc.Parent:GetChildren()) do
				if sibling:IsA("TextLabel") then
					local sText = sibling.Text:lower()
					if sText:find("upgrade pen") then
						isPen = true
						break
					elseif sText:find("upgrade dumbel") or sText:find("upgrade dumbbell") then
						isDumbbell = true
						break
					end
				end
			end
		end

		if isPen then
			desc:SetAttribute("UpgradeHooked", true)
			desc.Activated:Connect(function()
				upgradePenRemote:FireServer()
			end)
		elseif isDumbbell then
			desc:SetAttribute("UpgradeHooked", true)
			desc.Activated:Connect(function()
				upgradeDumbbellRemote:FireServer()
			end)
		end
	end
end

for _, pen in ipairs(getAllPens()) do
	for _, desc in ipairs(pen:GetDescendants()) do
		hookUpgradeButton(desc)
	end
end
Workspace.DescendantAdded:Connect(hookUpgradeButton)

print("[StatsHUD] Compact HUD, Dumbbell visibility isolation, Drop Button, Tap-to-place & Jump-to-leave active.")


