-- Lune test for src/shared/EnemyLogic.luau. Owner: B.
local L = require("../src/shared/EnemyLogic")
local Enemies = require("../src/shared/Config/Enemies")

local checks = 0
local function check(cond: boolean, label: string)
	checks += 1
	assert(cond, label)
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local Red = Enemies.Red
local White = Enemies.White
local V = L.vec

-- Red with the legacy flee brain (Behavior = "Flee"), kept for later variants.
local RedFlee = table.clone(Red)
RedFlee.Behavior = "Flee"

-- deterministic RNG
local seed = 12345
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local function sense(now: number, pos, players, extra: { [string]: any }?)
	local s = { Now = now, Pos = pos, Players = players or {}, Random = rand }
	if extra then
		for k, v in pairs(extra) do
			s[k] = v
		end
	end
	return s
end

-- Config schema (CONTRACT §3.6 / §1.8) -----------------------------------------------
check(Red.HP == 30 and Red.Speed == 8 and Red.RunSpeed == 14 and Red.Sight == 35 and Red.Penalty == false, "red cfg (v0.5)")
check(Red.Behavior == "Chase" and Red.Leash == 40, "red chases by default, leash 40")
check(Red.Melee ~= nil and Red.Melee.Damage == 8 and Red.Melee.Interval == 1.2 and Red.Melee.Range == 4, "red melee")
check(Red.RunSpeed < 16, "red chase slower than player walk")
check(Red.Flee ~= nil and Red.Flee.Run == 4 and Red.Flee.Rest == 2 and Red.Flee.RestSpeed == 6, "red flee cfg kept")
check(White.HP == 60 and White.RunSpeed == 18 and White.Sight == 25 and White.Leash == 50 and White.Penalty, "white cfg")
check(L.behaviourOf(Red) == "Chase" and L.behaviourOf(RedFlee) == "Flee" and L.behaviourOf(White) == "Chase", "behaviour field")
check(L.behaviourOf({ Speed = 1, RunSpeed = 1, Sight = 1, Flee = { Run = 1, Rest = 1, RestSpeed = 1 } }) == "Flee", "inferred flee")
check(L.behaviourOf({ Speed = 1, RunSpeed = 1, Sight = 1 }) == "None", "inferred none")
check(White.Melee ~= nil and White.Melee.Damage == 10 and White.Melee.Interval == 1 and White.Melee.Range == 4, "white melee")
for kind, cfg in pairs(Enemies) do
	check(type(cfg.Name) == "string" and cfg.HP > 0 and cfg.Radius > 0, kind .. " basics")
	check(string.match(cfg.Body, "^#%x%x%x%x%x%x$") ~= nil and string.match(cfg.Accent, "^#%x%x%x%x%x%x$") ~= nil, kind .. " colors")
end

-- Zone math -------------------------------------------------------------------------------
local home = V(0, 0, 0)
local c = L.clampToZone(V(30, 5, 40), home, 10)
check(near(L.flatDistance(c, home), 10) and c[2] == 5, "clamp onto rim keeps y")
check(near(c[1], 6) and near(c[3], 8), "clamp keeps direction")
local inside = L.clampToZone(V(3, 1, 4), home, 10)
check(inside[1] == 3 and inside[3] == 4, "inside point untouched")
check(L.inZone(V(10, 99, 0), home, 10) and not L.inZone(V(10.1, 0, 0), home, 10), "inZone ignores y")
for _ = 1, 200 do
	local p = L.randomPointInZone(V(5, 2, -5), 12, rand)
	check(L.flatDistance(p, V(5, 2, -5)) <= 12 + 1e-9 and p[2] == 2, "random point in zone")
end
check(near(L.segmentDistance(V(0, 0, 0), V(10, 0, 0), V(5, 0, 3)), 3), "segment distance mid")
check(near(L.segmentDistance(V(0, 0, 0), V(10, 0, 0), V(-4, 0, 3)), 5), "segment distance end")

