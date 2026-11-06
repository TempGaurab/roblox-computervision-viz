--!strict
local TestKit = require("./lib/TestKit")
local HudLayout = require("../src/client/Hud/HudLayout")

-- Mirrors Config.Hud, which Lune can't load because it holds Color3s.
local PARAMS: HudLayout.Params = {
	TOP_COUNT = 3,
	MARGIN = 16,
	WIDTH = 220,
	ROUND_WIDTH = 0.3,
	ROUND_GAP = 16,
	STANDINGS_HEIGHT = 110,
	Roomy = {
		ROW_HEIGHT = 30,
		ROW_GAP = 6,
		DIGIT_WIDTH = 28,
		PERCENT_WIDTH = 52,
		TEXT_SIZE = 20,
		MESSAGE_HEIGHT = 28,
		MESSAGE_TEXT_SIZE = 16,
		VERSION_HEIGHT = 14,
		PROMPT_HEIGHT = 56,
		SCORE_HEIGHT = 26,
		RESULT_HEIGHT = 60,
		STANDINGS_TEXT_SIZE = 18,
	},
	Compact = {
		MARGIN = 8,
		GAP = 8,
		MIN_FREE_WIDTH = 600,
		MIN_FREE_HEIGHT = 500,
		STANDINGS_SHARE = 0.28,
		TOP_SHARE = 0.3,
		ROW_HEIGHT = 16,
		ROW_GAP = 3,
		DIGIT_WIDTH = 16,
		PERCENT_WIDTH = 34,
		TEXT_SIZE = 13,
		MESSAGE_HEIGHT = 16,
		MESSAGE_TEXT_SIZE = 12,
		VERSION_HEIGHT = 0,
		PROMPT_HEIGHT = 32,
		SCORE_HEIGHT = 16,
		RESULT_HEIGHT = 28,
		STANDINGS_TEXT_SIZE = 12,
	},
}

-- The Glass's framed shape: (44 + 1.2) wide by (22 + 1.2) tall, with the 1.08 framing margin on both.
local GLASS_ASPECT = 45.2 / 23.2

-- PadView's arithmetic: a square screen plus its bezel, controls and margins.
local function dockedExtent(width: number, height: number): number
	local chrome = 2 * 18 + 8 + 44
	if height > width then
		local side = math.min(width - 2 * 16 - 2 * 18, height * 0.55 - chrome)
		return side + chrome + 2 * 16
	end
	local side = math.min(width * 0.42, height - 2 * 16 - chrome)
	return side + 2 * 18 + 2 * 16
end

local function overlaps(a: HudLayout.Rect, b: HudLayout.Rect): boolean
	return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
end

local function touchesFree(rect: HudLayout.Rect, free: HudLayout.Area): boolean
	return rect.x < free.right
		and free.left < rect.x + rect.width
		and rect.y < free.bottom
		and free.top < rect.y + rect.height
end

local SCREENS = {
	{ name = "phone landscape", width = 844, height = 354, compact = true },
	{ name = "small phone landscape", width = 667, height = 339, compact = true },
	{ name = "phone portrait", width = 390, height = 797, compact = true },
	{ name = "small phone portrait", width = 375, height = 631, compact = true },
	{ name = "tablet landscape", width = 1024, height = 732, compact = true },
	{ name = "tablet portrait", width = 768, height = 988, compact = true },
	{ name = "laptop", width = 1280, height = 662, compact = false },
	{ name = "desktop", width = 1506, height = 747, compact = false },
	{ name = "large desktop", width = 2560, height = 1380, compact = false },
}

return function(kit: TestKit.TestKit)
	for _, screen in SCREENS do
		local layout = HudLayout.compute(PARAMS, screen.width, screen.height, dockedExtent(screen.width, screen.height))

		kit.test(`{screen.name}: picks the expected layout`, function()
			kit.equal(layout.isCompact == screen.compact, true)
		end)

		kit.test(`{screen.name}: nothing covers the Glass or anything else`, function()
			kit.equal(not touchesFree(layout.top, layout.free), true)
			kit.equal(not touchesFree(layout.round, layout.free), true)
			kit.equal(not touchesFree(layout.standings, layout.free), true)
			kit.equal(not overlaps(layout.top, layout.round), true)
			kit.equal(not overlaps(layout.round, layout.standings), true)
			kit.equal(not overlaps(layout.top, layout.standings), true)
		end)

		kit.test(`{screen.name}: stays on screen and clear of the pad`, function()
			local isPortrait = screen.height > screen.width
			local minX = if isPortrait then 0 else dockedExtent(screen.width, screen.height)
			for _, rect in { layout.top, layout.round, layout.standings } do
				kit.equal(rect.x >= minX and rect.y >= 0, true)
				kit.equal(rect.x + rect.width <= screen.width and rect.y + rect.height <= screen.height, true)
				kit.equal(rect.width > 0 and rect.height > 0, true)
			end
		end)

		kit.test(`{screen.name}: leaves the Glass a usable view`, function()
			local free = layout.free
			local width = math.min(free.right - free.left, (free.bottom - free.top) * GLASS_ASPECT)
			kit.equal(width >= 300, true)
		end)
	end
end
