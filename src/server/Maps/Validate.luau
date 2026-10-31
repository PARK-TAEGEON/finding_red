--!strict
-- Map validator (CONTRACT §3.7 map checks). Owner: D.
-- Pure: no Roblox globals, no requires. Used by tests/maps.spec.luau and tools/dump_maps.luau.
-- Rotated parts are handled conservatively through the AABB of the rotated box.

local Validate = {}

export type Vec3 = { number }
export type Box = {
	min: Vec3,
	max: Vec3,
	collide: boolean,
	name: string,
	shape: string,
	transparency: number,
	index: number,
}
export type Grid = {
	res: number,
	nx: number,
	nz: number,
	x0: number, -- world x of the grid's min edge
	z0: number,
	h: { number }, -- top height of the highest collidable part over each cell (0 = bare floor level or none)
	solid: { boolean }, -- false where nothing collidable covers the cell (hole)
}
export type Report = {
	name: string,
	errors: { string },
	warnings: { string },
	stats: { [string]: any },
	reach: string?, -- one char per grid cell: "1" reachable on foot, "0" not, "t" trap
	grid: Grid?,
}

Validate.MaxParts = 400
Validate.Climb = 5.5 -- ledge height a player surely climbs with a jump (default jump ≈ 7.2, keep margin)
Validate.ClimbMax = 7.5 -- ledge height a player might climb (used where reaching would be bad: arena escape)
Validate.EscapeReach = 12 -- horizontal distance from the arena edge checked for wall-top escapes
Validate.SpawnLiftMax = 4

Validate.Materials = {}
for _, m in
	{
		"Plastic", "SmoothPlastic", "Neon", "Wood", "WoodPlanks", "Marble", "Basalt", "Slate", "CrackedLava",
		"Concrete", "Limestone", "Granite", "Pavement", "Brick", "Pebble", "Cobblestone", "Rock", "Sandstone",
		"CorrodedMetal", "DiamondPlate", "Foil", "Metal", "Grass", "LeafyGrass", "Sand", "Fabric", "Snow", "Mud",
		"Ground", "Asphalt", "Salt", "Ice", "Glacier", "Glass", "ForceField", "Cardboard", "Carpet",
		"CeramicTiles", "ClayRoofTiles", "RoofShingles", "Leather", "Plaster", "Rubber",
	}
do
	Validate.Materials[m] = true
end

local SHAPES = { Block = true, Wedge = true, Cylinder = true, Ball = true }
local KNOWN_TAGS = {
	PlayerSpawn = true,
	EnemySpawn = true,
	Board = true,
	WeaponPickup = true,
	AmmoPickup = true,
	HealthPickup = true,
	KeyPickup = true,
	KeyDoor = true,
	VehicleSpawn = true,
	StartDoor = true,
	StartRoom = true,
}
local PICKUP_TAGS = { "WeaponPickup", "HealthPickup", "AmmoPickup" }

-- Start room part names (must match Kit.Names). Overhead parts are ceilings: not a floor for the height grid.
Validate.DoorName = "StartDoor"
Validate.RoofName = "StartRoomRoof"
Validate.Overhead = { StartRoomRoof = true, DoorLintel = true }

-- Math ------------------------------------------------------------------------------

-- Rotation matrix of CFrame.Angles(rx, ry, rz) (degrees) = Rx * Ry * Rz, row-major.
function Validate.rotMatrix(rot: Vec3?): { { number } }
	if rot == nil then
		return { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
	end
	local a, b, c = math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3])
	local ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
	local rx = { { 1, 0, 0 }, { 0, ca, -sa }, { 0, sa, ca } }
	local ry = { { cb, 0, sb }, { 0, 1, 0 }, { -sb, 0, cb } }
	local rz = { { cc, -sc, 0 }, { sc, cc, 0 }, { 0, 0, 1 } }
	local function mul(p: { { number } }, q: { { number } }): { { number } }
		local r = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
		for i = 1, 3 do
			for j = 1, 3 do
				r[i][j] = p[i][1] * q[1][j] + p[i][2] * q[2][j] + p[i][3] * q[3][j]
			end
		end
		return r
	end
	return mul(mul(rx, ry), rz)
end

function Validate.aabb(part: any): (Vec3, Vec3)
	local m = Validate.rotMatrix(part.Rot)
	local hx, hy, hz = part.Size[1] / 2, part.Size[2] / 2, part.Size[3] / 2
	local e = { 0, 0, 0 }
	for i = 1, 3 do
		e[i] = math.abs(m[i][1]) * hx + math.abs(m[i][2]) * hy + math.abs(m[i][3]) * hz
	end
	local p = part.Pos
	return { p[1] - e[1], p[2] - e[2], p[3] - e[3] }, { p[1] + e[1], p[2] + e[2], p[3] + e[3] }
