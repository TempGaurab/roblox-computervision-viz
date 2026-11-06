--!strict
-- Everything known about players' best Solo streaks, and which are waiting to be saved. Pure logic with
-- no requires or Roblox APIs, so Lune can test it. A best only ever goes up.

export type Row = {
	rank: number,
	userId: number,
	best: number,
	isDeveloper: boolean,
}

export type Leaderboard = {
	developerId: number,
	size: number,
	bests: { [number]: number }, -- by user ID
	unsaved: { [number]: number },
}

local Leaderboard = {}

function Leaderboard.new(developerId: number, size: number): Leaderboard
	return { developerId = developerId, size = size, bests = {}, unsaved = {} }
end

-- Takes in a best read from storage. Returns whether it changed anything.
function Leaderboard.ingest(board: Leaderboard, userId: number, best: number): boolean
	if best <= (board.bests[userId] or 0) then
		return false
	end
	board.bests[userId] = best
	return true
end

-- Takes in a streak from play. Returns whether it is a new best, which then waits to be saved. Test
-- players in a Studio server have user IDs of zero or below, and never count.
function Leaderboard.recordStreak(board: Leaderboard, userId: number, streak: number): boolean
	if userId <= 0 or not Leaderboard.ingest(board, userId, streak) then
		return false
	end
	board.unsaved[userId] = streak
	return true
end

-- Returns the bests waiting to be saved, and forgets them. Put back any that fail with markUnsaved.
function Leaderboard.takeUnsaved(board: Leaderboard): { [number]: number }
	local unsaved = board.unsaved
	board.unsaved = {}
	return unsaved
end

function Leaderboard.markUnsaved(board: Leaderboard, userId: number, best: number)
	if best > (board.unsaved[userId] or 0) then
		board.unsaved[userId] = best
	end
end

-- The top of the board, best first. Equal bests rank by user ID, so every server agrees on the order.
function Leaderboard.rows(board: Leaderboard): { Row }
	local entries: { Row } = {}
	for userId, best in board.bests do
		table.insert(entries, {
			rank = 0,
			userId = userId,
			best = best,
			isDeveloper = userId == board.developerId,
		})
	end
	table.sort(entries, function(a: Row, b: Row): boolean
		if a.best ~= b.best then
			return a.best > b.best
		end
		return a.userId < b.userId
	end)
	local rows: { Row } = {}
	for rank = 1, math.min(board.size, #entries) do
		local entry = entries[rank]
		entry.rank = rank
		rows[rank] = entry
	end
	return rows
end

-- The developer's best, or nil until they have one.
function Leaderboard.developerBest(board: Leaderboard): number?
	return board.bests[board.developerId]
end

return Leaderboard
