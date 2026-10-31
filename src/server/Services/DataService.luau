--!strict
-- Player profiles (CONTRACT §2.8, §3.4 DataService). Owner: C.
-- Port of the OX Survival DataService: session lease via UpdateAsync, load retry + kick,
-- autosave loop, lease-expiry kick, BindToClose release. Studio uses memory unless
-- Config.Game.StudioUseDataStore is true (then StudioDataStoreName).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Rules = require(Shared.Rules)
local GameConfig = require(Shared.Config.Game)
local StagesConfig = require(Shared.Config.Stages)
local Profile = require(script.Parent.Profile)

type Record = {
	Profile: Profile.Profile,
	Token: string,
	Valid: boolean,
	Saving: boolean,
	Releasing: boolean,
	ReleaseStarted: boolean,
	LastSaved: number,
	Revision: number,
}

local DataService = {}

local ctx: Types.Context
local records: { [Player]: Record } = {}
local loading: { [Player]: boolean } = {}
local closing = false
local isStudio = RunService:IsStudio()
local memory = isStudio and not GameConfig.StudioUseDataStore
local store: DataStore? = nil

local LOAD_ATTEMPTS = 4
local SAVE_ATTEMPTS = 3

local function key(player: Player): string
	return "u_" .. tostring(player.UserId)
end

local function setStatus(player: Player, text: string)
	if player.Parent then
		player:SetAttribute("SaveStatus", text)
	end
end

local function getValid(player: Player): Record?
	local r = records[player]
	if r and r.Valid and not r.Releasing then
		return r
	end
	return nil
end

local function sync(player: Player)
	local r = getValid(player)
	if not r or not player.Parent then
		return
	end
	local p = r.Profile
	player:SetAttribute("Gold", p.Gold)
	player:SetAttribute("StageFlags", HttpService:JSONEncode(Profile.stageFlags(p)))
	player:SetAttribute("Sensitivity", p.Settings.Sensitivity)
end

local function markDirty(player: Player, r: Record)
	r.Revision += 1
	if not memory then
		setStatus(player, "저장 대기")
	end
	sync(player)
end

-- Load ----------------------------------------------------------------------------
local function load(self: Types.DataService, player: Player): boolean
	if records[player] or loading[player] then
		return false
	end
	loading[player] = true
	local token = HttpService:GenerateGUID(false)
	local loaded: Profile.Profile? = nil
	local lastError = "session locked"
	if memory then
		loaded = Profile.new(GameConfig.StudioStartGold)
	elseif store then
		local ds = store
		for attempt = 1, LOAD_ATTEMPTS do
			local ok, value = pcall(function()
				return ds:UpdateAsync(key(player), function(raw: any, _info: DataStoreKeyInfo): (any, { number }?, {}?)
					if type(raw) == "table" and type(raw._Session) == "table" then
						local session = raw._Session
						local fresh = (tonumber(session.Time) or 0) > os.time() - GameConfig.SessionLeaseSeconds
						if session.Token ~= token and fresh then
							return nil -- another server still holds the lease
						end
					end
					local stored: { [string]: any } = Profile.serialize(Profile.normalize(raw))
					stored._Session = { Token = token, Time = os.time() }
					return stored, { player.UserId }
				end)
			end)
			if ok and type(value) == "table" and type(value._Session) == "table" and value._Session.Token == token then
				loaded = Profile.normalize(value)
				break
			end
			lastError = if ok then "다른 서버의 저장이 끝나지 않았습니다" else tostring(value)
			if attempt < LOAD_ATTEMPTS then
				task.wait(attempt * 2)
			end
			if not player.Parent then
				break
			end
		end
	else
		lastError = "DataStore unavailable"
	end
	loading[player] = nil

	if not loaded then
		warn("[FindingRed] profile load refused:", player.UserId, lastError)
		if player.Parent then
			player:Kick("저장 데이터를 안전하게 불러오지 못했습니다. 잠시 후 다시 접속해 주세요.")
		end
		return false
	end
	records[player] = {
		Profile = loaded,
		Token = token,
		Valid = true,
		Saving = false,
		Releasing = false,
		ReleaseStarted = false,
		LastSaved = os.clock(),
		Revision = 0,
	}
	setStatus(player, if memory then "Studio 테스트 · 저장 안 됨" else "저장 완료")
	if not player.Parent or closing then
		task.spawn(function()
			self:Save(player, true)
			records[player] = nil
		end)
		return false
	end
	sync(player)
	player:SetAttribute("DataReady", true)
	return true
end

local function release(self: Types.DataService, player: Player)
	local r = records[player]
	if not r or r.ReleaseStarted then
		return
	end
	r.ReleaseStarted = true
	self:Save(player, true)
	r.Valid = false
	if records[player] == r then
		records[player] = nil
	end
end

-- Public API ----------------------------------------------------------------------
function DataService.Init(self: Types.DataService, c: Types.Context)
	ctx = c
	if not memory then
		local name = if isStudio then GameConfig.StudioDataStoreName else GameConfig.DataStoreName
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(name)
		end)
		if ok then
			store = result
		else
			warn("[FindingRed] DataStore unavailable:", result)
			if isStudio then
				warn("[FindingRed] Studio falls back to memory profiles (enable API access to test saving)")
				memory = true
			end
		end
	end
