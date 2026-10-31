--!strict
-- Stage 1-1 "그냥 찾기" (just find it). Owner: D. ~90×90, Day.
-- Idea: one Red hides in one of four corners, each corner a different look (brick room NW, tree grove NE,
-- crate yard SW, garden SE). The party starts in a closed start room in the middle of the south wall
-- (v0.5); a broken low-wall square with a tree in the centre and a few crates break the sight lines so
-- players follow the radar. One health box east of the centre square.
return function(K: any): any
	local parts, markers = {}, {}
	local C = K.C
	local W, D = 90, 90

	K.floor(parts, { 0, 0, 0 }, { W, D }, "Tile")
	K.perimeter(parts, { W, D })

	-- Start room (south middle): spawns at the west end look at the board on the east wall,
	-- the white door in the north wall opens onto the arena. Nothing to pick up in 1-1.
	K.startRoomSouth(parts, markers, D, 0)
	K.lamp(parts, { -11, 0, 30 })
	K.lamp(parts, { 11, 0, 30 })
	K.health(markers, { 13, 0, -4 }, "S1_1_Health")

	-- Centre: broken low brick square around a tree --------------------------------
	K.ring(parts, { -9, -12 }, { 9, 4 }, "Low", "Brick", {
		gaps = {
			{ side = "-z", at = 0, width = 7 },
			{ side = "+z", at = 0, width = 7 },
			{ side = "-x", at = 0, width = 6 },
			{ side = "+x", at = 0, width = 6 },
		},
	})
	K.tree(parts, { 0, 0, -4 }, { scale = 1.2 })
	K.crates(parts, { -18, 0, 14 }, "row2")
	K.crate(parts, { 17, 0, 12 }, 4, { rot = 15 })
	K.crate(parts, { 21, 0, 15 }, 4)
	K.barrel(parts, { 14, 0, -20 })
	K.barrel(parts, { -14, 0, -22 })

	-- NW: brick room with a doorway in its south-east corner -------------------------
	K.wall(parts, { -20, -45 }, { -20, -27 }, "Mid", "Brick")
	K.wall(parts, { -45, -20 }, { -29, -20 }, "Mid", "Brick")
	K.crates(parts, { -40, 0, -40 }, "pyramid")
	K.crate(parts, { -26, 0, -40 }, 4)
	K.barrel(parts, { -40, 0, -27 })
	K.red(markers, { -33, 0, -33 }, { weight = 1, zone = 9 })

	-- NE: tree grove behind a hedge ---------------------------------------------------
	K.patch(parts, { 31, 0, -31 }, { 26, 26 }, C.Grass, "Grass")
	K.wall(parts, { 18, -15 }, { 34, -15 }, "Low", "Hedge")
	K.tree(parts, { 24, 0.2, -38 })
	K.tree(parts, { 38, 0.2, -36 }, { scale = 0.9 })
	K.tree(parts, { 37, 0.2, -22 }, { scale = 1.1 })
	K.tree(parts, { 24, 0.2, -24 }, { scale = 0.8 })
	K.red(markers, { 31, 0.2, -30 }, { weight = 1, zone = 10 })

	-- SW: crate yard hidden behind a concrete wall ----------------------------------
	K.wall(parts, { -16, 8 }, { -16, 30 }, "Mid", "Concrete")
	K.crates(parts, { -38, 0, 14 }, "L3")
	K.crates(parts, { -26, 0, 34 }, "row2", "z")
	K.crate(parts, { -38, 0, 34 }, 4, { rot = 30 })
	K.crates(parts, { -24, 0, 15 }, "stack2")
	K.barrel(parts, { -42, 0, 26 })
	K.red(markers, { -31, 0, 24 }, { weight = 1, zone = 9 })

	-- SE: garden bed (low brick U) with a tree and barrels -----------------------------
	K.patch(parts, { 33, 0, 29 }, { 18, 16 }, C.GrassDark, "Grass")
	K.wall(parts, { 22, 20 }, { 22, 38 }, "Low", "Brick")
	K.wall(parts, { 22, 19 }, { 40, 19 }, "Low", "Brick")
	K.tree(parts, { 38, 0.2, 36 }, { style = "Block" })
	K.barrel(parts, { 41, 0, 23 })
	K.barrel(parts, { 41, 0, 27 })
	K.red(markers, { 32, 0.2, 29 }, { weight = 1, zone = 8 })

	return { Name = "S1_1", Size = { W, 30, D }, Parts = parts, Markers = markers }
end
