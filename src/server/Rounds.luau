--!strict
-- One player's Solo round: mode, target, streak, and score. Pure logic with no requires or Roblox APIs, so
-- Lune can test it. Targets are random but never repeat the last two. A miss keeps the target, so the
-- player can try that digit again; only a correct answer moves on.

export type Mode = "free" | "solo" | "compete"

export type Round = {
	mode: Mode,
	target: number?,
	recent: { number }, -- the last targets, most recent first
	streak: number,
	score: number,
}

-- Returns an integer in [low, high], like math.random. Injected so tests are deterministic.
export type RandomInt = (low: number, high: number) -> number

local REMEMBERED_TARGETS = 2

local Rounds = {}

function Rounds.new(): Round
	return { mode = "free", target = nil, recent = {}, streak = 0, score = 0 }
end

-- Picks a digit that isn't in `recent`, and remembers it there.
function Rounds.pickDigit(recent: { number }, digitCount: number, randomInt: RandomInt): number
	local index = randomInt(0, digitCount - 1 - #recent)
	-- Walk the digits in order, skipping the excluded ones, so every allowed digit is equally likely.
	local digit = -1
	for candidate = 0, digitCount - 1 do
		if table.find(recent, candidate) == nil then
			if index == 0 then
				digit = candidate
				break
			end
			index -= 1
		end
	end
	table.insert(recent, 1, digit)
	if #recent > REMEMBERED_TARGETS then
		table.remove(recent)
	end
	return digit
end

function Rounds.start(round: Round, mode: Mode, digitCount: number, randomInt: RandomInt)
	round.mode = mode
	if mode == "solo" and round.target == nil then
		round.target = Rounds.pickDigit(round.recent, digitCount, randomInt)
	end
end

-- Scores a prediction against the current target. Returns whether it was correct.
function Rounds.score(round: Round, predicted: number, digitCount: number, randomInt: RandomInt): boolean
	local isCorrect = predicted == round.target
	if isCorrect then
		round.score += 1
		round.streak += 1
		round.target = Rounds.pickDigit(round.recent, digitCount, randomInt)
	else
		round.streak = 0
	end
	return isCorrect
end

return Rounds
