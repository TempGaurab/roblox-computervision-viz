--!strict
local Golden = require("./lib/Golden")
local TestKit = require("./lib/TestKit")
local Base64 = require("../src/shared/NeuralCore/Base64")
local Explain = require("../src/shared/NeuralCore/Explain")
local Model = require("../src/shared/NeuralCore/Model")
local ModelData = require("../src/shared/NeuralCore/ModelData")

type Candidate = { src: number, dst: number, value: number }

-- Brute force: sorts by descending magnitude, then lower src, then lower dst.
local function ranked(candidates: { Candidate }): { Candidate }
	table.sort(candidates, function(a: Candidate, b: Candidate): boolean
		local magnitudeA, magnitudeB = math.abs(a.value), math.abs(b.value)
		if magnitudeA ~= magnitudeB then
			return magnitudeA > magnitudeB
		elseif a.src ~= b.src then
			return a.src < b.src
		end
		return a.dst < b.dst
	end)
	return candidates
end

local function edgeKey(src: number, dst: number): string
	return `{src}>{dst}`
end

local function keysInLayer(edges: Explain.Edges, count: number, layer: number): { [string]: number }
	local keys: { [string]: number } = {}
	for k = 1, count do
		if edges.layer[k] == layer then
			keys[edgeKey(edges.src[k], edges.dst[k])] = edges.value[k]
		end
	end
	return keys
end

