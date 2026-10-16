--!strict
-- ==============================================================================
-- Steal An Egg Style: Trail Shop & Speed Shop UI + Proximity Setup Script
-- Run this in Roblox Studio Command Bar (View -> Command Bar) to permanently
-- build the complete UI in StarterGui and the Interaction Controller in StarterPlayerScripts!
-- ==============================================================================

local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local TweenService = game:GetService("TweenService")

print("----------------------------------------------------------------------")
print("[Shops Setup] Creating Trail Shop & Speed Shop UI + Proximity System...")
print("----------------------------------------------------------------------")

--------------------------------------------------------------------------------
-- 1. CREATE OR REUSE SCREEN GUI (StarterGui.ShopsGui)
--------------------------------------------------------------------------------
local shopsGui = StarterGui:FindFirstChild("ShopsGui") :: ScreenGui?
if shopsGui then
	shopsGui:Destroy()
end

shopsGui = Instance.new("ScreenGui")
shopsGui.Name = "ShopsGui"
shopsGui.ResetOnSpawn = false
shopsGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
shopsGui.DisplayOrder = 10
shopsGui.Parent = StarterGui

local function createCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function createStroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function createGradient(parent: Instance, c1: Color3, c2: Color3, rotation: number?)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(c1, c2)
	grad.Rotation = rotation or 90
	grad.Parent = parent
	return grad
end

--------------------------------------------------------------------------------
-- 2. HELPER TO BUILD A MODERN SIMULATOR SHOP FRAME
--------------------------------------------------------------------------------
local function buildShopBase(name: string, titleText: string, iconText: string, accentColor: Color3)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.Size = UDim2.new(0.9, 0, 0.85, 0)
	frame.BackgroundColor3 = Color3.fromRGB(20, 24, 38)
	frame.Visible = false
	frame.ClipsDescendants = false
	frame.Parent = shopsGui

	-- Responsive sizing constraint for desktop & mobile
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(340, 380)
	sizeConstraint.MaxSize = Vector2.new(580, 520)
	sizeConstraint.Parent = frame

	createCorner(frame, 16)
	createStroke(frame, accentColor, 3)

	local bgGradient = createGradient(frame, Color3.fromRGB(26, 32, 50), Color3.fromRGB(15, 18, 30), 45)

	-- Header Frame
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 58)
	header.BackgroundColor3 = Color3.fromRGB(28, 35, 56)
	header.BorderSizePixel = 0
	header.Parent = frame
	createCorner(header, 16)

	-- Header bottom cover (to keep square bottom on header)
	local headerBottomPatch = Instance.new("Frame")
	headerBottomPatch.Size = UDim2.new(1, 0, 0, 16)
	headerBottomPatch.Position = UDim2.new(0, 0, 1, -16)
	headerBottomPatch.BackgroundColor3 = Color3.fromRGB(28, 35, 56)
	headerBottomPatch.BorderSizePixel = 0
	headerBottomPatch.Parent = header

	local headerBorder = Instance.new("Frame")
	headerBorder.Name = "HeaderBorder"
	headerBorder.Size = UDim2.new(1, 0, 0, 2)
	headerBorder.Position = UDim2.new(0, 0, 1, 0)
	headerBorder.BackgroundColor3 = accentColor
	headerBorder.BorderSizePixel = 0
	headerBorder.Parent = header

	-- Icon Badge
	local iconBadge = Instance.new("Frame")
	iconBadge.Name = "IconBadge"
	iconBadge.Size = UDim2.new(0, 40, 0, 40)
	iconBadge.Position = UDim2.new(0, 12, 0.5, -20)
	iconBadge.BackgroundColor3 = accentColor
	iconBadge.Parent = header
	createCorner(iconBadge, 10)

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(1, 0, 1, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = iconText
	iconLabel.TextSize = 22
	iconLabel.Font = Enum.Font.FredokaOne
	iconLabel.TextColor3 = Color3.fromRGB(20, 20, 20)
	iconLabel.Parent = iconBadge

	-- Title Label
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.new(0, 62, 0, 0)
	title.Size = UDim2.new(1, -120, 1, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.Text = titleText
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 24
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header
	createStroke(title, Color3.fromRGB(10, 10, 10), 2)

	-- Close Button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 38, 0, 38)
	closeBtn.Position = UDim2.new(1, -48, 0.5, -19)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	closeBtn.Font = Enum.Font.FredokaOne
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextSize = 20
	closeBtn.AutoButtonColor = true
	closeBtn.Parent = header
	createCorner(closeBtn, 10)
	createStroke(closeBtn, Color3.fromRGB(255, 120, 120), 1.5)

	-- Subtitle / Notice Bar
	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -24, 0, 26)
	subtitle.Position = UDim2.new(0, 12, 0, 64)
	subtitle.BackgroundColor3 = Color3.fromRGB(15, 20, 32)
	subtitle.BackgroundTransparency = 0.4
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextColor3 = Color3.fromRGB(200, 215, 240)
	subtitle.TextSize = 13
	subtitle.Parent = frame
	createCorner(subtitle, 6)

	-- Scrolling Content Area
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ScrollContent"
	scroll.Size = UDim2.new(1, -24, 1, -104)
	scroll.Position = UDim2.new(0, 12, 0, 94)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = accentColor
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = scroll

	return frame, scroll, closeBtn, subtitle
