--!strict
-- Locks the camera and the character while drawing, and puts both back afterwards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage.Shared.Config)

local GlassConfig = Config.Glass

local DrawMode = {}

-- Places using the input action system get Roblox's PlayerModule under StarterPlayer, with an
-- `Enabled` flag; older ones get it under PlayerScripts, with GetControls(). Handle both, and don't
-- wait on either: the module doesn't move once the client has loaded.
local function setControlsEnabled(isEnabled: boolean)
	local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
	local module = StarterPlayer:FindFirstChild("PlayerModule") or playerScripts:FindFirstChild("PlayerModule")
	if module == nil then
		warn("[NeuralGlass] PlayerModule not found; can't change character controls")
		return
	end
	-- Roblox's own module, outside our source tree, so the type checker can't follow this require.
	local playerModule = (require :: any)(module)
	if playerModule.ControlModule ~= nil then
		playerModule.ControlModule.Enabled = isEnabled
	elseif isEnabled then
		playerModule:GetControls():Enable()
	else
		playerModule:GetControls():Disable()
	end
end

function DrawMode.enter()
	setControlsEnabled(false)
	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
end

-- Aims square at the Glass and fits it in the screen area the docked pad leaves free, shifting the
-- camera so the Glass is centered in that area rather than in the whole screen.
function DrawMode.frame(dockedExtent: number)
	local camera = workspace.CurrentCamera
	-- The viewport, not a ScreenGui's size: the camera also renders under the top bar inset.
	local screen = camera.ViewportSize
	if screen.X <= 0 or screen.Y <= 0 then
		return
	end
	local isPortrait = screen.Y > screen.X
	local freeWidth = if isPortrait then 1 else math.max(1 - dockedExtent / screen.X, 0.1)
	local freeHeight = if isPortrait then math.max(1 - dockedExtent / screen.Y, 0.1) else 1

	local tanHalfFov = math.tan(math.rad(camera.FieldOfView) / 2)
	local aspect = screen.X / screen.Y
	local margin = Config.DrawMode.FRAMING_MARGIN
	local frameSpan = 2 * GlassConfig.FRAME_THICKNESS
	local fitWidth = (GlassConfig.WIDTH + frameSpan) * margin / (2 * tanHalfFov * aspect * freeWidth)
	local fitHeight = (GlassConfig.HEIGHT + frameSpan) * margin / (2 * tanHalfFov * freeHeight)
	local distance = math.max(fitWidth, fitHeight)

	local viewHeight = 2 * distance * tanHalfFov
	local viewWidth = viewHeight * aspect
	-- The free area's center sits right of the screen center in landscape, and above it in portrait.
	local shiftX = -(1 - freeWidth) / 2 * viewWidth
	local shiftY = -(1 - freeHeight) / 2 * viewHeight

	-- Fit is measured at the front pane, the nearest part of the chamber.
	camera.CFrame = GlassConfig.ORIGIN * CFrame.new(shiftX, shiftY, distance + GlassConfig.DEPTH / 2)
end

function DrawMode.exit()
	setControlsEnabled(true)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local character = Players.LocalPlayer.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid ~= nil then
		camera.CameraSubject = humanoid
	end
end

return DrawMode
