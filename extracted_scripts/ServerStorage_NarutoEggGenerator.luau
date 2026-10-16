-- Path: ServerStorage.NarutoEggGenerator
-- Class: ModuleScript

--[[
	NarutoEggGenerator
	-------------------
	Builds the five blocky, studded Naruto rarity eggs under Workspace.NarutoEggs.

	HOW TO RERUN (never creates duplicates):
	Open the Command Bar (View > Command Bar) and run:
		require(game.ServerStorage.NarutoEggGenerator).Build()
	Build() always removes the existing Workspace.NarutoEggs folder before
	rebuilding, so it is safe to run repeatedly.
]]

local NarutoEggGenerator = {}

-- Rarity configurations. Same shape/studs for all eggs; only colors and the
-- Mythic glow change to communicate rarity.
local EGG_CONFIGS = {
	{
		Name = "CommonEgg", -- Rock Lee green
		ShellColor = Color3.fromRGB(88, 208, 90),
		StudColor = Color3.fromRGB(64, 168, 70),
		BandColor = Color3.fromRGB(255, 205, 60),
	},
	{
		Name = "RareEgg", -- Sasuke blue
		ShellColor = Color3.fromRGB(52, 96, 220),
		StudColor = Color3.fromRGB(38, 72, 175),
		BandColor = Color3.fromRGB(230, 235, 245),
	},
	{
		Name = "EpicEgg", -- Naruto purple
		ShellColor = Color3.fromRGB(152, 84, 220),
		StudColor = Color3.fromRGB(118, 60, 180),
		BandColor = Color3.fromRGB(255, 170, 60),
	},
	{
		Name = "LegendaryEgg", -- Jiraiya gold
		ShellColor = Color3.fromRGB(255, 190, 60),
		StudColor = Color3.fromRGB(225, 160, 45),
		BandColor = Color3.fromRGB(120, 85, 40),
	},
	{
		Name = "MythicEgg", -- Sage Mode red-orange with a subtle fiery glow
		ShellColor = Color3.fromRGB(255, 92, 32),
		StudColor = Color3.fromRGB(225, 70, 20),
		BandColor = Color3.fromRGB(255, 200, 80),
		GlowColor = Color3.fromRGB(255, 140, 40),
	},
}

-- Stepped blocky silhouette: stacked rectangular layers, wide at the bottom,
-- progressively narrower toward a stepped crown.
local LAYERS = {
	{ name = "LowerBody",  width = 8.0, height = 2.0, depth = 8.0 },
	{ name = "MainBody",   width = 7.0, height = 3.0, depth = 7.0 },
	{ name = "UpperBody",  width = 6.0, height = 2.5, depth = 6.0 },
	{ name = "CrownLower", width = 5.0, height = 2.0, depth = 5.0 },
	{ name = "CrownTop",   width = 3.4, height = 1.6, depth = 3.4 },
}

local BAND_LAYER = "MainBody"
local BAND_HEIGHT = 0.3   -- thin horizontal band around the middle
local BAND_OUTSET = 0.28  -- how far the band sticks out past the shell

local STUD_SIZE = 0.55    -- square footprint of each raised stud
local STUD_DEPTH = 0.14   -- how far each stud rises off the shell
local STUD_MARGIN = 0.5   -- inset from the layer edges so studs never float

local FACES = {
	{ name = "StudFront", axis = "Z", sign = 1 },
	{ name = "StudBack",  axis = "Z", sign = -1 },
	{ name = "StudRight", axis = "X", sign = 1 },
	{ name = "StudLeft",  axis = "X", sign = -1 },
}

