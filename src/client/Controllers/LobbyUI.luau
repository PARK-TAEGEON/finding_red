--!strict
-- Lobby + stage vote UI (CONTRACT §1.1, §1.12.5). Owner: C.
-- Lobby: party list with ✔ marks, Ready toggle, friend invite. Vote: level-select grid
-- ("LEVEL 1" + numbered tiles from Config.Stages.Order grouped by Level), 3 stamp circles per tile
-- from my StageFlags, locked tiles grey with a lock, votes as small dots, my vote highlighted.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local StagesConfig = require(Shared.Config.Stages)

local UI = script.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Actions = require(UI:WaitForChild("Actions"))

local LobbyUI = {}

local player = Players.LocalPlayer
local ctx: Types.ClientContext
local C = Kit.Colors

local gui: ScreenGui
local lobbyPanel: Frame
local partyRow: Frame
local statusLabel: TextLabel
local readyButton: TextButton
local votePanel: Frame
local voteTimer: TextLabel
local levelList: Frame
local voteNote: TextLabel
local voteScaleBox: UIScale

local myVote: string? = nil
local lastPhase = ""
local lastRound = -1
local pendingReady: boolean? = nil

local function toast(text: string)
	pcall(function()
		ctx.Controllers.HUD:Toast(text)
	end)
end

local function amReady(s: Types.MatchState): boolean
	if pendingReady ~= nil then
		return pendingReady
	end
	return s.Ready ~= nil and table.find(s.Ready, player.UserId) ~= nil
end

local function renderLobby(s: Types.MatchState)
	Kit.clear(partyRow, { "UIListLayout" })
	local readyIds = s.Ready or {}
	for i, p in ipairs(Players:GetPlayers()) do
		local isReady = table.find(readyIds, p.UserId) ~= nil
		local chip = Kit.frame(partyRow, {
			Size = UDim2.fromOffset(118, 40),
			BackgroundColor3 = if isReady then C.GreenDark else C.PanelLight,
			LayoutOrder = i,
		})
		Kit.round(chip)
		Kit.stroke(chip, if p == player then C.Gold else C.Ink, 2)
		Kit.label(chip, (if isReady then "✔ " else "… ") .. p.DisplayName, {
			Position = UDim2.fromOffset(8, 6),
			Size = UDim2.new(1, -16, 1, -12),
		})
	end
	local ready = amReady(s)
	readyButton.Text = if ready then "준비 취소" else "준비!"
	readyButton.BackgroundColor3 = if ready then C.Gray else C.Green
end

local function renderStatus(s: Types.MatchState)
	local readyCount = if s.Ready then #s.Ready else 0
	local total = #Players:GetPlayers()
	if readyCount == 0 then
		statusLabel.Text = "준비를 누르면 출발해요"
	elseif readyCount >= total then
		statusLabel.Text = "출발!"
	elseif s.EndsAt then
		local left = math.max(0, math.ceil(s.EndsAt - workspace:GetServerTimeNow()))
		statusLabel.Text = string.format("모두 준비하면 바로 출발 · %d초 후 자동 출발 (%d/%d)", left, readyCount, total)
	else
		statusLabel.Text = string.format("준비 %d/%d", readyCount, total)
	end
end

local TILE_W, TILE_H, TILE_GAP, PER_ROW = 112, 132, 12, 5

-- Scale the vote panel (offset-sized, grows with the grid) to fit the screen.
local function fitVote()
	local camera = workspace.CurrentCamera
	if camera and votePanel and voteScaleBox then
		local vp = camera.ViewportSize
		local w, h = votePanel.Size.X.Offset, votePanel.Size.Y.Offset
		voteScaleBox.Scale = math.clamp(math.min(vp.X / (w + 40), vp.Y / (h + 90)), 0.45, 1.2)
	end
end
local LOCKED = Color3.fromRGB(78, 82, 92)
local LOCKED_DARK = Color3.fromRGB(56, 59, 68)
local DOT_COLORS = { C.Green, C.Blue, Color3.fromRGB(255, 150, 40), Color3.fromRGB(170, 90, 230) }

