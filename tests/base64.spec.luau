--!strict
local TestKit = require("./lib/TestKit")
local Base64 = require("../src/shared/NeuralCore/Base64")

return function(kit: TestKit.TestKit)
	local vectors = {
		{ "", "" },
		{ "f", "Zg==" },
		{ "fo", "Zm8=" },
		{ "foo", "Zm9v" },
		{ "foob", "Zm9vYg==" },
		{ "fooba", "Zm9vYmE=" },
		{ "foobar", "Zm9vYmFy" },
	}

	kit.test("base64 matches the RFC 4648 vectors both ways", function()
		for _, vector in vectors do
			kit.equal(Base64.encode(buffer.fromstring(vector[1])), vector[2], "encode")
			local decoded = Base64.decode(vector[2])
			assert(decoded ~= nil, "decode returned nil")
			kit.equal(buffer.tostring(decoded), vector[1], "decode")
		end
	end)

	kit.test("base64 round-trips every byte value at every length remainder", function()
		for extra = 0, 2 do
			local data = buffer.create(256 + extra)
			for i = 0, 255 + extra do
				buffer.writeu8(data, i, i % 256)
			end
			local decoded = Base64.decode(Base64.encode(data))
			assert(decoded ~= nil, "decode returned nil")
			kit.equal(buffer.tostring(decoded), buffer.tostring(data), "round trip")
		end
	end)

	kit.test("base64 rejects malformed text", function()
		for _, text in { "A", "AB", "ABC", "A===", "====", "AB=C", "A$BC", "Zh==", "Zm9=", "Zg==Zg==" } do
			kit.equal(Base64.decode(text), nil, text)
		end
	end)
end
