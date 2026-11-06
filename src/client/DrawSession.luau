--!strict
-- A player's time at the pad: wires Pad -> Inference -> Hud, and handles entering and leaving Draw Mode.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cleanup = require(script.Parent.Cleanup)
local DrawMode = require(script.Parent.Pad.DrawMode)
local GlassView = require(script.Parent.Glass.GlassView)
local Hud = require(script.Parent.Hud.Hud)
local Inference = require(script.Parent.Inference)
local Pad = require(script.Parent.Pad.Pad)
local PadView = require(script.Parent.Pad.PadView)

export type Mode = "free" | "challenge"

export type DrawSession = {
	pad: Pad.Pad,
	hud: Hud.Hud,
	glass: GlassView.GlassView,
	inference: Inference.Inference,
	mode: Mode,
	isActive: boolean,
	limitReached: boolean,
	activeCleanup: Cleanup.Cleanup,
}

local DrawSession = {}

local function refresh(session: DrawSession)
	local inference = session.inference
	local hud = session.hud
	if inference.status == "ok" then
		Hud.showTop(hud, inference.topDigits, inference.topProbs)
	else
		Hud.hideTop(hud)
	end
	if session.limitReached then
		Hud.setMessage(hud, Config.Hud.MESSAGE_LIMIT)
	elseif inference.status == "tooSmall" then
		Hud.setMessage(hud, Config.Hud.MESSAGE_TOO_SMALL)
	else
		Hud.setMessage(hud, "")
	end
	GlassView.setResult(session.glass, inference)
end

local function frameCamera(session: DrawSession)
	DrawMode.frame(PadView.dockedExtent(session.pad.view))
end

-- Runs the pending inference immediately. The harness uses this to read a result without waiting.
function DrawSession.inferNow(session: DrawSession)
	Inference.run(session.inference, session.pad.strokes)
	refresh(session)
end

function DrawSession.new(): DrawSession
	local session: DrawSession
	local pad = Pad.new({
		onChanged = function()
			session.limitReached = session.pad.limitReached
			Inference.markDirty(session.inference)
		end,
		onLimit = function()
			session.limitReached = true
			refresh(session)
		end,
		onSubmit = function()
			-- Validated Submit arrives with the game loop in M5.
		end,
		onExit = function()
			DrawSession.exit(session)
		end,
	})

	local inference = Inference.new()
	session = {
		pad = pad,
		hud = Hud.new(inference.model.version),
		glass = GlassView.new(inference.model),
		inference = inference,
		mode = "free",
		isActive = false,
		limitReached = false,
		activeCleanup = Cleanup.new(),
	}
	return session
end

local function handleKey(session: DrawSession, inputState: Enum.UserInputState, input: InputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return
	end
	local keyCode = input.KeyCode
	if keyCode == Enum.KeyCode.C then
		Pad.clear(session.pad)
	elseif keyCode == Enum.KeyCode.Z then
		Pad.undo(session.pad)
	elseif keyCode == Enum.KeyCode.Return then
		if session.mode == "challenge" then
			session.pad.callbacks.onSubmit()
		end
	elseif keyCode == Enum.KeyCode.X or keyCode == Enum.KeyCode.ButtonB then
		DrawSession.exit(session)
	end
end

function DrawSession.enter(session: DrawSession, mode: Mode)
	if session.isActive then
		return
	end
	session.isActive = true
	session.mode = mode

	DrawMode.enter()
	frameCamera(session)
	Pad.open(session.pad, mode == "challenge")
	Hud.setVisible(session.hud, true)
	refresh(session)

	local cleanup = session.activeCleanup
	Cleanup.connect(
		cleanup,
		session.pad.view.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			frameCamera(session)
		end)
	)
	Cleanup.connect(
		cleanup,
		RunService.PreRender:Connect(function()
			if Inference.step(session.inference, session.pad.strokes) then
				refresh(session)
			end
		end)
	)
	ContextActionService:BindAction(
		Config.DrawMode.ACTION_NAME,
		function(_: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			handleKey(session, inputState, input)
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.KeyCode.C,
		Enum.KeyCode.Z,
		Enum.KeyCode.Return,
		Enum.KeyCode.X,
		Enum.KeyCode.ButtonB
	)
	Cleanup.addTask(cleanup, function()
		ContextActionService:UnbindAction(Config.DrawMode.ACTION_NAME)
	end)
end

function DrawSession.exit(session: DrawSession)
	if not session.isActive then
		return
	end
	session.isActive = false
	Cleanup.run(session.activeCleanup)
	Pad.close(session.pad)
	Hud.setVisible(session.hud, false)
	DrawMode.exit()
end

-- Leaves Draw Mode whenever the character dies or is replaced, so controls and camera are never stuck.
function DrawSession.watchCharacter(session: DrawSession)
	local localPlayer = Players.LocalPlayer
	local diedConnection: RBXScriptConnection? = nil

	local function onCharacter(character: Model)
		if diedConnection ~= nil then
			diedConnection:Disconnect()
		end
		DrawSession.exit(session)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		diedConnection = humanoid.Died:Connect(function()
			DrawSession.exit(session)
		end)
	end

	localPlayer.CharacterAdded:Connect(onCharacter)
	if localPlayer.Character ~= nil then
		onCharacter(localPlayer.Character)
	end
end

return DrawSession
