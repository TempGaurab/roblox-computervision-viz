--!strict
local TestKit = require("./lib/TestKit")
local Classify = require("../src/shared/NeuralCore/Classify")
local Model = require("../src/shared/NeuralCore/Model")
local ModelData = require("../src/shared/NeuralCore/ModelData")
local Preprocess = require("../src/shared/NeuralCore/Preprocess")
local Strokes = require("../src/shared/NeuralCore/Strokes")

local function drawing(points: { { number } }): Strokes.Strokes
	local strokes = Strokes.new()
	for index, point in points do
		if index == 1 then
			Strokes.beginStroke(strokes, point[1], point[2])
		else
			Strokes.addPoint(strokes, point[1], point[2])
		end
	end
	return strokes
end

local SEVEN = { { 22000, 14000 }, { 46000, 15000 }, { 40000, 26000 }, { 30000, 50000 } }

return function(kit: TestKit.TestKit)
	local classifier = Classify.new(ModelData, ModelData.preprocess)

	kit.test("agrees with the client's pipeline on the same strokes", function()
		local strokes = drawing(SEVEN)
		local status, digit, prob = Classify.run(classifier, Strokes.encode(strokes))
		kit.equal(status, "ok", "status")

		local model = Model.load(ModelData)
		local input = Preprocess.newOutput(ModelData.preprocess)
		kit.equal(Preprocess.run(ModelData.preprocess, strokes, Preprocess.newScratch(), input), true, "preprocess")
		local top, pTop = Model.forward(model, input, Model.newScratch(model))
		kit.equal(digit, top, "digit")
		kit.equal(prob, pTop, "probability")
	end)

	kit.test("rejects malformed payloads", function()
		kit.equal(Classify.run(classifier, buffer.create(0)), "malformed", "empty buffer")
		kit.equal(Classify.run(classifier, buffer.create(1)), "malformed", "too short")
		kit.equal(Classify.run(classifier, buffer.create(Strokes.MAX_ENCODED_BYTES + 1)), "malformed", "too long")

		local trailing = buffer.create(3)
		kit.equal(Classify.run(classifier, trailing), "malformed", "bytes left over")

		local tooManyStrokes = buffer.create(2)
		buffer.writeu16(tooManyStrokes, 0, Strokes.MAX_STROKES + 1)
		kit.equal(Classify.run(classifier, tooManyStrokes), "malformed", "too many strokes")
	end)

	kit.test("reports drawings it can't read", function()
		kit.equal(Classify.run(classifier, Strokes.encode(Strokes.new())), "unreadable", "no strokes")
		local dot = Strokes.encode(drawing({ { 30000, 30000 } }))
		kit.equal(Classify.run(classifier, dot), "unreadable", "a single dot")
	end)
end
