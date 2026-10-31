-- Lune test for the map kit, the map modules and the validator (CONTRACT §3.7). Owner: D.
local fs = require("@lune/fs")

local Kit = require("../src/server/Maps/Kit")
local Validate = require("../src/server/Maps/Validate")
local Stages = require("../src/shared/Config/Stages")

local checks = 0
local function check(cond: any, label: string)
	checks += 1
	if not cond then
		error("FAILED: " .. label, 2)
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end
local function hasError(report, pattern: string): boolean
	for _, e in report.errors do
		if string.find(e, pattern, 1, true) then
			return true
		end
	end
	return false
end

-- Kit -----------------------------------------------------------------------------------

do -- heights: low walls and crates are climbable, Mid/High are not
	check(Kit.Heights.Low <= 5 and Kit.Heights.Low < Kit.JumpHeight, "Low wall climbable")
	check(Kit.Heights.Mid >= 8 and Kit.Heights.Mid > Kit.JumpHeight, "Mid wall not climbable")
	check(Kit.Heights.High >= 14, "High wall")
	local parts = {}
	local c = Kit.crate(parts, { 0, 0, 0 })
	check(c.Size[2] == 4 and c.Pos[2] == 2 and c.Material == "WoodPlanks", "crate is 4 studs of WoodPlanks on the ground")
	parts = {}
	Kit.wall(parts, { 0, 0 }, { 10, 0 }, "Low", "Brick")
	local top = 0
	for _, p in parts do
		local _, mx = Validate.aabb(p)
		top = math.max(top, mx[2])
	end
	check(near(top, Kit.Heights.Low), "brick Low wall incl. cap is exactly Low tall")
	parts = {}
	Kit.wall(parts, { 0, 0 }, { 10, 10 }, "Mid", "Concrete")
	check(parts[1].Rot ~= nil and near(parts[1].Size[1], math.sqrt(200), 1e-3), "diagonal wall is rotated and full length")
	local mn, mx = Validate.aabb(parts[1])
	check(mn[1] < 0.1 and mx[1] > 9.9 and mn[3] < 0.1 and mx[3] > 9.9, "diagonal wall AABB covers both ends")
	for _, style in { "Brick", "Concrete", "Glass", "Marble", "Hedge" } do
		local ps = {}
		Kit.wall(ps, { 0, 0 }, { 0, 12 }, "High", style)
		local hi = 0
		for _, p in ps do
			local _, m2 = Validate.aabb(p)
			hi = math.max(hi, m2[2])
			check(Validate.Materials[p.Material], "wall material valid " .. style)
		end
		check(near(hi, Kit.Heights.High), "wall style height " .. style)
	end
end

do -- faceRot: front (-Z) looks at the target
	check(near(Kit.faceRot({ 0, 0 }, { 0, -10 })[2], 0), "facing north = 0")
	check(near(Kit.faceRot({ 0, 0 }, { 10, 0 })[2], -90), "facing east = -90")
	check(near(math.abs(Kit.faceRot({ 0, 0 }, { 0, 10 })[2]), 180), "facing south = 180")
	-- the rotation matrix agrees: Ry(-90) LookVector (0,0,-1) -> (+1,0,0)
	local m = Validate.rotMatrix({ 0, -90, 0 })
	check(near(-m[1][3], 1) and near(-m[3][3], 0), "rotMatrix look vector")
	local m2 = Validate.rotMatrix({ 0, 0, 90 })
	check(near(m2[2][1], 1), "Rz(90) maps +X to +Y (vertical cylinders)")
end

