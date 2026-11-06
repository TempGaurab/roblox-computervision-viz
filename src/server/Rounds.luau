--!strict
-- One player's round: mode, target, streak, and score. Pure logic with no requires or Roblox APIs, so
-- Lune can test it. Targets are random but never repeat the last two. A miss keeps the target, so the
-- player can try that digit again; only a correct answer moves on.

export type Mode = "free" | "challenge"

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

local function pickTarget(round: Round, digitCount: number, randomInt: RandomInt)
	local recent = round.recent
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
	round.target = digit
	table.insert(recent, 1, digit)
	if #recent > REMEMBERED_TARGETS then
		table.remove(recent)
	end
end

function Rounds.start(round: Round, mode: Mode, digitCount: number, randomInt: RandomInt)
	round.mode = mode
	if mode == "challenge" and round.target == nil then
		pickTarget(round, digitCount, randomInt)
	end
end

-- Scores a prediction against the current target. Returns whether it was correct.
function Rounds.score(round: Round, predicted: number, digitCount: number, randomInt: RandomInt): boolean
	local isCorrect = predicted == round.target
	if isCorrect then
		round.score += 1
		round.streak += 1
		pickTarget(round, digitCount, randomInt)
	else
		round.streak = 0
	end
	return isCorrect
end

return Rounds
