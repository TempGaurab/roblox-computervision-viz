--!strict
-- The pad's GUI: a tablet with a square drawing screen and a row of controls in its body, docked left
-- in landscape and at the bottom in portrait, laid out again whenever the screen changes shape.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local PadConfig = Config.Pad

export type PadView = {
	gui: ScreenGui,
	root: Frame,
	surface: Frame,
	inkLayer: Frame,
	clearButton: TextButton,
	undoButton: TextButton,
	submitButton: TextButton,
	exitButton: TextButton,
	isOpen: boolean,
	slideTween: Tween?,
}

local PadView = {}

local function newButton(parent: Instance, name: string, text: string, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.TextSize = PadConfig.BUTTON_TEXT_SIZE
	button.Font = Enum.Font.GothamMedium
	button.TextColor3 = PadConfig.BUTTON_TEXT_COLOR
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, PadConfig.CORNER_RADIUS)
	corner.Parent = button
	return button
end

-- Everything in the tablet's height that isn't the drawing screen.
local function verticalChrome(): number
	return 2 * PadConfig.BEZEL + PadConfig.GAP + PadConfig.CONTROLS_HEIGHT
end

-- The side of the square drawing screen.
local function sideFor(screen: Vector2): number
	local margin = PadConfig.MARGIN
	local chrome = verticalChrome()
	if screen.Y > screen.X then
		local widthLimit = screen.X - 2 * margin - 2 * PadConfig.BEZEL
		return math.min(widthLimit, screen.Y * PadConfig.PORTRAIT_MAX_HEIGHT - chrome)
	end
	return math.min(screen.X * PadConfig.LANDSCAPE_MAX_WIDTH, screen.Y - 2 * margin - chrome)
end

-- Returns the pixels the docked pad takes from the side or bottom it docks to.
function PadView.dockedExtent(view: PadView): number
	local screen = view.gui.AbsoluteSize
	local side = sideFor(screen)
	if screen.Y > screen.X then
		return side + verticalChrome() + 2 * PadConfig.MARGIN
	end
	return side + 2 * PadConfig.BEZEL + 2 * PadConfig.MARGIN
end

-- Returns where the root sits when open, and where it hides when closed.
local function layOut(view: PadView): (UDim2, UDim2)
	local screen = view.gui.AbsoluteSize
	local margin = PadConfig.MARGIN
	local gap = PadConfig.GAP
	local bezel = PadConfig.BEZEL
	local controlsHeight = PadConfig.CONTROLS_HEIGHT

	local side = math.max(sideFor(screen), 0)
	local tabletWidth = side + 2 * bezel
	local tabletHeight = side + verticalChrome()

	local open: UDim2
	local closed: UDim2
	if screen.Y > screen.X then
		local x = (screen.X - tabletWidth) / 2
		open = UDim2.fromOffset(x, screen.Y - tabletHeight - margin)
		closed = UDim2.fromOffset(x, screen.Y + margin)
	else
		local y = (screen.Y - tabletHeight) / 2
		open = UDim2.fromOffset(margin, y)
		closed = UDim2.fromOffset(-tabletWidth - margin, y)
	end

	view.root.Size = UDim2.fromOffset(tabletWidth, tabletHeight)
	view.surface.Position = UDim2.fromOffset(bezel, bezel)
	view.surface.Size = UDim2.fromOffset(side, side)

	local buttons = { view.clearButton, view.undoButton, view.submitButton, view.exitButton }
	local visibleCount = 0
	for _, button in buttons do
		if button.Visible then
			visibleCount += 1
		end
	end
	local buttonWidth = (side - gap * (visibleCount - 1)) / visibleCount
	local slot = 0
	for _, button in buttons do
		if button.Visible then
			button.Position = UDim2.fromOffset(bezel + slot * (buttonWidth + gap), bezel + side + gap)
			button.Size = UDim2.fromOffset(buttonWidth, controlsHeight)
			slot += 1
		end
	end
	return open, closed
end

local function applyLayout(view: PadView)
	local open, closed = layOut(view)
	if view.slideTween == nil then
		view.root.Position = if view.isOpen then open else closed
	end
end

