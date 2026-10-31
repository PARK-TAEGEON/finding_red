--!strict
-- In-match HUD (CONTRACT §1.5, §1.6, §3.5). Owner: C.
-- Receives `State` -> ctx.SetState, drives camera/weapon mode by phase + own Life, and draws:
-- gold + target counter, radar, HP + team keys, weapon/ammo, full-screen hurt flash, toasts, downed
-- overlay, revive prompt (hold E), loading overlay, start-room door banner + hand button,
-- chalkboard mission banner, result screen, pause menu.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local GameConfig = require(Shared.Config.Game)
local StagesConfig = require(Shared.Config.Stages)
local WeaponsConfig: any = require(Shared.Config.Weapons)

local UI = script.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Actions = require(UI:WaitForChild("Actions"))
local Radar = require(UI:WaitForChild("Radar"))
local ResultScreen = require(UI:WaitForChild("ResultScreen"))
local PauseMenu = require(UI:WaitForChild("PauseMenu"))
local Loading = require(UI:WaitForChild("Loading"))

local HUDController = {}

local player = Players.LocalPlayer
local ctx: Types.ClientContext
local C = Kit.Colors

-- UI handles (created in Start)
local gui: ScreenGui
local goldLabel: TextLabel
local counterFrame: Frame
local counterLabel: TextLabel
local timerLabel: TextLabel
local radar: Radar.Radar
local hpFrame: Frame
local hpFill: Frame
local hpText: TextLabel
local keyRow: Frame
local weaponFrame: Frame
local weaponName: TextLabel
local weaponAmmo: TextLabel
local hurtFlash: Frame
local hurtTween: Tween? = nil
local toastList: Frame
local downedOverlay: Frame
local downedTitle: TextLabel
local downedInfo: TextLabel
local downedBar: Frame
local downedTrack: Frame
local spectateBanner: TextLabel
local revivePrompt: Frame
local reviveText: TextLabel
local reviveBar: Frame
local startLabel: TextLabel
local doorBanner: TextLabel
local doorPrompt: Frame
local doorButton: TextButton
local doorButtonScale: UIScale
local doorHint: TextLabel
local loading: Loading.Loading
local board: Frame
local boardLines: { TextLabel } = {}
local boardScale: UIScale
local resultScreen: ResultScreen.ResultScreen
local pauseMenu: PauseMenu.PauseMenu

-- client state
local lastFirstPerson: boolean? = nil
local lastWeaponOn: boolean? = nil
local lastLife = "Alive"
local flagsSnapshot: { [string]: number }? = nil
local myVote: string? = nil
local boardHideToken = 0
local started = false

local function state(): Types.MatchState
	return ctx.State()
end

local function inParty(): boolean
	return table.find(state().Party, player.UserId) ~= nil
end

local function stagePhase(phase: string): boolean
	return phase == "Countdown" or phase == "Playing" or phase == "Result"
end

-- Camera / weapon mode ------------------------------------------------------------
-- First person while playing and in the start room (walk to the door like the original);
-- weapons only while playing (the server ignores shots before the door opens).
local function refreshMode()
	local paused = pauseMenu ~= nil and pauseMenu.IsOpen()
	local weaponOn = Actions.canAct() and not paused
	local firstPerson = (Actions.canAct() or Actions.inStartRoom()) and not paused
	if firstPerson ~= lastFirstPerson then
		lastFirstPerson = firstPerson
		pcall(function()
			ctx.Controllers.Camera:SetFirstPerson(firstPerson)
		end)
	end
	if weaponOn ~= lastWeaponOn then
		lastWeaponOn = weaponOn
		pcall(function()
			ctx.Controllers.Weapon:SetEnabled(weaponOn)
		end)
	end
end

