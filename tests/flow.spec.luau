-- Lune test for src/server/Services/Flow/FlowLogic.luau. Owner: C.
local Rules = require("../src/shared/Rules")
local Flow = require("../src/server/Services/Flow/FlowLogic")
local Stages = require("../src/shared/Config/Stages")

local checks = 0
local function check(cond: boolean, label: string)
	checks += 1
	assert(cond, label)
end

-- Lobby: all ready -> now; one ready + 20 s -> start; nobody ready -> never
check(not Flow.lobbyShouldStart(0, 0, nil, 100, 20), "empty server waits")
check(not Flow.lobbyShouldStart(2, 0, nil, 100, 20), "nobody ready waits")
check(Flow.lobbyShouldStart(1, 1, 100, 100, 20), "solo ready starts now")
check(Flow.lobbyShouldStart(3, 3, 100, 100, 20), "all ready starts now")
check(not Flow.lobbyShouldStart(3, 1, 100, 119.9, 20), "partial ready waits for timeout")
check(Flow.lobbyShouldStart(3, 1, 100, 120, 20), "partial ready + 20 s starts")
check(not Flow.lobbyShouldStart(3, 1, nil, 999, 20), "no ready timestamp waits")

-- Votes
local ballot = Flow.tally({ [1] = "1-1", [2] = "1-2", [3] = "1-2", [4] = "9-9" }, { "1-1", "1-2" })
check(ballot["1-1"] == 1 and ballot["1-2"] == 2 and ballot["9-9"] == nil, "tally ignores unknown options")
check(Flow.tally({}, { "Next" }).Next == 0, "options start at zero")
check(Flow.allVoted({ 1, 2 }, { [1] = "a", [2] = "b" }), "all voted")
check(not Flow.allVoted({ 1, 2 }, { [1] = "a" }), "missing vote")
check(not Flow.allVoted({}, {}), "no voters is not all voted")
check(Flow.voteShouldEnd(10, 0, 10, false, 3), "deadline")
check(not Flow.voteShouldEnd(2, 0, 10, true, 3), "too early even if all voted")
check(Flow.voteShouldEnd(3, 0, 10, true, 3), "early end when all voted")
check(not Flow.voteShouldEnd(5, 0, 10, false, 3), "waits for votes")
local options = Rules.partyUnlocked(Stages.Order, { {}, { ["1-1"] = 1 } })
check(Rules.voteWinner(options, Flow.tally({}, options), options[#options]) == "1-2", "no votes -> highest unlocked")

-- Life transitions
local hp, life, downed = Flow.damage("Alive", 100, 30)
check(hp == 70 and life == "Alive" and not downed, "damage")
hp, life, downed = Flow.damage("Alive", 20, 25)
check(hp == 0 and life == "Downed" and downed, "damage to zero downs")
hp, life, downed = Flow.damage("Downed", 0, 25)
check(hp == 0 and life == "Downed" and not downed, "no damage while downed")
hp, life = Flow.damage("Out", 0, 25)
check(life == "Out", "out stays out")
hp, life = Flow.damage("Spectating", 100, 25)
check(hp == 100 and life == "Spectating", "spectators immune")
hp = Flow.damage("Alive", 100, 0/0)
check(hp == 100, "NaN damage ignored")
hp = Flow.damage("Alive", 100, -10)
check(hp == 100, "negative damage ignored")
hp = Flow.damage("Alive", 100, math.huge)
check(hp == 100, "infinite damage ignored")
check(Flow.heal("Alive", 90, 50, 100) == 100, "heal clamps")
check(Flow.heal("Downed", 0, 50, 100) == 0, "no heal while downed")
check(Flow.heal("Alive", 40, -5, 100) == 40, "negative heal ignored")

check(not Flow.shouldBleedOut("Downed", 0, 29.9, 30, false), "still bleeding")
check(Flow.shouldBleedOut("Downed", 0, 30, 30, false), "bled out")
check(not Flow.shouldBleedOut("Downed", 0, 40, 30, true), "revive pauses bleed out")
check(not Flow.shouldBleedOut("Alive", 0, 40, 30, false), "alive never bleeds out")

check(Flow.canRevive("Alive", "Downed", 5.9, 6), "revive in range")
check(not Flow.canRevive("Alive", "Downed", 6.1, 6), "revive out of range")
check(not Flow.canRevive("Downed", "Downed", 1, 6), "downed cannot revive")
check(not Flow.canRevive("Alive", "Out", 1, 6), "out cannot be revived")
check(not Flow.canRevive("Alive", "Downed", 0/0, 6), "NaN distance")
local progress, done = Flow.reviveStep(0, 1, 3)
check(math.abs(progress - 1 / 3) < 1e-9 and not done, "revive step")
progress, done = Flow.reviveStep(progress, 2.1, 3)
check(progress == 1 and done, "revive completes")
progress = Flow.reviveStep(0.5, -1, 3)
check(progress == 0.5, "negative dt ignored")
check(Flow.walkSpeed("Downed", 16, 4) == 4 and Flow.walkSpeed("Alive", 16, 4) == 16, "walk speed")

-- All down / fail
check(not Flow.allDown({}), "empty party is not all down")
check(Flow.allDown({ "Downed", "Out" }), "all down")
check(not Flow.allDown({ "Downed", "Alive" }), "one alive")
check(Flow.trackAllDown(true, nil, 5) == 5, "all-down starts")
check(Flow.trackAllDown(true, 5, 9) == 5, "all-down keeps start")
check(Flow.trackAllDown(false, 5, 9) == nil, "revive resets all-down")
check(Flow.failReason(nil, 50, 10, 0, 120) == nil, "no fail")
check(Flow.failReason(40, 49.9, 10, 0, 120) == nil, "grace running")
check(Flow.failReason(40, 50, 10, 0, 120) == "AllDown", "grace over")
check(Flow.failReason(nil, 120, 10, 0, 120) == nil, "exactly at limit still playing")
check(Flow.failReason(nil, 120.1, 10, 0, 120) == "Time", "time limit")

-- Kills
local red, pen = Flow.killDelta("Red", false, false)
check(red == 1 and pen == 0, "red by trap counts")
red, pen = Flow.killDelta("Red", true, true)
check(red == 1 and pen == 0, "red never a penalty")
red, pen = Flow.killDelta("White", true, true)
check(red == 0 and pen == 1, "white by player = penalty")
red, pen = Flow.killDelta("White", true, false)
check(red == 0 and pen == 0, "white by trap = no penalty")
red, pen = Flow.killDelta("Bomb", false, true)
check(red == 0 and pen == 0, "non-penalty kind")
check(Flow.isCleared(2, 2) and not Flow.isCleared(1, 2) and not Flow.isCleared(0, 0), "isCleared")

-- Target after leave (only lowers)
check(Flow.targetAfterLeave(Rules, 3, 1, 2, 0.5) == 2, "4->2 players: 3 -> 2")
check(Flow.targetAfterLeave(Rules, 2, 1, 1, 0.5) == 1, "2->1 players")
check(Flow.targetAfterLeave(Rules, 13, 5, 2, 0.5) == 8, "base 5")
check(Flow.targetAfterLeave(Rules, 1, 1, 3, 0.5) == 1, "never raised")
check(Flow.targetAfterLeave(Rules, 2, 1, 0, 0.5) == 2, "empty party keeps target")

-- Results
local reward = { Base = 20, PerStamp = 10, FirstClear = 30 }
local r = Flow.buildResult(Rules, {
	StageId = "1-1", Cleared = true, Seconds = 30.04, ParTime = 40, Killed = 2, Target = 2, PenaltyKills = 0,
	Reward = reward, PerRedOnFail = 2,
	Members = { { UserId = 1, PrevFlags = 0, RedKills = 2 }, { UserId = 2, PrevFlags = 7, RedKills = 0 } },
})
check(r.Flags == 7, "all stamps")
check(r.NewFlags == 7, "new flags = bits any member lacked")
check(r.Gold["1"] == 80 and r.Gold["2"] == 50, "first-clear bonus per player")
check(r.Members[1].FirstClear and not r.Members[2].FirstClear, "first clear flags")
check(r.Members[1].FlagsAfter == 7, "flags after merge")
check(r.Seconds == 30, "seconds rounded to 0.1")
local slow = Flow.buildResult(Rules, {
	StageId = "1-1", Cleared = true, Seconds = 90, ParTime = 40, Killed = 1, Target = 1, PenaltyKills = 1,
	Reward = reward, PerRedOnFail = 2,
	Members = { { UserId = 7, PrevFlags = 3, RedKills = 1 } },
})
check(slow.Flags == 1 and slow.NewFlags == 0 and slow.Gold["7"] == 30, "clear only, nothing new")
local fail = Flow.buildResult(Rules, {
	StageId = "1-2", Cleared = false, Seconds = 200, ParTime = 60, Killed = 3, Target = 4, PenaltyKills = 2,
	Reward = reward, PerRedOnFail = 2,
	Members = { { UserId = 1, PrevFlags = 0, RedKills = 3 }, { UserId = 2, PrevFlags = 0, RedKills = 0 } },
})
check(fail.Flags == 0 and fail.NewFlags == 0, "fail no flags")
check(fail.Gold["1"] == 6 and fail.Gold["2"] == 6, "fail reward same for all")
check(fail.Members[1].FlagsAfter == 0, "fail does not unlock")
check(Flow.resultId("job", 3, 42) == "job:3:42", "result id format")
check(Flow.resultId("job", 3, 42) ~= Flow.resultId("job", 4, 42), "result id unique per round")
check(Flow.resultId("job", 3, 42) ~= Flow.resultId("job", 3, 43), "result id unique per player")

-- Result options
local order = Stages.Order
local opts, default = Flow.resultOptions(Rules, order, "1-1", true, { { ["1-1"] = 1 } })
check(opts[1] == "Next" and opts[2] == "Retry" and opts[3] == "Lobby" and default == "Next", "clear -> next")
opts, default = Flow.resultOptions(Rules, order, "1-1", false, { { ["1-1"] = 0 } })
check(opts[1] == "Retry" and #opts == 2 and default == "Retry", "first fail -> retry")
opts, default = Flow.resultOptions(Rules, order, "1-1", false, { {}, { ["1-1"] = 1 } })
check(opts[1] == "Next" and default == "Next", "fail but a member already unlocked next")
opts, default = Flow.resultOptions(Rules, order, "1-3", true, { { ["1-3"] = 1 } })
check(opts[1] == "Retry" and default == "Lobby", "last stage -> lobby by default")
check(Flow.resolveResultChoice("Next", order, "1-1") == "1-2", "next stage")
check(Flow.resolveResultChoice("Retry", order, "1-2") == "1-2", "retry")
check(Flow.resolveResultChoice("Lobby", order, "1-2") == nil, "lobby")
check(Flow.resolveResultChoice("Next", order, "1-3") == nil, "next past the end -> lobby")

-- Party / placement
local party = Flow.nextParty({ 1, 2 }, { 3, 2, 4, 5 }, 4)
check(#party == 4 and party[3] == 3 and party[4] == 4, "late joiners appended, capped")
check(Flow.placement("Playing", true, "Alive", true) == "Stage", "alive player in stage")
check(Flow.placement("Playing", true, "Downed", true) == "Stage", "downed stays in stage")
check(Flow.placement("Playing", true, "Out", true) == "Lobby", "out -> lobby")
check(Flow.placement("Playing", false, "Spectating", true) == "Lobby", "spectator -> lobby")
check(Flow.placement("Countdown", true, "Alive", true) == "Stage", "countdown -> stage")
check(Flow.placement("Lobby", true, "Alive", false) == "Lobby", "lobby")
check(Flow.placement("Playing", true, "Alive", false) == "Lobby", "no stage loaded -> lobby")
check(Flow.spawnSlot(1, 4) == 1 and Flow.spawnSlot(5, 4) == 1 and Flow.spawnSlot(6, 4) == 2, "round robin")
check(Flow.spawnSlot(1, 0) == 0, "no markers")

-- v0.5 start room + door (§1.12.3) and loading (§1.12.4)
local Game = require("../src/shared/Config/Game")
check(Flow.loadingRemaining(10, 10, 1.5) == 1.5, "loading: full wait at start")
check(Flow.loadingRemaining(10, 11, 1.5) == 0.5, "loading: partial wait")
check(Flow.loadingRemaining(10, 12, 1.5) == 0, "loading: slow build never waits extra")
check(Flow.loadingRemaining(0 / 0, 12, 1.5) == 0, "loading: NaN safe")

local roomEnds = Flow.startRoomEndsAt(100, Game.StartRoomSeconds)
check(roomEnds == 100 + Game.StartRoomSeconds, "start room ends after StartRoomSeconds")
check(Flow.startRoomEndsAt(100, -5) == 100, "negative start room seconds clamp")
check(Flow.startRoomOutcome(100, roomEnds, false) == nil, "auto-open: waiting at start")
check(Flow.startRoomOutcome(roomEnds - 0.05, roomEnds, false) == nil, "auto-open: not before EndsAt")
check(Flow.startRoomOutcome(roomEnds, roomEnds, false) == "Auto", "auto-open exactly at EndsAt")
check(Flow.startRoomOutcome(roomEnds + 3, roomEnds, false) == "Auto", "auto-open after EndsAt")
check(Flow.startRoomOutcome(105, roomEnds, true) == "Door", "door opened early")
check(Flow.startRoomOutcome(roomEnds + 1, roomEnds, true) == "Door", "door beats auto")

-- door distance (flat, with a height window)
check(Flow.doorDistance({ 0, 3, 0 }, nil, 8) == nil, "no door position -> nil")
check(Flow.doorDistance({ 3, 3, 4 }, { 0, 6, 0 }, 8) == 5, "flat distance ignores height")
check(Flow.doorDistance({ 0, 20, 0 }, { 0, 6, 0 }, 8) == math.huge, "far above the door")
check(Flow.doorDistance({ 0 / 0, 3, 0 }, { 0, 6, 0 }, 8) == math.huge, "NaN root position")
check(Flow.doorDistance({ 0, 3, 0 }, { math.huge, 6, 0 }, 8) == math.huge, "infinite door position")

local function door(over: { [string]: any }): boolean
	local req = {
		Phase = "Countdown",
		RoundMatches = true,
		StartRoomOpen = true,
		InParty = true,
		Life = "Alive",
		Distance = 3,
		Range = Game.DoorInteractRange,
	}
	for k, v in pairs(over) do
		req[k] = v
	end
	return Flow.canOpenDoor(req)
end
check(door({}), "door: valid request")
check(door({ Distance = Game.DoorInteractRange }), "door: exactly at range")
check(not door({ Distance = Game.DoorInteractRange + 0.01 }), "door: out of range")
check(door({ Distance = nil :: any }), "door: unknown door position allows")
check(not door({ Distance = 0 / 0 }), "door: NaN distance")
check(not door({ Distance = math.huge }), "door: too high/low")
check(not door({ Phase = "Playing" }), "door: already playing")
check(not door({ Phase = "Lobby" }), "door: lobby")
check(not door({ Phase = "Result" }), "door: result")
check(not door({ RoundMatches = false }), "door: stale round id")
check(not door({ StartRoomOpen = false }), "door: still loading / already open")
check(not door({ InParty = false }), "door: spectator")
check(not door({ Life = "Downed" }), "door: downed")
check(not door({ Life = "Out" }), "door: out")
check(not door({ Life = "Spectating" }), "door: spectating")

-- the stage clock starts at the door, not at load
local loadedAt, openedAt = 0, 15
local limit = Rules.timeLimit(40, Game.TimeLimitMultiplier)
local startedAt, endsAt = Flow.playWindow(openedAt, limit)
check(startedAt == 15 and endsAt == 15 + limit, "play window starts at door open")
check(Flow.failReason(nil, loadedAt + limit + 1, 10, startedAt, limit) == nil, "start-room time not counted")
check(Flow.failReason(nil, endsAt + 0.1, 10, startedAt, limit) == "Time", "time limit from door")
local fastRun = Flow.buildResult(Rules, {
	StageId = "1-1", Cleared = true, Seconds = (openedAt + 39) - startedAt, ParTime = 40, Killed = 1, Target = 1,
	PenaltyKills = 0, Reward = reward, PerRedOnFail = 2, Members = { { UserId = 1, PrevFlags = 0, RedKills = 1 } },
})
check(bit32.band(fastRun.Flags, 2) ~= 0, "fast stamp measured from the door (39 s after open)")
local _, autoEnd = Flow.playWindow(roomEnds, limit)
check(autoEnd == roomEnds + limit, "auto-open starts the clock at EndsAt")
check(Flow.placement("Countdown", true, "Alive", false) == "Lobby", "loading (no stage yet) -> lobby")

print(("flow.spec: %d checks passed"):format(checks))
