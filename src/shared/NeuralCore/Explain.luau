--!strict
-- Picks which links the Glass shows, as contributions a_src * w. Reads the activations left by
-- Model.forward and writes only into preallocated arrays. Every selection is by descending magnitude;
-- ties break toward the lower source index, then the lower destination.

local ModelModule = require("./Model")

type Model = ModelModule.Model
type Scratch = ModelModule.Scratch

export type Edges = {
	layer: { number }, -- index of the model layer the link feeds
	src: { number }, -- 1-based index into the input (layer 1) or the previous layer's acts
	dst: { number }, -- 1-based index into this layer's acts
	value: { number }, -- signed contribution
	normalized: { number }, -- value / this layer's largest |value|, so within [-1, 1]

	-- Working storage, reused by every call.
	topNeurons: { number },
	topNeuronActs: { number },
	pickedSrc: { number },
	pickedDst: { number },
	pickedValue: { number },
	pickedMagnitude: { number },
	isForced: { boolean },
	nonZeroPixels: { number },
}

local INPUT_TOP_NEURONS = 16
local INPUT_LINKS_PER_NEURON = 6
local HIDDEN_LINKS = 96
local OUTPUT_LINKS = 64
local OUTPUT_FORCED_LINKS = 8

local Explain = {
	INPUT_TOP_NEURONS = INPUT_TOP_NEURONS,
	INPUT_LINKS_PER_NEURON = INPUT_LINKS_PER_NEURON,
	HIDDEN_LINKS = HIDDEN_LINKS,
	OUTPUT_LINKS = OUTPUT_LINKS,
	OUTPUT_FORCED_LINKS = OUTPUT_FORCED_LINKS,
}

function Explain.maxEdges(model: Model): number
	local hiddenLayers = #model.layers - 2
	return INPUT_TOP_NEURONS * INPUT_LINKS_PER_NEURON + hiddenLayers * HIDDEN_LINKS + OUTPUT_LINKS
end

