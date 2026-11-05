--!strict
local TestKit = require("./lib/TestKit")
local Strokes = require("../src/shared/NeuralCore/Strokes")

local function wire(values: { number }): buffer
	local data = buffer.create(#values * 2)
	for i, value in values do
		buffer.writeu16(data, (i - 1) * 2, value)
	end
	return data
end

return function(kit: TestKit.TestKit)
	kit.test("strokes record points, dots, and undo", function()
		local strokes = Strokes.new()
		kit.equal(Strokes.undo(strokes), false, "undo when empty")
		kit.equal(Strokes.addPoint(strokes, 1, 1), false, "point before any stroke")

		kit.equal(Strokes.beginStroke(strokes, 1, 2), true, "first stroke")
		kit.equal(Strokes.addPoint(strokes, 3, 4), true, "second point")
		kit.equal(Strokes.beginStroke(strokes, 5, 6), true, "dot")
		kit.equal(strokes.pointCount, 3, "points")
		kit.equal(strokes.strokeEnds[1], 2, "first end")
		kit.equal(strokes.strokeEnds[2], 3, "second end")

		kit.equal(Strokes.undo(strokes), true, "undo")
		kit.equal(strokes.pointCount, 2, "points after undo")
		kit.equal(strokes.strokeCount, 1, "strokes after undo")
		kit.equal(Strokes.undo(strokes), true, "undo again")
		kit.equal(strokes.pointCount, 0, "empty after undo")
	end)

	kit.test("strokes enforce the limits", function()
		local strokes = Strokes.new()
		for _ = 1, Strokes.MAX_STROKES do
			kit.equal(Strokes.beginStroke(strokes, 0, 0), true, "within stroke limit")
		end
		kit.equal(Strokes.beginStroke(strokes, 0, 0), false, "over stroke limit")
		while strokes.pointCount < Strokes.MAX_POINTS do
			kit.equal(Strokes.addPoint(strokes, 0, 0), true, "within point limit")
		end
		kit.equal(Strokes.addPoint(strokes, 0, 0), false, "over point limit")
	end)

	kit.test("quantize clamps and rounds to u16", function()
		kit.equal(Strokes.quantize(-0.5), 0, "below")
		kit.equal(Strokes.quantize(0), 0, "zero")
		kit.equal(Strokes.quantize(0.5), 32768, "middle")
		kit.equal(Strokes.quantize(1), 65535, "one")
		kit.equal(Strokes.quantize(1.5), 65535, "above")
	end)

	kit.test("the largest drawing encodes to 4,162 bytes and round-trips", function()
		local strokes = Strokes.new()
		for s = 1, Strokes.MAX_STROKES do
			Strokes.beginStroke(strokes, s, 65535 - s)
		end
		local i = 0
		while Strokes.addPoint(strokes, i % 65536, 65535) do
			i += 1
		end
		local encoded = Strokes.encode(strokes)
		kit.equal(buffer.len(encoded), 4162, "size")
		local decoded = Strokes.decode(encoded)
		assert(decoded ~= nil, "decode returned nil")
		kit.equal(buffer.tostring(Strokes.encode(decoded)), buffer.tostring(encoded), "round trip")
	end)

	kit.test("an empty drawing is valid on the wire", function()
		local decoded = Strokes.decode(wire({ 0 }))
		assert(decoded ~= nil, "decode returned nil")
		kit.equal(decoded.pointCount, 0, "points")
	end)

	kit.test("decode rejects malformed payloads", function()
		local overPoints = buffer.create(2 + 2 + 1025 * 4)
		buffer.writeu16(overPoints, 0, 1)
		buffer.writeu16(overPoints, 2, 1025)

		local tooManyPointsAcrossStrokes = buffer.create(2 + 2 * 2 + 1025 * 4)
		buffer.writeu16(tooManyPointsAcrossStrokes, 0, 2)
		buffer.writeu16(tooManyPointsAcrossStrokes, 2, 1024)
		buffer.writeu16(tooManyPointsAcrossStrokes, 2 + 2 + 1024 * 4, 1)

		local cases: { [string]: buffer } = {
			["empty payload"] = buffer.create(0),
			["one byte"] = buffer.create(1),
			["too many strokes"] = wire({ 33 }),
			["missing stroke header"] = wire({ 1 }),
			["zero-point stroke"] = wire({ 1, 0 }),
			["truncated points"] = wire({ 1, 2, 7, 7, 7 }),
			["trailing bytes"] = wire({ 1, 1, 7, 7, 9 }),
			["trailing bytes after no strokes"] = wire({ 0, 0 }),
			["over the point limit"] = overPoints,
			["over the point limit across strokes"] = tooManyPointsAcrossStrokes,
			["over the byte limit"] = buffer.create(4163),
		}
		for name, data in cases do
			kit.equal(Strokes.decode(data), nil, name)
		end
	end)
end
