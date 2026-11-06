--!strict
-- A player's time at the pad: wires Pad -> Inference -> Hud, and handles entering and leaving Draw Mode.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Strokes = require(ReplicatedStorage.Shared.NeuralCore.Strokes)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Cleanup = require(script.Parent.Cleanup)
local DrawMode = require(script.Parent.Pad.DrawMode)
local GlassView = require(script.Parent.Glass.GlassView)
local Hud = require(script.Parent.Hud.Hud)
local Inference = require(script.Parent.Inference)
local Pad = require(script.Parent.Pad.Pad)
local PadView = require(script.Parent.Pad.PadView)

local Net = ReplicatedStorage.Net

export type Mode = Protocol.Mode

export type DrawSession = {
	pad: Pad.Pad,
	hud: Hud.Hud,
	glass: GlassView.GlassView,
	inference: Inference.Inference,
	mode: Mode,
	isActive: boolean,
	limitReached: boolean,
	isSubmitting: boolean,
	round: Protocol.RoundState?,
	shownSeconds: number, -- the countdown on screen, so it only redraws when the number changes
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

-- "a 7", or "an 8".
local function withArticle(digit: number): string
	return `{if digit == 8 then "an" else "a"} {digit}`
end

local function secondsLeft(sprint: Protocol.SprintView): number
	return math.max(math.ceil(sprint.endsAt - workspace:GetServerTimeNow()), 0)
end

local function standingsText(sprint: Protocol.SprintView): string
	local lines: { string } = {}
	local userId = Players.LocalPlayer.UserId
	for rank, standing in sprint.standings do
		local name = if standing.userId == userId then Config.Hud.STANDINGS_YOU else standing.name
		table.insert(lines, string.format(Config.Hud.STANDINGS_LINE, rank, name, standing.score))
	end
	return table.concat(lines, "\n")
end

local function resultsHeadline(sprint: Protocol.SprintView): string
	local standings = sprint.standings
	local first = standings[1]
	if first == nil or #standings < 2 or first.score == 0 then
		return Config.Hud.PROMPT_TIME_UP
	end
	local userId = Players.LocalPlayer.UserId
	local topCount = 0
	local isOnTop = false
	for _, standing in standings do
		if standing.score == first.score then
			topCount += 1
			isOnTop = isOnTop or standing.userId == userId
		end
	end
	if not isOnTop then
		return string.format(Config.Hud.PROMPT_THEY_WON, first.name)
	end
	return if topCount > 1 then Config.Hud.PROMPT_YOU_TIED else Config.Hud.PROMPT_YOU_WON
end

local function showSprint(session: DrawSession, round: Protocol.RoundState, sprint: Protocol.SprintView)
	local hud = session.hud
	local seconds = secondsLeft(sprint)
	session.shownSeconds = seconds
	local hudConfig = Config.Hud
	local prompt: string
	local line: string
	if sprint.isWaiting then
		prompt = hudConfig.PROMPT_WAITING
		line = ""
	elseif sprint.phase == "running" and round.target ~= nil then
		prompt = string.format(hudConfig.PROMPT_DRAW, withArticle(round.target))
		line = string.format(hudConfig.SPRINT_RUNNING_LINE, round.score, seconds // 60, seconds % 60)
	elseif sprint.phase == "results" then
		prompt = resultsHeadline(sprint)
		line = string.format(hudConfig.SPRINT_SCORE_LINE, round.score)
			.. "  ·  "
			.. string.format(hudConfig.SPRINT_NEXT_LINE, seconds)
	else
		prompt = hudConfig.PROMPT_GET_READY
		line = string.format(hudConfig.SPRINT_STARTS_LINE, seconds)
	end
	Hud.setRound(hud, prompt, line)
	Hud.setStandings(hud, standingsText(sprint))
end

local function showRound(session: DrawSession)
	local round = session.round
	local hud = session.hud
	if round ~= nil and round.sprint ~= nil then
		showSprint(session, round, round.sprint)
		return
	end
	Hud.setStandings(hud, "")
	if round == nil or round.mode == "free" or round.target == nil then
		Hud.setRound(hud, Config.Hud.PROMPT_FREE, "")
	else
		Hud.setRound(
			hud,
			string.format(Config.Hud.PROMPT_DRAW, withArticle(round.target)),
			string.format(Config.Hud.SCORE_LINE, round.score, round.streak)
		)
	end
end

-- Redraws the countdown when the number on it changes.
local function stepCountdown(session: DrawSession)
	local round = session.round
	if round ~= nil and round.sprint ~= nil and secondsLeft(round.sprint) ~= session.shownSeconds then
		showRound(session)
	end
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
			Hud.setResult(session.hud, "", false)
		end,
		onLimit = function()
			session.limitReached = true
			refresh(session)
		end,
		onSubmit = function()
			-- Waits on the server, and this can be called from a keybind, which must not yield.
			task.spawn(DrawSession.submit, session)
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
		isSubmitting = false,
		round = nil,
		shownSeconds = -1,
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
		if session.mode ~= "free" then
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
	ProximityPromptService.Enabled = false
	frameCamera(session)
	Pad.open(session.pad, mode ~= "free")
	Hud.setVisible(session.hud, true)
	Hud.setResult(session.hud, "", false)
	showRound(session)
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
			stepCountdown(session)
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
	ProximityPromptService.Enabled = true
	-- Frees the station. Harmless if the server already released it.
	Net.Station:FireServer("exit")
end

local function showSubmitResult(session: DrawSession, result: Protocol.SubmitResult, runCount: number)
	local hud = session.hud
	if result.rejected == "unreadable" then
		Hud.setMessage(hud, Config.Hud.MESSAGE_TOO_SMALL)
		return
	elseif result.rejected == "notInRound" then
		Hud.setMessage(hud, Config.Hud.MESSAGE_WAIT)
		return
	elseif result.rejected ~= nil then
		Hud.setMessage(hud, Config.Hud.MESSAGE_RETRY)
		return
	end

	-- If the drawing has changed since it was sent, the Glass no longer shows what was scored.
	local inference = session.inference
	local isCurrent = inference.runCount == runCount and not inference.isDirty
	if result.correct then
		-- In a sprint the next digit is already up, so the pad clears at once. A delay could mix the next
		-- stroke in with this drawing.
		if session.mode == "compete" and isCurrent then
			Pad.clear(session.pad)
		end
		Hud.setResult(hud, string.format(Config.Hud.RESULT_CORRECT, withArticle(result.predicted)), true)
		if isCurrent and session.mode ~= "compete" then
			GlassView.celebrate(session.glass)
			task.delay(Config.Round.CLEAR_DELAY, function()
				local isUnchanged = inference.runCount == runCount and not inference.isDirty
				if session.isActive and isUnchanged and not session.pad.isDrawing then
					Pad.clear(session.pad)
				end
			end)
		end
	else
		local percent = math.round(result.prob * 100)
		Hud.setResult(hud, string.format(Config.Hud.RESULT_WRONG, withArticle(result.predicted), percent), false)
		if isCurrent then
			GlassView.highlightStrongestPath(session.glass, inference, result.predicted)
		end
	end
end

-- Sends the drawing to the server once and shows what comes back. The server is the only judge: the
-- client's own prediction is never sent.
function DrawSession.submit(session: DrawSession)
	if not session.isActive or session.mode == "free" or session.isSubmitting or session.pad.isDrawing then
		return
	end
	local round = session.round
	if round ~= nil and round.sprint ~= nil and round.target == nil then
		Hud.setMessage(session.hud, Config.Hud.MESSAGE_WAIT)
		return
	end
	DrawSession.inferNow(session)
	local status = session.inference.status
	if status ~= "ok" then
		Hud.setMessage(
			session.hud,
			if status == "empty" then Config.Hud.MESSAGE_DRAW_FIRST else Config.Hud.MESSAGE_TOO_SMALL
		)
		return
	end

	session.isSubmitting = true
	local runCount = session.inference.runCount
	local ok, result = pcall(function(): Protocol.SubmitResult
		return Net.Submit:InvokeServer(Strokes.encode(session.pad.strokes))
	end)
	session.isSubmitting = false
	if not session.isActive then
		return
	end
	if ok then
		showSubmitResult(session, result, runCount)
	else
		Hud.setMessage(session.hud, Config.Hud.MESSAGE_RETRY)
	end
end

-- Follows the server: it grants and releases stations, and owns the round.
function DrawSession.connectServer(session: DrawSession)
	Net.Station.OnClientEvent:Connect(function(action: string, mode: Mode?)
		if action == "enter" and mode ~= nil then
			DrawSession.enter(session, mode)
		elseif action == "exit" then
			DrawSession.exit(session)
		end
	end)
	Net.Round.OnClientEvent:Connect(function(round: Protocol.RoundState)
		local previous = session.round
		local wasRunning = previous ~= nil and previous.sprint ~= nil and previous.sprint.phase == "running"
		local isRunning = round.sprint ~= nil and round.sprint.phase == "running"
		session.round = round
		showRound(session)
		-- Everyone starts a sprint on an empty pad.
		if isRunning and not wasRunning and session.isActive then
			Pad.clear(session.pad)
		end
	end)
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