-- Flee direction --------------------------------------------------------------------------
do
	local pos, threat = V(0, 0, 0), V(10, 0, 0)
	local g = L.fleePoint(pos, threat, home, 30)
	check(g ~= nil, "flee point exists")
	local goal = g :: { number }
	check(goal[1] < 0, "flees away from threat")
	check(L.flatDistance(goal, threat) > 10, "flee increases distance")
	check(L.inZone(goal, home, 30), "flee stays in zone")
	check(L.flatDistance(goal, home) <= 30 * L.FLEE_EDGE + 1e-6, "flee keeps edge margin")
end

-- Cornered at the edge, threat coming from the middle: slide along the rim, never past the player.
do
	local pos, threat = V(17.5, 0, 0), V(8, 0, 0)
	local d0 = L.flatDistance(pos, threat)
	local g = L.fleePoint(pos, threat, home, 20)
	check(g ~= nil, "cornered still finds a point")
	local goal = g :: { number }
	check(L.inZone(goal, home, 20), "cornered flee in zone")
	check(L.flatDistance(goal, pos) >= L.FLEE_MIN_STEP, "cornered flee actually moves (no freeze)")
	check(L.flatDistance(goal, threat) > d0, "cornered flee gains distance")
	check(math.abs(goal[3]) > 3, "cornered flee slides sideways along the rim")
	check(L.segmentDistance(pos, goal, threat) >= math.min(d0, math.max(6, d0 * 0.75)) - 0.06, "never runs past threat")
end

-- Walkable filter: everything with z > 0 is blocked -> picks the other side.
do
	local pos, threat = V(17.5, 0, 0), V(8, 0, 0)
	local g = L.fleePoint(pos, threat, home, 20, function(_from, to)
		return to[3] <= 0
	end)
	check(g ~= nil and (g :: { number })[3] <= 0, "walkable filter respected")
	local none = L.fleePoint(pos, threat, home, 20, function()
		return false
	end)
	check(none == nil, "nothing walkable -> nil (stand)")
end

-- Enemy outside its zone (knocked out) flees back inside.
do
	local g = L.fleePoint(V(40, 0, 0), V(30, 0, 0), home, 20)
	check(g ~= nil and L.inZone(g :: { number }, home, 20), "outside enemy flees into zone")
	local goal = g :: { number }
	check(math.abs(goal[3]) > 5, "outside enemy swerves around the threat")
end

-- Threat exactly on top of the enemy still yields a direction.
do
	local g = L.fleePoint(V(5, 0, 0), V(5, 0, 0), home, 20)
	check(g ~= nil, "threat on top")
end

