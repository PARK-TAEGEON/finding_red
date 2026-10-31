--!strict
-- Map kit (CONTRACT §3.7). Owner: D.
-- Pure piece functions in the original game's grammar: grey tile floor, blue grid glass perimeter,
-- brick/concrete/glass walls (Low/Mid/High), stairs, rooftops, bridges, crates, red barrels,
-- cartoon trees, fence pens, chalkboards, lamps and marker helpers.
-- No Roblox globals, no requires: vectors are {x, y, z}, colors "#RRGGBB", materials Enum.Material names.
--
-- Conventions
--   * Map origin = floor center, y = 0 is the floor top. +x = east, -z = north.
--   * "pos" arguments of props are the ground point (bottom center) unless stated otherwise.
--   * Marker helpers take the SURFACE point the marker stands on and lift it themselves
--     (spawns +3 = character root height, pickups +2 = floating weapon).
--   * Every function appends to the `parts` / `markers` arrays it is given.

export type Vec3 = { number }
export type Attr = { [string]: string | number | boolean }
export type Part = {
	Shape: string,
	Size: Vec3,
	Pos: Vec3,
	Rot: Vec3?,
	Color: string,
	Material: string,
	Collide: boolean?,
	Transparency: number?,
	Name: string?,
}
export type Marker = { Tag: string, Pos: Vec3, Rot: Vec3?, Id: string?, Attr: Attr? }
export type Gimmick = { Type: string, Id: string, Attr: Attr }
export type Opts = { [string]: any }

local Kit = {}

-- Jump reach of a default Roblox character is about 7.2 studs.
Kit.Heights = { Low = 4, Mid = 8, High = 14 }
Kit.JumpHeight = 7.2
Kit.SpawnLift = 3 -- PlayerSpawn / EnemySpawn marker height above the surface (root part height)
Kit.PickupLift = 2 -- WeaponPickup marker height above the surface
Kit.EnemyLift = 3

Kit.C = {
	Tile = "#C3C7CC",
	TileSeam = "#9EA4AC",
	Grass = "#6DB548",
	GrassDark = "#5A9C3B",
	Path = "#D8CBB0",
	Navy = "#22305E",
	GridBlue = "#3570C4",
	Glass = "#8FD0FF",
	Brick = "#B5523B",
	BrickCap = "#D9D2C5",
	Concrete = "#A7AAAE",
	ConcreteDark = "#8A8E93",
	Marble = "#E8E4DC",
	MarbleDark = "#CFC9BE",
	Wood = "#B07A42",
	WoodDark = "#7E5228",
	Barrel = "#D2302B",
	BarrelBand = "#7A1712",
	Trunk = "#7B4F2B",
	Leaf1 = "#4DB33F",
	Leaf2 = "#3E9C35",
	Leaf3 = "#62C84F",
	Fence = "#F0EBDD",
	FencePost = "#C9B98F",
	Chalk = "#2E4E3A",
	BoardFrame = "#8A5A2E",
	Lamp = "#FFE7A3",
	LampPost = "#3A3F4A",
	SpawnPad = "#5ACB6A",
	Bench = "#9B6A3A",
	Roof = "#5D6B7A",
	Window = "#9ED8FF",
}

local H = Kit.Heights
local C = Kit.C

-- Low-level ----------------------------------------------------------------------

local function r3(v: number): number
	return math.floor(v * 1000 + 0.5) / 1000
end

local function v3(x: number, y: number, z: number): Vec3
	return { r3(x), r3(y), r3(z) }
end
Kit.v3 = v3

-- Appends a part. `center` is the part center.
function Kit.box(parts: { Part }, center: Vec3, size: Vec3, color: string, material: string, opts: Opts?): Part
	local o: Opts = opts or {}
	local p: Part = {
		Shape = o.Shape or "Block",
		Size = v3(size[1], size[2], size[3]),
		Pos = v3(center[1], center[2], center[3]),
		Color = color,
		Material = material,
	}
	if o.Rot then
		p.Rot = { o.Rot[1], o.Rot[2], o.Rot[3] }
	end
	if o.Collide == false then
		p.Collide = false
	end
	if o.Transparency and o.Transparency > 0 then
		p.Transparency = o.Transparency
	end
	if o.Name then
		p.Name = o.Name
	end
	table.insert(parts, p)
	return p
end

-- Box given by its bottom center (ground point).
function Kit.block(parts: { Part }, pos: Vec3, size: Vec3, color: string, material: string, opts: Opts?): Part
	return Kit.box(parts, { pos[1], pos[2] + size[2] / 2, pos[3] }, size, color, material, opts)
end

-- Box spanning min/max corners.
function Kit.span(parts: { Part }, minv: Vec3, maxv: Vec3, color: string, material: string, opts: Opts?): Part
	return Kit.box(
		parts,
		{ (minv[1] + maxv[1]) / 2, (minv[2] + maxv[2]) / 2, (minv[3] + maxv[3]) / 2 },
		{ maxv[1] - minv[1], maxv[2] - minv[2], maxv[3] - minv[3] },
		color,
		material,
		opts
	)
