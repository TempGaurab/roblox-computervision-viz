--!strict
-- Client bootstrap: the server grants a station -> Draw Mode; Pad -> inference -> Glass.

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
DrawSession.connectServer(session)

-- Attached before watching the character, which can wait on the Humanoid.
if isStudio then
	local Harness = require(script.Parent.Dev.Harness)
	Harness.attach(session)
	print("[NeuralGlass] client ready: walk up to a station to draw.")
end

DrawSession.watchCharacter(session)
