--!strict
-- Locks the camera and the character while drawing, and puts both back afterwards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DrawMode = {}

local function controls(): any
	local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
	-- Roblox's own module, outside our source tree, so the type checker can't follow this require.
	local playerModule = (require :: any)(playerScripts:WaitForChild("PlayerModule"))
	return playerModule:GetControls()
end

function DrawMode.enter()
	controls():Disable()
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(Config.DrawMode.CAMERA_POSITION, Config.DrawMode.CAMERA_TARGET)
end

function DrawMode.exit()
	controls():Enable()
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local character = Players.LocalPlayer.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid ~= nil then
		camera.CameraSubject = humanoid
	end
end

return DrawMode