-- Flee-behaviour Red (Behavior = "Flee") cycle: Idle -> Alert 0.5 -> Flee 4 -> Tired 2 -> Flee (threat) -> Tired -> Idle -------------
do
	local b = L.new("Red", RedFlee, home, 25, 0)
	check(b.State == "Idle" and b.Behaviour == "Flee", "flee red starts idle")
	local pos = V(0, 0, 0)
	local player = { Id = 7, Pos = V(30, 0, 0) }

	local a = L.step(b, RedFlee, sense(0, pos, {}))
	check(a.State == "Idle" and a.Speed == RedFlee.Speed, "red wanders at 8")
	check(a.Goal == nil or L.inZone(a.Goal :: { number }, home, 25), "wander goal in zone")

	-- out of sight range
	a = L.step(b, RedFlee, sense(0.1, pos, { { Id = 7, Pos = V(45, 0, 0) } }))
	check(a.State == "Idle", "beyond sight not seen")
	-- in range but no line of sight
	a = L.step(b, RedFlee, sense(0.2, pos, { player }, { CanSee = function()
		return false
	end }))
	check(a.State == "Idle", "no LOS not seen")

	a = L.step(b, RedFlee, sense(1, pos, { player }))
	check(a.State == "Alert" and a.Alert == true and a.Goal == nil, "alert on sight")
	check(a.Face ~= nil and (a.Face :: { number })[1] == 30, "faces player on alert")
	a = L.step(b, RedFlee, sense(1.3, pos, { player }))
	check(a.State == "Alert" and a.Alert == false, "alert pulse only once")
	a = L.step(b, RedFlee, sense(1.5, pos, { player }))
	check(a.State == "Flee" and a.Speed == RedFlee.RunSpeed, "flee after 0.5s alert")
	check(a.Goal ~= nil and (a.Goal :: { number })[1] < 0, "flee goal away from player")
	a = L.step(b, RedFlee, sense(5.49, pos, { player }))
	check(a.State == "Flee", "still fleeing before 4s")
	a = L.step(b, RedFlee, sense(5.5, pos, { player }))
	check(a.State == "Tired" and a.Speed == 6, "tired after 4s flee")
	a = L.step(b, RedFlee, sense(7.49, pos, { player }))
	check(a.State == "Tired", "tired lasts 2s")
	a = L.step(b, RedFlee, sense(7.5, pos, { player }))
	check(a.State == "Flee" and a.Alert == false, "flee again while threatened, no second alert")
	a = L.step(b, RedFlee, sense(11.5, pos, {}))
	check(a.State == "Tired", "tired again")
	a = L.step(b, RedFlee, sense(13.5, pos, {}))
	check(a.State == "Idle", "back to wander when safe")

	-- damage while idle alerts; damage while tired flees immediately
	local b2 = L.new("Red", RedFlee, home, 25, 0)
	check(L.damaged(b2, RedFlee, 1, pos, 9) == true, "damage alerts idle red")
	a = L.step(b2, RedFlee, sense(1, pos, { { Id = 9, Pos = V(0, 0, 20) } }))
	check(a.State == "Alert" and a.Alert, "damaged red alert pulse")
	a = L.step(b2, RedFlee, sense(1.5, pos, { { Id = 9, Pos = V(0, 0, 20) } }))
	check(a.State == "Flee" and a.Goal ~= nil and (a.Goal :: { number })[3] < 0, "damaged red flees from attacker")
	a = L.step(b2, RedFlee, sense(5.6, pos, { { Id = 9, Pos = V(0, 0, 20) } }))
	check(a.State == "Tired", "red tired")
	L.damaged(b2, RedFlee, 5.7, pos, 9)
	check(b2.State == "Flee", "hit while tired -> flee")

	-- fleeing red with no players left keeps running out its timer, still inside its zone
	local b3 = L.new("Red", RedFlee, home, 10, 0)
	L.damaged(b3, RedFlee, 0, pos, nil)
	L.step(b3, RedFlee, sense(0, pos, {}))
	a = L.step(b3, RedFlee, sense(0.5, pos, {}))
	check(a.State == "Flee" and a.Goal ~= nil and L.inZone(a.Goal :: { number }, home, 10), "flee without threat stays in zone")
end

-- Red flee goals always in zone over many random situations
do
	for i = 1, 300 do
		local zone = 6 + rand() * 30
		local pos = L.randomPointInZone(home, zone * 1.2, rand)
		local threat = L.randomPointInZone(home, zone * 2, rand)
		local g = L.fleePoint(pos, threat, home, zone)
		check(g ~= nil, "random flee never freezes " .. i)
		check(L.inZone(g :: { number }, home, zone), "random flee in zone " .. i)
		if L.inZone(pos, home, zone * L.FLEE_EDGE) then
			local d0 = L.flatDistance(pos, threat)
			check(
				L.segmentDistance(pos, g :: { number }, threat) >= math.min(d0, math.max(6, d0 * 0.75)) - 0.06,
				"random flee (inside zone) never past threat " .. i
			)
		end
	end
end