return function(kit: TestKit.TestKit)
	local model = Model.load(ModelData)
	local scratch = Model.newScratch(model)
	local edges = Explain.newEdges(model)
	local cases = Golden.load("mnist").cases

	kit.test("the real model allows at most 256 links", function()
		kit.equal(Explain.maxEdges(model), 256, "capacity")
	end)

	kit.test("edges are within the per-layer caps and normalized", function()
		for _, case in cases do
			local input = Golden.floats(case.input)
			Model.forward(model, input, scratch)
			local count = Explain.selectEdges(model, input, scratch, edges)
			assert(count > 0 and count <= 256, `{count} edges`)

			local perLayer = { 0, 0, 0 }
			local largest = { 0, 0, 0 }
			for k = 1, count do
				local layer = edges.layer[k]
				perLayer[layer] += 1
				largest[layer] = math.max(largest[layer], math.abs(edges.value[k]))
				kit.equal(
					edges.normalized[k] >= -1 and edges.normalized[k] <= 1,
					true,
					`normalized edge {k}: {edges.normalized[k]}`
				)
			end
			assert(perLayer[1] <= 96 and perLayer[2] <= 96 and perLayer[3] <= 64, "over a layer cap")
			for k = 1, count do
				kit.near(edges.normalized[k], edges.value[k] / largest[edges.layer[k]], 1e-15, `edge {k}`)
			end
		end
	end)

	kit.test("input links match a brute-force selection", function()
		local layer = model.layers[1]
		for _, case in cases do
			local input = Golden.floats(case.input)
			Model.forward(model, input, scratch)
			local count = Explain.selectEdges(model, input, scratch, edges)

			local neurons: { Candidate } = {}
			for o = 1, layer.outSize do
				if scratch.acts[1][o] > 0 then
					table.insert(neurons, { src = o, dst = 0, value = scratch.acts[1][o] })
				end
			end
			ranked(neurons)

			local expected: { [string]: number } = {}
			for n = 1, math.min(Explain.INPUT_TOP_NEURONS, #neurons) do
				local o = neurons[n].src
				local contributions: { Candidate } = {}
				for i = 0, layer.inSize - 1 do
					local value = input[i + 1] * layer.weights[i * layer.outSize + o]
					if value > 0 then
						table.insert(contributions, { src = i + 1, dst = o, value = value })
					end
				end
				ranked(contributions)
				for k = 1, math.min(Explain.INPUT_LINKS_PER_NEURON, #contributions) do
					expected[edgeKey(contributions[k].src, o)] = contributions[k].value
				end
			end

			local actual = keysInLayer(edges, count, 1)
			for key, value in expected do
				kit.equal(actual[key], value, `missing input link {key}`)
			end
			for key in actual do
				assert(expected[key] ~= nil, `unexpected input link {key}`)
			end
		end
	end)

	kit.test("hidden links are exactly the top pairs by magnitude", function()
		local layer = model.layers[2]
		for _, case in cases do
			local input = Golden.floats(case.input)
			Model.forward(model, input, scratch)
			local count = Explain.selectEdges(model, input, scratch, edges)

			local pairsList: { Candidate } = {}
			for i = 0, layer.inSize - 1 do
				for o = 1, layer.outSize do
					local value = scratch.acts[1][i + 1] * layer.weights[i * layer.outSize + o]
					if value ~= 0 then
						table.insert(pairsList, { src = i + 1, dst = o, value = value })
					end
				end
			end
			ranked(pairsList)

			local actual = keysInLayer(edges, count, 2)
			for k = 1, math.min(Explain.HIDDEN_LINKS, #pairsList) do
				local key = edgeKey(pairsList[k].src, pairsList[k].dst)
				kit.equal(actual[key], pairsList[k].value, `missing hidden link {key}`)
			end
		end
	end)

	kit.test("output links always include the top contributors to the predicted digit", function()
		local layer = model.layers[3]
		for _, case in cases do
			local input = Golden.floats(case.input)
			local top = Model.forward(model, input, scratch)
			local count = Explain.selectEdges(model, input, scratch, edges)
			local actual = keysInLayer(edges, count, 3)

			local toTop: { Candidate } = {}
			local others: { Candidate } = {}
			for i = 0, layer.inSize - 1 do
				for o = 1, layer.outSize do
					local value = scratch.acts[2][i + 1] * layer.weights[i * layer.outSize + o]
					if value ~= 0 then
						local candidate = { src = i + 1, dst = o, value = value }
						if o == top + 1 and value > 0 then
							table.insert(toTop, candidate)
						else
							table.insert(others, candidate)
						end
					end
				end
			end
			ranked(toTop)

			local forced = math.min(Explain.OUTPUT_FORCED_LINKS, #toTop)
			local expected: { [string]: number } = {}
			for k = 1, forced do
				expected[edgeKey(toTop[k].src, toTop[k].dst)] = toTop[k].value
				kit.equal(actual[edgeKey(toTop[k].src, toTop[k].dst)], toTop[k].value, "forced link")
			end
			for k = forced + 1, #toTop do
				table.insert(others, toTop[k])
			end
			ranked(others)
			for k = 1, math.min(Explain.OUTPUT_LINKS - forced, #others) do
				expected[edgeKey(others[k].src, others[k].dst)] = others[k].value
			end
			for key, value in expected do
				kit.equal(actual[key], value, `missing output link {key}`)
			end
			for key in actual do
				assert(expected[key] ~= nil, `unexpected output link {key}`)
			end
		end
	end)

	kit.test("selection is deterministic and ties go to the lower index", function()
		-- Three identical inputs to two identical neurons, then two identical outputs.
		local function encode(values: { number }): string
			local bytes = buffer.create(#values)
			for i, value in values do
				buffer.writei8(bytes, i - 1, value)
			end
			return Base64.encode(bytes)
		end
		local tiny = Model.load({
			formatVersion = 1,
			modelVersion = "tiny",
			layers = {
				{
					inSize = 8,
					outSize = 2,
					activation = "relu",
					weights = encode({ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }),
					scales = { 1, 1 },
					biases = { 0, 0 },
					actScale = { 1, 1 },
				},
				{
					inSize = 2,
					outSize = 2,
					activation = "softmax",
					weights = encode({ 1, 1, 1, 1 }),
					scales = { 1, 1 },
					biases = { 0, 0 },
					actScale = { 1, 1 },
				},
			},
		})
		local tinyScratch = Model.newScratch(tiny)
		local tinyEdges = Explain.newEdges(tiny)
		local input = { 1, 1, 1, 1, 1, 1, 1, 1 }
		Model.forward(tiny, input, tinyScratch)
		kit.equal(tinyScratch.top, 0, "tied class")
		local count = Explain.selectEdges(tiny, input, tinyScratch, tinyEdges)

		-- Each neuron keeps its first six pixels, not its last.
		for k = 1, 6 do
			kit.equal(tinyEdges.src[k], k, `pixel of edge {k}`)
			kit.equal(tinyEdges.dst[k], 1, `neuron of edge {k}`)
			kit.equal(tinyEdges.src[k + 6], k, `pixel of edge {k + 6}`)
			kit.equal(tinyEdges.dst[k + 6], 2, `neuron of edge {k + 6}`)
		end
		kit.equal(count, 12 + 4, "edge count")
		-- The forced links to class 0 come first, then the rest in index order.
		kit.equal(edgeKey(tinyEdges.src[13], tinyEdges.dst[13]), "1>1", "edge 13")
		kit.equal(edgeKey(tinyEdges.src[14], tinyEdges.dst[14]), "2>1", "edge 14")
		kit.equal(edgeKey(tinyEdges.src[15], tinyEdges.dst[15]), "1>2", "edge 15")
		kit.equal(edgeKey(tinyEdges.src[16], tinyEdges.dst[16]), "2>2", "edge 16")
	end)

	kit.test("input links only show positive contributions", function()
		local bytes = buffer.create(4)
		for i, weight in { 2, -3, 1, -1 } do
			buffer.writei8(bytes, i - 1, weight)
		end
		local outputBytes = buffer.create(1)
		buffer.writei8(outputBytes, 0, 1)
		local tiny = Model.load({
			formatVersion = 1,
			modelVersion = "tiny",
			layers = {
				{
					inSize = 4,
					outSize = 1,
					activation = "relu",
					weights = Base64.encode(bytes),
					scales = { 1 },
					biases = { 10 },
					actScale = { 1 },
				},
				{
					inSize = 1,
					outSize = 1,
					activation = "softmax",
					weights = Base64.encode(outputBytes),
					scales = { 1 },
					biases = { 0 },
					actScale = { 1 },
				},
			},
		})
		local tinyScratch = Model.newScratch(tiny)
		local tinyEdges = Explain.newEdges(tiny)
		local input = { 1, 1, 1, 1 }
		Model.forward(tiny, input, tinyScratch)
		Explain.selectEdges(tiny, input, tinyScratch, tinyEdges)
		local inputKeys = keysInLayer(tinyEdges, 3, 1)
		kit.equal(inputKeys[edgeKey(1, 1)], 2, "pixel 1")
		kit.equal(inputKeys[edgeKey(3, 1)], 1, "pixel 3")
		kit.equal(inputKeys[edgeKey(2, 1)], nil, "negative pixel 2")
		kit.equal(inputKeys[edgeKey(4, 1)], nil, "negative pixel 4")
	end)

	kit.test("stale state from a previous drawing does not leak", function()
		local first = Golden.floats(cases[1].input)
		local second = Golden.floats(cases[2].input)
		Model.forward(model, first, scratch)
		Explain.selectEdges(model, first, scratch, edges)
		Model.forward(model, second, scratch)
		local count = Explain.selectEdges(model, second, scratch, edges)

		local freshScratch = Model.newScratch(model)
		local freshEdges = Explain.newEdges(model)
		Model.forward(model, second, freshScratch)
		local freshCount = Explain.selectEdges(model, second, freshScratch, freshEdges)
		kit.equal(count, freshCount, "count")
		for k = 1, count do
			kit.equal(edges.src[k], freshEdges.src[k], `src {k}`)
			kit.equal(edges.dst[k], freshEdges.dst[k], `dst {k}`)
			kit.equal(edges.value[k], freshEdges.value[k], `value {k}`)
		end
	end)
end
