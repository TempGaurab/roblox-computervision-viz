--!strict
-- Runs the one Compete sprint on the server: joins and leaves, the clock, and telling players. Only names
-- and scores are shared. A drawing never reaches anyone else (Rule 4).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Sprint = require(script.Parent.Sprint)

local SprintConfig = Config.Sprint

export type Context = {
	nextDigit: (recent: { number }) -> number,
	-- Tells a player about their round.
	publish: (player: Player) -> (),
	addWin: (player: Player) -> (),
}

local context: Context
local sprint: Sprint.Sprint

local Compete = {}

local function publishAll()
	for _, entrant in sprint.entrants do
		context.publish(entrant.key)
	end
	for _, entrant in sprint.waiting do
		context.publish(entrant.key)
	end
end

function Compete.start(newContext: Context)
	context = newContext
	sprint = Sprint.new({
		lobbySeconds = SprintConfig.LOBBY_SECONDS,
		durationSeconds = SprintConfig.DURATION_SECONDS,
		resultsSeconds = SprintConfig.RESULTS_SECONDS,
		nextDigit = newContext.nextDigit,
	})
	task.spawn(function()
		while true do
			task.wait(SprintConfig.TICK_SECONDS)
			local left = Sprint.tick(sprint, workspace:GetServerTimeNow())
			if left == "running" then
				for _, winner in Sprint.winners(sprint) do
					context.addWin(winner.key)
				end
			end
			if left ~= nil then
				publishAll()
			end
		end
	end)
end

function Compete.join(player: Player)
	Sprint.join(sprint, player, player.DisplayName, workspace:GetServerTimeNow())
	publishAll()
end

function Compete.leave(player: Player)
	Sprint.leave(sprint, player, workspace:GetServerTimeNow())
	publishAll()
end

function Compete.canSubmit(player: Player): boolean
	return Sprint.targetOf(sprint, player) ~= nil
end

function Compete.targetOf(player: Player): number?
	return Sprint.targetOf(sprint, player)
end

function Compete.scoreOf(player: Player): number
	return Sprint.scoreOf(sprint, player)
end

function Compete.score(player: Player, predicted: number): boolean
	local isCorrect = Sprint.score(sprint, player, predicted, workspace:GetServerTimeNow())
	if isCorrect then
		publishAll()
	end
	return isCorrect
end

function Compete.viewOf(player: Player): Protocol.SprintView
	local standings: { Protocol.Standing } = {}
	for _, entrant in Sprint.standings(sprint) do
		table.insert(standings, { userId = entrant.key.UserId, name = entrant.name, score = entrant.score })
	end
	return {
		phase = sprint.phase,
		endsAt = sprint.endsAt,
		isWaiting = Sprint.isWaiting(sprint, player),
		standings = standings,
	}
end

return Compete