end

function Validate.boxes(spec: any): { Box }
	local out: { Box } = {}
	for i, part in spec.Parts do
		local mn, mx = Validate.aabb(part)
		table.insert(out, {
			min = mn,
			max = mx,
			collide = part.Collide ~= false,
			name = part.Name or "",
			shape = part.Shape or "Block",
			transparency = part.Transparency or 0,
			index = i,
		})
	end
	return out
end

-- Highest collidable top at (x, z) that is <= maxY (+ eps). nil if none.
function Validate.groundAt(boxes: { Box }, x: number, z: number, maxY: number): number?
	local best: number? = nil
	for _, b in boxes do
		if b.collide and x >= b.min[1] and x <= b.max[1] and z >= b.min[3] and z <= b.max[3] then
			local top = b.max[2]
			if top <= maxY + 1e-3 and (best == nil or top > (best :: number)) then
				best = top
			end
		end
	end
	return best
end

-- First collidable box intersecting the open box (mn, mx); nil if clear.
function Validate.blocked(boxes: { Box }, mn: Vec3, mx: Vec3, ignore: { [string]: boolean }?): Box?
	for _, b in boxes do
		if b.collide and not (ignore and ignore[b.name]) then
			if
				mn[1] < b.max[1] - 1e-3
				and mx[1] > b.min[1] + 1e-3
				and mn[2] < b.max[2] - 1e-3
				and mx[2] > b.min[2] + 1e-3
				and mn[3] < b.max[3] - 1e-3
				and mx[3] > b.min[3] + 1e-3
			then
				return b
			end
		end
	end
	return nil
end

-- Segment a→b against collidable boxes (slab test). Returns the first box hit or nil.
function Validate.segmentHit(boxes: { Box }, a: Vec3, b: Vec3, ignore: { [string]: boolean }?): Box?
	local d = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
	local bestT = math.huge
	local best: Box? = nil
	for _, bx in boxes do
		if bx.collide and not (ignore and ignore[bx.name]) then
			local t0, t1 = 0, 1
			local ok = true
			for i = 1, 3 do
				if math.abs(d[i]) < 1e-9 then
					if a[i] <= bx.min[i] or a[i] >= bx.max[i] then
						ok = false
						break
					end
				else
					local u = (bx.min[i] - a[i]) / d[i]
					local v = (bx.max[i] - a[i]) / d[i]
					if u > v then
						u, v = v, u
					end
					if u > t0 then
						t0 = u
					end
					if v < t1 then
						t1 = v
					end
					if t0 > t1 then
						ok = false
						break
					end
				end
			end
			if ok and t0 < bestT then
				bestT = t0
				best = bx
			end
		end
	end
	return best
end

-- Height grid ------------------------------------------------------------------------

-- skip = part names left out (ceilings, an open door); keep = optional filter (false = leave the box out).
function Validate.grid(
	spec: any,
	boxes: { Box },
	res: number?,
	skip: { [string]: boolean }?,
	keep: ((Box) -> boolean)?
): Grid
	local r = res or 1
	local w, d = spec.Size[1], spec.Size[3]
	local nx, nz = math.ceil(w / r), math.ceil(d / r)
	local x0, z0 = -w / 2, -d / 2
	local h: { number } = table.create(nx * nz, -math.huge)
	local solid: { boolean } = table.create(nx * nz, false)
	local eps = 0.05
	for _, b in boxes do
		if b.collide and not (skip and skip[b.name]) and (keep == nil or keep(b)) then
			local i0 = math.max(1, math.floor((b.min[1] + eps - x0) / r) + 1)
			local i1 = math.min(nx, math.ceil((b.max[1] - eps - x0) / r))
			local k0 = math.max(1, math.floor((b.min[3] + eps - z0) / r) + 1)
			local k1 = math.min(nz, math.ceil((b.max[3] - eps - z0) / r))
			for k = k0, k1 do
				for i = i0, i1 do
					local idx = (k - 1) * nx + i
					if b.max[2] > h[idx] then
						h[idx] = b.max[2]
					end
					solid[idx] = true
				end
			end
		end
	end
	for i = 1, nx * nz do
		if not solid[i] then
			h[i] = -100
		end
	end
	return { res = r, nx = nx, nz = nz, x0 = x0, z0 = z0, h = h, solid = solid }
end