local function slide(view: PadView, target: UDim2, onDone: (() -> ())?)
	if view.slideTween ~= nil then
		view.slideTween:Cancel()
	end
	local info = TweenInfo.new(PadConfig.SLIDE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(view.root, info, { Position = target })
	view.slideTween = tween
	tween.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed then
			view.slideTween = nil
			if onDone ~= nil then
				onDone()
			end
		end
	end)
	tween:Play()
end

function PadView.new(): PadView
	local localPlayer = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "NeuralGlassPad"
	gui.ResetOnSpawn = false
	-- Keeps AbsolutePosition in the same space as InputObject.Position.
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("Frame")
	root.Name = "Tablet"
	root.BackgroundColor3 = PadConfig.TABLET_COLOR
	root.BorderSizePixel = 0
	root.Active = true
	root.Visible = false
	root.Parent = gui

	local tabletCorner = Instance.new("UICorner")
	tabletCorner.CornerRadius = UDim.new(0, PadConfig.TABLET_CORNER_RADIUS)
	tabletCorner.Parent = root

	local tabletStroke = Instance.new("UIStroke")
	tabletStroke.Color = PadConfig.TABLET_STROKE_COLOR
	tabletStroke.Thickness = PadConfig.TABLET_STROKE_THICKNESS
	tabletStroke.Parent = root

	local cameraDot = Instance.new("Frame")
	cameraDot.Name = "CameraDot"
	cameraDot.AnchorPoint = Vector2.new(0.5, 0.5)
	cameraDot.Position = UDim2.new(0.5, 0, 0, PadConfig.BEZEL / 2)
	cameraDot.Size = UDim2.fromOffset(PadConfig.CAMERA_DOT_SIZE, PadConfig.CAMERA_DOT_SIZE)
	cameraDot.BackgroundColor3 = PadConfig.CAMERA_DOT_COLOR
	cameraDot.BorderSizePixel = 0
	cameraDot.Parent = root

	local cameraDotCorner = Instance.new("UICorner")
	cameraDotCorner.CornerRadius = UDim.new(0.5, 0)
	cameraDotCorner.Parent = cameraDot

	local surface = Instance.new("Frame")
	surface.Name = "Surface"
	surface.BackgroundColor3 = PadConfig.SURFACE_COLOR
	surface.BorderSizePixel = 0
	surface.Active = true
	surface.ClipsDescendants = true
	surface.Parent = root

	local surfaceCorner = Instance.new("UICorner")
	surfaceCorner.CornerRadius = UDim.new(0, PadConfig.SCREEN_CORNER_RADIUS)
	surfaceCorner.Parent = surface

	local stroke = Instance.new("UIStroke")
	stroke.Color = PadConfig.SURFACE_STROKE_COLOR
	stroke.Thickness = PadConfig.SURFACE_STROKE_THICKNESS
	stroke.Parent = surface

	-- Not parented to the surface yet: Ink fills it with the whole pool first.
	local inkLayer = Instance.new("Frame")
	inkLayer.Name = "Ink"
	inkLayer.BackgroundTransparency = 1
	inkLayer.Size = UDim2.fromScale(1, 1)

	local view: PadView = {
		gui = gui,
		root = root,
		surface = surface,
		inkLayer = inkLayer,
		clearButton = newButton(root, "Clear", "Clear", PadConfig.BUTTON_COLOR),
		undoButton = newButton(root, "Undo", "Undo", PadConfig.BUTTON_COLOR),
		submitButton = newButton(root, "Submit", "Submit", PadConfig.SUBMIT_COLOR),
		exitButton = newButton(root, "Exit", "Exit", PadConfig.BUTTON_COLOR),
		isOpen = false,
		slideTween = nil,
	}

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		applyLayout(view)
	end)
	applyLayout(view)
	return view
end

function PadView.open(view: PadView, showSubmit: boolean)
	view.isOpen = true
	view.submitButton.Visible = showSubmit
	view.root.Visible = true
	local open = layOut(view)
	slide(view, open)
end

function PadView.close(view: PadView)
	view.isOpen = false
	local _, closed = layOut(view)
	slide(view, closed, function()
		view.root.Visible = false
	end)
end

return PadView
