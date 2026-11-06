--!strict
-- Tracks connections and teardown functions so they can all be released together.

export type Cleanup = {
	connections: { RBXScriptConnection },
	tasks: { () -> () },
}

local Cleanup = {}

function Cleanup.new(): Cleanup
	return { connections = {}, tasks = {} }
end

function Cleanup.connect(cleanup: Cleanup, connection: RBXScriptConnection)
	table.insert(cleanup.connections, connection)
end

function Cleanup.addTask(cleanup: Cleanup, teardown: () -> ())
	table.insert(cleanup.tasks, teardown)
end

function Cleanup.run(cleanup: Cleanup)
	for _, connection in cleanup.connections do
		connection:Disconnect()
	end
	table.clear(cleanup.connections)
	for _, teardown in cleanup.tasks do
		teardown()
	end
	table.clear(cleanup.tasks)
end

return Cleanup
