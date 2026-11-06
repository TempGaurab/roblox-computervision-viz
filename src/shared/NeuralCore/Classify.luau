--!strict
-- The whole pipeline from a Submit payload to a digit, as the server runs it. The decoded strokes are
-- local to run() and dropped when it returns: nothing here stores, logs, or forwards them (Rule 4).

local Model = require("./Model")
local Preprocess = require("./Preprocess")
local Strokes = require("./Strokes")

export type Status = "ok" | "malformed" | "unreadable"

export type Classifier = {
	params: Preprocess.Params,
	model: Model.Model,
	scratch: Model.Scratch,
	preprocessScratch: Preprocess.Scratch,
	input: { number },
}

local Classify = {}

function Classify.new(data: Model.ModelData, params: Preprocess.Params): Classifier
	local model = Model.load(data)
	return {
		params = params,
		model = model,
		scratch = Model.newScratch(model),
		preprocessScratch = Preprocess.newScratch(),
		input = Preprocess.newOutput(params),
	}
end

-- Returns the status, the digit (-1 unless ok), and its probability.
function Classify.run(classifier: Classifier, payload: buffer): (Status, number, number)
	local strokes = Strokes.decode(payload)
	if strokes == nil then
		return "malformed", -1, 0
	end
	if not Preprocess.run(classifier.params, strokes, classifier.preprocessScratch, classifier.input) then
		return "unreadable", -1, 0
	end
	local top, pTop = Model.forward(classifier.model, classifier.input, classifier.scratch)
	return "ok", top, pTop
end

return Classify
