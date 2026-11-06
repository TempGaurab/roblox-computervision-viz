--!strict
-- Shows the live top-3 guesses, a short message when the drawing needs attention, and the model version.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HudLayout = require(script.Parent.HudLayout)

local HudConfig = Config.Hud

type Row = {
	root: Frame,
	digit: TextLabel,
	bar: Frame,
	fill: Frame,
	percent: TextLabel,
	shownDigit: number,
	shownPercent: number,
}

export type Hud = {
	gui: ScreenGui,
	root: Frame,
	rows: { Row },
	message: TextLabel,
	version: TextLabel,
	rootPadding: UIPadding,
	roundRoot: Frame,
	roundPadding: UIPadding,
	prompt: TextLabel,
	result: TextLabel,
	score: TextLabel,
	standings: TextLabel,
}

local Hud = {}

-- Backing and side padding for a panel, off until the compact layout asks for them.
local function addStrip(panel: Frame): UIPadding
	panel.BackgroundColor3 = HudConfig.STRIP_COLOR
	panel.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, HudConfig.CORNER_RADIUS)
	corner.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.Parent = panel
	return padding
end

local function setStrip(panel: Frame, padding: UIPadding, isOn: boolean)
	panel.BackgroundTransparency = if isOn then HudConfig.STRIP_TRANSPARENCY else 1
	local inset = UDim.new(0, if isOn then HudConfig.STRIP_PADDING else 0)
	padding.PaddingLeft = inset
	padding.PaddingRight = inset
end

local function newLabel(parent: Instance, name: string, textSize: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = textSize
	label.TextColor3 = color
	label.Text = ""
	label.Parent = parent
	return label
end

local function newRow(parent: Instance, index: number): Row
	local root = Instance.new("Frame")
	root.Name = `Row{index}`
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = parent

	local digit = newLabel(root, "Digit", HudConfig.Roomy.TEXT_SIZE, HudConfig.TEXT_COLOR)

	local percent = newLabel(root, "Percent", HudConfig.Roomy.TEXT_SIZE, HudConfig.TEXT_COLOR)
	percent.AnchorPoint = Vector2.new(1, 0)
	percent.Position = UDim2.fromScale(1, 0)
	percent.TextXAlignment = Enum.TextXAlignment.Right

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = HudConfig.BAR_BACKGROUND_COLOR
	bar.BorderSizePixel = 0
	bar.Parent = root

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, HudConfig.CORNER_RADIUS)
	barCorner.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = if index == 1 then HudConfig.TOP_BAR_COLOR else HudConfig.BAR_COLOR
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = bar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, HudConfig.CORNER_RADIUS)
	fillCorner.Parent = fill

	return { root = root, digit = digit, bar = bar, fill = fill, percent = percent, shownDigit = -1, shownPercent = -1 }
end

-- Text that shrinks to fit on small screens, up to the given size.
local function newScaledLabel(parent: Instance, name: string, maxSize: number): TextLabel
	local label = newLabel(parent, name, maxSize, HudConfig.TEXT_COLOR)
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextScaled = true
	label.TextWrapped = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxSize
	constraint.Parent = label
	return label
end

function Hud.new(modelVersion: string): Hud
	local gui = Instance.new("ScreenGui")
	gui.Name = "NeuralGlassHud"
	gui.ResetOnSpawn = false

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = gui
	local rootPadding = addStrip(root)

	local rows: { Row } = table.create(HudConfig.TOP_COUNT)
	for index = 1, HudConfig.TOP_COUNT do
		rows[index] = newRow(root, index)
	end

	local message = newLabel(root, "Message", HudConfig.Roomy.MESSAGE_TEXT_SIZE, HudConfig.WARNING_TEXT_COLOR)
	message.TextXAlignment = Enum.TextXAlignment.Right

	local version = newLabel(root, "Version", HudConfig.VERSION_TEXT_SIZE, HudConfig.MUTED_TEXT_COLOR)
	version.TextXAlignment = Enum.TextXAlignment.Right
	version.Text = `model {modelVersion}`

	local roundRoot = Instance.new("Frame")
	roundRoot.Name = "Round"
	roundRoot.BackgroundTransparency = 1
	roundRoot.Visible = false
	roundRoot.Parent = gui
	local roundPadding = addStrip(roundRoot)

	local prompt = newScaledLabel(roundRoot, "Prompt", HudConfig.PROMPT_MAX_TEXT_SIZE)
	prompt.Font = Enum.Font.GothamBold
	local score = newScaledLabel(roundRoot, "Score", HudConfig.SCORE_MAX_TEXT_SIZE)
	score.TextColor3 = HudConfig.MUTED_TEXT_COLOR
	local result = newScaledLabel(roundRoot, "Result", HudConfig.RESULT_MAX_TEXT_SIZE)

	local standings = newLabel(gui, "Standings", HudConfig.Roomy.STANDINGS_TEXT_SIZE, HudConfig.TEXT_COLOR)
	standings.ClipsDescendants = true
	standings.Visible = false

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return {
		gui = gui,
		root = root,
		rows = rows,
		message = message,
		version = version,
		rootPadding = rootPadding,
		roundRoot = roundRoot,
		roundPadding = roundPadding,
		prompt = prompt,
		result = result,
		score = score,
		standings = standings,
	}
