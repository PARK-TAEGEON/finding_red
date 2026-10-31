--!strict
-- Pure persistence schema v1 (CONTRACT §3.1 Profile, §2.8). Owner: C.
-- No Roblox globals, no requires: tested by Lune (tests/profile.spec.luau).
-- Ported from the OX Survival Profile module and adapted to the Finding Red schema.
local Profile = {}

export type StageRecord = { Flags: number, BestTime: number? }
export type Profile = {
	Version: number,
	Gold: number,
	Owned: { [string]: boolean },
	Stages: { [string]: StageRecord },
	Stats: { RedKills: number, Clears: number, Plays: number },
	Settings: { Sensitivity: number },
	Results: { string },
	Receipts: { string },
}

Profile.VERSION = 1
Profile.MAX_RESULTS = 20
Profile.MAX_RECEIPTS = 100
Profile.MAX_STAGES = 500
Profile.MAX_OWNED = 200
Profile.MAX_GOLD = 1000000000
Profile.SENS_MIN = 0.2
Profile.SENS_MAX = 3
Profile.SENS_DEFAULT = 1
Profile.FLAG_CLEAR = 1
Profile.FLAG_MASK = 7 -- Clear | Fast | Clean
Profile.MAX_ID_LENGTH = 64

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function integer(value: any, fallback: number, maximum: number?): number
	if not finite(value) then
		return fallback
	end
	return math.clamp(math.floor(value), 0, maximum or Profile.MAX_GOLD)
end

