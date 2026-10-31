--!strict
-- Server match loop (CONTRACT §1.1–1.5, §3.4 StageFlow). Owner: C.
-- Lobby -> Vote -> Countdown -> Playing -> Result -> (Next / Retry -> Countdown | Lobby).
-- Branchy decisions live in Flow/FlowLogic (pure, Lune-tested); this file does the Roblox side.
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Rules = require(Shared.Rules)
local GameConfig = require(Shared.Config.Game)
local StagesConfig = require(Shared.Config.Stages)
local EnemiesConfig: any = require(Shared.Config.Enemies)
local FlowLogic = require(script.Parent.Flow.FlowLogic)

type LifeRec = { Life: Types.LifeState, HP: number, DownedAt: number? }
type ReviveRec = { Target: Player, Progress: number }

local StageFlow = {}

local ctx: Types.Context
local serverId = ""
local stateEvent: RemoteEvent
local feedbackEvent: RemoteEvent

local state: Types.MatchState = {
	Phase = "Lobby",
	RoundId = 0,
	Target = 0,
	Killed = 0,
	PenaltyKills = 0,
	Party = {},
}
local party: { Player } = {}
local lives: { [Player]: LifeRec } = {}
local ready: { [Player]: boolean? } = {}
local firstReadyAt: number? = nil
local votes: { [number]: string } = {}
local lateJoiners: { Player } = {}
local revives: { [Player]: ReviveRec } = {}
local personalReds: { [Player]: number } = {}
local allDownSince: number? = nil
local pendingClear = false
local handle: Types.StageHandle? = nil
local spawnList: { BasePart } = {}
local stageBase = 1
local currentStageCfg: any = nil
local lastReload: { [Player]: number } = {}

