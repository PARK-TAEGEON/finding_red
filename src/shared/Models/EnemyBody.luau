--!strict
-- Pure data: the visible "shell" parts of each enemy, welded onto the invisible R6 bones.
-- The R6 bones (Head, Torso, arms, legs) keep the standard sizes/joints so Roblox R6
-- animations and the ragdoll keep working; only these shells are seen.
-- No Roblox globals, no requires (Lune renders it: tools/model_preview).
--
-- Coordinates: each shell is placed in its bone's local space (rest pose, bones axis-aligned,
-- character faces -Z). Rot is degrees, applied like CFrame.Angles(x, y, z).
-- Shape "Ellipsoid" = Block part + SpecialMesh Sphere (non-uniform sphere).
-- Cylinders run along their local X axis (Roblox convention); Rot {0,0,90} stands one up.

export type Shell = {
	Bone: string,
	Shape: "Block" | "Ball" | "Cylinder" | "Wedge" | "Ellipsoid",
	Size: { number },
	Pos: { number },
	Rot: { number }?,
	Color: string,
	Material: string?,
	Name: string?,
}

local EnemyBody = {}

-- Rest-pose bone centers in model space (feet on y = 0), matching EnemyModels' R6 rig.
EnemyBody.Bones = {
	HumanoidRootPart = { 0, 3, 0 },
	Torso = { 0, 3, 0 },
	Head = { 0, 4.5, 0 },
	["Left Arm"] = { -1.5, 3, 0 },
	["Right Arm"] = { 1.5, 3, 0 },
	["Left Leg"] = { -0.5, 1, 0 },
	["Right Leg"] = { 0.5, 1, 0 },
}

-- Height of the top of the head above the Head bone center (for overhead GUIs).
EnemyBody.HeadTop = 1.4

local function mix(a: string, b: string, t: number): string
	local function ch(hex: string, i: number): number
		return tonumber(string.sub(hex, i, i + 1), 16) or 0
	end
	local out = "#"
	for _, i in ipairs({ 2, 4, 6 }) do
		local v = math.floor(ch(a, i) + (ch(b, i) - ch(a, i)) * t + 0.5)
		out ..= string.format("%02X", math.clamp(v, 0, 255))
	end
	return out
end
EnemyBody.mix = mix

local function S(bone: string, shape: any, size: { number }, pos: { number }, color: string, rot: { number }?, material: string?, name: string?): Shell
	return { Bone = bone, Shape = shape, Size = size, Pos = pos, Rot = rot, Color = color, Material = material, Name = name }
end

-- Limbs shared by both kinds: tapered ellipsoid segments (no tubes) with small joints, so the
-- silhouette reads slim and organic instead of blocky. Arms hang slightly toward the torso.
export type LimbStyle = {
	Arm: number, -- upper-arm thickness
	Leg: number, -- thigh thickness
	Hand: number, -- fist size
	Foot: { number }, -- foot size
}
local function limbs(out: { Shell }, style: LimbStyle, skin: string, dark: string, joint: string, hand: string, foot: string)
	local a, l = style.Arm, style.Leg
	for _, side in ipairs({ -1, 1 }) do
		local arm = if side < 0 then "Left Arm" else "Right Arm"
		local leg = if side < 0 then "Left Leg" else "Right Leg"
		local inX = -side * 0.36 -- toward the body (arms tucked in, no T-pose look)
		-- arm: deltoid, upper arm, elbow, forearm (thicker near the wrist), fist
		table.insert(out, S(arm, "Ellipsoid", { a * 1.15, a * 1.1, a * 1.1 }, { inX * 0.8, 0.62, 0 }, skin, { 0, 0, side * -20 }, nil, "Shoulder"))
		table.insert(out, S(arm, "Ellipsoid", { a, 1.35, a }, { inX, 0.1, 0 }, skin, nil, nil, "UpperArm"))
		table.insert(out, S(arm, "Ball", { a * 0.8, a * 0.8, a * 0.8 }, { inX, -0.45, 0 }, joint, nil, nil, "Elbow"))
		table.insert(out, S(arm, "Ellipsoid", { a * 0.9, 1.15, a * 0.92 }, { inX, -0.85, -0.03 }, dark, nil, nil, "Forearm"))
		table.insert(out, S(arm, "Ellipsoid", { style.Hand, style.Hand * 1.1, style.Hand }, { inX, -1.36, -0.05 }, hand, nil, nil, "Hand"))
		-- leg: thigh, knee, calf, foot
		table.insert(out, S(leg, "Ellipsoid", { l, 1.45, l * 1.05 }, { side * 0.06, 0.35, 0 }, dark, nil, nil, "Thigh"))
		table.insert(out, S(leg, "Ball", { l * 0.74, l * 0.74, l * 0.74 }, { side * 0.06, -0.25, -0.04 }, joint, nil, nil, "Knee"))
		table.insert(out, S(leg, "Ellipsoid", { l * 0.78, 1.1, l * 0.85 }, { side * 0.06, -0.58, 0.04 }, dark, nil, nil, "Calf"))
		table.insert(out, S(leg, "Ellipsoid", style.Foot, { side * 0.06, -0.9, -0.2 }, foot, nil, nil, "Foot"))
	end
