--!strict
-- Pure enemy brain (CONTRACT §1.8, §2.6). Owner: B.
-- No Roblox globals, no requires: vectors are {x, y, z} arrays, time is a plain number (seconds),
-- the world is reached only through callbacks in `Sense` (line of sight, walkability).
-- EnemyService builds a Sense every brain tick, calls `step`, and executes the returned Action.
--
-- States (model attribute `State`): Idle, Alert, Flee, Tired, Chase, Return, Stunned, Dead.
--   Flee behaviour (Red):   Idle(wander) -> sees player -> Alert 0.5s -> Flee(Run) -> Tired(Rest)
--                           -> Flee again while threatened, else Idle.
--   Chase behaviour (White): Idle(wander) -> sees player or is hit -> Alert 0.5s -> Chase (+melee)
--                           -> beyond Leash from home -> Return -> Idle.
-- Zones are horizontal circles (x/z) around Home; y is ignored by zone math.

local EnemyLogic = {}

export type Vec3 = { number }

export type Config = {
	Speed: number,
	RunSpeed: number,
	Sight: number,
	Leash: number?,
	Flee: { Run: number, Rest: number, RestSpeed: number }?,
	Melee: { Damage: number, Interval: number, Range: number }?,
}

export type PlayerInfo = { Id: number, Pos: Vec3 }

export type Sense = {
	Now: number,
	Pos: Vec3,
	Players: { PlayerInfo }, -- only targetable (Alive) players
	CanSee: ((id: number) -> boolean)?, -- line of sight to player id; nil = always visible
	Walkable: ((from: Vec3, to: Vec3) -> boolean)?, -- can walk straight from -> to; nil = always
	Stuck: boolean?, -- mover made no progress toward the last goal
	Random: (() -> number)?, -- [0, 1); default math.random
}

export type Action = {
	State: string,
	Goal: Vec3?, -- nil = stand still
	Speed: number,
	Attack: number?, -- player id to hit this tick
	Alert: boolean, -- true once, on the tick the "!" should pop
	Face: Vec3?, -- turn toward this point (alert / melee)
}

export type Brain = {
	Kind: string,
	Behaviour: string, -- "Flee" | "Chase" | "None"
	State: string,
	Home: Vec3,
	Zone: number,
	Since: number,
	Until: number, -- end of timed states (Alert, Flee, Tired, Stunned, Return timeout)
	Goal: Vec3?,
	GoalAt: number,
	ReplanAt: number,
	PauseUntil: number,
	Target: number?, -- player id being chased / fled from
	ThreatPos: Vec3?, -- last known threat position (flee keeps going if players vanish)
	NextAttack: number,
	AfterAlert: string,
	AlertPending: boolean,
}

-- Tuning shared by every kind ------------------------------------------------------
EnemyLogic.ALERT_SECONDS = 0.5
EnemyLogic.ARRIVE = 2 -- goal reached (horizontal studs)
EnemyLogic.MIN_WANDER_STEP = 3
EnemyLogic.WANDER_FILL = 0.85 -- wander goals stay inside this fraction of the zone
EnemyLogic.WANDER_TIMEOUT = 8
EnemyLogic.PAUSE_MIN = 0.8
EnemyLogic.PAUSE_MAX = 2.5
EnemyLogic.FLEE_EDGE = 0.9 -- flee goals stay inside this fraction of the zone
EnemyLogic.FLEE_LOOKAHEAD = 16
EnemyLogic.FLEE_REPLAN = 0.5
EnemyLogic.FLEE_SAMPLES = 16
EnemyLogic.FLEE_MIN_STEP = 2
EnemyLogic.ATTACK_WINDUP = 0.35 -- first swing after the chase starts
EnemyLogic.RETURN_TIMEOUT = 20
EnemyLogic.LEASH_REAGGRO = 0.8 -- hit while returning re-aggroes only inside this fraction of Leash

local TAU = 2 * math.pi

-- Vector helpers ----------------------------------------------------------------------
function EnemyLogic.vec(x: number, y: number, z: number): Vec3
	return { x, y, z }
end

local function copy(v: Vec3): Vec3
	return { v[1], v[2], v[3] }
end

function EnemyLogic.flatDistance(a: Vec3, b: Vec3): number
	local dx, dz = a[1] - b[1], a[3] - b[3]
	return math.sqrt(dx * dx + dz * dz)
end