end

--------------------------------------------------------------------------------
-- 3. BUILD TRAIL SHOP UI
--------------------------------------------------------------------------------
local trailFrame, trailScroll, trailCloseBtn, trailSubtitle = buildShopBase(
	"TrailShopFrame",
	"TRAIL SHOP",
	"✨",
	Color3.fromRGB(255, 225, 45) -- Steal An Egg vibrant yellow accent
)
trailSubtitle.Text = "⚡ Equip custom visual speed trails to flex on opponents!"

local trailGrid = Instance.new("UIGridLayout")
trailGrid.CellPadding = UDim2.new(0, 12, 0, 12)
trailGrid.CellSize = UDim2.new(0.5, -6, 0, 150)
trailGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
trailGrid.SortOrder = Enum.SortOrder.LayoutOrder
trailGrid.Parent = trailScroll

local TRAIL_DATA = {
	{ id = "default_white", name = "Basic White Trail",   boost = "Default Starter", price = "FREE",       equipped = true,  color1 = Color3.fromRGB(240, 240, 240), color2 = Color3.fromRGB(180, 180, 180) },
	{ id = "electric_gold", name = "Electric Gold Trail", boost = "+1.2x Speed FX",  price = "1,000 Coins", equipped = false, color1 = Color3.fromRGB(255, 220, 40),  color2 = Color3.fromRGB(255, 140, 0) },
	{ id = "neon_cyan",     name = "Cyan Lightning",      boost = "+1.5x Speed FX",  price = "5,000 Coins", equipped = false, color1 = Color3.fromRGB(0, 240, 255),   color2 = Color3.fromRGB(0, 120, 255) },
	{ id = "anime_fire",    name = "Anime Flame Trail",   boost = "+2.0x Speed FX",  price = "15,000 Coins",equipped = false, color1 = Color3.fromRGB(255, 75, 40),   color2 = Color3.fromRGB(255, 200, 0) },
	{ id = "rainbow_aura",  name = "Rainbow Sparkle",     boost = "+3.0x Speed FX",  price = "50,000 Coins",equipped = false, color1 = Color3.fromRGB(255, 100, 220), color2 = Color3.fromRGB(120, 255, 100) },
	{ id = "void_godspeed", name = "Void Godspeed Trail", boost = "+5.0x Speed FX",  price = "200,000 Coins",equipped = false, color1 = Color3.fromRGB(170, 0, 255),  color2 = Color3.fromRGB(50, 0, 120) },
}

