-- Orchestrator regression test (review v0.5 #1): a perched Red chasing a player on the ground
-- must keep its goal on its own floor, inside its zone, instead of walking off the roof.
local EnemyLogic = require("../src/shared/EnemyLogic")
local Enemies = require("../src/shared/Config/Enemies")

local checks = 0
local function check(cond: boolean, label: string)
	checks += 1
	assert(cond, label)
end

local cfg = Enemies.Red
local home = { 0, 24, 0 } -- tower top
local zone = 4
local brain = EnemyLogic.new("Red", cfg, home, zone, 0)
local player = { Id = 1, Pos = { 15, 3, 15 } } -- on the ground, ~30 studs away, in sight

local now = 0
local sawGoal = false
for _ = 1, 200 do
	now += 0.1
	local action = EnemyLogic.step(brain, cfg, {
		Now = now,
		Pos = home,
		Players = { player },
		Random = function()
			return 0.5
		end,
	})
	if action.Goal then
		sawGoal = true
		check(math.abs(action.Goal[2] - home[2]) < 0.01, "goal stays on the perch floor")
		local dx, dz = action.Goal[1] - home[1], action.Goal[3] - home[3]
		check(math.sqrt(dx * dx + dz * dz) <= zone + 0.01, "goal stays inside the zone")
	end
	check(action.Attack == nil, "cannot hit a player 21 studs below")
end
check(sawGoal, "the brain produced goals")

-- Same-level chase still goes straight at the player.
local ground = EnemyLogic.new("Red", cfg, { 0, 3, 0 }, 10, 0)
local lastGoal = nil
now = 0
for _ = 1, 30 do
	now += 0.1
	local a = EnemyLogic.step(ground, cfg, { Now = now, Pos = { 0, 3, 0 }, Players = { { Id = 1, Pos = { 20, 3, 0 } } } })
	lastGoal = a.Goal or lastGoal
end
check(lastGoal ~= nil and lastGoal[1] > 15, "same-level chase targets the player")

print(("perch.spec: %d checks passed"):format(checks))
