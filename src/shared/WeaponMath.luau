--!strict
-- Pure weapon math (CONTRACT §2.7). No Roblox globals, no requires — tested with Lune.
-- Vectors are { x, y, z } number arrays. Owner: A.
--
-- Server flow (WeaponService):
--   1. shot gate  : round, ownership, life, rateOk(shotTime), ammo, checkShot(head, origin, dir)
--                   + head->origin line of sight (raycast, in the service)
--   2. shot spent : ammo -1, last shot time = shotTime
--   3. hit claim  : checkHit(origin, dir, point, range, enemyPos(rewindTime), radius)
--                   + origin->point line of sight (raycast, in the service)
local WeaponMath = {}

export type Vec3 = { number }

WeaponMath.RATE_SLACK = 0.1 -- shots may come 10% faster than 1/Rate
WeaponMath.MAX_REWIND = 0.4 -- lag compensation window (seconds)
WeaponMath.MAX_AHEAD = 0.1 -- client clock may run slightly ahead of the server
WeaponMath.MAX_ORIGIN_OFFSET = 8 -- studs between head and claimed origin
WeaponMath.MAX_ANGLE = 3 -- degrees between look direction and claimed hit point
WeaponMath.HIT_SLACK = 2.5 -- studs added to the enemy radius
WeaponMath.DIR_TOLERANCE = 0.02 -- | |dir| - 1 | allowed
WeaponMath.RANGE_SLACK = 2 -- studs added to weapon range
WeaponMath.POINT_MIN_DISTANCE = 1 -- below this the angle test is meaningless (point at muzzle)

-- Vector helpers ------------------------------------------------------------------
local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
WeaponMath.finite = finite

function WeaponMath.isVec(v: any): boolean
	if type(v) ~= "table" then
		return false
	end
	return finite(v[1]) and finite(v[2]) and finite(v[3])
end

function WeaponMath.sub(a: Vec3, b: Vec3): Vec3
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end

function WeaponMath.add(a: Vec3, b: Vec3): Vec3
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end

function WeaponMath.scale(a: Vec3, s: number): Vec3
	return { a[1] * s, a[2] * s, a[3] * s }
end

function WeaponMath.dot(a: Vec3, b: Vec3): number
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

function WeaponMath.length(a: Vec3): number
	return math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
end

function WeaponMath.distance(a: Vec3, b: Vec3): number
	return WeaponMath.length(WeaponMath.sub(a, b))
end

function WeaponMath.unit(a: Vec3): Vec3?
	local len = WeaponMath.length(a)
	if len < 1e-6 or not finite(len) then
		return nil
	end
	return { a[1] / len, a[2] / len, a[3] / len }
end

-- Angle between two vectors in degrees (0 when either is ~zero).
function WeaponMath.angleDeg(a: Vec3, b: Vec3): number
	local la, lb = WeaponMath.length(a), WeaponMath.length(b)
	if la < 1e-6 or lb < 1e-6 then
		return 0
	end
	local c = math.clamp(WeaponMath.dot(a, b) / (la * lb), -1, 1)
	return math.deg(math.acos(c))
end

-- Timing --------------------------------------------------------------------------
-- Minimum seconds between two shots for a weapon firing `rate` shots/second.
function WeaponMath.minInterval(rate: number, slack: number?): number
	if not finite(rate) or rate <= 0 then
		return math.huge
	end
	return (1 / rate) * (1 - (slack or WeaponMath.RATE_SLACK))
end

-- Time used for the rate check: the client's claimed send time, clamped to a small window around
-- the server clock so network jitter does not reject honest shots, while forged times gain at most
-- MAX_REWIND + MAX_AHEAD seconds once (shot times must keep increasing).
function WeaponMath.shotTime(claimed: any, now: number, maxRewind: number?, maxAhead: number?): number
	if not finite(claimed) then
		return now
	end
	return math.clamp(claimed, now - (maxRewind or WeaponMath.MAX_REWIND), now + (maxAhead or WeaponMath.MAX_AHEAD))
end

-- Time used for lag compensation: clamp(T, now - 0.4, now).
function WeaponMath.rewindTime(claimed: any, now: number, maxRewind: number?): number
	if not finite(claimed) then
		return now
	end
	return math.clamp(claimed, now - (maxRewind or WeaponMath.MAX_REWIND), now)
end

-- lastShot = shot time of the previous accepted shot with this weapon (nil = never fired).
function WeaponMath.rateOk(lastShot: number?, shotTime: number, rate: number, slack: number?): boolean
	if not finite(shotTime) then
		return false
	end
	if lastShot == nil then
		return true
	end
	return shotTime - lastShot >= WeaponMath.minInterval(rate, slack) - 1e-9
