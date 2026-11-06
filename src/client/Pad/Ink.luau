--!strict
-- Draws strokes with pooled Frames: a round joint per point and a rotated segment between points.
-- Sizes and positions are in scale, and the pad is square, so ink follows any pad resize untouched.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Strokes = require(ReplicatedStorage.Shared.NeuralCore.Strokes)

local atan2 = math.atan2
local deg = math.deg
local sqrt = math.sqrt

export type Ink = {
	joints: { Frame },
	segments: { Frame },
	jointCount: number,
	segmentCount: number,
	lastX: number,
	lastY: number,
}

local Ink = {}

local function newInkFrame(parent: Instance, name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Config.Pad.INK_COLOR
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parent
	return frame
end

-- Builds the whole pool up front, while `layer` is not yet parented, so drawing never creates instances.
function Ink.new(layer: Instance): Ink
	local capacity = Strokes.MAX_POINTS
	local thickness = Config.Pad.INK_THICKNESS
	local jointSize = UDim2.fromScale(thickness, thickness)
	local jointRadius = UDim.new(0.5, 0)

	local joints: { Frame } = table.create(capacity)
	local segments: { Frame } = table.create(capacity)
	for i = 1, capacity do
		local joint = newInkFrame(layer, "Joint")
		joint.Size = jointSize
		local corner = Instance.new("UICorner")
		corner.CornerRadius = jointRadius
		corner.Parent = joint
		joints[i] = joint
		segments[i] = newInkFrame(layer, "Segment")
	end

	return { joints = joints, segments = segments, jointCount = 0, segmentCount = 0, lastX = 0, lastY = 0 }
end

-- Draws one point, in unit pad space, joined to the previous point unless it starts a stroke.
function Ink.addPoint(ink: Ink, x: number, y: number, startsStroke: boolean)
	if not startsStroke then
		local dx = x - ink.lastX
		local dy = y - ink.lastY
		local segmentCount = ink.segmentCount + 1
		local segment = ink.segments[segmentCount]
		segment.Position = UDim2.fromScale(ink.lastX + dx / 2, ink.lastY + dy / 2)
		segment.Size = UDim2.fromScale(sqrt(dx * dx + dy * dy), Config.Pad.INK_THICKNESS)
		segment.Rotation = deg(atan2(dy, dx))
		segment.Visible = true
		ink.segmentCount = segmentCount
	end

	local jointCount = ink.jointCount + 1
	local joint = ink.joints[jointCount]
	joint.Position = UDim2.fromScale(x, y)
	joint.Visible = true
	ink.jointCount = jointCount
	ink.lastX = x
	ink.lastY = y
end

-- Hides everything past the given counts. Each point has a joint; each stroke has one segment fewer than points.
function Ink.trim(ink: Ink, pointCount: number, strokeCount: number)
	local segmentCount = pointCount - strokeCount
	for i = pointCount + 1, ink.jointCount do
		ink.joints[i].Visible = false
	end
	for i = segmentCount + 1, ink.segmentCount do
		ink.segments[i].Visible = false
	end
	ink.jointCount = pointCount
	ink.segmentCount = segmentCount
end

return Ink