end

-- Y rotation (degrees) so that a part's front (-Z, LookVector) faces from `from` toward `to` ({x, z} or {x, y, z}).
function Kit.faceRot(from: { number }, to: { number }): Vec3
	local fx = to[1] - from[1]
	local fz = (if #to >= 3 then to[3] else to[2]) - (if #from >= 3 then from[3] else from[2])
	if fx == 0 and fz == 0 then
		return { 0, 0, 0 }
	end
	return { 0, r3(math.deg(math.atan2(-fx, -fz))), 0 }
end

-- Vertical cylinder (Roblox cylinders run along X, so rotate 90° about Z). pos = bottom center.
function Kit.cylinder(
	parts: { Part },
	pos: Vec3,
	height: number,
	diameter: number,
	color: string,
	material: string,
	opts: Opts?
): Part
	local o: Opts = table.clone(opts or {})
	o.Shape = "Cylinder"
	o.Rot = { 0, 0, 90 }
	return Kit.box(parts, { pos[1], pos[2] + height / 2, pos[3] }, { height, diameter, diameter }, color, material, o)
end

function Kit.ball(parts: { Part }, center: Vec3, diameter: number, color: string, material: string, opts: Opts?): Part
	local o: Opts = table.clone(opts or {})
	o.Shape = "Ball"
	return Kit.box(parts, center, { diameter, diameter, diameter }, color, material, o)
end

-- Floor --------------------------------------------------------------------------

-- Floor slab whose top is at center.y. style: "Tile" (grey tiles with seams), "Grass", "Concrete", "Marble".
-- opts.tile = seam spacing (Tile only, default 10), opts.thickness (default 2).
function Kit.floor(parts: { Part }, center: Vec3, size: { number }, style: string?, opts: Opts?)
	local o: Opts = opts or {}
	local s = style or "Tile"
	local w, d = size[1], size[2]
	local t = o.thickness or 2
	local cx, top, cz = center[1], center[2], center[3]
	local color, material = C.Tile, "Slate"
	if s == "Grass" then
		color, material = C.Grass, "Grass"
	elseif s == "Concrete" then
		color, material = C.Concrete, "Concrete"
	elseif s == "Marble" then
		color, material = C.Marble, "Marble"
	elseif s == "Path" then
		color, material = C.Path, "Sandstone"
	end
	if o.color then
		color = o.color
	end
	Kit.box(parts, { cx, top - t / 2, cz }, { w, t, d }, color, material, { Name = "Floor" })
	if s == "Tile" then
		-- Thin non-collidable seams give the grey tile grid look with few parts.
		local step = o.tile or 10
		local seam = { Collide = false, Name = "FloorSeam" }
		local nx = math.floor(w / step + 0.5)
		for i = 1, nx - 1 do
			local x = cx - w / 2 + i * step
			Kit.box(parts, { x, top, cz }, { 0.3, 0.1, d }, C.TileSeam, "SmoothPlastic", seam)
		end
		local nz = math.floor(d / step + 0.5)
		for i = 1, nz - 1 do
			local z = cz - d / 2 + i * step
			Kit.box(parts, { cx, top, z }, { w, 0.1, 0.3 }, C.TileSeam, "SmoothPlastic", seam)
		end
	end
end

-- Flat decorative patch on top of the floor (collidable, 0.2 thick so feet barely notice).
function Kit.patch(parts: { Part }, center: Vec3, size: { number }, color: string, material: string, opts: Opts?)
	local o: Opts = table.clone(opts or {})
	o.Name = o.Name or "Patch"
	Kit.box(parts, { center[1], center[2] + 0.1, center[3] }, { size[1], 0.2, size[2] }, color, material, o)
end

-- Perimeter ----------------------------------------------------------------------

-- Outer walls around a w×d arena centered on the origin. Inner faces sit exactly on ±w/2, ±d/2.
-- Navy base band + blue-grid glass panels + navy top beam. opts.height (default 16), opts.post (grid spacing, 10).
-- An invisible collidable barrier continues 30 studs above the wall (opts.barrier = false to skip), so nobody
-- can jump from a roof onto the wall top and out of the arena.
function Kit.perimeter(parts: { Part }, size: { number }, opts: Opts?)
	local o: Opts = opts or {}
	local w, d = size[1], size[2]
	local h = o.height or 16
	local t = 2
	local base = 3
	local beam = 1
	local spacing = o.post or 10
	local nm = { Name = "Perimeter" }
	local glass = { Name = "Perimeter", Transparency = 0.45 }
	local deco = { Name = "Perimeter", Collide = false }
	local sides = {
		{ cx = 0, cz = -d / 2 - t / 2, len = w + 2 * t, alongX = true },
		{ cx = 0, cz = d / 2 + t / 2, len = w + 2 * t, alongX = true },
		{ cx = -w / 2 - t / 2, cz = 0, len = d, alongX = false },
		{ cx = w / 2 + t / 2, cz = 0, len = d, alongX = false },
	}
	for _, sd in sides do
		local cx, cz, len, alongX = sd.cx, sd.cz, sd.len, sd.alongX
		local function sz(l: number, hh: number, th: number): Vec3
			if alongX then
				return { l, hh, th }
			end
			return { th, hh, l }
		end
		Kit.box(parts, { cx, base / 2, cz }, sz(len, base, t), C.Navy, "Concrete", nm)
		Kit.box(parts, { cx, base + (h - base - beam) / 2, cz }, sz(len, h - base - beam, t * 0.5), C.Glass, "Glass", glass)
		Kit.box(parts, { cx, h - beam / 2, cz }, sz(len, beam, t), C.Navy, "Concrete", nm)
		-- grid: posts and one mid rail on the inner side
		-- the grid sits on the glass' inner face, inside the wall's 2-stud band
		local inward = if alongX then (if cz < 0 then 1 else -1) else (if cx < 0 then 1 else -1)
		local gx, gz = cx, cz
		if alongX then
			gz = cz + inward * (t * 0.25 + 0.25)
		else
			gx = cx + inward * (t * 0.25 + 0.25)
		end
		Kit.box(parts, { gx, base + (h - base - beam) / 2, gz }, sz(len, 0.5, 0.5), C.GridBlue, "SmoothPlastic", deco)
		local inner = if alongX then w else d
		local n = math.max(1, math.floor(inner / spacing + 0.5))
		for i = 1, n - 1 do
			local a = -inner / 2 + i * inner / n
			local px = if alongX then a else gx
			local pz = if alongX then gz else a
			Kit.box(parts, { px, base + (h - base - beam) / 2, pz }, sz(0.5, h - base - beam, 0.5), C.GridBlue, "SmoothPlastic", deco)
		end
		if o.barrier ~= false then
			Kit.box(parts, { cx, h + 15, cz }, sz(len, 30, t), C.Navy, "SmoothPlastic", { Name = "PerimeterBarrier", Transparency = 1 })
		end
	end
end

-- Walls --------------------------------------------------------------------------

local function wallHeight(kind: any): number
	if type(kind) == "number" then
		return kind
	end
	local v = (H :: any)[kind]
	assert(type(v) == "number", "unknown wall kind " .. tostring(kind))
	return v
end
Kit.wallHeight = wallHeight

-- Straight wall from a = {x, z} to b = {x, z}. kind = "Low" | "Mid" | "High" | number,
-- style = "Brick" | "Concrete" | "Glass" | "Marble" | "Hedge". opts.y = base height (default 0), opts.thick (default 2).
function Kit.wall(parts: { Part }, a: { number }, b: { number }, kind: any, style: string?, opts: Opts?)
	local o: Opts = opts or {}
	local st = style or "Brick"
	local y0: number = o.y or 0
	local h = wallHeight(kind)
	local t: number = o.thick or 2
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local len = math.sqrt(dx * dx + dz * dz)
	assert(len > 0, "zero-length wall")
	local cx, cz = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
	local alongX = math.abs(dz) < 1e-6
	local alongZ = math.abs(dx) < 1e-6
	local rot: Vec3? = nil
	if not alongX and not alongZ then
		rot = { 0, r3(math.deg(math.atan2(-dz, dx))), 0 }
	end
	-- size along the wall's own axis: X = length (rotated case) / world axes otherwise
	local function sz(l: number, hh: number, th: number): Vec3
		if alongZ then
			return { th, hh, l }
		end
		return { l, hh, th }
	end
	local function add(yc: number, l: number, hh: number, th: number, color: string, mat: string, extra: Opts?)
		local e: Opts = table.clone(extra or {})
		e.Rot = rot
		e.Name = e.Name or ("Wall" .. st)
		Kit.box(parts, { cx, yc, cz }, sz(l, hh, th), color, mat, e)
	end
	if st == "Brick" then
		local cap = 0.4
		add(y0 + (h - cap) / 2, len, h - cap, t, C.Brick, "Brick")
		add(y0 + h - cap / 2, len + 0.4, cap, t + 0.4, C.BrickCap, "Concrete")
	elseif st == "Concrete" then
		add(y0 + h / 2, len, h, t, C.Concrete, "Concrete")
	elseif st == "Marble" then
		add(y0 + h / 2, len, h, t, C.Marble, "Marble")
	elseif st == "Hedge" then
		add(y0 + h / 2, len, h, t + 0.5, C.Leaf2, "Grass")
	elseif st == "Glass" then
		local sill, beam = 1, 0.6
		add(y0 + sill / 2, len, sill, t, C.Navy, "Concrete")
		add(y0 + sill + (h - sill - beam) / 2, len, h - sill - beam, t * 0.5, C.Glass, "Glass", { Transparency = 0.45 })
		add(y0 + h - beam / 2, len, beam, t, C.Navy, "Concrete")
		-- grid posts (decorative, inside the glass thickness band)
		if rot == nil then
			local n = math.max(1, math.floor(len / 6 + 0.5))
			for i = 1, n - 1 do
				local f = i / n
				local px, pz = a[1] + dx * f, a[2] + dz * f
				Kit.box(
					parts,
					{ px, y0 + sill + (h - sill - beam) / 2, pz },
					sz(0.4, h - sill - beam, t * 0.8),
					C.GridBlue,
					"SmoothPlastic",
					{ Collide = false, Name = "WallGlass" }
				)
			end
		end
	else
		error("unknown wall style " .. st)
	end
end

-- Rectangle of walls (closed ring) given min/max {x, z} corners. opts.gaps = list of { side =, at =, width = }
-- where side is "-x" | "+x" | "-z" | "+z" and `at` is the offset of the gap center along that side from its middle
-- (towards +x / +z).
function Kit.ring(parts: { Part }, minc: { number }, maxc: { number }, kind: any, style: string?, opts: Opts?)
	local o: Opts = opts or {}
	local gaps: { any } = o.gaps or {}
	local x0, z0, x1, z1 = minc[1], minc[2], maxc[1], maxc[2]
	local function side(name: string, a: { number }, b: { number })
		-- collect gap intervals along the side (parameter s from a to b)
		local len = math.abs(b[1] - a[1]) + math.abs(b[2] - a[2])
		local cuts: { { number } } = {}
		for _, g in gaps do
			if g.side == name then
				local mid = len / 2 + (g.at or 0)
				table.insert(cuts, { mid - g.width / 2, mid + g.width / 2 })
			end
		end
		table.sort(cuts, function(p, q)
			return p[1] < q[1]
		end)
		local s = 0
		local function emit(s0: number, s1: number)
			if s1 - s0 < 0.5 then
				return
			end
			local fa, fb = s0 / len, s1 / len
			Kit.wall(
				parts,
				{ a[1] + (b[1] - a[1]) * fa, a[2] + (b[2] - a[2]) * fa },
				{ a[1] + (b[1] - a[1]) * fb, a[2] + (b[2] - a[2]) * fb },
				kind,
				style,
				o
			)
		end
		for _, c in cuts do
			emit(s, c[1])
			s = c[2]
		end
		emit(s, len)
	end
	local t: number = o.thick or 2
	-- x sides run full length, z sides fit between them
	side("-z", { x0, z0 }, { x1, z0 })
	side("+z", { x0, z1 }, { x1, z1 })
	side("-x", { x0, z0 + t / 2 }, { x0, z1 - t / 2 })
	side("+x", { x1, z0 + t / 2 }, { x1, z1 - t / 2 })
end

-- Stairs -------------------------------------------------------------------------

local DIRS: { [string]: { number } } = {
	["+x"] = { 1, 0 },
	["-x"] = { -1, 0 },
	["+z"] = { 0, 1 },
	["-z"] = { 0, -1 },
}
Kit.Dirs = DIRS

-- Solid stairs. `top` = {x, y, z}: point on the edge of the upper surface where the stairs arrive
-- (y = upper surface height). `dir` = direction you walk while going UP ("+x" | "-x" | "+z" | "-z").
-- Steps are at most 1 stud tall (opts.step) and opts.run (default 2) deep; base at opts.base (default 0).
-- Returns the ground point in front of the first step.
function Kit.stairs(parts: { Part }, top: Vec3, dir: string, width: number, opts: Opts?): Vec3
	local o: Opts = opts or {}
	local dv = DIRS[dir]
	assert(dv ~= nil, "bad stairs dir " .. dir)
	local base: number = o.base or 0
	local rise = top[2] - base
	assert(rise > 0, "stairs need rise > 0")
	local maxStep: number = o.step or 1
	local run: number = o.run or 2
	local n = math.ceil(rise / maxStep - 1e-9)
	local h = rise / n
	local colors = { o.color or C.Marble, o.color2 or C.MarbleDark }
	local material: string = o.material or "Marble"
	for k = 1, n do
		-- step k (1 = lowest) lies (n - k) .. (n - k + 1) runs back from the top edge
		local back = (n - k + 0.5) * run
		local cx = top[1] - dv[1] * back
		local cz = top[3] - dv[2] * back
		local hk = h * k
		local size: Vec3 = if dv[1] ~= 0 then { run, hk, width } else { width, hk, run }
		Kit.box(parts, { cx, base + hk / 2, cz }, size, colors[(k % 2) + 1], material, { Name = "Stairs" })
	end
	return v3(top[1] - dv[1] * (n * run + 1), base, top[3] - dv[2] * (n * run + 1))
end

-- Platforms ----------------------------------------------------------------------

-- Low parapet along the edges of a rectangle top. opts.open = list of { side =, at =, width = } openings.
function Kit.parapet(parts: { Part }, center: Vec3, size: { number }, opts: Opts?)
	local o: Opts = opts or {}
	local hw, hd = size[1] / 2, size[2] / 2
	local y = center[2]
	local t = 1
	Kit.ring(
		parts,
		{ center[1] - hw + t / 2, center[3] - hd + t / 2 },
		{ center[1] + hw - t / 2, center[3] + hd - t / 2 },
		o.height or 2,
		"Concrete",
		{ y = y, thick = t, gaps = o.open or {} }
	)
end

-- Platform with its top surface at center.y.
-- opts.style: "Deck" (1-stud slab on 4 pillars, default), "Building" (solid brick block with windows),
--             "Tower" (solid marble block), "Concrete" (solid concrete block).
-- opts.parapet (height, default 0 = none), opts.open = parapet openings (see ring gaps).
function Kit.platform(parts: { Part }, center: Vec3, size: { number }, opts: Opts?)
	local o: Opts = opts or {}
	local style: string = o.style or "Deck"
	local w, d = size[1], size[2]
	local top = center[2]
	local cx, cz = center[1], center[3]
	local base: number = o.base or 0
	if style == "Deck" then
		local t = 1
		Kit.box(parts, { cx, top - t / 2, cz }, { w, t, d }, C.Concrete, "Concrete", { Name = "Platform" })
		local ph = top - t - base
		if ph > 0 then
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					Kit.box(
						parts,
						{ cx + sx * (w / 2 - 1), base + ph / 2, cz + sz * (d / 2 - 1) },
						{ 2, ph, 2 },
						C.ConcreteDark,
						"Concrete",
						{ Name = "Pillar" }
					)
				end
			end
		end
	elseif style == "Building" then
		local hgt = top - base
		Kit.box(parts, { cx, base + hgt / 2, cz }, { w, hgt, d }, C.Brick, "Brick", { Name = "Building" })
		Kit.box(parts, { cx, top - 0.2, cz }, { w + 0.6, 0.4, d + 0.6 }, C.BrickCap, "Concrete", { Name = "Building" })
		-- window bands on all four faces (decorative, thin, non-collidable)
		local rows = math.floor((hgt - 2) / 4)
		for r = 1, rows do
			local wy = base + r * 4 - 0.5
			local deco = { Collide = false, Name = "Window", Transparency = 0.15 }
			Kit.box(parts, { cx, wy, cz - d / 2 - 0.05 }, { w - 3, 1.6, 0.2 }, C.Window, "Glass", deco)
			Kit.box(parts, { cx, wy, cz + d / 2 + 0.05 }, { w - 3, 1.6, 0.2 }, C.Window, "Glass", deco)
			Kit.box(parts, { cx - w / 2 - 0.05, wy, cz }, { 0.2, 1.6, d - 3 }, C.Window, "Glass", deco)
			Kit.box(parts, { cx + w / 2 + 0.05, wy, cz }, { 0.2, 1.6, d - 3 }, C.Window, "Glass", deco)
		end
	elseif style == "Tower" then
		local hgt = top - base
		local cap = 1.5
		local cw = o.column or math.min(w, d) * 0.6
		Kit.box(parts, { cx, base + (hgt - cap) / 2, cz }, { cw, hgt - cap, cw }, C.Marble, "Marble", { Name = "Tower" })
		Kit.box(parts, { cx, top - cap / 2, cz }, { w, cap, d }, C.MarbleDark, "Marble", { Name = "Tower" })
		-- decorative bands
		for _, f in { 0.33, 0.66 } do
			Kit.box(
				parts,
				{ cx, base + (hgt - cap) * f, cz },
				{ cw + 0.6, 0.8, cw + 0.6 },
				C.GridBlue,
				"SmoothPlastic",
				{ Name = "Tower" }
			)
		end
	elseif style == "Concrete" then
		local hgt = top - base
		Kit.box(parts, { cx, base + hgt / 2, cz }, { w, hgt, d }, C.Concrete, "Concrete", { Name = "Block" })
	else
		error("unknown platform style " .. style)
	end
	if o.parapet and o.parapet > 0 then
		Kit.parapet(parts, center, size, { height = o.parapet, open = o.open })
	end
end

-- Axis-aligned bridge deck between a and b ({x, y, z}, same y = deck top) with low side rails.
function Kit.bridge(parts: { Part }, a: Vec3, b: Vec3, width: number, opts: Opts?)
	local o: Opts = opts or {}
	local y = a[2]
	local alongX = math.abs(b[3] - a[3]) < 1e-6
	assert(alongX or math.abs(b[1] - a[1]) < 1e-6, "bridge must be axis aligned")
	local len = if alongX then math.abs(b[1] - a[1]) else math.abs(b[3] - a[3])
	local cx, cz = (a[1] + b[1]) / 2, (a[3] + b[3]) / 2
	local t = 1
	local size: Vec3 = if alongX then { len, t, width } else { width, t, len }
	Kit.box(parts, { cx, y - t / 2, cz }, size, C.Wood, "WoodPlanks", { Name = "Bridge" })
	local rh: number = o.rail or 2.5
	if rh > 0 then
		for _, s in { -1, 1 } do
			local off = s * (width / 2 - 0.25)
			local rc: Vec3 = if alongX then { cx, y + rh / 2, cz + off } else { cx + off, y + rh / 2, cz }
			local rs: Vec3 = if alongX then { len, rh, 0.5 } else { 0.5, rh, len }
			Kit.box(parts, rc, rs, C.WoodDark, "Wood", { Name = "BridgeRail" })
		end
	end
end

-- Props --------------------------------------------------------------------------

-- Wooden crate, 4 studs by default (jumpable). pos = bottom center. opts.rot = yaw degrees.
function Kit.crate(parts: { Part }, pos: Vec3, size: number?, opts: Opts?): Part
	local o: Opts = opts or {}
	local s = size or 4
	local rot: Vec3? = if o.rot then { 0, o.rot, 0 } else nil
	return Kit.block(parts, pos, { s, s, s }, o.color or C.Wood, "WoodPlanks", { Rot = rot, Name = "Crate" })
end

-- A few crates. layout: "row2", "row3", "pyramid" (2 + 1 on top), "L3", "stack2". axis "x" | "z".
function Kit.crates(parts: { Part }, pos: Vec3, layout: string, axis: string?)
	local s = 4
	local ax = axis or "x"
	local function at(i: number, j: number, k: number)
		local dx, dz = i * s, j * s
		if ax == "z" then
			dx, dz = j * s, i * s
		end
		Kit.crate(parts, { pos[1] + dx, pos[2] + k * s, pos[3] + dz }, s, { color = if (i + j + k) % 2 == 0 then C.Wood else "#A06D38" })
	end
	if layout == "row2" then
		at(-0.5, 0, 0)
		at(0.5, 0, 0)
	elseif layout == "row3" then
		at(-1, 0, 0)
		at(0, 0, 0)
		at(1, 0, 0)
	elseif layout == "pyramid" then
		at(-0.5, 0, 0)
		at(0.5, 0, 0)
		at(0, 0, 1)
	elseif layout == "L3" then
		at(0, 0, 0)
		at(1, 0, 0)
		at(0, 1, 0)
	elseif layout == "stack2" then
		at(0, 0, 0)
		at(0, 0, 1)
	else
		error("unknown crate layout " .. layout)
	end
end

-- Red barrel (cylinder, 4 tall, 3 wide). pos = bottom center.
function Kit.barrel(parts: { Part }, pos: Vec3)
	Kit.cylinder(parts, pos, 4, 3, C.Barrel, "SmoothPlastic", { Name = "Barrel" })
	for _, y in { 0.9, 3.1 } do
		Kit.cylinder(
			parts,
			{ pos[1], pos[2] + y - 0.15, pos[3] },
			0.3,
			3.15,
			C.BarrelBand,
			"Metal",
			{ Collide = false, Name = "Barrel" }
		)
	end
end

-- Cartoon tree: brown trunk + stacked green balls (style "Ball") or blocks (style "Block").
-- opts.scale (default 1). Footprint of the trunk is small; leaves start above head height.
function Kit.tree(parts: { Part }, pos: Vec3, opts: Opts?)
	local o: Opts = opts or {}
	local s: number = o.scale or 1
	local style: string = o.style or "Ball"
	local trunkH = 7 * s
	local x, y, z = pos[1], pos[2], pos[3]
	if style == "Ball" then
		Kit.cylinder(parts, pos, trunkH, 1.6 * s, C.Trunk, "Wood", { Name = "Tree" })
		Kit.ball(parts, { x, y + trunkH + 1.5 * s, z }, 8 * s, C.Leaf2, "Grass", { Name = "Tree" })
		Kit.ball(parts, { x + 0.6 * s, y + trunkH + 5.2 * s, z - 0.4 * s }, 6 * s, C.Leaf1, "Grass", { Name = "Tree" })
		Kit.ball(parts, { x - 0.3 * s, y + trunkH + 8.2 * s, z + 0.3 * s }, 3.6 * s, C.Leaf3, "Grass", { Name = "Tree" })
	else
		Kit.block(parts, pos, { 1.6 * s, trunkH, 1.6 * s }, C.Trunk, "Wood", { Name = "Tree" })
		Kit.block(parts, { x, y + trunkH - 1 * s, z }, { 8 * s, 3 * s, 8 * s }, C.Leaf2, "Grass", { Name = "Tree" })
		Kit.block(parts, { x, y + trunkH + 2 * s, z }, { 5.5 * s, 3 * s, 5.5 * s }, C.Leaf1, "Grass", { Name = "Tree" })
		Kit.block(parts, { x, y + trunkH + 5 * s, z }, { 3 * s, 2.4 * s, 3 * s }, C.Leaf3, "Grass", { Name = "Tree" })
	end
end

-- Fence ring (pen) around center ({x, y, z} ground) of size {w, d}. Posts every ~4 studs and three rails
-- with gaps < 1 stud, top at opts.height (default 4.5: a player can hop over, walking enemies cannot pass).
-- Returns a "Pen" gimmick record (CONTRACT §1.10) for the map's Gimmicks list.
function Kit.pen(parts: { Part }, center: Vec3, size: { number }, opts: Opts?): Gimmick
	local o: Opts = opts or {}
	local h: number = o.height or 4.5
	local w, d = size[1], size[2]
	local cx, y, cz = center[1], center[2], center[3]
	local railH = 0.7
	local railYs = { h * 0.22, h * 0.56, h - railH / 2 }
	local edges = {
		{ { cx - w / 2, cz - d / 2 }, { cx + w / 2, cz - d / 2 } },
		{ { cx - w / 2, cz + d / 2 }, { cx + w / 2, cz + d / 2 } },
		{ { cx - w / 2, cz - d / 2 }, { cx - w / 2, cz + d / 2 } },
		{ { cx + w / 2, cz - d / 2 }, { cx + w / 2, cz + d / 2 } },
	}
	for ei, e in edges do
		local a, b = e[1], e[2]
		local alongX = ei <= 2
		local len = if alongX then b[1] - a[1] else b[2] - a[2]
		local mx, mz = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
		for _, ry in railYs do
			local sz: Vec3 = if alongX then { len, railH, 0.4 } else { 0.4, railH, len }
			Kit.box(parts, { mx, y + ry, mz }, sz, C.Fence, "WoodPlanks", { Name = "Pen" })
		end
		local n = math.max(1, math.floor(len / 4 + 0.5))
		local first = if ei <= 2 then 0 else 1 -- corners only once
		local last = if ei <= 2 then n else n - 1
		for i = first, last do
			local f = i / n
			local px = a[1] + (b[1] - a[1]) * f
			local pz = a[2] + (b[2] - a[2]) * f
			Kit.box(parts, { px, y + (h + 0.4) / 2, pz }, { 0.8, h + 0.4, 0.8 }, C.FencePost, "Wood", { Name = "Pen" })
		end
	end
	return {
		Type = "Pen",
		Id = o.id or "Pen",
		Attr = { X = cx, Z = cz, W = w, D = d, Height = h },
	}
end

-- Chalkboard. pos = ground point under the board, faceTo = {x, z} the board should face.
-- Adds the wooden frame/legs as parts and a `Board` marker at the panel center (MapBuilder turns
-- the marker into the visible dark-green panel with the text). opts.w (12), opts.h (7), opts.lift (2.5).
function Kit.board(parts: { Part }, markers: { Marker }, pos: Vec3, faceTo: { number }, opts: Opts?): Marker
	local o: Opts = opts or {}
	local bw: number = o.w or 12
	local bh: number = o.h or 7
	local lift: number = o.lift or 2.5
	local rot = Kit.faceRot(pos, faceTo)
	local yaw = math.rad(rot[2])
	-- local axes: right = (cos, 0, -sin), back (+Z local) = (sin, 0, cos)
	local rx, rz = math.cos(yaw), -math.sin(yaw)
	local bx, bz = math.sin(yaw), math.cos(yaw)
	local cy = pos[2] + lift + bh / 2
	local function at(right: number, back: number, y: number): Vec3
		return { pos[1] + rx * right + bx * back, y, pos[3] + rz * right + bz * back }
	end
	local frame = { Rot = rot, Name = "BoardFrame" }
	-- backing panel 0.6 behind the board face, legs at both sides, top and bottom rails
	Kit.box(parts, at(0, 0.7, cy), { bw + 1.2, bh + 1.2, 0.6 }, C.BoardFrame, "WoodPlanks", frame)
	for _, s in { -1, 1 } do
		Kit.box(parts, at(s * (bw / 2 + 0.4), 0.7, (pos[2] + cy + bh / 2 + 0.6) / 2), { 0.8, cy + bh / 2 + 0.6 - pos[2], 0.8 }, C.WoodDark, "Wood", frame)
	end
	Kit.box(parts, at(0, 0.1, cy - bh / 2 - 0.35), { bw + 0.6, 0.5, 1.0 }, C.BoardFrame, "WoodPlanks", frame) -- chalk tray
	local attr: Attr = { Width = bw, Height = bh }
	local m: Marker = { Tag = "Board", Pos = v3(pos[1], cy, pos[3]), Rot = rot, Attr = attr }
	table.insert(markers, m)
	return m
end

-- Lamp post with a glowing head (parts named "Light" get a PointLight from MapBuilder).
function Kit.lamp(parts: { Part }, pos: Vec3, opts: Opts?)
	local o: Opts = opts or {}
	local h: number = o.height or 9
	Kit.cylinder(parts, pos, h, 0.6, C.LampPost, "Metal", { Name = "LampPost" })
	Kit.box(parts, { pos[1], pos[2] + h + 0.6, pos[3] }, { 1.6, 1.2, 1.6 }, o.color or C.Lamp, "Neon", { Name = "Light" })
end

-- Bench (2 studs tall seat), yaw degrees.
function Kit.bench(parts: { Part }, pos: Vec3, yaw: number?)
	local rot: Vec3 = { 0, yaw or 0, 0 }
	local r = math.rad(yaw or 0)
	local rx, rz = math.cos(r), -math.sin(r)
	local bx, bz = math.sin(r), math.cos(r)
	local function at(right: number, back: number, y: number): Vec3
		return { pos[1] + rx * right + bx * back, pos[2] + y, pos[3] + rz * right + bz * back }
	end
	Kit.box(parts, at(0, 0, 1.75), { 7, 0.5, 2 }, C.Bench, "WoodPlanks", { Rot = rot, Name = "Bench" })
	Kit.box(parts, at(0, 0.85, 3), { 7, 2, 0.4 }, C.Bench, "WoodPlanks", { Rot = rot, Name = "Bench" })
	for _, s in { -1, 1 } do
		Kit.box(parts, at(s * 3, 0, 0.75), { 0.5, 1.5, 1.8 }, C.LampPost, "Metal", { Rot = rot, Name = "Bench" })
	end
end

-- Markers --------------------------------------------------------------------------

function Kit.marker(markers: { Marker }, tag: string, pos: Vec3, attr: Attr?, id: string?, rot: Vec3?): Marker
	local m: Marker = { Tag = tag, Pos = v3(pos[1], pos[2], pos[3]) }
	if rot then
		m.Rot = rot
	end
	if id then
		m.Id = id
	end
	if attr then
		m.Attr = attr
	end
	table.insert(markers, m)
	return m
end

-- Player spawn standing on `surface` ({x, y, z}, y = floor top), facing faceTo ({x, z}) if given.
function Kit.playerSpawn(markers: { Marker }, surface: Vec3, faceTo: { number }?, id: string?): Marker
	local rot = if faceTo then Kit.faceRot(surface, faceTo) else nil
	return Kit.marker(markers, "PlayerSpawn", { surface[1], surface[2] + Kit.SpawnLift, surface[3] }, nil, id, rot)
end

-- Row of player spawns centered at `surface`, `spacing` apart along axis "x" | "z".
function Kit.spawnRow(markers: { Marker }, surface: Vec3, count: number, spacing: number, axis: string, faceTo: { number }?)
	for i = 1, count do
		local off = (i - (count + 1) / 2) * spacing
		local p: Vec3 = if axis == "x"
			then { surface[1] + off, surface[2], surface[3] }
			else { surface[1], surface[2], surface[3] + off }
		Kit.playerSpawn(markers, p, faceTo, "Spawn" .. i)
	end
end

-- Spawn pad decoration (thin green plate) under a spawn group.
function Kit.spawnPad(parts: { Part }, center: Vec3, size: { number })
	Kit.patch(parts, center, size, C.SpawnPad, "SmoothPlastic", { Name = "SpawnPad" })
end

-- Red spawn zone. opts.weight (1), opts.zone (10), opts.id, opts.hasKey, opts.keyColor.
function Kit.red(markers: { Marker }, surface: Vec3, opts: Opts?): Marker
	local o: Opts = opts or {}
	local attr: Attr = { Kind = "Red", Weight = o.weight or 1, Zone = o.zone or 10 }
	if o.hasKey then
		attr.HasKey = true
		attr.KeyColor = o.keyColor or "Red"
	end
	return Kit.marker(markers, "EnemySpawn", { surface[1], surface[2] + Kit.EnemyLift, surface[3] }, attr, o.id)
end

-- Non-target spawn group (Kind default "White"). opts.count (2), opts.zone (14), opts.kind, opts.id.
function Kit.enemy(markers: { Marker }, surface: Vec3, opts: Opts?): Marker
	local o: Opts = opts or {}
	local attr: Attr = { Kind = o.kind or "White", Count = o.count or 2, Zone = o.zone or 14 }
	if o.hasKey then
		attr.HasKey = true
		attr.KeyColor = o.keyColor or "Red"
	end
	return Kit.marker(markers, "EnemySpawn", { surface[1], surface[2] + Kit.EnemyLift, surface[3] }, attr, o.id)
end
Kit.white = Kit.enemy

-- Weapon pickup floating above `surface`. id must be unique within the map.
function Kit.weapon(markers: { Marker }, surface: Vec3, weapon: string, id: string): Marker
	local attr: Attr = { Weapon = weapon }
	return Kit.marker(markers, "WeaponPickup", { surface[1], surface[2] + Kit.PickupLift, surface[3] }, attr, id)
end

-- Small display pedestal for a pickup (1 stud tall marble plinth). Returns the surface point on top.
function Kit.plinth(parts: { Part }, pos: Vec3, size: number?): Vec3
	local s = size or 3
	Kit.block(parts, pos, { s, 1, s }, C.Marble, "Marble", { Name = "Plinth" })
	return { pos[1], pos[2] + 1, pos[3] }
end

return Kit
