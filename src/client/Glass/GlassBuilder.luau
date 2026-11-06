--!strict
-- Builds the whole Glass once, from the model's shapes, and pools everything. After this, nothing in
-- the Glass is created or destroyed. Viewers stand on +Z with input on their left.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Explain = require(ReplicatedStorage.Shared.NeuralCore.Explain)
local Model = require(ReplicatedStorage.Shared.NeuralCore.Model)
local ModelData = require(ReplicatedStorage.Shared.NeuralCore.ModelData)

local GlassConfig = Config.Glass

export type OutputRow = {
	fill: Frame,
	shownPercent: number,
	isWinner: boolean,
}

export type Parts = {
	root: Folder,
	orbs: { { Part } }, -- orbs[layer][neuron]
	orbAttachments: { { Attachment } },
	orbPositions: { { Vector3 } }, -- world space
	pixelFrames: { Frame },
	pixelPositions: { Vector3 }, -- world space, front of the network view
	pixelLocalPositions: { Vector3 }, -- relative to the network view part
	pixelAttachments: { Attachment },
	beams: { Beam },
	packets: { Part },
	outputRows: { OutputRow },
	halo: Part,
	winnerLabel: TextLabel,
}

local GlassBuilder = {}

local function configurePart(part: BasePart, parent: Instance)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
end

