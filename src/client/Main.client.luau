--!strict
-- Client bootstrap: stations -> Glass; Pad -> inference -> Glass.

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local RunService = game:GetService("RunService")

local isStudio = RunService:IsStudio()
if isStudio then
	print("[NeuralGlass] client starting")
end

local DrawSession = require(script.Parent.DrawSession)

local session = DrawSession.new()

-- Attached before watching the character, which can wait on the Humanoid.
if isStudio then
	local Harness = require(script.Parent.Dev.Harness)
	Harness.attach(session)
	print("[NeuralGlass] client ready: the Glass is built at Workspace.TheGlass. Press F2 to draw.")
end

DrawSession.watchCharacter(session)
