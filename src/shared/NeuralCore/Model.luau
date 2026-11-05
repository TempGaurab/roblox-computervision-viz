--!strict
-- Loads the generated model once, then runs an allocation-free forward pass. Every shape comes from
-- ModelData. Neuron and pixel indices are 1-based; the `top` that forward returns is 0-based, so it
-- is the digit itself.

local Base64 = require("./Base64")

local exp = math.exp

export type LayerData = {
	inSize: number,
	outSize: number,
	activation: string,
	weights: string,
	scales: { number },
	biases: { number },
	actScale: { number },
}

export type ModelData = {
	formatVersion: number,
	modelVersion: string,
	layers: { LayerData },
}

export type Layer = {
	inSize: number,
	outSize: number,
	isRelu: boolean,
	weights: { number }, -- input-major: weights[i * outSize + o], with 0-based i and 1-based o
	biases: { number },
	actScale: { number },
}

export type Model = {
	version: string,
	layers: { Layer },
}

export type Scratch = {
	acts: { { number } }, -- acts[layer][neuron]; the last layer holds logits
	probs: { number },
	top: number, -- the 0-based class from the latest forward
}

local FORMAT_VERSION = 1

local Model = {}

function Model.load(data: ModelData): Model
	assert(data.formatVersion == FORMAT_VERSION, "unsupported ModelData format")
	local count = #data.layers
	local layers: { Layer } = table.create(count)
	for l, layerData in data.layers do
		local inSize = layerData.inSize
		local outSize = layerData.outSize
		local isLast = l == count
		assert(layerData.activation == (if isLast then "softmax" else "relu"), "unexpected activation")

		local bytes = Base64.decode(layerData.weights)
		assert(bytes ~= nil and buffer.len(bytes) == inSize * outSize, "weights do not match the layer shape")

		local weights: { number } = table.create(inSize * outSize, 0)
		local scales = layerData.scales
		for index = 0, inSize * outSize - 1 do
			weights[index + 1] = buffer.readi8(bytes, index) * scales[index % outSize + 1]
		end

		layers[l] = {
			inSize = inSize,
			outSize = outSize,
			isRelu = not isLast,
			weights = weights,
			biases = layerData.biases,
			actScale = layerData.actScale,
		}
	end
	return { version = data.modelVersion, layers = layers }
end

function Model.newScratch(model: Model): Scratch
	local acts: { { number } } = table.create(#model.layers)
	for l, layer in model.layers do
		acts[l] = table.create(layer.outSize, 0)
	end
	return { acts = acts, probs = table.create(model.layers[#model.layers].outSize, 0), top = 0 }
end

-- Fills scratch.acts and scratch.probs. Returns the winning class (0-based; ties go to the lowest
-- index) and its probability. Zero inputs are skipped, which is most of the image and of each ReLU.
function Model.forward(model: Model, input: { number }, scratch: Scratch): (number, number)
	local layers = model.layers
	local layerCount = #layers
	local acts = scratch.acts
	local source = input

	for l = 1, layerCount do
		local layer = layers[l]
		local outSize = layer.outSize
		local weights = layer.weights
		local biases = layer.biases
		local current = acts[l]

		for o = 1, outSize do
			current[o] = biases[o]
		end
		for i = 0, layer.inSize - 1 do
			local value = source[i + 1]
			if value ~= 0 then
				local base = i * outSize
				for o = 1, outSize do
					current[o] += value * weights[base + o]
				end
			end
		end
		if layer.isRelu then
			for o = 1, outSize do
				if current[o] < 0 then
					current[o] = 0
				end
			end
		end
		source = current
	end

	local logits = acts[layerCount]
	local probs = scratch.probs
	local classCount = layers[layerCount].outSize
	local top = 1
	local maxLogit = logits[1]
	for o = 2, classCount do
		if logits[o] > maxLogit then
			maxLogit = logits[o]
			top = o
		end
	end
	local sum = 0
	for o = 1, classCount do
		local p = exp(logits[o] - maxLogit)
		probs[o] = p
		sum += p
	end
	for o = 1, classCount do
		probs[o] /= sum
	end
	scratch.top = top - 1
	return top - 1, probs[top]
end

return Model