end

-- Shot gate -----------------------------------------------------------------------
-- Is the claimed shot physically possible? (origin near the head, unit direction)
function WeaponMath.checkShot(head: Vec3, origin: Vec3, dir: Vec3, maxOffset: number?): (boolean, string?)
	if not WeaponMath.isVec(head) or not WeaponMath.isVec(origin) then
		return false, "BadOrigin"
	end
	if not WeaponMath.isVec(dir) then
		return false, "BadDirection"
	end
	if WeaponMath.distance(head, origin) > (maxOffset or WeaponMath.MAX_ORIGIN_OFFSET) then
		return false, "OriginFar"
	end
	if math.abs(WeaponMath.length(dir) - 1) > WeaponMath.DIR_TOLERANCE then
		return false, "BadDirection"
	end
	return true, nil
end

-- Is the claimed hit point along the look direction and inside the weapon range?
function WeaponMath.checkAim(origin: Vec3, dir: Vec3, point: Vec3, range: number, maxAngle: number?): (boolean, string?)
	if not WeaponMath.isVec(point) then
		return false, "BadPoint"
	end
	if not WeaponMath.isVec(origin) or not WeaponMath.isVec(dir) then
		return false, "BadOrigin"
	end
	local offset = WeaponMath.sub(point, origin)
	local dist = WeaponMath.length(offset)
	if dist > range + WeaponMath.RANGE_SLACK then
		return false, "OutOfRange"
	end
	if dist >= WeaponMath.POINT_MIN_DISTANCE and WeaponMath.angleDeg(dir, offset) >= (maxAngle or WeaponMath.MAX_ANGLE) then
		return false, "AngleOff"
	end
	return true, nil
end

-- Was the enemy (at the rewound time) close enough to the claimed point?
function WeaponMath.checkLagComp(enemyPos: Vec3?, point: Vec3, radius: number, slack: number?): (boolean, string?)
	if enemyPos == nil or not WeaponMath.isVec(enemyPos) then
		return false, "NoHistory"
	end
	if not WeaponMath.isVec(point) then
		return false, "BadPoint"
	end
	local r = if finite(radius) and radius > 0 then radius else 0
	if WeaponMath.distance(enemyPos, point) > r + (slack or WeaponMath.HIT_SLACK) then
		return false, "EnemyFar"
	end
	return true, nil
end

-- Full hit claim check (everything except raycasts).
function WeaponMath.checkHit(
	origin: Vec3,
	dir: Vec3,
	point: Vec3,
	range: number,
	enemyPos: Vec3?,
	radius: number
): (boolean, string?)
	local ok, reason = WeaponMath.checkAim(origin, dir, point, range)
	if not ok then
		return false, reason
	end
	return WeaponMath.checkLagComp(enemyPos, point, radius)
end

-- Where a missed shot ends (for tracers).
function WeaponMath.missEnd(origin: Vec3, dir: Vec3, range: number): Vec3
	return WeaponMath.add(origin, WeaponMath.scale(dir, range))
end

-- Melee -----------------------------------------------------------------------------
export type MeleeCandidate = { Id: number, Pos: Vec3, Radius: number }

-- Pick the nearest candidate in front of `origin`.
-- range: max horizontal distance to the enemy centre; halfCone: degrees either side of `forward`
-- (the enemy radius widens the cone so a body overlapping the edge still counts);
-- maxDy: max height difference. Returns (id, flat unit direction origin->enemy) or nil.
function WeaponMath.meleePick(
	origin: Vec3,
	forward: Vec3,
	candidates: { MeleeCandidate },
	range: number,
	halfCone: number,
	maxDy: number?
): (number?, Vec3?)
	local flatForward = WeaponMath.unit({ forward[1], 0, forward[3] })
	if not flatForward then
		return nil, nil
	end
	local bestId: number?, bestDir: Vec3?, bestDist = nil, nil, math.huge
	for _, c in ipairs(candidates) do
		if WeaponMath.isVec(c.Pos) then
			local offset = WeaponMath.sub(c.Pos, origin)
			local flat = { offset[1], 0, offset[3] }
			local dist = WeaponMath.length(flat)
			local radius = if finite(c.Radius) and c.Radius > 0 then c.Radius else 0
			if dist <= range and math.abs(offset[2]) <= (maxDy or 6) then
				local inCone: boolean
				local dirToEnemy: Vec3
				if dist <= radius + 0.5 then
					-- Standing inside the enemy: always in front.
					inCone, dirToEnemy = true, flatForward
				else
					dirToEnemy = WeaponMath.unit(flat) or flatForward
					local widen = math.deg(math.atan(radius / dist))
					inCone = WeaponMath.angleDeg(flatForward, flat) <= halfCone + widen
				end
				if inCone and dist < bestDist then
					bestId, bestDir, bestDist = c.Id, dirToEnemy, dist
				end
			end
		end
	end
	return bestId, bestDir