end

-- Red: lean, hunched little brute with an egg-shaped head, glowing slit eyes, a jagged grin
-- and two swept-back horn spikes.
local function red(body: string, accent: string): { Shell }
	local skin = body
	local dark = mix(body, "#000000", 0.25)
	local deep = mix(body, "#000000", 0.55)
	local light = mix(body, "#FFFFFF", 0.18)
	local out: { Shell } = {}
	-- torso: chest wider than waist, slight forward hunch
	table.insert(out, S("Torso", "Ellipsoid", { 1.7, 1.3, 1.0 }, { 0, 0.42, 0 }, skin, { -8, 0, 0 }, nil, "Chest"))
	table.insert(out, S("Torso", "Ellipsoid", { 1.25, 1.1, 0.88 }, { 0, -0.4, 0.02 }, dark, nil, nil, "Belly"))
	table.insert(out, S("Torso", "Ellipsoid", { 0.9, 0.7, 0.2 }, { 0, -0.3, -0.42 }, light, nil, nil, "BellyPatch"))
	table.insert(out, S("Torso", "Ellipsoid", { 1.3, 0.75, 0.95 }, { 0, -0.98, 0.02 }, dark, nil, nil, "Pelvis"))
	table.insert(out, S("Torso", "Ellipsoid", { 0.62, 0.7, 0.62 }, { 0, 1.0, -0.12 }, dark, nil, nil, "Neck"))
	-- head: tall egg, pushed forward (hunched brute)
	table.insert(out, S("Head", "Ellipsoid", { 1.5, 1.8, 1.45 }, { 0, 0.42, -0.18 }, skin, nil, nil, "Skull"))
	table.insert(out, S("Head", "Ellipsoid", { 1.15, 0.7, 1.0 }, { 0, -0.05, -0.32 }, skin, nil, nil, "Jaw"))
	-- brow ridge
	table.insert(out, S("Head", "Block", { 1.25, 0.2, 0.3 }, { 0, 0.72, -0.8 }, deep, { -12, 0, 0 }, nil, "Brow"))
	-- slit eyes (glowing), angled down toward the nose
	for _, side in ipairs({ -1, 1 }) do
		table.insert(out, S("Head", "Block", { 0.42, 0.17, 0.12 }, { side * 0.31, 0.52, -0.88 }, accent, { 0, 0, side * 14 }, "Neon", "Eye"))
	end
	-- mouth: dark slot with a jagged row of teeth
	table.insert(out, S("Head", "Ellipsoid", { 0.95, 0.34, 0.2 }, { 0, 0.0, -0.8 }, "#1A1014", nil, nil, "Mouth"))
	for i = -2, 2 do
		local up = i % 2 == 0
		table.insert(out, S("Head", "Wedge", { 0.13, 0.17, 0.1 }, { i * 0.17, if up then 0.09 else -0.09, -0.88 }, "#F4F1EA", if up then { 0, 0, 180 } else nil, nil, "Tooth"))
	end
	-- swept-back horn spikes (two segments each)
	for _, side in ipairs({ -1, 1 }) do
		table.insert(out, S("Head", "Wedge", { 0.22, 0.42, 0.5 }, { side * 0.42, 1.22, 0.0 }, deep, { -25, 0, side * -12 }, nil, "Horn"))
	end
	-- spine ridge on the back of the head (reads from behind)
	for i = 0, 2 do
		table.insert(out, S("Head", "Wedge", { 0.14, 0.28, 0.3 }, { 0, 1.0 - i * 0.32, 0.52 + i * 0.03 }, deep, { -70, 180, 0 }, nil, "Spine"))
	end
	limbs(out, { Arm = 0.56, Leg = 0.68, Hand = 0.66, Foot = { 0.62, 0.38, 1.1 } }, skin, dark, dark, skin, deep)
	return out
