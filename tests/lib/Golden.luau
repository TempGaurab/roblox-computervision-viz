--!strict
-- Reads the generated goldens: JSON with float64 vectors stored as base64.

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Base64 = require("../../src/shared/NeuralCore/Base64")

local Golden = {}

function Golden.load(name: string): any
	return serde.decode("json", fs.readFile(`tests/golden/{name}.json`))
end

function Golden.bytes(encoded: string): buffer
	local bytes = Base64.decode(encoded)
	assert(bytes ~= nil, "golden is not valid base64")
	return bytes
end

function Golden.floats(encoded: string): { number }
	local bytes = Golden.bytes(encoded)
	local count = buffer.len(bytes) // 8
	local values: { number } = table.create(count, 0)
	for i = 1, count do
		values[i] = buffer.readf64(bytes, (i - 1) * 8)
	end
	return values
end

return Golden