end

-- Ammo --------------------------------------------------------------------------------
-- magSize nil = infinite (melee).
function WeaponMath.fullAmmo(magSize: number?, reserveMax: number?): (number, number)
	return magSize or 0, reserveMax or 0
end

function WeaponMath.hasAmmo(magSize: number?, mag: number): boolean
	if magSize == nil then
		return true
	end
	return mag >= 1
end

function WeaponMath.spend(magSize: number?, mag: number): number
	if magSize == nil then
		return mag
	end
	return math.max(0, mag - 1)
end

function WeaponMath.canReload(magSize: number?, mag: number, reserve: number): boolean
	if magSize == nil then
		return false
	end
	return mag < magSize and reserve > 0
end

-- Returns (newMag, newReserve) after a full reload.
function WeaponMath.reload(magSize: number?, mag: number, reserve: number): (number, number)
	if magSize == nil then
		return mag, reserve
	end
	local take = math.max(0, math.min(magSize - mag, reserve))
	return mag + take, reserve - take
end

-- Ammo pickups: add `percent`% of the weapon's total capacity (mag + reserve) to the reserve,
-- capped at reserveMax + whatever is missing from the magazine (never above full capacity).
function WeaponMath.addPercent(magSize: number?, reserveMax: number?, mag: number, reserve: number, percent: number): number
	if magSize == nil or not finite(percent) or percent <= 0 then
		return reserve
	end
	local maxReserve = reserveMax or 0
	local capacity = magSize + maxReserve
	local add = math.ceil(capacity * percent / 100)
	local cap = maxReserve + math.max(0, magSize - mag)
	return math.min(cap, reserve + add)
end

-- Loadout -------------------------------------------------------------------------------
-- Ordered weapon list: every id in `order` that is a default, owned, or a round pickup.
function WeaponMath.loadout(
	order: { string },
	default: { string },
	owned: { [string]: boolean }?,
	roundOnly: { [string]: boolean }?
): { string }
	local want: { [string]: boolean } = {}
	for _, id in ipairs(default) do
		want[id] = true
	end
	if owned then
		for id, has in pairs(owned) do
			if has == true then
				want[id] = true
			end
		end
	end
	if roundOnly then
		for id, has in pairs(roundOnly) do
			if has == true then
				want[id] = true
			end
		end
	end
	local out = {}
	for _, id in ipairs(order) do
		if want[id] then
			table.insert(out, id)
		end
	end
	return out
end

function WeaponMath.joinList(ids: { string }): string
	return table.concat(ids, ",")
end

function WeaponMath.parseList(text: any): { string }
	local out = {}
	if type(text) ~= "string" then
		return out
	end
	for id in string.gmatch(text, "[^,]+") do
		table.insert(out, id)
	end
	return out
end

-- Next weapon in a list (wraps around). Returns the first one if `current` is not in the list.
function WeaponMath.cycle(list: { string }, current: string?, step: number?): string?
	if #list == 0 then
		return nil
	end
	local index = if current then table.find(list, current) else nil
	if not index then
		return list[1]
	end
	local n = #list
	return list[((index - 1 + (step or 1)) % n) + 1]
end

-- Pickups -------------------------------------------------------------------------------
-- Within pickup reach? Horizontal distance <= reach and height difference <= maxDy.
function WeaponMath.inReach(a: Vec3, b: Vec3, reach: number, maxDy: number?): boolean
	if not WeaponMath.isVec(a) or not WeaponMath.isVec(b) then
		return false
	end
	local dx, dz = a[1] - b[1], a[3] - b[3]
	return dx * dx + dz * dz <= reach * reach and math.abs(a[2] - b[2]) <= (maxDy or 6)
end

-- Explosions ----------------------------------------------------------------------------
-- Full damage inside the radius (original-game feel: no falloff). 0 outside.
function WeaponMath.blastDamage(center: Vec3, pos: Vec3, radius: number, damage: number): number
	if not WeaponMath.isVec(center) or not WeaponMath.isVec(pos) then
		return 0
	end
	if WeaponMath.distance(center, pos) <= radius then
		return damage
	end
	return 0
end

return WeaponMath
