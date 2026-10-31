--!strict
-- Pure match-flow decisions for StageFlow (CONTRACT §1.1–1.5, §1.7). Owner: C.
-- No Roblox globals, no requires. Functions that need the shared Rules take it as an argument,
-- so Lune can test this module with the real Rules (tests/flow.spec.luau).
local FlowLogic = {}

export type LifeState = "Alive" | "Downed" | "Out" | "Spectating"
export type Phase = "Lobby" | "Vote" | "Countdown" | "Playing" | "Result"
export type Reward = { Base: number, PerStamp: number, FirstClear: number }

export type RulesApi = {
	target: (base: number, players: number, coopScale: number) -> number,
	lowerTarget: (current: number, base: number, remaining: number, coopScale: number) -> number,
	flags: (cleared: boolean, seconds: number, parTime: number, penaltyKills: number) -> number,
	clearReward: (reward: Reward, runFlags: number, firstClear: boolean) -> number,
	failReward: (perRed: number, killed: number) -> number,
	partyUnlocked: (order: { string }, members: { { [string]: number } }) -> { string },
	mergeFlags: (old: number, new: number) -> number,
}

local FLAG_CLEAR = 1

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Lobby ---------------------------------------------------------------------------
-- Everyone present is ready -> start now. At least one ready for `timeout` seconds -> start.
function FlowLogic.lobbyShouldStart(
	present: number,
	readyCount: number,
	firstReadyAt: number?,
	now: number,
	timeout: number
): boolean
	if present <= 0 or readyCount <= 0 then
		return false
	end
	if readyCount >= present then
		return true
	end
	return firstReadyAt ~= nil and now - firstReadyAt >= timeout
end

-- Votes ---------------------------------------------------------------------------
-- votes: voter userId -> option. Votes for options not offered are ignored.
function FlowLogic.tally(votes: { [number]: string }, options: { string }): { [string]: number }
	local ballot: { [string]: number } = {}
	for _, option in ipairs(options) do
		ballot[option] = 0
	end
	for _, option in pairs(votes) do
		if ballot[option] ~= nil then
			ballot[option] += 1
		end
	end
	return ballot
end

function FlowLogic.allVoted(voters: { number }, votes: { [number]: string }): boolean
	if #voters == 0 then
		return false
	end
	for _, userId in ipairs(voters) do
		if votes[userId] == nil then
			return false
		end
	end
	return true
end

-- A vote ends at its deadline, or early once every voter voted and `minSeconds` passed.
function FlowLogic.voteShouldEnd(now: number, startedAt: number, endsAt: number, everyoneVoted: boolean, minSeconds: number): boolean
	if now >= endsAt then
		return true
	end
	return everyoneVoted and now - startedAt >= minSeconds
end

-- Life ----------------------------------------------------------------------------
-- Returns new HP, new life state and whether the player just went down.
function FlowLogic.damage(life: LifeState, hp: number, amount: number): (number, LifeState, boolean)
	if life ~= "Alive" or not finite(amount) or amount <= 0 then
		return hp, life, false
	end
	local nextHp = math.max(0, hp - amount)
	if nextHp <= 0 then
		return 0, "Downed", true
	end
	return nextHp, "Alive", false
end

function FlowLogic.heal(life: LifeState, hp: number, amount: number, maxHP: number): number
	if life ~= "Alive" or not finite(amount) or amount <= 0 then
		return hp
	end
	return math.clamp(hp + amount, 0, maxHP)
end

-- Bleed-out pauses while someone is actively reviving the player.
function FlowLogic.shouldBleedOut(life: LifeState, downedAt: number?, now: number, bleedSeconds: number, beingRevived: boolean): boolean
	if life ~= "Downed" or downedAt == nil or beingRevived then
		return false
	end
	return now - downedAt >= bleedSeconds
end

function FlowLogic.canRevive(reviverLife: LifeState, targetLife: LifeState, distance: number, range: number): boolean
	return reviverLife == "Alive" and targetLife == "Downed" and finite(distance) and distance <= range
end

-- Advances a revive hold. Returns progress in 0..1 and whether it completed.
function FlowLogic.reviveStep(progress: number, dt: number, holdSeconds: number): (number, boolean)
	if holdSeconds <= 0 then
		return 1, true
	end
	local nextProgress = math.clamp(progress + math.max(0, dt) / holdSeconds, 0, 1)
	return nextProgress, nextProgress >= 1
end

function FlowLogic.walkSpeed(life: LifeState, walk: number, downed: number): number
	if life == "Downed" then
		return downed
	end
	return walk
end

-- Win / lose --------------------------------------------------------------------
-- Everyone in the party is Downed or Out (an empty party is not "all down").
function FlowLogic.allDown(lives: { LifeState }): boolean
	if #lives == 0 then
		return false
	end
	for _, life in ipairs(lives) do
		if life == "Alive" then
			return false
		end
	end
	return true
end

-- Tracks when "all down" started. Returns the new allDownSince.
function FlowLogic.trackAllDown(isAllDown: boolean, allDownSince: number?, now: number): number?
	if not isAllDown then
		return nil
	end
	return allDownSince or now
end

-- "AllDown" after the grace period, "Time" after the limit, otherwise nil.
function FlowLogic.failReason(allDownSince: number?, now: number, grace: number, startedAt: number, limit: number): string?
	if allDownSince ~= nil and now - allDownSince >= grace then
		return "AllDown"
	end
	if now - startedAt > limit then
		return "Time"
	end
	return nil
end

function FlowLogic.isCleared(killed: number, target: number): boolean
	return target > 0 and killed >= target