function Explain.newEdges(model: Model): Edges
	local capacity = Explain.maxEdges(model)
	local pickCapacity = math.max(INPUT_LINKS_PER_NEURON, HIDDEN_LINKS, OUTPUT_LINKS)
	local lastLayer = model.layers[#model.layers]
	return {
		layer = table.create(capacity, 0),
		src = table.create(capacity, 0),
		dst = table.create(capacity, 0),
		value = table.create(capacity, 0),
		normalized = table.create(capacity, 0),
		topNeurons = table.create(INPUT_TOP_NEURONS, 0),
		topNeuronActs = table.create(INPUT_TOP_NEURONS, 0),
		pickedSrc = table.create(pickCapacity, 0),
		pickedDst = table.create(pickCapacity, 0),
		pickedValue = table.create(pickCapacity, 0),
		pickedMagnitude = table.create(pickCapacity, 0),
		isForced = table.create(lastLayer.inSize, false),
		nonZeroPixels = table.create(model.layers[1].inSize, 0),
	}
end

-- Inserts into the picks, kept sorted by descending magnitude. Candidates arrive in index order, so
-- an equal magnitude lands after existing picks, which keeps ties on the lower index. Returns the
-- new pick count. The caller has already checked that the candidate beats the current last pick.
local function insertPick(
	edges: Edges,
	first: number,
	count: number,
	capacity: number,
	src: number,
	dst: number,
	value: number,
	magnitude: number
): number
	local pickedSrc = edges.pickedSrc
	local pickedDst = edges.pickedDst
	local pickedValue = edges.pickedValue
	local pickedMagnitude = edges.pickedMagnitude

	local newCount = if count < capacity then count + 1 else count
	local slot = first + newCount - 1
	while slot > first and pickedMagnitude[slot - 1] < magnitude do
		pickedSrc[slot] = pickedSrc[slot - 1]
		pickedDst[slot] = pickedDst[slot - 1]
		pickedValue[slot] = pickedValue[slot - 1]
		pickedMagnitude[slot] = pickedMagnitude[slot - 1]
		slot -= 1
	end
	pickedSrc[slot] = src
	pickedDst[slot] = dst
	pickedValue[slot] = value
	pickedMagnitude[slot] = magnitude
	return newCount
end

local function appendPicks(edges: Edges, layer: number, cursor: number, count: number): number
	local largest = 0
	local pickedValue = edges.pickedValue
	for k = 1, count do
		local value = pickedValue[k]
		local magnitude = if value < 0 then -value else value
		if magnitude > largest then
			largest = magnitude
		end
	end
	for k = 1, count do
		local index = cursor + k
		edges.layer[index] = layer
		edges.src[index] = edges.pickedSrc[k]
		edges.dst[index] = edges.pickedDst[k]
		edges.value[index] = pickedValue[k]
		edges.normalized[index] = pickedValue[k] / largest
	end
	return cursor + count
end

-- The most active neurons of layer 1, each with its strongest positive pixel contributions.
local function selectInputEdges(model: Model, input: { number }, scratch: Scratch, edges: Edges): number
	local layer = model.layers[1]
	local acts = scratch.acts[1]
	local topNeurons = edges.topNeurons
	local topNeuronActs = edges.topNeuronActs

	local neuronCount = 0
	for o = 1, layer.outSize do
		local act = acts[o]
		if act > 0 and (neuronCount < INPUT_TOP_NEURONS or act > topNeuronActs[neuronCount]) then
			if neuronCount < INPUT_TOP_NEURONS then
				neuronCount += 1
			end
			local slot = neuronCount
			while slot > 1 and topNeuronActs[slot - 1] < act do
				topNeurons[slot] = topNeurons[slot - 1]
				topNeuronActs[slot] = topNeuronActs[slot - 1]
				slot -= 1
			end
			topNeurons[slot] = o
			topNeuronActs[slot] = act
		end
	end

	local nonZeroPixels = edges.nonZeroPixels
	local nonZeroCount = 0
	for i = 1, layer.inSize do
		if input[i] ~= 0 then
			nonZeroCount += 1
			nonZeroPixels[nonZeroCount] = i
		end
	end

	local weights = layer.weights
	local outSize = layer.outSize
	local pickedMagnitude = edges.pickedMagnitude
	local cursor = 0
	local largest = 0
	for n = 1, neuronCount do
		local o = topNeurons[n]
		local count = 0
		for p = 1, nonZeroCount do
			local pixel = nonZeroPixels[p]
			local value = input[pixel] * weights[(pixel - 1) * outSize + o]
			if value > 0 and (count < INPUT_LINKS_PER_NEURON or value > pickedMagnitude[count]) then
				count = insertPick(edges, 1, count, INPUT_LINKS_PER_NEURON, pixel, o, value, value)
			end
		end
		if count > 0 and pickedMagnitude[1] > largest then
			largest = pickedMagnitude[1]
		end
		for k = 1, count do
			local index = cursor + k
			edges.layer[index] = 1
			edges.src[index] = edges.pickedSrc[k]
			edges.dst[index] = o
			edges.value[index] = edges.pickedValue[k]
		end
		cursor += count
	end
	for index = 1, cursor do
		edges.normalized[index] = edges.value[index] / largest
	end
	return cursor
end

-- The strongest source -> destination pairs of a later layer, by |a * w|.
local function selectPairs(
	model: Model,
	scratch: Scratch,
	edges: Edges,
	l: number,
	first: number,
	capacity: number,
	skipForcedDst: number
): number
	local layer = model.layers[l]
	local sourceActs = scratch.acts[l - 1]
	local weights = layer.weights
	local outSize = layer.outSize
	local pickedMagnitude = edges.pickedMagnitude
	local isForced = edges.isForced

	local count = 0
	for i = 0, layer.inSize - 1 do
		local act = sourceActs[i + 1]
		if act ~= 0 then
			local base = i * outSize
			local forced = isForced[i + 1]
			for o = 1, outSize do
				local value = act * weights[base + o]
				local magnitude = if value < 0 then -value else value
				if
					magnitude > 0
					and (count < capacity or magnitude > pickedMagnitude[first + count - 1])
					and not (forced and o == skipForcedDst)
				then
					count = insertPick(edges, first, count, capacity, i + 1, o, value, magnitude)
				end
			end
		end
	end
	return count
end

-- Fills `edges` and returns how many links to show. Call after Model.forward with the same scratch.
function Explain.selectEdges(model: Model, input: { number }, scratch: Scratch, edges: Edges): number
	local cursor = selectInputEdges(model, input, scratch, edges)

	local layerCount = #model.layers
	for l = 2, layerCount - 1 do
		local count = selectPairs(model, scratch, edges, l, 1, HIDDEN_LINKS, 0)
		cursor = appendPicks(edges, l, cursor, count)
	end

	-- Output layer: the largest positive contributors to the predicted digit always appear, and the
	-- remaining slots go to the strongest pairs overall.
	local outputLayer = model.layers[layerCount]
	local topDst = scratch.top + 1
	local sourceActs = scratch.acts[layerCount - 1]
	local isForced = edges.isForced
	local pickedMagnitude = edges.pickedMagnitude
	local forcedCount = 0
	for i = 0, outputLayer.inSize - 1 do
		isForced[i + 1] = false
		local value = sourceActs[i + 1] * outputLayer.weights[i * outputLayer.outSize + topDst]
		if value > 0 and (forcedCount < OUTPUT_FORCED_LINKS or value > pickedMagnitude[forcedCount]) then
			forcedCount = insertPick(edges, 1, forcedCount, OUTPUT_FORCED_LINKS, i + 1, topDst, value, value)
		end
	end
	for k = 1, forcedCount do
		isForced[edges.pickedSrc[k]] = true
	end
	local restCount =
		selectPairs(model, scratch, edges, layerCount, forcedCount + 1, OUTPUT_LINKS - forcedCount, topDst)
	return appendPicks(edges, layerCount, cursor, forcedCount + restCount)
end

return Explain
