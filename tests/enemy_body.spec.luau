-- Orchestrator test: enemy shell bodies are well-formed and pure.
local fs = require("@lune/fs")
local EnemyBody = require("../src/shared/Models/EnemyBody")
local Enemies = require("../src/shared/Config/Enemies")

local checks = 0
local function check(cond: boolean, label: string)
	checks += 1
	assert(cond, label)
end

local SHAPES = { Block = true, Ball = true, Cylinder = true, Wedge = true, Ellipsoid = true }
local src = string.gsub(fs.readFile("src/shared/Models/EnemyBody.luau"), "%-%-[^\n]*", "") -- code only, no comments
for _, banned in ipairs({ "game", "workspace", "Vector3", "Color3", "CFrame", "Enum", "Instance", "require" }) do
	check(not string.find(src, "[^%w_%.]" .. banned .. "[%.%(%:]"), "EnemyBody uses no " .. banned)
end

for _, kind in ipairs({ "Red", "White" }) do
	local cfg = Enemies[kind]
	local shells = EnemyBody.shells(kind, cfg.Body, cfg.Accent)
	check(shells ~= nil and #shells >= 20, kind .. " has a full body")
	local top = 0
	for _, s in ipairs(shells :: any) do
		local bone = EnemyBody.Bones[s.Bone]
		check(bone ~= nil and s.Bone ~= "HumanoidRootPart", kind .. " shell on a visible bone: " .. tostring(s.Bone))
		check(SHAPES[s.Shape] == true, kind .. " known shape " .. tostring(s.Shape))
		check(#s.Size == 3 and s.Size[1] > 0 and s.Size[2] > 0 and s.Size[3] > 0, kind .. " positive size")
		check(type(s.Color) == "string" and string.match(s.Color, "^#%x%x%x%x%x%x$") ~= nil, kind .. " hex color")
		top = math.max(top, bone[2] + s.Pos[2] + s.Size[2] / 2)
	end
	check(top > 5 and top < 6.6, kind .. " height ~5-6.5 studs (" .. top .. ")")
	check(top <= EnemyBody.Bones.Head[2] + EnemyBody.HeadTop + 0.3, kind .. " HP bar clears the head")
end
check(EnemyBody.shells("Bomb", "#000000", "#FFFFFF") == nil, "unknown kinds keep the plain rig")
check(EnemyBody.mix("#000000", "#FFFFFF", 0.5) == "#808080", "color mix")

print(("enemy_body.spec: %d checks passed"):format(checks))
