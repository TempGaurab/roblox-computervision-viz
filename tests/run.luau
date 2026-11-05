--!strict
-- Runs every tests/*.spec.luau from the repo root: `lune run tests/run`.
-- Each spec returns a function that receives a TestKit. Exits non-zero on any failure, or if nothing ran.

local fs = require("@lune/fs")
local process = require("@lune/process")

local TestKit = require("./lib/TestKit")

local SPEC_SUFFIX = ".spec.luau"

local specNames: { string } = {}
for _, entry in fs.readDir("tests") do
	if string.sub(entry, -#SPEC_SUFFIX) == SPEC_SUFFIX then
		table.insert(specNames, entry)
	end
end
table.sort(specNames)

local kit = TestKit.new()
for _, specName in specNames do
	local modulePath = "./" .. string.sub(specName, 1, -#".luau" - 1)
	local spec = (require :: any)(modulePath) :: (TestKit.TestKit) -> ()
	spec(kit)
end

for _, failure in kit.failures do
	print(`FAIL {failure.name}\n{failure.message}\n`)
end
print(`{#specNames} spec files: {kit.passed} passed, {#kit.failures} failed`)

if #kit.failures > 0 or kit.passed == 0 then
	process.exit(1)
end
