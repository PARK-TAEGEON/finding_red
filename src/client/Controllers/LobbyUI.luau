--!strict
-- Lobby + stage vote UI (CONTRACT §1.1). Owner: C.
-- Lobby: party list with ✔ marks, Ready toggle, friend invite. Vote: stage cards with Korean
-- names, own stamp counts (StageFlags) and live vote counts.
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
local voteTitle: TextLabel
local voteTimer: TextLabel
local cardRow: Frame
local voteNote: TextLabel

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

local function stampText(flags: number): string
	local out = ""
	for _, bit in ipairs({ 1, 2, 4 }) do
		out ..= if bit32.band(flags, bit) ~= 0 then "★" else "☆"
	end
	return out
end

local function renderVote(s: Types.MatchState)
	Kit.clear(cardRow, { "UIListLayout" })
	local options = s.Options or {}
	local ballot = s.Ballot or {}
	local member = table.find(s.Party, player.UserId) ~= nil
	local flags = Actions.stageFlags()
	for i, stageId in ipairs(options) do
		local cfg = StagesConfig[stageId]
		local card = Kit.button(cardRow, "", {
			Size = UDim2.fromOffset(160, 190),
			BackgroundColor3 = if myVote == stageId then C.GreenDark else C.PanelLight,
			AutoButtonColor = member,
			LayoutOrder = i,
		})
		Kit.corner(card, UDim.new(0, 16))
		Kit.stroke(card, if myVote == stageId then C.Gold else C.Ink, 3)
		local level = Kit.label(card, "LEVEL " .. stageId, {
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.new(1, -20, 0, 34),
			Font = Kit.Title,
			TextColor3 = C.Gold,
		})
		Kit.textStroke(level, C.Ink, 2)
		Kit.label(card, if type(cfg) == "table" then tostring(cfg.Name) else stageId, {
			Position = UDim2.fromOffset(10, 50),
			Size = UDim2.new(1, -20, 0, 30),
		})
		Kit.label(card, stampText(flags[stageId] or 0), {
			Position = UDim2.fromOffset(10, 88),
			Size = UDim2.new(1, -20, 0, 34),
			TextColor3 = C.Red,
			Font = Kit.Title,
		})
		local count = Kit.label(card, string.format("%d표", ballot[stageId] or 0), {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.fromOffset(90, 36),
			BackgroundTransparency = 0,
			BackgroundColor3 = C.Panel,
			Font = Kit.Title,
		})
		Kit.round(count)
		Kit.padding(count, 5)
		card.Activated:Connect(function()
			if not member then
				return
			end
			myVote = stageId
			Net.event(ctx.Remotes, "Vote"):FireServer(stageId)
			renderVote(ctx.State())
		end)
	end
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
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(600, 330),
		BackgroundTransparency = 0.1,
		Visible = false,
	})
	Kit.corner(votePanel, UDim.new(0, 22))
	Kit.stroke(votePanel, C.White, 3)
	local voteScale = Instance.new("UIScale")
	voteScale.Parent = votePanel
	voteTitle = Kit.label(votePanel, "스테이지 고르기", {
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -140, 0, 40),
		Font = Kit.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Kit.textStroke(voteTitle, C.Ink, 2)
	voteTimer = Kit.label(votePanel, "", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 12),
		Size = UDim2.fromOffset(110, 40),
		Font = Kit.Title,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	cardRow = Kit.frame(votePanel, {
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.new(1, -32, 0, 200),
		BackgroundTransparency = 1,
	})
	Kit.list(cardRow, true, 14)
	voteNote = Kit.label(votePanel, "", {
		Position = UDim2.fromOffset(20, 280),
		Size = UDim2.new(1, -40, 0, 26),
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
			voteScale.Scale = math.clamp(math.min(vp.X / 640, vp.Y / 400), 0.5, 1)
		end
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
