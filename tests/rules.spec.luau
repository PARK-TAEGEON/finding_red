-- Lune test for src/shared/Rules.luau. Owner: orchestrator.
local Rules = require("../src/shared/Rules")

local checks = 0
local function check(cond: boolean, label: string)
	checks += 1
	assert(cond, label)
end

-- Target scaling (CONTRACT §1.2)
check(Rules.target(1, 1, 0.5) == 1, "base 1 solo")
check(Rules.target(1, 2, 0.5) == 2, "base 1 duo")
check(Rules.target(1, 4, 0.5) == 3, "base 1 four")
check(Rules.target(5, 4, 0.5) == 13, "base 5 four")
check(Rules.target(3, 3, 0.5) == 6, "base 3 three")
check(Rules.target(2, 0, 0.5) == 2, "zero players clamps to one")
check(Rules.lowerTarget(13, 5, 2, 0.5) == 8, "leave lowers target")
check(Rules.lowerTarget(3, 5, 4, 0.5) == 3, "target never rises")

-- Flags and stamps (CONTRACT §1.3)
check(Rules.flags(false, 10, 40, 0) == 0, "fail = 0")
check(Rules.flags(true, 50, 40, 1) == 1, "clear only")
check(Rules.flags(true, 40, 40, 1) == 3, "clear + fast at exactly par")
check(Rules.flags(true, 90, 40, 0) == 5, "clear + clean")
check(Rules.flags(true, 10, 40, 0) == 7, "all three")
check(Rules.mergeFlags(3, 5) == 7, "merge is union")
check(Rules.stampCount(0) == 0 and Rules.stampCount(5) == 2 and Rules.stampCount(7) == 3, "stamp count")

-- Rewards
local reward = { Base = 20, PerStamp = 10, FirstClear = 30 }
check(Rules.clearReward(reward, 7, true) == 80, "first clear all stamps")
check(Rules.clearReward(reward, 1, false) == 30, "replay one stamp")
check(Rules.clearReward(reward, 0, true) == 0, "no clear no gold")
check(Rules.failReward(2, 3) == 6, "fail reward")

-- Unlocks (CONTRACT D5)
local order = { "1-1", "1-2", "1-3" }
check(Rules.isUnlocked(order, {}, "1-1"), "first always unlocked")
check(not Rules.isUnlocked(order, {}, "1-2"), "second locked")
check(Rules.isUnlocked(order, { ["1-1"] = 1 }, "1-2"), "clear unlocks next")
check(not Rules.isUnlocked(order, { ["1-1"] = 2 }, "1-2"), "fast bit alone is not a clear")
check(not Rules.isUnlocked(order, {}, "9-9"), "unknown stage locked")
local party = Rules.partyUnlocked(order, { {}, { ["1-1"] = 7, ["1-2"] = 1 } })
check(#party == 3, "party union unlocks via any member")
check(#Rules.partyUnlocked(order, {}) == 1, "empty party still has first stage")

-- Votes
check(Rules.voteWinner({ "1-1", "1-2" }, { ["1-2"] = 2, ["1-1"] = 1 }, "1-1") == "1-2", "most votes")
check(Rules.voteWinner({ "1-1", "1-2" }, { ["1-2"] = 1, ["1-1"] = 1 }, "1-2") == "1-1", "tie -> earliest")
check(Rules.voteWinner({ "1-1", "1-2" }, {}, "1-2") == "1-2", "no votes -> fallback")

-- Distribution
local d = Rules.distribute(5, { 1, 1, 1 })
check(d[1] + d[2] + d[3] == 5, "distribute total")
check(d[1] == 2 and d[2] == 2 and d[3] == 1, "largest remainder, earliest first")
local z = Rules.distribute(3, { 0, 0 })
check(z[1] == 3 and z[2] == 0, "zero weights -> all to first")
check(Rules.redSpawnCount(3, 1) == 4, "spawn count")

print(("rules.spec: %d checks passed"):format(checks))