for i, item in ipairs(TRAIL_DATA) do
	local card = Instance.new("Frame")
	card.Name = "TrailCard_" .. item.id
	card.LayoutOrder = i
	card.BackgroundColor3 = Color3.fromRGB(28, 34, 52)
	card.Parent = trailScroll
	createCorner(card, 12)
	createStroke(card, item.equipped and Color3.fromRGB(80, 230, 120) or Color3.fromRGB(45, 55, 80), 1.5)

	-- Trail Color Preview Box
	local preview = Instance.new("Frame")
	preview.Name = "Preview"
	preview.Size = UDim2.new(1, -16, 0, 42)
	preview.Position = UDim2.new(0, 8, 0, 8)
	preview.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	preview.Parent = card
	createCorner(preview, 8)
	createStroke(preview, Color3.fromRGB(255, 255, 255), 1, 0.7)

	local ribbon = Instance.new("Frame")
	ribbon.Size = UDim2.new(0.85, 0, 0, 12)
	ribbon.AnchorPoint = Vector2.new(0.5, 0.5)
	ribbon.Position = UDim2.new(0.5, 0, 0.5, 0)
	ribbon.BackgroundColor3 = item.color1
	ribbon.BorderSizePixel = 0
	ribbon.Parent = preview
	createCorner(ribbon, 6)
	createGradient(ribbon, item.color1, item.color2, 0)

	-- Trail Title
	local tTitle = Instance.new("TextLabel")
	tTitle.Name = "ItemName"
	tTitle.Size = UDim2.new(1, -16, 0, 18)
	tTitle.Position = UDim2.new(0, 8, 0, 54)
	tTitle.BackgroundTransparency = 1
	tTitle.Font = Enum.Font.FredokaOne
	tTitle.Text = item.name
	tTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	tTitle.TextSize = 14
	tTitle.TextXAlignment = Enum.TextXAlignment.Left
	tTitle.Parent = card

	-- Boost Subtitle
	local tBoost = Instance.new("TextLabel")
	tBoost.Name = "ItemBoost"
	tBoost.Size = UDim2.new(1, -16, 0, 14)
	tBoost.Position = UDim2.new(0, 8, 0, 74)
	tBoost.BackgroundTransparency = 1
	tBoost.Font = Enum.Font.GothamMedium
	tBoost.Text = item.boost
	tBoost.TextColor3 = Color3.fromRGB(255, 220, 60)
	tBoost.TextSize = 12
	tBoost.TextXAlignment = Enum.TextXAlignment.Left
	tBoost.Parent = card

	-- Price Label / Buy Button
	local buyBtn = Instance.new("TextButton")
	buyBtn.Name = "ActionBtn"
	buyBtn.Size = UDim2.new(1, -16, 0, 36)
	buyBtn.Position = UDim2.new(0, 8, 1, -44)
	buyBtn.AutoButtonColor = true
	buyBtn.Font = Enum.Font.FredokaOne
	buyBtn.TextSize = 14
	buyBtn.Parent = card
	createCorner(buyBtn, 8)

	if item.equipped then
		buyBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
		buyBtn.Text = "EQUIPPED"
		buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		createStroke(buyBtn, Color3.fromRGB(100, 240, 140), 1.5)
	else
		buyBtn.BackgroundColor3 = Color3.fromRGB(240, 180, 25)
		buyBtn.Text = item.price
		buyBtn.TextColor3 = Color3.fromRGB(20, 20, 20)
		createStroke(buyBtn, Color3.fromRGB(255, 230, 80), 1.5)
	end
end

--------------------------------------------------------------------------------
-- 4. BUILD SPEED SHOP UI
--------------------------------------------------------------------------------
local speedFrame, speedScroll, speedCloseBtn, speedSubtitle = buildShopBase(
	"SpeedShopFrame",
	"SPEED SHOP",
	"⚡",
	Color3.fromRGB(255, 210, 35) -- Golden energy yellow
)
speedSubtitle.Text = "👟 Upgrade your running speed to easily outrun opponents and guards!"