end

-- White: tall, smooth guard in a round helmet with a wide wraparound black visor and light armor.
local function white(body: string, accent: string): { Shell }
	local skin = body
	local plate = mix(body, "#8A93A6", 0.35)
	local joint = "#3B3F49"
	local out: { Shell } = {}
	table.insert(out, S("Torso", "Ellipsoid", { 1.8, 1.3, 1.05 }, { 0, 0.4, 0 }, skin, nil, nil, "Chest"))
	table.insert(out, S("Torso", "Ellipsoid", { 1.3, 1.0, 0.92 }, { 0, -0.45, 0 }, skin, nil, nil, "Belly"))
	table.insert(out, S("Torso", "Ellipsoid", { 1.45, 1.05, 0.35 }, { 0, 0.45, -0.42 }, plate, { -6, 0, 0 }, nil, "ChestPlate"))
	table.insert(out, S("Torso", "Ellipsoid", { 1.45, 0.3, 1.0 }, { 0, -0.1, 0 }, joint, nil, nil, "Belt"))
	table.insert(out, S("Torso", "Ellipsoid", { 1.3, 0.7, 0.95 }, { 0, -0.98, 0 }, skin, nil, nil, "Pelvis"))
	table.insert(out, S("Torso", "Ellipsoid", { 0.55, 0.6, 0.55 }, { 0, 1.0, 0 }, joint, nil, nil, "Neck"))
	-- helmet: big round dome
	table.insert(out, S("Head", "Ellipsoid", { 1.7, 1.75, 1.65 }, { 0, 0.4, 0 }, skin, nil, nil, "Helmet"))
	-- wraparound visor: front band + two side wings
	table.insert(out, S("Head", "Ellipsoid", { 1.45, 0.46, 0.45 }, { 0, 0.45, -0.66 }, accent, nil, "Glass", "Visor"))
	for _, side in ipairs({ -1, 1 }) do
		table.insert(out, S("Head", "Ellipsoid", { 0.42, 0.42, 0.7 }, { side * 0.7, 0.45, -0.32 }, accent, { 0, side * 35, 0 }, "Glass", "VisorSide"))
	end
	table.insert(out, S("Head", "Block", { 0.35, 0.06, 0.05 }, { -0.35, 0.6, -0.88 }, "#FFFFFF", { 0, 0, 8 }, "Neon", "Glint"))
	-- helmet crest
	table.insert(out, S("Head", "Ellipsoid", { 0.28, 0.4, 1.45 }, { 0, 1.18, 0.05 }, plate, nil, nil, "Crest"))
	-- shoulder pads
	for _, side in ipairs({ -1, 1 }) do
		local arm = if side < 0 then "Left Arm" else "Right Arm"
		table.insert(out, S(arm, "Ellipsoid", { 0.78, 0.36, 0.8 }, { -side * 0.28, 0.92, 0 }, plate, { 0, 0, side * -18 }, nil, "Pad"))
	end
	limbs(out, { Arm = 0.55, Leg = 0.66, Hand = 0.56, Foot = { 0.6, 0.38, 1.0 } }, skin, skin, joint, joint, joint)
	return out
end

