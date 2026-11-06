--!strict
-- Every tunable for the Pad, the Glass, and the game loop lives here.

local Config = {
	Inference = {
		MIN_INTERVAL = 0.1, -- seconds between inferences: at most 10 per second
	},

	DrawMode = {
		ACTION_NAME = "NeuralGlassDrawKeys",
		FRAMING_MARGIN = 1.08, -- how much larger than the Glass the framed view is
	},

	Glass = {
		-- Placeholder spot until stations place it (M5). Viewers stand on +Z, with input on their left.
		ORIGIN = CFrame.new(0, 15, -60),
		WIDTH = 44,
		HEIGHT = 22,
		DEPTH = 8,
		FRAME_THICKNESS = 0.6,

		-- Layout, in studs from the chamber center.
		NETWORK_VIEW_SIZE = 12,
		NETWORK_VIEW_X = -15.5,
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

		ORB_MIN_SIZE = 0.5,
		ORB_MAX_SIZE = 1.2,
		HALO_SIZE = 2.4,
		HALO_TRANSPARENCY = 0.75,

		-- Propagation: displayed values chase targets after a per-layer lag, in seconds.
		HIDDEN_LAG_STEP = 0.08,
		SMOOTHING_TAU = 0.12,
		HISTORY_SIZE = 4, -- inference snapshots kept: enough to cover the longest lag at the highest rate

		-- Quantized steps, so writes skip small changes and colors and sequences are made once.
		ORB_LEVELS = 32,
		PIXEL_LEVELS = 32,
		LINK_LEVELS = 8,
		LINK_MIN_WIDTH = 0.04,
		LINK_MAX_WIDTH = 0.28,
		LINK_MIN_OPACITY = 0.15,
		LINK_MAX_OPACITY = 0.95,

		PACKET_COUNT = 300,
		PACKET_SECONDS = 0.45, -- time to cross one link
		PACKET_MAX_RATE = 4, -- packets per second on the strongest link
		PACKET_SIZE = 0.32,
		PACKET_NEGATIVE_SIZE = 0.18, -- smaller, so sign never relies on color alone
		-- Parked above the map: anything below FallenPartsDestroyHeight could be destroyed.
		PACKET_PARK_POSITION = Vector3.new(0, 5000, 0),

		IDLE_BASE = 0.06,
		IDLE_AMPLITUDE = 0.05,
		IDLE_SPEED = 1.2,
		IDLE_PACKET_RATE = 3, -- ambient packets per second
		PHASE_STEP = 0.7, -- radians between neighboring orbs

		BACK_COLOR = Color3.fromRGB(8, 10, 16),
		FRAME_COLOR = Color3.fromRGB(28, 34, 48),
		PANE_COLOR = Color3.fromRGB(150, 200, 255),
		PANE_TRANSPARENCY = 0.9,
		PANE_REFLECTANCE = 0.05,
		ORB_DIM_COLOR = Color3.fromRGB(16, 30, 58),
		ORB_BRIGHT_COLOR = Color3.fromRGB(190, 240, 255),
		PIXEL_OFF_COLOR = Color3.fromRGB(10, 13, 20),
		PIXEL_ON_COLOR = Color3.fromRGB(235, 245, 255),
		-- A colorblind-safe pair.
		POSITIVE_COLOR = Color3.fromRGB(70, 180, 255),
		NEGATIVE_COLOR = Color3.fromRGB(255, 140, 40),
		TEXT_COLOR = Color3.fromRGB(235, 245, 255),
		BAR_BACKGROUND_COLOR = Color3.fromRGB(28, 34, 48),
		BAR_COLOR = Color3.fromRGB(90, 170, 255),
		WINNER_BAR_COLOR = Color3.fromRGB(190, 240, 255),
	},

	Pad = {
		MARGIN = 16, -- pixels from the viewport edge
		GAP = 8, -- pixels between the pad, the controls, and each button
		CONTROLS_HEIGHT = 44,
		LANDSCAPE_MAX_WIDTH = 0.42, -- share of viewport width
		PORTRAIT_MAX_HEIGHT = 0.55, -- share of viewport height
		MIN_POINT_DISTANCE = 0.01, -- share of pad size a pointer must move to add a point
		INK_THICKNESS = 0.05, -- share of pad size
		SLIDE_SECONDS = 0.25,
		CORNER_RADIUS = 8,
		BUTTON_TEXT_SIZE = 16,

		SURFACE_COLOR = Color3.fromRGB(14, 18, 28),
		SURFACE_STROKE_COLOR = Color3.fromRGB(90, 170, 255),
		SURFACE_STROKE_THICKNESS = 2,
		INK_COLOR = Color3.fromRGB(235, 245, 255),
		BUTTON_COLOR = Color3.fromRGB(38, 46, 66),
		SUBMIT_COLOR = Color3.fromRGB(40, 110, 200),
		BUTTON_TEXT_COLOR = Color3.fromRGB(235, 245, 255),
	},

	Hud = {
		TOP_COUNT = 3,
		MARGIN = 16,
		WIDTH = 220,
		ROW_HEIGHT = 30,
		ROW_GAP = 6,
		DIGIT_WIDTH = 28,
		PERCENT_WIDTH = 52,
		TEXT_SIZE = 20,
		MESSAGE_HEIGHT = 28,
		MESSAGE_TEXT_SIZE = 16,
		VERSION_HEIGHT = 14,
		VERSION_TEXT_SIZE = 11,
		CORNER_RADIUS = 6,

		TEXT_COLOR = Color3.fromRGB(235, 245, 255),
		MUTED_TEXT_COLOR = Color3.fromRGB(130, 145, 170),
		WARNING_TEXT_COLOR = Color3.fromRGB(255, 190, 90),
		BAR_BACKGROUND_COLOR = Color3.fromRGB(38, 46, 66),
		BAR_COLOR = Color3.fromRGB(90, 170, 255),
		TOP_BAR_COLOR = Color3.fromRGB(150, 225, 255),

		MESSAGE_TOO_SMALL = "Draw bigger",
		MESSAGE_LIMIT = "Clear to keep drawing",
	},

	Dev = {
		TOGGLE_DRAW_KEY = Enum.KeyCode.F2,
		DUMP_STROKES_KEY = Enum.KeyCode.F3,
		FRAME_SAMPLES = 30,
	},
}

return Config