-- Current Speed Display Header
local currentSpeedBar = Instance.new("Frame")
currentSpeedBar.Name = "CurrentSpeedBar"
currentSpeedBar.Size = UDim2.new(1, 0, 0, 38)
currentSpeedBar.BackgroundColor3 = Color3.fromRGB(36, 44, 70)
currentSpeedBar.Parent = speedScroll
createCorner(currentSpeedBar, 10)
createStroke(currentSpeedBar, Color3.fromRGB(255, 220, 50), 1.5)

local curSpeedLabel = Instance.new("TextLabel")
curSpeedLabel.Name = "CurrentSpeedText"
curSpeedLabel.Size = UDim2.new(1, -16, 1, 0)
curSpeedLabel.Position = UDim2.new(0, 12, 0, 0)
curSpeedLabel.BackgroundTransparency = 1
curSpeedLabel.Font = Enum.Font.FredokaOne
curSpeedLabel.Text = "CURRENT SPEED: 50 WalkSpeed"
curSpeedLabel.TextColor3 = Color3.fromRGB(255, 235, 80)
curSpeedLabel.TextSize = 16
curSpeedLabel.TextXAlignment = Enum.TextXAlignment.Left
curSpeedLabel.Parent = currentSpeedBar

local speedList = Instance.new("UIListLayout")
speedList.Padding = UDim.new(0, 10)
speedList.HorizontalAlignment = Enum.HorizontalAlignment.Center
speedList.SortOrder = Enum.SortOrder.LayoutOrder
speedList.Parent = speedScroll

local SPEED_TIERS = {
	{ tier = 1, name = "Tier I: Starter Pace",    speed = 50,  price = "DEFAULT",       current = true },
	{ tier = 2, name = "Tier II: Swift Runner",   speed = 75,  price = "500 Coins",     current = false },
	{ tier = 3, name = "Tier III: Supersonic",    speed = 100, price = "2,500 Coins",   current = false },
	{ tier = 4, name = "Tier IV: Lightning Sprint",speed = 150, price = "10,000 Coins",  current = false },
	{ tier = 5, name = "Tier V: Anime Flash",     speed = 225, price = "50,000 Coins",  current = false },
	{ tier = 6, name = "Tier VI: Divine Godspeed",speed = 350, price = "250,000 Coins", current = false },
}

for i, tier in ipairs(SPEED_TIERS) do
	local row = Instance.new("Frame")
	row.Name = "SpeedTier_" .. tostring(tier.tier)
	row.Size = UDim2.new(1, 0, 0, 62)
	row.LayoutOrder = i + 1
	row.BackgroundColor3 = Color3.fromRGB(28, 34, 52)
	row.Parent = speedScroll
	createCorner(row, 10)
	createStroke(row, tier.current and Color3.fromRGB(80, 230, 120) or Color3.fromRGB(45, 55, 80), 1.5)

	-- Speed Badge
	local sBadge = Instance.new("Frame")
	sBadge.Name = "Badge"
	sBadge.Size = UDim2.new(0, 48, 0, 44)
	sBadge.Position = UDim2.new(0, 10, 0.5, -22)
	sBadge.BackgroundColor3 = Color3.fromRGB(20, 24, 38)
	sBadge.Parent = row
	createCorner(sBadge, 8)
	createStroke(sBadge, Color3.fromRGB(255, 215, 40), 1)

	local sVal = Instance.new("TextLabel")
	sVal.Size = UDim2.new(1, 0, 1, 0)
	sVal.BackgroundTransparency = 1
	sVal.Font = Enum.Font.FredokaOne
	sVal.Text = tostring(tier.speed)
	sVal.TextColor3 = Color3.fromRGB(255, 220, 50)
	sVal.TextSize = 16
	sVal.Parent = sBadge

	-- Name & Info
	local sName = Instance.new("TextLabel")
	sName.Name = "TierName"
	sName.Size = UDim2.new(1, -210, 0, 22)
	sName.Position = UDim2.new(0, 68, 0, 10)
	sName.BackgroundTransparency = 1
	sName.Font = Enum.Font.FredokaOne
	sName.Text = tier.name
	sName.TextColor3 = Color3.fromRGB(255, 255, 255)
	sName.TextSize = 15
	sName.TextXAlignment = Enum.TextXAlignment.Left
	sName.Parent = row

	local sStat = Instance.new("TextLabel")
	sStat.Name = "StatText"
	sStat.Size = UDim2.new(1, -210, 0, 18)
	sStat.Position = UDim2.new(0, 68, 0, 32)
	sStat.BackgroundTransparency = 1
	sStat.Font = Enum.Font.GothamMedium
	sStat.Text = "+" .. tostring(tier.speed) .. " WalkSpeed Capability"
	sStat.TextColor3 = Color3.fromRGB(180, 195, 220)
	sStat.TextSize = 12
	sStat.TextXAlignment = Enum.TextXAlignment.Left
	sStat.Parent = row

	-- Upgrade / Active Button
	local upBtn = Instance.new("TextButton")
	upBtn.Name = "ActionBtn"
	upBtn.Size = UDim2.new(0, 120, 0, 38)
	upBtn.Position = UDim2.new(1, -130, 0.5, -19)
	upBtn.AutoButtonColor = true
	upBtn.Font = Enum.Font.FredokaOne
	upBtn.TextSize = 14
	upBtn.Parent = row
	createCorner(upBtn, 8)

	if tier.current then
		upBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
		upBtn.Text = "ACTIVE"
		upBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		createStroke(upBtn, Color3.fromRGB(100, 240, 140), 1.5)
	else
		upBtn.BackgroundColor3 = Color3.fromRGB(240, 180, 25)
		upBtn.Text = tier.price
		upBtn.TextColor3 = Color3.fromRGB(20, 20, 20)
		createStroke(upBtn, Color3.fromRGB(255, 230, 80), 1.5)
	end
