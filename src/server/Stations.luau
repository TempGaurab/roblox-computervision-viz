--!strict
-- Grants stations, one player each, and releases them on exit, death, or leaving.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local RateLimit = require(script.Parent.RateLimit)

local WorldConfig = Config.World
local StationEvent = ReplicatedStorage.Net.Station

export type Context = {
	-- Puts the player in a mode, then tells them about their round.
	startRound: (player: Player, mode: Protocol.Mode) -> (),
	-- The player has left their station, for any reason.
	onReleased: (player: Player) -> (),
}

type Station = {
	anchor: Part,
	prompts: { ProximityPrompt },
	occupant: Player?,
}

local stations: { Station } = {}
local held: { [Player]: Station } = {}
local exitLimit = RateLimit.new(Config.Net.STATION_EVENTS_PER_SECOND, 1)

local Stations = {}

local function setPromptsEnabled(station: Station, isEnabled: boolean)
	for _, prompt in station.prompts do
		prompt.Enabled = isEnabled
	end
end

local function release(context: Context, player: Player, tellClient: boolean)
	local station = held[player]
	if station == nil then
		return
	end
	held[player] = nil
	station.occupant = nil
	setPromptsEnabled(station, true)
	context.onReleased(player)
	if tellClient then
		StationEvent:FireClient(player, "exit")
	end
end

-- The prompt's own range is enforced on the client, so check it again here.
local function isInReach(player: Player, station: Station): boolean
	local character = player.Character
	if character == nil then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return false
	end
	local reach = WorldConfig.PROMPT_DISTANCE + WorldConfig.REACH_SLACK
	return (character:GetPivot().Position - station.anchor.Position).Magnitude <= reach
end

local function claim(context: Context, player: Player, station: Station, mode: Protocol.Mode)
	if held[player] ~= nil or station.occupant ~= nil or not isInReach(player, station) then
		return
	end
	held[player] = station
	station.occupant = player
	setPromptsEnabled(station, false)
	context.startRound(player, mode)
	StationEvent:FireClient(player, "enter", mode)
end

local function newPrompt(
	context: Context,
	station: Station,
	mode: Protocol.Mode,
	objectText: string,
	key: Enum.KeyCode,
	slot: number
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = WorldConfig.PROMPT_ACTION
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = key
	-- Prompts on one part share a screen position, so space them out in a column.
	prompt.UIOffset = Vector2.new(0, slot * WorldConfig.PROMPT_SPACING)
	prompt.MaxActivationDistance = WorldConfig.PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = station.anchor
	prompt.Triggered:Connect(function(player: Player)
		claim(context, player, station, mode)
	end)
	return prompt
end

local function watchCharacter(context: Context, player: Player)
	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.Died:Connect(function()
			release(context, player, true)
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function()
		release(context, player, true)
	end)
	if player.Character ~= nil then
		task.spawn(onCharacter, player.Character)
	end
end

function Stations.holds(player: Player): boolean
	return held[player] ~= nil
end

function Stations.start(context: Context, anchors: { Part })
	for index, anchor in anchors do
		local station: Station = { anchor = anchor, prompts = {}, occupant = nil }
		station.prompts = {
			newPrompt(context, station, "solo", WorldConfig.PROMPT_SOLO, WorldConfig.PROMPT_SOLO_KEY, -1),
			newPrompt(context, station, "compete", WorldConfig.PROMPT_COMPETE, WorldConfig.PROMPT_COMPETE_KEY, 0),
			newPrompt(context, station, "free", WorldConfig.PROMPT_FREE, WorldConfig.PROMPT_FREE_KEY, 1),
		}
		stations[index] = station
	end

	StationEvent.OnServerEvent:Connect(function(player: Player, action: unknown)
		if action == "exit" and RateLimit.allow(exitLimit, player, os.clock()) then
			release(context, player, false)
		end
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		watchCharacter(context, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		release(context, player, false)
		RateLimit.forget(exitLimit, player)
	end)
	for _, player in Players:GetPlayers() do
		watchCharacter(context, player)
	end
end

return Stations
