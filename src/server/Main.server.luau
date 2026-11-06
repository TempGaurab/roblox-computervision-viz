--!strict
-- Server bootstrap: World, Stations, Rounds, Submissions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelData = require(ReplicatedStorage.Shared.NeuralCore.ModelData)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Compete = require(script.Parent.Compete)
local Rounds = require(script.Parent.Rounds)
local Stations = require(script.Parent.Stations)
local Submissions = require(script.Parent.Submissions)
local World = require(script.Parent.World)

local Net = ReplicatedStorage.Net

local DIGIT_COUNT = ModelData.layers[#ModelData.layers].outSize

type PlayerState = {
	round: Rounds.Round,
	scoreStat: IntValue,
	streakStat: IntValue,
	winsStat: IntValue,
}

local states: { [Player]: PlayerState } = {}

local random = Random.new()

local function randomInt(low: number, high: number): number
	return random:NextInteger(low, high)
end

local function newStat(parent: Instance, name: string): IntValue
	local stat = Instance.new("IntValue")
	stat.Name = name
	stat.Parent = parent
	return stat
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	states[player] = {
		round = Rounds.new(),
		scoreStat = newStat(leaderstats, "Score"),
		streakStat = newStat(leaderstats, "Streak"),
		winsStat = newStat(leaderstats, "Wins"),
	}
	leaderstats.Parent = player
end

-- Updates the leaderboard and tells the player about their round.
local function publish(player: Player)
	local state = states[player]
	local round = state.round
	state.scoreStat.Value = round.score
	state.streakStat.Value = round.streak
	local message: Protocol.RoundState
	if round.mode == "compete" then
		message = {
			mode = "compete",
			target = Compete.targetOf(player),
			score = Compete.scoreOf(player),
			streak = 0,
			sprint = Compete.viewOf(player),
		}
	else
		message = {
			mode = round.mode,
			target = if round.mode == "solo" then round.target else nil,
			score = round.score,
			streak = round.streak,
		}
	end
	Net.Round:FireClient(player, message)
end

local anchors = World.build()

Compete.start({
	nextDigit = function(recent: { number }): number
		return Rounds.pickDigit(recent, DIGIT_COUNT, randomInt)
	end,
	publish = function(player: Player)
		if states[player] ~= nil then
			publish(player)
		end
	end,
	addWin = function(player: Player)
		local state = states[player]
		if state ~= nil then
			state.winsStat.Value += 1
		end
	end,
})

Stations.start({
	startRound = function(player: Player, mode: Protocol.Mode)
		Rounds.start(states[player].round, mode, DIGIT_COUNT, randomInt)
		if mode == "compete" then
			Compete.join(player)
		else
			publish(player)
		end
	end,
	onReleased = Compete.leave,
}, anchors)

Submissions.start({
	canSubmit = function(player: Player): boolean
		local state = states[player]
		if state == nil or not Stations.holds(player) then
			return false
		end
		local mode = state.round.mode
		return mode == "solo" or (mode == "compete" and Compete.canSubmit(player))
	end,
	targetOf = function(player: Player): number
		local round = states[player].round
		local target = if round.mode == "compete" then Compete.targetOf(player) else round.target
		return target or -1
	end,
	score = function(player: Player, predicted: number): (boolean, number)
		local round = states[player].round
		if round.mode == "compete" then
			local target = Compete.targetOf(player) or -1
			return Compete.score(player, predicted), target
		end
		local target = round.target or -1
		local isCorrect = Rounds.score(round, predicted, DIGIT_COUNT, randomInt)
		publish(player)
		return isCorrect, target
	end,
})

-- The server only ever sends on this one, so anything arriving is dropped rather than queued.
Net.Round.OnServerEvent:Connect(function() end)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player: Player)
	states[player] = nil
end)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
