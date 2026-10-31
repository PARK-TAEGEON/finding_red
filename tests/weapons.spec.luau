-- Lune test for src/shared/WeaponMath.luau and src/shared/Config/Weapons.luau. Owner: A.
local WeaponMath = require("../src/shared/WeaponMath")
local Weapons = require("../src/shared/Config/Weapons")

local checks = 0
local function check(cond: boolean, label: string)
	checks += 1
	assert(cond, label)
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local NAN = 0 / 0
local INF = math.huge

-- Vector helpers -------------------------------------------------------------------------
check(WeaponMath.isVec({ 1, 2, 3 }), "isVec ok")
check(not WeaponMath.isVec({ 1, 2 }), "isVec short")
check(not WeaponMath.isVec({ 1, NAN, 3 }), "isVec NaN")
check(not WeaponMath.isVec({ INF, 0, 0 }), "isVec inf")
check(not WeaponMath.isVec({ -INF, 0, 0 }), "isVec -inf")
check(not WeaponMath.isVec("1,2,3"), "isVec string")
check(not WeaponMath.isVec(nil), "isVec nil")
check(near(WeaponMath.angleDeg({ 1, 0, 0 }, { 0, 0, 1 }), 90), "angle 90")
check(near(WeaponMath.angleDeg({ 1, 0, 0 }, { 1, 0, 0 }), 0), "angle 0")
check(WeaponMath.unit({ 0, 0, 0 }) == nil, "unit of zero")

-- Shot gate -----------------------------------------------------------------------------------
local head = { 0, 5, 0 }
local origin = { 0, 5.5, 0 }
local fwd = { 0, 0, -1 }

local ok, reason = WeaponMath.checkShot(head, origin, fwd)
check(ok and reason == nil, "valid shot gate")
ok, reason = WeaponMath.checkShot(head, { 0, 5, 9 }, fwd)
check(not ok and reason == "OriginFar", "origin > 8 studs from head")
ok, reason = WeaponMath.checkShot(head, { 0, 5, 7.9 }, fwd)
check(ok, "origin 7.9 studs ok")
ok, reason = WeaponMath.checkShot(head, origin, { 0, 0, -2 })
check(not ok and reason == "BadDirection", "non-unit direction")
ok, reason = WeaponMath.checkShot(head, origin, { 0, 0, -1.01 })
check(ok, "direction within tolerance")
ok, reason = WeaponMath.checkShot(head, origin, { 0, 0, 0 })
check(not ok and reason == "BadDirection", "zero direction")
ok, reason = WeaponMath.checkShot(head, origin, { NAN, 0, -1 })
check(not ok and reason == "BadDirection", "NaN direction")
ok, reason = WeaponMath.checkShot(head, { INF, 0, 0 }, fwd)
check(not ok and reason == "BadOrigin", "inf origin")
ok, reason = WeaponMath.checkShot(head, { NAN, NAN, NAN }, fwd)
check(not ok and reason == "BadOrigin", "NaN origin")

-- Hit claim -----------------------------------------------------------------------------------
local enemy = { 0, 5, -50 }
local point = { 0, 5.5, -48 }
local dir = WeaponMath.unit(WeaponMath.sub(point, origin)) :: { number }

ok, reason = WeaponMath.checkHit(origin, dir, point, 300, enemy, 2)
check(ok and reason == nil, "valid hit")
ok, reason = WeaponMath.checkHit(origin, dir, point, 40, enemy, 2)
check(not ok and reason == "OutOfRange", "beyond range")
ok, reason = WeaponMath.checkHit(origin, fwd, { 10, 5.5, -48 }, 300, { 10, 5, -50 }, 2)
check(not ok and reason == "AngleOff", "point far off the look direction")
-- 2 degrees off is accepted, 4 degrees is not
local function rotY(v: { number }, deg: number): { number }
	local r = math.rad(deg)
	return { v[1] * math.cos(r) + v[3] * math.sin(r), v[2], -v[1] * math.sin(r) + v[3] * math.cos(r) }