-- Stage ids of Config.Stages.Order grouped by Level, levels ascending.
local function levels(): { { Level: number, Stages: { string } } }
	local byLevel: { [number]: { string } } = {}
	local order: { number } = {}
	for _, id in ipairs(StagesConfig.Order) do
		local cfg = StagesConfig[id]
		local level = if type(cfg) == "table" and type(cfg.Level) == "number" then cfg.Level else 1
		if not byLevel[level] then
			byLevel[level] = {}
			table.insert(order, level)
		end
		table.insert(byLevel[level], id)
	end
	table.sort(order)
	local out = {}
	for _, level in ipairs(order) do
		table.insert(out, { Level = level, Stages = byLevel[level] })
	end
	return out
end

-- "1-3" -> "3"
local function tileNumber(stageId: string): string
	return string.match(stageId, "%-(%d+)$") or stageId
end

local function lockIcon(parent: Instance)
	local holder = Kit.frame(parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(36, 42),
		BackgroundTransparency = 1,
		ZIndex = 4,
	})
	local shackle = Kit.frame(holder, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(24, 26),
		BackgroundTransparency = 1,
		ZIndex = 4,
	})
	Kit.corner(shackle, UDim.new(0.5, 0))
	Kit.stroke(shackle, C.Gray, 5)
	local body = Kit.frame(holder, {
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.fromOffset(36, 26),
		BackgroundColor3 = C.Gray,
		ZIndex = 5,
	})
	Kit.corner(body, UDim.new(0, 5))
	local hole = Kit.frame(body, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(7, 9),
		BackgroundColor3 = LOCKED_DARK,
		ZIndex = 6,
	})
	Kit.round(hole)
end

local function stampCircles(parent: Instance, flags: number, locked: boolean)
	local row = Kit.frame(parent, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -16, 0, 22),
		BackgroundTransparency = 1,
		ZIndex = 4,
	})
	Kit.list(row, true, 7)
	for i, bit in ipairs({ 1, 2, 4 }) do
		local on = bit32.band(flags, bit) ~= 0
		local circle = Kit.frame(row, {
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = if on then C.Red else LOCKED_DARK,
			BackgroundTransparency = if on then 0 else 0.3,
			LayoutOrder = i,
			ZIndex = 4,
		})
		Kit.round(circle)
		Kit.stroke(circle, if on then C.RedDark elseif locked then C.Gray else C.Chalk, 2)
	end
end

