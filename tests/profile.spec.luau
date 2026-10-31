-- Lune test for src/server/Services/Profile.luau. Owner: C.
local Profile = require("../src/server/Services/Profile")

local checks = 0
local function check(cond: boolean, label: string)
	checks += 1
	assert(cond, label)
end

-- new / defaults
local fresh = Profile.new(2000)
check(fresh.Version == 1 and fresh.Gold == 2000, "new with start gold")
check(fresh.Settings.Sensitivity == 1, "default sensitivity")
check(#fresh.Results == 0 and #fresh.Receipts == 0, "empty histories")
check(Profile.new().Gold == 0, "new without start gold")

-- normalize garbage
check(Profile.normalize(nil).Gold == 0, "normalize nil")
for _, junk in ipairs({ 5, "x", true, {}, { Gold = "lots" } } :: { any }) do
	local p = Profile.normalize(junk)
	check(p.Version == 1 and p.Gold == 0 and p.Settings.Sensitivity == 1, "normalize junk " .. tostring(junk))
end
local raw = {
	_Session = { Token = "abc", Time = 1 },
	Version = 99,
	Gold = -50,
	Owned = { Sniper = true, Rifle = "yes", [5] = true, [string.rep("x", 100)] = true },
	Stages = {
		["1-1"] = { Flags = 7, BestTime = 31.5 },
		["1-2"] = { Flags = 255, BestTime = -3 },
		["1-3"] = { Flags = 0/0, BestTime = 1/0 },
		["1-4"] = "broken",
		[7] = { Flags = 1 },
	},
	Stats = { RedKills = 12.7, Clears = -1, Plays = "many" },
	Settings = { Sensitivity = 50 },
	Results = { "a", 5, "b", "a", "c" },
	Receipts = "nope",
	Extra = { deep = true },
}
local n = Profile.normalize(raw)
check((n :: any)._Session == nil and (n :: any).Extra == nil, "unknown keys dropped")
check(n.Version == 1, "version reset to 1")
check(n.Gold == 0, "negative gold clamps to 0")
check(n.Owned.Sniper == true and n.Owned.Rifle == nil, "owned only true values")
local ownedCount = 0
for _ in pairs(n.Owned) do
	ownedCount += 1
end
check(ownedCount == 1, "owned drops non-string and long ids")
check(n.Stages["1-1"].Flags == 7 and n.Stages["1-1"].BestTime == 31.5, "valid stage kept")
check(n.Stages["1-2"].Flags == 7 and n.Stages["1-2"].BestTime == nil, "flags masked, bad best time dropped")
check(n.Stages["1-3"] == nil, "NaN flags + inf time dropped")
check(n.Stages["1-4"] == nil and (n.Stages :: any)[7] == nil, "broken records dropped")
check(n.Stats.RedKills == 12 and n.Stats.Clears == 0 and n.Stats.Plays == 0, "stats integers")
check(n.Settings.Sensitivity == 3, "sensitivity clamped to 3")
check(#n.Results == 3 and n.Results[1] == "a" and n.Results[3] == "c", "results filtered, deduped")
check(#n.Receipts == 0, "bad receipts list")
check(Profile.normalize({ Settings = { Sensitivity = 0.01 } }).Settings.Sensitivity == 0.2, "sensitivity min")
check(Profile.normalize({ Settings = { Sensitivity = 0/0 } }).Settings.Sensitivity == 1, "NaN sensitivity -> default")

-- long histories keep the newest entries
local longResults, longReceipts = {}, {}
for i = 1, 50 do
	table.insert(longResults, "r" .. i)
end
for i = 1, 150 do
	table.insert(longReceipts, "p" .. i)
end
local trimmed = Profile.normalize({ Results = longResults, Receipts = longReceipts })
check(#trimmed.Results == 20 and trimmed.Results[1] == "r31" and trimmed.Results[20] == "r50", "results keep last 20")
check(#trimmed.Receipts == 100 and trimmed.Receipts[1] == "p51", "receipts keep last 100")

-- normalize(serialize(p)) round-trips
local rt = Profile.normalize(Profile.serialize(n))
check(rt.Stages["1-1"].BestTime == 31.5 and rt.Owned.Sniper and rt.Settings.Sensitivity == 3, "round trip")
local s = Profile.serialize(n)
s.Stages["1-1"].Flags = 0
check(n.Stages["1-1"].Flags == 7, "serialize is a deep copy")

-- applyResult: idempotent, merges flags, best time, stats
local p = Profile.new(0)
check(Profile.applyResult(p, "job:1:100", "1-1", 1, 50, 50, 2), "first apply")
check(p.Gold == 50 and p.Stats.Plays == 1 and p.Stats.Clears == 1 and p.Stats.RedKills == 2, "gold and stats")
check(p.Stages["1-1"].Flags == 1 and p.Stages["1-1"].BestTime == 50, "flags + best time")
check(not Profile.applyResult(p, "job:1:100", "1-1", 7, 10, 999, 9), "same result id ignored")
check(p.Gold == 50 and p.Stats.Plays == 1 and p.Stages["1-1"].Flags == 1, "duplicate changed nothing")
check(Profile.applyResult(p, "job:2:100", "1-1", 4 + 1, 70, 30, 1), "second run")
check(p.Stages["1-1"].Flags == 5, "flags merged by union")
check(p.Stages["1-1"].BestTime == 50, "slower clear keeps best time")
check(Profile.applyResult(p, "job:3:100", "1-1", 3, 30, 40, 1), "faster run")
check(p.Stages["1-1"].Flags == 7 and p.Stages["1-1"].BestTime == 30, "faster clear updates best time")
check(Profile.applyResult(p, "job:4:100", "1-1", 0, 5, 4, 2), "failed run")
check(p.Stages["1-1"].BestTime == 30 and p.Stages["1-1"].Flags == 7, "fail never touches best time / flags")
check(p.Stats.Plays == 4 and p.Stats.Clears == 3 and p.Gold == 124, "fail counts a play, not a clear")
check(Profile.applyResult(p, "job:5:100", "1-2", 0, 12, 2, 1), "fail on new stage")
check(p.Stages["1-2"].Flags == 0 and p.Stages["1-2"].BestTime == nil, "fail record has no best time")
check(not Profile.hasCleared(p, "1-2") and Profile.hasCleared(p, "1-1"), "hasCleared")
check(not Profile.applyResult(p, "", "1-1", 1, 1, 1, 1), "empty result id rejected")
check(not Profile.applyResult(p, "x", "", 1, 1, 1, 1), "empty stage id rejected")
local before = p.Gold
check(Profile.applyResult(p, "job:6:100", "1-1", 1, 0/0, -100, -5), "garbage numbers")
check(p.Gold == before and p.Stages["1-1"].BestTime == 30, "negative gold / NaN time ignored")

-- results are capped at 20 and an evicted id could re-apply, receipts do not evict results
local q = Profile.new(0)
for i = 1, 25 do
	Profile.applyResult(q, "res" .. i, "1-1", 1, 40, 1, 0)
end
check(#q.Results == 20 and q.Results[1] == "res6", "results capped at 20")
for i = 1, 150 do
	check(Profile.claimReceipt(q, "buy" .. i), "receipt " .. i)
end
check(#q.Receipts == 100 and #q.Results == 20, "receipts capped separately")
check(Profile.hasResult(q, "res25") and Profile.hasResult(q, "res6"), "receipts did not evict results")
check(not Profile.applyResult(q, "res25", "1-1", 1, 40, 1, 0), "result still idempotent after receipts")
check(not Profile.claimReceipt(q, "buy150"), "receipt claimed once")
check(not Profile.claimReceipt(q, ""), "empty receipt rejected")

-- settings
local t = Profile.new(0)
check(Profile.setSensitivity(t, 2.5) and t.Settings.Sensitivity == 2.5, "set sensitivity")
check(not Profile.setSensitivity(t, 2.5), "same value is no change")
check(Profile.setSensitivity(t, 10) and t.Settings.Sensitivity == 3, "clamped high")
check(not Profile.setSensitivity(t, "fast"), "non-number ignored")
check(not Profile.setSensitivity(t, 0/0), "NaN ignored")

-- ownership / gold
check(Profile.owns(t, "Bat", { "Bat", "Pistol" }), "defaults owned without storage")
check(not Profile.owns(t, "Sniper", { "Bat", "Pistol" }), "sniper not owned")
check(Profile.grant(t, "Sniper") and Profile.owns(t, "Sniper", {}), "grant")
check(not Profile.grant(t, "Sniper"), "grant twice")
t.Gold = 10
check(not Profile.spend(t, 11) and t.Gold == 10, "cannot overspend")
check(Profile.spend(t, 10) and t.Gold == 0, "spend")

-- stage flag view
local view = Profile.stageFlags(p)
check(view["1-1"] == 7 and view["1-2"] == nil, "stageFlags omits zero records")

print(("profile.spec: %d checks passed"):format(checks))
