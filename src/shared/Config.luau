--!strict
-- Every tunable for the Pad, the Glass, and the game loop lives here.

local Config = {
	Inference = {
		MIN_INTERVAL = 0.1, -- seconds between inferences: at most 10 per second
	},

	DrawMode = {
		ACTION_NAME = "NeuralGlassDrawKeys",
		FRAMING_MARGIN = 1.08, -- how much larger than the Glass the framed view is
		MIN_FREE_SHARE = 0.1, -- the least of the screen the Glass is ever fitted into
		HIDDEN_SIGNS = { "Title", "Guide", "Scoreboard" }, -- children of the lab, not shown while drawing
	},

	Glass = {
		-- One chamber on the lab's back wall; each client fills it with its own network. Viewers stand
		-- on +Z, with input on their left.
		ORIGIN = CFrame.new(0, 15, -60),
		WIDTH = 44,
		HEIGHT = 22,
		DEPTH = 5,
		FRAME_THICKNESS = 0.6,
		TRIM_THICKNESS = 0.16, -- the glowing line around the front of the frame

		-- Layout, in studs from the chamber center.
		NETWORK_VIEW_SIZE = 12,
		NETWORK_VIEW_X = -15.5,
		NETWORK_VIEW_BEZEL = 0.18,
		LAYERS_LEFT_X = -9.5, -- neuron layers share this span, with equal gaps around them
		LAYERS_RIGHT_X = 14,
		OUTPUT_PANEL_X = 18,
		OUTPUT_PANEL_WIDTH = 8,
		ORB_SPACING = 1.5,
		HIDDEN_ROWS = 8,
		WINNER_Y = 9.2,
		WINNER_WIDTH = 16,
		WINNER_HEIGHT = 3,

		PIXELS_PER_STUD = 25,
		WINNER_TEXT_SIZE = 64,
		OUTPUT_TEXT_SIZE = 32,
		OUTPUT_BAR_HEIGHT = 0.05, -- share of panel height
		OUTPUT_DIGIT_WIDTH = 0.2, -- share of panel width
		OUTPUT_BAR_WIDTH = 0.75,
		CAPTION_Y = -9.3,
		CAPTION_HEIGHT = 1.4,
		CAPTION_WIDTH = 9, -- each caption, in studs
		CAPTION_TEXT_SIZE = 22,
		CAPTION_INPUT = "WHAT IT SEES",
		CAPTION_HIDDEN = "LAYER %d",
		CAPTION_OUTPUT = "ANSWER",

		ORB_MIN_SIZE = 0.5,
		ORB_MAX_SIZE = 1.1,
		HALO_SIZE = 2.2,
		HALO_TRANSPARENCY = 0.6,

		-- Propagation: displayed values chase targets after a per-layer lag, in seconds.
		HIDDEN_LAG_STEP = 0.08,
		SMOOTHING_TAU = 0.12,
		HISTORY_SIZE = 4, -- inference snapshots kept: enough to cover the longest lag at the highest rate

		-- Quantized steps, so writes skip small changes and colors and sequences are made once.
		ORB_LEVELS = 32,
		PIXEL_LEVELS = 32,
		LINK_LEVELS = 8,
		LINK_MIN_WIDTH = 0.03,
		LINK_MAX_WIDTH = 0.22,
		LINK_MIN_OPACITY = 0.08,
		LINK_MAX_OPACITY = 0.95,

		PACKET_COUNT = 300,
		PACKET_SECONDS = 0.45, -- time to cross one link
		PACKET_MAX_RATE = 4, -- packets per second on the strongest link
		PACKET_SIZE = 0.32,
		PACKET_NEGATIVE_SIZE = 0.18, -- smaller, so sign never relies on color alone
		-- Parked above the map: anything below FallenPartsDestroyHeight could be destroyed.
		PACKET_PARK_POSITION = Vector3.new(0, 5000, 0),

		IDLE_BASE = 0.25,
		IDLE_AMPLITUDE = 0.1,
		IDLE_SPEED = 1.2,
		IDLE_PACKET_RATE = 3, -- ambient packets per second
		PHASE_STEP = 0.7, -- radians between neighboring orbs

		BACK_COLOR = Color3.fromRGB(22, 28, 42),
		FRAME_COLOR = Color3.fromRGB(38, 44, 58),
		TRIM_COLOR = Color3.fromRGB(70, 180, 255), -- Neon: the chamber has to read from across the room
		BEZEL_COLOR = Color3.fromRGB(58, 70, 92),
		PANE_COLOR = Color3.fromRGB(150, 200, 255),
		PANE_TRANSPARENCY = 0.9,
		PANE_REFLECTANCE = 0.05,
		ORB_DIM_COLOR = Color3.fromRGB(30, 60, 110),
		ORB_BRIGHT_COLOR = Color3.fromRGB(120, 215, 255), -- keeps its hue under bloom, unlike near-white
		HALO_COLOR = Color3.fromRGB(90, 190, 255),
		PIXEL_OFF_COLOR = Color3.fromRGB(16, 20, 30),
		PIXEL_ON_COLOR = Color3.fromRGB(235, 245, 255),
		-- A colorblind-safe pair.
		POSITIVE_COLOR = Color3.fromRGB(70, 180, 255),
		NEGATIVE_COLOR = Color3.fromRGB(255, 140, 40),
		TEXT_COLOR = Color3.fromRGB(235, 245, 255),
		CAPTION_COLOR = Color3.fromRGB(130, 145, 170),
		BAR_BACKGROUND_COLOR = Color3.fromRGB(38, 46, 64),
		BAR_COLOR = Color3.fromRGB(90, 170, 255),
		WINNER_BAR_COLOR = Color3.fromRGB(190, 240, 255),

		-- Feedback after a Submit.
		PATH_COLOR = Color3.fromRGB(255, 235, 120), -- the strongest path, also the widest thing on screen
		PATH_WIDTH = 0.5,
		PATH_DIM_OPACITY = 0.04, -- every other link, while the path shows
		CELEBRATE_SECONDS = 1.5,
		CELEBRATE_SPEED = 9, -- radians per second
		CELEBRATE_AMPLITUDE = 0.5, -- share of the halo's size
		CELEBRATE_TEXT_COLOR = Color3.fromRGB(150, 240, 170),
	},

	World = {
		ROOM_WIDTH = 96,
		ROOM_HEIGHT = 36,
		ROOM_FRONT_Z = -66, -- just behind the Glass
		ROOM_BACK_Z = 44, -- deep enough for the Draw Mode camera, which backs up a long way in portrait
		WALL_THICKNESS = 2,
		-- Bright values: the lab's ambient light is low, so these still read as dark.
		FLOOR_COLOR = Color3.fromRGB(105, 112, 130),
		FLOOR_REFLECTANCE = 0.08,
		WALL_COLOR = Color3.fromRGB(70, 76, 92),
		GLOW_COLOR = Color3.fromRGB(70, 180, 255),
		ACCENT_COLOR = Color3.fromRGB(95, 60, 190), -- dark, because Neon washes out toward white
		STRIP_HEIGHT = 0.2,
		STRIP_DEPTH = 0.2,
		STRIP_Y = 0.6,
		TEXT_PIXELS_PER_STUD = 25,

		GRID_SPACING = 16,
		GRID_LINE_WIDTH = 0.1,
		GRID_LINE_HEIGHT = 0.04,
		GRID_COLOR = Color3.fromRGB(14, 42, 66), -- dim enough to stay below the bloom threshold
		WALKWAY_HALF_WIDTH = 5,
		WALKWAY_LINE_WIDTH = 0.18,

		ARCH_COUNT = 4,
		ARCH_FIRST_Z = -48,
		ARCH_SPACING = 28,
		ARCH_HALF_WIDTH = 44,
		ARCH_HEIGHT = 33,
		ARCH_CHAMFER = 7,
		ARCH_BEAM = 1.6,
		ARCH_DEPTH = 1.4,
		ARCH_GLOW = 0.14,
		ARCH_COLOR = Color3.fromRGB(95, 104, 124),
		LAMP_COLOR = Color3.fromRGB(150, 205, 255),
		LAMP_RANGE = 45,
		LAMP_BRIGHTNESS = 1.2,

		SPAWN_POSITION = Vector3.new(0, 0, 14),
		SPAWN_DIAMETER = 12,
		SPAWN_HEIGHT = 0.6,
		SPAWN_RING = 0.5,
		SPAWN_COLOR = Color3.fromRGB(150, 160, 185),

		SIGN_DEPTH = 0.5,
		TITLE_TEXT = "NEURAL  GLASS",
		TITLE_TEXT_SIZE = 110,
		TITLE_WIDTH = 44,
		TITLE_HEIGHT = 6,
		TITLE_Y = 30.5,

		-- Mirrors the leaderboard, on the other side of the Glass.
		GUIDE_POSITION = Vector3.new(-36, 14, -65.75),
		GUIDE_WIDTH = 20,
		GUIDE_HEIGHT = 24,
		GUIDE_TRIM = 0.16,
		GUIDE_COLOR = Color3.fromRGB(14, 17, 25),
		GUIDE_TITLE_COLOR = Color3.fromRGB(235, 245, 255),
		GUIDE_TEXT_COLOR = Color3.fromRGB(150, 225, 255),
		GUIDE_TITLE_SIZE = 50,
		GUIDE_TEXT_SIZE = 32,
		GUIDE_LINES = {
			"HOW TO PLAY",
			"Walk up to a console",
			"SOLO\nBeat your best streak",
			"COMPETE\nA 60-second sprint",
			"FREE DRAW\nJust explore",
			"HOW IT WORKS\nOn the wall behind you",
		},

		HOW_IT_WORKS = {
			ROW_WIDTH = 84,
			TITLE = "HOW IT WORKS",
			TITLE_Y = 29,
			TITLE_HEIGHT = 5,
			TITLE_TEXT_SIZE = 90,

			CARD_Y = 15,
			CARD_WIDTH = 18,
			CARD_HEIGHT = 20,
			CARD_GAP = 4,
			CARD_COLOR = Color3.fromRGB(14, 17, 25),
			TRIM = 0.16,
			LINK_THICKNESS = 0.16,

			NUMBER_SHARE = 0.17, -- of a card's height
			HEADING_SHARE = 0.13,
			BODY_MARGIN = 0.08, -- of a card's width
			NUMBER_TEXT_SIZE = 60,
			HEADING_TEXT_SIZE = 44,
			BODY_TEXT_SIZE = 40,
			HEADING_COLOR = Color3.fromRGB(235, 245, 255),
			BODY_COLOR = Color3.fromRGB(150, 225, 255),

			-- Each step's body gets the model's real numbers.
			HEADINGS = { "YOU DRAW", "IT SIMPLIFIES", "NEURONS FIRE", "IT ANSWERS" },
			BODY_DRAW = "Your strokes are saved as points, so it works the same on any screen.",
			BODY_SEE = "Your digit is scaled and centered on a %d x %d grid. Those %d numbers are all the network sees.",
			BODY_THINK = "They flow through %s neurons. Blue links push a neuron up, orange links push it down.",
			BODY_ANSWER = "%d outputs, one per digit. The highest is its guess, and the percent is how sure it is.",

			FOOTER_Y = 2.6,
			FOOTER_HEIGHT = 4,
			FOOTER_TEXT_SIZE = 28,
			FOOTER = "Trained on MNIST handwritten digits (LeCun, Cortes, Burges), and %.1f%% right on its test set. It runs on your device. Your drawing is only sent when you press Submit, and is never kept or shown to anyone.",
		},

		MOTES_POSITION = Vector3.new(0, 16, 12),
		MOTES_SIZE = Vector3.new(88, 30, 58),
		MOTES_RATE = 10,
		MOTES_LIFETIME = NumberRange.new(8, 14),
		MOTES_SPEED = NumberRange.new(0.3, 1.2),
		MOTES_PARTICLE_SIZE = 0.22,
		MOTES_TRANSPARENCY = 0.25,

		STATION_COUNT = 4,
		STATION_SPACING = 14,
		CONSOLE_Z = -20,
		CONSOLE_SIZE = Vector3.new(4.5, 3, 1.6),
		CONSOLE_COLOR = Color3.fromRGB(150, 160, 185),
		CONSOLE_SCREEN_THICKNESS = 0.2,
		CONSOLE_SCREEN_DEPTH = 3,
		CONSOLE_SCREEN_LIFT = 0.5,
		CONSOLE_SCREEN_TILT = math.rad(55), -- from upright
		CONSOLE_SCREEN_COLOR = Color3.fromRGB(14, 17, 25),
		CONSOLE_EDGE = 0.1,
		CONSOLE_BEACON_SIZE = 0.4,
		CONSOLE_BEACON_Y = 5.5,
		CONSOLE_RING_DIAMETER = 7,
		CONSOLE_RING_COLOR = Color3.fromRGB(10, 32, 54),
		CONSOLE_TEXT = "DRAW",
		CONSOLE_TEXT_SIZE = 30,
		CONSOLE_TEXT_COLOR = Color3.fromRGB(150, 225, 255),

		PROMPT_ACTION = "Draw",
		PROMPT_SOLO = "Solo",
		PROMPT_COMPETE = "Compete",
		PROMPT_FREE = "Free Draw",
		PROMPT_SOLO_KEY = Enum.KeyCode.E,
		PROMPT_COMPETE_KEY = Enum.KeyCode.R,
		PROMPT_FREE_KEY = Enum.KeyCode.F,
		PROMPT_DISTANCE = 12,
		PROMPT_SPACING = 80, -- pixels between a console's prompts
		REACH_SLACK = 6, -- studs of lag allowed when the server checks a prompt's range
	},

	Net = {
		SUBMITS_PER_SECOND = 2,
		MAX_SUBMIT_BYTES = 8192,
		STATION_EVENTS_PER_SECOND = 5,
	},

	Pad = {
		MARGIN = 16, -- pixels from the viewport edge
		BEZEL = 18, -- pixels of tablet body around the screen
		TABLET_CORNER_RADIUS = 22,
		TABLET_STROKE_THICKNESS = 2,
		SCREEN_CORNER_RADIUS = 6,
		CAMERA_DOT_SIZE = 6,
		GAP = 8, -- pixels between the pad, the controls, and each button
		CONTROLS_HEIGHT = 44,
		LANDSCAPE_MAX_WIDTH = 0.42, -- share of viewport width
		PORTRAIT_MAX_HEIGHT = 0.55, -- share of viewport height
		MIN_POINT_DISTANCE = 0.01, -- share of pad size a pointer must move to add a point
		INK_THICKNESS = 0.05, -- share of pad size
		SLIDE_SECONDS = 0.25,
		CORNER_RADIUS = 8,
		BUTTON_TEXT_SIZE = 16,

		TABLET_COLOR = Color3.fromRGB(24, 26, 32),
		TABLET_STROKE_COLOR = Color3.fromRGB(88, 94, 108),
		CAMERA_DOT_COLOR = Color3.fromRGB(58, 64, 78),
		SURFACE_COLOR = Color3.fromRGB(14, 18, 28),
		SURFACE_STROKE_COLOR = Color3.fromRGB(90, 170, 255),
		SURFACE_STROKE_THICKNESS = 1,
		INK_COLOR = Color3.fromRGB(235, 245, 255),
		BUTTON_COLOR = Color3.fromRGB(38, 46, 66),
		SUBMIT_COLOR = Color3.fromRGB(40, 110, 200),
		BUTTON_TEXT_COLOR = Color3.fromRGB(235, 245, 255),
	},

	Hud = {
		TOP_COUNT = 3,
		MARGIN = 16,
		WIDTH = 220,
		-- The layout for large screens.
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
		-- One strip above the Glass, for phones, narrow windows and portrait.
		Compact = {
			MARGIN = 8,
			GAP = 8,
			MIN_FREE_WIDTH = 600, -- pixels beside the pad; any less and the roomy layout covers the Glass
			MIN_FREE_HEIGHT = 500,
			STANDINGS_SHARE = 0.28, -- of the strip's width
			TOP_SHARE = 0.3,
			ROW_HEIGHT = 16,
			ROW_GAP = 3,
			DIGIT_WIDTH = 16,
			PERCENT_WIDTH = 34,
			TEXT_SIZE = 13,
			MESSAGE_HEIGHT = 16,
			MESSAGE_TEXT_SIZE = 12,
			VERSION_HEIGHT = 0, -- hidden
			PROMPT_HEIGHT = 32,
			SCORE_HEIGHT = 16,
			RESULT_HEIGHT = 28,
			STANDINGS_TEXT_SIZE = 12,
		},
		VERSION_TEXT_SIZE = 11,
		-- A backing for the compact strip, so the lab's neon trim can't run through the text.
		STRIP_COLOR = Color3.fromRGB(14, 17, 25),
		STRIP_TRANSPARENCY = 0.25,
		STRIP_PADDING = 6,
		CORNER_RADIUS = 6,

		TEXT_COLOR = Color3.fromRGB(235, 245, 255),
		MUTED_TEXT_COLOR = Color3.fromRGB(130, 145, 170),
		WARNING_TEXT_COLOR = Color3.fromRGB(255, 190, 90),
		BAR_BACKGROUND_COLOR = Color3.fromRGB(38, 46, 66),
		BAR_COLOR = Color3.fromRGB(90, 170, 255),
		TOP_BAR_COLOR = Color3.fromRGB(150, 225, 255),

		MESSAGE_TOO_SMALL = "Draw bigger",
		MESSAGE_LIMIT = "Clear to keep drawing",
		MESSAGE_DRAW_FIRST = "Draw a digit first",
		MESSAGE_RETRY = "Couldn't reach the server. Try again",

		ROUND_WIDTH = 0.3, -- share of screen width, so it clears the docked pad on small screens
		ROUND_GAP = 16, -- pixels between this and the top-3
		PROMPT_MAX_TEXT_SIZE = 42,
		RESULT_MAX_TEXT_SIZE = 22,
		SCORE_MAX_TEXT_SIZE = 18,
		GOOD_TEXT_COLOR = Color3.fromRGB(150, 240, 170),

		PROMPT_DRAW = "Draw %s",
		PROMPT_FREE = "Free Draw",
		RESULT_CORRECT = "Correct! That's %s",
		RESULT_WRONG = "The network saw %s (%d%%)",
		SCORE_LINE = "Score %d  ·  Streak %d",

		-- Compete.
		STANDINGS_HEIGHT = 110,
		STANDINGS_YOU = "You",
		STANDINGS_LINE = "%d. %s  %d",
		MESSAGE_WAIT = "Wait for the next sprint",
		PROMPT_GET_READY = "Get ready",
		PROMPT_WAITING = "Next sprint soon",
		PROMPT_YOU_WON = "You won!",
		PROMPT_YOU_TIED = "You tied for first!",
		PROMPT_THEY_WON = "%s won",
		PROMPT_TIME_UP = "Time's up",
		SPRINT_STARTS_LINE = "Starts in %d",
		SPRINT_RUNNING_LINE = "Score %d  ·  %d:%02d",
		SPRINT_SCORE_LINE = "You scored %d",
		SPRINT_NEXT_LINE = "Next sprint in %d",
	},

	Round = {
		CLEAR_DELAY = 1.5, -- seconds a correct drawing stays up before the pad clears for the next digit
	},

	Scoreboard = {
		DEVELOPER_USER_ID = 1128590649, -- GauurabBeast. Set by hand: the game belongs to a group, so game.CreatorId isn't them
		STORE_NAME = "BestStreaks",
		STUDIO_STORE_NAME = "BestStreaks_Studio",
		SIZE = 10,
		SAVE_SECONDS = 30,
		REFRESH_SECONDS = 60,
		RENDER_SECONDS = 1,

		-- On the back wall, to the right of the Glass.
		POSITION = Vector3.new(36, 14, -65.75),
		WIDTH = 20,
		HEIGHT = 24,
		DEPTH = 0.5,
		TRIM_HEIGHT = 0.16,
		PIXELS_PER_STUD = 25,
		TITLE_SHARE = 0.13, -- of the panel's height
		DEVELOPER_SHARE = 0.2,
		RANK_WIDTH = 0.22, -- of the panel's width
		BEST_WIDTH = 0.18,
		TITLE_TEXT_SIZE = 50,
		ROW_TEXT_SIZE = 36,
		CAPTION_TEXT_SIZE = 32,

		PANEL_COLOR = Color3.fromRGB(14, 17, 25),
		TRIM_COLOR = Color3.fromRGB(70, 180, 255),
		TEXT_COLOR = Color3.fromRGB(235, 245, 255),
		MUTED_COLOR = Color3.fromRGB(130, 145, 170),
		DEVELOPER_COLOR = Color3.fromRGB(255, 200, 110),
		DEVELOPER_BACKGROUND_COLOR = Color3.fromRGB(44, 34, 20),

		TITLE = "HIGHEST STREAKS",
		DEVELOPER_CAPTION = "BEAT THE DEVELOPER",
		DEVELOPER_TAG = "DEV",
		NO_BEST = "-",
		UNKNOWN_NAME = "Player",
	},

	Sprint = {
		LOBBY_SECONDS = 10,
		DURATION_SECONDS = 60,
		RESULTS_SECONDS = 8,
		TICK_SECONDS = 0.25,
	},

	Dev = {
		-- A letter key: function keys need fn held on a Mac.
		DUMP_STROKES_KEY = Enum.KeyCode.H,
		FRAME_SAMPLES = 30,
	},
}

return Config