-- Style B "Imp": big round head, huge glowing round eyes, pointy ears, fangs and a tail.
local function redImp(body: string, accent: string): { Shell }
	local skin = body
	local dark = mix(body, "#000000", 0.22)
	local deep = mix(body, "#000000", 0.55)
	local light = mix(body, "#FFFFFF", 0.3)
	local out: { Shell } = {}
	table.insert(out, S("Torso", "Ellipsoid", { 1.45, 1.55, 1.15 }, { 0, -0.05, 0 }, skin, nil, nil, "Body"))
	table.insert(out, S("Torso", "Ellipsoid", { 0.95, 0.95, 0.25 }, { 0, -0.2, -0.5 }, light, nil, nil, "Belly"))
	table.insert(out, S("Torso", "Ellipsoid", { 1.15, 0.6, 0.95 }, { 0, -0.95, 0.02 }, dark, nil, nil, "Pelvis"))
	table.insert(out, S("Torso", "Ellipsoid", { 0.75, 0.8, 0.7 }, { 0, 0.95, -0.03 }, dark, nil, nil, "Neck"))
	-- big head
	table.insert(out, S("Head", "Ellipsoid", { 2.0, 1.8, 1.75 }, { 0, 0.45, -0.05 }, skin, nil, nil, "Skull"))
	for _, side in ipairs({ -1, 1 }) do
		-- round glowing eyes with pupils, angry brow
		table.insert(out, S("Head", "Ellipsoid", { 0.55, 0.62, 0.2 }, { side * 0.42, 0.68, -0.86 }, accent, nil, "Neon", "Eye"))
		table.insert(out, S("Head", "Ball", { 0.22, 0.22, 0.22 }, { side * 0.36, 0.62, -0.97 }, "#14100C", nil, nil, "Pupil"))
		table.insert(out, S("Head", "Block", { 0.6, 0.14, 0.2 }, { side * 0.42, 1.02, -0.84 }, deep, { 0, 0, side * 20 }, nil, "Brow"))
		-- pointy ears
		table.insert(out, S("Head", "Wedge", { 0.18, 0.9, 0.55 }, { side * 1.02, 0.85, 0.05 }, skin, { 0, side * 90, side * -35 }, nil, "Ear"))
		-- little horn nubs
		table.insert(out, S("Head", "Ellipsoid", { 0.28, 0.42, 0.28 }, { side * 0.45, 1.45, 0.05 }, deep, { 0, 0, side * -18 }, nil, "Horn"))
		-- fangs
		table.insert(out, S("Head", "Wedge", { 0.14, 0.24, 0.1 }, { side * 0.26, 0.03, -0.87 }, "#F6F3EA", { 0, 0, 180 }, nil, "Fang"))
	end
	table.insert(out, S("Head", "Ellipsoid", { 1.05, 0.26, 0.2 }, { 0, 0.15, -0.82 }, "#1A1014", nil, nil, "Grin"))
	-- tail: three segments curling back, arrow tip
	table.insert(out, S("Torso", "Ellipsoid", { 0.3, 0.3, 0.75 }, { 0, -0.9, 0.78 }, dark, { 25, 0, 0 }, nil, "Tail1"))
	table.insert(out, S("Torso", "Ellipsoid", { 0.26, 0.26, 0.7 }, { 0, -0.7, 1.35 }, dark, { -20, 0, 0 }, nil, "Tail2"))
	table.insert(out, S("Torso", "Wedge", { 0.12, 0.45, 0.4 }, { 0, -0.45, 1.68 }, deep, { -90, 0, 0 }, nil, "TailTip"))
	limbs(out, { Arm = 0.48, Leg = 0.6, Hand = 0.56, Foot = { 0.55, 0.32, 0.9 } }, skin, dark, dark, skin, deep)
	return out
end

