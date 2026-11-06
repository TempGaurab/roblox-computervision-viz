--!strict
local TestKit = require("./lib/TestKit")
local Rounds = require("../src/server/Rounds")

local DIGITS = 10

-- Always picks the first allowed digit.
local function first(low: number, _high: number): number
	return low
end

return function(kit: TestKit.TestKit)
	kit.test("free draw has no target", function()
		local round = Rounds.new()
		Rounds.start(round, "free", DIGITS, first)
		kit.equal(round.target, nil, "target")
	end)

	kit.test("a correct answer scores and moves to a new target", function()
		local round = Rounds.new()
		Rounds.start(round, "challenge", DIGITS, first)
		kit.equal(round.target, 0, "first target")
		kit.equal(Rounds.score(round, 0, DIGITS, first), true, "correct")
		kit.equal(round.score, 1, "score")
		kit.equal(round.streak, 1, "streak")
		kit.equal(round.target, 1, "next target")
	end)

	kit.test("a miss resets the streak, keeps the score, and keeps the target", function()
		local round = Rounds.new()
		Rounds.start(round, "challenge", DIGITS, first)
		Rounds.score(round, 0, DIGITS, first)
		kit.equal(Rounds.score(round, 9, DIGITS, first), false, "wrong")
		kit.equal(round.score, 1, "score")
		kit.equal(round.streak, 0, "streak")
		kit.equal(round.target, 1, "target")
	end)

	kit.test("re-entering a challenge keeps the target", function()
		local round = Rounds.new()
		Rounds.start(round, "challenge", DIGITS, first)
		Rounds.start(round, "free", DIGITS, first)
		Rounds.start(round, "challenge", DIGITS, first)
		kit.equal(round.target, 0, "target")
		kit.equal(#round.recent, 1, "only one target picked")
	end)

	kit.test("targets never repeat the last two, and every other digit can come up", function()
		local seen: { [number]: boolean } = {}
		local round = Rounds.new()
		Rounds.start(round, "challenge", DIGITS, math.random)
		local previous: number? = nil
		local beforeThat: number? = nil
		for _ = 1, 2000 do
			local target = round.target :: number
			kit.equal(target ~= previous and target ~= beforeThat, true, "repeated a recent target")
			kit.equal(target >= 0 and target < DIGITS, true, "in range")
			seen[target] = true
			beforeThat = previous
			previous = target
			Rounds.score(round, target, DIGITS, math.random)
		end
		for digit = 0, DIGITS - 1 do
			kit.equal(seen[digit], true, `digit {digit} came up`)
		end
	end)
end