local function newBox(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	transparency: number
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = GlassConfig.ORIGIN * CFrame.new(position)
	part.Color = color
	part.Transparency = transparency
	-- Never Glass material: it hides the beams and GUIs behind it (Rule 5).
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	configurePart(part, parent)
	return part
end

local function newBall(parent: Instance, name: string, size: number, cframe: CFrame, color: Color3): Part
	local ball = Instance.new("Part")
	ball.Name = name
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(size, size, size)
	ball.CFrame = cframe
	ball.Color = color
	ball.Material = Enum.Material.Neon
	configurePart(ball, parent)
	return ball
end

local function newSurfaceGui(parent: Part): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- +Z, facing the viewer
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = GlassConfig.PIXELS_PER_STUD
	gui.ResetOnSpawn = false
	gui.Parent = parent
	return gui
end

local function buildChamber(root: Instance)
	local width = GlassConfig.WIDTH
	local height = GlassConfig.HEIGHT
	local depth = GlassConfig.DEPTH
	local thickness = GlassConfig.FRAME_THICKNESS
	local frameColor = GlassConfig.FRAME_COLOR

	newBox(
		root,
		"Back",
		Vector3.new(width, height, thickness),
		Vector3.new(0, 0, -depth / 2),
		GlassConfig.BACK_COLOR,
		0
	)

	local pane =
		newBox(root, "Pane", Vector3.new(width, height, 0.1), Vector3.new(0, 0, depth / 2), GlassConfig.PANE_COLOR, 0)
	pane.Transparency = GlassConfig.PANE_TRANSPARENCY
	pane.Reflectance = GlassConfig.PANE_REFLECTANCE

	local outerWidth = width + 2 * thickness
	local frameDepth = depth + thickness
	for _, side in { -1, 1 } do
		newBox(
			root,
			"FrameHorizontal",
			Vector3.new(outerWidth, thickness, frameDepth),
			Vector3.new(0, side * (height + thickness) / 2, 0),
			frameColor,
			0
		)
		newBox(
			root,
			"FrameVertical",
			Vector3.new(thickness, height, frameDepth),
			Vector3.new(side * (width + thickness) / 2, 0, 0),
			frameColor,
			0
		)
	end
end

-- Returns each layer's center X, spreading the layers across the span with equal gaps between them.
local function layerCenters(model: Model.Model): { number }
	local count = #model.layers
	local spacing = GlassConfig.ORB_SPACING
	local widths: { number } = table.create(count, 0)
	local totalWidth = 0
	for l, layer in model.layers do
		local rows = if l == count then layer.outSize else GlassConfig.HIDDEN_ROWS
		widths[l] = (math.ceil(layer.outSize / rows) - 1) * spacing
		totalWidth += widths[l]
	end

	local left = GlassConfig.LAYERS_LEFT_X
	local gap = (GlassConfig.LAYERS_RIGHT_X - left - totalWidth) / (count + 1)
	local centers: { number } = table.create(count, 0)
	local cursor = left + gap
	for l = 1, count do
		centers[l] = cursor + widths[l] / 2
		cursor += widths[l] + gap
	end
	return centers
end

-- Returns the local position of each neuron in a layer: a centered grid of columns, top to bottom.
local function layerPositions(count: number, rows: number, centerX: number): { Vector3 }
	local spacing = GlassConfig.ORB_SPACING
	local columns = math.ceil(count / rows)
	local positions: { Vector3 } = table.create(count)
	for neuron = 0, count - 1 do
		local column = neuron // rows
		local row = neuron % rows
		positions[neuron + 1] =
			Vector3.new(centerX + (column - (columns - 1) / 2) * spacing, ((rows - 1) / 2 - row) * spacing, 0)
	end
	return positions
end

local function buildNetworkView(root: Instance): (Part, { Frame }, { Vector3 }, { Vector3 })
	local grid = ModelData.preprocess.grid
	local size = GlassConfig.NETWORK_VIEW_SIZE
	local thickness = GlassConfig.FRAME_THICKNESS
	local view = newBox(
		root,
		"NetworkView",
		Vector3.new(size, size, thickness),
		Vector3.new(GlassConfig.NETWORK_VIEW_X, 0, 0),
		GlassConfig.PIXEL_OFF_COLOR,
		0
	)

	local gui = newSurfaceGui(view)
	local pixelScale = 1 / grid
	local pixelSize = UDim2.fromScale(pixelScale, pixelScale)
	local frames: { Frame } = table.create(grid * grid)
	local worldPositions: { Vector3 } = table.create(grid * grid)
	local localPositions: { Vector3 } = table.create(grid * grid)
	for row = 0, grid - 1 do
		for col = 0, grid - 1 do
			local index = row * grid + col + 1
			local frame = Instance.new("Frame")
			frame.Name = "Pixel"
			frame.BackgroundColor3 = GlassConfig.PIXEL_OFF_COLOR
			frame.BorderSizePixel = 0
			frame.Position = UDim2.fromScale(col * pixelScale, row * pixelScale)
			frame.Size = pixelSize
			frame.Parent = gui
			frames[index] = frame

			local localPosition = Vector3.new(
				((col + 0.5) * pixelScale - 0.5) * size,
				(0.5 - (row + 0.5) * pixelScale) * size,
				thickness / 2
			)
			localPositions[index] = localPosition
			worldPositions[index] = view.CFrame:PointToWorldSpace(localPosition)
		end
	end
	return view, frames, worldPositions, localPositions
end

local function buildOutputPanel(root: Instance, positions: { Vector3 }): { OutputRow }
	local panelWidth = GlassConfig.OUTPUT_PANEL_WIDTH
	local panelHeight = GlassConfig.HEIGHT
	local panel = newBox(
		root,
		"OutputPanel",
		Vector3.new(panelWidth, panelHeight, 0.1),
		Vector3.new(GlassConfig.OUTPUT_PANEL_X, 0, 0),
		GlassConfig.BACK_COLOR,
		1
	)
	local gui = newSurfaceGui(panel)

	local rows: { OutputRow } = table.create(#positions)
	for index, position in positions do
		local centerY = 0.5 - position.Y / panelHeight
		local digitWidth = GlassConfig.OUTPUT_DIGIT_WIDTH
		local barHeight = GlassConfig.OUTPUT_BAR_HEIGHT

		local digit = Instance.new("TextLabel")
		digit.Name = "Digit"
		digit.BackgroundTransparency = 1
		digit.AnchorPoint = Vector2.new(0, 0.5)
		digit.Position = UDim2.fromScale(0, centerY)
		digit.Size = UDim2.fromScale(digitWidth, barHeight * 2)
		digit.Font = Enum.Font.GothamBold
		digit.TextSize = GlassConfig.OUTPUT_TEXT_SIZE
		digit.TextColor3 = GlassConfig.TEXT_COLOR
		digit.Text = tostring(index - 1)
		digit.Parent = gui

		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.BackgroundColor3 = GlassConfig.BAR_BACKGROUND_COLOR
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0, 0.5)
		bar.Position = UDim2.fromScale(digitWidth, centerY)
		bar.Size = UDim2.fromScale(GlassConfig.OUTPUT_BAR_WIDTH, barHeight)
		bar.Parent = gui

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = GlassConfig.BAR_COLOR
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0, 1)
		fill.Parent = bar

		rows[index] = { fill = fill, shownPercent = 0, isWinner = false }
	end
	return rows
end

