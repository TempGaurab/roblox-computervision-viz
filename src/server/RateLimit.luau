--!strict
-- A sliding-window limit per key: at most `limit` events in any `window` seconds. Pure logic, so Lune
-- can test it.

export type RateLimit = {
	limit: number,
	window: number,
	times: { [any]: { number } }, -- per key, a ring of the last `limit` allowed event times
	heads: { [any]: number },
}

local RateLimit = {}

function RateLimit.new(limit: number, window: number): RateLimit
	return { limit = limit, window = window, times = {}, heads = {} }
end

-- Records the event and returns true if it is within the limit.
function RateLimit.allow(rateLimit: RateLimit, key: any, now: number): boolean
	local times = rateLimit.times[key]
	if times == nil then
		times = table.create(rateLimit.limit, -math.huge)
		rateLimit.times[key] = times
		rateLimit.heads[key] = 1
	end
	-- The head is the oldest of the last `limit` allowed events.
	local head = rateLimit.heads[key]
	if now - times[head] < rateLimit.window then
		return false
	end
	times[head] = now
	rateLimit.heads[key] = head % rateLimit.limit + 1
	return true
end

function RateLimit.forget(rateLimit: RateLimit, key: any)
	rateLimit.times[key] = nil
	rateLimit.heads[key] = nil
end

return RateLimit
