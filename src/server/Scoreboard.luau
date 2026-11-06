--!strict
-- The all-time best-streak board on the lab wall, with the developer's best pinned for players to beat.
-- Stores user IDs and numbers only, never anything about a drawing (Rule 4). If DataStores are out of
-- reach the board still works for this server, and says nothing is being saved.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local Config = require(ReplicatedStorage.Shared.Config)
local Leaderboard = require(script.Parent.Leaderboard)

local BoardConfig = Config.Scoreboard

type RowLabels = {
	root: Frame,
	rank: TextLabel,
	name: TextLabel,
	best: TextLabel,
}

local board = Leaderboard.new(BoardConfig.DEVELOPER_USER_ID, BoardConfig.SIZE)
local store: OrderedDataStore? = nil
local hasWarned = false
local needsRender = true
local isSaving = false
local nameCache: { [number]: string } = {}
local rowLabels: { RowLabels } = {}
local developerName: TextLabel
local developerBest: TextLabel

local Scoreboard = {}

local function warnOnce(message: unknown)
	if not hasWarned then
		hasWarned = true
		warn(`[NeuralGlass] Best streaks aren't being saved: {message}`)
	end
end

-- Runs a DataStore call. Returns nil if there is no store or the call fails.
local function tryStore<T>(call: (OrderedDataStore) -> T): T?
	local current = store
	if current == nil then
		return nil
	end
	local ok, result = pcall(call, current)
	if not ok then
		warnOnce(result)
		return nil
	end
	return result
end

local function save()
	if isSaving then
		return
	end
	isSaving = true
	for userId, best in Leaderboard.takeUnsaved(board) do
		-- Keep whichever is higher: another server may have saved a better one for this player.
		local saved = tryStore(function(current: OrderedDataStore): number
			local key = tostring(userId)
			return (
				current:UpdateAsync(key, function(old: number?): number
					return math.max(old or 0, best)
				end)
			) :: number
		end)
		if saved == nil then
			Leaderboard.markUnsaved(board, userId, best)
		end
	end
	isSaving = false
end

local function refresh()
	local pages = tryStore(function(current: OrderedDataStore): DataStorePages
		return current:GetSortedAsync(false, BoardConfig.SIZE)
	end)
	if pages ~= nil then
		for _, entry in pages:GetCurrentPage() do
			if Leaderboard.ingest(board, tonumber(entry.key) :: number, entry.value) then
				needsRender = true
			end
		end
	end
	-- The developer may be outside the top of the board, and is pinned regardless.
	local developerKey = tostring(BoardConfig.DEVELOPER_USER_ID)
	local best = tryStore(function(current: OrderedDataStore): number?
		return (current:GetAsync(developerKey))
	end)
	if best ~= nil and Leaderboard.ingest(board, BoardConfig.DEVELOPER_USER_ID, best) then
		needsRender = true
	end
end

-- Display names are already moderated by Roblox. Looks up any it doesn't know, for this user and the rest
-- on the board in one request.
local function cacheNames(userIds: { number })
	local missing: { number } = {}
	for _, userId in userIds do
		if nameCache[userId] == nil then
			local player = Players:GetPlayerByUserId(userId)
			if player ~= nil then
				nameCache[userId] = player.DisplayName
			else
				table.insert(missing, userId)
			end
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok then
		for _, info in infos do
			nameCache[info.Id] = info.DisplayName
		end
	end
end

