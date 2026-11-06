--!strict
-- Client bootstrap: stations -> Glass; Pad -> inference -> Glass.

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local RunService = game:GetService("RunService")

local DrawSession = require(script.Parent.DrawSession)

local session = DrawSession.new()
DrawSession.watchCharacter(session)

if RunService:IsStudio() then
	local Harness = require(script.Parent.Dev.Harness)
	Harness.attach(session)
end
