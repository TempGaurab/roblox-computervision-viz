--!strict
-- Runs the model on the current drawing: only when it has changed, and at a limited rate. Everything
-- is preallocated, so an inference creates no tables.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Model = require(ReplicatedStorage.Shared.NeuralCore.Model)
local ModelData = require(ReplicatedStorage.Shared.NeuralCore.ModelData)
local Preprocess = require(ReplicatedStorage.Shared.NeuralCore.Preprocess)
local Strokes = require(ReplicatedStorage.Shared.NeuralCore.Strokes)

local clock = os.clock

export type Status = "empty" | "tooSmall" | "ok"

export type Inference = {
	model: Model.Model,
	scratch: Model.Scratch,
	preprocessScratch: Preprocess.Scratch,
	input: { number },
	status: Status,
	isDirty: boolean,
	lastRunAt: number,
	lastSeconds: number,
	runCount: number,
	topDigits: { number },
	topProbs: { number },
}

local Inference = {}

function Inference.new(): Inference
	local model = Model.load(ModelData)
	local topCount = Config.Hud.TOP_COUNT
	return {
		model = model,
		scratch = Model.newScratch(model),
		preprocessScratch = Preprocess.newScratch(),
		input = Preprocess.newOutput(ModelData.preprocess),
		status = "empty",
		isDirty = false,
		lastRunAt = -math.huge,
		lastSeconds = 0,
		runCount = 0,
		topDigits = table.create(topCount, 0),
		topProbs = table.create(topCount, 0),
	}
end

function Inference.markDirty(inference: Inference)
	inference.isDirty = true
end

-- Fills topDigits and topProbs, best first. Ties keep the lower digit first.
local function rankTop(inference: Inference)
	local probs = inference.scratch.probs
	local topDigits = inference.topDigits
	local topProbs = inference.topProbs
	local topCount = #topDigits
	for k = 1, topCount do
		topProbs[k] = -1
	end
	for o = 1, #probs do
		local p = probs[o]
		if p > topProbs[topCount] then
			local slot = topCount
			while slot > 1 and topProbs[slot - 1] < p do
				topDigits[slot] = topDigits[slot - 1]
				topProbs[slot] = topProbs[slot - 1]
				slot -= 1
			end
			topDigits[slot] = o - 1
			topProbs[slot] = p
		end
	end
end

-- Runs now, regardless of the rate limit.
function Inference.run(inference: Inference, strokes: Strokes.Strokes)
	local started = clock()
	inference.isDirty = false
	inference.lastRunAt = started
	inference.runCount += 1
	if strokes.pointCount == 0 then
		inference.status = "empty"
	elseif Preprocess.run(ModelData.preprocess, strokes, inference.preprocessScratch, inference.input) then
		Model.forward(inference.model, inference.input, inference.scratch)
		rankTop(inference)
		inference.status = "ok"
	else
		inference.status = "tooSmall"
	end
	inference.lastSeconds = clock() - started
end

-- Call once per frame. Returns true when it ran, so the caller knows to refresh what it shows.
function Inference.step(inference: Inference, strokes: Strokes.Strokes): boolean
	if not inference.isDirty or clock() - inference.lastRunAt < Config.Inference.MIN_INTERVAL then
		return false
	end
	Inference.run(inference, strokes)
	return true
end

return Inference
