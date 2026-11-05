--!strict
-- Standard base64 (RFC 4648) to and from buffers. Used at load time and in tooling, never per frame.

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local PADDING = string.byte("=")

local valueOfByte: { [number]: number } = {}
local byteOfValue: { [number]: number } = {}
for i = 1, #ALPHABET do
	local byte = string.byte(ALPHABET, i)
	valueOfByte[byte] = i - 1
	byteOfValue[i - 1] = byte
end

local Base64 = {}

-- Returns nil if the text is not valid, canonically padded base64.
function Base64.decode(text: string): buffer?
	local length = #text
	if length % 4 ~= 0 then
		return nil
	end
	if length == 0 then
		return buffer.create(0)
	end

	local padding = 0
	if string.byte(text, length) == PADDING then
		padding = if string.byte(text, length - 1) == PADDING then 2 else 1
	end

	local out = buffer.create(length // 4 * 3 - padding)
	local cursor = 0
	for i = 1, length - padding do
		local value = valueOfByte[string.byte(text, i)]
		if value == nil then
			return nil
		end
		local phase = (i - 1) % 4
		if phase == 0 then
			buffer.writeu8(out, cursor, bit32.lshift(value, 2))
		elseif phase == 1 then
			buffer.writeu8(out, cursor, buffer.readu8(out, cursor) + bit32.rshift(value, 4))
			cursor += 1
			if cursor < buffer.len(out) then
				buffer.writeu8(out, cursor, bit32.band(bit32.lshift(value, 4), 0xFF))
			elseif bit32.band(value, 0x0F) ~= 0 then
				return nil
			end
		elseif phase == 2 then
			buffer.writeu8(out, cursor, buffer.readu8(out, cursor) + bit32.rshift(value, 2))
			cursor += 1
			if cursor < buffer.len(out) then
				buffer.writeu8(out, cursor, bit32.band(bit32.lshift(value, 6), 0xFF))
			elseif bit32.band(value, 0x03) ~= 0 then
				return nil
			end
		else
			buffer.writeu8(out, cursor, buffer.readu8(out, cursor) + value)
			cursor += 1
		end
	end
	return out
end

function Base64.encode(data: buffer): string
	local length = buffer.len(data)
	local out = buffer.create((length + 2) // 3 * 4)
	local cursor = 0
	for i = 0, length - 1, 3 do
		local remaining = length - i
		local a = buffer.readu8(data, i)
		local b = if remaining > 1 then buffer.readu8(data, i + 1) else 0
		local c = if remaining > 2 then buffer.readu8(data, i + 2) else 0

		buffer.writeu8(out, cursor, byteOfValue[bit32.rshift(a, 2)])
		buffer.writeu8(out, cursor + 1, byteOfValue[bit32.band(bit32.lshift(a, 4), 0x30) + bit32.rshift(b, 4)])
		buffer.writeu8(
			out,
			cursor + 2,
			if remaining > 1 then byteOfValue[bit32.band(bit32.lshift(b, 2), 0x3C) + bit32.rshift(c, 6)] else PADDING
		)
		buffer.writeu8(out, cursor + 3, if remaining > 2 then byteOfValue[bit32.band(c, 0x3F)] else PADDING)
		cursor += 4
	end
	return buffer.tostring(out)
end

return Base64
