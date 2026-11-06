--!strict
-- Server bootstrap: World, Stations, Rounds, Submissions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelData = require(ReplicatedStorage.Shared.NeuralCore.ModelData)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
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
	}
	leaderstats.Parent = player
end

-- Updates the leaderboard and tells the player about their round.
local function publish(player: Player)
	local state = states[player]
	local round = state.round
	state.scoreStat.Value = round.score
	state.streakStat.Value = round.streak
	local message: Protocol.RoundState = {
		mode = round.mode,
		target = if round.mode == "challenge" then round.target else nil,
		score = round.score,
		streak = round.streak,
	}
	Net.Round:FireClient(player, message)
end

local anchors = World.build()

Stations.start({
	startRound = function(player: Player, mode: Protocol.Mode)
		Rounds.start(states[player].round, mode, DIGIT_COUNT, randomInt)
		publish(player)
	end,
}, anchors)

Submissions.start({
	isInChallenge = function(player: Player): boolean
		local state = states[player]
		return state ~= nil and state.round.mode == "challenge" and Stations.holds(player)
	end,
	targetOf = function(player: Player): number
		return states[player].round.target or -1
	end,
	score = function(player: Player, predicted: number): (boolean, number)
		local round = states[player].round
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
