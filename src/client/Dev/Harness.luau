--!strict
-- Studio-only test hooks. Everything here does nothing outside Studio, and this is the only code
-- allowed to print a drawing (Rule 4). See "Verifying your work" in claude.md.
--
-- The command bar and Studio MCP get their own copy of this module, separate from the running client,
-- so every call goes through a BindableFunction that the client's copy creates in attach().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Base64 = require(ReplicatedStorage.Shared.NeuralCore.Base64)
local Strokes = require(ReplicatedStorage.Shared.NeuralCore.Strokes)
local DrawSession = require(script.Parent.Parent.DrawSession)
local GlassView = require(script.Parent.Parent.Glass.GlassView)
local Fixtures = require(script.Parent.Fixtures)
local Pad = require(script.Parent.Parent.Pad.Pad)

local BRIDGE_NAME = "Bridge"

local Harness = {}

local function statusOf(session: DrawSession.DrawSession): { [string]: any }
	local inference = session.inference
	local probabilities = table.clone(inference.scratch.probs)
	local ok = inference.status == "ok"
	return {
		status = inference.status,
		prediction = if ok then inference.topDigits[1] else nil,
		probability = if ok then inference.topProbs[1] else nil,
		probabilities = if ok then probabilities else nil,
		modelVersion = inference.model.version,
		inferenceMs = inference.lastSeconds * 1000,
		inferenceCount = inference.runCount,
		isDrawMode = session.isActive,
		pointCount = session.pad.strokes.pointCount,
		strokeCount = session.pad.strokes.strokeCount,
		inkFrames = session.pad.ink.jointCount + session.pad.ink.segmentCount,
		edgeCount = inference.edgeCount,
		glassInstances = GlassView.instanceCount(session.glass),
		glassUpdateMs = session.glass.lastStepSeconds * 1000,
		activePackets = session.glass.activePackets,
		mode = session.mode,
		round = session.round,
	}
end

local function replay(session: DrawSession.DrawSession, encoded: string): { [string]: any }
	local bytes = Base64.decode(encoded)
	assert(bytes ~= nil, "replay: not valid base64")
	local strokes = Strokes.decode(bytes)
	assert(strokes ~= nil, "replay: not valid strokes")
	Pad.load(session.pad, strokes)
	DrawSession.inferNow(session)
	return statusOf(session)
end

local function sampleFrameMs(): number
	local total = 0
	for _ = 1, Config.Dev.FRAME_SAMPLES do
		total += RunService.PreRender:Wait()
	end
	return total / Config.Dev.FRAME_SAMPLES * 1000
end

local function selfTest(session: DrawSession.DrawSession): { [string]: any }
	local wasActive = session.isActive
	DrawSession.enter(session, "free")

	local results: { { [string]: any } } = {}
	local correct = 0
	local slowestMs = 0
	for _, fixture in Fixtures :: { any } do
		local result = replay(session, fixture.strokes)
		local isCorrect = result.prediction == fixture.digit
		if isCorrect then
			correct += 1
		end
		slowestMs = math.max(slowestMs, result.inferenceMs)
		table.insert(results, {
			digit = fixture.digit,
			prediction = result.prediction,
			probability = result.probability,
			correct = isCorrect,
			inferenceMs = result.inferenceMs,
		})
	end
	local frameMs = sampleFrameMs()
	local glassUpdateMs = session.glass.lastStepSeconds * 1000

	Pad.clear(session.pad)
	DrawSession.inferNow(session)
	if not wasActive then
		DrawSession.exit(session)
	end

	return {
		fixtureCount = #results,
		correct = correct,
		slowestInferenceMs = slowestMs,
		frameMs = frameMs,
		glassUpdateMs = glassUpdateMs,
		glassInstances = GlassView.instanceCount(session.glass),
		results = results,
	}
end

local function dumpStrokes(session: DrawSession.DrawSession): string
	local encoded = Base64.encode(Strokes.encode(session.pad.strokes))
	print(`[Harness] strokes: {encoded}`)
	return encoded
end

-- Called once by the running client, in Studio only.
function Harness.attach(session: DrawSession.DrawSession)
	if not RunService:IsStudio() then
		return
	end

	local handlers: { [string]: (...any) -> any } = {
		selfTest = function()
			return selfTest(session)
		end,
		replay = function(encoded: string)
			return replay(session, encoded)
		end,
		state = function()
			return statusOf(session)
		end,
		dumpStrokes = function()
			return dumpStrokes(session)
		end,
	}

	local bridge = Instance.new("BindableFunction")
	bridge.Name = BRIDGE_NAME
	bridge.OnInvoke = function(name: string, ...: any): any
		return handlers[name](...)
	end
	bridge.Parent = script

	-- H prints the current drawing.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Config.Dev.DUMP_STROKES_KEY then
			dumpStrokes(session)
		end
	end)
end

local function call(name: string, ...: any): any
	if not RunService:IsStudio() then
		return nil
	end
	local bridge = script:FindFirstChild(BRIDGE_NAME)
	assert(bridge ~= nil and bridge:IsA("BindableFunction"), "Harness: the client is not running")
	return bridge:Invoke(name, ...)
end

-- Replays every fixture through the real Pad and returns predictions and timings.
function Harness.selfTest(): any
	return call("selfTest")
end

-- Loads a base64 drawing onto the Pad and returns the resulting state.
function Harness.replay(strokesBase64: string): any
	return call("replay", strokesBase64)
end

-- Returns prediction, probabilities, model version, timings, and instance counts.
function Harness.state(): any
	return call("state")
end

-- Prints the current drawing as base64, to save as tests/fixtures/strokes/<digit>_<n>.b64.
function Harness.dumpStrokes(): any
	return call("dumpStrokes")
end

return Harness