end

print("[+] StarterGui.ShopsGui created successfully with TrailShopFrame and SpeedShopFrame")

--------------------------------------------------------------------------------
-- 5. CREATE CLIENT INTERACTION CONTROLLER (StarterPlayerScripts)
--------------------------------------------------------------------------------
local clientController = StarterPlayerScripts:FindFirstChild("ShopInteractionController") :: LocalScript?
if clientController then
	clientController:Destroy()
end

clientController = Instance.new("LocalScript")
clientController.Name = "ShopInteractionController"
clientController.Parent = StarterPlayerScripts

clientController.Source = [=[--!strict
-- ShopInteractionController.client.luau
-- Independent Proximity Detection, Steal An Egg Yellow Glow Highlight, and UI Controller

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local shopsGui = playerGui:WaitForChild("ShopsGui") :: ScreenGui

local trailFrame = shopsGui:WaitForChild("TrailShopFrame") :: Frame
local speedFrame = shopsGui:WaitForChild("SpeedShopFrame") :: Frame

local trailCloseBtn = trailFrame:WaitForChild("Header"):WaitForChild("CloseButton") :: TextButton
local speedCloseBtn = speedFrame:WaitForChild("Header"):WaitForChild("CloseButton") :: TextButton

local trailScroll = trailFrame:WaitForChild("ScrollContent") :: ScrollingFrame
local speedScroll = speedFrame:WaitForChild("ScrollContent") :: ScrollingFrame

local currentSpeedLabel = speedScroll:WaitForChild("CurrentSpeedBar"):WaitForChild("CurrentSpeedText") :: TextLabel

--------------------------------------------------------------------------------
-- CONFIGURATION: PROXIMITY & HIGHLIGHT
--------------------------------------------------------------------------------
local ENTER_DISTANCE = 14 -- Studs distance to open shop & trigger highlight
local EXIT_DISTANCE  = 18 -- Studs distance to close shop & remove highlight (hysteresis)

local HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 235, 40) -- Steal An Egg bright yellow
local HIGHLIGHT_FILL_COLOR    = Color3.fromRGB(255, 240, 100) -- Tasteful subtle yellow glow
local HIGHLIGHT_OUTLINE_TRANS = 0.0
local HIGHLIGHT_FILL_TRANS    = 0.85 -- Kept high so shop model remains fully visible

--------------------------------------------------------------------------------
-- MODEL RESOLUTION (Safe & Map-Preserving)
--------------------------------------------------------------------------------
local function findShopModel(names: {string}): Model?
	for _, n in ipairs(names) do
		-- Look in Workspace.Spawn first, then anywhere in Workspace
		local spawnFolder = Workspace:FindFirstChild("Spawn")
		if spawnFolder then
			local found = spawnFolder:FindFirstChild(n)
			if found and found:IsA("Model") then
				return found
			end
		end
		local foundAnywhere = Workspace:FindFirstChild(n, true)
		if foundAnywhere and foundAnywhere:IsA("Model") then
			return foundAnywhere
		end
	end
	return nil
end

local trailModel = findShopModel({"Trails", "Trail"})
local speedModel = findShopModel({"Speed"})

local function getModelInteractionPoint(model: Model?): Vector3?
	if not model then return nil end
	if model.PrimaryPart then
		return model.PrimaryPart.Position
	end
	local cf, size = model:GetBoundingBox()
	return cf.Position
end

--------------------------------------------------------------------------------
-- CLIENT HIGHLIGHT SINGLETON
--------------------------------------------------------------------------------
local activeHighlight: Highlight? = nil
local currentHighlightedModel: Model? = nil

local function setHighlight(targetModel: Model?)
	if targetModel == currentHighlightedModel then
		return
	end

	if activeHighlight then
		activeHighlight:Destroy()
		activeHighlight = nil
		currentHighlightedModel = nil
	end

	if targetModel then
		local hl = Instance.new("Highlight")
		hl.Name = "ShopGlowHighlight"
		hl.Adornee = targetModel
		hl.OutlineColor = HIGHLIGHT_OUTLINE_COLOR
		hl.OutlineTransparency = HIGHLIGHT_OUTLINE_TRANS
		hl.FillColor = HIGHLIGHT_FILL_COLOR
		hl.FillTransparency = HIGHLIGHT_FILL_TRANS
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = targetModel
		activeHighlight = hl
		currentHighlightedModel = targetModel
	end
end

--------------------------------------------------------------------------------
-- UI SMOOTH TRANSITIONS
--------------------------------------------------------------------------------
local activeOpenShop: string? = nil -- "trail" | "speed" | nil
local suppressedShop: string? = nil -- suppressed after clicking close button until exiting

local BASE_SIZE = UDim2.new(0.9, 0, 0.85, 0)
local POP_SIZE  = UDim2.new(0.82, 0, 0.78, 0)

local function animateOpen(frame: Frame)
	frame.Visible = true
	frame.Size = POP_SIZE
	local tween = TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = BASE_SIZE
	})
	tween:Play()