-- Red (v0.5 default, Behavior = "Chase"): wander -> "!" -> chase 14 -> melee 8 / 1.2 s -> leash 40 -------
do
	local b = L.new("Red", Red, home, 15, 0)
	check(b.State == "Idle" and b.Behaviour == "Chase", "red starts idle, chase brain")
	local pos = V(0, 0, 0)
	local p = { Id = 7, Pos = V(36, 0, 0) }

	local a = L.step(b, Red, sense(0, pos, {}))
	check(a.State == "Idle" and a.Speed == 8, "red wanders at 8")
	check(a.Goal == nil or L.inZone(a.Goal :: { number }, home, 15), "red wander goal in zone")
	a = L.step(b, Red, sense(0.1, pos, { p }))
	check(a.State == "Idle", "red: beyond sight 35 not seen")
	p.Pos = V(30, 0, 0)
	a = L.step(b, Red, sense(0.2, pos, { p }, { CanSee = function()
		return false
	end }))
	check(a.State == "Idle", "red: no line of sight not seen")

	a = L.step(b, Red, sense(1, pos, { p }))
	check(a.State == "Alert" and a.Alert == true and a.Goal == nil, "red alerts on sight")
	check(a.Face ~= nil and (a.Face :: { number })[1] == 30, "red faces player during alert")
	a = L.step(b, Red, sense(1.3, pos, { p }))
	check(a.State == "Alert" and a.Alert == false and a.Goal == nil, "red holds still, '!' once")
	a = L.step(b, Red, sense(1.5, pos, { p }))
	check(a.State == "Chase" and a.Speed == 14, "red chases at 14 after 0.5 s")
	check(a.Goal ~= nil and (a.Goal :: { number })[1] == 30, "red runs toward the player (not away)")
	check(a.Attack == nil, "red: no hit out of range")

	-- in range: windup, then 8 damage every 1.2 s
	pos = V(27, 0, 0)
	a = L.step(b, Red, sense(1.6, pos, { p }))
	check(a.Attack == nil and a.Face ~= nil, "red windup before first hit")
	a = L.step(b, Red, sense(1.85, pos, { p }))
	check(a.Attack == 7, "red first hit")
	a = L.step(b, Red, sense(2.9, pos, { p }))
	check(a.Attack == nil, "red interval 1.2 respected")
	a = L.step(b, Red, sense(3.1, pos, { p }))
	check(a.Attack == 7, "red second hit after 1.2 s")
	a = L.step(b, Red, sense(3.2, V(28, 0, 0), { p }))
	check(a.Goal == nil and a.Face ~= nil and a.Attack == nil, "red stands and faces when hugging")
	-- player backs off: red follows again
	p.Pos = V(34, 0, 0)
	a = L.step(b, Red, sense(3.3, V(28, 0, 0), { p }))
	check(a.State == "Chase" and a.Goal ~= nil and (a.Goal :: { number })[1] == 34, "red follows a retreating player")

	-- leash 40 from home -> return (walk 8), players ignored on the way back
	p.Pos = V(50, 0, 0)
	a = L.step(b, Red, sense(4, V(40.5, 0, 0), { p }))
	check(a.State == "Return" and a.Speed == 8 and a.Goal ~= nil and (a.Goal :: { number })[1] == 0, "red leash -> return home")
	a = L.step(b, Red, sense(4.1, V(38, 0, 0), { { Id = 7, Pos = V(36, 0, 0) } }))
	check(a.State == "Return" and a.Attack == nil, "returning red ignores players")
	check(L.damaged(b, Red, 4.2, V(38, 0, 0), 7) == false and b.State == "Return", "red: no re-aggro near the leash")
	check(L.damaged(b, Red, 4.3, V(20, 0, 0), 7) == true and b.State == "Alert", "red re-aggro when hit near home")
	b.State = "Return"
	a = L.step(b, Red, sense(5, V(1, 0, 1), {}))
	check(a.State == "Idle", "red home -> idle")

	-- shot from out of sight while idle: "!" then chase the shooter
	local b2 = L.new("Red", Red, home, 15, 0)
	check(L.damaged(b2, Red, 0, V(0, 0, 0), 9) == true, "hit alerts idle red")
	a = L.step(b2, Red, sense(0, V(0, 0, 0), { { Id = 9, Pos = V(0, 0, 50) } }))
	check(a.State == "Alert" and a.Alert, "hit red alert pulse")
	a = L.step(b2, Red, sense(0.5, V(0, 0, 0), { { Id = 9, Pos = V(0, 0, 50) } }))
	check(a.State == "Chase" and b2.Target == 9 and (a.Goal :: { number })[3] == 50, "hit red chases the shooter")
	-- shooter goes down (leaves the targetable list), nobody else visible -> return
	a = L.step(b2, Red, sense(0.6, V(0, 0, 9), {}))
	check(a.State == "Return", "red target gone -> return")

	-- retarget another visible player when the first one goes down
	local b3 = L.new("Red", Red, home, 15, 0)
	L.damaged(b3, Red, 0, V(0, 0, 0), 1)
	L.step(b3, Red, sense(0, V(0, 0, 0), {}))
	a = L.step(b3, Red, sense(0.5, V(0, 0, 0), { { Id = 2, Pos = V(0, 0, 10) } }))
	check(a.State == "Chase" and b3.Target == 2, "red retargets nearest visible")

	-- chasing red never flees, whatever happens
	local b4 = L.new("Red", Red, home, 12, 0)
	local pp = V(0, 0, 0)
	for i = 1, 400 do
		local t = i * 0.1
		local players = {}
		if rand() < 0.8 then
			table.insert(players, { Id = 1, Pos = L.randomPointInZone(home, 45, rand) })
		end
		if rand() < 0.05 then
			L.damaged(b4, Red, t, pp, 1)
		end
		local act = L.step(b4, Red, sense(t, pp, players))
		check(act.State ~= "Flee" and act.State ~= "Tired", "chasing red never flees " .. i)
		check(act.Attack == nil or act.State == "Chase", "red only hits while chasing " .. i)
		local g = act.Goal
		if g then
			pp = { pp[1] + (g[1] - pp[1]) * 0.3, 0, pp[3] + (g[3] - pp[3]) * 0.3 }
		end
	end