-- Toasts --------------------------------------------------------------------------
local function toast(text: string)
	if not toastList then
		return
	end
	local items = toastList:GetChildren()
	local count = 0
	for _, item in ipairs(items) do
		if item:IsA("TextLabel") then
			count += 1
		end
	end
	if count >= 4 then
		for _, item in ipairs(items) do
			if item:IsA("TextLabel") then
				item:Destroy()
				break
			end
		end
	end
	local label = Kit.label(toastList, text, {
		Size = UDim2.fromOffset(460, 36),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = C.Panel,
		TextScaled = true,
		LayoutOrder = math.floor(os.clock() * 100) % 1000000,
		ZIndex = 30,
	})
	Kit.corner(label, UDim.new(1, 0))
	Kit.padding(label, 6)
	local s = Kit.stroke(label, C.White, 2)
	task.delay(2.6, function()
		if label.Parent then
			TweenService:Create(label, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			TweenService:Create(s, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			task.wait(0.45)
			label:Destroy()
		end
	end)
end

-- Hurt flash (§1.12.7): the whole screen goes translucent red and fades in ~0.3 s ----------
local function hurt(amount: number)
	local intensity = math.clamp(amount / 40, 0.3, 0.55)
	if hurtTween then
		hurtTween:Cancel()
	end
	hurtFlash.BackgroundTransparency = 1 - intensity
	hurtFlash.Visible = true
	local tween = TweenService:Create(hurtFlash, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})
	hurtTween = tween
	tween:Play()
	ctx.PlaySound("PlayerHurt")
end

-- Chalkboard banner ------------------------------------------------------------------
local function showBoard(s: Types.MatchState)
	local stageId = s.StageId
	if not stageId then
		return
	end
	local cfg = StagesConfig[stageId]
	local mission = if type(cfg) == "table" and type(cfg.Mission) == "string" then cfg.Mission else "레드 %d마리 잡기"
	local ok, missionText = pcall(string.format, mission, s.Target)
	boardLines[1].Text = "LEVEL " .. stageId
	boardLines[2].Text = if ok then missionText else mission
	boardLines[3].Text = "힌트: " .. (if type(cfg) == "table" then tostring(cfg.Hint or "") else "")
	board.Visible = true
	boardScale.Scale = 0.6
	TweenService:Create(boardScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	boardHideToken += 1
end

local function hideBoardLater(seconds: number)
	boardHideToken += 1
	local token = boardHideToken
	task.delay(seconds, function()
		if token == boardHideToken then
			board.Visible = false
		end
	end)
end

-- Static refresh (on state / attribute change) ---------------------------------------
local function refreshWeapon()
	local equipped = player:GetAttribute("Equipped")
	if type(equipped) ~= "string" or equipped == "" then
		weaponName.Text = ""
		weaponAmmo.Text = ""
		return
	end
	local cfg = if type(WeaponsConfig) == "table" then WeaponsConfig[equipped] else nil
	weaponName.Text = if type(cfg) == "table" and type(cfg.Name) == "string" then cfg.Name else equipped
	local mag = player:GetAttribute("Mag_" .. equipped)
	local ammo = player:GetAttribute("Ammo_" .. equipped)
	if type(mag) == "number" then
		weaponAmmo.Text = if type(ammo) == "number" then string.format("%d / %d", mag, ammo) else tostring(mag)
		weaponAmmo.TextColor3 = if mag <= 0 then C.Red else C.White
	else
		weaponAmmo.Text = "∞"
		weaponAmmo.TextColor3 = C.White
	end
end

local function refreshHP()
	local hp = player:GetAttribute("HP")
	local value = if type(hp) == "number" then hp else GameConfig.MaxHP
	local alpha = math.clamp(value / GameConfig.MaxHP, 0, 1)
	hpFill.Size = UDim2.fromScale(alpha, 1)
	hpFill.BackgroundColor3 = if alpha > 0.5 then C.Green elseif alpha > 0.25 then C.Gold else C.Red
	hpText.Text = string.format("HP %d", math.ceil(value))
end

local function refreshKeys(s: Types.MatchState)
	Kit.clear(keyRow, { "UIListLayout" })
	for i, color in ipairs(s.Keys or {}) do
		local icon = Kit.frame(keyRow, {
			Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = Kit.keyColor(color),
			LayoutOrder = i,
		})
		Kit.corner(icon, UDim.new(0, 8))
		Kit.stroke(icon, C.Ink, 2)
		Kit.label(icon, "열쇠", {
			Size = UDim2.fromScale(0.9, 0.5),
			Position = UDim2.fromScale(0.05, 0.25),
			TextColor3 = C.Ink,
		})
	end
end

local function refreshStatic()
	local s = state()
	local phase = s.Phase
	local member = inParty()
	local inStage = stagePhase(phase) and member
	local gold = player:GetAttribute("Gold")
	goldLabel.Text = if type(gold) == "number" then tostring(gold) else "-"
	counterFrame.Visible = stagePhase(phase)
	counterLabel.Text = string.format("%d/%d", s.Killed, s.Target)
	radar.Frame.Visible = stagePhase(phase) and phase ~= "Result"
	hpFrame.Visible = inStage and phase ~= "Result"
	keyRow.Visible = inStage
	weaponFrame.Visible = phase == "Playing" and member and Actions.myLife() == "Alive"
	spectateBanner.Visible = stagePhase(phase) and not member
	refreshKeys(s)
	refreshHP()
	refreshWeapon()
end

-- Life ------------------------------------------------------------------------------
local function onLifeChanged()
	local life = Actions.myLife()
	if life == "Downed" and lastLife ~= "Downed" then
		ctx.PlaySound("Downed")
		Actions.stopRevive()
		Actions.setSprint(false)
	elseif life == "Alive" and lastLife == "Downed" then
		ctx.PlaySound("Revived")
	end
	lastLife = life
	Actions.applySpeed()
	refreshMode()
	refreshStatic()
end

local function watchTeammate(other: Player)
	if other == player then
		return
	end
	local last = Actions.lifeOf(other)
	other:GetAttributeChangedSignal("Life"):Connect(function()
		local life = Actions.lifeOf(other)
		local s = state()
		if s.Phase == "Playing" and table.find(s.Party, other.UserId) then
			if life == "Downed" and last == "Alive" then
				toast(other.DisplayName .. " 님이 쓰러졌어요! 가까이 가서 살려 주세요")
			elseif life == "Alive" and last == "Downed" then
				toast(other.DisplayName .. " 님이 일어났어요")
			elseif life == "Out" then
				toast(other.DisplayName .. " 님이 탈락했어요")
			end
		end
		last = life
	end)
end

-- State -----------------------------------------------------------------------------
local function onState(newState: Types.MatchState)
	if type(newState) ~= "table" then
		return
	end
	local prev = state()
	ctx.SetState(newState)
	Actions.publish(newState)
	local phase = newState.Phase
	local newRound = newState.RoundId ~= prev.RoundId

	if phase ~= prev.Phase or newRound then
		myVote = nil
	end
	local member = table.find(newState.Party, player.UserId) ~= nil

	-- Loading overlay (§1.12.4): Countdown with EndsAt == nil = the server is building/teleporting.
	if phase == "Countdown" and newState.EndsAt == nil and member then
		loading.Show(GameConfig.LoadingSeconds)
	elseif loading.IsShown() then
		loading.Finish()
	end
	if phase == "Countdown" and (prev.Phase ~= "Countdown" or newRound) then
		flagsSnapshot = Actions.stageFlags()
	end

	-- Start room (§1.12.3): Countdown with EndsAt = auto-open time.
	local startRoom = phase == "Countdown" and newState.EndsAt ~= nil
	local wasStartRoom = prev.Phase == "Countdown" and prev.EndsAt ~= nil and not newRound
	if startRoom and not wasStartRoom and member then
		showBoard(newState)
		hideBoardLater(6)
	elseif startRoom and newState.Target ~= prev.Target and board.Visible then
		showBoard(newState)
		hideBoardLater(4)
	end
	if phase == "Playing" and prev.Phase ~= "Playing" then
		local door = workspace:FindFirstChild("Stage") and (workspace :: any).Stage:FindFirstChild("StartDoor", true)
		ctx.PlaySound("DoorOpen", if door and door:IsA("BasePart") then door.Position else nil) -- orchestrator
		startLabel.Text = "시작!"
		startLabel.Visible = true
		task.delay(0.9, function()
			startLabel.Visible = false
		end)
		board.Visible = false
	end
	if phase ~= "Countdown" then
		board.Visible = false
	end
	if phase == "Playing" and not newRound and newState.PenaltyKills > prev.PenaltyKills then
		toast("레드가 아닌 몬스터를 처치했어요 (깔끔 도장 실패)")
	end

	if phase == "Result" and newState.Result then
		local personalNew: number? = nil
		local snapshot = flagsSnapshot
		if snapshot and table.find(newState.Party, player.UserId) then
			local before = snapshot[newState.Result.StageId] or 0
			personalNew = bit32.band(newState.Result.Flags, bit32.bnot(before))
		end
		resultScreen.Show(newState, personalNew)
		resultScreen.Update(newState, myVote)
	else
		resultScreen.Hide()
	end
	if phase ~= "Playing" then
		Actions.stopRevive()
	end
	Actions.applySpeed()
	refreshMode()
	refreshStatic()
end

-- Per-frame -------------------------------------------------------------------------
local radarAccum = 0
local slowAccum = 0

local function onFrame(dt: number)
	local s = state()
	local t = workspace:GetServerTimeNow()

	radarAccum += dt
	if radarAccum >= 1 / 30 and radar.Frame.Visible then
		radarAccum = 0
		radar.Update(s)
	end

	-- start room: door banner with the auto-open countdown + hand button near the door
	local inRoom = s.Phase == "Countdown" and s.EndsAt ~= nil and table.find(s.Party, player.UserId) ~= nil
	doorBanner.Visible = inRoom
	if inRoom and s.EndsAt then
		doorBanner.Text = string.format("문을 열고 들어가세요! (%d)", math.max(0, math.ceil(s.EndsAt - t)))
	end
	local canOpen = Actions.canOpenDoor()
	if canOpen ~= doorPrompt.Visible then
		doorPrompt.Visible = canOpen
		if canOpen then
			doorButtonScale.Scale = 0.6
			TweenService:Create(doorButtonScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
	end
	if canOpen then
		doorButton.Rotation = math.sin(os.clock() * 6) * 8 -- a little wave
	end

	-- stage timer (elapsed / par)
	if s.Phase == "Playing" and s.StartedAt then
		local elapsed = t - s.StartedAt
		local par = s.ParTime or 0
		timerLabel.Text = string.format("%s / %s", Kit.formatTime(elapsed), Kit.formatTime(par))
		timerLabel.TextColor3 = if elapsed <= par then C.Gold else C.Gray
	elseif s.Phase == "Countdown" then
		timerLabel.Text = string.format("기준 %s", Kit.formatTime(s.ParTime or 0))
		timerLabel.TextColor3 = C.Gold
	end

	-- downed / out overlay
	local life = Actions.myLife()
	local member = table.find(s.Party, player.UserId) ~= nil
	local showDowned = member and (s.Phase == "Playing" or s.Phase == "Countdown") and (life == "Downed" or life == "Out")
	downedOverlay.Visible = showDowned
	if showDowned then
		if life == "Downed" then
			local bleedAt = player:GetAttribute("BleedOutAt")
			local left = if type(bleedAt) == "number" then math.max(0, math.ceil(bleedAt - t)) else 0
			local progress = player:GetAttribute("ReviveProgress")
			local p = if type(progress) == "number" then progress else 0
			downedTitle.Text = "쓰러졌어요!"
			downedInfo.Text = if p > 0
				then "동료가 살려 주는 중..."
				else string.format("동료가 살려 줄 때까지 %d초", left)
			downedBar.Size = UDim2.fromScale(p, 1)
			downedTrack.Visible = true
		else
			downedTitle.Text = "탈락"
			downedInfo.Text = "이번 판은 관전 중이에요"
			downedTrack.Visible = false
		end
	end

	-- revive prompt
	Actions.watchRevive()
	local target = Actions.reviving() or Actions.reviveCandidate()
	revivePrompt.Visible = target ~= nil
	if target then
		local progress = target:GetAttribute("ReviveProgress")
		local p = if type(progress) == "number" and Actions.reviving() then progress else 0
		reviveBar.Size = UDim2.fromScale(p, 1)
		if Actions.reviving() then
			reviveText.Text = target.DisplayName .. " 님 살리는 중..."
		elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			reviveText.Text = "부활 버튼을 길게 눌러 " .. target.DisplayName .. " 님 살리기"
		else
			reviveText.Text = "E 길게 누르기: " .. target.DisplayName .. " 님 살리기"
		end
	end

	slowAccum += dt
	if slowAccum >= 0.25 then
		slowAccum = 0
		if s.Phase == "Result" and resultScreen.Visible() then
			resultScreen.Update(s, myVote)
		end
		refreshMode()
	end
end

-- Build -----------------------------------------------------------------------------
local function build()
	local playerGui = player:WaitForChild("PlayerGui")
	gui = Kit.gui("FindingRedHUD", 5, playerGui)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	-- full-screen hurt flash (bottom-most, never blocks input)
	hurtFlash = Kit.frame(gui, {
		Name = "Hurt",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(230, 20, 20),
		BackgroundTransparency = 1,
		Active = false,
		ZIndex = 1,
	})
	loading = Loading.new(playerGui)

	-- top center: gold + counter
	local top = Kit.frame(gui, {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(360, 44),
		BackgroundTransparency = 1,
	})
	Kit.list(top, true, 14)
	local goldPill = Kit.frame(top, { Size = UDim2.fromOffset(140, 40), BackgroundColor3 = C.Panel, LayoutOrder = 1 })
	goldPill.BackgroundTransparency = 0.15
	Kit.round(goldPill)
	Kit.stroke(goldPill, C.Ink, 3)
	local coin = Kit.frame(goldPill, {
		Position = UDim2.fromOffset(5, 5),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = C.Gold,
	})
	Kit.round(coin)
	Kit.stroke(coin, Color3.fromRGB(170, 120, 20), 2)
	Kit.label(coin, "G", { Font = Kit.Title, TextColor3 = Color3.fromRGB(150, 100, 10) })
	goldLabel = Kit.label(goldPill, "-", {
		Position = UDim2.fromOffset(40, 4),
		Size = UDim2.new(1, -50, 1, -8),
		Font = Kit.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	counterFrame = Kit.frame(top, { Size = UDim2.fromOffset(150, 40), BackgroundColor3 = C.Panel, LayoutOrder = 2 })
	counterFrame.BackgroundTransparency = 0.15
	Kit.round(counterFrame)
	Kit.stroke(counterFrame, C.Ink, 3)
	local face = Kit.frame(counterFrame, {
		Position = UDim2.fromOffset(5, 5),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = C.Red,
	})
	Kit.corner(face, UDim.new(0, 7))
	Kit.stroke(face, C.RedDark, 2)
	for _, x in ipairs({ 0.22, 0.58 }) do
		local eye = Kit.frame(face, {
			Position = UDim2.fromScale(x, 0.25),
			Size = UDim2.fromScale(0.22, 0.24),
			BackgroundColor3 = Color3.fromRGB(255, 230, 40),
		})
		Kit.round(eye)
	end
	Kit.frame(face, {
		Position = UDim2.fromScale(0.25, 0.65),
		Size = UDim2.fromScale(0.5, 0.12),
		BackgroundColor3 = C.White,
	})
	counterLabel = Kit.label(counterFrame, "0/0", {
		Position = UDim2.fromOffset(42, 4),
		Size = UDim2.new(1, -50, 1, -8),
		Font = Kit.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	timerLabel = Kit.label(counterFrame, "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.fromOffset(150, 22),
		Font = Kit.Title,
		TextColor3 = C.Gold,
	})
	Kit.textStroke(timerLabel, C.Ink, 2)

	-- top right: radar + pause button
	local radarSize = if touch then 120 else 150
	radar = Radar.new(gui, radarSize)
	radar.Frame.AnchorPoint = Vector2.new(1, 0)
	radar.Frame.Position = UDim2.new(1, -16, 0, 64)
	local pauseButton = Kit.button(gui, "II", {
		Name = "PauseButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16 - radarSize - 10, 0, 64),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = C.Panel,
	})
	Kit.round(pauseButton)
	Kit.stroke(pauseButton, C.White, 2)
	Kit.padding(pauseButton, 9)

	-- top left: HP + keys (below Roblox's top bar buttons)
	hpFrame = Kit.frame(gui, {
		Name = "HP",
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.fromOffset(240, 30),
		BackgroundColor3 = C.Ink,
	})
	Kit.round(hpFrame)
	Kit.stroke(hpFrame, C.White, 2)
	hpFill = Kit.frame(hpFrame, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Green })
	Kit.round(hpFill)
	hpText = Kit.label(hpFrame, "HP 100", { Font = Kit.Title, ZIndex = 2 })
	Kit.textStroke(hpText, C.Ink, 2)
	keyRow = Kit.frame(gui, {
		Name = "Keys",
		Position = UDim2.fromOffset(16, 100),
		Size = UDim2.fromOffset(240, 32),
		BackgroundTransparency = 1,
	})
	Kit.list(keyRow, true, 6, Enum.HorizontalAlignment.Left)

	-- bottom right (PC) / under radar (touch): weapon + ammo
	weaponFrame = Kit.frame(gui, {
		Name = "Weapon",
		AnchorPoint = Vector2.new(1, if touch then 0 else 1),
		Position = if touch then UDim2.new(1, -16, 0, 64 + radarSize + 10) else UDim2.new(1, -20, 1, -20),
		Size = UDim2.fromOffset(200, 74),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
	})
	Kit.corner(weaponFrame, UDim.new(0, 14))
	Kit.stroke(weaponFrame, C.Ink, 3)
	weaponName = Kit.label(weaponFrame, "", {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Chalk,
	})
	weaponAmmo = Kit.label(weaponFrame, "", {
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(1, -24, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Kit.Title,
	})
	Kit.textStroke(weaponAmmo, C.Ink, 2)

	-- toasts
	toastList = Kit.frame(gui, {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 126),
		Size = UDim2.fromOffset(480, 170),
		BackgroundTransparency = 1,
		ZIndex = 30,
	})
	local toastLayout = Kit.list(toastList, false, 6)
	toastLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	-- spectate banner
	spectateBanner = Kit.label(gui, "관전 중 · 다음 판부터 함께해요", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(420, 40),
		BackgroundTransparency = 0.2,
		BackgroundColor3 = C.Panel,
		Visible = false,
	})
	Kit.round(spectateBanner)
	Kit.padding(spectateBanner, 7)

	-- downed overlay
	downedOverlay = Kit.frame(gui, {
		Name = "Downed",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.RedDark,
		BackgroundTransparency = 0.7,
		Visible = false,
		ZIndex = 10,
	})
	local downedPanel = Kit.frame(downedOverlay, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(420, 150),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.1,
		ZIndex = 11,
	})
	Kit.corner(downedPanel, UDim.new(0, 18))
	Kit.stroke(downedPanel, C.White, 3)
	downedTitle = Kit.label(downedPanel, "쓰러졌어요!", {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 52),
		Font = Kit.Title,
		TextColor3 = C.Red,
		ZIndex = 12,
	})
	Kit.textStroke(downedTitle, C.Ink, 2)
	downedInfo = Kit.label(downedPanel, "", {
		Position = UDim2.fromOffset(16, 66),
		Size = UDim2.new(1, -32, 0, 28),
		ZIndex = 12,
	})
	downedTrack = Kit.frame(downedPanel, {
		Position = UDim2.fromOffset(40, 106),
		Size = UDim2.new(1, -80, 0, 18),
		BackgroundColor3 = C.Ink,
		ZIndex = 12,
	})
	Kit.round(downedTrack)
	downedBar = Kit.frame(downedTrack, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Green, ZIndex = 13 })
	Kit.round(downedBar)

	-- revive prompt
	revivePrompt = Kit.frame(gui, {
		Name = "RevivePrompt",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(420, 66),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		Visible = false,
		ZIndex = 12,
	})
	Kit.corner(revivePrompt, UDim.new(0, 16))
	Kit.stroke(revivePrompt, C.Green, 3)
	reviveText = Kit.label(revivePrompt, "", {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 30),
		ZIndex = 13,
	})
	local reviveTrack = Kit.frame(revivePrompt, {
		Position = UDim2.fromOffset(24, 42),
		Size = UDim2.new(1, -48, 0, 14),
		BackgroundColor3 = C.Ink,
		ZIndex = 13,
	})
	Kit.round(reviveTrack)
	reviveBar = Kit.frame(reviveTrack, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Green, ZIndex = 14 })
	Kit.round(reviveBar)

	-- "시작!" when the door opens
	startLabel = Kit.label(gui, "", {
		Name = "Start",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(260, 110),
		Font = Kit.Title,
		TextColor3 = C.Gold,
		Visible = false,
		ZIndex = 15,
	})
	Kit.textStroke(startLabel, C.Ink, 5)

	-- start room: small top banner + big hand button (tap / click / E)
	doorBanner = Kit.label(gui, "", {
		Name = "DoorBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.fromOffset(330, 34),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = C.Panel,
		Font = Kit.Title,
		TextColor3 = C.White,
		Visible = false,
		ZIndex = 16,
	})
	Kit.round(doorBanner)
	Kit.padding(doorBanner, 5)
	Kit.stroke(doorBanner, C.Gold, 2)
	doorPrompt = Kit.frame(gui, {
		Name = "DoorPrompt",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.66),
		Size = UDim2.fromOffset(150, 170),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 16,
	})
	doorButton = Kit.button(doorPrompt, "✋", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(120, 120),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.05,
		TextColor3 = C.Ink,
		Font = Enum.Font.GothamBold,
		ZIndex = 17,
	})
	Kit.round(doorButton)
	Kit.stroke(doorButton, C.Gold, 5)
	Kit.padding(doorButton, 18)
	doorButtonScale = Instance.new("UIScale")
	doorButtonScale.Parent = doorButton
	doorHint = Kit.label(doorPrompt, if touch then "눌러서 문 열기" else "E: 문 열기", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 128),
		Size = UDim2.fromOffset(170, 34),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = C.Panel,
		Font = Kit.Title,
		ZIndex = 17,
	})
	Kit.round(doorHint)
	Kit.padding(doorHint, 5)
	doorButton.Activated:Connect(function()
		Actions.openDoor()
	end)

	-- chalkboard mission banner
	board = Kit.frame(gui, {
		Name = "Board",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 130),
		Size = UDim2.fromOffset(520, 176),
		BackgroundColor3 = C.Board,
		Visible = false,
		ZIndex = 14,
	})
	Kit.corner(board, UDim.new(0, 10))
	Kit.stroke(board, C.Wood, 9)
	boardScale = Instance.new("UIScale")
	boardScale.Parent = board
	local lineSpecs = {
		{ Y = 12, H = 40, Font = Kit.Title, Color = C.Gold },
		{ Y = 58, H = 56, Font = Kit.Title, Color = C.Chalk },
		{ Y = 124, H = 32, Font = Kit.Body, Color = C.Chalk },
	}
	for _, spec in ipairs(lineSpecs) do
		local l = Kit.label(board, "", {
			Position = UDim2.fromOffset(20, spec.Y),
			Size = UDim2.new(1, -40, 0, spec.H),
			Font = spec.Font,
			TextColor3 = spec.Color,
			ZIndex = 15,
		})
		table.insert(boardLines, l)
	end

	-- result + pause
	resultScreen = ResultScreen.new(gui, function(key)
		ctx.PlaySound(key)
	end, function(option)
		myVote = option
		Net.event(ctx.Remotes, "Vote"):FireServer(option)
		resultScreen.Update(state(), myVote)
	end)

	local function sendSensitivity(value: number, final: boolean)
		pcall(function()
			ctx.Controllers.Camera:SetSensitivity(value)
		end)
		if final then
			Net.event(ctx.Remotes, "Setting"):FireServer("Sensitivity", value)
		end
	end
	pauseMenu = PauseMenu.new(gui, {
		OnClose = function()
			refreshMode()
		end,
		OnSensitivity = sendSensitivity,
		OnLobbyInfo = function()
			toast("결과 화면에서 '로비로'에 투표하면 로비로 돌아가요")
		end,
	})
	pauseButton.Activated:Connect(function()
		if pauseMenu.IsOpen() then
			pauseMenu.Close()
		else
			pauseMenu.Open()
			refreshMode()
		end
	end)