end

local function place(frame: GuiObject, rect: HudLayout.Rect)
	frame.Position = UDim2.fromOffset(rect.x, rect.y)
	frame.Size = UDim2.fromOffset(rect.width, rect.height)
end

-- Fits the HUD to the screen and returns the area it leaves for the Glass. `dockedExtent` is what the pad
-- takes from the screen. Call it again whenever the screen changes shape.
function Hud.layOut(hud: Hud, dockedExtent: number): HudLayout.Area
	local screen = hud.gui.AbsoluteSize
	local layout = HudLayout.compute(HudConfig :: any, screen.X, screen.Y, dockedExtent)
	local sizes = layout.sizes

	place(hud.root, layout.top)
	setStrip(hud.root, hud.rootPadding, layout.isCompact)
	for index, row in hud.rows do
		row.root.Position = UDim2.fromOffset(0, (index - 1) * (sizes.ROW_HEIGHT + sizes.ROW_GAP))
		row.root.Size = UDim2.new(1, 0, 0, sizes.ROW_HEIGHT)
		row.digit.Size = UDim2.new(0, sizes.DIGIT_WIDTH, 1, 0)
		row.digit.TextSize = sizes.TEXT_SIZE
		row.percent.Size = UDim2.new(0, sizes.PERCENT_WIDTH, 1, 0)
		row.percent.TextSize = sizes.TEXT_SIZE
		row.bar.Position = UDim2.fromOffset(sizes.DIGIT_WIDTH, 0)
		row.bar.Size = UDim2.new(1, -sizes.DIGIT_WIDTH - sizes.PERCENT_WIDTH, 1, 0)
	end
	local rowsHeight = #hud.rows * (sizes.ROW_HEIGHT + sizes.ROW_GAP)
	hud.version.Visible = not layout.isCompact
	hud.version.Position = UDim2.fromOffset(0, rowsHeight)
	hud.version.Size = UDim2.new(1, 0, 0, sizes.VERSION_HEIGHT)
	hud.message.Position = UDim2.fromOffset(0, rowsHeight + sizes.VERSION_HEIGHT)
	hud.message.Size = UDim2.new(1, 0, 0, sizes.MESSAGE_HEIGHT)
	hud.message.TextSize = sizes.MESSAGE_TEXT_SIZE
	hud.message.TextScaled = layout.isCompact -- the long messages have to fit a narrow column

	place(hud.roundRoot, layout.round)
	setStrip(hud.roundRoot, hud.roundPadding, layout.isCompact)
	hud.prompt.Position = UDim2.fromOffset(0, 0)
	hud.prompt.Size = UDim2.new(1, 0, 0, sizes.PROMPT_HEIGHT)
	hud.score.Position = UDim2.fromOffset(0, sizes.PROMPT_HEIGHT)
	hud.score.Size = UDim2.new(1, 0, 0, sizes.SCORE_HEIGHT)
	hud.result.Position = UDim2.fromOffset(0, sizes.PROMPT_HEIGHT + sizes.SCORE_HEIGHT)
	hud.result.Size = UDim2.new(1, 0, 0, sizes.RESULT_HEIGHT)

	place(hud.standings, layout.standings)
	hud.standings.TextSize = sizes.STANDINGS_TEXT_SIZE
	hud.standings.TextXAlignment = if layout.isCompact then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
	hud.standings.TextYAlignment = if layout.isCompact then Enum.TextYAlignment.Top else Enum.TextYAlignment.Bottom

	return layout.free
end

function Hud.setVisible(hud: Hud, visible: boolean)
	hud.root.Visible = visible
	hud.roundRoot.Visible = visible
	hud.standings.Visible = visible
end

-- One line per player, best first. Empty hides it.
function Hud.setStandings(hud: Hud, text: string)
	hud.standings.Text = text
end

-- `promptText` says what to do; `scoreText` is empty in Free Draw.
function Hud.setRound(hud: Hud, promptText: string, scoreText: string)
	hud.prompt.Text = promptText
	hud.score.Text = scoreText
end

function Hud.setResult(hud: Hud, text: string, isGood: boolean)
	hud.result.Text = text
	hud.result.TextColor3 = if isGood then HudConfig.GOOD_TEXT_COLOR else HudConfig.WARNING_TEXT_COLOR
end

function Hud.setMessage(hud: Hud, text: string)
	if hud.message.Text ~= text then
		hud.message.Text = text
	end
end

function Hud.showTop(hud: Hud, digits: { number }, probs: { number })
	for k, row in hud.rows do
		row.root.Visible = true
		local digit = digits[k]
		if digit ~= row.shownDigit then
			row.shownDigit = digit
			row.digit.Text = tostring(digit)
		end
		local percent = math.round(probs[k] * 100)
		if percent ~= row.shownPercent then
			row.shownPercent = percent
			row.percent.Text = `{percent}%`
			row.fill.Size = UDim2.fromScale(percent / 100, 1)
		end
	end
end

function Hud.hideTop(hud: Hud)
	for _, row in hud.rows do
		row.root.Visible = false
	end
end

return Hud