end

function DataService.Start(self: Types.DataService)
	Players.PlayerAdded:Connect(function(player)
		load(self, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		release(self, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(load, self, player)
	end

	local setting = Net.event(ctx.Remotes, "Setting")
	setting.OnServerEvent:Connect(function(player: Player, settingKey: any, value: any)
		if not Net.throttle(player, "Setting", 0.25) then
			return
		end
		if settingKey == "Sensitivity" and Net.isNumber(value, Profile.SENS_MIN, Profile.SENS_MAX) then
			self:Mutate(player, function(p)
				return Profile.setSensitivity(p, value)
			end)
		end
	end)

	-- Autosave + lease guard.
	task.spawn(function()
		while not closing do
			task.wait(5)
			for player, r in pairs(records) do
				local elapsed = os.clock() - r.LastSaved
				if not memory and r.Valid and not r.Releasing and elapsed > GameConfig.SessionLeaseSeconds - 30 then
					-- Stop gameplay before another server can take this lease.
					if player.Parent then
						player:Kick("저장 연결이 오래 끊겼습니다. 데이터 보호를 위해 다시 접속해 주세요.")
					end
				elseif elapsed > GameConfig.AutoSaveSeconds and not r.Saving and not r.Releasing then
					task.spawn(function()
						self:Save(player, false)
					end)
				end
			end
		end
	end)

	game:BindToClose(function()
		closing = true
		local pending = 0
		for player in pairs(records) do
			pending += 1
			task.spawn(function()
				release(self, player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

function DataService.Get(self: Types.DataService, player: Player): Types.Profile?
	local r = getValid(player)
	return if r then r.Profile else nil
end

-- Server-validated change. fn returns true when it changed the profile.
function DataService.Mutate(self: Types.DataService, player: Player, fn: (Types.Profile) -> boolean): boolean
	local r = getValid(player)
	if not r then
		return false
	end
	local ok, changed = pcall(fn, r.Profile)
	if not ok then
		warn("[FindingRed] profile mutate failed:", changed)
		return false
	end
	if not changed then
		return false
	end
	markDirty(player, r)
	return true
end

function DataService.Save(self: Types.DataService, player: Player, releaseLease: boolean): boolean
	local r = records[player]
	if not r or not r.Valid then
		return false
	end
	if r.Releasing and not releaseLease then
		return false
	end
	if releaseLease then
		r.Releasing = true
	end
	while r.Saving do
		task.wait(0.1)
	end
	if records[player] ~= r or not r.Valid then
		return false
	end
	if r.Releasing and not releaseLease then
		return false
	end
	r.Saving = true
	if memory or not store then
		r.Saving = false
		r.LastSaved = os.clock()
		return memory
	end
	local ds = store :: DataStore
	local revision = r.Revision
	local snapshot = Profile.serialize(r.Profile)
	local saved = false
	for attempt = 1, SAVE_ATTEMPTS do
		local lost = false
		local ok, value = pcall(function()
			return ds:UpdateAsync(key(player), function(raw: any, _info: DataStoreKeyInfo): (any, { number }?, {}?)
				lost = false
				if type(raw) ~= "table" or type(raw._Session) ~= "table" or raw._Session.Token ~= r.Token then
					lost = true
					return nil
				end
				local nextValue: { [string]: any } = table.clone(snapshot)
				if not releaseLease then
					nextValue._Session = { Token = r.Token, Time = os.time() }
				end
				return nextValue, { player.UserId }
			end)
		end)
		if ok and value ~= nil and not lost then
			saved = true
			break
		end
		if lost then
			r.Valid = false
			if player.Parent then
				player:Kick("다른 서버에서 저장 세션이 열렸습니다. 다시 접속해 주세요.")
			end
			break
		end
		warn("[FindingRed] save retry:", player.UserId, attempt, value)
		if attempt < SAVE_ATTEMPTS then
			task.wait(attempt)
		end
	end
	r.Saving = false
	if saved then
		r.LastSaved = os.clock()
	end
	setStatus(player, if saved then (if r.Revision == revision then "저장 완료" else "저장 대기") else "저장 재시도 중")
	return saved
end

-- Idempotent by resultId: merges flags, BestTime on clear, gold/kills/plays/clears. Saves async.
function DataService.ApplyResult(
	self: Types.DataService,
	player: Player,
	resultId: string,
	stageId: string,
	flags: number,
	seconds: number,
	gold: number,
	redKills: number
): boolean
	local r = getValid(player)
	if not r then
		return false
	end
	if not Profile.applyResult(r.Profile, resultId, stageId, flags, seconds, gold, redKills) then
		return false
	end
	markDirty(player, r)
	task.spawn(function()
		self:Save(player, false)
	end)
	return true
end

function DataService.UnlockedStages(self: Types.DataService, player: Player): { string }
	local r = getValid(player)
	local flags = if r then Profile.stageFlags(r.Profile) else {}
	local out: { string } = {}
	for _, stageId in ipairs(StagesConfig.Order) do
		if Rules.isUnlocked(StagesConfig.Order, flags, stageId) then
			table.insert(out, stageId)
		end
	end
	return out
end

return DataService
