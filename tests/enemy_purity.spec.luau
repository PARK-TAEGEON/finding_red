-- Guards CONTRACT §2.4: EnemyLogic and Config/Enemies stay pure (no Roblox globals, no requires).
-- Owner: B. Run from the repo root (tools/check.sh does).
local fs = require("@lune/fs")

local checks = 0
local FORBIDDEN = { "game", "workspace", "Vector3", "CFrame", "Color3", "Enum", "Instance", "require", "script", "task" }

for _, path in ipairs({ "src/shared/EnemyLogic.luau", "src/shared/Config/Enemies.luau" }) do
	local source = fs.readFile(path)
	-- strip comments and strings so prose does not trigger false positives
	local code = source:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", ""):gsub('"[^"\n]*"', '""')
	for _, word in ipairs(FORBIDDEN) do
		checks += 1
		local found = code:find("%f[%w_]" .. word .. "%f[^%w_]")
		assert(found == nil, ("%s uses forbidden global '%s'"):format(path, word))
	end
end

print(("enemy_purity.spec: %d checks passed"):format(checks))