local function voteDots(parent: Instance, count: number, mine: boolean)
	if count <= 0 then
		return
	end
	local row = Kit.frame(parent, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(60, 14),
		BackgroundTransparency = 1,
		ZIndex = 6,
	})
	Kit.list(row, true, 3, Enum.HorizontalAlignment.Right)
	for i = 1, math.min(count, 4) do
		-- my vote is the gold dot; teammates' votes take the other colours
		local color = if mine and i == 1 then C.Gold else DOT_COLORS[((i - 1) % #DOT_COLORS) + 1]
		local dot = Kit.frame(row, {
			Size = UDim2.fromOffset(13, 13),
			BackgroundColor3 = color,
			LayoutOrder = i,
			ZIndex = 6,
		})
		Kit.round(dot)
		Kit.stroke(dot, C.Ink, 2)
	end
end

local function renderVote(s: Types.MatchState)
	Kit.clear(levelList, { "UIListLayout" })
	local options = s.Options or {}
	local ballot = s.Ballot or {}
	local member = table.find(s.Party, player.UserId) ~= nil
	local flags = Actions.stageFlags()
	local height = 0
	for li, group in ipairs(levels()) do
		local rows = math.max(1, math.ceil(#group.Stages / PER_ROW))
		local sectionH = 46 + rows * TILE_H + (rows - 1) * TILE_GAP
		height += sectionH + (if li > 1 then 10 else 0)
		local section = Kit.frame(levelList, {
			Size = UDim2.new(1, 0, 0, sectionH),
			BackgroundTransparency = 1,
			LayoutOrder = li,
		})
		local header = Kit.label(section, "LEVEL " .. tostring(group.Level), {
			Position = UDim2.fromOffset(4, 0),
			Size = UDim2.new(1, -130, 0, 40),
			Font = Kit.Title,
			TextColor3 = C.Gold,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		Kit.textStroke(header, C.Ink, 2)
		local grid = Kit.frame(section, {
			Position = UDim2.fromOffset(0, 46),
			Size = UDim2.new(1, 0, 1, -46),
			BackgroundTransparency = 1,
		})
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
		layout.CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.Parent = grid

		for i, stageId in ipairs(group.Stages) do
			local cfg = StagesConfig[stageId]
			local unlocked = table.find(options, stageId) ~= nil
			local chosen = myVote == stageId
			local tile = Kit.button(grid, "", {
				BackgroundColor3 = if not unlocked then LOCKED elseif chosen then C.GreenDark else C.PanelLight,
				AutoButtonColor = member and unlocked,
				LayoutOrder = i,
				ZIndex = 3,
			})
			Kit.corner(tile, UDim.new(0, 14))
			Kit.stroke(tile, if chosen then C.Gold elseif unlocked then C.Chalk else LOCKED_DARK, if chosen then 5 else 3)
			if unlocked then
				local number = Kit.label(tile, tileNumber(stageId), {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 10),
					Size = UDim2.new(1, -20, 0, 54),
					Font = Kit.Title,
					TextColor3 = C.White,
					ZIndex = 4,
				})
				Kit.textStroke(number, C.Ink, 3)
			else
				lockIcon(tile)
			end
			Kit.label(tile, if type(cfg) == "table" then tostring(cfg.Name) else stageId, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 68),
				Size = UDim2.new(1, -12, 0, 20),
				TextColor3 = if unlocked then C.Chalk else C.Gray,
				ZIndex = 4,
			})
			stampCircles(tile, flags[stageId] or 0, not unlocked)
			voteDots(tile, if unlocked then ballot[stageId] or 0 else 0, chosen)
			tile.Activated:Connect(function()
				if not member then
					return
				end
				if not unlocked then
					toast("아직 잠긴 스테이지예요")
					return
				end
				myVote = stageId
				Net.event(ctx.Remotes, "Vote"):FireServer(stageId)
				renderVote(ctx.State())
			end)
		end
	end
	levelList.Size = UDim2.new(1, -32, 0, height)
	votePanel.Size = UDim2.fromOffset(PER_ROW * TILE_W + (PER_ROW - 1) * TILE_GAP + 32, 16 + height + 50)
	fitVote()
	voteNote.Text = if member
		then "가고 싶은 스테이지를 누르세요 · 동점이면 앞 번호"
		else "관전 중 · 다음 판부터 함께해요"
end

local function render(s: Types.MatchState)
	if s.Phase ~= lastPhase or s.RoundId ~= lastRound then
		myVote = nil
		pendingReady = nil
		lastPhase = s.Phase
		lastRound = s.RoundId
	end
	lobbyPanel.Visible = s.Phase == "Lobby"
	votePanel.Visible = s.Phase == "Vote"
	if s.Phase == "Lobby" then
		renderLobby(s)
		renderStatus(s)
	elseif s.Phase == "Vote" then
		renderVote(s)
	end
end

local function invite()
	task.spawn(function()
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if ok and can then
			local shown = pcall(function()
				SocialService:PromptGameInvite(player)
			end)
			if not shown then
				toast("초대 창을 열 수 없어요")
			end
		else
			toast("지금은 친구를 초대할 수 없어요")
		end
	end)
end

local function build()
	gui = Kit.gui("FindingRedLobby", 4, player:WaitForChild("PlayerGui"))

	lobbyPanel = Kit.frame(gui, {
		Name = "LobbyPanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(560, 200),
		BackgroundTransparency = 0.1,
		Visible = false,
	})
	Kit.corner(lobbyPanel, UDim.new(0, 20))
	Kit.stroke(lobbyPanel, C.White, 3)
	local scale = Instance.new("UIScale")
	scale.Parent = lobbyPanel
	local title = Kit.label(lobbyPanel, "파티", {
		Position = UDim2.fromOffset(20, 10),
		Size = UDim2.new(1, -40, 0, 32),
		Font = Kit.Title,
		TextColor3 = C.Gold,
	})
	Kit.textStroke(title, C.Ink, 2)
	partyRow = Kit.frame(lobbyPanel, {
		Position = UDim2.fromOffset(16, 46),
		Size = UDim2.new(1, -32, 0, 44),
		BackgroundTransparency = 1,
	})
	Kit.list(partyRow, true, 8)
	statusLabel = Kit.label(lobbyPanel, "", {
		Position = UDim2.fromOffset(20, 96),
		Size = UDim2.new(1, -40, 0, 24),
		TextColor3 = C.Chalk,
	})
	readyButton = Kit.button(lobbyPanel, "준비!", {
		Position = UDim2.fromOffset(20, 130),
		Size = UDim2.new(0.62, -26, 0, 56),
		BackgroundColor3 = C.Green,
	})
	Kit.corner(readyButton, UDim.new(0, 16))
	Kit.stroke(readyButton, C.Ink, 3)
	Kit.padding(readyButton, 9)
	local inviteButton = Kit.button(lobbyPanel, "친구 초대", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 130),
		Size = UDim2.new(0.38, -14, 0, 56),
		BackgroundColor3 = C.Blue,
	})
	Kit.corner(inviteButton, UDim.new(0, 16))
	Kit.stroke(inviteButton, C.Ink, 3)
	Kit.padding(inviteButton, 11)

	votePanel = Kit.frame(gui, {
		Name = "VotePanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(640, 260),
		BackgroundTransparency = 0.08,
		Visible = false,
	})
	Kit.corner(votePanel, UDim.new(0, 22))
	Kit.stroke(votePanel, C.White, 3)
	voteScaleBox = Instance.new("UIScale")
	voteScaleBox.Parent = votePanel
	voteTimer = Kit.label(votePanel, "", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 16),
		Size = UDim2.fromOffset(110, 38),
		Font = Kit.Title,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 2,
	})
	Kit.textStroke(voteTimer, C.Ink, 2)
	levelList = Kit.frame(votePanel, {
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.new(1, -32, 0, 200),
		BackgroundTransparency = 1,
	})
	Kit.list(levelList, false, 10, Enum.HorizontalAlignment.Left).VerticalAlignment = Enum.VerticalAlignment.Top
	voteNote = Kit.label(votePanel, "", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -14),
		Size = UDim2.new(1, -40, 0, 24),
		TextColor3 = C.Chalk,
	})

	readyButton.Activated:Connect(function()
		local s = ctx.State()
		if s.Phase ~= "Lobby" then
			return
		end
		local want = not amReady(s)
		pendingReady = want
		Net.event(ctx.Remotes, "Ready"):FireServer(want)
		renderLobby(s)
	end)
	inviteButton.Activated:Connect(invite)

	local function fit()
		local camera = workspace.CurrentCamera
		if camera then
			local vp = camera.ViewportSize
			scale.Scale = math.clamp(math.min(vp.X / 600, vp.Y / 420), 0.55, 1)
		end
		fitVote()
	end
	fit()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
end

function LobbyUI.Init(self: Types.LobbyUI, c: Types.ClientContext)
	ctx = c
end

function LobbyUI.Start(self: Types.LobbyUI)
	build()
	Actions.onState(function(s)
		-- the server answered: drop the optimistic ready flag
		pendingReady = nil
		render(s)
	end)
	local function rerender()
		render(ctx.State())
	end
	Players.PlayerAdded:Connect(rerender)
	Players.PlayerRemoving:Connect(function()
		task.defer(rerender)
	end)
	player:GetAttributeChangedSignal("StageFlags"):Connect(function()
		if ctx.State().Phase == "Vote" then
			rerender()
		end
	end)
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.2 then
			return
		end
		accum = 0
		local s = ctx.State()
		if s.Phase == "Lobby" then
			renderStatus(s)
		elseif s.Phase == "Vote" and s.EndsAt then
			voteTimer.Text = string.format("%d초", math.max(0, math.ceil(s.EndsAt - workspace:GetServerTimeNow())))
		end
	end)
	rerender()
end

return LobbyUI