local VOID_Y = -100
local VOTE_MIN_SECONDS = 2
local RESULT_MIN_SECONDS = 4
local LOBBY_BOARD = "파인딩 레드\n준비 버튼을 누르면 출발!\n레드만 잡으세요!" -- 3 board lines (review fix #5)

-- Helpers -------------------------------------------------------------------------
local function now(): number
	return workspace:GetServerTimeNow()
end

local function safe(label: string, fn: () -> ()): boolean
	local ok, err = pcall(fn :: any)
	if not ok then
		warn("[FindingRed] " .. label .. " failed:", err)
	end
	return ok
end

local function partyIds(): { number }
	local ids: { number } = {}
	for _, p in ipairs(party) do
		table.insert(ids, p.UserId)
	end
	return ids
end

local function inParty(player: Player): boolean
	return table.find(party, player) ~= nil
end

local function broadcast()
	state.Party = partyIds()
	stateEvent:FireAllClients(state)
end

local function feedback(player: Player, data: { [string]: any })
	if player.Parent then
		feedbackEvent:FireClient(player, data)
	end
end

local function message(player: Player, text: string)
	feedback(player, { Kind = "Message", Text = text })
end

local function messageParty(text: string)
	for _, p in ipairs(party) do
		message(p, text)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function stageFlagsOf(player: Player): { [string]: number }
	local out: { [string]: number } = {}
	local ok, profile = pcall(function()
		return ctx.Services.Data:Get(player)
	end)
	if ok and type(profile) == "table" and type(profile.Stages) == "table" then
		for id, record in pairs(profile.Stages) do
			if type(id) == "string" and type(record) == "table" and type(record.Flags) == "number" then
				out[id] = record.Flags
			end
		end
	end
	return out
end

-- Life ----------------------------------------------------------------------------
local function applyMovement(player: Player)
	local humanoid = humanoidOf(player)
	local rec = lives[player]
	if not humanoid or not rec then
		return
	end
	humanoid.WalkSpeed = FlowLogic.walkSpeed(rec.Life, GameConfig.WalkSpeed, GameConfig.DownedWalkSpeed)
	if rec.Life == "Downed" then
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	else
		humanoid.JumpHeight = StarterPlayer.CharacterJumpHeight
		humanoid.JumpPower = StarterPlayer.CharacterJumpPower
	end
end

local function setLife(player: Player, life: Types.LifeState, hp: number?)
	local rec = lives[player]
	if not rec then
		rec = { Life = life, HP = GameConfig.MaxHP, DownedAt = nil }
		lives[player] = rec
	end
	rec.Life = life
	if hp then
		rec.HP = hp
	end
	if life == "Downed" then
		rec.DownedAt = now()
	else
		rec.DownedAt = nil
	end
	if player.Parent then
		player:SetAttribute("Life", life)
		player:SetAttribute("HP", rec.HP)
		player:SetAttribute("ReviveProgress", 0)
		player:SetAttribute("BleedOutAt", if rec.DownedAt then rec.DownedAt + GameConfig.BleedOutSeconds else nil)
	end
	applyMovement(player)
end

local function cancelRevivesOn(target: Player)
	for reviver, rec in pairs(revives) do
		if rec.Target == target then
			revives[reviver] = nil
		end
	end
	if target.Parent then
		target:SetAttribute("ReviveProgress", 0)
	end
end

local function beingRevived(target: Player): boolean
	for _, rec in pairs(revives) do
		if rec.Target == target then
			return true
		end
	end
	return false
end

-- Placement -------------------------------------------------------------------------
local function lobbyCFrame(index: number): CFrame
	local ok, cf = pcall(function()
		return ctx.Services.Stage:LobbySpawn(index)
	end)
	if ok and typeof(cf) == "CFrame" then
		return cf -- LobbySpawn is already at root height (review fix #2)
	end
	return CFrame.new(index * 4, 8, 0)
end

local function stageCFrame(index: number): CFrame
	local slot = FlowLogic.spawnSlot(index, #spawnList)
	local marker = spawnList[slot]
	if marker and marker.Parent then
		local pos = marker.Position -- spawn markers already sit at root height (Kit.SpawnLift, review fix #2)
		local look = marker.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			return CFrame.lookAt(pos, pos + flat.Unit)
		end
		return CFrame.new(pos)
	end
	local o = GameConfig.StageOrigin
	return CFrame.new(o[1] + index * 4, o[2] + 8, o[3])
end

local function moveTo(player: Player, cf: CFrame)
	local character = player.Character
	local root = rootOf(player)
	if character and root then
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(cf)
	end
end

local function place(player: Player)
	if not player.Parent then
		return
	end
	local life: Types.LifeState = if lives[player] then lives[player].Life else "Spectating"
	local member = table.find(party, player)
	local where = FlowLogic.placement(state.Phase, member ~= nil, life, handle ~= nil)
	if where == "Stage" and member then
		moveTo(player, stageCFrame(member))
	else
		moveTo(player, lobbyCFrame(table.find(Players:GetPlayers(), player) or 1))
	end
end

local function reload(player: Player)
	local last = lastReload[player] or 0
	if os.clock() - last < 5 or not player.Parent then
		return
	end
	lastReload[player] = os.clock()
	pcall(function()
		player:LoadCharacterAsync()
	end)
end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	-- Players never die the Roblox way: real HP is the `HP` attribute.
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid.HealthChanged:Connect(function(health)
		if health < humanoid.MaxHealth then
			task.defer(function()
				if humanoid.Parent then
					humanoid.Health = humanoid.MaxHealth
				end
			end)
		end
	end)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root then
		root.AncestryChanged:Connect(function()
			-- Root destroyed (fell out of the world) while the character is still ours: rebuild it.
			if not root:IsDescendantOf(workspace) and player.Character == character then
				task.delay(1, function()
					if player.Character == character then
						reload(player)
					end
				end)
			end
		end)
	end
	applyMovement(player)
	-- Place after Roblox's own spawn positioning; repeat once in case a SpawnLocation moved it late.
	task.defer(place, player)
	task.delay(0.3, function()
		if player.Character == character then
			place(player)
		end
	end)
end

-- Stage lifecycle -----------------------------------------------------------------
local function cleanupStage()
	safe("Enemy:ClearAll", function()
		ctx.Services.Enemy:ClearAll()
	end)
	safe("Weapon:ClearStage", function()
		ctx.Services.Weapon:ClearStage()
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		safe("Weapon:StripLoadout", function()
			ctx.Services.Weapon:StripLoadout(p)
		end)
	end
	revives = {}
	for _, p in ipairs(Players:GetPlayers()) do
		p:SetAttribute("ReviveProgress", 0)
	end
end

-- Moves everyone to the lobby first (so nobody falls), then unloads the map.
local function leaveStage()
	handle = nil
	spawnList = {}
	for i, p in ipairs(Players:GetPlayers()) do
		moveTo(p, lobbyCFrame(i))
	end
	safe("Stage:Unload", function()
		ctx.Services.Stage:Unload()
	end)
end

local function refreshBoard()
	local cfg = currentStageCfg
	if not cfg or not state.StageId then
		return
	end
	local mission = if type(cfg.Mission) == "string" then cfg.Mission else "레드 %d마리 잡기"
	local okFmt, missionText = pcall(string.format, mission, state.Target)
	local lines = {
		"LEVEL " .. state.StageId,
		if okFmt then missionText else mission,
		"힌트: " .. tostring(cfg.Hint or ""),
	}
	safe("Stage:SetBoard", function()
		ctx.Services.Stage:SetBoard(lines)
	end)
end

local function prunedParty(): boolean
	for i = #party, 1, -1 do
		if not party[i].Parent then
			table.remove(party, i)
		end
	end
	return #party > 0
end

local function waitUntil(deadline: number?, done: () -> boolean)
	while true do
		if done() then
			return
		end
		if deadline and now() >= deadline then
			return
		end
		task.wait(0.1)
	end
end

-- Phases ----------------------------------------------------------------------------
local function enterLobby()
	party = {}
	ready = {}
	firstReadyAt = nil
	votes = {}
	lateJoiners = {}
	revives = {}
	personalReds = {}
	currentStageCfg = nil
	state = {
		Phase = "Lobby",
		RoundId = state.RoundId,
		Target = 0,
		Killed = 0,
		PenaltyKills = 0,
		Party = {},
		Ready = {},
	}
	for _, p in ipairs(Players:GetPlayers()) do
		setLife(p, "Alive", GameConfig.MaxHP)
	end
	safe("Stage:SetLobbyBoard", function()
		ctx.Services.Stage:SetLobbyBoard(LOBBY_BOARD)
	end)
	broadcast()
end

local function readyIds(): { number }
	local ids: { number } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if ready[p] then
			table.insert(ids, p.UserId)
		end
	end
	return ids
end

local function refreshLobbyTimer()
	local ids = readyIds()
	if #ids == 0 then
		firstReadyAt = nil
	elseif firstReadyAt == nil then
		firstReadyAt = now()
	end
	state.Ready = ids
	state.EndsAt = if firstReadyAt and #ids < #Players:GetPlayers()
		then firstReadyAt + GameConfig.ReadyTimeoutSeconds
		else nil
end

local function runLobby()
	enterLobby()
	while true do
		local present = #Players:GetPlayers()
		local readyCount = #readyIds()
		if FlowLogic.lobbyShouldStart(present, readyCount, firstReadyAt, now(), GameConfig.ReadyTimeoutSeconds) then
			break
		end
		task.wait(0.25)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if ready[p] and #party < GameConfig.MaxPlayers then
			table.insert(party, p)
		end
	end
	ready = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if not inParty(p) then
			setLife(p, "Spectating", GameConfig.MaxHP)
		end
	end
end

-- Returns the chosen stage id, or nil when the party vanished.
local function runVote(): string?
	local flags: { { [string]: number } } = {}
	for _, p in ipairs(party) do
		table.insert(flags, stageFlagsOf(p))
	end
	local options = Rules.partyUnlocked(StagesConfig.Order, flags)
	votes = {}
	local started = now()
	state = {
		Phase = "Vote",
		RoundId = state.RoundId,
		Target = 0,
		Killed = 0,
		PenaltyKills = 0,
		Party = partyIds(),
		Options = options,
		Ballot = FlowLogic.tally(votes, options),
		EndsAt = started + GameConfig.VoteSeconds,
	}
	broadcast()
	local endsAt = started + GameConfig.VoteSeconds
	waitUntil(nil, function()
		if not prunedParty() then
			return true
		end
		local everyone = #options <= 1 or FlowLogic.allVoted(partyIds(), votes)
		return FlowLogic.voteShouldEnd(now(), started, endsAt, everyone, VOTE_MIN_SECONDS)
	end)
	if #party == 0 or #options == 0 then
		return nil
	end
	return Rules.voteWinner(options, FlowLogic.tally(votes, options), options[#options])
end

local function membersAlive(): { Types.LifeState }
	local out: { Types.LifeState } = {}
	for _, p in ipairs(party) do
		table.insert(out, if lives[p] then lives[p].Life else "Out")
	end
	return out
end

local function tickRevives(dt: number)
	local best: { [Player]: number } = {}
	for reviver, rec in pairs(revives) do
		local target = rec.Target
		local a, b = rootOf(reviver), rootOf(target)
		local distance = if a and b then (a.Position - b.Position).Magnitude else math.huge
		local reviverLife: Types.LifeState = if lives[reviver] then lives[reviver].Life else "Out"
		local targetLife: Types.LifeState = if lives[target] then lives[target].Life else "Out"
		if
			not reviver.Parent
			or not target.Parent
			or not inParty(reviver)
			or not inParty(target)
			or not FlowLogic.canRevive(reviverLife, targetLife, distance, GameConfig.ReviveRange + 1)
		then
			revives[reviver] = nil
		else
			local progress, done = FlowLogic.reviveStep(rec.Progress, dt, GameConfig.ReviveHoldSeconds)
			rec.Progress = progress
			if done then
				cancelRevivesOn(target)
				setLife(target, "Alive", GameConfig.ReviveHP)
				message(target, reviver.DisplayName .. " 님이 살려 주었습니다!")
				message(reviver, target.DisplayName .. " 님을 살렸습니다!")
			else
				best[target] = math.max(best[target] or 0, progress)
			end
		end
	end
	for _, p in ipairs(party) do
		local rec = lives[p]
		if rec and rec.Life == "Downed" then
			p:SetAttribute("ReviveProgress", best[p] or 0)
		end
	end
end

local function tickBleed(dt: number)
	local t = now()
	for _, p in ipairs(party) do
		local rec = lives[p]
		if rec and rec.Life == "Downed" and rec.DownedAt then
			local reviving = beingRevived(p)
			if reviving then
				-- Bleed-out pauses while a teammate holds the revive.
				rec.DownedAt += dt
				p:SetAttribute("BleedOutAt", rec.DownedAt + GameConfig.BleedOutSeconds)
			end
			if FlowLogic.shouldBleedOut(rec.Life, rec.DownedAt, t, GameConfig.BleedOutSeconds, reviving) then
				cancelRevivesOn(p)
				setLife(p, "Out", 0)
				message(p, "이번 판은 관전합니다")
			end
		end
	end
end

-- Countdown + Playing + Result for one stage. Returns the next stage id, or nil for the lobby.
local function runStage(stageId: string): string?
	local cfg = StagesConfig[stageId]
	if type(cfg) ~= "table" or not prunedParty() then
		return nil
	end
	currentStageCfg = cfg
	stageBase = cfg.Red.Base
	local roundId = state.RoundId + 1
	local target = Rules.target(stageBase, #party, GameConfig.CoopScale)
	local timeLimit = Rules.timeLimit(cfg.ParTime, GameConfig.TimeLimitMultiplier)
	revives = {}
	personalReds = {}
	allDownSince = nil
	pendingClear = false
	votes = {}

	-- Countdown
	state = {
		Phase = "Countdown",
		RoundId = roundId,
		StageId = stageId,
		Target = target,
		Killed = 0,
		PenaltyKills = 0,
		ParTime = cfg.ParTime,
		Party = partyIds(),
		Keys = {},
		EndsAt = now() + GameConfig.CountdownSeconds,
	}
	for _, p in ipairs(Players:GetPlayers()) do
		if inParty(p) then
			setLife(p, "Alive", GameConfig.MaxHP)
		else
			setLife(p, "Spectating", GameConfig.MaxHP)
		end
	end
	broadcast()

	local loaded: Types.StageHandle? = nil
	safe("Stage:Load", function()
		loaded = ctx.Services.Stage:Load(stageId)
	end)
	if not loaded then
		messageParty("스테이지를 불러오지 못했습니다")
		return nil
	end
	local h = loaded :: Types.StageHandle
	handle = h
	spawnList = {}
	local markers = (h.Markers :: { [string]: { BasePart }? })["PlayerSpawn"]
	if markers then
		for _, m in ipairs(markers) do
			table.insert(spawnList, m)
		end
		table.sort(spawnList, function(a, b)
			return tostring(a:GetAttribute("MarkerId") or a.Name) < tostring(b:GetAttribute("MarkerId") or b.Name)
		end)
	end
	safe("Weapon:PrepareStage", function()
		ctx.Services.Weapon:PrepareStage(h)
	end)
	safe("Enemy:SpawnStage", function()
		ctx.Services.Enemy:SpawnStage(h, Rules.redSpawnCount(target, cfg.Red.Spare))
	end)
	for i, p in ipairs(party) do
		moveTo(p, stageCFrame(i))
		safe("Weapon:GiveLoadout", function()
			ctx.Services.Weapon:GiveLoadout(p)
		end)
	end
	refreshBoard()

	waitUntil(state.EndsAt, function()
		return not prunedParty()
	end)
	if #party == 0 then
		return nil
	end

	-- Playing
	local startedAt = now()
	state.Phase = "Playing"
	state.StartedAt = startedAt
	state.EndsAt = startedAt + timeLimit
	pendingClear = FlowLogic.isCleared(state.Killed, state.Target)
	broadcast()

	local cleared = false
	while true do
		local dt = task.wait(0.1)
		if not prunedParty() then
			return nil
		end
		if pendingClear then
			cleared = true
			break
		end
		tickRevives(dt)
		tickBleed(dt)
		allDownSince = FlowLogic.trackAllDown(FlowLogic.allDown(membersAlive()), allDownSince, now())
		local reason = FlowLogic.failReason(allDownSince, now(), GameConfig.AllDownGraceSeconds, startedAt, timeLimit)
		if reason then
			break
		end
	end

	-- Result
	local seconds = now() - startedAt
	local members: { FlowLogic.ResultMember } = {}
	for _, p in ipairs(party) do
		table.insert(members, {
			UserId = p.UserId,
			PrevFlags = stageFlagsOf(p)[stageId] or 0,
			RedKills = personalReds[p] or 0,
		})
	end
	local result = FlowLogic.buildResult(Rules, {
		StageId = stageId,
		Cleared = cleared,
		Seconds = seconds,
		ParTime = cfg.ParTime,
		Killed = state.Killed,
		Target = state.Target,
		PenaltyKills = state.PenaltyKills,
		Reward = cfg.Reward,
		PerRedOnFail = GameConfig.Reward.PerRedOnFail,
		Members = members,
	})
	cleanupStage()
	-- Party unlock view after this run (read before applying, merged with this run).
	local flagsAfter: { { [string]: number } } = {}
	for _, p in ipairs(party) do
		local merged = stageFlagsOf(p)
		merged[stageId] = Rules.mergeFlags(merged[stageId] or 0, result.Flags)
		table.insert(flagsAfter, merged)
	end
	for _, m in ipairs(result.Members) do
		local p = Players:GetPlayerByUserId(m.UserId)
		if p then
			local rid = FlowLogic.resultId(serverId, roundId, m.UserId)
			safe("Data:ApplyResult", function()
				ctx.Services.Data:ApplyResult(p, rid, stageId, result.Flags, result.Seconds, m.Gold, personalReds[p] or 0)
			end)
		end
	end
	local options, default = FlowLogic.resultOptions(Rules, StagesConfig.Order, stageId, cleared, flagsAfter)
	local resultStarted = now()
	local resultEnds = resultStarted + GameConfig.ResultSeconds
	votes = {}
	state.Phase = "Result"
	state.EndsAt = resultEnds
	state.Result = {
		StageId = result.StageId,
		Cleared = result.Cleared,
		Flags = result.Flags,
		NewFlags = result.NewFlags,
		Seconds = result.Seconds,
		Killed = result.Killed,
		Target = result.Target,
		PenaltyKills = result.PenaltyKills,
		Gold = result.Gold,
	}
	state.Options = options
	state.Ballot = FlowLogic.tally(votes, options)
	broadcast()

	waitUntil(nil, function()
		if not prunedParty() then
			return true
		end
		return FlowLogic.voteShouldEnd(
			now(),
			resultStarted,
			resultEnds,
			FlowLogic.allVoted(partyIds(), votes),
			RESULT_MIN_SECONDS
		)
	end)
	local choice = Rules.voteWinner(options, FlowLogic.tally(votes, options), default)
	leaveStage()
	if #party == 0 then
		return nil
	end
	local nextId = FlowLogic.resolveResultChoice(choice, StagesConfig.Order, stageId)
	if nextId then
		-- Players who joined during the run come along; everyone stands up again.
		local late: { number } = {}
		for _, p in ipairs(lateJoiners) do
			if p.Parent then
				table.insert(late, p.UserId)
			end
		end
		local ids = FlowLogic.nextParty(partyIds(), late, GameConfig.MaxPlayers)
		local nextPartyList: { Player } = {}
		for _, id in ipairs(ids) do
			local p = Players:GetPlayerByUserId(id)
			if p then
				table.insert(nextPartyList, p)
			end
		end
		party = nextPartyList
		lateJoiners = {}
	end
	return nextId
end

local function runCycle()
	runLobby()
	if #party == 0 then
		return
	end
	local stageId = runVote()
	while stageId do
		stageId = runStage(stageId)
	end
	cleanupStage()
	leaveStage()
end

-- Remotes -------------------------------------------------------------------------
local function onReady(player: Player, on: any)
	if type(on) ~= "boolean" or not Net.throttle(player, "Ready", 0.2) then
		return
	end
	if state.Phase ~= "Lobby" then
		return
	end
	ready[player] = if on then true else nil
	refreshLobbyTimer()
	broadcast()
end

local function onVote(player: Player, option: any)
	if not Net.isString(option, 16) or not Net.throttle(player, "Vote", 0.2) then
		return
	end
	if state.Phase ~= "Vote" and state.Phase ~= "Result" then
		return
	end
	local options = state.Options
	if not options or not table.find(options, option) or not inParty(player) then
		return
	end
	votes[player.UserId] = option
	state.Ballot = FlowLogic.tally(votes, options)
	broadcast()
end

local function onInteract(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.Kind
	if kind == "ReviveStop" then
		local rec = revives[player]
		revives[player] = nil
		if rec and not beingRevived(rec.Target) and rec.Target.Parent then
			rec.Target:SetAttribute("ReviveProgress", 0)
		end
		return
	end
	if kind ~= "ReviveStart" or not Net.throttle(player, "ReviveStart", 0.2) then
		return
	end
	if not Net.isNumber(payload.R) or payload.R ~= state.RoundId or state.Phase ~= "Playing" then
		return
	end
	-- Studio local-server test players have negative UserIds (-1, -2): allow them. (review fix #1)
	if not Net.isNumber(payload.Target, -2 ^ 53, 2 ^ 53) or payload.Target ~= math.floor(payload.Target) then
		return
	end
	local target = Players:GetPlayerByUserId(payload.Target)
	if not target or target == player or not inParty(player) or not inParty(target) then
		return
	end
	local a, b = rootOf(player), rootOf(target)
	if not a or not b then
		return
	end
	local reviverLife: Types.LifeState = if lives[player] then lives[player].Life else "Out"
	local targetLife: Types.LifeState = if lives[target] then lives[target].Life else "Out"
	if not FlowLogic.canRevive(reviverLife, targetLife, (a.Position - b.Position).Magnitude, GameConfig.ReviveRange + 1) then
		return
	end
	local existing = revives[player]
	if existing and existing.Target == target then
		return
	end
	revives[player] = { Target = target, Progress = 0 }
end

-- Players -------------------------------------------------------------------------
local tracked: { [Player]: boolean } = {}

local function onPlayerAdded(player: Player)
	if tracked[player] then
		return
	end
	tracked[player] = true
	if state.Phase == "Lobby" then
		setLife(player, "Alive", GameConfig.MaxHP)
		refreshLobbyTimer()
		broadcast()
	else
		setLife(player, "Spectating", GameConfig.MaxHP)
		if not table.find(lateJoiners, player) then
			table.insert(lateJoiners, player)
		end
		stateEvent:FireClient(player, state)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local wasMember = table.find(party, player)
	ready[player] = nil
	votes[player.UserId] = nil
	revives[player] = nil
	cancelRevivesOn(player)
	personalReds[player] = nil
	lastReload[player] = nil
	local late = table.find(lateJoiners, player)
	if late then
		table.remove(lateJoiners, late)
	end
	if wasMember then
		table.remove(party, wasMember)
	end
	lives[player] = nil
	tracked[player] = nil

	if state.Phase == "Lobby" then
		refreshLobbyTimer()
	elseif wasMember and (state.Phase == "Countdown" or state.Phase == "Playing") then
		local lowered = FlowLogic.targetAfterLeave(Rules, state.Target, stageBase, #party, GameConfig.CoopScale)
		if lowered ~= state.Target then
			state.Target = lowered
			refreshBoard()
		end
		if state.Phase == "Playing" and FlowLogic.isCleared(state.Killed, state.Target) then
			pendingClear = true
		end
	end
	if state.Options and (state.Phase == "Vote" or state.Phase == "Result") then
		state.Ballot = FlowLogic.tally(votes, state.Options)
	end
	broadcast()
end

-- Public API ----------------------------------------------------------------------
function StageFlow.Init(self: Types.StageFlow, c: Types.Context)
	ctx = c
	stateEvent = Net.event(ctx.Remotes, "State")
	feedbackEvent = Net.event(ctx.Remotes, "Feedback")
	serverId = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)
end

function StageFlow.Start(self: Types.StageFlow)
	Net.event(ctx.Remotes, "Ready").OnServerEvent:Connect(onReady)
	Net.event(ctx.Remotes, "Vote").OnServerEvent:Connect(onVote)
	Net.event(ctx.Remotes, "Interact").OnServerEvent:Connect(onInteract)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end

	-- Void guard: anyone who falls far below the world is put back where they belong.
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, p in ipairs(Players:GetPlayers()) do
				local root = rootOf(p)
				if root and root.Position.Y < VOID_Y then
					place(p)
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(runCycle :: any)
			if not ok then
				warn("[FindingRed] match loop error:", err)
				pcall(cleanupStage)
				pcall(leaveStage)
				task.wait(1)
			end
		end
	end)
end

function StageFlow.GetState(self: Types.StageFlow): Types.MatchState
	return state
end

function StageFlow.RoundId(self: Types.StageFlow): number
	return state.RoundId
end

function StageFlow.GetParty(self: Types.StageFlow): { Player }
	local out: { Player } = {}
	for _, p in ipairs(party) do
		if p.Parent then
			table.insert(out, p)
		end
	end
	return out
end

function StageFlow.IsPlaying(self: Types.StageFlow): boolean
	return state.Phase == "Playing"
end

function StageFlow.GetLife(self: Types.StageFlow, player: Player): Types.LifeState
	local rec = lives[player]
	return if rec then rec.Life else "Spectating"
end

function StageFlow.DamagePlayer(self: Types.StageFlow, player: Player, amount: number, sourceKind: string, from: Vector3?)
	if state.Phase ~= "Playing" or not inParty(player) then
		return
	end
	local rec = lives[player]
	if not rec or not Net.isNumber(amount, 0, 1e6) then
		return
	end
	local hp, life, wentDown = FlowLogic.damage(rec.Life, rec.HP, amount)
	if hp == rec.HP and life == rec.Life then
		return
	end
	rec.HP = hp
	player:SetAttribute("HP", hp)
	feedback(player, {
		Kind = "Hurt",
		Amount = amount,
		From = if typeof(from) == "Vector3" then from else nil,
		Source = if type(sourceKind) == "string" then sourceKind else nil,
	})
	if wentDown then
		revives[player] = nil
		setLife(player, "Downed", 0)
	end
end

function StageFlow.HealPlayer(self: Types.StageFlow, player: Player, amount: number)
	local rec = lives[player]
	if not rec or not inParty(player) then
		return
	end
	local hp = FlowLogic.heal(rec.Life, rec.HP, amount, GameConfig.MaxHP)
	if hp ~= rec.HP then
		rec.HP = hp
		player:SetAttribute("HP", hp)
	end
end

function StageFlow.ReportKill(self: Types.StageFlow, kind: string, byPlayer: Player?, cause: Types.KillCause)
	if state.Phase ~= "Countdown" and state.Phase ~= "Playing" then
		return
	end
	if type(kind) ~= "string" then
		return
	end
	local enemyCfg = if type(EnemiesConfig) == "table" then EnemiesConfig[kind] else nil
	local penaltyKind = type(enemyCfg) == "table" and enemyCfg.Penalty == true
	local red, penalty = FlowLogic.killDelta(kind, penaltyKind, byPlayer ~= nil)
	if red == 0 and penalty == 0 then
		return
	end
	state.Killed += red
	state.PenaltyKills += penalty
	if red > 0 and byPlayer then
		personalReds[byPlayer] = (personalReds[byPlayer] or 0) + 1
	end
	if state.Phase == "Playing" and FlowLogic.isCleared(state.Killed, state.Target) then
		pendingClear = true
	end
	broadcast()
end

function StageFlow.GiveTeamKey(self: Types.StageFlow, color: string)
	if type(color) ~= "string" or color == "" then
		return
	end
	local keys = state.Keys or {}
	state.Keys = keys
	if not table.find(keys, color) then
		table.insert(keys, color)
		broadcast()
	end
end

function StageFlow.HasTeamKey(self: Types.StageFlow, color: string): boolean
	local keys = state.Keys
	return keys ~= nil and table.find(keys, color) ~= nil
end

return StageFlow