function Validate.cellOf(g: Grid, x: number, z: number): number?
	local i = math.floor((x - g.x0) / g.res) + 1
	local k = math.floor((z - g.z0) / g.res) + 1
	if i < 1 or i > g.nx or k < 1 or k > g.nz then
		return nil
	end
	return (k - 1) * g.nx + i
end

-- Flood fill over 4-neighbours. forward: may step from c to n when h[n] - h[c] <= climb.
-- reverse = true walks the edges backwards (cells that can reach a start).
function Validate.flood(g: Grid, starts: { number }, climb: number, reverse: boolean?): { boolean }
	local seen: { boolean } = table.create(g.nx * g.nz, false)
	local queue: { number } = {}
	for _, s in starts do
		if g.solid[s] and not seen[s] then
			seen[s] = true
			table.insert(queue, s)
		end
	end
	local head = 1
	while head <= #queue do
		local c = queue[head]
		head += 1
		local ci = (c - 1) % g.nx + 1
		local ck = (c - 1) // g.nx + 1
		local hc = g.h[c]
		for dir = 1, 4 do
			local ni, nk = ci, ck
			if dir == 1 then
				ni += 1
			elseif dir == 2 then
				ni -= 1
			elseif dir == 3 then
				nk += 1
			else
				nk -= 1
			end
			if ni >= 1 and ni <= g.nx and nk >= 1 and nk <= g.nz then
				local n = (nk - 1) * g.nx + ni
				if not seen[n] and g.solid[n] then
					local rise = if reverse then hc - g.h[n] else g.h[n] - hc
					if rise <= climb then
						seen[n] = true
						table.insert(queue, n)
					end
				end
			end
		end
	end
	return seen
end

-- Main check -------------------------------------------------------------------------

local function fmt(v: Vec3): string
	return string.format("(%.1f, %.1f, %.1f)", v[1], v[2], v[3])
end

local function isColor(s: any): boolean
	return type(s) == "string" and string.match(s, "^#%x%x%x%x%x%x$") ~= nil
end

-- "x,y,z" -> {x, y, z} (positive numbers) or nil
function Validate.parseSize(s: any): Vec3?
	if type(s) ~= "string" then
		return nil
	end
	local a, b, c = string.match(s, "^%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*$")
	local x, y, z = tonumber(a), tonumber(b), tonumber(c)
	if x == nil or y == nil or z == nil or x <= 0 or y <= 0 or z <= 0 then
		return nil
	end
	return { x :: number, y :: number, z :: number }
end

local function isVec(v: any): boolean
	if type(v) ~= "table" or #v ~= 3 then
		return false
	end
	for i = 1, 3 do
		local n = v[i]
		if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
			return false
		end
	end
	return true
end

export type Options = {
	stage: boolean?, -- stage rules (Board = 1, red weight > 0); lobby otherwise
	maxParts: number?,
}