end

local function animateClose(frame: Frame, shopTag: string)
	local tween = TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = POP_SIZE
	})
	tween:Play()
	task.delay(0.15, function()
		if activeOpenShop ~= shopTag then
			frame.Visible = false
			frame.Size = BASE_SIZE
		end
	end)
end

-- Close Button Listeners
trailCloseBtn.MouseButton1Click:Connect(function()
	suppressedShop = "trail"
	activeOpenShop = nil
	animateClose(trailFrame, "trail")
	setHighlight(nil)
end)

speedCloseBtn.MouseButton1Click:Connect(function()
	suppressedShop = "speed"
	activeOpenShop = nil
	animateClose(speedFrame, "speed")
	setHighlight(nil)
end)

-- Update active WalkSpeed indicator
local function updateSpeedDisplay()
	local char = localPlayer.Character
	if char then
		local humanoid = char:FindFirstChildWhichIsA("Humanoid")
		if humanoid then
			currentSpeedLabel.Text = "CURRENT SPEED: " .. tostring(math.round(humanoid.WalkSpeed)) .. " WalkSpeed"
		end
	end
end

--------------------------------------------------------------------------------
-- PROXIMITY TICK LOOP (Clean & Zero-Flicker)
--------------------------------------------------------------------------------
local lastCheck = 0
RunService.Heartbeat:Connect(function(dt)
	lastCheck += dt
	if lastCheck < 0.08 then return end -- Check ~12 times/sec
	lastCheck = 0

	local char = localPlayer.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	local playerPos = hrp.Position

	-- Resolve centers dynamically
	local trailPos = getModelInteractionPoint(trailModel)
	local speedPos = getModelInteractionPoint(speedModel)

	local trailDist = trailPos and (playerPos - trailPos).Magnitude or math.huge
	local speedDist = speedPos and (playerPos - speedPos).Magnitude or math.huge

	-- Reset suppression when player walks beyond EXIT_DISTANCE
	if suppressedShop == "trail" and trailDist > EXIT_DISTANCE then
		suppressedShop = nil
	elseif suppressedShop == "speed" and speedDist > EXIT_DISTANCE then
		suppressedShop = nil
	end

	-- Determine target shop based on proximity & hysteresis
	local targetShop: string? = nil

	if activeOpenShop == "trail" then
		if trailDist <= EXIT_DISTANCE then
			targetShop = "trail"
		end
	elseif activeOpenShop == "speed" then
		if speedDist <= EXIT_DISTANCE then
			targetShop = "speed"
		end
	end

	if not targetShop then
		-- Check entry distance
		if trailDist <= ENTER_DISTANCE and speedDist <= ENTER_DISTANCE then
			-- Closer one wins
			targetShop = (trailDist <= speedDist) and "trail" or "speed"
		elseif trailDist <= ENTER_DISTANCE then
			targetShop = "trail"
		elseif speedDist <= ENTER_DISTANCE then
			targetShop = "speed"
		end
	end

	-- Respect suppression from close button
	if targetShop == suppressedShop then
		targetShop = nil
	end

	-- Apply state transitions cleanly
	if targetShop == "trail" then
		if activeOpenShop ~= "trail" then
			if activeOpenShop == "speed" then
				animateClose(speedFrame, "speed")
			end
			activeOpenShop = "trail"
			animateOpen(trailFrame)
			setHighlight(trailModel)
		end
	elseif targetShop == "speed" then
		if activeOpenShop ~= "speed" then
			if activeOpenShop == "trail" then
				animateClose(trailFrame, "trail")
			end
			activeOpenShop = "speed"
			animateOpen(speedFrame)
			setHighlight(speedModel)
			updateSpeedDisplay()
		end
	else
		-- Outside interaction zones
		if activeOpenShop == "trail" then
			animateClose(trailFrame, "trail")
		elseif activeOpenShop == "speed" then
			animateClose(speedFrame, "speed")
		end
		activeOpenShop = nil
		setHighlight(nil)
	end
end)

