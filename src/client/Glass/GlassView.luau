--!strict
-- Animates the Glass. One per-frame connection drives everything. Colors and sequences come from
-- palettes made once, values are quantized so small changes skip their writes, and packets all move
-- through a single BulkMoveTo call.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Model = require(ReplicatedStorage.Shared.NeuralCore.Model)
local Inference = require(script.Parent.Parent.Inference)
local GlassBuilder = require(script.Parent.GlassBuilder)

local GlassConfig = Config.Glass

local clock = os.clock
local exp = math.exp
local floor = math.floor
local random = math.random
local sin = math.sin

type Snapshot = {
	time: number,
	values: { { number } }, -- values[layer][neuron], in [0, 1]
	isIdle: boolean,
}

export type GlassView = {
	parts: GlassBuilder.Parts,
	model: Model.Model,
	reducedMotion: boolean,

	-- Propagation.
	history: { Snapshot },
	historyHead: number,
	targets: { { number } },
	targetIdle: { boolean },
	displayed: { { number } },
	shownOrbLevel: { { number } },
	phases: { { number } },

	-- Palettes.
	orbColors: { Color3 },
	orbSizes: { Vector3 },
	pixelColors: { Color3 },
	positiveLinkColor: ColorSequence,
	negativeLinkColor: ColorSequence,
	linkTransparency: { NumberSequence },
	linkWidths: { number },

	-- Links.
	shownPixelLevel: { number },
	beamSign: { number },
	beamLevel: { number },
	beamSource: { Attachment? },
	beamTarget: { Attachment? },
	edgeCount: number,
	edgeFrom: { Vector3 },
	edgeTo: { Vector3 },
	edgeRate: { number },
	edgeSpawnCredit: { number },
	edgeIsNegative: { boolean },

	-- Packets. Entries 1..activePackets are live and line up with the BulkMoveTo arrays.
	activePackets: number,
	freePackets: { Part },
	freePacketCount: number,
	movingParts: { Part },
	movingCFrames: { CFrame },
	packetFrom: { Vector3 },
	packetTo: { Vector3 },
	packetProgress: { number },
	idlePacketCredit: number,

	winner: number,
	lastStepSeconds: number,
	elapsed: number,
}

local GlassView = {}

local function retirePacket(view: GlassView, slot: number)
	local count = view.activePackets
	local part = view.movingParts[slot]
	part.CFrame = CFrame.new(GlassConfig.PACKET_PARK_POSITION)
	view.freePacketCount += 1
	view.freePackets[view.freePacketCount] = part

	view.movingParts[slot] = view.movingParts[count]
	view.movingCFrames[slot] = view.movingCFrames[count]
	view.packetFrom[slot] = view.packetFrom[count]
	view.packetTo[slot] = view.packetTo[count]
	view.packetProgress[slot] = view.packetProgress[count]
	-- BulkMoveTo takes the arrays' lengths, so the ends have to go.
	view.movingParts[count] = nil :: any
	view.movingCFrames[count] = nil :: any
	view.activePackets = count - 1
end

local function spawnPacket(view: GlassView, from: Vector3, to: Vector3, isNegative: boolean)
	local freeCount = view.freePacketCount
	if freeCount == 0 then
		return
	end
	local part = view.freePackets[freeCount]
	view.freePacketCount = freeCount - 1

	local size = if isNegative then GlassConfig.PACKET_NEGATIVE_SIZE else GlassConfig.PACKET_SIZE
	part.Size = Vector3.new(size, size, size)
	part.Color = if isNegative then GlassConfig.NEGATIVE_COLOR else GlassConfig.POSITIVE_COLOR

	local slot = view.activePackets + 1
	view.activePackets = slot
	view.movingParts[slot] = part
	view.movingCFrames[slot] = CFrame.new(from)
	view.packetFrom[slot] = from
	view.packetTo[slot] = to
	view.packetProgress[slot] = 0
end