do -- stairs: every step <= 1 stud, top step flush with the upper surface, solid to the base
	local parts = {}
	local foot = Kit.stairs(parts, { 0, 8, 0 }, "-z", 6)
	check(#parts == 8, "8 steps for 8 studs")
	local prev = 0
	for k, p in parts do
		local mn, mx = Validate.aabb(p)
		check(near(mn[2], 0), "step solid to base")
		check(mx[2] - prev <= 1 + 1e-6, "step rise <= 1")
		prev = mx[2]
		check(mn[3] >= -1e-6, "steps lie behind the top edge (going up = -z)")
		check(near(mx[1] - mn[1], 6), "stairs width")
		if k == #parts then
			check(near(mx[2], 8) and near(mn[3], 0), "top step flush with the top edge")
		end
	end
	check(foot[3] > 16, "foot point in front of the first step")
	parts = {}
	Kit.stairs(parts, { 0, 5, 0 }, "+x", 4, { step = 1, run = 2 })
	local _, mx = Validate.aabb(parts[#parts])
	check(near(mx[1], 0) and near(mx[2], 5), "+x stairs end at the edge")
end

do -- floor, perimeter
	local parts = {}
	Kit.floor(parts, { 0, 0, 0 }, { 40, 40 }, "Tile")
	check(parts[1].Name == "Floor" and near(parts[1].Pos[2] + parts[1].Size[2] / 2, 0), "floor top at y = 0")
	local seams = 0
	for _, p in parts do
		if p.Name == "FloorSeam" then
			seams += 1
			check(p.Collide == false, "seams do not collide")
		end
	end
	check(seams == 6, "tile seams every 10 studs")
	parts = {}
	Kit.perimeter(parts, { 60, 40 })
	local barriers = 0
	for _, p in parts do
		if p.Collide ~= false then
			local mn, mx = Validate.aabb(p)
			local inside = mn[1] < 30 - 1e-6 and mx[1] > -30 + 1e-6 and mn[3] < 20 - 1e-6 and mx[3] > -20 + 1e-6
			check(not inside, "collidable perimeter stays outside the arena")
			if p.Name == "PerimeterBarrier" then
				barriers += 1
				check(p.Transparency == 1 and mx[2] >= 46 - 1e-6, "invisible barrier above the wall")
			else
				check(mx[2] <= 16 + 1e-6, "visible perimeter height 16")
			end
		end
	end
	check(barriers == 4, "barrier on all four sides")
	check(#parts < 60, "perimeter part count")
end

do -- ring gaps really are open
	local parts = {}
	Kit.ring(parts, { -10, -10 }, { 10, 10 }, "Mid", "Brick", { gaps = { { side = "-z", at = 0, width = 6 } } })
	local boxes = Validate.boxes({ Parts = parts })
	check(Validate.blocked(boxes, { -2.5, 0.5, -11 }, { 2.5, 5, -9 }) == nil, "gap is open")
	check(Validate.blocked(boxes, { -8, 0.5, -11 }, { -6, 5, -9 }) ~= nil, "wall beside the gap")
	check(Validate.blocked(boxes, { 9, 0.5, 0 }, { 11, 5, 1 }) ~= nil, "closed side")
end

do -- pen: rails leave < 1 stud gaps, top is hop-able, returns a Pen gimmick
	local parts = {}
	local g = Kit.pen(parts, { 0, 0, 0 }, { 20, 20 })
	check(g.Type == "Pen" and g.Attr.W == 20 and g.Attr.D == 20, "pen gimmick")
	local ys = {}
	local hi = 0
	for _, p in parts do
		local mn, mx = Validate.aabb(p)
		hi = math.max(hi, mx[2])
		if p.Size[1] >= 20 and p.Size[3] < 1 and p.Pos[3] < 0 then
			table.insert(ys, { mn[2], mx[2] })
		end
	end
	table.sort(ys, function(a, b)
		return a[1] < b[1]
	end)
	check(#ys == 3, "three rails per side")
	check(ys[1][1] < 1, "bottom gap < 1")
	for i = 2, #ys do
		check(ys[i][1] - ys[i - 1][2] < 1.0, "rail gap < 1")
	end
	check(hi <= 5, "fence is low enough to hop over")
end

do -- markers: lifts, attributes, board
	local markers = {}
	local s = Kit.playerSpawn(markers, { 1, 2, 3 }, { 1, -10 })
	check(s.Tag == "PlayerSpawn" and s.Pos[2] == 2 + Kit.SpawnLift and near(s.Rot[2], 0), "player spawn lift + facing")
	local r = Kit.red(markers, { 0, 0, 0 }, { weight = 2, zone = 6 })
	check(r.Attr.Kind == "Red" and r.Attr.Weight == 2 and r.Attr.Zone == 6 and r.Attr.Count == nil, "red attrs")
	local w = Kit.white(markers, { 0, 0, 0 }, { count = 3 })
	check(w.Attr.Kind == "White" and w.Attr.Count == 3 and w.Attr.Weight == nil, "white attrs")
	local k = Kit.red(markers, { 0, 0, 0 }, { hasKey = true, keyColor = "Blue" })
	check(k.Attr.HasKey == true and k.Attr.KeyColor == "Blue", "key attrs")
	local p = Kit.weapon(markers, { 0, 1, 0 }, "Sniper", "X")
	check(p.Attr.Weapon == "Sniper" and p.Id == "X" and p.Pos[2] == 1 + Kit.PickupLift, "pickup")
	local parts = {}
	local b = Kit.board(parts, markers, { 0, 0, 0 }, { 0, 10 }, { w = 10, h = 6 })
	check(b.Tag == "Board" and b.Attr.Width == 10 and b.Attr.Height == 6, "board marker")
	check(near(math.abs(b.Rot[2]), 180), "board faces south")
	local boxes = Validate.boxes({ Parts = parts })
	-- nothing of the frame sits in front of the panel face
	check(Validate.segmentHit(boxes, { 0, b.Pos[2], 10 }, { 0, b.Pos[2], 0.3 }) == nil, "board face unobstructed")
end

-- Validator negative tests ---------------------------------------------------------------

-- 40×40 arena, start room on the south wall (interior x -7..7, z 9..19, door at x -1..5, z 8..9)
local function baseSpec()
	local parts, markers = {}, {}
	Kit.floor(parts, { 0, 0, 0 }, { 40, 40 }, "Concrete")
	Kit.perimeter(parts, { 40, 40 })
	Kit.startRoomSouth(parts, markers, 40, 0)
	Kit.red(markers, { 0, 0, -10 }, { zone = 6 })
	return { Name = "T", Size = { 40, 20, 40 }, Parts = parts, Markers = markers }
end
local function removeTag(s, tag: string, count: number?)
	local n = 0
	for i = #s.Markers, 1, -1 do
		if s.Markers[i].Tag == tag and n < (count or math.huge) then
			table.remove(s.Markers, i)
			n += 1
		end
	end
end
local function removePart(s, name: string, nth: number?)
	local k = 0
	for i, p in s.Parts do
		if p.Name == name then
			k += 1
			if k == (nth or 1) then
				table.remove(s.Parts, i)
				return
			end
		end
	end
	error("no part " .. name)
end

do
	local ok = Validate.run(baseSpec())
	check(#ok.errors == 0, "base spec valid: " .. table.concat(ok.errors, "; "))

	local s = baseSpec()
	removeTag(s, "PlayerSpawn", 1)
	check(hasError(Validate.run(s), "PlayerSpawn"), "too few spawns")

	s = baseSpec()
	for i = #s.Markers, 1, -1 do
		if s.Markers[i].Tag == "Board" then
			table.remove(s.Markers, i)
		end
	end
	check(hasError(Validate.run(s), "Board"), "missing board")
	check(not hasError(Validate.run(s, { stage = false }), "Red Weight"), "lobby needs no reds")

	s = baseSpec()
	s.Markers[#s.Markers].Attr.Weight = 0
	check(hasError(Validate.run(s), "Red Weight sum"), "red weight zero")

	s = baseSpec()
	Kit.crate(s.Parts, { 0, 0, -10 })
	check(hasError(Validate.run(s), "buried"), "buried marker")

	s = baseSpec()
	Kit.marker(s.Markers, "PlayerSpawn", { 5, 9, 15 })
	check(hasError(Validate.run(s), "floor is"), "floating spawn")

	s = baseSpec()
	Kit.marker(s.Markers, "PlayerSpawn", { 5, 3, 45 })
	check(hasError(Validate.run(s), "outside map bounds"), "spawn outside")

	s = baseSpec()
	Kit.box(s.Parts, { -4.5, 4, 15 }, { 2, 2, 2 }, "#FFFFFF", "Concrete")
	check(hasError(Validate.run(s), "headroom"), "spawn under a low ceiling")

	s = baseSpec()
	Kit.weapon(s.Markers, { 10, 0, 10 }, "Sniper", "A")
	Kit.weapon(s.Markers, { -10, 0, 10 }, "Sniper", "A")
	check(hasError(Validate.run(s), "duplicate WeaponPickup Id"), "duplicate pickup id")

	s = baseSpec()
	s.Parts[1].Material = "Lava"
	check(hasError(Validate.run(s), "unknown Material"), "bad material")
	s = baseSpec()
	s.Parts[1].Color = "red"
	check(hasError(Validate.run(s), "bad Color"), "bad color")

	s = baseSpec()
	Kit.platform(s.Parts, { 12, 6, -10 }, { 6, 6 }, { style = "Concrete" })
	Kit.red(s.Markers, { 12, 6, -10 }, { zone = 6 })
	local r = Validate.run(s)
	check(hasError(r, "hangs over a drop"), "zone wider than its platform")

	s = baseSpec()
	Kit.white(s.Markers, { 0, 0, 0 }, { zone = 30 })
	check(hasError(Validate.run(s), "leaves the arena"), "zone outside arena")

	-- arena escape: a roof next to a wall without the barrier is reported
	s = baseSpec()
	s.Parts = {}
	Kit.floor(s.Parts, { 0, 0, 0 }, { 40, 40 }, "Concrete")
	Kit.perimeter(s.Parts, { 40, 40 }, { barrier = false })
	Kit.board(s.Parts, {}, { 0, 0, 8 }, { 0, 15 }, {})
	Kit.platform(s.Parts, { -15, 10, -12 }, { 10, 10 }, { style = "Concrete" })
	Kit.stairs(s.Parts, { -15, 10, -7 }, "-z", 4)
	check(hasError(Validate.run(s), "perimeter top"), "wall-top escape detected")
	Kit.perimeter(s.Parts, { 40, 40 })
	check(not hasError(Validate.run(s), "perimeter top"), "barrier prevents the escape")

	-- one-way drop: spawns on a 10-stud ledge (z -20..0) above a lower floor (z 0..20) with no way back up
	local s3 = { Name = "Trap", Size = { 40, 20, 40 }, Parts = {}, Markers = {} }
	Kit.box(s3.Parts, { 0, 5, -10 }, { 40, 10, 20 }, "#808080", "Concrete")
	Kit.box(s3.Parts, { 0, -1, 10 }, { 40, 2, 20 }, "#808080", "Concrete")
	Kit.spawnRow(s3.Markers, { 0, 10, -10 }, 4, 3, "x", nil)
	Kit.board(s3.Parts, s3.Markers, { 0, 10, -16 }, { 0, -10 }, {})
	Kit.red(s3.Markers, { 0, 10, -5 }, { zone = 3 })
	local r3 = Validate.run(s3)
	check(hasError(r3, "trap"), "one-way drop is reported as a trap")
	check(r3.stats.trapCells > 0, "trap cells counted")
end

-- Start room (v0.5) -----------------------------------------------------------------------

local function tagged(markers, tag: string)
	local out = {}
	for _, m in markers do
		if m.Tag == tag then
			table.insert(out, m)
		end
	end
	return out
end

do -- kit: markers, door, slide pocket, sizes
	local parts, markers = {}, {}
	local room = Kit.startRoom(parts, markers, { 0, 0, 0 }, {})
	check(#tagged(markers, "StartDoor") == 1 and #tagged(markers, "StartRoom") == 1, "startRoom markers")
	check(#tagged(markers, "PlayerSpawn") == 4 and #tagged(markers, "Board") == 1, "startRoom spawns + board")
	local rm = tagged(markers, "StartRoom")[1]
	check(rm.Attr.Size == "14,12,10", "StartRoom Size attr " .. tostring(rm.Attr.Size))
	local dm = tagged(markers, "StartDoor")[1]
	check(dm.Attr.Slide == "-6,0,0" and dm.Attr.Width == 6 and dm.Attr.Height == 8, "StartDoor attrs " .. tostring(dm.Attr.Slide))
	check(near(dm.Pos[1], 2) and near(dm.Pos[2], 4) and near(dm.Pos[3], -5.5), "door center in the north wall")
	check(near(dm.Rot[2], 0), "door marker faces the arena (-z)")
	local door, pocket
	local roofTop, wallTop = 0, math.huge
	for _, p in parts do
		check(Validate.Materials[p.Material] ~= nil, "startRoom material " .. p.Material)
		local mn, mx = Validate.aabb(p)
		if p.Name == "StartDoor" and p.Collide ~= false then
			door = p
		elseif p.Name == "StartRoomWall" then
			wallTop = math.min(wallTop, mx[2])
			if mx[3] > -5 - 1e-6 and mn[3] < -5 + 1e-6 and mn[1] < -7 then
				pocket = { mn, mx }
			end
		elseif p.Name == "StartRoomRoof" then
			roofTop = mx[2]
		end
	end
	check(door ~= nil and near(door.Size[1], 6) and near(door.Size[2], 8), "door 6 wide 8 tall")
	check(wallTop >= 10 and roofTop > wallTop, "walls >= 10 under a roof")
	check(pocket ~= nil, "pocket wall beside the door")
	-- every door part slid by Slide ends up hidden inside the pocket wall
	for _, p in parts do
		if p.Name == "StartDoor" then
			local q = table.clone(p)
			q.Pos = { p.Pos[1] - 6, p.Pos[2], p.Pos[3] }
			local mn, mx = Validate.aabb(q)
			for i = 1, 3 do
				check(mn[i] >= pocket[1][i] - 1e-6 and mx[i] <= pocket[2][i] + 1e-6, "open door hidden in the wall")
			end
		end
	end
	-- spawns look at the board, board on the far end wall
	local board = tagged(markers, "Board")[1]
	for _, sp in tagged(markers, "PlayerSpawn") do
		check(sp.Pos[1] < board.Pos[1] - 8, "spawns at the far end")
		check(sp.Pos[2] == room.floor + Kit.SpawnLift, "spawn root height on the room floor")
	end
	check(#room.spots == 3, "pickup spots")
	for _, sp in room.spots do
		check(math.abs(sp[1]) < 7 and math.abs(sp[3]) < 5, "spot inside")
	end
	-- mirrored / rotated rooms validate too (room against each wall of a small arena)
	for _, facing in { "-z", "+z", "-x", "+x" } do
		for _, side in { "right", "left" } do
			local ps, ms = {}, {}
			Kit.floor(ps, { 0, 0, 0 }, { 50, 50 }, "Concrete")
			Kit.perimeter(ps, { 50, 50 })
			local dv = Kit.Dirs[facing]
			local back = 25 - 1 - 5
			local r = Kit.startRoom(ps, ms, { -dv[1] * back, 0, -dv[2] * back }, { facing = facing, board = side })
			Kit.red(ms, { dv[1] * 12, 0, dv[2] * 12 }, { zone = 5 })
			Kit.health(ms, r.outside, "H")
			local rep = Validate.run({ Name = "R" .. facing .. side, Size = { 50, 20, 50 }, Parts = ps, Markers = ms })
			check(#rep.errors == 0, "room " .. facing .. " " .. side .. ": " .. table.concat(rep.errors, "; "))
			local d = tagged(ms, "StartDoor")[1]
			local sx, sy, sz = string.match(d.Attr.Slide, "^([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)$")
			sx, sy, sz = tonumber(sx), tonumber(sy), tonumber(sz)
			check(sx ~= nil and sy == 0 and near(math.sqrt(sx * sx + sz * sz), 6), "slide 6 studs " .. d.Attr.Slide)
			check(near(sx * dv[1] + sz * dv[2], 0), "slide runs along the door wall")
		end
	end
	check(Validate.parseSize("14,12,10")[3] == 10 and Validate.parseSize("1,2") == nil and Validate.parseSize("0,1,1") == nil, "parseSize")
end

do -- validator: start room rules
	local s = baseSpec()
	removeTag(s, "StartDoor")
	check(hasError(Validate.run(s), "exactly 1 StartDoor"), "missing StartDoor")
	s = baseSpec()
	removeTag(s, "StartRoom")
	check(hasError(Validate.run(s), "exactly 1 StartRoom"), "missing StartRoom")
	s = baseSpec()
	tagged(s.Markers, "StartRoom")[1].Attr.Size = "14x12x10"
	check(hasError(Validate.run(s), "Attr Size"), "bad StartRoom Size")
	check(not hasError(Validate.run(baseSpec(), { stage = false }), "StartRoom"), "lobby needs no start room")

	s = baseSpec()
	Kit.playerSpawn(s.Markers, { 0, 0, 0 }, nil, "Out")
	check(hasError(Validate.run(s), "PlayerSpawn outside the StartRoom"), "spawn outside the room")

	-- the door counts as solid when closed: without it the room leaks; with it the arena is still reachable
	s = baseSpec()
	removePart(s, "StartDoor")
	check(hasError(Validate.run(s), "not sealed"), "doorway without a door leaks")
	local okr = Validate.run(baseSpec())
	check(okr.stats.startRoomLeakCells == 0 and okr.stats.enemyMarkersReachable == 1, "door open for reachability")
	s = baseSpec()
	removePart(s, "StartRoomWall", 2) -- spawn-end wall
	check(hasError(Validate.run(s), "not sealed"), "missing wall leaks")
	s = baseSpec()
	-- the spawn-end wall raised 6 studs off the floor: a player walks under it
	for _, p in s.Parts do
		if p.Name == "StartRoomWall" and p.Size[1] == 1 and p.Pos[1] < 0 then
			p.Pos = { p.Pos[1], p.Pos[2] + 6, p.Pos[3] }
			break
		end
	end
	check(hasError(Validate.run(s), "not sealed"), "crawl gap under a wall leaks")
	s = baseSpec()
	for _, p in s.Parts do
		if p.Name == "StartRoomWall" then
			p.Size = { p.Size[1], 6, p.Size[3] }
			p.Pos = { p.Pos[1], 3, p.Pos[3] }
		end
	end
	removePart(s, "StartRoomRoof")
	check(hasError(Validate.run(s), "not sealed"), "low walls without roof can be jumped over")

	s = baseSpec()
	Kit.crates(s.Parts, { 12, 0, 14 }, "pyramid", "x")
	check(hasError(Validate.run(s), "roof can be climbed"), "crate pyramid next to the room reaches the roof")

	s = baseSpec()
	Kit.white(s.Markers, { 0, 0, -2 }, { count = 2, zone = 11 })
	check(hasError(Validate.run(s), "overlaps the StartRoom"), "enemy zone overlapping the room")
	s = baseSpec()
	Kit.white(s.Markers, { 0, 0, -10 }, { count = 2, zone = 6 })
	check(not hasError(Validate.run(s), "overlaps the StartRoom"), "zone clear of the room")

	-- health / ammo pickups
	s = baseSpec()
	Kit.marker(s.Markers, "HealthPickup", { 10, 2, -5 })
	check(hasError(Validate.run(s), "HealthPickup without Id"), "health without id")
	s = baseSpec()
	Kit.health(s.Markers, { 10, 0, -5 }, "X")
	Kit.ammo(s.Markers, { -10, 0, -5 }, "X")
	check(hasError(Validate.run(s), "duplicate AmmoPickup Id"), "ids unique across pickups")
	s = baseSpec()
	Kit.weapon(s.Markers, { 10, 0, -5 }, "Sniper", "Y")
	Kit.health(s.Markers, { -10, 0, -5 }, "Y")
	check(hasError(Validate.run(s), "duplicate HealthPickup Id"), "weapon/health id clash")
	s = baseSpec()
	Kit.health(s.Markers, { 10, 6, -5 }, "H")
	check(hasError(Validate.run(s), "HealthPickup floor is"), "floating health")
	s = baseSpec()
	Kit.platform(s.Parts, { 12, 10, -10 }, { 6, 6 }, { style = "Concrete" })
	Kit.ammo(s.Markers, { 12, 10, -10 }, "A")
	check(hasError(Validate.run(s), "AmmoPickup not reachable"), "unreachable ammo")
	s = baseSpec()
	Kit.health(s.Markers, { 10, 0, -5 }, "H")
	Kit.ammo(s.Markers, { -10, 0, -5 }, "A", "Pistol")
	local okp = Validate.run(s)
	check(#okp.errors == 0, "health + ammo valid: " .. table.concat(okp.errors, "; "))
end

-- Map modules ------------------------------------------------------------------------------

local mapNames = {}
for _, file in fs.readDir("src/server/Maps") do
	local name = string.match(file, "^(.+)%.luau$")
	if name and name ~= "Kit" and name ~= "Validate" then
		table.insert(mapNames, name)
	end
end
table.sort(mapNames)

local specs = {}
local reports = {}
for _, name in mapNames do
	local spec = require("../src/server/Maps/" .. name)(Kit)
	specs[name] = spec
	check(spec.Name == name, name .. " spec name matches module")
	local report = Validate.run(spec, { stage = name ~= "Lobby" })
	reports[name] = report
	check(#report.errors == 0, name .. " validates: " .. table.concat(report.errors, "; "))
	check(#spec.Parts < 400, name .. " part count < 400")
	check(report.stats.trapCells == 0, name .. " has no traps")
end

-- every configured stage has a map module
for _, id in Stages.Order do
	local cfg = Stages[id]
	check(specs[cfg.Map] ~= nil, "stage " .. id .. " map " .. cfg.Map .. " exists")
end
check(specs.Lobby ~= nil, "lobby exists")

local function byTag(spec, tag)
	local out = {}
	for _, m in spec.Markers do
		if m.Tag == tag then
			table.insert(out, m)
		end
	end
	return out
end
local function enemies(spec, kind)
	local out = {}
	for _, m in byTag(spec, "EnemySpawn") do
		if m.Attr.Kind == kind then
			table.insert(out, m)
		end
	end
	return out
end
local function spawnCentroid(spec)
	local x, y, z, n = 0, 0, 0, 0
	for _, m in byTag(spec, "PlayerSpawn") do
		x += m.Pos[1]
		y += m.Pos[2]
		z += m.Pos[3]
		n += 1
	end
	return { x / n, y / n, z / n }
end
local function dist2(a, b)
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2)
end

-- start room helpers
local function roomBox(spec)
	local m = byTag(spec, "StartRoom")[1]
	local size = Validate.parseSize(m.Attr.Size)
	local c = m.Pos
	return { c[1] - size[1] / 2, c[2] - size[2] / 2, c[3] - size[3] / 2 }, { c[1] + size[1] / 2, c[2] + size[2] / 2, c[3] + size[3] / 2 }, size
end
local function insideRoom(spec, p): boolean
	local mn, mx = roomBox(spec)
	return p[1] > mn[1] and p[1] < mx[1] and p[3] > mn[3] and p[3] < mx[3] and p[2] > mn[2] and p[2] < mx[2]
end
-- eye of a player standing 3 studs outside the door (all rooms here open to -z)
local function doorEye(spec)
	local d = byTag(spec, "StartDoor")[1]
	return { d.Pos[1], d.Pos[2] - d.Attr.Height / 2 + 4.5, d.Pos[3] - 3 }
end
local function openDoorBoxes(spec)
	local out = {}
	for _, b in Validate.boxes(spec) do
		if b.name ~= "StartDoor" then
			table.insert(out, b)
		end
	end
	return out
end

do -- every stage: one start room on the south wall, door 6×8, pickups with unique ids
	for _, name in { "S1_1", "S1_2", "S1_3" } do
		local s = specs[name]
		check(#byTag(s, "StartDoor") == 1 and #byTag(s, "StartRoom") == 1, name .. " one StartDoor + one StartRoom")
		local mn, mx, size = roomBox(s)
		check(size[1] >= 12 and size[1] <= 16 and size[3] >= 8 and size[3] <= 12, name .. " room ~14×10")
		check(size[2] >= 10, name .. " room walls >= 10")
		check(mx[3] >= s.Size[3] / 2 - 2, name .. " room against the south wall")
		for _, m in byTag(s, "PlayerSpawn") do
			check(insideRoom(s, m.Pos), name .. " spawn inside the room")
		end
		check(insideRoom(s, byTag(s, "Board")[1].Pos), name .. " board inside the room")
		local d = byTag(s, "StartDoor")[1]
		check(d.Attr.Width == 6 and d.Attr.Height == 8, name .. " door 6×8")
		check(d.Pos[3] < mn[3] and d.Pos[3] > mn[3] - 1.5, name .. " door in the north wall")
		local doorParts = 0
		for _, p in s.Parts do
			if p.Name == "StartDoor" and p.Collide ~= false then
				doorParts += 1
				check(p.Color == Kit.C.Door, name .. " door is white")
				check(near(p.Pos[1], d.Pos[1]) and near(p.Pos[2], d.Pos[2]) and near(p.Pos[3], d.Pos[3]), name .. " marker at door center")
			end
		end
		check(doorParts == 1, name .. " one solid door part")
		check(reports[name].stats.startRoomLeakCells == 0, name .. " room sealed")
		-- the room shows the party nothing of the arena: no enemy marker visible from the room center either
		local boxes = Validate.boxes(s)
		local rc = byTag(s, "StartRoom")[1].Pos
		for _, e in byTag(s, "EnemySpawn") do
			check(Validate.segmentHit(boxes, { rc[1], 5, rc[3] }, { e.Pos[1], e.Pos[2] + 1, e.Pos[3] }) ~= nil, name .. " enemy hidden from the room")
		end
		local health, ammo = byTag(s, "HealthPickup"), byTag(s, "AmmoPickup")
		check(#health >= 1 and #health <= 2, name .. " 1-2 health pickups")
		check(#ammo <= 2, name .. " <= 2 ammo pickups")
		if name ~= "S1_1" then
			check(#ammo >= 1, name .. " has ammo")
		end
		local ids = {}
		for _, tag in { "WeaponPickup", "HealthPickup", "AmmoPickup" } do
			for _, m in byTag(s, tag) do
				check(m.Id ~= nil and not ids[m.Id], name .. " unique pickup id " .. tostring(m.Id))
				ids[m.Id] = true
			end
		end
		for _, m in health do
			check(not insideRoom(s, m.Pos), name .. " health is out in the arena")
		end
	end
	-- 1-3: pistol ammo in the room, the sniper stays out in the arena
	local s3 = specs.S1_3
	local roomAmmo = 0
	for _, m in byTag(s3, "AmmoPickup") do
		if insideRoom(s3, m.Pos) then
			roomAmmo += 1
			check(m.Attr and m.Attr.Weapon == "Pistol", "1-3 room ammo is pistol ammo")
		end
	end
	check(roomAmmo == 1, "1-3 one ammo box in the start room")
	check(not insideRoom(s3, byTag(s3, "WeaponPickup")[1].Pos), "1-3 sniper outside the room")
end

do -- Lobby
	local s = specs.Lobby
	check(#byTag(s, "PlayerSpawn") >= 4, "lobby spawns")
	check(#byTag(s, "Board") == 1, "lobby board")
	check(#byTag(s, "EnemySpawn") == 0, "no enemies in the lobby")
	local ids = {}
	for _, m in byTag(s, "PlayerSpawn") do
		check(m.Id ~= nil and not ids[m.Id], "lobby spawn ids unique (round-robin order)")
		ids[m.Id] = true
	end
end

do -- 1-1: one Red in a random corner, no Whites
	local s = specs.S1_1
	local reds = enemies(s, "Red")
	check(#reds >= 3 and #reds <= 4, "1-1 has 3-4 Red markers")
	check(#enemies(s, "White") == 0, "1-1 has no Whites")
	local quadrants = {}
	for _, m in reds do
		check(m.Attr.Weight == 1, "1-1 red weight 1")
		check(m.Attr.Zone >= 8 and m.Attr.Zone <= 12, "1-1 red zone 8-12")
		local q = (if m.Pos[1] < 0 then "W" else "E") .. (if m.Pos[3] < 0 then "N" else "S")
		check(not quadrants[q], "1-1 reds in different corners")
		quadrants[q] = true
		check(math.abs(m.Pos[1]) > 20 and math.abs(m.Pos[3]) > 18, "1-1 red near a corner")
	end
	check(reports.S1_1.stats.redMarkersVisibleFromSpawn < #reds, "1-1 spawn does not overlook every Red")
	check(s.Size[1] >= 80 and s.Size[1] <= 100, "1-1 size ~90")
end

do -- 1-2: rooftops by stairs, an unreachable perch on a sniping lane, Sniper near spawn
	local s = specs.S1_2
	local r = reports.S1_2
	local reds = enemies(s, "Red")
	check(#reds >= 3, "1-2 has >= 3 Red markers")
	local perch
	local reachableHigh = 0
	local grid = r.grid
	local cells = r.reach
	for _, m in reds do
		check(m.Pos[2] - Kit.EnemyLift >= 6, "1-2 reds are up high")
		check(m.Attr.Zone >= 4 and m.Attr.Zone <= 6, "1-2 red zones 4-6")
		local c = Validate.cellOf(grid, m.Pos[1], m.Pos[3])
		local ch = string.sub(cells, c, c)
		if ch == "1" then
			reachableHigh += 1
		else
			perch = m
		end
	end
	check(reachableHigh >= 2, "1-2 two rooftops reachable on foot")
	check(perch ~= nil and perch.Id == "Perch", "1-2 perch is not reachable on foot")
	local pickups = byTag(s, "WeaponPickup")
	check(#pickups == 1 and pickups[1].Attr.Weapon == "Sniper", "1-2 sniper pickup")
	local sc = spawnCentroid(s)
	check(dist2(pickups[1].Pos, sc) <= 16, "1-2 sniper near the spawn")
	local boxes = Validate.boxes(s)
	local target = { perch.Pos[1], perch.Pos[2] + 1, perch.Pos[3] }
	-- v0.5: the party starts in the closed room; the sniping lane starts at the door
	check(Validate.segmentHit(boxes, doorEye(s), target) == nil, "1-2 sniping lane door -> perch")
	local open = openDoorBoxes(s)
	local inDoorway = { byTag(s, "StartDoor")[1].Pos[1], 4.7, byTag(s, "StartDoor")[1].Pos[3] }
	check(Validate.segmentHit(open, inDoorway, target) == nil, "1-2 perch visible from the open doorway")
	check(insideRoom(s, pickups[1].Pos), "1-2 sniper lies in the start room")
	-- no surface within jumping reach of the perch except the perch itself
	local perchTop = perch.Pos[2] - Kit.EnemyLift
	for i, h in grid.h do
		if h > perchTop - 8 and h < perchTop - 0.5 then
			local ci = (i - 1) % grid.nx
			local ck = (i - 1) // grid.nx
			local x = grid.x0 + (ci + 0.5) * grid.res
			local z = grid.z0 + (ck + 0.5) * grid.res
			check(dist2({ x, 0, z }, perch.Pos) > 15, "1-2 nothing to jump to the perch from")
		end
	end
	check(#enemies(s, "White") <= 1, "1-2 at most one White marker")
	for _, m in enemies(s, "White") do
		check(m.Pos[2] - Kit.EnemyLift < 1, "1-2 White on the ground")
	end
end

do -- 1-3: Reds among White groups, a pen, a riskier Sniper, Night-friendly lamps
	local s = specs.S1_3
	local whites = enemies(s, "White")
	local reds = enemies(s, "Red")
	local groups = 0
	for _, m in whites do
		check(m.Attr.Count >= 2 and m.Attr.Count <= 3, "1-3 white groups of 2-3")
		if m.Attr.Zone >= 12 and m.Attr.Zone <= 20 then
			groups += 1
		end
	end
	check(groups >= 3, "1-3 has >= 3 roaming White groups")
	local pen
	for _, g in s.Gimmicks or {} do
		if g.Type == "Pen" then
			pen = g
		end
	end
	check(pen ~= nil, "1-3 has a pen")
	local penned = 0
	for _, m in whites do
		local dx, dz = math.abs(m.Pos[1] - pen.Attr.X), math.abs(m.Pos[3] - pen.Attr.Z)
		if dx < pen.Attr.W / 2 and dz < pen.Attr.D / 2 then
			penned += 1
			check(dx + m.Attr.Zone <= pen.Attr.W / 2 - 1 and dz + m.Attr.Zone <= pen.Attr.D / 2 - 1, "1-3 penned zone inside fence")
		end
	end
	check(penned >= 1, "1-3 Whites in the pen")
	local mixed = 0
	for _, r in reds do
		for _, w in whites do
			if dist2(r.Pos, w.Pos) < r.Attr.Zone + w.Attr.Zone then
				mixed += 1
				break
			end
		end
	end
	check(mixed >= 3, "1-3 at least 3 Red zones overlap White zones")
	local pickups = byTag(s, "WeaponPickup")
	check(#pickups == 1 and pickups[1].Attr.Weapon == "Sniper", "1-3 sniper pickup")
	local sc = spawnCentroid(s)
	check(dist2(pickups[1].Pos, sc) > 40, "1-3 sniper is away from the spawn (riskier)")
	local nearWhite = false
	for _, w in whites do
		if dist2(pickups[1].Pos, w.Pos) <= w.Attr.Zone + 10 then
			nearWhite = true
		end
	end
	check(nearWhite, "1-3 sniper is close to a White group")
	local lights = 0
	for _, p in s.Parts do
		if p.Name == "Light" then
			lights += 1
		end
	end
	check(lights >= 8, "1-3 night stage has lamps")
end

print(("maps.spec: %d checks passed (%s)"):format(checks, table.concat(mapNames, ", ")))
