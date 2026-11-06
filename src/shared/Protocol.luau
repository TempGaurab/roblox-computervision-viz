--!strict
-- The shapes that cross the network. Strokes only ever travel inside a Submit payload.

export type Mode = "free" | "challenge"

export type RoundState = {
	mode: Mode,
	target: number?, -- the digit to draw; nil in Free Draw
	score: number,
	streak: number,
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