end

-- White: chase, melee, leash, return ---------------------------------------------------------
do
	local b = L.new("White", White, home, 15, 0)
	check(b.Behaviour == "Chase", "white chases")
	local pos = V(0, 0, 0)
	local p = { Id = 3, Pos = V(30, 0, 0) }
	local a = L.step(b, White, sense(0, pos, { p }))
	check(a.State == "Idle", "white ignores beyond 25")
	p.Pos = V(20, 0, 0)
	a = L.step(b, White, sense(0.1, pos, { p }))
	check(a.State == "Alert" and a.Alert, "white alerts within 25")
	a = L.step(b, White, sense(0.6, pos, { p }))
	check(a.State == "Chase" and a.Speed == 18, "white chases at 18")
	check(a.Goal ~= nil and (a.Goal :: { number })[1] == 20, "chase goal = player")
	check(a.Attack == nil, "no attack out of range")

	-- in range: windup then 1 hit per second
	pos = V(17, 0, 0)
	a = L.step(b, White, sense(0.7, pos, { p }))
	check(a.Attack == nil, "windup before first swing")
	a = L.step(b, White, sense(0.95, pos, { p }))
	check(a.Attack == 3, "first swing")
	a = L.step(b, White, sense(1.5, pos, { p }))
	check(a.Attack == nil, "interval respected")
	a = L.step(b, White, sense(1.95, pos, { p }))
	check(a.Attack == 3, "second swing after 1s")
	pos = V(19, 0, 0)
	a = L.step(b, White, sense(2.0, pos, { p }))
	check(a.Goal == nil and a.Face ~= nil, "stops when hugging the target")

	-- target out of party (downed/left): no other target -> return
	local b2 = L.new("White", White, home, 15, 0)
	L.damaged(b2, White, 0, pos, 3)
	L.step(b2, White, sense(0, V(0, 0, 0), { p }))
	a = L.step(b2, White, sense(0.5, V(0, 0, 0), { p }))
	check(a.State == "Chase", "hit white chases attacker")
	a = L.step(b2, White, sense(0.6, V(12, 0, 0), {}))
	check(a.State == "Return" and a.Goal ~= nil and (a.Goal :: { number })[1] == 0, "target gone -> return home")

	-- leash
	b.Target = 3
	a = L.step(b, White, sense(3, V(50.5, 0, 0), { { Id = 3, Pos = V(60, 0, 0) } }))
	check(a.State == "Return" and a.Speed == White.Speed, "beyond leash -> return")
	a = L.step(b, White, sense(3.1, V(45, 0, 0), { { Id = 3, Pos = V(47, 0, 0) } }))
	check(a.State == "Return", "return ignores players")
	-- hit while far from home does not re-aggro (avoids leash ping-pong)
	check(L.damaged(b, White, 3.2, V(45, 0, 0), 3) == false and b.State == "Return", "no reaggro near leash")
	check(L.damaged(b, White, 3.3, V(20, 0, 0), 3) == true and b.State == "Alert", "reaggro when close to home")
	b.State = "Return"
	a = L.step(b, White, sense(4, V(1, 0, 1), {}))
	check(a.State == "Idle", "home -> idle")

	-- retarget: original target gone but another visible player within sight
	local b3 = L.new("White", White, home, 15, 0)
	L.damaged(b3, White, 0, V(0, 0, 0), 1)
	L.step(b3, White, sense(0, V(0, 0, 0), {}))
	a = L.step(b3, White, sense(0.5, V(0, 0, 0), { { Id = 2, Pos = V(0, 0, 10) } }))
	check(a.State == "Chase" and b3.Target == 2, "retarget nearest visible")
