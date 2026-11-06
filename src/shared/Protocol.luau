--!strict
-- The shapes that cross the network. Strokes only ever travel inside a Submit payload.

export type Mode = "free" | "solo" | "compete"

export type Standing = {
	userId: number,
	name: string,
	score: number,
}

-- Names and scores only: nothing about anyone's drawing is ever shared.
export type SprintView = {
	phase: "idle" | "lobby" | "running" | "results",
	endsAt: number, -- in workspace:GetServerTimeNow() time
	isWaiting: boolean, -- joined too late for this sprint; in the next one
	standings: { Standing }, -- best first
}

export type RoundState = {
	mode: Mode,
	target: number?, -- the digit to draw; nil if there is nothing to draw yet
	score: number,
	streak: number,
	sprint: SprintView?, -- only in Compete
}

export type RejectReason = "rateLimited" | "notInRound" | "malformed" | "unreadable"

export type SubmitResult = {
	correct: boolean,
	predicted: number, -- -1 when rejected
	prob: number,
	target: number,
	rejected: RejectReason?,
}

return {}
