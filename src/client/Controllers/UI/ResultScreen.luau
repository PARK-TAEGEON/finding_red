--!strict
-- Result screen: "미션 성공!!" / "미션 실패", three stamps popping in, gold, Next/Retry/Lobby vote. Owner: C.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local StagesConfig = require(Shared.Config.Stages)
local Kit = require(script.Parent.Kit)

export type ResultScreen = {
	Show: (state: Types.MatchState, personalNew: number?) -> (),
	Update: (state: Types.MatchState, myVote: string?) -> (),
	Hide: () -> (),
	Visible: () -> boolean,
}

local ResultScreen = {}

local STAMPS = {
	{ Bit = 1, Text = "성공", Caption = "클리어" },
	{ Bit = 2, Text = "빠름", Caption = "기준 시간 안에" },
	{ Bit = 4, Text = "깔끔", Caption = "레드만 처치" },
}

local OPTION_TEXT: { [string]: string } = {
	Next = "다음 스테이지",
	Retry = "다시하기",
	Lobby = "로비로",
}

function ResultScreen.new(
	parent: Instance,
	playSound: (key: string) -> (),
	onVote: (option: string) -> ()
): ResultScreen
	local root = Kit.frame(parent, {
		Name = "Result",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 20,
	})
	local panel = Kit.frame(root, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 560, 0, 430),
		BackgroundColor3 = Kit.Colors.Panel,
		ZIndex = 21,
	})
	Kit.corner(panel, UDim.new(0, 22))
	Kit.stroke(panel, Kit.Colors.White, 4)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(560, 430)
	constraint.Parent = panel
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local title = Kit.label(panel, "", {
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(1, -40, 0, 64),
		Font = Kit.Title,
		ZIndex = 22,
	})
	Kit.textStroke(title, Kit.Colors.Ink, 3)
	local subtitle = Kit.label(panel, "", {
		Position = UDim2.fromOffset(20, 80),
		Size = UDim2.new(1, -40, 0, 26),
		TextColor3 = Kit.Colors.Chalk,
		ZIndex = 22,
	})

	local stampRow = Kit.frame(panel, {
		Position = UDim2.fromOffset(20, 116),
		Size = UDim2.new(1, -40, 0, 140),
		BackgroundTransparency = 1,
		ZIndex = 22,
	})
	Kit.list(stampRow, true, 34)

	type StampUi = { Holder: Frame, Ink: Frame, InkScale: UIScale, Text: TextLabel, New: TextLabel, Slot: UIStroke }
	local stamps: { StampUi } = {}
	for i, info in ipairs(STAMPS) do
		local holder = Kit.frame(stampRow, {
			Size = UDim2.fromOffset(110, 140),
			BackgroundTransparency = 1,
			LayoutOrder = i,
			ZIndex = 22,
		})
		local slot = Kit.frame(holder, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(100, 100),
			BackgroundColor3 = Kit.Colors.PanelLight,
			ZIndex = 22,
		})
		Kit.round(slot)
		local slotStroke = Kit.stroke(slot, Kit.Colors.Gray, 3)
		local ink = Kit.frame(slot, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Kit.Colors.Red,
			Rotation = -12,
			Visible = false,
			ZIndex = 23,
		})
		Kit.round(ink)
		Kit.stroke(ink, Kit.Colors.RedDark, 5)
		local inkScale = Instance.new("UIScale")
		inkScale.Parent = ink
		local inkText = Kit.label(ink, info.Text, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.75, 0.45),
			Font = Kit.Title,
			ZIndex = 24,
		})
		Kit.label(holder, info.Caption, {
			Position = UDim2.fromOffset(0, 106),
			Size = UDim2.new(1, 0, 0, 20),
			TextColor3 = Kit.Colors.Chalk,
			ZIndex = 22,
		})
		local new = Kit.label(holder, "NEW!", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 4, 0, -6),
			Size = UDim2.fromOffset(52, 22),
			BackgroundTransparency = 0,
			BackgroundColor3 = Kit.Colors.Gold,
			TextColor3 = Kit.Colors.Ink,
			Font = Kit.Title,
			Rotation = 10,
			Visible = false,
			ZIndex = 26,
		})
		Kit.corner(new, UDim.new(0, 6))
		table.insert(stamps, { Holder = holder, Ink = ink, InkScale = inkScale, Text = inkText, New = new, Slot = slotStroke })
	end

	local stats = Kit.label(panel, "", {
		Position = UDim2.fromOffset(20, 262),
		Size = UDim2.new(1, -40, 0, 24),
		TextColor3 = Kit.Colors.Chalk,
		ZIndex = 22,
	})
	local gold = Kit.label(panel, "", {
		Position = UDim2.fromOffset(20, 290),
		Size = UDim2.new(1, -40, 0, 34),
		TextColor3 = Kit.Colors.Gold,
		Font = Kit.Title,
		ZIndex = 22,
	})
	Kit.textStroke(gold, Kit.Colors.Ink, 2)

	local buttons = Kit.frame(panel, {
		Position = UDim2.fromOffset(20, 334),
		Size = UDim2.new(1, -40, 0, 56),
		BackgroundTransparency = 1,
		ZIndex = 22,
	})
	Kit.list(buttons, true, 12)
	local timer = Kit.label(panel, "", {
		Position = UDim2.fromOffset(20, 396),
		Size = UDim2.new(1, -40, 0, 22),
		TextColor3 = Kit.Colors.Gray,
		ZIndex = 22,
	})

	local optionButtons: { [string]: TextButton } = {}
	local shownRound = -1
	local animToken = 0

	local function fitScale()
		local camera = workspace.CurrentCamera
		if camera then
			local vp = camera.ViewportSize
			scale.Scale = math.clamp(math.min(vp.X / 600, vp.Y / 470), 0.5, 1)
		end
	end

	local function show(state: Types.MatchState, personalNew: number?)
		local result = state.Result
		if not result then
			return
		end
		fitScale()
		root.Visible = true
		if shownRound == state.RoundId then
			return
		end
		shownRound = state.RoundId
		animToken += 1
		local token = animToken
		local cfg = StagesConfig[result.StageId]
		local name = if type(cfg) == "table" then cfg.Name else ""
		title.Text = if result.Cleared then "미션 성공!!" else "미션 실패"
		title.TextColor3 = if result.Cleared then Kit.Colors.Gold else Kit.Colors.Red
		subtitle.Text = string.format("LEVEL %s  %s", result.StageId, tostring(name))
		local par = state.ParTime or 0
		stats.Text = string.format(
			"레드 %d/%d   ·   시간 %s (기준 %s)%s",
			result.Killed,
			result.Target,
			Kit.formatTime(result.Seconds),
			Kit.formatTime(par),
			if result.PenaltyKills > 0 then string.format("   ·   레드 아닌 처치 %d", result.PenaltyKills) else ""
		)
		local myGold = result.Gold[tostring(Players.LocalPlayer.UserId)]
		gold.Text = if myGold then string.format("+%d 골드", myGold) else "관전"
		local newBits = personalNew or result.NewFlags

		for _, s in ipairs(stamps) do
			s.Ink.Visible = false
			s.New.Visible = false
			s.Slot.Color = Kit.Colors.Gray
		end
		playSound(if result.Cleared then "StageClear" else "StageFail")
		task.spawn(function()
			task.wait(0.6)
			for i, info in ipairs(STAMPS) do
				if token ~= animToken then
					return
				end
				local s = stamps[i]
				if bit32.band(result.Flags, info.Bit) ~= 0 then
					s.Ink.Visible = true
					s.InkScale.Scale = 2.2
					s.Ink.BackgroundTransparency = 1
					TweenService:Create(s.InkScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
						:Play()
					TweenService:Create(s.Ink, TweenInfo.new(0.18), { BackgroundTransparency = 0 }):Play()
					playSound("Stamp")
					if bit32.band(newBits, info.Bit) ~= 0 then
						s.New.Visible = true
						s.Slot.Color = Kit.Colors.Gold
					end
					task.wait(0.45)
				end
			end
		end)
	end

	local function update(state: Types.MatchState, myVote: string?)
		local options = state.Options or {}
		local ballot = state.Ballot or {}
		local canVote = table.find(state.Party, Players.LocalPlayer.UserId) ~= nil
		for option, b in pairs(optionButtons) do
			if not table.find(options, option) then
				b:Destroy()
				optionButtons[option] = nil
			end
		end
		for i, option in ipairs(options) do
			local b = optionButtons[option]
			if not b then
				local created = Kit.button(buttons, "", {
					Size = UDim2.fromOffset(160, 52),
					LayoutOrder = i,
					ZIndex = 23,
				})
				Kit.corner(created, UDim.new(0, 14))
				Kit.stroke(created, Kit.Colors.Ink, 3)
				Kit.padding(created, 8)
				created.Activated:Connect(function()
					onVote(option)
				end)
				optionButtons[option] = created
				b = created
			end
			local button = b :: TextButton
			button.Text = string.format("%s  %d", OPTION_TEXT[option] or option, ballot[option] or 0)
			button.Active = canVote
			button.AutoButtonColor = canVote
			button.BackgroundColor3 = if myVote == option
				then Kit.Colors.Green
				elseif option == "Next" then Kit.Colors.Blue
				else Kit.Colors.PanelLight
		end
		local remaining = if state.EndsAt then state.EndsAt - workspace:GetServerTimeNow() else 0
		timer.Text = if canVote
			then string.format("투표하세요 · %d초", math.max(0, math.ceil(remaining)))
			else string.format("관전 중 · %d초", math.max(0, math.ceil(remaining)))
	end

	local function hide()
		root.Visible = false
		animToken += 1
	end

	return {
		Show = show,
		Update = update,
		Hide = hide,
		Visible = function()
			return root.Visible
		end,
	}
end

return ResultScreen