end
ok = WeaponMath.checkAim(origin, rotY(fwd, 2), { 0, 5.5, -48 }, 300)
check(ok, "2 degrees accepted")
ok, reason = WeaponMath.checkAim(origin, rotY(fwd, 4), { 0, 5.5, -48 }, 300)
check(not ok and reason == "AngleOff", "4 degrees rejected")
ok, reason = WeaponMath.checkHit(origin, dir, point, 300, { 0, 5, -60 }, 2)
check(not ok and reason == "EnemyFar", "enemy history far from point")
ok, reason = WeaponMath.checkHit(origin, dir, point, 300, { 0, 5, -52.4 }, 2)
check(ok, "enemy within radius + 2.5")
ok, reason = WeaponMath.checkHit(origin, dir, point, 300, nil, 2)
check(not ok and reason == "NoHistory", "no history -> reject")
ok, reason = WeaponMath.checkHit(origin, dir, { NAN, 0, 0 }, 300, enemy, 2)
check(not ok and reason == "BadPoint", "NaN point")
ok, reason = WeaponMath.checkHit(origin, dir, { 0, INF, 0 }, 300, enemy, 2)
check(not ok and reason == "BadPoint", "inf point")
ok, reason = WeaponMath.checkHit(origin, dir, point, 300, enemy, NAN)
check(ok, "NaN radius treated as 0 (point still within slack)")
ok = WeaponMath.checkAim(origin, fwd, { 0.3, 5.5, 0.2 }, 300)
check(ok, "point at the muzzle skips the angle test")
local miss = WeaponMath.missEnd(origin, fwd, 100)
check(near(miss[3], -100) and near(miss[2], 5.5), "miss end")

-- Timing ----------------------------------------------------------------------------------------
check(near(WeaponMath.minInterval(4), 0.225), "pistol interval with 10% slack")
check(WeaponMath.minInterval(0) == math.huge, "zero rate never fires")
check(WeaponMath.minInterval(NAN) == math.huge, "NaN rate never fires")
check(WeaponMath.rateOk(nil, 10, 4), "first shot ok")
check(WeaponMath.rateOk(10, 10.25, 4), "exact interval ok")
check(WeaponMath.rateOk(10, 10.23, 4), "within 10% slack ok")
check(not WeaponMath.rateOk(10, 10.2, 4), "faster than slack rejected")
check(not WeaponMath.rateOk(10, 10.0, 4), "same time rejected")
check(not WeaponMath.rateOk(10, NAN, 4), "NaN shot time rejected")
check(WeaponMath.rateOk(10, 11.25, 0.8), "sniper 1.25s ok")
check(not WeaponMath.rateOk(10, 11.0, 0.8), "sniper 1.0s rejected")

local now = 100
check(WeaponMath.shotTime(99.9, now) == 99.9, "claimed time inside window kept")
check(WeaponMath.shotTime(50, now) == now - 0.4, "old claim clamped to now-0.4")
check(WeaponMath.shotTime(200, now) == now + 0.1, "future claim clamped to now+0.1")
check(WeaponMath.shotTime(NAN, now) == now, "NaN claim -> now")
check(WeaponMath.shotTime(INF, now) == now, "inf claim -> now")
check(WeaponMath.shotTime("x", now) == now, "string claim -> now")
check(WeaponMath.rewindTime(99.8, now) == 99.8, "rewind inside window")
check(WeaponMath.rewindTime(10, now) == now - 0.4, "rewind clamped to 0.4s")
check(WeaponMath.rewindTime(101, now) == now, "rewind never in the future")
check(WeaponMath.rewindTime(NAN, now) == now, "NaN rewind -> now")

-- Forged burst: a cheater sending many shots with the same T only gets one.
do
	local last: number? = nil
	local accepted = 0
	for _ = 1, 20 do
		local t = WeaponMath.shotTime(now, now)
		if WeaponMath.rateOk(last, t, 4) then
			last = t
			accepted += 1
		end
	end
	check(accepted == 1, "same-time burst accepted once")
end
-- Sustained honest fire at exactly 4/s over 10 seconds with up to 80ms arrival jitter: all accepted.
do
	local last: number? = nil
	local accepted = 0
	for i = 0, 39 do
		local sent = 1000 + i * 0.25
		local arrive = sent + 0.05 + ((i * 37) % 9) * 0.01
		local t = WeaponMath.shotTime(sent, arrive)
		if WeaponMath.rateOk(last, t, 4) then
			last = t
			accepted += 1
		end
	end
	check(accepted == 40, "honest 4/s with jitter all accepted")
