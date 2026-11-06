--!strict
local Golden = require("./lib/Golden")
local TestKit = require("./lib/TestKit")
local Base64 = require("../src/shared/NeuralCore/Base64")
local Explain = require("../src/shared/NeuralCore/Explain")
local Model = require("../src/shared/NeuralCore/Model")
local ModelData = require("../src/shared/NeuralCore/ModelData")
local Preprocess = require("../src/shared/NeuralCore/Preprocess")
local Strokes = require("../src/shared/NeuralCore/Strokes")

local LOGIT_TOLERANCE = 1e-6
local MAX_RUNS_WITH_RUNTIME_ALLOCATION = 3

local function tinyModelData(weights: { number }, biases: { number }): Model.ModelData
	local bytes = buffer.create(#weights)
	for i, weight in weights do
		buffer.writei8(bytes, i - 1, weight)
	end
	return {
		formatVersion = 1,
		modelVersion = "tiny",
		layers = {
			{
				inSize = 2,
				outSize = #biases,
				activation = "softmax",
				weights = Base64.encode(bytes),
				scales = table.create(#biases, 1),
				biases = biases,
				actScale = table.create(#biases, 1),
			},
		},
	}
end

return function(kit: TestKit.TestKit)
	local model = Model.load(ModelData)
	local scratch = Model.newScratch(model)

	kit.test("goldens were generated for this model", function()
		kit.equal(Golden.load("mnist").modelVersion, ModelData.modelVersion, "mnist")
		kit.equal(Golden.load("strokes").modelVersion, ModelData.modelVersion, "strokes")
	end)

	kit.test("logits match Python on the MNIST goldens", function()
		local golden = Golden.load("mnist")
		assert(#golden.cases > 0, "no MNIST golden cases")
		local logits = scratch.acts[#scratch.acts]
		local correct = 0
		for index, case in golden.cases do
			local top, pTop = Model.forward(model, Golden.floats(case.input), scratch)
			kit.equal(top, case.top, `case {index} argmax`)
			kit.equal(pTop, scratch.probs[top + 1], `case {index} probability`)
			local expected = Golden.floats(case.logits)
			for o = 1, #expected do
				kit.near(logits[o], expected[o], LOGIT_TOLERANCE, `case {index} logit {o}`)
			end
			if top == case.label then
				correct += 1
			end
		end
		assert(correct >= #golden.cases - 2, `only {correct} of {#golden.cases} MNIST cases are right`)
	end)

	kit.test("the whole Luau path matches Python on the stroke goldens", function()
		local golden = Golden.load("strokes")
		local params = ModelData.preprocess
		local preprocessScratch = Preprocess.newScratch()
		local input = Preprocess.newOutput(params)
		local logits = scratch.acts[#scratch.acts]
		for _, case in golden.cases do
			local strokes = Strokes.decode(Golden.bytes(case.strokes))
			assert(strokes ~= nil, "strokes did not decode")
			Preprocess.run(params, strokes, preprocessScratch, input)
			local top = Model.forward(model, input, scratch)
			kit.equal(top, case.top, `{case.name} argmax`)
			local expected = Golden.floats(case.logits)
			for o = 1, #expected do
				kit.near(logits[o], expected[o], LOGIT_TOLERANCE, `{case.name} logit {o}`)
			end
		end
	end)

	kit.test("probabilities are a distribution", function()
		local golden = Golden.load("mnist")
		Model.forward(model, Golden.floats(golden.cases[1].input), scratch)
		local sum = 0
		for _, p in scratch.probs do
			assert(p >= 0 and p <= 1, "probability out of range")
			sum += p
		end
		kit.near(sum, 1, 1e-12, "sum")
	end)

	kit.test("argmax ties go to the lowest index", function()
		local tiny = Model.load(tinyModelData({ 0, 0, 0, 0, 0, 0 }, { 1, 5, 5 }))
		local top, pTop = Model.forward(tiny, { 0, 0 }, Model.newScratch(tiny))
		kit.equal(top, 1, "tie")
		assert(pTop > 0.49 and pTop < 0.5, "tied probability")
	end)

	kit.test("weights are read input-major with signed bytes and per-neuron scales", function()
		local data = tinyModelData({ 1, -2, 3, 4 }, { 0, 0 })
		data.layers[1].scales = { 0.5, 2 }
		local tiny = Model.load(data)
		local tinyScratch = Model.newScratch(tiny)
		Model.forward(tiny, { 1, 0 }, tinyScratch)
		kit.equal(tinyScratch.acts[1][1], 0.5, "input 1 -> output 1")
		kit.equal(tinyScratch.acts[1][2], -4, "input 1 -> output 2")
		Model.forward(tiny, { 0, 1 }, tinyScratch)
		kit.equal(tinyScratch.acts[1][1], 1.5, "input 2 -> output 1")
		kit.equal(tinyScratch.acts[1][2], 8, "input 2 -> output 2")
	end)

	kit.test("load rejects a bad format or weight shape", function()
		local wrongFormat = tinyModelData({ 0, 0 }, { 0 })
		wrongFormat.formatVersion = 2
		kit.equal(pcall(Model.load, wrongFormat), false, "format")
		kit.equal(pcall(Model.load, tinyModelData({ 0 }, { 0 })), false, "shape")
	end)

	kit.test("preprocess, forward, and explain allocate nothing once warmed up", function()
		local golden = Golden.load("strokes")
		local params = ModelData.preprocess
		local preprocessScratch = Preprocess.newScratch()
		local input = Preprocess.newOutput(params)
		local edges = Explain.newEdges(model)
		local strokes = Strokes.decode(Golden.bytes(golden.cases[1].strokes))
		assert(strokes ~= nil, "strokes did not decode")

		for _ = 1, 3 do
			Preprocess.run(params, strokes, preprocessScratch, input)
			Model.forward(model, input, scratch)
			Explain.selectEdges(model, input, scratch, edges)
		end
		-- The runtime occasionally makes a one-off allocation of its own during a run, so allow a few.
		-- Our code allocating per inference would grow on nearly every run.
		local runs = 200
		local runsThatGrew = 0
		for _ = 1, runs do
			local before = collectgarbage("count")
			Preprocess.run(params, strokes, preprocessScratch, input)
			Model.forward(model, input, scratch)
			Explain.selectEdges(model, input, scratch, edges)
			if collectgarbage("count") > before then
				runsThatGrew += 1
			end
		end
		assert(runsThatGrew <= MAX_RUNS_WITH_RUNTIME_ALLOCATION, `{runsThatGrew} of {runs} runs allocated`)
	end)
end