end

-- Red always counts for the team; penalty kinds count only when a player owns the kill.
function FlowLogic.killDelta(kind: string, penaltyKind: boolean, byPlayer: boolean): (number, number)
	local red = if kind == "Red" then 1 else 0
	local penalty = if kind ~= "Red" and penaltyKind and byPlayer then 1 else 0
	return red, penalty
end

-- Target after someone leaves: recomputed for the remaining players, never raised.
function FlowLogic.targetAfterLeave(rules: RulesApi, current: number, base: number, remaining: number, coopScale: number): number
	if remaining <= 0 then
		return current
	end
	return rules.lowerTarget(current, base, remaining, coopScale)
end

-- Result ---------------------------------------------------------------------------
export type ResultMember = { UserId: number, PrevFlags: number, RedKills: number }
export type ResultInput = {
	StageId: string,
	Cleared: boolean,
	Seconds: number,
	ParTime: number,
	Killed: number,
	Target: number,
	PenaltyKills: number,
	Reward: Reward,
	PerRedOnFail: number,
	Members: { ResultMember },
}
export type MemberResult = { UserId: number, Gold: number, FirstClear: boolean, FlagsAfter: number }
export type ResultOutput = {
	StageId: string,
	Cleared: boolean,
	Flags: number,
	NewFlags: number,
	Seconds: number,
	Killed: number,
	Target: number,
	PenaltyKills: number,
	Gold: { [string]: number },
	Members: { MemberResult },
}

-- NewFlags = bits of this run that at least one member did not have before.
function FlowLogic.buildResult(rules: RulesApi, input: ResultInput): ResultOutput
	local seconds = math.max(0, input.Seconds)
	local runFlags = rules.flags(input.Cleared, seconds, input.ParTime, input.PenaltyKills)
	local newFlags = 0
	local gold: { [string]: number } = {}
	local members: { MemberResult } = {}
	for _, m in ipairs(input.Members) do
		local prev = m.PrevFlags
		local firstClear = input.Cleared and bit32.band(prev, FLAG_CLEAR) == 0
		local amount
		if input.Cleared then
			amount = rules.clearReward(input.Reward, runFlags, firstClear)
		else
			amount = rules.failReward(input.PerRedOnFail, input.Killed)
		end
		newFlags = bit32.bor(newFlags, bit32.band(runFlags, bit32.bnot(prev)))
		gold[tostring(m.UserId)] = amount
		table.insert(members, {
			UserId = m.UserId,
			Gold = amount,
			FirstClear = firstClear,
			FlagsAfter = rules.mergeFlags(prev, runFlags),
		})
	end
	return {
		StageId = input.StageId,
		Cleared = input.Cleared,
		Flags = runFlags,
		NewFlags = bit32.band(newFlags, 7),
		Seconds = math.floor(seconds * 10 + 0.5) / 10,
		Killed = input.Killed,
		Target = input.Target,
		PenaltyKills = input.PenaltyKills,
		Gold = gold,
		Members = members,
	}
end

function FlowLogic.resultId(serverId: string, roundId: number, userId: number): string
	return string.format("%s:%d:%d", string.sub(serverId, 1, 36), roundId, userId)
end

-- Options after a result: Next (next stage exists and is unlocked for the party after
-- this run), Retry, Lobby. Default = Next when offered, Retry after a fail, else Lobby.
function FlowLogic.resultOptions(
	rules: RulesApi,
	order: { string },
	stageId: string,
	cleared: boolean,
	partyFlagsAfter: { { [string]: number } }
): ({ string }, string)
	local options: { string } = {}
	local index = table.find(order, stageId)
	local nextId = if index then order[index + 1] else nil
	if nextId then
		local unlocked = rules.partyUnlocked(order, partyFlagsAfter)
		if table.find(unlocked, nextId) then
			table.insert(options, "Next")
		end
	end
	table.insert(options, "Retry")
	table.insert(options, "Lobby")
	local default = if options[1] == "Next" then "Next" elseif not cleared then "Retry" else "Lobby"
	return options, default
end

-- Maps a result-vote winner to what happens next: a stage id, or nil = back to the lobby.
function FlowLogic.resolveResultChoice(choice: string, order: { string }, stageId: string): string?
	if choice == "Retry" then
		return stageId
	end
	if choice == "Next" then
		local index = table.find(order, stageId)
		return if index then order[index + 1] else nil
	end
	return nil
end

-- Next run's party: the current party plus players who joined while a stage ran (capped).
function FlowLogic.nextParty(current: { number }, late: { number }, maxPlayers: number): { number }
	local out: { number } = {}
	for _, list in ipairs({ current, late }) do
		for _, userId in ipairs(list) do
			if #out >= maxPlayers then
				return out
			end
			if not table.find(out, userId) then
				table.insert(out, userId)
			end
		end
	end
	return out
end

-- Where a (re)spawned character belongs.
function FlowLogic.placement(phase: Phase, inParty: boolean, life: LifeState, stageLoaded: boolean): "Stage" | "Lobby"
	if not inParty or not stageLoaded then
		return "Lobby"
	end
	if phase == "Countdown" then
		return "Stage"
	end
	if (phase == "Playing" or phase == "Result") and (life == "Alive" or life == "Downed") then
		return "Stage"
	end
	return "Lobby"
end

-- Round-robin spawn slot (1-based).
function FlowLogic.spawnSlot(index: number, count: number): number
	if count <= 0 then
		return 0
	end
	return ((math.max(1, index) - 1) % count) + 1
end

return FlowLogic