end

local function applySavedSensitivity()
	local v = player:GetAttribute("Sensitivity")
	if type(v) == "number" then
		pcall(function()
			ctx.Controllers.Camera:SetSensitivity(v)
		end)
		pauseMenu.SetSensitivity(v)
	end
end

-- Public API ----------------------------------------------------------------------
function HUDController.Init(self: Types.HUDController, c: Types.ClientContext)
	ctx = c
	Actions.init(c)
end

function HUDController.Start(self: Types.HUDController)
	build()
	started = true

	Net.event(ctx.Remotes, "State").OnClientEvent:Connect(onState)
	Net.event(ctx.Remotes, "Feedback").OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" then
			return
		end
		if data.Kind == "Hurt" then
			hurt(if type(data.Amount) == "number" then data.Amount else 10)
		elseif data.Kind == "Message" and type(data.Text) == "string" then
			toast(data.Text)
		elseif data.Kind == "PickedUp" and type(data.Text) == "string" then
			toast(if data.Item == "Weapon" or data.Item == nil and data.Weapon ~= nil then data.Text .. " (3번 키)" else data.Text) -- review v0.5 #3
		end
	end)

	player:GetAttributeChangedSignal("Life"):Connect(onLifeChanged)
	player:GetAttributeChangedSignal("HP"):Connect(refreshHP)
	player:GetAttributeChangedSignal("Gold"):Connect(refreshStatic)
	player:GetAttributeChangedSignal("Sensitivity"):Connect(applySavedSensitivity)
	player.AttributeChanged:Connect(function(name)
		if name == "Equipped" or string.sub(name, 1, 4) == "Mag_" or string.sub(name, 1, 5) == "Ammo_" then
			refreshWeapon()
		end
	end)
	player.CharacterAdded:Connect(function()
		task.defer(Actions.applySpeed)
	end)
	for _, other in ipairs(Players:GetPlayers()) do
		watchTeammate(other)
	end
	Players.PlayerAdded:Connect(watchTeammate)

	-- Keyboard: Shift = sprint toggle, E = hold to revive, Esc / P = pause.
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.P then
			if processed and input.KeyCode ~= Enum.KeyCode.Escape then
				return
			end
			if pauseMenu.IsOpen() then
				pauseMenu.Close()
			elseif not processed then
				pauseMenu.Open()
				refreshMode()
			end
			return
		end
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			if Actions.myLife() == "Alive" then
				Actions.toggleSprint()
			end
		elseif input.KeyCode == Enum.KeyCode.E then
			if not Actions.openDoor() then
				Actions.startRevive()
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- first person locks the mouse, so a click anywhere near the door also opens it
			if Actions.canOpenDoor() then
				Actions.openDoor()
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.E then
			Actions.stopRevive()
		end
	end)

	RunService.RenderStepped:Connect(onFrame)
	lastLife = Actions.myLife()
	applySavedSensitivity()
	refreshMode()
	refreshStatic()
end

function HUDController.Toast(self: Types.HUDController, text: string)
	if started then
		toast(text)
	end
end

return HUDController
