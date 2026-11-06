--!strict
-- The Compete sprint as a pure state machine, with no requires or Roblox APIs, so Lune can test it.
-- Time is passed in. Everyone in a sprint gets the same digits in the same order, at their own pace.
--
-- idle -> lobby -> running -> results -> lobby (everyone who stayed, plus anyone who waited) or idle

export type Phase = "idle" | "lobby" | "running" | "results"

export type Entrant = {
	key: any,
	name: string,
	score: number,
	index: number, -- position in the sprint's digit sequence
	reachedAt: number, -- when they reached this score; earlier ranks first among equal scores
}

export type Options = {
	lobbySeconds: number,
	durationSeconds: number,
	resultsSeconds: number,
	-- Returns a digit that isn't in `recent`, and remembers it there.
	nextDigit: (recent: { number }) -> number,
}

export type Sprint = {
	options: Options,
	phase: Phase,
	endsAt: number,
	entrants: { Entrant },
	waiting: { Entrant }, -- joined too late for this sprint; in the next one
	sequence: { number },
	recent: { number },
}

local MIN_ENTRANTS_TO_WIN = 2

local Sprint = {}

function Sprint.new(options: Options): Sprint
	return { options = options, phase = "idle", endsAt = 0, entrants = {}, waiting = {}, sequence = {}, recent = {} }
end

local function findIn(list: { Entrant }, key: any): number?
	for index, entrant in list do
		if entrant.key == key then
			return index
		end
	end
	return nil
end

local function resetScores(sprint: Sprint)
	for _, entrant in sprint.entrants do
		entrant.score = 0
		entrant.index = 1
		entrant.reachedAt = 0
	end
end

-- Moves everyone waiting into a new lobby, or goes idle if nobody is left.
local function nextLobby(sprint: Sprint, now: number)
	for _, entrant in sprint.waiting do
		table.insert(sprint.entrants, entrant)
	end
	table.clear(sprint.waiting)
	resetScores(sprint)
	if #sprint.entrants > 0 then
		sprint.phase = "lobby"
		sprint.endsAt = now + sprint.options.lobbySeconds
	else
		sprint.phase = "idle"
	end
end

function Sprint.join(sprint: Sprint, key: any, name: string, now: number)
	if findIn(sprint.entrants, key) ~= nil or findIn(sprint.waiting, key) ~= nil then
		return
	end
	local entrant: Entrant = { key = key, name = name, score = 0, index = 1, reachedAt = 0 }
	if sprint.phase == "idle" then
		table.insert(sprint.entrants, entrant)
		sprint.phase = "lobby"
		sprint.endsAt = now + sprint.options.lobbySeconds
	elseif sprint.phase == "lobby" then
		table.insert(sprint.entrants, entrant)
	else
		table.insert(sprint.waiting, entrant)
	end
end

-- Leaving forfeits: a player who goes is out of this sprint's standings.
function Sprint.leave(sprint: Sprint, key: any, now: number)
	local waitingIndex = findIn(sprint.waiting, key)
	if waitingIndex ~= nil then
		table.remove(sprint.waiting, waitingIndex)
	end
	local index = findIn(sprint.entrants, key)
	if index ~= nil then
		table.remove(sprint.entrants, index)
	end
	if #sprint.entrants == 0 and sprint.phase ~= "idle" then
		nextLobby(sprint, now)
	end
end

-- Advances the phase if its time is up. Returns the phase it just left, or nil if nothing changed.
function Sprint.tick(sprint: Sprint, now: number): Phase?
	local phase: Phase = sprint.phase
	if phase == "idle" or now < sprint.endsAt then
		return nil
	end
	if phase == "lobby" then
		table.clear(sprint.sequence)
		table.clear(sprint.recent)
		resetScores(sprint)
		sprint.phase = "running"
		sprint.endsAt = now + sprint.options.durationSeconds
	elseif phase == "running" then
		sprint.phase = "results"
		sprint.endsAt = now + sprint.options.resultsSeconds
	else
		nextLobby(sprint, now)
	end
	return phase
end

function Sprint.isWaiting(sprint: Sprint, key: any): boolean
	return findIn(sprint.waiting, key) ~= nil
end

-- The digit this player should draw now, or nil unless they are in a running sprint.
function Sprint.targetOf(sprint: Sprint, key: any): number?
	if sprint.phase ~= "running" then
		return nil
	end
	local index = findIn(sprint.entrants, key)
	if index == nil then
		return nil
	end
	local position = sprint.entrants[index].index
	local sequence = sprint.sequence
	while #sequence < position do
		table.insert(sequence, sprint.options.nextDigit(sprint.recent))
	end
	return sequence[position]
end

function Sprint.scoreOf(sprint: Sprint, key: any): number
	local index = findIn(sprint.entrants, key)
	return if index ~= nil then sprint.entrants[index].score else 0
end

-- Scores a prediction against the player's current digit. A miss keeps the digit and costs nothing but
-- time. Returns whether it was correct.
function Sprint.score(sprint: Sprint, key: any, predicted: number, now: number): boolean
	local target = Sprint.targetOf(sprint, key)
	if target == nil or predicted ~= target then
		return false
	end
	local entrant = sprint.entrants[findIn(sprint.entrants, key) :: number]
	entrant.score += 1
	entrant.index += 1
	entrant.reachedAt = now
	return true
end

-- Best first. Equal scores rank by who got there first, and then by who joined first.
function Sprint.standings(sprint: Sprint): { Entrant }
	local ordered = table.clone(sprint.entrants)
	local joinOrder: { [Entrant]: number } = {}
	for index, entrant in sprint.entrants do
		joinOrder[entrant] = index
	end
	table.sort(ordered, function(a: Entrant, b: Entrant): boolean
		if a.score ~= b.score then
			return a.score > b.score
		end
		if a.reachedAt ~= b.reachedAt then
			return a.reachedAt < b.reachedAt
		end
		return joinOrder[a] < joinOrder[b]
	end)
	return ordered
end

-- Everyone on the top score. Equal scores share the win. A sprint needs at least two players to have a
-- winner, so nobody can collect wins alone, and a score of zero never wins.
function Sprint.winners(sprint: Sprint): { Entrant }
	local winners: { Entrant } = {}
	if #sprint.entrants < MIN_ENTRANTS_TO_WIN then
		return winners
	end
	local top = 0
	for _, entrant in sprint.entrants do
		top = math.max(top, entrant.score)
	end
	if top == 0 then
		return winners
	end
	for _, entrant in sprint.entrants do
		if entrant.score == top then
			table.insert(winners, entrant)
		end
	end
	return winners
end

return Sprint