end
-- Cheater claiming increasing fake times at 2x rate: long-run rate bounded.
do
	local last: number? = nil
	local accepted = 0
	local fake = 2000
	for i = 0, 79 do
		local arrive = 2000 + i * 0.125
		fake += 0.125 * 2 -- pretends shots were 0.25 apart
		local t = WeaponMath.shotTime(fake, arrive)
		if WeaponMath.rateOk(last, t, 4) then
			last = t
			accepted += 1
		end
	end
	-- 10 seconds at 4/s (+10% slack, +0.5s window) is at most ~46 shots, not 80
	check(accepted <= 46, ("forged times bounded (%d)"):format(accepted))
end

-- Melee pick ----------------------------------------------------------------------------------------
local me = { 0, 3, 0 }
local cands = {
	{ Id = 1, Pos = { 0, 3, -5 }, Radius = 1.5 }, -- straight ahead, 5
	{ Id = 2, Pos = { 0, 3, -3 }, Radius = 1.5 }, -- straight ahead, 3 (nearest)
	{ Id = 3, Pos = { 0, 3, 4 }, Radius = 1.5 }, -- behind
	{ Id = 4, Pos = { 5, 3, -1 }, Radius = 1.5 }, -- far to the side
}
local id, flatDir = WeaponMath.meleePick(me, { 0, 0, -1 }, cands, 7, 30)
check(id == 2, "nearest in front picked")
check(flatDir ~= nil and near(flatDir[3], -1) and near(flatDir[2], 0), "flat direction toward target")
id = WeaponMath.meleePick(me, { 0, 0, 1 }, cands, 7, 30)
check(id == 3, "turned around picks the one behind")
id = WeaponMath.meleePick(me, { 0, 0, -1 }, { cands[4] }, 7, 30)
check(id == nil, "side target outside the cone")
id = WeaponMath.meleePick(me, { 0, 0, -1 }, { { Id = 5, Pos = { 0, 3, -7.5 }, Radius = 1.5 } }, 7, 30)
check(id == nil, "beyond range")
id = WeaponMath.meleePick(me, { 0, 0, -1 }, { { Id = 6, Pos = { 0, 12, -3 }, Radius = 1.5 } }, 7, 30)
check(id == nil, "too high")
id = WeaponMath.meleePick(me, { 0, 0, -1 }, { { Id = 7, Pos = { 0.5, 3, 0.5 }, Radius = 1.5 } }, 7, 30)
check(id == 7, "overlapping enemy always hit")
id = WeaponMath.meleePick(me, { 0, -1, 0 }, cands, 7, 30)
check(id == nil, "straight-down look has no flat forward")
id = WeaponMath.meleePick(me, { 0, 0, -1 }, { { Id = 8, Pos = { NAN, 3, -3 }, Radius = 1.5 } }, 7, 30)
check(id == nil, "NaN candidate ignored")
-- A body overlapping the edge of the cone counts (radius widens it).
id = WeaponMath.meleePick(me, { 0, 0, -1 }, { { Id = 9, Pos = { 2.6, 3, -3 }, Radius = 1.5 } }, 7, 30)
check(id == 9, "edge overlap widened by radius")

-- Ammo ------------------------------------------------------------------------------------------------
local m, r = WeaponMath.fullAmmo(12, 48)
check(m == 12 and r == 48, "full ammo")
check(WeaponMath.hasAmmo(12, 1) and not WeaponMath.hasAmmo(12, 0), "has ammo")
check(WeaponMath.hasAmmo(nil, 0), "melee always has ammo")
check(WeaponMath.spend(12, 5) == 4 and WeaponMath.spend(12, 0) == 0, "spend")
check(WeaponMath.spend(nil, 0) == 0, "melee spend no-op")
check(WeaponMath.canReload(12, 5, 10), "can reload")
check(not WeaponMath.canReload(12, 12, 10), "full mag no reload")
check(not WeaponMath.canReload(12, 3, 0), "no reserve no reload")
check(not WeaponMath.canReload(nil, 0, 0), "melee no reload")
m, r = WeaponMath.reload(12, 5, 48)
check(m == 12 and r == 41, "reload takes what is missing")
m, r = WeaponMath.reload(12, 5, 3)
check(m == 8 and r == 0, "reload partial reserve")
m, r = WeaponMath.reload(5, 0, 10)
check(m == 5 and r == 5, "sniper reload")
check(WeaponMath.addPercent(12, 48, 12, 0, 50) == 30, "50% of 60 capacity")
check(WeaponMath.addPercent(12, 48, 12, 40, 50) == 48, "capped at reserve max with full mag")
check(WeaponMath.addPercent(12, 48, 2, 40, 100) == 58, "missing mag rounds can sit in reserve")
check(WeaponMath.addPercent(nil, nil, 0, 0, 50) == 0, "melee no ammo")
check(WeaponMath.addPercent(12, 48, 12, 10, NAN) == 10, "NaN percent ignored")