local function makePart(name, size, cframe, color, canCollide)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Plastic
	part.Anchored = true
	part.CanCollide = canCollide
	part.CanQuery = canCollide
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Adds a regular grid of raised square studs to one layer's four flat side
-- faces. Column/row counts are derived from the layer's dimensions.
local function addStuds(model, layer, layerCenterY, config)
	local bandCenter = (layer.name == BAND_LAYER) and 0 or nil

	for _, face in ipairs(FACES) do
		local isZFace = face.axis == "Z"
		-- Horizontal extent along the face, and the axis the face is offset along.
		local horizontalExtent = isZFace and layer.width or layer.depth
		local offsetExtent = isZFace and layer.depth or layer.width
		local faceOffset = offsetExtent / 2 + STUD_DEPTH / 2

		-- Evenly spaced columns across the face width.
		local usableWidth = math.max(horizontalExtent - 2 * STUD_MARGIN, STUD_SIZE)
		local columns = math.max(1, math.floor(usableWidth / 1.1))
		local colStep = usableWidth / columns

		-- Evenly spaced rows across the face height.
		local usableHeight = math.max(layer.height - 1.0, 0.4)
		local rows = math.max(1, math.floor(usableHeight / 1.0))
		local rowStep = usableHeight / rows

		for row = 1, rows do
			local rowPos = -usableHeight / 2 + (row - 0.5) * rowStep

			-- Skip studs that the middle band would overlap.
			if bandCenter then
				if math.abs(rowPos) < BAND_HEIGHT / 2 + STUD_SIZE / 2 then
					continue
			end
			end

			for col = 1, columns do
				local colPos = -usableWidth / 2 + (col - 0.5) * colStep
				local x, z
				if isZFace then
					x = colPos
					z = faceOffset * face.sign
				else
					x = faceOffset * face.sign
					z = colPos
				end

				local size = isZFace
				and Vector3.new(STUD_SIZE, STUD_SIZE, STUD_DEPTH)
				or Vector3.new(STUD_DEPTH, STUD_SIZE, STUD_SIZE)

			local stud = makePart(face.name, size, CFrame.new(x, layerCenterY + rowPos, z), config.StudColor, false)
			stud.Parent = model
			end
		end
	end
end

-- Builds one egg Model with its bottom at the origin, centered on X/Z.
function NarutoEggGenerator.BuildEgg(config)
	local model = Instance.new("Model")
	model.Name = config.Name

	local bottomY = 0
	local mainBody = nil
	local bandLayer, bandCenterY = nil, nil

	for _, layer in ipairs(LAYERS) do
		local centerY = bottomY + layer.height / 2
		local body = makePart(
			layer.name,
			Vector3.new(layer.width, layer.height, layer.depth),
			CFrame.new(0, centerY, 0),
			config.ShellColor,
			true
		)
		body.Parent = model

		if layer.name == "MainBody" then
			mainBody = body
		end
		if layer.name == BAND_LAYER then
			bandLayer = layer
			bandCenterY = centerY
		end

		addStuds(model, layer, centerY, config)
		bottomY += layer.height
	end

	-- Thin decorative band wrapping the middle of the body.
	if bandLayer then
		local band = makePart(
			"Band",
			Vector3.new(bandLayer.width + 2 * BAND_OUTSET, BAND_HEIGHT, bandLayer.depth + 2 * BAND_OUTSET),
			CFrame.new(0, bandCenterY, 0),
			config.BandColor,
			false
		)
		band.Parent = model
	end

	-- Restrained fiery glow for the Mythic egg only.
	if config.GlowColor and mainBody then
		local light = Instance.new("PointLight")
		light.Color = config.GlowColor
		light.Brightness = 1.2
		light.Range = 9
		light.Shadows = false
		light.Parent = mainBody
	end

	if mainBody then
		model.PrimaryPart = mainBody
	end
	return model
end

-- Builds all five eggs under Workspace.NarutoEggs. Removes any existing
-- NarutoEggs folder first so reruns never create duplicates.
function NarutoEggGenerator.Build()
	local workspaceService = game:GetService("Workspace")

	local existing = workspaceService:FindFirstChild("NarutoEggs")
	if existing then
		existing.Parent = nil
	end

	local folder = Instance.new("Folder")
	folder.Name = "NarutoEggs"

	local spacing = 14
	local count = #EGG_CONFIGS
	for index, config in ipairs(EGG_CONFIGS) do
		local egg = NarutoEggGenerator.BuildEgg(config)
		-- Keep the pivot at its local height (MainBody center) so the egg's
		-- bottom rests exactly on the ground (Y = 0).
		local pivotY = egg:GetPivot().Position.Y
		egg:PivotTo(CFrame.new((index - (count + 1) / 2) * spacing, pivotY, 0))
		egg.Parent = folder
	end

	folder.Parent = workspaceService
	return folder
end

NarutoEggGenerator.Version = 2

return NarutoEggGenerator