local function whiteImp(body: string, accent: string): { Shell }
	local skin = body
	local plate = mix(body, "#8A93A6", 0.3)
	local joint = "#3B3F49"
	local out: { Shell } = {}
	table.insert(out, S("Torso", "Ellipsoid", { 1.55, 1.6, 1.2 }, { 0, -0.05, 0 }, skin, nil, nil, "Body"))
	table.insert(out, S("Torso", "Ellipsoid", { 1.2, 0.6, 1.0 }, { 0, -0.95, 0 }, skin, nil, nil, "Pelvis"))
	table.insert(out, S("Torso", "Ellipsoid", { 1.6, 0.25, 1.25 }, { 0, -0.35, 0 }, joint, nil, nil, "Belt"))
	table.insert(out, S("Torso", "Ellipsoid", { 0.7, 0.75, 0.7 }, { 0, 0.95, 0 }, joint, nil, nil, "Neck"))
	-- big round helmet with one wide visor
	table.insert(out, S("Head", "Ellipsoid", { 2.0, 1.85, 1.8 }, { 0, 0.45, 0 }, skin, nil, nil, "Helmet"))
	table.insert(out, S("Head", "Ellipsoid", { 1.6, 0.6, 0.45 }, { 0, 0.52, -0.75 }, accent, nil, "Glass", "Visor"))
	table.insert(out, S("Head", "Block", { 0.4, 0.07, 0.05 }, { -0.4, 0.68, -0.98 }, "#FFFFFF", { 0, 0, 8 }, "Neon", "Glint"))
	for _, side in ipairs({ -1, 1 }) do
		table.insert(out, S("Head", "Cylinder", { 0.2, 0.55, 0.55 }, { side * 1.0, 0.45, 0 }, plate, nil, nil, "EarCap"))
	end
	table.insert(out, S("Head", "Cylinder", { 0.5, 0.12, 0.12 }, { 0.35, 1.5, 0.1 }, joint, { 0, 0, 90 }, nil, "Antenna"))
	table.insert(out, S("Head", "Ball", { 0.24, 0.24, 0.24 }, { 0.35, 1.8, 0.1 }, "#FF4A4A", nil, "Neon", "AntennaTip"))
	limbs(out, { Arm = 0.5, Leg = 0.62, Hand = 0.5, Foot = { 0.58, 0.34, 0.9 } }, skin, skin, joint, joint, joint)
	return out
end

-- Style C "Brute": wide shoulders, long arms with claws, small head, underbite with tusks, back spikes.
local function redBrute(body: string, accent: string): { Shell }
	local skin = body
	local dark = mix(body, "#000000", 0.3)
	local deep = mix(body, "#000000", 0.6)
	local out: { Shell } = {}
	table.insert(out, S("Torso", "Ellipsoid", { 2.25, 1.35, 1.2 }, { 0, 0.5, 0.05 }, skin, { -14, 0, 0 }, nil, "Chest"))
	table.insert(out, S("Torso", "Ellipsoid", { 1.15, 1.15, 0.85 }, { 0, -0.4, 0.05 }, dark, nil, nil, "Waist"))
	table.insert(out, S("Torso", "Ellipsoid", { 1.25, 0.7, 0.95 }, { 0, -0.98, 0.05 }, deep, nil, nil, "Pelvis"))
	for i = 0, 3 do
		table.insert(out, S("Torso", "Wedge", { 0.16, 0.42, 0.5 }, { 0, 0.95 - i * 0.42, 0.62 }, deep, { -60, 180, 0 }, nil, "Spike"))
	end
	-- small low head pushed forward, heavy brow, big jaw with tusks
	table.insert(out, S("Head", "Ellipsoid", { 1.3, 1.25, 1.3 }, { 0, 0.15, -0.35 }, skin, nil, nil, "Skull"))
	table.insert(out, S("Head", "Ellipsoid", { 1.35, 0.7, 1.15 }, { 0, -0.25, -0.5 }, dark, nil, nil, "Jaw"))
	table.insert(out, S("Head", "Block", { 1.2, 0.26, 0.4 }, { 0, 0.42, -0.86 }, deep, { -10, 0, 0 }, nil, "Brow"))
	for _, side in ipairs({ -1, 1 }) do
		table.insert(out, S("Head", "Ellipsoid", { 0.3, 0.16, 0.1 }, { side * 0.27, 0.26, -1.0 }, accent, nil, "Neon", "Eye"))
		table.insert(out, S("Head", "Wedge", { 0.14, 0.38, 0.14 }, { side * 0.38, -0.02, -1.02 }, "#F2EAD8", nil, nil, "Tusk"))
		table.insert(out, S("Head", "Wedge", { 0.2, 0.5, 0.45 }, { side * 0.55, 0.75, -0.2 }, deep, { -40, 0, side * -25 }, nil, "Horn"))
	end
	-- long arms: extra forearm length + claws
	limbs(out, { Arm = 0.7, Leg = 0.78, Hand = 0.78, Foot = { 0.72, 0.4, 1.15 } }, skin, dark, dark, skin, deep)
	for _, side in ipairs({ -1, 1 }) do
		local arm = if side < 0 then "Left Arm" else "Right Arm"
		for k = -1, 1 do
			table.insert(out, S(arm, "Wedge", { 0.12, 0.38, 0.14 }, { -side * 0.36 + k * 0.18, -1.78, -0.12 }, "#F2EAD8", { 0, 0, 180 }, nil, "Claw"))
		end
	end
	return out
