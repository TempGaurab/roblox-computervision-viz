--!strict
local Golden = require("./lib/Golden")
local TestKit = require("./lib/TestKit")
local ModelData = require("../src/shared/NeuralCore/ModelData")
local Preprocess = require("../src/shared/NeuralCore/Preprocess")
local Strokes = require("../src/shared/NeuralCore/Strokes")

local PARITY_TOLERANCE = 1e-9
local CENTERING_TOLERANCE = 0.05

return function(kit: TestKit.TestKit)
	local params = ModelData.preprocess
	local scratch = Preprocess.newScratch()
	local grid = params.grid

	kit.test("an empty drawing returns false", function()
		kit.equal(Preprocess.run(params, Strokes.new(), scratch, Preprocess.newOutput(params)), false, "empty")
	end)

	kit.test("a drawing under the minimum extent returns false and leaves the output alone", function()
		local strokes = Strokes.new()
		Strokes.beginStroke(strokes, 1000, 1000)
		Strokes.addPoint(strokes, 1100, 1100)
		local output = Preprocess.newOutput(params)
		output[1] = 0.25
		kit.equal(Preprocess.run(params, strokes, scratch, output), false, "too small")
		kit.equal(output[1], 0.25, "untouched")
	end)

	kit.test("a drawing fills the box, stays in range, and is centered by mass", function()
		local strokes = Strokes.new()
		Strokes.beginStroke(strokes, 20000, 10000)
		Strokes.addPoint(strokes, 40000, 12000)
		Strokes.addPoint(strokes, 22000, 50000)
		local output = Preprocess.newOutput(params)
		kit.equal(Preprocess.run(params, strokes, scratch, output), true, "readable")

		local total, momentX, momentY = 0, 0, 0
		for row = 0, grid - 1 do
			for col = 0, grid - 1 do
				local value = output[row * grid + col + 1]
				assert(value >= 0 and value <= 1, "pixel out of range")
				total += value
				momentX += value * (col + 0.5)
				momentY += value * (row + 0.5)
			end
		end
		-- The vectors are centered exactly; re-rasterizing onto pixels leaves a small sampling error.
		kit.near(momentX / total, grid / 2, CENTERING_TOLERANCE, "center x")
		kit.near(momentY / total, grid / 2, CENTERING_TOLERANCE, "center y")
	end)

	kit.test("preprocessing matches Python on every golden stroke case", function()
		local golden = Golden.load("strokes")
		assert(#golden.cases > 0, "no golden stroke cases")
		local output = Preprocess.newOutput(params)
		for _, case in golden.cases do
			local strokes = Strokes.decode(Golden.bytes(case.strokes))
			assert(strokes ~= nil, `{case.name}: strokes did not decode`)
			kit.equal(Preprocess.run(params, strokes, scratch, output), true, case.name)
			local expected = Golden.floats(case.expected)
			kit.equal(#expected, grid * grid, "expected size")
			for i = 1, #expected do
				kit.near(output[i], expected[i], PARITY_TOLERANCE, `{case.name} pixel {i}`)
			end
		end
	end)

	kit.test("reused scratch gives the same result as fresh scratch", function()
		local golden = Golden.load("strokes")
		local reused = Preprocess.newOutput(params)
		for _, case in golden.cases do
			local strokes = Strokes.decode(Golden.bytes(case.strokes))
			assert(strokes ~= nil, "strokes did not decode")
			Preprocess.run(params, strokes, scratch, reused)
			local fresh = Preprocess.newOutput(params)
			Preprocess.run(params, strokes, Preprocess.newScratch(), fresh)
			for i = 1, #fresh do
				kit.equal(reused[i], fresh[i], `{case.name} pixel {i}`)
			end
		end
	end)
end
