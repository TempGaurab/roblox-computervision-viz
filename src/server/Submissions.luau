--!strict
-- The Submit remote: validates, scores, and returns the result. The payload goes no further than
-- Classify.run and is never stored, logged, printed, or forwarded (Rule 4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Classify = require(ReplicatedStorage.Shared.NeuralCore.Classify)
local ModelData = require(ReplicatedStorage.Shared.NeuralCore.ModelData)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local RateLimit = require(script.Parent.RateLimit)

local Submit = ReplicatedStorage.Net.Submit

export type Context = {
	-- Returns false unless the player has a digit to draw right now, in Solo or a running sprint.
	canSubmit: (player: Player) -> boolean,
	-- Scores a prediction, tells the player about their round, and returns the digit it was scored against.
	score: (player: Player, predicted: number) -> (boolean, number),
	targetOf: (player: Player) -> number,
}

local Submissions = {}

local function rejected(reason: Protocol.RejectReason, target: number): Protocol.SubmitResult
	return { correct = false, predicted = -1, prob = 0, target = target, rejected = reason }
end

function Submissions.start(context: Context)
	local classifier = Classify.new(ModelData, ModelData.preprocess)
	local limit = RateLimit.new(Config.Net.SUBMITS_PER_SECOND, 1)

	Submit.OnServerInvoke = function(player: Player, payload: unknown): Protocol.SubmitResult
		if not RateLimit.allow(limit, player, os.clock()) then
			return rejected("rateLimited", -1)
		end
		if not context.canSubmit(player) then
			return rejected("notInRound", -1)
		end
		local target = context.targetOf(player)
		if typeof(payload) ~= "buffer" or buffer.len(payload) > Config.Net.MAX_SUBMIT_BYTES then
			return rejected("malformed", target)
		end

		local status, predicted, prob = Classify.run(classifier, payload)
		if status ~= "ok" then
			return rejected(status :: any, target)
		end
		local isCorrect, scoredTarget = context.score(player, predicted)
		return { correct = isCorrect, predicted = predicted, prob = prob, target = scoredTarget }
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		RateLimit.forget(limit, player)
	end)
end

return Submissions
