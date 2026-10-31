--!strict
-- Lobby plaza (built at the world origin as workspace.Lobby). Owner: D.
-- Compact tiled plaza: 8 spawn spots on a red-and-white target emblem facing a big board,
-- benches, trees in the corners, a few crates and barrels. Players wait here between rounds.
return function(K: any): any
	local parts, markers = {}, {}
	local C = K.C
	local W, D = 64, 64

	K.floor(parts, { 0, 0, 0 }, { W, D }, "Tile", { tile = 8 })
	K.perimeter(parts, { W, D }, { height = 16, post = 8 })

	-- grass borders along the walls
	K.patch(parts, { 0, 0, -D / 2 + 3 }, { W, 6 }, C.Grass, "Grass")
	K.patch(parts, { 0, 0, D / 2 - 3 }, { W, 6 }, C.Grass, "Grass")
	K.patch(parts, { -W / 2 + 3, 0, 0 }, { 6, D - 12 }, C.Grass, "Grass")
	K.patch(parts, { W / 2 - 3, 0, 0 }, { 6, D - 12 }, C.Grass, "Grass")

	-- target emblem (flat discs) in the middle: the spawn ring
	K.cylinder(parts, { 0, 0, 2 }, 0.2, 22, "#F4F1EA", "SmoothPlastic", { Name = "Emblem" })
	K.cylinder(parts, { 0, 0.2, 2 }, 0.1, 15, C.Barrel, "SmoothPlastic", { Name = "Emblem", Collide = false })
	K.cylinder(parts, { 0, 0.25, 2 }, 0.1, 8, "#F4F1EA", "SmoothPlastic", { Name = "Emblem", Collide = false })
	K.cylinder(parts, { 0, 0.3, 2 }, 0.1, 3, C.Barrel, "SmoothPlastic", { Name = "Emblem", Collide = false })

	-- big board on the north side facing the plaza
	K.board(parts, markers, { 0, 0, -21 }, { 0, 2 }, { w = 22, h = 9, lift = 3 })

	-- 8 spawns on a ring around the emblem, all facing the board
	for i = 1, 8 do
		local a = (i - 1) / 8 * 2 * math.pi
		K.playerSpawn(markers, { math.cos(a) * 7, 0.2, 2 + math.sin(a) * 7 }, { 0, -21 }, string.format("Lobby%d", i))
	end

	-- benches facing the middle (east / west) and south
	K.bench(parts, { -20, 0, 4 }, -90)
	K.bench(parts, { 20, 0, 4 }, 90)
	K.bench(parts, { -10, 0, 22 }, 0)
	K.bench(parts, { 10, 0, 22 }, 0)

	-- corner trees, crates and barrels
	K.tree(parts, { -26, 0.2, -26 }, { scale = 1.1 })
	K.tree(parts, { 26, 0.2, -26 }, { scale = 1.1 })
	K.tree(parts, { -26, 0.2, 26 }, { style = "Block" })
	K.tree(parts, { 26, 0.2, 26 }, { style = "Block" })
	K.crates(parts, { -22, 0, -14 }, "pyramid", "z")
	K.crate(parts, { 23, 0, -15 }, 4, { rot = 20 })
	K.barrel(parts, { 19, 0, -18 })
	K.barrel(parts, { -18, 0, 15 })

	-- lamps at the board corners
	K.lamp(parts, { -14, 0, -20 })
	K.lamp(parts, { 14, 0, -20 })

	return { Name = "Lobby", Size = { W, 24, D }, Parts = parts, Markers = markers }
end
