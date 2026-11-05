--!strict
-- M0 smoke test: the runner works, and the project file declares what scripts assume exists.

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local TestKit = require("./lib/TestKit")

return function(kit: TestKit.TestKit)
	local project = serde.decode("json", fs.readFile("default.project.json"))
	local tree = project.tree

	kit.test("project declares the remotes under ReplicatedStorage.Net", function()
		local net = tree.ReplicatedStorage.Net
		kit.equal(net["$className"], "Folder", "Net")
		kit.equal(net.Submit["$className"], "RemoteFunction", "Submit")
		kit.equal(net.Round["$className"], "RemoteEvent", "Round")
		kit.equal(net.Station["$className"], "RemoteEvent", "Station")
	end)

	kit.test("project maps source folders to their services", function()
		kit.equal(tree.ReplicatedStorage.Shared["$path"], "src/shared", "Shared")
		kit.equal(tree.StarterPlayer.StarterPlayerScripts.Client["$path"], "src/client", "Client")
		kit.equal(tree.ServerScriptService.Server["$path"], "src/server", "Server")
	end)

	kit.test("project declares the bloom used for glow", function()
		kit.equal(tree.Lighting.Bloom["$className"], "BloomEffect", "Bloom")
	end)
end
