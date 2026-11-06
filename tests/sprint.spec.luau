--!strict
local TestKit = require("./lib/TestKit")
local Rounds = require("../src/server/Rounds")
local Sprint = require("../src/server/Sprint")

local LOBBY = 10
local DURATION = 60
local RESULTS = 8
local START = 100
local RUNNING_AT = START + LOBBY
local RESULTS_AT = RUNNING_AT + DURATION
local NEXT_LOBBY_AT = RESULTS_AT + RESULTS

local function newSprint(): Sprint.Sprint
	return Sprint.new({
		lobbySeconds = LOBBY,
		durationSeconds = DURATION,
		resultsSeconds = RESULTS,
		nextDigit = function(recent: { number }): number
			return Rounds.pickDigit(recent, 10, math.random)
		end,
	})
end

-- Answers the player's current digit correctly.
local function answer(sprint: Sprint.Sprint, key: string, now: number): boolean
	return Sprint.score(sprint, key, Sprint.targetOf(sprint, key) :: number, now)
end

return function(kit: TestKit.TestKit)
	kit.test("joining starts a lobby, which times out into a sprint and then results", function()
		local sprint = newSprint()
		kit.equal(sprint.phase, "idle", "starts idle")
		Sprint.join(sprint, "a", "A", START)
		kit.equal(sprint.phase, "lobby", "lobby")
		kit.equal(Sprint.tick(sprint, RUNNING_AT - 1), nil, "still in the lobby")
		kit.equal(Sprint.targetOf(sprint, "a"), nil, "no digit in the lobby")

		kit.equal(Sprint.tick(sprint, RUNNING_AT), "lobby", "left the lobby")
		kit.equal(sprint.phase, "running", "running")
		kit.equal(Sprint.targetOf(sprint, "a") ~= nil, true, "a digit once running")

		kit.equal(Sprint.tick(sprint, RESULTS_AT), "running", "left running")
		kit.equal(sprint.phase, "results", "results")
		kit.equal(Sprint.targetOf(sprint, "a"), nil, "no digit after time is up")
	end)

	kit.test("everyone gets the same digits in the same order, at their own pace", function()
		local sprint = newSprint()
		Sprint.join(sprint, "a", "A", START)
		Sprint.join(sprint, "b", "B", START)
		Sprint.tick(sprint, RUNNING_AT)

		local seen: { number } = {}
		for index = 1, 20 do
			seen[index] = Sprint.targetOf(sprint, "a") :: number
			answer(sprint, "a", RUNNING_AT + index)
		end
		for index = 1, 20 do
			kit.equal(Sprint.targetOf(sprint, "b"), seen[index], `digit {index}`)
			answer(sprint, "b", RUNNING_AT + 30 + index)
		end
		for index = 2, 20 do
			kit.equal(seen[index] ~= seen[index - 1], true, "no immediate repeat")
		end
	end)

	kit.test("a miss costs nothing and keeps the digit", function()
		local sprint = newSprint()
		Sprint.join(sprint, "a", "A", START)
		Sprint.tick(sprint, RUNNING_AT)
		local target = Sprint.targetOf(sprint, "a") :: number
		local wrong = (target + 1) % 10
		kit.equal(Sprint.score(sprint, "a", wrong, RUNNING_AT + 1), false, "wrong")
		kit.equal(Sprint.scoreOf(sprint, "a"), 0, "score")
		kit.equal(Sprint.targetOf(sprint, "a"), target, "same digit")
	end)

	kit.test("nothing scores outside a running sprint, or for strangers", function()
		local sprint = newSprint()
		Sprint.join(sprint, "a", "A", START)
		kit.equal(Sprint.score(sprint, "a", 0, START), false, "lobby")
		Sprint.tick(sprint, RUNNING_AT)
		kit.equal(Sprint.score(sprint, "stranger", 0, RUNNING_AT), false, "not in the sprint")
		Sprint.tick(sprint, RESULTS_AT)
		kit.equal(Sprint.score(sprint, "a", 0, RESULTS_AT), false, "results")
	end)

	kit.test("the top score wins, and standings rank first to get there first", function()
		local sprint = newSprint()
		Sprint.join(sprint, "a", "A", START)
		Sprint.join(sprint, "b", "B", START)
		Sprint.join(sprint, "c", "C", START)
		Sprint.tick(sprint, RUNNING_AT)
		answer(sprint, "b", RUNNING_AT + 5)
		answer(sprint, "c", RUNNING_AT + 1)
		answer(sprint, "c", RUNNING_AT + 2)
		answer(sprint, "b", RUNNING_AT + 6)
		answer(sprint, "b", RUNNING_AT + 7)
		answer(sprint, "a", RUNNING_AT + 8)
		answer(sprint, "a", RUNNING_AT + 9)
		Sprint.tick(sprint, RESULTS_AT)

		local standings = Sprint.standings(sprint)
		kit.equal(standings[1].key, "b", "first")
		kit.equal(standings[2].key, "c", "second: reached 2 before a did")
		kit.equal(standings[3].key, "a", "third")
		local winners = Sprint.winners(sprint)
		kit.equal(#winners, 1, "one winner")
		kit.equal(winners[1].key, "b", "winner")
	end)

	kit.test("equal top scores share the win", function()
		local sprint = newSprint()
		Sprint.join(sprint, "a", "A", START)
		Sprint.join(sprint, "b", "B", START)
		Sprint.tick(sprint, RUNNING_AT)
		answer(sprint, "a", RUNNING_AT + 1)
		answer(sprint, "b", RUNNING_AT + 2)
		Sprint.tick(sprint, RESULTS_AT)
		kit.equal(#Sprint.winners(sprint), 2, "two winners")
	end)

	kit.test("a win needs two players and a score above zero", function()
		local alone = newSprint()
		Sprint.join(alone, "a", "A", START)
		Sprint.tick(alone, RUNNING_AT)
		answer(alone, "a", RUNNING_AT + 1)
		Sprint.tick(alone, RESULTS_AT)
		kit.equal(#Sprint.winners(alone), 0, "alone")
		kit.equal(Sprint.scoreOf(alone, "a"), 1, "still has a score")

		local scoreless = newSprint()
		Sprint.join(scoreless, "a", "A", START)
		Sprint.join(scoreless, "b", "B", START)
		Sprint.tick(scoreless, RUNNING_AT)
		Sprint.tick(scoreless, RESULTS_AT)
		kit.equal(#Sprint.winners(scoreless), 0, "nobody scored")
	end)

	kit.test("late joiners wait, and everyone loops into the next sprint with a clean slate", function()
		local sprint = newSprint()
		Sprint.join(sprint, "a", "A", START)
		Sprint.tick(sprint, RUNNING_AT)
		answer(sprint, "a", RUNNING_AT + 1)

		Sprint.join(sprint, "late", "Late", RUNNING_AT + 2)
		kit.equal(Sprint.isWaiting(sprint, "late"), true, "waiting")
		kit.equal(Sprint.targetOf(sprint, "late"), nil, "no digit while waiting")
		kit.equal(#Sprint.standings(sprint), 1, "not in the standings")

		Sprint.tick(sprint, RESULTS_AT)
		Sprint.tick(sprint, NEXT_LOBBY_AT)
		kit.equal(sprint.phase, "lobby", "next lobby")
		kit.equal(Sprint.isWaiting(sprint, "late"), false, "no longer waiting")
		kit.equal(Sprint.scoreOf(sprint, "a"), 0, "score reset")

		Sprint.tick(sprint, NEXT_LOBBY_AT + LOBBY)
		kit.equal(sprint.phase, "running", "running again")
		kit.equal(Sprint.targetOf(sprint, "a"), Sprint.targetOf(sprint, "late"), "same first digit")
	end)

	kit.test("leaving forfeits, and an empty sprint stops", function()
		local sprint = newSprint()
		Sprint.join(sprint, "a", "A", START)
		Sprint.join(sprint, "b", "B", START)
		Sprint.tick(sprint, RUNNING_AT)
		answer(sprint, "a", RUNNING_AT + 1)
		Sprint.leave(sprint, "a", RUNNING_AT + 2)
		kit.equal(#Sprint.standings(sprint), 1, "gone from the standings")
		kit.equal(Sprint.targetOf(sprint, "a"), nil, "no digit")
		kit.equal(sprint.phase, "running", "the other player carries on")
		Sprint.leave(sprint, "b", RUNNING_AT + 3)
		kit.equal(sprint.phase, "idle", "nobody left")
		kit.equal(Sprint.tick(sprint, RESULTS_AT), nil, "idle doesn't tick")
	end)

	kit.test("if everyone playing leaves, those waiting get a new lobby", function()
		local sprint = newSprint()
		Sprint.join(sprint, "a", "A", START)
		Sprint.tick(sprint, RUNNING_AT)
		Sprint.join(sprint, "late", "Late", RUNNING_AT + 1)
		Sprint.leave(sprint, "a", RUNNING_AT + 2)
		kit.equal(sprint.phase, "lobby", "lobby")
		kit.equal(Sprint.isWaiting(sprint, "late"), false, "in it")
		kit.equal(sprint.endsAt, RUNNING_AT + 2 + LOBBY, "a full lobby")
	end)

	kit.test("joining twice changes nothing", function()
		local sprint = newSprint()
		Sprint.join(sprint, "a", "A", START)
		Sprint.join(sprint, "a", "A", START + 1)
		kit.equal(#sprint.entrants, 1, "one entrant")
		kit.equal(sprint.endsAt, RUNNING_AT, "lobby clock unchanged")
	end)
end
