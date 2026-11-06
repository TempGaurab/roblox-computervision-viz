--!strict
-- Where the HUD goes, and what's left of the screen for the Glass. Pure logic with no requires, so Lune
-- tests it. Everything is in the ScreenGui's pixels.
--
-- Large screens keep the roomy layout. Phones, narrow windows and portrait get one short strip across the
-- free area, because the roomy layout would cover the Glass there.

export type Rect = { x: number, y: number, width: number, height: number }
export type Area = { left: number, top: number, right: number, bottom: number }

export type Sizes = {
	ROW_HEIGHT: number,
	ROW_GAP: number,
	DIGIT_WIDTH: number,
	PERCENT_WIDTH: number,
	TEXT_SIZE: number,
	MESSAGE_HEIGHT: number,
	MESSAGE_TEXT_SIZE: number,
	VERSION_HEIGHT: number,
	PROMPT_HEIGHT: number,
	SCORE_HEIGHT: number,
	RESULT_HEIGHT: number,
	STANDINGS_TEXT_SIZE: number,
}

export type Params = {
	TOP_COUNT: number,
	MARGIN: number,
	WIDTH: number,
	ROUND_WIDTH: number,
	ROUND_GAP: number,
	STANDINGS_HEIGHT: number,
	Roomy: Sizes,
	Compact: Sizes & {
		MARGIN: number,
		GAP: number,
		MIN_FREE_WIDTH: number,
		MIN_FREE_HEIGHT: number,
		STANDINGS_SHARE: number,
		TOP_SHARE: number,
	},
}

export type Layout = {
	isCompact: boolean,
	sizes: Sizes,
	top: Rect,
	round: Rect,
	standings: Rect,
	free: Area, -- where the Glass goes
}

local HudLayout = {}

local function rowsHeight(params: Params, sizes: Sizes): number
	return params.TOP_COUNT * (sizes.ROW_HEIGHT + sizes.ROW_GAP)
end

local function roundHeight(sizes: Sizes): number
	return sizes.PROMPT_HEIGHT + sizes.SCORE_HEIGHT + sizes.RESULT_HEIGHT
end

-- `dockedExtent` is what the pad takes from the left in landscape, or from the bottom in portrait.
function HudLayout.compute(params: Params, width: number, height: number, dockedExtent: number): Layout
	local isPortrait = height > width
	local freeLeft = if isPortrait then 0 else dockedExtent
	local freeBottom = if isPortrait then height - dockedExtent else height
	local freeWidth = width - freeLeft
	local compact = params.Compact

	if isPortrait or freeWidth < compact.MIN_FREE_WIDTH or height < compact.MIN_FREE_HEIGHT then
		local stripHeight = math.max(rowsHeight(params, compact) + compact.MESSAGE_HEIGHT, roundHeight(compact))
		local inner = math.max(freeWidth - 2 * compact.MARGIN - 2 * compact.GAP, 0)
		local standingsWidth = inner * compact.STANDINGS_SHARE
		local topWidth = inner * compact.TOP_SHARE
		local roundWidth = inner - standingsWidth - topWidth
		local left = freeLeft + compact.MARGIN
		local y = compact.MARGIN
		return {
			isCompact = true,
			sizes = compact,
			standings = { x = left, y = y, width = standingsWidth, height = stripHeight },
			round = { x = left + standingsWidth + compact.GAP, y = y, width = roundWidth, height = stripHeight },
			top = { x = width - compact.MARGIN - topWidth, y = y, width = topWidth, height = stripHeight },
			free = { left = freeLeft, top = y + stripHeight, right = width, bottom = freeBottom },
		}
	end

	local roomy = params.Roomy
	local margin = params.MARGIN
	local topHeight = rowsHeight(params, roomy) + roomy.VERSION_HEIGHT + roomy.MESSAGE_HEIGHT
	local topX = width - margin - params.WIDTH
	local roundWidth = math.min(params.ROUND_WIDTH * width, topX - params.ROUND_GAP - freeLeft - margin)
	local standingsY = height - margin - params.STANDINGS_HEIGHT
	return {
		isCompact = false,
		sizes = roomy,
		top = { x = topX, y = margin, width = params.WIDTH, height = topHeight },
		round = {
			x = topX - params.ROUND_GAP - roundWidth,
			y = margin,
			width = roundWidth,
			height = roundHeight(roomy),
		},
		standings = { x = topX, y = standingsY, width = params.WIDTH, height = params.STANDINGS_HEIGHT },
		free = {
			left = freeLeft,
			top = margin + math.max(topHeight, roundHeight(roomy)),
			right = width,
			bottom = standingsY,
		},
	}
end

return HudLayout
