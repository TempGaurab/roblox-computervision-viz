--!strict
-- Strokes -> the grid the model sees. Implements the same spec as training/preprocess.py (claude.md),
-- with the same floating-point operations in the same order; the golden tests hold them together.

local StrokesModule = require("./Strokes")

local floor = math.floor
local sqrt = math.sqrt

type Strokes = StrokesModule.Strokes

export type Params = {
	grid: number,
	box: number,
	brushInner: number,
	brushOuter: number,
	minExtent: number,
}

export type Scratch = {
	gridXs: { number },
	gridYs: { number },
}

local COORD_MAX = StrokesModule.COORD_MAX

local Preprocess = {}

function Preprocess.newScratch(): Scratch
	return {
		gridXs = table.create(StrokesModule.MAX_POINTS, 0),
		gridYs = table.create(StrokesModule.MAX_POINTS, 0),
	}
end

function Preprocess.newOutput(params: Params): { number }
	return table.create(params.grid * params.grid, 0)
end

-- Max-combines one segment (or a dot, when both ends match) into the image.
local function stampSegment(
	image: { number },
	grid: number,
	inner: number,
	outer: number,
	ax: number,
	ay: number,
	bx: number,
	by: number
)
	local loX, hiX = ax, bx
	if bx < ax then
		loX, hiX = bx, ax
	end
	local loY, hiY = ay, by
	if by < ay then
		loY, hiY = by, ay
	end

	local firstCol = floor(loX - outer)
	if firstCol < 0 then
		firstCol = 0
	end
	local lastCol = floor(hiX + outer)
	if lastCol > grid - 1 then
		lastCol = grid - 1
	end
	local firstRow = floor(loY - outer)
	if firstRow < 0 then
		firstRow = 0
	end
	local lastRow = floor(hiY + outer)
	if lastRow > grid - 1 then
		lastRow = grid - 1
	end

	local dx = bx - ax
	local dy = by - ay
	local lengthSquared = dx * dx + dy * dy
	local outerSquared = outer * outer
	local band = outer - inner

	for row = firstRow, lastRow do
		local centerY = row + 0.5
		local rowBase = row * grid + 1
		for col = firstCol, lastCol do
			local centerX = col + 0.5
			local t = 0
			if lengthSquared > 0 then
				t = ((centerX - ax) * dx + (centerY - ay) * dy) / lengthSquared
				if t < 0 then
					t = 0
				elseif t > 1 then
					t = 1
				end
			end
			local offsetX = centerX - (ax + t * dx)
			local offsetY = centerY - (ay + t * dy)
			local distanceSquared = offsetX * offsetX + offsetY * offsetY
			-- At or beyond the outer radius the intensity is 0, so the sqrt can be skipped.
			if distanceSquared < outerSquared then
				local intensity = (outer - sqrt(distanceSquared)) / band
				if intensity > 1 then
					intensity = 1
				end
				local index = rowBase + col
				if intensity > image[index] then
					image[index] = intensity
				end
			end
		end
	end
end

local function rasterize(
	xs: { number },
	ys: { number },
	strokeEnds: { number },
	strokeCount: number,
	inner: number,
	outer: number,
	grid: number,
	image: { number }
)
	for i = 1, grid * grid do
		image[i] = 0
	end
	local first = 1
	for s = 1, strokeCount do
		local last = strokeEnds[s]
		if first == last then
			stampSegment(image, grid, inner, outer, xs[first], ys[first], xs[first], ys[first])
		else
			for i = first, last - 1 do
				stampSegment(image, grid, inner, outer, xs[i], ys[i], xs[i + 1], ys[i + 1])
			end
		end
		first = last + 1
	end
end

-- Fills `output` (row-major, row 0 on top, ink = 1). Returns false, leaving it untouched, when the
-- drawing is empty or too small to read.
function Preprocess.run(params: Params, strokes: Strokes, scratch: Scratch, output: { number }): boolean
	local pointCount = strokes.pointCount
	if pointCount == 0 then
		return false
	end

	local gridXs = scratch.gridXs
	local gridYs = scratch.gridYs
	local sourceXs = strokes.xs
	local sourceYs = strokes.ys

	local minX = sourceXs[1] / COORD_MAX
	local minY = sourceYs[1] / COORD_MAX
	local maxX = minX
	local maxY = minY
	for i = 1, pointCount do
		local x = sourceXs[i] / COORD_MAX
		local y = sourceYs[i] / COORD_MAX
		gridXs[i] = x
		gridYs[i] = y
		if x < minX then
			minX = x
		elseif x > maxX then
			maxX = x
		end
		if y < minY then
			minY = y
		elseif y > maxY then
			maxY = y
		end
	end

	local width = maxX - minX
	local height = maxY - minY
	local extent = if width > height then width else height
	if extent < params.minExtent then
		return false
	end

	local grid = params.grid
	local inner = params.brushInner
	local outer = params.brushOuter
	local scale = params.box / extent
	local offsetX = (grid - width * scale) / 2
	local offsetY = (grid - height * scale) / 2
	for i = 1, pointCount do
		gridXs[i] = (gridXs[i] - minX) * scale + offsetX
		gridYs[i] = (gridYs[i] - minY) * scale + offsetY
	end

	local strokeEnds = strokes.strokeEnds
	local strokeCount = strokes.strokeCount
	rasterize(gridXs, gridYs, strokeEnds, strokeCount, inner, outer, grid, output)

	local total = 0
	local momentX = 0
	local momentY = 0
	for row = 0, grid - 1 do
		local rowBase = row * grid + 1
		local centerY = row + 0.5
		for col = 0, grid - 1 do
			local intensity = output[rowBase + col]
			if intensity > 0 then
				total += intensity
				momentX += intensity * (col + 0.5)
				momentY += intensity * centerY
			end
		end
	end
	if total <= 0 then
		return false
	end

	local shiftX = grid / 2 - momentX / total
	local shiftY = grid / 2 - momentY / total
	for i = 1, pointCount do
		gridXs[i] += shiftX
		gridYs[i] += shiftY
	end
	rasterize(gridXs, gridYs, strokeEnds, strokeCount, inner, outer, grid, output)
	return true
end

return Preprocess