function Validate.run(spec: any, opts: Options?): Report
	local o: Options = opts or {}
	local isStage = o.stage ~= false
	local errors: { string } = {}
	local warnings: { string } = {}
	local stats: { [string]: any } = {}
	local name = if type(spec) == "table" and type(spec.Name) == "string" then spec.Name else "?"
	local report: Report = { name = name, errors = errors, warnings = warnings, stats = stats }
	local function err(s: string)
		table.insert(errors, name .. ": " .. s)
	end
	local function warn(s: string)
		table.insert(warnings, name .. ": " .. s)
	end

	-- Schema ----------------------------------------------------------------------
	if type(spec) ~= "table" then
		err("spec is not a table")
		return report
	end
	if type(spec.Name) ~= "string" or spec.Name == "" then
		err("missing Name")
	end
	if not isVec(spec.Size) or spec.Size[1] <= 0 or spec.Size[2] <= 0 or spec.Size[3] <= 0 then
		err("bad Size")
		return report
	end
	if type(spec.Parts) ~= "table" or type(spec.Markers) ~= "table" then
		err("Parts/Markers must be arrays")
		return report
	end
	local schemaOk = true
	for i, p in spec.Parts do
		local where = string.format("part %d (%s)", i, tostring(p.Name))
		if not SHAPES[p.Shape] then
			err(where .. " bad Shape " .. tostring(p.Shape))
			schemaOk = false
		end
		if not isVec(p.Size) or p.Size[1] <= 0 or p.Size[2] <= 0 or p.Size[3] <= 0 then
			err(where .. " bad Size")
			schemaOk = false
		end
		if not isVec(p.Pos) then
			err(where .. " bad Pos")
			schemaOk = false
		end
		if p.Rot ~= nil and not isVec(p.Rot) then
			err(where .. " bad Rot")
			schemaOk = false
		end
		if not isColor(p.Color) then
			err(where .. " bad Color " .. tostring(p.Color))
		end
		if not Validate.Materials[p.Material] then
			err(where .. " unknown Material " .. tostring(p.Material))
		end
		if p.Transparency ~= nil and (type(p.Transparency) ~= "number" or p.Transparency < 0 or p.Transparency > 1) then
			err(where .. " bad Transparency")
		end
		if p.Collide ~= nil and type(p.Collide) ~= "boolean" then
			err(where .. " bad Collide")
		end
	end
	if not schemaOk then
		return report
	end
	local markersOk = true
	for i, m in spec.Markers do
		local where = string.format("marker %d (%s)", i, tostring(m.Tag))
		if type(m.Tag) ~= "string" or m.Tag == "" then
			err(where .. " missing Tag")
			markersOk = false
		elseif not KNOWN_TAGS[m.Tag] then
			warn(where .. " unknown tag")
		end
		if not isVec(m.Pos) then
			err(where .. " bad Pos")
			markersOk = false
		end
		if m.Rot ~= nil and not isVec(m.Rot) then
			err(where .. " bad Rot")
		end
		if m.Id ~= nil and (type(m.Id) ~= "string" or m.Id == "") then
			err(where .. " bad Id")
		end
		if m.Attr ~= nil then
			if type(m.Attr) ~= "table" then
				err(where .. " Attr must be a table")
			else
				for k, v in m.Attr do
					local tv = type(v)
					if type(k) ~= "string" or (tv ~= "string" and tv ~= "number" and tv ~= "boolean") then
						err(where .. " bad Attr " .. tostring(k))
					end
				end
			end
		end
	end
	if not markersOk then
		return report
	end

	-- Counts -----------------------------------------------------------------------
	local maxParts = o.maxParts or Validate.MaxParts
	stats.parts = #spec.Parts
	if #spec.Parts >= maxParts then
		err(string.format("%d parts (limit < %d)", #spec.Parts, maxParts))
	end
	local byTag: { [string]: { any } } = {}
	for _, m in spec.Markers do
		byTag[m.Tag] = byTag[m.Tag] or {}
		table.insert(byTag[m.Tag], m)
	end
	local function list(tag: string): { any }
		return byTag[tag] or {}
	end
	local counts = {}
	for tag, l in byTag do
		counts[tag] = #l
	end
	stats.markers = counts
	if #list("PlayerSpawn") < 4 then
		err(string.format("needs >= 4 PlayerSpawn, has %d", #list("PlayerSpawn")))
	end
	if #list("Board") ~= 1 then
		err(string.format("needs exactly 1 Board, has %d", #list("Board")))
	end
	local redWeight, whiteCount, redMarkers = 0, 0, 0
	for _, m in list("EnemySpawn") do
		local a = m.Attr or {}
		if type(a.Kind) ~= "string" then
			err("EnemySpawn without Kind at " .. fmt(m.Pos))
			continue
		end
		if type(a.Zone) ~= "number" or a.Zone <= 0 then
			err("EnemySpawn needs Zone > 0 at " .. fmt(m.Pos))
		end
		if a.Kind == "Red" then
			redMarkers += 1
			if type(a.Weight) ~= "number" or a.Weight < 0 then
				err("Red marker needs numeric Weight at " .. fmt(m.Pos))
			else
				redWeight += a.Weight
			end
		else
			if type(a.Count) ~= "number" or a.Count < 1 or a.Count % 1 ~= 0 then
				err(a.Kind .. " marker needs integer Count >= 1 at " .. fmt(m.Pos))
			else
				whiteCount += a.Count
			end
		end
		if a.HasKey ~= nil and type(a.HasKey) ~= "boolean" then
			err("HasKey must be boolean")
		end
	end
	stats.redMarkers = redMarkers
	stats.redWeight = redWeight
	stats.otherEnemies = whiteCount
	if isStage and redWeight <= 0 then
		err("Red Weight sum must be > 0")
	end
	if not isStage and #list("EnemySpawn") > 0 then
		warn("lobby has EnemySpawn markers")
	end
	local ids: { [string]: boolean } = {}
	for _, tag in PICKUP_TAGS do
		for _, m in list(tag) do
			local a = m.Attr or {}
			if tag == "WeaponPickup" and (type(a.Weapon) ~= "string" or a.Weapon == "") then
				err("WeaponPickup without Weapon at " .. fmt(m.Pos))
			end
			if type(m.Id) ~= "string" then
				err(tag .. " without Id at " .. fmt(m.Pos))
			elseif ids[m.Id] then
				err("duplicate " .. tag .. " Id " .. m.Id)
			else
				ids[m.Id] = true
			end
		end
	end
	-- start room (v0.5): exactly one StartDoor and one StartRoom per stage
	local room: { min: Vec3, max: Vec3, center: Vec3 }? = nil
	local door = list("StartDoor")[1]
	if isStage then
		if #list("StartDoor") ~= 1 then
			err(string.format("needs exactly 1 StartDoor, has %d", #list("StartDoor")))
		end
		if #list("StartRoom") ~= 1 then
			err(string.format("needs exactly 1 StartRoom, has %d", #list("StartRoom")))
		end
	end
	local roomMarker = list("StartRoom")[1]
	if roomMarker then
		local size = Validate.parseSize((roomMarker.Attr or {}).Size)
		if size == nil then
			err("StartRoom needs Attr Size = \"x,y,z\" at " .. fmt(roomMarker.Pos))
		else
			local c, s = roomMarker.Pos, size :: Vec3
			room = {
				center = c,
				min = { c[1] - s[1] / 2, c[2] - s[2] / 2, c[3] - s[3] / 2 },
				max = { c[1] + s[1] / 2, c[2] + s[2] / 2, c[3] + s[3] / 2 },
			}
			stats.startRoom = string.format("%gx%gx%g", s[1], s[2], s[3])
		end
	end
	local function inRoom(p: Vec3, pad: number): boolean
		local r = room
		if r == nil then
			return false
		end
		return p[1] >= r.min[1] - pad
			and p[1] <= r.max[1] + pad
			and p[3] >= r.min[3] - pad
			and p[3] <= r.max[3] + pad
	end
	if room then
		for _, m in list("PlayerSpawn") do
			if not inRoom(m.Pos, 0) or m.Pos[2] < room.min[2] or m.Pos[2] > room.max[2] then
				err("PlayerSpawn outside the StartRoom at " .. fmt(m.Pos))
			end
		end
		if door and not inRoom(door.Pos, 2.5) then
			err("StartDoor is not on the StartRoom's wall at " .. fmt(door.Pos))
		end
	end
	local anyIds: { [string]: boolean } = {}
	for _, m in spec.Markers do
		if m.Id then
			if anyIds[m.Id] then
				warn("duplicate marker Id " .. m.Id)
			end
			anyIds[m.Id] = true
		end
	end

	-- Geometry -------------------------------------------------------------------------
	local boxes = Validate.boxes(spec)
	local hw, hd, hh = spec.Size[1] / 2, spec.Size[3] / 2, spec.Size[2]
	for _, m in spec.Markers do
		local p = m.Pos
		if math.abs(p[1]) > hw or math.abs(p[3]) > hd or p[2] < -1 or p[2] > hh then
			err(m.Tag .. " outside map bounds at " .. fmt(p))
		end
		-- the Board marker becomes the panel inside its own frame: ignore the frame for it
		-- the StartDoor marker sits inside the door it names
		local ignore = if m.Tag == "Board"
			then { BoardFrame = true }
			elseif m.Tag == "StartDoor" then { [Validate.DoorName] = true }
			else nil
		local inside = Validate.blocked(
			boxes,
			{ p[1] - 0.05, p[2] - 0.05, p[3] - 0.05 },
			{ p[1] + 0.05, p[2] + 0.05, p[3] + 0.05 },
			ignore
		)
		if inside then
			err(string.format("%s at %s buried in part %d (%s)", m.Tag, fmt(p), inside.index, inside.name))
		end
	end

	local bodyHeight: { [string]: number } =
		{ PlayerSpawn = 5, EnemySpawn = 5, WeaponPickup = 3, HealthPickup = 3, AmmoPickup = 3 }
	local groundOf: { [any]: number } = {}
	for _, tag in { "PlayerSpawn", "EnemySpawn", "WeaponPickup", "HealthPickup", "AmmoPickup" } do
		local bodyH = bodyHeight[tag]
		for _, m in list(tag) do
			local p = m.Pos
			local g = Validate.groundAt(boxes, p[1], p[3], p[2])
			if g == nil then
				err(tag .. " has no floor below at " .. fmt(p))
				continue
			end
			local gap = p[2] - (g :: number)
			if gap < 0 or gap > Validate.SpawnLiftMax then
				err(string.format("%s floor is %.1f below at %s (needs 0-4)", tag, gap, fmt(p)))
			end
			groundOf[m] = g :: number
			local r = if bodyH < 5 then 0.5 else 1
			local hit = Validate.blocked(
				boxes,
				{ p[1] - r, (g :: number) + 0.3, p[3] - r },
				{ p[1] + r, (g :: number) + bodyH, p[3] + r }
			)
			if hit then
				err(string.format("%s at %s has no headroom (part %d %s)", tag, fmt(p), hit.index, hit.name))
			end
		end
	end

	-- Enemy zones: sampled rings must be walkable ground at the spawn's level, inside the arena.
	local zoneStats: { string } = {}
	for _, m in list("EnemySpawn") do
		local a = m.Attr or {}
		local g = groundOf[m]
		local zone = a.Zone
		if g == nil or type(zone) ~= "number" then
			continue
		end
		local total, okN, drops, outs = 0, 0, 0, 0
		local samples: { { number } } = { { m.Pos[1], m.Pos[3] } }
		for _, f in { 0.35, 0.7, 1.0 } do
			local n = if f < 0.5 then 8 else 16
			for k = 0, n - 1 do
				local ang = 2 * math.pi * k / n
				table.insert(samples, { m.Pos[1] + math.cos(ang) * zone * f, m.Pos[3] + math.sin(ang) * zone * f })
			end
		end
		for _, s in samples do
			total += 1
			local x, z = s[1], s[2]
			if math.abs(x) > hw - 1 or math.abs(z) > hd - 1 then
				outs += 1
				continue
			end
			local sg = Validate.groundAt(boxes, x, z, g + 0.6)
			if sg == nil or (sg :: number) < g - 0.6 then
				drops += 1
				continue
			end
			if Validate.blocked(boxes, { x - 0.4, g + 0.3, z - 0.4 }, { x + 0.4, g + 4.5, z + 0.4 }) == nil then
				okN += 1
			end
		end
		local frac = okN / total
		table.insert(zoneStats, string.format("%s@%.0f,%.0f:%.0f%%", tostring(a.Kind), m.Pos[1], m.Pos[3], frac * 100))
		if outs > 0 then
			err(string.format("%s zone %.0f at %s leaves the arena", tostring(a.Kind), zone, fmt(m.Pos)))
		end
		if drops > 0 then
			err(string.format("%s zone %.0f at %s hangs over a drop (%d samples)", tostring(a.Kind), zone, fmt(m.Pos), drops))
		end
		if frac < 0.6 then
			err(string.format("%s zone at %s only %.0f%% walkable", tostring(a.Kind), fmt(m.Pos), frac * 100))
		end
	end
	stats.zones = zoneStats

	-- Enemy zones must not reach into the start room (its walls included: interior + 1).
	if room then
		for _, m in list("EnemySpawn") do
			local zone = (m.Attr or {}).Zone
			if type(zone) == "number" then
				local px = math.clamp(m.Pos[1], room.min[1] - 1, room.max[1] + 1)
				local pz = math.clamp(m.Pos[3], room.min[3] - 1, room.max[3] + 1)
				local dd = math.sqrt((m.Pos[1] - px) ^ 2 + (m.Pos[3] - pz) ^ 2)
				if dd < zone then
					err(string.format("%s zone %.0f at %s overlaps the StartRoom", tostring(m.Attr.Kind), zone, fmt(m.Pos)))
				end
			end
		end
	end

	-- Reachability (start door open, ceilings ignored) ----------------------------------
	local reachSkip: { [string]: boolean } = table.clone(Validate.Overhead)
	reachSkip[Validate.DoorName] = true
	local grid = Validate.grid(spec, boxes, 1, reachSkip)
	report.grid = grid
	-- Under the start room roof nobody stands where the ceiling is closer than a body height: those cells
	-- (walls, a board's top edge) become walls, so the heightmap does not walk over the room's walls.
	local roofTop: number?, roofBottom: number? = nil, nil
	for _, b in boxes do
		if b.collide and b.name == Validate.RoofName then
			roofTop = math.max(roofTop or -math.huge, b.max[2])
			roofBottom = math.min(roofBottom or math.huge, b.min[2])
		end
	end
	local function capUnderRoof(g: Grid)
		if room == nil or roofBottom == nil then
			return
		end
		local cap = (roofBottom :: number) - 5
		for i = 1, g.nx * g.nz do
			if g.solid[i] and g.h[i] > cap then
				local x = g.x0 + ((i - 1) % g.nx + 0.5) * g.res
				local z = g.z0 + ((i - 1) // g.nx + 0.5) * g.res
				if inRoom({ x, 0, z }, 1) then
					g.h[i] = 1000
				end
			end
		end
	end
	capUnderRoof(grid)
	local starts: { number } = {}
	for _, m in list("PlayerSpawn") do
		local c = Validate.cellOf(grid, m.Pos[1], m.Pos[3])
		if c then
			table.insert(starts, c)
		end
	end
	local fwd = Validate.flood(grid, starts, Validate.Climb, false)
	local back = Validate.flood(grid, starts, Validate.Climb, true)
	local reachable, traps, solidCells = 0, 0, 0
	local chars = table.create(grid.nx * grid.nz, "0")
	for i = 1, grid.nx * grid.nz do
		if grid.solid[i] then
			solidCells += 1
		end
		if fwd[i] then
			reachable += 1
			if back[i] then
				chars[i] = "1"
			else
				chars[i] = "t"
				traps += 1
			end
		end
	end
	report.reach = table.concat(chars)
	stats.reachablePct = math.floor(reachable / math.max(1, solidCells) * 1000) / 10
	stats.trapCells = traps
	if traps > 0 then
		err(string.format("%d grid cells can be entered but not left (trap)", traps))
	end
	if solidCells < grid.nx * grid.nz then
		warn(string.format("%d grid cells have no floor", grid.nx * grid.nz - solidCells))
	end

	-- Arena escape: with the generous climb, no surface near the edge may get within a jump of the wall top.
	local perimTop: number? = nil
	for _, b in boxes do
		if b.collide and string.sub(b.name, 1, 9) == "Perimeter" then
			perimTop = math.max(perimTop or 0, b.max[2])
		end
	end
	local loose = Validate.flood(grid, starts, Validate.ClimbMax, false)
	if perimTop then
		local risky = 0
		local example = ""
		for i = 1, grid.nx * grid.nz do
			if loose[i] and grid.h[i] >= (perimTop :: number) - Validate.ClimbMax then
				local ci = (i - 1) % grid.nx
				local ck = (i - 1) // grid.nx
				local x = grid.x0 + (ci + 0.5) * grid.res
				local z = grid.z0 + (ck + 0.5) * grid.res
				local edge = math.min(hw - math.abs(x), hd - math.abs(z))
				if edge <= Validate.EscapeReach then
					risky += 1
					example = string.format("(%.0f, %.0f) top %.1f", x, z, grid.h[i])
				end
			end
		end
		stats.perimeterTop = perimTop
		if risky > 0 then
			err(string.format("%d cells near the edge are within a jump of the perimeter top, e.g. %s", risky, example))
		end
	else
		warn("no Perimeter parts: arena escape not checked")
	end

	-- Start room seal (door closed): from the spawns, even the generous climb never leaves the room,
	-- no enemy marker is visible, and nobody outside can climb onto the room's roof.
	local doorEye: Vec3? = nil
	if room then
		-- door stays solid; anything a player can walk under (bottom >= room floor + 5) is left out,
		-- so a wall that does not reach the floor shows up as a gap
		local underY = room.min[2] + 5
		local sealGrid = Validate.grid(spec, boxes, 1, Validate.Overhead, function(b: Box): boolean
			return b.min[2] < underY
		end)
		capUnderRoof(sealGrid)
		local inside = Validate.flood(sealGrid, starts, Validate.ClimbMax, false)
		local leaks, leakAt = 0, ""
		for i = 1, sealGrid.nx * sealGrid.nz do
			if inside[i] then
				local x = sealGrid.x0 + ((i - 1) % sealGrid.nx + 0.5) * sealGrid.res
				local z = sealGrid.z0 + ((i - 1) // sealGrid.nx + 0.5) * sealGrid.res
				if not inRoom({ x, 0, z }, 0.5) then
					leaks += 1
					leakAt = string.format("(%.0f, %.0f)", x, z)
				end
			end
		end
		stats.startRoomLeakCells = leaks
		if leaks > 0 then
			err(string.format("StartRoom is not sealed with the door closed: %d cells outside reachable, e.g. %s", leaks, leakAt))
		end
		local seen = 0
		for _, s in list("PlayerSpawn") do
			local e = { s.Pos[1], s.Pos[2] + 1.5, s.Pos[3] }
			for _, m in list("EnemySpawn") do
				if Validate.segmentHit(boxes, e, { m.Pos[1], m.Pos[2] + 1, m.Pos[3] }) == nil then
					seen += 1
				end
			end
		end
		if seen > 0 then
			err(string.format("%d enemy markers visible from inside the closed StartRoom", seen))
		end
		if roofTop then
			local climbable = 0
			for i = 1, grid.nx * grid.nz do
				if loose[i] and grid.h[i] >= (roofTop :: number) - Validate.ClimbMax then
					local x = grid.x0 + ((i - 1) % grid.nx + 0.5) * grid.res
					local z = grid.z0 + ((i - 1) // grid.nx + 0.5) * grid.res
					if inRoom({ x, 0, z }, 4) and not inRoom({ x, 0, z }, 0) then
						climbable += 1
					end
				end
			end
			if climbable > 0 then
				err(string.format("StartRoom roof can be climbed from %d cells", climbable))
			end
		end
		if door then
			-- eye of someone standing 3 studs outside the door on the arena side
			local c = room.center
			local dx, dz = door.Pos[1] - c[1], door.Pos[3] - c[3]
			local ux, uz = 0, 0
			if math.abs(dx) > math.abs(dz) then
				ux = if dx > 0 then 1 else -1
			else
				uz = if dz > 0 then 1 else -1
			end
			local dh = (door.Attr or {}).Height
			local floorY = door.Pos[2] - (if type(dh) == "number" then dh / 2 else 4)
			doorEye = { door.Pos[1] + ux * 3, floorY + 4.5, door.Pos[3] + uz * 3 }
			local dc = Validate.cellOf(grid, door.Pos[1] + ux * 3, door.Pos[3] + uz * 3)
			if dc == nil or not fwd[dc] then
				err("arena in front of the StartDoor not reachable from the spawns (door open)")
			end
		end
	end

	local function reachableAt(p: Vec3): boolean
		local c = Validate.cellOf(grid, p[1], p[3])
		return c ~= nil and fwd[c] == true
	end
	local eyes: { Vec3 } = {}
	for _, m in list("PlayerSpawn") do
		table.insert(eyes, { m.Pos[1], m.Pos[2] + 1.5, m.Pos[3] })
	end
	if doorEye then
		table.insert(eyes, doorEye :: Vec3)
	end
	for _, tag in PICKUP_TAGS do
		for _, m in list(tag) do
			if tag == "WeaponPickup" then
				table.insert(eyes, { m.Pos[1], m.Pos[2] + 2.5, m.Pos[3] })
			end
			if not reachableAt(m.Pos) then
				err(tag .. " not reachable on foot at " .. fmt(m.Pos))
			end
		end
	end
	local reachableEnemies, sniperOnly = 0, 0
	for _, m in list("EnemySpawn") do
		if reachableAt(m.Pos) then
			reachableEnemies += 1
		else
			local seen = false
			local target = { m.Pos[1], m.Pos[2] + 1, m.Pos[3] }
			for _, e in eyes do
				if Validate.segmentHit(boxes, e, target) == nil then
					seen = true
					break
				end
			end
			if seen then
				sniperOnly += 1
			else
				err("EnemySpawn neither reachable nor visible from a spawn/pickup at " .. fmt(m.Pos))
			end
		end
	end
	stats.enemyMarkersReachable = reachableEnemies
	stats.enemyMarkersShootOnly = sniperOnly

	-- Board visible from the spawns; Reds not all visible from the spawn centroid.
	local board = list("Board")[1]
	if board then
		local blockedFrom = 0
		for _, m in list("PlayerSpawn") do
			local e = { m.Pos[1], m.Pos[2] + 1.5, m.Pos[3] }
			local t = board.Pos
			local d = { t[1] - e[1], t[2] - e[2], t[3] - e[3] }
			local len = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
			local k = math.max(0, (len - 0.6) / len)
			local stop = { e[1] + d[1] * k, e[2] + d[2] * k, e[3] + d[3] * k }
			if Validate.segmentHit(boxes, e, stop, { BoardFrame = true }) then
				blockedFrom += 1
			end
		end
		stats.boardBlockedFrom = blockedFrom
		if blockedFrom > 0 then
			err(string.format("Board hidden from %d PlayerSpawn(s)", blockedFrom))
		end
	end
	local spawns = list("PlayerSpawn")
	if #spawns > 0 then
		local cx, cy, cz = 0, 0, 0
		for _, m in spawns do
			cx += m.Pos[1]
			cy += m.Pos[2]
			cz += m.Pos[3]
		end
		-- what the party sees from the spawns, or (with a start room) right outside the opened door
		local eye: Vec3 = doorEye or { cx / #spawns, cy / #spawns + 1.5, cz / #spawns }
		local visible = 0
		for _, m in list("EnemySpawn") do
			if m.Attr and m.Attr.Kind == "Red" then
				if Validate.segmentHit(boxes, eye, { m.Pos[1], m.Pos[2] + 1, m.Pos[3] }, { BoardFrame = true }) == nil then
					visible += 1
				end
			end
		end
		stats.redMarkersVisibleFromSpawn = visible
		if isStage and redMarkers > 1 and visible == redMarkers then
			warn("every Red marker is visible from the spawn")
		end
	end
	return report
end

return Validate
