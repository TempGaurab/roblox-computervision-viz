--!strict
-- Owns the player's drawing: captures input into Strokes, keeps the ink in step, and reports changes.
-- Nothing here replicates. Strokes only leave this client through an explicit Submit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Strokes = require(ReplicatedStorage.Shared.NeuralCore.Strokes)
local Cleanup = require(script.Parent.Parent.Cleanup)
local Ink = require(script.Parent.Ink)
local PadInput = require(script.Parent.PadInput)
local PadView = require(script.Parent.PadView)

export type Callbacks = {
	onChanged: () -> (),
	onLimit: () -> (),
	onSubmit: () -> (),
	onExit: () -> (),
}

export type Pad = {
	view: PadView.PadView,
	ink: Ink.Ink,
	strokes: Strokes.Strokes,
	callbacks: Callbacks,
	inputCleanup: Cleanup.Cleanup,
	isDrawing: boolean,
	limitReached: boolean,
	lastX: number,
	lastY: number,
}

local Pad = {}

local function unitOf(coordinate: number): number
	return coordinate / Strokes.COORD_MAX
end

local function reachedLimit(pad: Pad)
	pad.isDrawing = false
	if not pad.limitReached then
		pad.limitReached = true
		pad.callbacks.onLimit()
	end
end

local function beginStroke(pad: Pad, x: number, y: number)
	local quantizedX = Strokes.quantize(x)
	local quantizedY = Strokes.quantize(y)
	if not Strokes.beginStroke(pad.strokes, quantizedX, quantizedY) then
		reachedLimit(pad)
		return
	end
	Ink.addPoint(pad.ink, unitOf(quantizedX), unitOf(quantizedY), true)
	pad.isDrawing = true
	pad.lastX = x
	pad.lastY = y
	pad.callbacks.onChanged()
end

local function extendStroke(pad: Pad, x: number, y: number)
	if not pad.isDrawing then
		return
	end
	local dx = x - pad.lastX
	local dy = y - pad.lastY
	local minDistance = Config.Pad.MIN_POINT_DISTANCE
	if dx * dx + dy * dy < minDistance * minDistance then
		return
	end
	local quantizedX = Strokes.quantize(x)
	local quantizedY = Strokes.quantize(y)
	if not Strokes.addPoint(pad.strokes, quantizedX, quantizedY) then
		reachedLimit(pad)
		return
	end
	Ink.addPoint(pad.ink, unitOf(quantizedX), unitOf(quantizedY), false)
	pad.lastX = x
	pad.lastY = y
	pad.callbacks.onChanged()
end

local function endStroke(pad: Pad)
	pad.isDrawing = false
end

function Pad.new(callbacks: Callbacks): Pad
	local view = PadView.new()
	local ink = Ink.new(view.inkLayer)
	view.inkLayer.Parent = view.surface

	local pad: Pad = {
		view = view,
		ink = ink,
		strokes = Strokes.new(),
		callbacks = callbacks,
		inputCleanup = Cleanup.new(),
		isDrawing = false,
		limitReached = false,
		lastX = 0,
		lastY = 0,
	}

	view.clearButton.Activated:Connect(function()
		Pad.clear(pad)
	end)
	view.undoButton.Activated:Connect(function()
		Pad.undo(pad)
	end)
	view.submitButton.Activated:Connect(function()
		callbacks.onSubmit()
	end)
	view.exitButton.Activated:Connect(function()
		callbacks.onExit()
	end)
	return pad
end

function Pad.open(pad: Pad, showSubmit: boolean)
	PadInput.connect(pad.view.surface, {
		onBegin = function(x: number, y: number)
			beginStroke(pad, x, y)
		end,
		onMove = function(x: number, y: number)
			extendStroke(pad, x, y)
		end,
		onEnd = function()
			endStroke(pad)
		end,
	}, pad.inputCleanup)
	PadView.open(pad.view, showSubmit)
end

function Pad.close(pad: Pad)
	Cleanup.run(pad.inputCleanup)
	PadView.close(pad.view)
end

function Pad.clear(pad: Pad)
	Strokes.clear(pad.strokes)
	Ink.trim(pad.ink, 0, 0)
	pad.isDrawing = false
	pad.limitReached = false
	pad.callbacks.onChanged()
end

function Pad.undo(pad: Pad)
	if pad.isDrawing or not Strokes.undo(pad.strokes) then
		return
	end
	Ink.trim(pad.ink, pad.strokes.pointCount, pad.strokes.strokeCount)
	pad.limitReached = false
	pad.callbacks.onChanged()
end

-- Replaces the drawing, with the ink to match. Used by the Studio-only Dev harness.
function Pad.load(pad: Pad, source: Strokes.Strokes)
	Pad.clear(pad)
	local first = 1
	for s = 1, source.strokeCount do
		local last = source.strokeEnds[s]
		for i = first, last do
			local x = source.xs[i]
			local y = source.ys[i]
			if i == first then
				Strokes.beginStroke(pad.strokes, x, y)
			else
				Strokes.addPoint(pad.strokes, x, y)
			end
			Ink.addPoint(pad.ink, unitOf(x), unitOf(y), i == first)
		end
		first = last + 1
	end
	pad.callbacks.onChanged()
end

return Pad
