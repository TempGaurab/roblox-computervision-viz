--!strict
-- Every tunable for the Pad, the Glass, and the game loop lives here.

local Config = {
	Inference = {
		MIN_INTERVAL = 0.1, -- seconds between inferences: at most 10 per second
	},

	DrawMode = {
		-- Placeholder view until the Glass exists (M4) and stations place it (M5).
		CAMERA_POSITION = Vector3.new(0, 20, 40),
		CAMERA_TARGET = Vector3.new(0, 10, 0),
		ACTION_NAME = "NeuralGlassDrawKeys",
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
