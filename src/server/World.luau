--!strict
-- Builds the lab and the station consoles from Config, so `rojo build` alone reproduces the whole place.
-- The Glass itself is built by each client, against the same Config.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldConfig = Config.World

local World = {}

local function newPart(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	part.Parent = parent
	return part
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

local function buildRoom(parent: Instance)
	local width = WorldConfig.ROOM_WIDTH
	local height = WorldConfig.ROOM_HEIGHT
	local front = WorldConfig.ROOM_FRONT_Z
	local back = WorldConfig.ROOM_BACK_Z
	local depth = back - front
	local centerZ = (front + back) / 2
	local thickness = WorldConfig.WALL_THICKNESS
	local wallColor = WorldConfig.WALL_COLOR
	local plastic = Enum.Material.SmoothPlastic

	newPart(
		parent,
		"Floor",
		Vector3.new(width, thickness, depth),
		Vector3.new(0, -thickness / 2, centerZ),
		WorldConfig.FLOOR_COLOR,
		plastic
	)
	newPart(
		parent,
		"Ceiling",
		Vector3.new(width, thickness, depth),
		Vector3.new(0, height + thickness / 2, centerZ),
		wallColor,
		plastic
	)
	for _, z in { front - thickness / 2, back + thickness / 2 } do
		newPart(
			parent,
			"Wall",
			Vector3.new(width, height, thickness),
			Vector3.new(0, height / 2, z),
			wallColor,
			plastic
		)
	end
	local stripHeight = WorldConfig.STRIP_HEIGHT
	for _, side in { -1, 1 } do
		local x = side * (width + thickness) / 2
		newPart(
			parent,
			"Wall",
			Vector3.new(thickness, height, depth),
			Vector3.new(x, height / 2, centerZ),
			wallColor,
			plastic
		)
		-- A low glowing line along each side wall leads the eye to the Glass.
		newPart(
			parent,
			"Strip",
			Vector3.new(WorldConfig.STRIP_DEPTH, stripHeight, depth),
			Vector3.new(side * (width - WorldConfig.STRIP_DEPTH) / 2, WorldConfig.STRIP_Y, centerZ),
			WorldConfig.STRIP_COLOR,
			Enum.Material.Neon
		)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = WorldConfig.SPAWN_SIZE
	spawn.Position = WorldConfig.SPAWN_POSITION
	spawn.Color = WorldConfig.SPAWN_COLOR
	spawn.Material = plastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.CastShadow = false
	spawn.Parent = parent
end

local function buildConsole(parent: Instance, x: number): Part
	local size = WorldConfig.CONSOLE_SIZE
	local z = WorldConfig.CONSOLE_Z
	local anchor = newPart(
		parent,
		"Console",
		size,
		Vector3.new(x, size.Y / 2, z),
		WorldConfig.CONSOLE_COLOR,
		Enum.Material.SmoothPlastic
	)
	newPart(
		anchor,
		"Light",
		Vector3.new(size.X, WorldConfig.CONSOLE_LIGHT_HEIGHT, size.Z),
		Vector3.new(x, size.Y + WorldConfig.CONSOLE_LIGHT_HEIGHT / 2, z),
		WorldConfig.STRIP_COLOR,
		Enum.Material.Neon
	)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- +Z, toward players walking in from the spawn
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = WorldConfig.CONSOLE_TEXT_COLOR
	label.Text = WorldConfig.CONSOLE_TEXT
	label.Parent = gui
	return anchor
end

-- Builds everything and returns the station anchors.
function World.build(): { Part }
	removeTemplateParts()

	local lab = Instance.new("Model")
	lab.Name = "Lab"
	lab.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	buildRoom(lab)
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