end

-- Stun ------------------------------------------------------------------------------------------
do
	local b = L.new("White", White, home, 15, 0)
	local p = { Id = 4, Pos = V(10, 0, 0) }
	L.step(b, White, sense(0, V(0, 0, 0), { p }))
	L.step(b, White, sense(0.5, V(0, 0, 0), { p }))
	check(b.State == "Chase", "chasing before stun")
	L.stun(b, 1, 2)
	local a = L.step(b, White, sense(1.5, V(0, 0, 0), { p }))
	check(a.State == "Stunned" and a.Goal == nil and a.Speed == 0 and a.Attack == nil, "stunned does nothing")
	a = L.step(b, White, sense(2.99, V(9, 0, 0), { p }))
	check(a.State == "Stunned" and a.Attack == nil, "no attack while stunned even in range")
	check(L.damaged(b, White, 2.5, V(0, 0, 0), 5) == false and b.State == "Stunned", "damage keeps stun")
	a = L.step(b, White, sense(3, V(0, 0, 0), { p, { Id = 5, Pos = V(0, 0, 12) } }))
	check(a.State == "Chase" and b.Target == 5, "after stun chase last attacker")
	check(a.Alert == false, "no alert after stun")

	local r = L.new("Red", RedFlee, home, 15, 0)
	L.stun(r, 0, 1)
	local ar = L.step(r, RedFlee, sense(1, V(0, 0, 0), { p }))
	check(ar.State == "Flee", "flee red resumes flee when threatened after stun")
	local r2 = L.new("Red", RedFlee, home, 15, 0)
	L.stun(r2, 0, 1)
	ar = L.step(r2, RedFlee, sense(1, V(0, 0, 0), {}))
	check(ar.State == "Idle", "flee red idle after stun when safe")

	-- chasing Red: stunned mid-chase, resumes the chase (no second "!")
	local rc = L.new("Red", Red, home, 15, 0)
	L.damaged(rc, Red, 0, V(0, 0, 0), 4)
	L.step(rc, Red, sense(0, V(0, 0, 0), { p }))
	L.step(rc, Red, sense(0.5, V(0, 0, 0), { p }))
	check(rc.State == "Chase", "red chasing before stun")
	L.stun(rc, 1, 1)
	ar = L.step(rc, Red, sense(1.5, V(9, 0, 0), { p }))
	check(ar.State == "Stunned" and ar.Attack == nil, "stunned red does not hit")
	ar = L.step(rc, Red, sense(2, V(0, 0, 0), { p }))
	check(ar.State == "Chase" and ar.Alert == false, "red resumes chase after stun")
end

-- Dead does nothing --------------------------------------------------------------------------
do
	local b = L.new("White", White, home, 15, 0)
	L.kill(b)
	local a = L.step(b, White, sense(1, V(0, 0, 0), { { Id = 1, Pos = V(1, 0, 0) } }))
	check(a.State == "Dead" and a.Goal == nil and a.Attack == nil and not a.Alert and a.Speed == 0, "dead is inert")
	check(L.damaged(b, White, 2, V(0, 0, 0), 1) == false and b.State == "Dead", "dead ignores damage")
	L.stun(b, 3, 2)
	check(b.State == "Dead", "dead ignores stun")
end