-- Loadout ----------------------------------------------------------------------------------------------
local order = { "Bat", "Pistol", "Sniper", "Rifle" }
local list = WeaponMath.loadout(order, { "Bat", "Pistol" }, nil, nil)
check(WeaponMath.joinList(list) == "Bat,Pistol", "defaults only")
list = WeaponMath.loadout(order, { "Bat", "Pistol" }, { Rifle = true, Fake = true }, { Sniper = true })
check(WeaponMath.joinList(list) == "Bat,Pistol,Sniper,Rifle", "owned + pickup, ordered, unknown dropped")
list = WeaponMath.loadout(order, { "Bat", "Pistol" }, { Rifle = false }, {})
check(WeaponMath.joinList(list) == "Bat,Pistol", "owned=false ignored")
local parsed = WeaponMath.parseList("Bat,Pistol,Sniper")
check(#parsed == 3 and parsed[3] == "Sniper", "parse list")
check(#WeaponMath.parseList(nil) == 0 and #WeaponMath.parseList("") == 0, "parse empty")
check(WeaponMath.cycle(parsed, "Pistol") == "Sniper", "cycle next")
check(WeaponMath.cycle(parsed, "Sniper") == "Bat", "cycle wraps")
check(WeaponMath.cycle(parsed, "Rocket") == "Bat", "cycle unknown -> first")
check(WeaponMath.cycle({}, "Bat") == nil, "cycle empty")

-- Pickup reach / blast ------------------------------------------------------------------------------
check(WeaponMath.inReach({ 0, 3, 0 }, { 3, 1, 2 }, 4), "within 4 studs flat")
check(not WeaponMath.inReach({ 0, 3, 0 }, { 3, 1, 3 }, 4), "outside 4 studs")
check(not WeaponMath.inReach({ 0, 3, 0 }, { 0, 20, 0 }, 4), "too high above")
check(not WeaponMath.inReach({ NAN, 3, 0 }, { 0, 3, 0 }, 4), "NaN reach")
check(WeaponMath.blastDamage({ 0, 0, 0 }, { 0, 0, 11 }, 12, 40) == 40, "inside blast")
check(WeaponMath.blastDamage({ 0, 0, 0 }, { 0, 0, 13 }, 12, 40) == 0, "outside blast")

-- Config sanity -----------------------------------------------------------------------------------------
local kinds = { Melee = true, Hitscan = true, Throw = true, Projectile = true }
for _, wid in ipairs(Weapons.Order) do
	local spec = Weapons[wid]
	check(type(spec) == "table", "config entry " .. wid)
	check(type(spec.Name) == "string" and kinds[spec.Kind] == true, "name/kind " .. wid)
	check(type(spec.Damage) == "number" and spec.Rate > 0 and spec.Range > 0, "numbers " .. wid)
	check(type(spec.Sound) == "string", "sound key " .. wid)
	check(spec.Slot >= 1 and spec.Slot <= 4, "slot " .. wid)
	if spec.Kind ~= "Melee" then
		check(type(spec.Mag) == "number" and type(spec.Reserve) == "number", "ammo " .. wid)
	end
end
for _, wid in ipairs(Weapons.Default) do
	check(table.find(Weapons.Order, wid) ~= nil, "default in order " .. wid)
end
check(Weapons.Bat.Damage == 35 and Weapons.Bat.Rate == 1.5 and Weapons.Bat.Range == 7, "bat numbers (§1.9)")
check(Weapons.Bat.Knockback ~= nil and Weapons.Bat.Knockback.Stun == 2, "bat stun 2s")
check(Weapons.Pistol.Damage == 15 and Weapons.Pistol.Rate == 4, "pistol numbers")
check(Weapons.Pistol.Mag == 12 and Weapons.Pistol.Reserve == 48 and Weapons.Pistol.AimFov == 55, "pistol ammo/fov")
check(Weapons.Sniper.Damage == 100 and Weapons.Sniper.Rate == 0.8, "sniper numbers")
check(Weapons.Sniper.Mag == 5 and Weapons.Sniper.Reserve == 10, "sniper ammo")
check(Weapons.Sniper.Scope == true and Weapons.Sniper.AimFov == 20, "sniper scope")

print(("weapons.spec: %d checks passed"):format(checks))