--------------------------------------------------------------------------------
-- PLACEHOLDER USER INTERACTION FEEDBACK
--------------------------------------------------------------------------------
for _, card in ipairs(trailScroll:GetChildren()) do
	if card:IsA("Frame") and card:FindFirstChild("ActionBtn") then
		local btn = card.ActionBtn :: TextButton
		btn.MouseButton1Click:Connect(function()
			print("[Trail Shop Preview] Clicked: " .. card.Name .. " (" .. btn.Text .. "). Ready for inventory/purchase backend!")
		end)
	end
end

for _, row in ipairs(speedScroll:GetChildren()) do
	if row:IsA("Frame") and row:FindFirstChild("ActionBtn") then
		local btn = row.ActionBtn :: TextButton
		btn.MouseButton1Click:Connect(function()
			print("[Speed Shop Preview] Clicked: " .. row.Name .. " (" .. btn.Text .. "). Ready for currency/upgrade backend!")
		end)
	end
end

print("[ShopInteractionController] Initialized: Proximity, Yellow Glow, and Hysteresis active.")
]=]

print("[+] StarterPlayer.StarterPlayerScripts.ShopInteractionController created")
print("----------------------------------------------------------------------")
print("[Shops Setup] SUCCESS! Trail Shop & Speed Shop systems fully created.")
print("----------------------------------------------------------------------")