-- Unknown behaviour (no Flee/Melee) only wanders --------------------------------------------
do
	local cfg = { Speed = 5, RunSpeed = 5, Sight = 50 }
	local b = L.new("Dummy", cfg, home, 10, 0)
	local a = L.step(b, cfg, sense(1, V(0, 0, 0), { { Id = 1, Pos = V(3, 0, 0) } }))
	check(a.State == "Idle", "no-behaviour kind wanders")
end

-- Wander respects stuck + walkable ------------------------------------------------------------
do
	local b = L.new("Red", Red, home, 20, 0)
	local a = L.step(b, Red, sense(1, V(0, 0, 0), {}))
	check(a.Goal ~= nil, "wander picks goal")
	a = L.step(b, Red, sense(1.1, V(0, 0, 0), {}, { Stuck = true }))
	check(a.Goal == nil, "stuck drops goal and pauses")
	local b2 = L.new("Red", Red, home, 20, 0)
	a = L.step(b2, Red, sense(1, V(0, 0, 0), {}, { Walkable = function()
		return false
	end }))
	check(a.Goal == nil and a.State == "Idle", "nothing walkable -> stand")
end

-- Death collapse helpers -------------------------------------------------------------------------
do
	local C = L.CORPSE
	local fwd, back = 0, 0
	for _ = 1, 400 do
		local d, sign = L.deathPush(V(10, 0, 0), V(0, 5, 0), rand)
		check(near(d[1], 1) and near(d[2], 0) and near(d[3], 0), "push points away from the attacker, flat")
		check(sign == 1 or sign == -1, "fall sign")
		if sign == 1 then
			back += 1
		else
			fwd += 1
		end
	end
	check(back > fwd and fwd > 0, "falls both ways, mostly backward")
	for _ = 1, 50 do
		local d = L.deathPush(V(3, 0, 3), nil, rand)
		check(near(math.sqrt(d[1] * d[1] + d[3] * d[3]), 1) and d[2] == 0, "random push is a flat unit vector")
		local d2 = L.deathPush(V(3, 0, 3), V(3, 9, 3), rand)
		check(near(math.sqrt(d2[1] * d2[1] + d2[3] * d2[3]), 1), "attacker straight above -> random flat push")
	end
	check(C.PushSpeed > 0 and C.PushSpeed <= 5 and C.MaxSlide >= 1 and C.MaxSlide <= 3, "small shove, not a fling")
	check(C.Cap == 12, "12 bodies kept")
	check(not L.corpseShouldFreeze(0.2, 10, false), "never freeze instantly")
	check(not L.corpseShouldFreeze(1.0, 1, false), "wait for calm")
	check(L.corpseShouldFreeze(1.0, C.CalmTicks, false), "freeze when calm")
	check(not L.corpseShouldFreeze(1.5, C.CalmTicks, true), "keep simulating while falling")
	check(L.corpseShouldFreeze(C.MaxSettle, 0, false), "freeze at max settle even if jittering")
	check(not L.corpseShouldFreeze(C.MaxSettle + 1, 0, true), "falling body may run past max settle")
	check(L.corpseShouldFreeze(C.HardMax, 0, true), "hard max always freezes")
	check(L.corpsesToEvict(12, 12) == 0 and L.corpsesToEvict(13, 12) == 1 and L.corpsesToEvict(15, 12) == 3, "evict oldest beyond cap")
end

-- History interpolation ---------------------------------------------------------------------------
do
	local times = { 10.0, 10.1, 10.2, 10.3 }
	local i, j, t = L.historyAt(times, 10.15)
	check(i == 2 and j == 3 and near(t, 0.5), "history interpolates")
	i, j = L.historyAt(times, 9)
	check(i == 1 and j == 1, "history clamps old")
	i, j = L.historyAt(times, 11)
	check(i == 4 and j == 4, "history clamps new")
	i, j, t = L.historyAt(times, 10.1)
	check((i == 2 and near(t, 0)) or (i == 1 and near(t, 1)), "history exact sample")
	local none = L.historyAt({}, 1)
	check(none == nil, "empty history")
end

print(("enemy_logic.spec: %d checks passed"):format(checks))
