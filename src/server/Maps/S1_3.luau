--!strict
-- Stage 1-3 "섞여 있다" (mixed in). Owner: D. ~120×120, Night.
-- Idea: Reds walk among three White groups in a night garden of low brick walls (jumpable cover).
-- A fenced pen in the north-east holds three more Whites (look, don't touch). The Sniper sits on a plinth
-- inside a small walled shrine in the middle of the map, right next to the northern White group,
-- so grabbing it is a risk. Lamp posts keep every area lit.
return function(K: any): any
	local parts, markers = {}, {}
	local gimmicks = {}
	local C = K.C
	local W, D = 120, 120

	K.floor(parts, { 0, 0, 0 }, { W, D }, "Tile", { tile = 12 })
	K.perimeter(parts, { W, D })

	-- Spawn (south middle) + board ----------------------------------------------------
	K.spawnPad(parts, { 0, 0, 53 }, { 16, 6 })
	K.spawnRow(markers, { 0, 0.2, 53 }, 4, 3.5, "x", { 0, 0 })
	K.board(parts, markers, { 0, 0, 44 }, { 0, 53 }, { w = 10, h = 6 })
	K.lamp(parts, { -10, 0, 50 })
	K.lamp(parts, { 10, 0, 50 })
	-- a little cover between the spawn and the middle (crate stacks block the first look)
	K.crates(parts, { -14, 0, 28 }, "stack2")
	K.crates(parts, { 12, 0, 24 }, "stack2")
	K.tree(parts, { 4, 0, 32 }, { style = "Block", scale = 0.8 })

	-- Centre shrine with the Sniper (gaps on all four sides) --------------------------
	K.patch(parts, { 0, 0, -8 }, { 14, 14 }, C.Marble, "Marble")
	K.ring(parts, { -7, -15 }, { 7, -1 }, "Low", "Brick", {
		y = 0.2,
		gaps = {
			{ side = "-z", at = 0, width = 6 },
			{ side = "+z", at = 0, width = 6 },
			{ side = "-x", at = 0, width = 6 },
			{ side = "+x", at = 0, width = 6 },
		},
	})
	local top = K.plinth(parts, { 0, 0.2, -8 })
	K.weapon(markers, top, "Sniper", "S1_3_Sniper")
	K.lamp(parts, { -9, 0, 1 })
	K.lamp(parts, { 9, 0, -17 })

	-- West garden: big White group with a Red among them ---------------------------------
	K.white(markers, { -36, 0, 14 }, { count = 3, zone = 16 })
	K.red(markers, { -30, 0, 22 }, { weight = 1, zone = 12 })
	K.wall(parts, { -50, 2 }, { -32, 2 }, "Low", "Brick")
	K.wall(parts, { -22, 18 }, { -22, 34 }, "Low", "Brick")
	K.wall(parts, { -46, 30 }, { -36, 30 }, "Low", "Brick")
	K.crates(parts, { -44, 0, 20 }, "row2", "z")
	K.tree(parts, { -52, 0, 48 }, { scale = 1.1 })
	K.tree(parts, { -36, 0, 46 }, { style = "Block", scale = 0.9 })
	K.lamp(parts, { -26, 0, 4 })
	K.lamp(parts, { -52, 0, 12 })

	-- North: White pair patrolling between hedges, a Red behind them ---------------------
	K.white(markers, { 0, 0, -32 }, { count = 2, zone = 14 })
	K.red(markers, { -8, 0, -42 }, { weight = 1, zone = 12 })
	K.wall(parts, { -16, -24 }, { -16, -42 }, "Low", "Hedge")
	K.wall(parts, { 14, -26 }, { 14, -48 }, "Low", "Brick")
	K.barrel(parts, { 6, 0, -50 })
	K.barrel(parts, { -4, 0, -24 })
	K.lamp(parts, { 0, 0, -52 })

	-- North-west: walled garden corner with a lone Red ---------------------------------
	-- (an L of low walls against the perimeter: no narrow alley behind it)
	K.wall(parts, { -60, -32 }, { -48, -32 }, "Low", "Brick")
	K.wall(parts, { -40, -32 }, { -30, -32 }, "Low", "Brick")
	K.wall(parts, { -30, -60 }, { -30, -50 }, "Low", "Brick")
	K.wall(parts, { -30, -42 }, { -30, -33 }, "Low", "Brick")
	K.patch(parts, { -45, 0, -46 }, { 26, 24 }, C.GrassDark, "Grass")
	K.tree(parts, { -53, 0.2, -53 }, { scale = 0.9 })
	K.crates(parts, { -36, 0.2, -54 }, "row2")
	K.red(markers, { -44, 0.2, -45 }, { weight = 1, zone = 9 })
	K.lamp(parts, { -26, 0, -28 })

	-- East: White pair with a Red around crate stacks ------------------------------------
	K.white(markers, { 36, 0, 16 }, { count = 2, zone = 14 })
	K.red(markers, { 30, 0, 8 }, { weight = 1, zone = 12 })
	K.wall(parts, { 26, 0 }, { 46, 0 }, "Low", "Brick")
	K.wall(parts, { 22, 22 }, { 22, 38 }, "Low", "Brick")
	K.crates(parts, { 44, 0, 24 }, "pyramid", "z")
	K.crate(parts, { 30, 0, 30 }, 4, { rot = 25 })
	K.barrel(parts, { 50, 0, 10 })
	K.tree(parts, { 50, 0, 48 }, { scale = 1.1 })
	K.lamp(parts, { 26, 0, 4 })
	K.lamp(parts, { 52, 0, 34 })

	-- North-east: the pen (Whites stay inside the fence) ---------------------------------
	K.patch(parts, { 38, 0, -38 }, { 22, 22 }, C.Grass, "Grass")
	table.insert(gimmicks, K.pen(parts, { 38, 0.2, -38 }, { 22, 22 }, { id = "PenNE" }))
	K.white(markers, { 38, 0.2, -38 }, { count = 3, zone = 7 })
	K.red(markers, { 18, 0, -16 }, { weight = 1, zone = 10 })
	K.lamp(parts, { 24, 0, -26 })
	K.lamp(parts, { 52, 0, -22 })

	return { Name = "S1_3", Size = { W, 30, D }, Parts = parts, Markers = markers, Gimmicks = gimmicks }
end
