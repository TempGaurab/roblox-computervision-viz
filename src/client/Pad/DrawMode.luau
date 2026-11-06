--!strict
-- Locks the camera and the character while drawing, and puts both back afterwards.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage.Shared.Config)
local HudLayout = require(script.Parent.Parent.Hud.HudLayout)

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

-- The lab's signs would crowd the framed Glass, and their edges would poke in at the side. This only
-- changes this player's own view.
local function setSignsShown(isShown: boolean)
	local lab = workspace:FindFirstChild("Lab")
	if lab == nil then
		return
	end
	for _, name in Config.DrawMode.HIDDEN_SIGNS do
		local sign = lab:FindFirstChild(name)
		local gui = if sign ~= nil then sign:FindFirstChildOfClass("SurfaceGui") else nil
		if gui ~= nil then
			gui.Enabled = isShown
		end
	end
end

function DrawMode.enter()
	setControlsEnabled(false)
	setSignsShown(false)
	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
end

-- Aims square at the Glass and fits it in `free`, the area of the ScreenGui the pad and HUD leave open,
-- shifting the camera so the Glass is centered there rather than in the whole screen.
function DrawMode.frame(free: HudLayout.Area)
	local camera = workspace.CurrentCamera
	-- The viewport, not a ScreenGui's size: the camera also renders under the top bar inset.
	local screen = camera.ViewportSize
	if screen.X <= 0 or screen.Y <= 0 then
		return
	end
	local inset = GuiService:GetGuiInset()
	local left, right = free.left + inset.X, free.right + inset.X
	local top, bottom = free.top + inset.Y, free.bottom + inset.Y
	local freeWidth = math.max((right - left) / screen.X, Config.DrawMode.MIN_FREE_SHARE)
	local freeHeight = math.max((bottom - top) / screen.Y, Config.DrawMode.MIN_FREE_SHARE)

	local tanHalfFov = math.tan(math.rad(camera.FieldOfView) / 2)
	local aspect = screen.X / screen.Y
	local margin = Config.DrawMode.FRAMING_MARGIN
	local frameSpan = 2 * GlassConfig.FRAME_THICKNESS
	local fitWidth = (GlassConfig.WIDTH + frameSpan) * margin / (2 * tanHalfFov * aspect * freeWidth)
	local fitHeight = (GlassConfig.HEIGHT + frameSpan) * margin / (2 * tanHalfFov * freeHeight)
	local distance = math.max(fitWidth, fitHeight)

	local viewHeight = 2 * distance * tanHalfFov
	local viewWidth = viewHeight * aspect
	-- Move the camera opposite to how far the free area's center is from the screen's.
	local shiftX = -((left + right) / 2 / screen.X - 0.5) * viewWidth
	local shiftY = ((top + bottom) / 2 / screen.Y - 0.5) * viewHeight

	-- Fit is measured at the front pane, the nearest part of the chamber.
	camera.CFrame = GlassConfig.ORIGIN * CFrame.new(shiftX, shiftY, distance + GlassConfig.DEPTH / 2)
end

function DrawMode.exit()
	setControlsEnabled(true)
	setSignsShown(true)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local character = Players.LocalPlayer.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid ~= nil then
		camera.CameraSubject = humanoid
	end
end

return DrawMode