local function newLabel(parent: Instance, name: string, textSize: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = textSize
	label.TextColor3 = color
	label.Text = ""
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent
	return label
end

-- A row: rank on the left, then the name, then the best on the right.
local function newRow(parent: Instance, y: number, height: number, color: Color3): RowLabels
	local textSize = BoardConfig.ROW_TEXT_SIZE
	local root = Instance.new("Frame")
	root.Name = "Row"
	root.BackgroundTransparency = 1
	root.Position = UDim2.fromScale(0, y)
	root.Size = UDim2.fromScale(1, height)
	root.Parent = parent

	local rankWidth = BoardConfig.RANK_WIDTH
	local bestWidth = BoardConfig.BEST_WIDTH
	local rank = newLabel(root, "Rank", textSize, BoardConfig.MUTED_COLOR)
	rank.Size = UDim2.fromScale(rankWidth, 1)
	local name = newLabel(root, "Name", textSize, color)
	name.Position = UDim2.fromScale(rankWidth, 0)
	name.Size = UDim2.fromScale(1 - rankWidth - bestWidth, 1)
	name.TextXAlignment = Enum.TextXAlignment.Left
	local best = newLabel(root, "Best", textSize, color)
	best.Position = UDim2.fromScale(1 - bestWidth, 0)
	best.Size = UDim2.fromScale(bestWidth, 1)
	return { root = root, rank = rank, name = name, best = best }
end

local function buildPanel()
	local width = BoardConfig.WIDTH
	local height = BoardConfig.HEIGHT
	local panel = Instance.new("Part")
	panel.Name = "Scoreboard"
	panel.Anchored = true
	panel.CanCollide = false
	panel.CanQuery = false
	panel.CanTouch = false
	panel.CastShadow = false
	panel.Size = Vector3.new(width, height, BoardConfig.DEPTH)
	panel.Position = BoardConfig.POSITION
	panel.Color = BoardConfig.PANEL_COLOR
	panel.Material = Enum.Material.SmoothPlastic
	panel.Parent = workspace:WaitForChild("Lab")

	local trim = Instance.new("Part")
	trim.Name = "Trim"
	trim.Anchored = true
	trim.CanCollide = false
	trim.CanQuery = false
	trim.CanTouch = false
	trim.CastShadow = false
	trim.Size = Vector3.new(width, BoardConfig.TRIM_HEIGHT, BoardConfig.DEPTH)
	trim.Position = BoardConfig.POSITION + Vector3.new(0, (height + BoardConfig.TRIM_HEIGHT) / 2, 0)
	trim.Color = BoardConfig.TRIM_COLOR
	trim.Material = Enum.Material.Neon
	trim.Parent = panel

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- +Z, facing the room
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = BoardConfig.PIXELS_PER_STUD
	gui.Parent = panel

	local rowCount = BoardConfig.SIZE
	-- In shares of the panel's height: title, the rows, then the pinned developer block at the bottom.
	local titleShare = BoardConfig.TITLE_SHARE
	local developerShare = BoardConfig.DEVELOPER_SHARE
	local rowShare = (1 - titleShare - developerShare) / rowCount

	local title = newLabel(gui, "Title", BoardConfig.TITLE_TEXT_SIZE, BoardConfig.TEXT_COLOR)
	title.Font = Enum.Font.GothamBold
	title.Size = UDim2.fromScale(1, titleShare)
	title.Text = BoardConfig.TITLE

	for index = 1, rowCount do
		local row = newRow(gui, titleShare + (index - 1) * rowShare, rowShare, BoardConfig.TEXT_COLOR)
		row.root.Visible = false
		rowLabels[index] = row
	end

	local developerRoot = Instance.new("Frame")
	developerRoot.Name = "Developer"
	developerRoot.BackgroundColor3 = BoardConfig.DEVELOPER_BACKGROUND_COLOR
	developerRoot.BorderSizePixel = 0
	developerRoot.Position = UDim2.fromScale(0, 1 - developerShare)
	developerRoot.Size = UDim2.fromScale(1, developerShare)
	developerRoot.Parent = gui

	local caption = newLabel(developerRoot, "Caption", BoardConfig.CAPTION_TEXT_SIZE, BoardConfig.DEVELOPER_COLOR)
	caption.Size = UDim2.fromScale(1, 0.4)
	caption.Text = BoardConfig.DEVELOPER_CAPTION
	local row = newRow(developerRoot, 0.4, 0.6, BoardConfig.DEVELOPER_COLOR)
	row.rank.Text = BoardConfig.DEVELOPER_TAG
	row.rank.TextColor3 = BoardConfig.DEVELOPER_COLOR
	developerName = row.name
	developerBest = row.best
	developerBest.Text = BoardConfig.NO_BEST
end

local function render()
	local rows = Leaderboard.rows(board)
	local userIds: { number } = { BoardConfig.DEVELOPER_USER_ID }
	for _, row in rows do
		table.insert(userIds, row.userId)
	end
	cacheNames(userIds)

	for index, labels in rowLabels do
		local row = rows[index]
		labels.root.Visible = row ~= nil
		if row ~= nil then
			local name = nameCache[row.userId] or BoardConfig.UNKNOWN_NAME
			labels.rank.Text = tostring(row.rank)
			labels.name.Text = if row.isDeveloper then `{name} ({BoardConfig.DEVELOPER_TAG})` else name
			labels.best.Text = tostring(row.best)
		end
	end

	developerName.Text = nameCache[BoardConfig.DEVELOPER_USER_ID] or BoardConfig.UNKNOWN_NAME
	local best = Leaderboard.developerBest(board)
	developerBest.Text = if best ~= nil then tostring(best) else BoardConfig.NO_BEST
end

-- A player's own all-time best, so only a real improvement is saved.
local function loadPlayer(player: Player)
	local best = tryStore(function(current: OrderedDataStore): number?
		return (current:GetAsync(tostring(player.UserId)))
	end)
	if best ~= nil and Leaderboard.ingest(board, player.UserId, best) then
		needsRender = true
	end
end

function Scoreboard.recordStreak(player: Player, streak: number)
	if Leaderboard.recordStreak(board, player.UserId, streak) then
		needsRender = true
	end
end

function Scoreboard.start()
	buildPanel()

	-- Studio gets its own store, so test streaks never reach the live board.
	local storeName = if RunService:IsStudio() then BoardConfig.STUDIO_STORE_NAME else BoardConfig.STORE_NAME
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(storeName)
	end)
	if ok then
		store = result
	else
		warnOnce(result)
	end

	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(function()
		task.spawn(save)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end
	-- The server waits for this before it shuts down, so a new best isn't lost.
	game:BindToClose(function()
		isSaving = false
		save()
	end)

	task.spawn(function()
		while true do
			refresh()
			task.wait(BoardConfig.REFRESH_SECONDS)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(BoardConfig.SAVE_SECONDS)
			save()
		end
	end)
	task.spawn(function()
		while true do
			if needsRender then
				needsRender = false
				render()
			end
			task.wait(BoardConfig.RENDER_SECONDS)
		end
	end)
end

return Scoreboard
