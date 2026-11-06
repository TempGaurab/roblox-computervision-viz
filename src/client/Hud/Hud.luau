--!strict
-- Shows the live top-3 guesses, a short message when the drawing needs attention, and the model version.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local HudConfig = Config.Hud

type Row = {
	root: Frame,
	digit: TextLabel,
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
	roundRoot: Frame,
	prompt: TextLabel,
	result: TextLabel,
	score: TextLabel,
}

local Hud = {}

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
	root.Size = UDim2.new(1, 0, 0, HudConfig.ROW_HEIGHT)
	root.Position = UDim2.fromOffset(0, (index - 1) * (HudConfig.ROW_HEIGHT + HudConfig.ROW_GAP))
	root.Visible = false
	root.Parent = parent

	local digit = newLabel(root, "Digit", HudConfig.TEXT_SIZE, HudConfig.TEXT_COLOR)
	digit.Size = UDim2.new(0, HudConfig.DIGIT_WIDTH, 1, 0)

	local percent = newLabel(root, "Percent", HudConfig.TEXT_SIZE, HudConfig.TEXT_COLOR)
	percent.AnchorPoint = Vector2.new(1, 0)
	percent.Position = UDim2.fromScale(1, 0)
	percent.Size = UDim2.new(0, HudConfig.PERCENT_WIDTH, 1, 0)
	percent.TextXAlignment = Enum.TextXAlignment.Right

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = HudConfig.BAR_BACKGROUND_COLOR
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(HudConfig.DIGIT_WIDTH, 0)
	bar.Size = UDim2.new(1, -HudConfig.DIGIT_WIDTH - HudConfig.PERCENT_WIDTH, 1, 0)
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

	return { root = root, digit = digit, fill = fill, percent = percent, shownDigit = -1, shownPercent = -1 }
end

-- Text that shrinks to fit on small screens, up to the given size.
local function newScaledLabel(parent: Instance, name: string, top: number, height: number, maxSize: number): TextLabel
	local label = newLabel(parent, name, maxSize, HudConfig.TEXT_COLOR)
	label.Position = UDim2.fromOffset(0, top)
	label.Size = UDim2.new(1, 0, 0, height)
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

	local rowsHeight = HudConfig.TOP_COUNT * (HudConfig.ROW_HEIGHT + HudConfig.ROW_GAP)
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(1, -HudConfig.MARGIN, 0, HudConfig.MARGIN)
	root.Size = UDim2.fromOffset(HudConfig.WIDTH, rowsHeight + HudConfig.MESSAGE_HEIGHT + HudConfig.VERSION_HEIGHT)
	root.Visible = false
	root.Parent = gui

	local rows: { Row } = table.create(HudConfig.TOP_COUNT)
	for index = 1, HudConfig.TOP_COUNT do
		rows[index] = newRow(root, index)
	end

	local message = newLabel(root, "Message", HudConfig.MESSAGE_TEXT_SIZE, HudConfig.WARNING_TEXT_COLOR)
	message.Position = UDim2.fromOffset(0, rowsHeight + HudConfig.VERSION_HEIGHT)
	message.Size = UDim2.new(1, 0, 0, HudConfig.MESSAGE_HEIGHT)
	message.TextXAlignment = Enum.TextXAlignment.Right

	local version = newLabel(root, "Version", HudConfig.VERSION_TEXT_SIZE, HudConfig.MUTED_TEXT_COLOR)
	version.Position = UDim2.fromOffset(0, rowsHeight)
	version.Size = UDim2.new(1, 0, 0, HudConfig.VERSION_HEIGHT)
	version.TextXAlignment = Enum.TextXAlignment.Right
	version.Text = `model {modelVersion}`

	local promptHeight = HudConfig.PROMPT_HEIGHT
	local resultHeight = HudConfig.RESULT_HEIGHT
	local scoreHeight = HudConfig.SCORE_HEIGHT
	local roundRoot = Instance.new("Frame")
	roundRoot.Name = "Round"
	roundRoot.BackgroundTransparency = 1
	roundRoot.AnchorPoint = Vector2.new(1, 0)
	roundRoot.Position = UDim2.new(1, -(HudConfig.MARGIN + HudConfig.WIDTH + HudConfig.ROUND_GAP), 0, HudConfig.MARGIN)
	roundRoot.Size = UDim2.new(HudConfig.ROUND_WIDTH, 0, 0, promptHeight + scoreHeight + resultHeight)
	roundRoot.Visible = false
	roundRoot.Parent = gui

	local prompt = newScaledLabel(roundRoot, "Prompt", 0, promptHeight, HudConfig.PROMPT_MAX_TEXT_SIZE)
	prompt.Font = Enum.Font.GothamBold
	local score = newScaledLabel(roundRoot, "Score", promptHeight, scoreHeight, HudConfig.SCORE_MAX_TEXT_SIZE)
	score.TextColor3 = HudConfig.MUTED_TEXT_COLOR
	local result =
		newScaledLabel(roundRoot, "Result", promptHeight + scoreHeight, resultHeight, HudConfig.RESULT_MAX_TEXT_SIZE)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return {
		gui = gui,
		root = root,
		rows = rows,
		message = message,
		roundRoot = roundRoot,
		prompt = prompt,
		result = result,
		score = score,
	}
end

function Hud.setVisible(hud: Hud, visible: boolean)
	hud.root.Visible = visible
	hud.roundRoot.Visible = visible
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