end

local function whiteBrute(body: string, accent: string): { Shell }
	local skin = body
	local plate = mix(body, "#7C8597", 0.45)
	local joint = "#30343D"
	local out: { Shell } = {}
	table.insert(out, S("Torso", "Ellipsoid", { 2.1, 1.35, 1.15 }, { 0, 0.45, 0 }, skin, nil, nil, "Chest"))
	table.insert(out, S("Torso", "Block", { 1.55, 1.1, 0.3 }, { 0, 0.45, -0.52 }, plate, { -6, 0, 0 }, nil, "ChestPlate"))
	table.insert(out, S("Torso", "Ellipsoid", { 1.2, 1.1, 0.9 }, { 0, -0.45, 0 }, skin, nil, nil, "Waist"))
	table.insert(out, S("Torso", "Ellipsoid", { 1.3, 0.7, 0.95 }, { 0, -0.98, 0 }, joint, nil, nil, "Pelvis"))
	-- angular helmet with a narrow glowing slit
	table.insert(out, S("Head", "Ellipsoid", { 1.5, 1.6, 1.55 }, { 0, 0.45, 0 }, skin, nil, nil, "Helmet"))
	table.insert(out, S("Head", "Ellipsoid", { 0.3, 0.45, 1.5 }, { 0, 1.15, 0.05 }, plate, nil, nil, "Crest"))
	table.insert(out, S("Head", "Ellipsoid", { 1.2, 0.5, 0.35 }, { 0, 0.5, -0.62 }, accent, nil, nil, "Faceplate"))
	table.insert(out, S("Head", "Block", { 0.95, 0.12, 0.08 }, { 0, 0.55, -0.79 }, "#46E6FF", nil, "Neon", "Slit"))
	table.insert(out, S("Head", "Ellipsoid", { 1.2, 0.45, 0.4 }, { 0, -0.05, -0.5 }, plate, nil, nil, "Jawguard"))
	for _, side in ipairs({ -1, 1 }) do
		local arm = if side < 0 then "Left Arm" else "Right Arm"
		table.insert(out, S(arm, "Ellipsoid", { 1.2, 0.6, 1.15 }, { -side * 0.15, 0.95, 0 }, plate, { 0, 0, side * -15 }, nil, "Pauldron"))
	end
	limbs(out, { Arm = 0.66, Leg = 0.74, Hand = 0.64, Foot = { 0.7, 0.4, 1.1 } }, skin, skin, joint, joint, joint)
	return out
end

EnemyBody.Styles = { "Sleek", "Imp", "Brute" }
EnemyBody.StyleNames = { Sleek = "A 날렵형", Imp = "B 장난꾸러기형", Brute = "C 짐승형" }
EnemyBody.DefaultStyle = "Sleek"

local BUILDERS: { [string]: { [string]: (string, string) -> { Shell } } } = {
	Sleek = { Red = red, White = white },
	Imp = { Red = redImp, White = whiteImp },
	Brute = { Red = redBrute, White = whiteBrute },
}

-- Returns the shell list for `kind` in `style` (default EnemyBody.DefaultStyle), or nil (caller keeps
-- the plain R6 look) for unknown kinds.
function EnemyBody.shells(kind: string, body: string, accent: string, style: string?): { Shell }?
	local set = BUILDERS[style or EnemyBody.DefaultStyle] or BUILDERS.Sleek
	local build = set[kind]
	if not build then
		return nil
	end
	return build(body, accent)
end

return EnemyBody
