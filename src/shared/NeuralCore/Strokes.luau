--!strict
-- Stroke storage, limits, and the wire format. Coordinates are integers 0..65535 in pad space:
-- (0, 0) is top-left and y points down. strokeEnds[s] is the index of stroke s's last point.

local floor = math.floor

export type Strokes = {
	xs: { number },
	ys: { number },
	strokeEnds: { number },
	pointCount: number,
	strokeCount: number,
}

local MAX_STROKES = 32
local MAX_POINTS = 1024
local COORD_MAX = 65535
local HEADER_BYTES = 2
local POINT_BYTES = 4

local Strokes = {
	MAX_STROKES = MAX_STROKES,
	MAX_POINTS = MAX_POINTS,
	COORD_MAX = COORD_MAX,
	MAX_ENCODED_BYTES = HEADER_BYTES + MAX_STROKES * HEADER_BYTES + MAX_POINTS * POINT_BYTES,
}

function Strokes.new(): Strokes
	return {
		xs = table.create(MAX_POINTS, 0),
		ys = table.create(MAX_POINTS, 0),
		strokeEnds = table.create(MAX_STROKES, 0),
		pointCount = 0,
		strokeCount = 0,
	}
end

function Strokes.clear(strokes: Strokes)
	strokes.pointCount = 0
	strokes.strokeCount = 0
end

-- Maps a position in [0, 1] to a u16 coordinate, clamping anything outside the pad.
function Strokes.quantize(unit: number): number
	if unit <= 0 then
		return 0
	elseif unit >= 1 then
		return COORD_MAX
	end
	return floor(unit * COORD_MAX + 0.5)
end

-- Starts a stroke with one point (a dot until more arrive). Returns false at a limit.
function Strokes.beginStroke(strokes: Strokes, x: number, y: number): boolean
	if strokes.strokeCount >= MAX_STROKES or strokes.pointCount >= MAX_POINTS then
		return false
	end
	local index = strokes.pointCount + 1
	strokes.xs[index] = x
	strokes.ys[index] = y
	strokes.pointCount = index
	strokes.strokeCount += 1
	strokes.strokeEnds[strokes.strokeCount] = index
	return true
end

-- Extends the current stroke. Returns false at the point limit or with no stroke started.
function Strokes.addPoint(strokes: Strokes, x: number, y: number): boolean
	if strokes.strokeCount == 0 or strokes.pointCount >= MAX_POINTS then
		return false
	end
	local index = strokes.pointCount + 1
	strokes.xs[index] = x
	strokes.ys[index] = y
	strokes.pointCount = index
	strokes.strokeEnds[strokes.strokeCount] = index
	return true
end

-- Removes the most recent stroke. Returns false when there is nothing to undo.
function Strokes.undo(strokes: Strokes): boolean
	if strokes.strokeCount == 0 then
		return false
	end
	strokes.strokeCount -= 1
	strokes.pointCount = if strokes.strokeCount > 0 then strokes.strokeEnds[strokes.strokeCount] else 0
	return true
end

function Strokes.encode(strokes: Strokes): buffer
	local size = HEADER_BYTES + strokes.strokeCount * HEADER_BYTES + strokes.pointCount * POINT_BYTES
	local out = buffer.create(size)
	buffer.writeu16(out, 0, strokes.strokeCount)
	local cursor = HEADER_BYTES
	local first = 1
	for s = 1, strokes.strokeCount do
		local last = strokes.strokeEnds[s]
		buffer.writeu16(out, cursor, last - first + 1)
		cursor += HEADER_BYTES
		for i = first, last do
			buffer.writeu16(out, cursor, strokes.xs[i])
			buffer.writeu16(out, cursor + 2, strokes.ys[i])
			cursor += POINT_BYTES
		end
		first = last + 1
	end
	return out
end

-- Returns nil for anything malformed, over the limits, or with bytes left over.
function Strokes.decode(data: buffer): Strokes?
	local size = buffer.len(data)
	if size < HEADER_BYTES or size > Strokes.MAX_ENCODED_BYTES then
		return nil
	end
	local strokeCount = buffer.readu16(data, 0)
	if strokeCount > MAX_STROKES then
		return nil
	end

	local strokes = Strokes.new()
	local cursor = HEADER_BYTES
	local total = 0
	for s = 1, strokeCount do
		if cursor + HEADER_BYTES > size then
			return nil
		end
		local pointCount = buffer.readu16(data, cursor)
		cursor += HEADER_BYTES
		if pointCount == 0 or total + pointCount > MAX_POINTS or cursor + pointCount * POINT_BYTES > size then
			return nil
		end
		for _ = 1, pointCount do
			total += 1
			strokes.xs[total] = buffer.readu16(data, cursor)
			strokes.ys[total] = buffer.readu16(data, cursor + 2)
			cursor += POINT_BYTES
		end
		strokes.strokeEnds[s] = total
	end
	if cursor ~= size then
		return nil
	end
	strokes.pointCount = total
	strokes.strokeCount = strokeCount
	return strokes
end

return Strokes
