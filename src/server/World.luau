--!strict
-- Builds the lab and the station consoles from Config, so `rojo build` alone reproduces the whole place.
-- The Glass itself is built by each client, against the same Config.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ModelData = require(ReplicatedStorage.Shared.NeuralCore.ModelData)

local WorldConfig = Config.World

local World = {}

local function newPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- Scenery you can't bump into or click through.
local function newDecor(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local part = newPart(parent, name, size, cframe, color, material)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

local function newGlow(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	return newDecor(parent, name, size, cframe, color, Enum.Material.Neon)
end

-- A flat glowing disc lying on the floor. A cylinder's axis is X, so stand it up.
local function discCFrame(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi / 2)
end

local function newGlowDisc(parent: Instance, name: string, diameter: number, x: number, z: number, color: Color3): Part
	local height = WorldConfig.GRID_LINE_HEIGHT
	local disc = newGlow(parent, name, Vector3.new(height, diameter, diameter), discCFrame(x, height, z), color)
	disc.Shape = Enum.PartType.Cylinder
	return disc
end

local function newSurfaceText(parent: Part, face: Enum.NormalId): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = WorldConfig.TEXT_PIXELS_PER_STUD
	gui.Parent = parent
	return gui
end

local function newText(parent: Instance, text: string, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = color
	label.Text = text
	label.Parent = parent
	return label
end

-- Leftovers from the Studio template. A place made by `rojo build` has neither.
local function removeTemplateParts()
	for _, name in { "Baseplate", "SpawnLocation" } do
		local template = workspace:FindFirstChild(name)
		if template ~= nil then
			template:Destroy()
		end
	end
end

local function buildShell(parent: Instance)
	local width = WorldConfig.ROOM_WIDTH
	local height = WorldConfig.ROOM_HEIGHT
	local front = WorldConfig.ROOM_FRONT_Z
	local back = WorldConfig.ROOM_BACK_Z
	local depth = back - front
	local centerZ = (front + back) / 2
	local thickness = WorldConfig.WALL_THICKNESS
	local wallColor = WorldConfig.WALL_COLOR
	local plastic = Enum.Material.SmoothPlastic

	local floor = newPart(
		parent,
		"Floor",
		Vector3.new(width, thickness, depth),
		CFrame.new(0, -thickness / 2, centerZ),
		WorldConfig.FLOOR_COLOR,
		plastic
	)
	floor.Reflectance = WorldConfig.FLOOR_REFLECTANCE
	newPart(
		parent,
		"Ceiling",
		Vector3.new(width, thickness, depth),
		CFrame.new(0, height + thickness / 2, centerZ),
		wallColor,
		plastic
	)
	for _, z in { front - thickness / 2, back + thickness / 2 } do
		newPart(parent, "Wall", Vector3.new(width, height, thickness), CFrame.new(0, height / 2, z), wallColor, plastic)
	end
	for _, side in { -1, 1 } do
		local x = side * (width + thickness) / 2
		newPart(
			parent,
			"Wall",
			Vector3.new(thickness, height, depth),
			CFrame.new(x, height / 2, centerZ),
			wallColor,
			plastic
		)
		-- A low glowing line along each side wall leads the eye to the Glass.
		newGlow(
			parent,
			"Strip",
			Vector3.new(WorldConfig.STRIP_DEPTH, WorldConfig.STRIP_HEIGHT, depth),
			CFrame.new(side * (width - WorldConfig.STRIP_DEPTH) / 2, WorldConfig.STRIP_Y, centerZ),
			WorldConfig.GLOW_COLOR
		)
	end
end

-- A faint grid set into the floor, with a brighter walkway from the spawn to the consoles.
local function buildFloorLights(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "FloorLights"
	folder.Parent = parent

	local width = WorldConfig.ROOM_WIDTH
	local front = WorldConfig.ROOM_FRONT_Z
	local back = WorldConfig.ROOM_BACK_Z
	local spacing = WorldConfig.GRID_SPACING
	local line = WorldConfig.GRID_LINE_WIDTH
	local y = WorldConfig.GRID_LINE_HEIGHT / 2
	local height = WorldConfig.GRID_LINE_HEIGHT
	local gridColor = WorldConfig.GRID_COLOR

	local x = spacing
	while x < width / 2 do
		for _, side in { -1, 1 } do
			newGlow(
				folder,
				"GridLine",
				Vector3.new(line, height, back - front),
				CFrame.new(side * x, y, (front + back) / 2),
				gridColor
			)
		end
		x += spacing
	end
	local z = back - spacing
	while z > front do
		newGlow(folder, "GridLine", Vector3.new(width, height, line), CFrame.new(0, y, z), gridColor)
		z -= spacing
	end

	local walkFront = WorldConfig.CONSOLE_Z + WorldConfig.CONSOLE_SIZE.Z
	local walkBack = WorldConfig.SPAWN_POSITION.Z - WorldConfig.SPAWN_DIAMETER / 2
	for _, side in { -1, 1 } do
		newGlow(
			folder,
			"Walkway",
			Vector3.new(WorldConfig.WALKWAY_LINE_WIDTH, height * 2, walkBack - walkFront),
			CFrame.new(side * WorldConfig.WALKWAY_HALF_WIDTH, height, (walkFront + walkBack) / 2),
			WorldConfig.ACCENT_COLOR
		)
	end
end

-- Chamfered portals down the room, framing the Glass as you walk toward it. They stay well clear of the
-- middle, because the Draw Mode camera looks through them.
local function buildArch(parent: Instance, z: number)
	local arch = Instance.new("Model")
	arch.Name = "Arch"
	arch.Parent = parent

	local halfWidth = WorldConfig.ARCH_HALF_WIDTH
	local height = WorldConfig.ARCH_HEIGHT
	local chamfer = WorldConfig.ARCH_CHAMFER
	local beam = WorldConfig.ARCH_BEAM
	local depth = WorldConfig.ARCH_DEPTH
	local glow = WorldConfig.ARCH_GLOW
	local frameColor = WorldConfig.ARCH_COLOR
	local glowColor = WorldConfig.GLOW_COLOR
	local metal = Enum.Material.Metal

	local columnHeight = height - chamfer
	local spanLength = 2 * (halfWidth - chamfer)
	local braceLength = chamfer * math.sqrt(2)

	newDecor(arch, "Beam", Vector3.new(spanLength, beam, depth), CFrame.new(0, height, z), frameColor, metal)
	newGlow(arch, "BeamGlow", Vector3.new(spanLength, glow, glow), CFrame.new(0, height - beam / 2, z), glowColor)

	for _, side in { -1, 1 } do
		local columnX = side * halfWidth
		newDecor(
			arch,
			"Column",
			Vector3.new(beam, columnHeight, depth),
			CFrame.new(columnX, columnHeight / 2, z),
			frameColor,
			metal
		)
		newGlow(
			arch,
			"ColumnGlow",
			Vector3.new(glow, columnHeight, glow),
			CFrame.new(columnX - side * beam / 2, columnHeight / 2, z),
			glowColor
		)

		local braceCFrame = CFrame.new(side * (halfWidth - chamfer / 2), height - chamfer / 2, z)
			* CFrame.Angles(0, 0, side * math.pi / 4)
		newDecor(arch, "Brace", Vector3.new(braceLength, beam, depth), braceCFrame, frameColor, metal)
		newGlow(
			arch,
			"BraceGlow",
			Vector3.new(braceLength, glow, glow),
			braceCFrame * CFrame.new(0, -beam / 2, 0),
			glowColor
		)
	end

	local lamp = Instance.new("PointLight")
	lamp.Color = WorldConfig.LAMP_COLOR
	lamp.Range = WorldConfig.LAMP_RANGE
	lamp.Brightness = WorldConfig.LAMP_BRIGHTNESS
	lamp.Parent = arch:FindFirstChild("BeamGlow")
end

local function buildSpawn(parent: Instance)
	local position = WorldConfig.SPAWN_POSITION
	local diameter = WorldConfig.SPAWN_DIAMETER
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Shape = Enum.PartType.Cylinder
	spawn.Size = Vector3.new(WorldConfig.SPAWN_HEIGHT, diameter, diameter)
	spawn.CFrame = discCFrame(position.X, WorldConfig.SPAWN_HEIGHT / 2, position.Z)
	spawn.Color = WorldConfig.SPAWN_COLOR
	spawn.Material = Enum.Material.Metal
	spawn.CastShadow = false
	spawn.Parent = parent

	newGlowDisc(parent, "SpawnRing", diameter + WorldConfig.SPAWN_RING, position.X, position.Z, WorldConfig.GLOW_COLOR)
end

-- The name over the Glass, and how to play on the wall opposite the leaderboard.
local function buildBackWall(parent: Instance)
	local z = WorldConfig.ROOM_FRONT_Z + WorldConfig.SIGN_DEPTH / 2

	local title = newDecor(
		parent,
		"Title",
		Vector3.new(WorldConfig.TITLE_WIDTH, WorldConfig.TITLE_HEIGHT, WorldConfig.SIGN_DEPTH),
		CFrame.new(0, WorldConfig.TITLE_Y, z),
		WorldConfig.WALL_COLOR,
		Enum.Material.SmoothPlastic
	)
	title.Transparency = 1
	newText(
		newSurfaceText(title, Enum.NormalId.Back),
		WorldConfig.TITLE_TEXT,
		WorldConfig.TITLE_TEXT_SIZE,
		WorldConfig.GLOW_COLOR
	)

	local position = WorldConfig.GUIDE_POSITION
	local guide = newDecor(
		parent,
		"Guide",
		Vector3.new(WorldConfig.GUIDE_WIDTH, WorldConfig.GUIDE_HEIGHT, WorldConfig.SIGN_DEPTH),
		CFrame.new(position),
		WorldConfig.GUIDE_COLOR,
		Enum.Material.SmoothPlastic
	)
	newGlow(
		guide,
		"Trim",
		Vector3.new(WorldConfig.GUIDE_WIDTH, WorldConfig.GUIDE_TRIM, WorldConfig.SIGN_DEPTH),
		CFrame.new(position + Vector3.new(0, (WorldConfig.GUIDE_HEIGHT + WorldConfig.GUIDE_TRIM) / 2, 0)),
		WorldConfig.GLOW_COLOR
	)
	local gui = newSurfaceText(guide, Enum.NormalId.Back)
	local lines = WorldConfig.GUIDE_LINES
	for index, line in lines do
		local label = newText(
			gui,
			line,
			if index == 1 then WorldConfig.GUIDE_TITLE_SIZE else WorldConfig.GUIDE_TEXT_SIZE,
			if index == 1 then WorldConfig.GUIDE_TITLE_COLOR else WorldConfig.GUIDE_TEXT_COLOR
		)
		label.Position = UDim2.fromScale(0, (index - 1) / #lines)
		label.Size = UDim2.fromScale(1, 1 / #lines)
		label.TextWrapped = true
	end
end

-- "64, then 32": the hidden layers' sizes, read from the model like every other shape.
local function hiddenSizesText(): string
	local sizes: { string } = {}
	for index = 1, #ModelData.layers - 1 do
		table.insert(sizes, tostring(ModelData.layers[index].outSize))
	end
	return table.concat(sizes, ", then ")
end

-- The four steps from a drawing to an answer, on the wall behind the spawn. The numbers come from the
-- model itself, so a retrain can't leave this out of date.
local function buildHowItWorks(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "HowItWorks"
	folder.Parent = parent

	local config = WorldConfig.HOW_IT_WORKS
	local layers = ModelData.layers
	local grid = ModelData.preprocess.grid
	local z = WorldConfig.ROOM_BACK_Z - WorldConfig.SIGN_DEPTH / 2
	local face = Enum.NormalId.Front -- -Z, facing back into the room

	local title = newDecor(
		folder,
		"Title",
		Vector3.new(config.ROW_WIDTH, config.TITLE_HEIGHT, WorldConfig.SIGN_DEPTH),
		CFrame.new(0, config.TITLE_Y, z),
		WorldConfig.WALL_COLOR,
		Enum.Material.SmoothPlastic
	)
	title.Transparency = 1
	newText(newSurfaceText(title, face), config.TITLE, config.TITLE_TEXT_SIZE, WorldConfig.GLOW_COLOR)

	local bodies = {
		config.BODY_DRAW,
		string.format(config.BODY_SEE, grid, grid, layers[1].inSize),
		string.format(config.BODY_THINK, hiddenSizesText()),
		string.format(config.BODY_ANSWER, layers[#layers].outSize),
	}
	local count = #config.HEADINGS
	local cardWidth = config.CARD_WIDTH
	local pitch = cardWidth + config.CARD_GAP
	for index, heading in config.HEADINGS do
		-- A viewer here faces +Z, so their left is +X: step 1 goes on the +X side.
		local x = ((count + 1) / 2 - index) * pitch
		local card = newDecor(
			folder,
			"Card",
			Vector3.new(cardWidth, config.CARD_HEIGHT, WorldConfig.SIGN_DEPTH),
			CFrame.new(x, config.CARD_Y, z),
			config.CARD_COLOR,
			Enum.Material.SmoothPlastic
		)
		newGlow(
			card,
			"Trim",
			Vector3.new(cardWidth, config.TRIM, WorldConfig.SIGN_DEPTH),
			CFrame.new(x, config.CARD_Y + (config.CARD_HEIGHT + config.TRIM) / 2, z),
			WorldConfig.GLOW_COLOR
		)

		local gui = newSurfaceText(card, face)
		local number = newText(gui, tostring(index), config.NUMBER_TEXT_SIZE, WorldConfig.GLOW_COLOR)
		number.Size = UDim2.fromScale(1, config.NUMBER_SHARE)

		local headingLabel = newText(gui, heading, config.HEADING_TEXT_SIZE, config.HEADING_COLOR)
		headingLabel.Position = UDim2.fromScale(0, config.NUMBER_SHARE)
		headingLabel.Size = UDim2.fromScale(1, config.HEADING_SHARE)

		local bodyTop = config.NUMBER_SHARE + config.HEADING_SHARE
		local margin = config.BODY_MARGIN
		local body = newText(gui, bodies[index], config.BODY_TEXT_SIZE, config.BODY_COLOR)
		body.Font = Enum.Font.GothamMedium
		body.Position = UDim2.fromScale(margin, bodyTop)
		body.Size = UDim2.fromScale(1 - 2 * margin, 1 - bodyTop)
		body.TextWrapped = true
		body.TextYAlignment = Enum.TextYAlignment.Top

		-- An arrow-like bar across the gap to the next step.
		if index < count then
			newGlow(
				folder,
				"Link",
				Vector3.new(config.CARD_GAP, config.LINK_THICKNESS, config.LINK_THICKNESS),
				CFrame.new(x - pitch / 2, config.CARD_Y, z),
				WorldConfig.ACCENT_COLOR
			)
		end
	end

	local footer = newDecor(
		folder,
		"Footer",
		Vector3.new(config.ROW_WIDTH, config.FOOTER_HEIGHT, WorldConfig.SIGN_DEPTH),
		CFrame.new(0, config.FOOTER_Y, z),
		WorldConfig.WALL_COLOR,
		Enum.Material.SmoothPlastic
	)
	footer.Transparency = 1
	local footerLabel = newText(
		newSurfaceText(footer, face),
		string.format(config.FOOTER, ModelData.metrics.int8TestAcc),
		config.FOOTER_TEXT_SIZE,
		config.BODY_COLOR
	)
	footerLabel.Font = Enum.Font.GothamMedium
	footerLabel.TextWrapped = true
end

-- Data drifting through the air behind where the Draw Mode camera sits, so it never crosses the Glass.
local function buildMotes(parent: Instance)
	local volume = newDecor(
		parent,
		"Motes",
		WorldConfig.MOTES_SIZE,
		CFrame.new(WorldConfig.MOTES_POSITION),
		WorldConfig.GLOW_COLOR,
		Enum.Material.SmoothPlastic
	)
	volume.Transparency = 1

	local motes = Instance.new("ParticleEmitter")
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	motes.Rate = WorldConfig.MOTES_RATE
	motes.Lifetime = WorldConfig.MOTES_LIFETIME
	motes.Speed = WorldConfig.MOTES_SPEED
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Size = NumberSequence.new(WorldConfig.MOTES_PARTICLE_SIZE)
	motes.Color = ColorSequence.new(WorldConfig.GLOW_COLOR)
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, WorldConfig.MOTES_TRANSPARENCY),
		NumberSequenceKeypoint.new(0.7, WorldConfig.MOTES_TRANSPARENCY),
		NumberSequenceKeypoint.new(1, 1),
	})
	motes.Parent = volume
end

-- A pedestal with an angled screen, a floating light above it, and a ring on the floor around it.
local function buildConsole(parent: Instance, x: number): Part
	local size = WorldConfig.CONSOLE_SIZE
	local z = WorldConfig.CONSOLE_Z
	local anchor =
		newPart(parent, "Console", size, CFrame.new(x, size.Y / 2, z), WorldConfig.CONSOLE_COLOR, Enum.Material.Metal)

	-- Tilted toward whoever walks up, like a lectern. The text is on the face that points at them, which
	-- reads the right way up because the part's own up direction runs away from them.
	local depth = WorldConfig.CONSOLE_SCREEN_DEPTH
	local screen = newDecor(
		anchor,
		"Screen",
		Vector3.new(size.X, depth, WorldConfig.CONSOLE_SCREEN_THICKNESS),
		CFrame.new(x, size.Y + WorldConfig.CONSOLE_SCREEN_LIFT, z)
			* CFrame.Angles(-WorldConfig.CONSOLE_SCREEN_TILT, 0, 0),
		WorldConfig.CONSOLE_SCREEN_COLOR,
		Enum.Material.SmoothPlastic
	)
	newGlow(
		screen,
		"ScreenEdge",
		Vector3.new(size.X, WorldConfig.CONSOLE_EDGE, WorldConfig.CONSOLE_EDGE),
		screen.CFrame * CFrame.new(0, -depth / 2, 0),
		WorldConfig.GLOW_COLOR
	)
	newText(
		newSurfaceText(screen, Enum.NormalId.Back),
		WorldConfig.CONSOLE_TEXT,
		WorldConfig.CONSOLE_TEXT_SIZE,
		WorldConfig.CONSOLE_TEXT_COLOR
	)

	local beacon = WorldConfig.CONSOLE_BEACON_SIZE
	newGlow(
		anchor,
		"Beacon",
		Vector3.new(beacon, beacon, beacon),
		CFrame.new(x, WorldConfig.CONSOLE_BEACON_Y, z) * CFrame.Angles(math.pi / 4, 0, math.pi / 4),
		WorldConfig.ACCENT_COLOR
	)
	newGlowDisc(anchor, "Ring", WorldConfig.CONSOLE_RING_DIAMETER, x, z, WorldConfig.CONSOLE_RING_COLOR)
	return anchor
end

-- Builds everything and returns the station anchors.
function World.build(): { Part }
	removeTemplateParts()

	local lab = Instance.new("Model")
	lab.Name = "Lab"
	lab.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	buildShell(lab)
	buildFloorLights(lab)
	for index = 1, WorldConfig.ARCH_COUNT do
		buildArch(lab, WorldConfig.ARCH_FIRST_Z + (index - 1) * WorldConfig.ARCH_SPACING)
	end
	buildSpawn(lab)
	buildBackWall(lab)
	buildHowItWorks(lab)
	buildMotes(lab)
	lab.Parent = workspace

	local stations = Instance.new("Model")
	stations.Name = "Stations"
	stations.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local anchors: { Part } = table.create(WorldConfig.STATION_COUNT)
	local spacing = WorldConfig.STATION_SPACING
	for index = 1, WorldConfig.STATION_COUNT do
		local x = (index - (WorldConfig.STATION_COUNT + 1) / 2) * spacing
		anchors[index] = buildConsole(stations, x)
	end
	stations.Parent = workspace
	return anchors
end

return World