function EnemyLogic.distance(a: Vec3, b: Vec3): number
	local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local flatDistance = EnemyLogic.flatDistance
local distance = EnemyLogic.distance

-- Zone math -----------------------------------------------------------------------------
-- Closest point to p inside the zone circle (keeps p's y).
function EnemyLogic.clampToZone(p: Vec3, home: Vec3, zone: number): Vec3
	local dx, dz = p[1] - home[1], p[3] - home[3]
	local d = math.sqrt(dx * dx + dz * dz)
	if d <= zone or d < 1e-9 then
		return copy(p)
	end
	local k = zone / d
	return { home[1] + dx * k, p[2], home[3] + dz * k }
end

function EnemyLogic.inZone(p: Vec3, home: Vec3, zone: number): boolean
	return flatDistance(p, home) <= zone + 1e-6
end

-- Uniform random point in the zone disc (y = home y).
function EnemyLogic.randomPointInZone(home: Vec3, zone: number, rand: () -> number): Vec3
	local r = zone * math.sqrt(rand())
	local a = rand() * TAU
	return { home[1] + math.cos(a) * r, home[2], home[3] + math.sin(a) * r }
end

-- Horizontal distance from p to segment a-b.
function EnemyLogic.segmentDistance(a: Vec3, b: Vec3, p: Vec3): number
	local abx, abz = b[1] - a[1], b[3] - a[3]
	local len2 = abx * abx + abz * abz
	local t = 0
	if len2 > 1e-12 then
		t = math.clamp(((p[1] - a[1]) * abx + (p[3] - a[3]) * abz) / len2, 0, 1)
	end
	local cx, cz = a[1] + abx * t, a[3] + abz * t
	local dx, dz = p[1] - cx, p[3] - cz
	return math.sqrt(dx * dx + dz * dz)
end

-- Where to run from `threat`, staying inside the zone.
-- Candidates: points LOOKAHEAD studs away in 16 directions (clamped into the zone, which makes
-- the enemy slide along the edge when cornered) plus 16 points on the zone rim. A candidate is
-- rejected when the straight run would get closer to the threat than `safe` (never run past the
-- player). The survivor farthest from the threat wins; `walkable` filters blocked runs. If no
-- safe run exists, the run passing farthest from the threat is used (never freeze).
-- Returns nil only when nothing is walkable / no candidate moves at least FLEE_MIN_STEP.
function EnemyLogic.fleePoint(
	pos: Vec3,
	threat: Vec3,
	home: Vec3,
	zone: number,
	walkable: ((from: Vec3, to: Vec3) -> boolean)?
): Vec3?
	local radius = zone * EnemyLogic.FLEE_EDGE
	local ax, az = pos[1] - threat[1], pos[3] - threat[3]
	local d0 = math.sqrt(ax * ax + az * az)
	if d0 < 1e-3 then
		ax, az = pos[1] - home[1], pos[3] - home[3]
		if math.sqrt(ax * ax + az * az) < 1e-3 then
			ax, az = 1, 0
		end
	end
	local base = math.atan2(az, ax)
	local safe = math.min(d0, math.max(6, d0 * 0.75))
	local lookahead = EnemyLogic.FLEE_LOOKAHEAD

	local candidates: { { P: Vec3, Score: number } } = {}
	local risky: { { P: Vec3, Score: number } } = {} -- runs that pass near the threat (fallback)
	local function consider(x: number, z: number)
		local q = EnemyLogic.clampToZone({ x, pos[2], z }, home, radius)
		if flatDistance(q, pos) < EnemyLogic.FLEE_MIN_STEP then
			return
		end
		local closest = EnemyLogic.segmentDistance(pos, q, threat)
		if closest < safe - 0.05 then
			table.insert(risky, { P = q, Score = closest * 1000 + flatDistance(q, threat) })
			return
		end
		table.insert(candidates, { P = q, Score = flatDistance(q, threat) })
	end

	local n = EnemyLogic.FLEE_SAMPLES
	for k = 0, n - 1 do
		local a = base + (k / n) * TAU
		consider(pos[1] + math.cos(a) * lookahead, pos[3] + math.sin(a) * lookahead)
		local r = (k / n) * TAU
		consider(home[1] + math.cos(r) * radius, home[3] + math.sin(r) * radius)
	end

	local function byScore(x: { P: Vec3, Score: number }, y: { P: Vec3, Score: number }): boolean
		return x.Score > y.Score
	end
	table.sort(candidates, byScore)
	for _, c in ipairs(candidates) do
		if not walkable or walkable(pos, c.P) then
			return c.P
		end
	end
	-- Every safe run is blocked (e.g. knocked out of the zone with the player in between):
	-- take the run that keeps the most room from the threat instead of freezing.
	table.sort(risky, byScore)
	for _, c in ipairs(risky) do
		if not walkable or walkable(pos, c.P) then
			return c.P
		end
	end
	return nil
end

-- Players ---------------------------------------------------------------------------
local function findPlayer(players: { PlayerInfo }, id: number?): PlayerInfo?
	if id == nil then
		return nil
	end
	for _, p in ipairs(players) do
		if p.Id == id then
			return p
		end
	end
	return nil
end

function EnemyLogic.nearestPlayer(players: { PlayerInfo }, pos: Vec3): (PlayerInfo?, number)
	local best, bestD = nil, math.huge
	for _, p in ipairs(players) do
		local d = distance(pos, p.Pos)
		if d < bestD then
			best, bestD = p, d
		end
	end
	return best, bestD
end

-- Nearest player within `range` that is visible. Line of sight is checked nearest-first so
-- the caller's (budgeted) raycasts stop at the first visible player.
function EnemyLogic.detect(players: { PlayerInfo }, pos: Vec3, range: number, canSee: ((id: number) -> boolean)?): PlayerInfo?
	local inRange: { { P: PlayerInfo, D: number } } = {}
	for _, p in ipairs(players) do
		local d = distance(pos, p.Pos)
		if d <= range then
			table.insert(inRange, { P = p, D = d })
		end
	end
	table.sort(inRange, function(a, b)
		return a.D < b.D
	end)
	for _, entry in ipairs(inRange) do
		if not canSee or canSee(entry.P.Id) then
			return entry.P
		end
	end
	return nil
end

-- Brain ---------------------------------------------------------------------------------
local function behaviourOf(cfg: Config): string
	if cfg.Flee then
		return "Flee"
	elseif cfg.Melee and cfg.Leash then
		return "Chase"
	end
	return "None"
end

function EnemyLogic.new(kind: string, cfg: Config, home: Vec3, zone: number, now: number): Brain
	return {
		Kind = kind,
		Behaviour = behaviourOf(cfg),
		State = "Idle",
		Home = copy(home),
		Zone = math.max(0, zone),
		Since = now,
		Until = now,
		Goal = nil,
		GoalAt = now,
		ReplanAt = now,
		PauseUntil = now,
		Target = nil,
		ThreatPos = nil,
		NextAttack = now,
		AfterAlert = "Idle",
		AlertPending = false,
	}
end

local function enter(brain: Brain, cfg: Config, state: string, now: number)
	brain.State = state
	brain.Since = now
	brain.Goal = nil
	brain.ReplanAt = now
	if state == "Alert" then
		brain.Until = now + EnemyLogic.ALERT_SECONDS
		brain.AlertPending = true
	elseif state == "Flee" then
		brain.Until = now + (if cfg.Flee then cfg.Flee.Run else 0)
	elseif state == "Tired" then
		brain.Until = now + (if cfg.Flee then cfg.Flee.Rest else 0)
	elseif state == "Chase" then
		brain.NextAttack = math.max(brain.NextAttack, now + EnemyLogic.ATTACK_WINDUP)
	elseif state == "Return" then
		brain.Until = now + EnemyLogic.RETURN_TIMEOUT
	elseif state == "Idle" then
		brain.PauseUntil = now + 0.3
	end
end

local function alert(brain: Brain, cfg: Config, now: number)
	enter(brain, cfg, "Alert", now)
	brain.AfterAlert = if brain.Behaviour == "Flee" then "Flee" else "Chase"
end

local function threatened(brain: Brain, cfg: Config, sense: Sense): PlayerInfo?
	return EnemyLogic.detect(sense.Players, sense.Pos, cfg.Sight, sense.CanSee)
end

local function defaultRandom(): number
	return math.random()
end

local function randomOf(sense: Sense): () -> number
	return sense.Random or defaultRandom
end

local function wander(brain: Brain, cfg: Config, sense: Sense, action: Action)
	local now, pos = sense.Now, sense.Pos
	local rand = randomOf(sense)
	local goal = brain.Goal
	if goal then
		if flatDistance(pos, goal) <= EnemyLogic.ARRIVE or now - brain.GoalAt > EnemyLogic.WANDER_TIMEOUT or sense.Stuck then
			brain.Goal = nil
			brain.PauseUntil = now + EnemyLogic.PAUSE_MIN + rand() * (EnemyLogic.PAUSE_MAX - EnemyLogic.PAUSE_MIN)
		end
	end
	if brain.Goal == nil and now >= brain.PauseUntil then
		for _ = 1, 6 do
			local c = EnemyLogic.randomPointInZone(brain.Home, brain.Zone * EnemyLogic.WANDER_FILL, rand)
			if
				flatDistance(c, pos) >= EnemyLogic.MIN_WANDER_STEP
				and (sense.Walkable == nil or (sense.Walkable :: (Vec3, Vec3) -> boolean)(pos, c))
			then
				brain.Goal = c
				brain.GoalAt = now
				break
			end
		end
		if brain.Goal == nil then
			brain.PauseUntil = now + 1
		end
	end
	action.Goal = brain.Goal
	action.Speed = cfg.Speed
end

local function fleeMove(brain: Brain, sense: Sense, action: Action)
	local now, pos = sense.Now, sense.Pos
	local threat = EnemyLogic.nearestPlayer(sense.Players, pos)
	if threat then
		brain.ThreatPos = copy(threat.Pos)
	end
	local goal = brain.Goal
	local replan = goal == nil
		or now >= brain.ReplanAt
		or sense.Stuck == true
		or flatDistance(pos, goal :: Vec3) <= EnemyLogic.ARRIVE
	if replan then
		local tp = brain.ThreatPos
		if tp then
			brain.Goal = EnemyLogic.fleePoint(pos, tp, brain.Home, brain.Zone, sense.Walkable)
		else
			brain.Goal = EnemyLogic.randomPointInZone(brain.Home, brain.Zone * EnemyLogic.WANDER_FILL, randomOf(sense))
		end
		brain.ReplanAt = now + EnemyLogic.FLEE_REPLAN
	end
	action.Goal = brain.Goal
end

-- Each handler fills `action` and returns true, or changes state and returns false so the
-- new state is evaluated in the same tick.
type Handler = (brain: Brain, cfg: Config, sense: Sense, action: Action) -> boolean

local handlers: { [string]: Handler } = {}

handlers.Idle = function(brain, cfg, sense, action)
	if brain.Behaviour ~= "None" then
		local seen = threatened(brain, cfg, sense)
		if seen then
			brain.Target = seen.Id
			brain.ThreatPos = copy(seen.Pos)
			alert(brain, cfg, sense.Now)
			return false
		end
	end
	wander(brain, cfg, sense, action)
	return true
end

handlers.Alert = function(brain, cfg, sense, action)
	if sense.Now >= brain.Until then
		enter(brain, cfg, brain.AfterAlert, sense.Now)
		return false
	end
	local t = findPlayer(sense.Players, brain.Target)
	if t then
		action.Face = copy(t.Pos)
	end
	return true
end

handlers.Flee = function(brain, cfg, sense, action)
	if sense.Now >= brain.Until then
		enter(brain, cfg, "Tired", sense.Now)
		return false
	end
	fleeMove(brain, sense, action)
	action.Speed = cfg.RunSpeed
	return true
end

handlers.Tired = function(brain, cfg, sense, action)
	if sense.Now >= brain.Until then
		if threatened(brain, cfg, sense) then
			enter(brain, cfg, "Flee", sense.Now)
		else
			enter(brain, cfg, "Idle", sense.Now)
		end
		return false
	end
	fleeMove(brain, sense, action)
	action.Speed = if cfg.Flee then cfg.Flee.RestSpeed else cfg.Speed
	return true
end

handlers.Chase = function(brain, cfg, sense, action)
	local pos = sense.Pos
	if cfg.Leash and flatDistance(pos, brain.Home) > cfg.Leash then
		brain.Target = nil
		enter(brain, cfg, "Return", sense.Now)
		return false
	end
	local target = findPlayer(sense.Players, brain.Target)
	if not target then
		target = threatened(brain, cfg, sense)
		if not target then
			brain.Target = nil
			enter(brain, cfg, "Return", sense.Now)
			return false
		end
		brain.Target = target.Id
	end
	local t = target :: PlayerInfo
	local d = distance(pos, t.Pos)
	local melee = cfg.Melee
	local range = if melee then melee.Range else 0
	action.Speed = cfg.RunSpeed
	if melee and d <= range then
		action.Face = copy(t.Pos)
		if sense.Now >= brain.NextAttack then
			action.Attack = t.Id
			brain.NextAttack = sense.Now + melee.Interval
		end
	end
	if d > range * 0.6 then
		action.Goal = copy(t.Pos)
	else
		action.Face = copy(t.Pos)
	end
	return true
end

handlers.Return = function(brain, cfg, sense, action)
	local d = flatDistance(sense.Pos, brain.Home)
	local arrive = math.max(2.5, math.min(brain.Zone * 0.5, 5))
	if d <= arrive or sense.Now >= brain.Until then
		enter(brain, cfg, "Idle", sense.Now)
		return false
	end
	action.Goal = copy(brain.Home)
	action.Speed = cfg.Speed
	return true
end

-- After a stun: chasers go back to their target, fleers run if threatened.
local function resume(brain: Brain, cfg: Config, sense: Sense)
	if brain.Behaviour == "Chase" and findPlayer(sense.Players, brain.Target) then
		enter(brain, cfg, "Chase", sense.Now)
	elseif brain.Behaviour == "Flee" and threatened(brain, cfg, sense) then
		enter(brain, cfg, "Flee", sense.Now)
	else
		enter(brain, cfg, "Idle", sense.Now)
	end
end

function EnemyLogic.step(brain: Brain, cfg: Config, sense: Sense): Action
	local action: Action = { State = brain.State, Goal = nil, Speed = 0, Attack = nil, Alert = false, Face = nil }
	if brain.State == "Dead" then
		return action
	end
	if brain.State == "Stunned" then
		if sense.Now < brain.Until then
			return action
		end
		resume(brain, cfg, sense)
	end
	for _ = 1, 4 do
		local handler = handlers[brain.State]
		if not handler then
			enter(brain, cfg, "Idle", sense.Now)
		elseif handler(brain, cfg, sense, action) then
			break
		end
	end
	action.State = brain.State
	if brain.AlertPending then
		action.Alert = true
		brain.AlertPending = false
	end
	return action
end

-- Events --------------------------------------------------------------------------------
-- The enemy was hit. Returns true when this hit alerted it ("!" will pop on the next step).
function EnemyLogic.damaged(brain: Brain, cfg: Config, now: number, pos: Vec3, attackerId: number?): boolean
	local state = brain.State
	if state == "Dead" then
		return false
	end
	if attackerId ~= nil then
		brain.Target = attackerId
	end
	if state == "Stunned" or brain.Behaviour == "None" then
		return false
	end
	if brain.Behaviour == "Flee" then
		if state == "Idle" then
			alert(brain, cfg, now)
			return true
		elseif state == "Tired" then
			enter(brain, cfg, "Flee", now)
		end
		return false
	end
	-- Chase
	if state == "Idle" then
		alert(brain, cfg, now)
		return true
	elseif state == "Return" then
		local leash = cfg.Leash or math.huge
		if flatDistance(pos, brain.Home) <= leash * EnemyLogic.LEASH_REAGGRO then
			alert(brain, cfg, now)
			return true
		end
	end
	return false
end

function EnemyLogic.stun(brain: Brain, now: number, seconds: number)
	if brain.State == "Dead" then
		return
	end
	brain.State = "Stunned"
	brain.Since = now
	brain.Until = now + math.max(0, seconds)
	brain.Goal = nil
	brain.AlertPending = false
end

function EnemyLogic.kill(brain: Brain)
	brain.State = "Dead"
	brain.Goal = nil
	brain.Target = nil
	brain.AlertPending = false
end

-- Position history ------------------------------------------------------------------------
-- times: ascending sample times. Returns the bracketing indices and blend factor for time t,
-- clamped to the recorded range (i == j means "use sample i"). nil when there are no samples.
function EnemyLogic.historyAt(times: { number }, t: number): (number?, number?, number)
	local n = #times
	if n == 0 then
		return nil, nil, 0
	end
	if t <= times[1] then
		return 1, 1, 0
	end
	if t >= times[n] then
		return n, n, 0
	end
	for i = n - 1, 1, -1 do
		local a, b = times[i], times[i + 1]
		if t >= a then
			local span = b - a
			return i, i + 1, if span > 1e-9 then (t - a) / span else 0
		end
	end
	return 1, 1, 0
end

return EnemyLogic
