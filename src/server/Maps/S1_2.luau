--!strict
-- Stage 1-2 "높은 곳" (high places). Owner: D. ~110×110, Day.
-- Idea: Reds stand on rooftops. Two rooftops are reachable by stairs (brick house west, concrete block east);
-- a marble tower at the far north end is NOT reachable on foot but sits at the end of a clear sniping lane
-- straight up the middle from the start-room door. The Sniper lies on the start room floor (v0.5).
-- One White wanders the open middle field to punish players who run straight in.
return function(K: any): any
	local parts, markers = {}, {}
	local C = K.C
	local W, D = 110, 110

	K.floor(parts, { 0, 0, 0 }, { W, D }, "Tile")
	K.perimeter(parts, { W, D })

	-- Start room (south middle) with the Sniper lying on its floor. The door (x = 2) opens straight onto
	-- the sniping lane up the middle of the arena.
	local room = K.startRoomSouth(parts, markers, D, 0)
	K.weapon(markers, room.spots[1], "Sniper", "S1_2_Sniper")
	K.lamp(parts, { -11, 0, 40 })
	K.lamp(parts, { 11, 0, 40 })

	-- Health behind the west low wall, ammo east of the lane by the crate L
	K.health(markers, { -30, 0, 20 }, "S1_2_Health")
	K.ammo(markers, { 31, 0, 2 }, "S1_2_Ammo")

	-- West: brick house, roof at 8, stairs along the west wall going north ----------------
	K.platform(parts, { -44, 8, -16 }, { 22, 20 }, {
		style = "Building",
		parapet = 2,
		open = { { side = "+z", at = -8, width = 7 } },
	})
	K.stairs(parts, { -52, 8, -6 }, "-z", 6)
	K.red(markers, { -42, 8, -17 }, { weight = 1, zone = 5, id = "RoofWest" })

	-- East: concrete block, roof at 12, stairs from the south ---------------------------
	K.platform(parts, { 39, 12, -23 }, { 18, 18 }, {
		style = "Concrete",
		parapet = 2,
		open = { { side = "+z", at = 5, width = 7 } },
	})
	K.stairs(parts, { 44, 12, -14 }, "-z", 6, { material = "Concrete", color = C.Concrete, color2 = C.ConcreteDark })
	K.red(markers, { 37, 12, -24 }, { weight = 1, zone = 5, id = "RoofEast" })

	-- North: marble tower perch (top 24), only reachable by bullets ------------------
	K.platform(parts, { 0, 24, -40 }, { 12, 12 }, { style = "Tower", parapet = 2, column = 7 })
	K.red(markers, { 0, 24, -40 }, { weight = 1, zone = 4, id = "Perch" })

	-- Ground: one White in the middle field, cover on both sides of the lane --------------
	K.white(markers, { 0, 0, -6 }, { count = 1, zone = 14 })
	K.wall(parts, { -34, 16 }, { -14, 16 }, "Low", "Brick")
	K.wall(parts, { 14, 16 }, { 34, 16 }, "Low", "Brick")
	K.crates(parts, { -24, 0, 22 }, "row2")
	K.crates(parts, { 24, 0, 22 }, "pyramid")
	K.crate(parts, { -38, 0, 14 }, 4, { rot = 20 })
	K.crates(parts, { 26, 0, -6 }, "L3", "z")
	K.barrel(parts, { 30, 0, -12 })
	K.barrel(parts, { 49, 0, -2 })
	K.crates(parts, { -26, 0, -32 }, "stack2")
	K.barrel(parts, { -20, 0, -30 })

	-- corner trees and the far corners behind the buildings
	K.tree(parts, { -46, 0, 44 }, { scale = 1.1 })
	K.tree(parts, { 46, 0, 44 }, { style = "Block" })
	K.tree(parts, { -46, 0, -46 }, { scale = 0.9 })
	K.tree(parts, { 46, 0, -46 }, { scale = 0.9 })
	K.crates(parts, { 26, 0, -46 }, "row2")
	K.wall(parts, { -32, -44 }, { -16, -44 }, "Low", "Hedge")

	return { Name = "S1_2", Size = { W, 40, D }, Parts = parts, Markers = markers }
end