local function stepPackets(view: GlassView, dt: number)
	local progressPerSecond = 1 / GlassConfig.PACKET_SECONDS
	local slot = 1
	while slot <= view.activePackets do
		local progress = view.packetProgress[slot] + dt * progressPerSecond
		if progress >= 1 then
			retirePacket(view, slot)
		else
			view.packetProgress[slot] = progress
			local from = view.packetFrom[slot]
			view.movingCFrames[slot] = CFrame.new(from + (view.packetTo[slot] - from) * progress)
			slot += 1
		end
	end
	if view.activePackets > 0 then
		workspace:BulkMoveTo(view.movingParts, view.movingCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function spawnFromEdges(view: GlassView, dt: number)
	local maxRate = GlassConfig.PACKET_MAX_RATE
	for k = 1, view.edgeCount do
		local credit = view.edgeSpawnCredit[k] + dt * maxRate * view.edgeRate[k]
		if credit >= 1 then
			credit -= 1
			spawnPacket(view, view.edgeFrom[k], view.edgeTo[k], view.edgeIsNegative[k])
		end
		view.edgeSpawnCredit[k] = credit
	end
end

-- Ambient packets between random neighboring layers, while the pad is empty.
local function spawnIdlePackets(view: GlassView, dt: number)
	local credit = view.idlePacketCredit + dt * GlassConfig.IDLE_PACKET_RATE
	if credit >= 1 then
		credit -= 1
		local positions = view.parts.orbPositions
		local l = random(2, #positions)
		local sourceLayer = positions[l - 1]
		local targetLayer = positions[l]
		spawnPacket(view, sourceLayer[random(1, #sourceLayer)], targetLayer[random(1, #targetLayer)], false)
	end
	view.idlePacketCredit = credit
end

local function layerLag(l: number): number
	return l * GlassConfig.HIDDEN_LAG_STEP
end

-- Points each layer at the newest snapshot old enough for that layer's lag.
local function updateTargets(view: GlassView, now: number)
	local history = view.history
	local size = #history
	for l = 1, #view.targets do
		local lag = layerLag(l)
		for age = 0, size - 1 do
			local snapshot = history[(view.historyHead - age - 1) % size + 1]
			if snapshot.time + lag <= now then
				view.targets[l] = snapshot.values[l]
				view.targetIdle[l] = snapshot.isIdle
				break
			end
		end
	end
end

local function stepOrbs(view: GlassView, dt: number)
	local smoothing = 1 - exp(-dt / GlassConfig.SMOOTHING_TAU)
	local levels = GlassConfig.ORB_LEVELS
	local elapsedAngle = view.elapsed * GlassConfig.IDLE_SPEED
	local idleBase = GlassConfig.IDLE_BASE
	local idleAmplitude = GlassConfig.IDLE_AMPLITUDE
	local orbColors = view.orbColors
	local orbSizes = view.orbSizes

	for l = 1, #view.targets do
		local target = view.targets[l]
		local displayed = view.displayed[l]
		local shown = view.shownOrbLevel[l]
		local orbs = view.parts.orbs[l]
		local phases = view.phases[l]
		local isIdle = view.targetIdle[l]
		for n = 1, #displayed do
			local value = displayed[n] + (target[n] - displayed[n]) * smoothing
			displayed[n] = value
			local brightness = value
			if isIdle then
				brightness += idleBase + idleAmplitude * sin(elapsedAngle + phases[n])
			end
			local level = floor(brightness * (levels - 1) + 0.5)
			if level < 0 then
				level = 0
			elseif level > levels - 1 then
				level = levels - 1
			end
			if level ~= shown[n] then
				shown[n] = level
				local orb = orbs[n]
				orb.Color = orbColors[level + 1]
				orb.Size = orbSizes[level + 1]
			end
		end
	end
end

local function stepOutputBars(view: GlassView)
	local displayed = view.displayed[#view.displayed]
	local rows = view.parts.outputRows
	for index = 1, #rows do
		local row = rows[index]
		local percent = floor(displayed[index] * 100 + 0.5)
		if percent ~= row.shownPercent then
			row.shownPercent = percent
			row.fill.Size = UDim2.fromScale(percent / 100, 1)
		end
	end
end

local function step(view: GlassView, dt: number)
	local started = clock()
	view.elapsed += dt
	updateTargets(view, started)
	stepOrbs(view, dt)
	stepOutputBars(view)
	-- Reduced motion keeps the links and only stops new packets.
	if not view.reducedMotion then
		if view.edgeCount > 0 then
			spawnFromEdges(view, dt)
		elseif view.targetIdle[#view.targetIdle] then
			spawnIdlePackets(view, dt)
		end
	end
	stepPackets(view, dt)
	view.lastStepSeconds = clock() - started
end

local function newPalettes(): ({ Color3 }, { Vector3 }, { Color3 })
	local orbColors: { Color3 } = table.create(GlassConfig.ORB_LEVELS)
	local orbSizes: { Vector3 } = table.create(GlassConfig.ORB_LEVELS)
	for level = 1, GlassConfig.ORB_LEVELS do
		local fraction = (level - 1) / (GlassConfig.ORB_LEVELS - 1)
		orbColors[level] = GlassConfig.ORB_DIM_COLOR:Lerp(GlassConfig.ORB_BRIGHT_COLOR, fraction)
		local size = GlassConfig.ORB_MIN_SIZE + (GlassConfig.ORB_MAX_SIZE - GlassConfig.ORB_MIN_SIZE) * fraction
		orbSizes[level] = Vector3.new(size, size, size)
	end
	local pixelColors: { Color3 } = table.create(GlassConfig.PIXEL_LEVELS)
	for level = 1, GlassConfig.PIXEL_LEVELS do
		local fraction = (level - 1) / (GlassConfig.PIXEL_LEVELS - 1)
		pixelColors[level] = GlassConfig.PIXEL_OFF_COLOR:Lerp(GlassConfig.PIXEL_ON_COLOR, fraction)
	end
	return orbColors, orbSizes, pixelColors
end

function GlassView.new(model: Model.Model): GlassView
	local parts = GlassBuilder.build(model)
	local layerCount = #model.layers

	local function perNeuron(fill: number): { { number } }
		local values: { { number } } = table.create(layerCount)
		for l, layer in model.layers do
			values[l] = table.create(layer.outSize, fill)
		end
		return values
	end

	local history: { Snapshot } = table.create(GlassConfig.HISTORY_SIZE)
	for index = 1, GlassConfig.HISTORY_SIZE do
		history[index] = { time = -math.huge, values = perNeuron(0), isIdle = true }
	end

	local targets: { { number } } = table.create(layerCount)
	local targetIdle: { boolean } = table.create(layerCount, true)
	for l = 1, layerCount do
		targets[l] = history[1].values[l]
	end

	local phases = perNeuron(0)
	local phaseOffset = 0
	for l = 1, layerCount do
		for n = 1, #phases[l] do
			phases[l][n] = phaseOffset
			phaseOffset += GlassConfig.PHASE_STEP
		end
	end

	local orbColors, orbSizes, pixelColors = newPalettes()

	local linkLevels = GlassConfig.LINK_LEVELS
	local linkTransparency: { NumberSequence } = table.create(linkLevels)
	local linkWidths: { number } = table.create(linkLevels, 0)
	for level = 1, linkLevels do
		local fraction = level / linkLevels
		local opacity = GlassConfig.LINK_MIN_OPACITY
			+ (GlassConfig.LINK_MAX_OPACITY - GlassConfig.LINK_MIN_OPACITY) * fraction
		linkTransparency[level] = NumberSequence.new(1 - opacity)
		linkWidths[level] = GlassConfig.LINK_MIN_WIDTH
			+ (GlassConfig.LINK_MAX_WIDTH - GlassConfig.LINK_MIN_WIDTH) * fraction
	end

	local beamCount = #parts.beams
	local pixelCount = #parts.pixelFrames
	local packetCount = #parts.packets
	local parked = GlassConfig.PACKET_PARK_POSITION

	local view: GlassView = {
		parts = parts,
		model = model,
		reducedMotion = false,

		history = history,
		historyHead = 1,
		targets = targets,
		targetIdle = targetIdle,
		displayed = perNeuron(0),
		shownOrbLevel = perNeuron(-1),
		phases = phases,

		orbColors = orbColors,
		orbSizes = orbSizes,
		pixelColors = pixelColors,
		positiveLinkColor = ColorSequence.new(GlassConfig.POSITIVE_COLOR),
		negativeLinkColor = ColorSequence.new(GlassConfig.NEGATIVE_COLOR),
		linkTransparency = linkTransparency,
		linkWidths = linkWidths,

		shownPixelLevel = table.create(pixelCount, 0),
		beamSign = table.create(beamCount, 0),
		beamLevel = table.create(beamCount, 0),
		beamSource = table.create(beamCount),
		beamTarget = table.create(beamCount),
		edgeCount = 0,
		edgeFrom = table.create(beamCount, parked),
		edgeTo = table.create(beamCount, parked),
		edgeRate = table.create(beamCount, 0),
		edgeSpawnCredit = table.create(beamCount, 0),
		edgeIsNegative = table.create(beamCount, false),

		activePackets = 0,
		freePackets = table.clone(parts.packets),
		freePacketCount = packetCount,
		movingParts = table.create(packetCount),
		movingCFrames = table.create(packetCount),
		packetFrom = table.create(packetCount, parked),
		packetTo = table.create(packetCount, parked),
		packetProgress = table.create(packetCount, 0),
		idlePacketCredit = 0,

		winner = -1,
		lastStepSeconds = 0,
		elapsed = 0,
	}

	RunService.PreRender:Connect(function(dt: number)
		step(view, dt)
	end)
	return view
end

local function showPixels(view: GlassView, input: { number }, isEmpty: boolean)
	local frames = view.parts.pixelFrames
	local shown = view.shownPixelLevel
	local colors = view.pixelColors
	local top = GlassConfig.PIXEL_LEVELS - 1
	for i = 1, #frames do
		local level = if isEmpty then 0 else floor(input[i] * top + 0.5)
		if level ~= shown[i] then
			shown[i] = level
			frames[i].BackgroundColor3 = colors[level + 1]
		end
	end
end

local function showLinks(view: GlassView, result: Inference.Inference)
	local parts = view.parts
	local beams = parts.beams
	local edges = result.edges
	local count = result.edgeCount
	local levels = GlassConfig.LINK_LEVELS

	for k = 1, count do
		local l = edges.layer[k]
		local src = edges.src[k]
		local dst = edges.dst[k]
		local normalized = edges.normalized[k]
		local magnitude = if normalized < 0 then -normalized else normalized
		local isNegative = normalized < 0

		local source: Attachment
		if l == 1 then
			source = parts.pixelAttachments[k]
			source.Position = parts.pixelLocalPositions[src]
			view.edgeFrom[k] = parts.pixelPositions[src]
		else
			source = parts.orbAttachments[l - 1][src]
			view.edgeFrom[k] = parts.orbPositions[l - 1][src]
		end
		local target = parts.orbAttachments[l][dst]
		view.edgeTo[k] = parts.orbPositions[l][dst]
		view.edgeRate[k] = magnitude
		view.edgeIsNegative[k] = isNegative

		local beam = beams[k]
		if view.beamSource[k] ~= source then
			view.beamSource[k] = source
			beam.Attachment0 = source
		end
		if view.beamTarget[k] ~= target then
			view.beamTarget[k] = target
			beam.Attachment1 = target
		end

		local level = floor(magnitude * (levels - 1) + 0.5) + 1
		local sign = if isNegative then -1 else 1
		if sign ~= view.beamSign[k] then
			view.beamSign[k] = sign
			beam.Color = if isNegative then view.negativeLinkColor else view.positiveLinkColor
		end
		if level ~= view.beamLevel[k] then
			view.beamLevel[k] = level
			beam.Transparency = view.linkTransparency[level]
			local width = view.linkWidths[level]
			beam.Width0 = width
			beam.Width1 = width
		end
		if not beam.Enabled then
			beam.Enabled = true
		end
	end
	for k = count + 1, view.edgeCount do
		beams[k].Enabled = false
	end
	view.edgeCount = count
end

local function showWinner(view: GlassView, digit: number, probability: number)
	local parts = view.parts
	local rows = parts.outputRows
	if digit ~= view.winner then
		if view.winner >= 0 then
			rows[view.winner + 1].fill.BackgroundColor3 = GlassConfig.BAR_COLOR
		end
		view.winner = digit
		if digit >= 0 then
			rows[digit + 1].fill.BackgroundColor3 = GlassConfig.WINNER_BAR_COLOR
			local positions = parts.orbPositions[#parts.orbPositions]
			parts.halo.CFrame = CFrame.new(positions[digit + 1])
		else
			parts.halo.CFrame = CFrame.new(GlassConfig.PACKET_PARK_POSITION)
		end
	end
	local text = if digit >= 0 then `{digit} · {floor(probability * 100 + 0.5)}%` else ""
	if parts.winnerLabel.Text ~= text then
		parts.winnerLabel.Text = text
	end
end

-- Takes a finished inference. The input and links show at once; neurons follow through the snapshots.
function GlassView.setResult(view: GlassView, result: Inference.Inference)
	local isOk = result.status == "ok"
	local size = #view.history
	local head = view.historyHead % size + 1
	view.historyHead = head
	local snapshot = view.history[head]
	snapshot.time = clock()
	snapshot.isIdle = not isOk

	local layers = view.model.layers
	local layerCount = #layers
	for l = 1, layerCount do
		local values = snapshot.values[l]
		-- Output orbs show probability, which reads better than a scaled logit.
		local source = if l == layerCount then result.scratch.probs else result.scratch.acts[l]
		local scales = layers[l].actScale
		for n = 1, #values do
			local value = 0
			if isOk then
				value = if l == layerCount then source[n] else source[n] / scales[n]
				if value > 1 then
					value = 1
				elseif value < 0 then
					value = 0
				end
			end
			values[n] = value
		end
	end

	showPixels(view, result.input, not isOk)
	showLinks(view, result)
	if isOk then
		showWinner(view, result.topDigits[1], result.topProbs[1])
	else
		showWinner(view, -1, 0)
	end
end

function GlassView.instanceCount(view: GlassView): number
	return #view.parts.root:GetDescendants() + 1
end

return GlassView