local function buildWinnerLabel(root: Instance): TextLabel
	local part = newBox(
		root,
		"Winner",
		Vector3.new(GlassConfig.WINNER_WIDTH, GlassConfig.WINNER_HEIGHT, 0.1),
		Vector3.new(0, GlassConfig.WINNER_Y, 0),
		GlassConfig.BACK_COLOR,
		1
	)
	local gui = newSurfaceGui(part)
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = GlassConfig.WINNER_TEXT_SIZE
	label.TextColor3 = GlassConfig.TEXT_COLOR
	label.Text = ""
	label.Parent = gui
	return label
end

function GlassBuilder.build(model: Model.Model): Parts
	-- Stays unparented until complete, so the engine processes the build once.
	local root = Instance.new("Folder")
	root.Name = "TheGlass"

	buildChamber(root)
	local networkView, pixelFrames, pixelPositions, pixelLocalPositions = buildNetworkView(root)

	local layerCount = #model.layers
	local orbFolder = Instance.new("Folder")
	orbFolder.Name = "Orbs"
	orbFolder.Parent = root

	local orbs: { { Part } } = table.create(layerCount)
	local orbAttachments: { { Attachment } } = table.create(layerCount)
	local orbPositions: { { Vector3 } } = table.create(layerCount)
	local outputRows: { OutputRow } = {}
	local origin = GlassConfig.ORIGIN
	local centers = layerCenters(model)
	for l, layer in model.layers do
		local isOutput = l == layerCount
		local count = layer.outSize
		local positions = layerPositions(count, if isOutput then count else GlassConfig.HIDDEN_ROWS, centers[l])

		local layerOrbs: { Part } = table.create(count)
		local layerAttachments: { Attachment } = table.create(count)
		local layerWorld: { Vector3 } = table.create(count)
		for neuron, position in positions do
			local cframe = origin * CFrame.new(position)
			local orb = newBall(orbFolder, "Orb", GlassConfig.ORB_MIN_SIZE, cframe, GlassConfig.ORB_DIM_COLOR)
			local attachment = Instance.new("Attachment")
			attachment.Parent = orb
			layerOrbs[neuron] = orb
			layerAttachments[neuron] = attachment
			layerWorld[neuron] = cframe.Position
		end
		orbs[l] = layerOrbs
		orbAttachments[l] = layerAttachments
		orbPositions[l] = layerWorld
		if isOutput then
			outputRows = buildOutputPanel(root, positions)
		end
	end

	local capacity = Explain.maxEdges(model)
	local pixelAttachmentCount = Explain.INPUT_TOP_NEURONS * Explain.INPUT_LINKS_PER_NEURON
	local pixelAttachments: { Attachment } = table.create(pixelAttachmentCount)
	for index = 1, pixelAttachmentCount do
		local attachment = Instance.new("Attachment")
		attachment.Name = "PixelLink"
		attachment.Parent = networkView
		pixelAttachments[index] = attachment
	end

	local beamFolder = Instance.new("Folder")
	beamFolder.Name = "Links"
	beamFolder.Parent = root
	local beams: { Beam } = table.create(capacity)
	for index = 1, capacity do
		local beam = Instance.new("Beam")
		beam.FaceCamera = true
		beam.LightInfluence = 0
		beam.LightEmission = 1
		beam.Segments = 1
		beam.Enabled = false
		beam.Parent = beamFolder
		beams[index] = beam
	end

	local packetFolder = Instance.new("Folder")
	packetFolder.Name = "Packets"
	packetFolder.Parent = root
	local parked = CFrame.new(GlassConfig.PACKET_PARK_POSITION)
	local packets: { Part } = table.create(GlassConfig.PACKET_COUNT)
	for index = 1, GlassConfig.PACKET_COUNT do
		packets[index] = newBall(packetFolder, "Packet", GlassConfig.PACKET_SIZE, parked, GlassConfig.POSITIVE_COLOR)
	end

	local halo = newBall(root, "Halo", GlassConfig.HALO_SIZE, parked, GlassConfig.ORB_BRIGHT_COLOR)
	halo.Transparency = GlassConfig.HALO_TRANSPARENCY

	local winnerLabel = buildWinnerLabel(root)

	root.Parent = workspace
	return {
		root = root,
		orbs = orbs,
		orbAttachments = orbAttachments,
		orbPositions = orbPositions,
		pixelFrames = pixelFrames,
		pixelPositions = pixelPositions,
		pixelLocalPositions = pixelLocalPositions,
		pixelAttachments = pixelAttachments,
		beams = beams,
		packets = packets,
		outputRows = outputRows,
		halo = halo,
		winnerLabel = winnerLabel,
	}
end

return GlassBuilder
