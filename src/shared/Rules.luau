--!strict
-- Pure game rules (CONTRACT §1.2, §1.3, §1.7). No Roblox globals, no requires. Owner: orchestrator.
local Rules = {}

Rules.FLAG_CLEAR = 1
Rules.FLAG_FAST = 2
Rules.FLAG_CLEAN = 4

-- Target = ceil(base * (1 + coopScale * (players - 1)))
function Rules.target(base: number, players: number, coopScale: number): number
	local n = math.max(1, math.floor(players))
	return math.max(1, math.ceil(base * (1 + coopScale * (n - 1)) - 1e-9))
end

-- When someone leaves the target may only go down.
function Rules.lowerTarget(current: number, base: number, remaining: number, coopScale: number): number
	return math.min(current, Rules.target(base, remaining, coopScale))
end

function Rules.redSpawnCount(target: number, spare: number): number
	return target + math.max(0, spare)
end

function Rules.timeLimit(parTime: number, multiplier: number): number
	return parTime * multiplier
end

-- Flags earned by one run.
function Rules.flags(cleared: boolean, seconds: number, parTime: number, penaltyKills: number): number
	if not cleared then
		return 0
	end
	local f = Rules.FLAG_CLEAR
	if seconds <= parTime then
		f += Rules.FLAG_FAST
	end
	if penaltyKills == 0 then
		f += Rules.FLAG_CLEAN
	end
	return f
end

function Rules.mergeFlags(old: number, new: number): number
	return bit32.bor(old, new)
end

function Rules.stampCount(flags: number): number
	local n = 0
	for _, bit in ipairs({ Rules.FLAG_CLEAR, Rules.FLAG_FAST, Rules.FLAG_CLEAN }) do
		if bit32.band(flags, bit) ~= 0 then
			n += 1
		end
	end
	return n
end

export type StageReward = { Base: number, PerStamp: number, FirstClear: number }

function Rules.clearReward(reward: StageReward, runFlags: number, firstClear: boolean): number
	if bit32.band(runFlags, Rules.FLAG_CLEAR) == 0 then
		return 0
	end
	local gold = reward.Base + reward.PerStamp * Rules.stampCount(runFlags)
	if firstClear then
		gold += reward.FirstClear
	end
	return gold
end

function Rules.failReward(perRed: number, killed: number): number
	return math.max(0, perRed * killed)
end

-- A stage is unlocked when it is first in order or the previous one was cleared.
function Rules.isUnlocked(order: { string }, flagsByStage: { [string]: number }, stageId: string): boolean
	local index = table.find(order, stageId)
	if not index then
		return false
	end
	if index == 1 then
		return true
	end
	local prev = flagsByStage[order[index - 1]] or 0
	return bit32.band(prev, Rules.FLAG_CLEAR) ~= 0
end

-- Party unlock = union over members (CONTRACT D5).
function Rules.partyUnlocked(order: { string }, members: { { [string]: number } }): { string }
	local out = {}
	for _, stageId in ipairs(order) do
		for _, flags in ipairs(members) do
			if Rules.isUnlocked(order, flags, stageId) then
				table.insert(out, stageId)
				break
			end
		end
	end
	if #out == 0 and #order > 0 then
		table.insert(out, order[1])
	end
	return out
end

-- Most votes wins; ties go to the earliest option; no votes -> fallback.
function Rules.voteWinner(options: { string }, ballot: { [string]: number }, fallback: string): string
	local best, bestVotes = fallback, 0
	for _, option in ipairs(options) do
		local votes = ballot[option] or 0
		if votes > bestVotes then
			best, bestVotes = option, votes
		end
	end
	return best
end

-- Split `total` across weights (largest remainder). Returns counts in the same order.
function Rules.distribute(total: number, weights: { number }): { number }
	local sum = 0
	for _, w in ipairs(weights) do
		sum += math.max(0, w)
	end
	local counts, remainders = {}, {}
	if sum <= 0 then
		for i = 1, #weights do
			counts[i] = 0
		end
		if #weights > 0 then
			counts[1] = total
		end
		return counts
	end
	local used = 0
	for i, w in ipairs(weights) do
		local exact = total * math.max(0, w) / sum
		counts[i] = math.floor(exact)
		used += counts[i]
		table.insert(remainders, { Index = i, Rem = exact - counts[i] })
	end
	table.sort(remainders, function(a, b)
		if a.Rem == b.Rem then
			return a.Index < b.Index
		end
		return a.Rem > b.Rem
	end)
	for k = 1, total - used do
		local r = remainders[((k - 1) % #remainders) + 1]
		counts[r.Index] += 1
	end
	return counts
end

return Rules
