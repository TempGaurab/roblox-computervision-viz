--!strict
-- Minimal test helpers for specs run by tests/run.luau under Lune.

export type Failure = {
	name: string,
	message: string,
}

export type TestKit = {
	test: (name: string, body: () -> ()) -> (),
	equal: (actual: unknown, expected: unknown, label: string?) -> (),
	near: (actual: number, expected: number, tolerance: number, label: string?) -> (),
	passed: number,
	failures: { Failure },
}

local TestKit = {}

function TestKit.new(): TestKit
	local kit: TestKit
	kit = {
		passed = 0,
		failures = {},
		test = function(name: string, body: () -> ())
			local ok, message = xpcall(body, function(err: unknown): string
				return debug.traceback(tostring(err), 2)
			end)
			if ok then
				kit.passed += 1
			else
				table.insert(kit.failures, { name = name, message = tostring(message) })
			end
		end,
		equal = function(actual: unknown, expected: unknown, label: string?)
			if actual ~= expected then
				error(`{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
			end
		end,
		near = function(actual: number, expected: number, tolerance: number, label: string?)
			if math.abs(actual - expected) > tolerance then
				error(`{label or "value"}: expected {expected} within {tolerance}, got {actual}`, 2)
			end
		end,
	}
	return kit
end

return TestKit