local function validId(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= Profile.MAX_ID_LENGTH
end

-- Keeps the last `limit` valid id strings of `list` (oldest first), without duplicates.
local function tailIds(list: any, limit: number): { string }
	local out: { string } = {}
	if type(list) ~= "table" then
		return out
	end
	local n = #list
	for i = math.max(1, n - limit + 1), n do
		local id = list[i]
		if validId(id) and not table.find(out, id) then
			table.insert(out, id)
		end
	end
	return out
end

local function pushCapped(list: { string }, id: string, limit: number)
	table.insert(list, id)
	while #list > limit do
		table.remove(list, 1)
	end
end

function Profile.clampSensitivity(value: any): number?
	if not finite(value) then
		return nil
	end
	return math.clamp(value, Profile.SENS_MIN, Profile.SENS_MAX)
end

function Profile.new(startGold: number?): Profile
	return {
		Version = Profile.VERSION,
		Gold = integer(startGold, 0),
		Owned = {},
		Stages = {},
		Stats = { RedKills = 0, Clears = 0, Plays = 0 },
		Settings = { Sensitivity = Profile.SENS_DEFAULT },
		Results = {},
		Receipts = {},
	}
end

-- Turns anything (nil, a stored table with junk, an older shape) into a valid v1 profile.
-- Unknown keys (including the DataService session lease `_Session`) are dropped.
function Profile.normalize(raw: any): Profile
	local p = Profile.new(0)
	if type(raw) ~= "table" then
		return p
	end
	p.Gold = integer(raw.Gold, 0)

	if type(raw.Owned) == "table" then
		local count = 0
		for id, owned in pairs(raw.Owned) do
			if count >= Profile.MAX_OWNED then
				break
			end
			if validId(id) and owned == true then
				p.Owned[id] = true
				count += 1
			end
		end
	end

	if type(raw.Stages) == "table" then
		local count = 0
		for id, record in pairs(raw.Stages) do
			if count >= Profile.MAX_STAGES then
				break
			end
			if validId(id) and type(record) == "table" then
				local flags = bit32.band(integer(record.Flags, 0, Profile.FLAG_MASK), Profile.FLAG_MASK)
				local best: number? = nil
				if finite(record.BestTime) and record.BestTime > 0 and record.BestTime < 1e6 then
					best = record.BestTime
				end
				if flags ~= 0 or best ~= nil then
					p.Stages[id] = { Flags = flags, BestTime = best }
					count += 1
				end
			end
		end
	end

	if type(raw.Stats) == "table" then
		p.Stats.RedKills = integer(raw.Stats.RedKills, 0)
		p.Stats.Clears = integer(raw.Stats.Clears, 0)
		p.Stats.Plays = integer(raw.Stats.Plays, 0)
	end

	if type(raw.Settings) == "table" then
		p.Settings.Sensitivity = Profile.clampSensitivity(raw.Settings.Sensitivity) or Profile.SENS_DEFAULT
	end

	p.Results = tailIds(raw.Results, Profile.MAX_RESULTS)
	p.Receipts = tailIds(raw.Receipts, Profile.MAX_RECEIPTS)
	return p
end

-- Deep copy safe to hand to a DataStore (plain tables only).
function Profile.serialize(p: Profile): { [string]: any }
	local stages: { [string]: any } = {}
	for id, record in pairs(p.Stages) do
		stages[id] = { Flags = record.Flags, BestTime = record.BestTime }
	end
	return {
		Version = Profile.VERSION,
		Gold = p.Gold,
		Owned = table.clone(p.Owned),
		Stages = stages,
		Stats = { RedKills = p.Stats.RedKills, Clears = p.Stats.Clears, Plays = p.Stats.Plays },
		Settings = { Sensitivity = p.Settings.Sensitivity },
		Results = table.clone(p.Results),
		Receipts = table.clone(p.Receipts),
	}
end

function Profile.stageFlags(p: Profile): { [string]: number }
	local out: { [string]: number } = {}
	for id, record in pairs(p.Stages) do
		if record.Flags ~= 0 then
			out[id] = record.Flags
		end
	end
	return out
end

function Profile.hasCleared(p: Profile, stageId: string): boolean
	local record = p.Stages[stageId]
	return record ~= nil and bit32.band(record.Flags, Profile.FLAG_CLEAR) ~= 0
end

function Profile.hasResult(p: Profile, resultId: string): boolean
	return table.find(p.Results, resultId) ~= nil
end

-- Applies one stage result at most once (idempotent by resultId).
-- Merges flags (union), updates BestTime when cleared, adds gold / kills / plays / clears.
-- Returns true when the profile changed.
function Profile.applyResult(
	p: Profile,
	resultId: string,
	stageId: string,
	flags: number,
	seconds: number,
	gold: number,
	redKills: number
): boolean
	if not validId(resultId) or not validId(stageId) then
		return false
	end
	if Profile.hasResult(p, resultId) then
		return false
	end
	local runFlags = bit32.band(integer(flags, 0, Profile.FLAG_MASK), Profile.FLAG_MASK)
	local cleared = bit32.band(runFlags, Profile.FLAG_CLEAR) ~= 0

	local record = p.Stages[stageId]
	if not record then
		local count = 0
		for _ in pairs(p.Stages) do
			count += 1
		end
		if count < Profile.MAX_STAGES then
			record = { Flags = 0, BestTime = nil }
			p.Stages[stageId] = record
		end
	end
	if record then
		record.Flags = bit32.bor(record.Flags, runFlags)
		if cleared and finite(seconds) and seconds > 0 and seconds < 1e6 then
			local best = record.BestTime
			if best == nil or seconds < best then
				record.BestTime = seconds
			end
		end
	end

	p.Gold = math.min(Profile.MAX_GOLD, p.Gold + integer(gold, 0))
	p.Stats.RedKills = math.min(Profile.MAX_GOLD, p.Stats.RedKills + integer(redKills, 0, 100000))
	p.Stats.Plays += 1
	if cleared then
		p.Stats.Clears += 1
	end
	pushCapped(p.Results, resultId, Profile.MAX_RESULTS)
	return true
end

-- Developer-product receipts are granted at most once. Kept separate from Results so
-- purchases can never evict stage-result ids (and the reverse).
function Profile.claimReceipt(p: Profile, purchaseId: string): boolean
	if not validId(purchaseId) then
		return false
	end
	if table.find(p.Receipts, purchaseId) then
		return false
	end
	pushCapped(p.Receipts, purchaseId, Profile.MAX_RECEIPTS)
	return true
end

-- Returns true when the stored value changed.
function Profile.setSensitivity(p: Profile, value: any): boolean
	local v = Profile.clampSensitivity(value)
	if v == nil or v == p.Settings.Sensitivity then
		return false
	end
	p.Settings.Sensitivity = v
	return true
end

-- Weapon ownership. Defaults (Config.Weapons.Default) are implied and never stored.
function Profile.owns(p: Profile, weaponId: string, defaults: { string }): boolean
	return p.Owned[weaponId] == true or table.find(defaults, weaponId) ~= nil
end

function Profile.grant(p: Profile, weaponId: string): boolean
	if not validId(weaponId) or p.Owned[weaponId] then
		return false
	end
	p.Owned[weaponId] = true
	return true
end

-- Returns true when the purchase went through.
function Profile.spend(p: Profile, amount: number): boolean
	if not finite(amount) or amount < 0 then
		return false
	end
	local cost = math.ceil(amount)
	if p.Gold < cost then
		return false
	end
	p.Gold -= cost
	return true
end

return Profile
