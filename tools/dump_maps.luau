-- Map dump (Lune). Owner: D.
-- Loads Kit + every map module in src/server/Maps (except helper modules), validates each one
-- (src/server/Maps/Validate.luau) and writes build/maps/<Name>.json for tools/map_preview.py.
-- Run from the repo root: lune run tools/dump_maps.luau   (exit code 1 on validation errors)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local Kit = require("../src/server/Maps/Kit")
local Validate = require("../src/server/Maps/Validate")

local MAPS_DIR = "src/server/Maps"
local HELPERS = { Kit = true, Validate = true }
local LOBBY = "Lobby"

if not fs.isDir(MAPS_DIR) then
	print("run from the repo root (missing " .. MAPS_DIR .. ")")
	process.exit(2)
end

local names = {}
for _, file in fs.readDir(MAPS_DIR) do
	local name = string.match(file, "^(.+)%.luau$")
	if name and not HELPERS[name] then
		table.insert(names, name)
	end
end
table.sort(names, function(a, b)
	if a == LOBBY then
		return b ~= LOBBY
	elseif b == LOBBY then
		return false
	end
	return a < b
end)

fs.writeDir("build/maps")
local failed, totalErrors = 0, 0
for _, name in names do
	local ok, result = pcall(function()
		local build = require("../src/server/Maps/" .. name)
		return build(Kit)
	end)
	if not ok then
		print(string.format("FAIL %s: map module errored: %s", name, tostring(result)))
		failed += 1
		totalErrors += 1
		continue
	end
	local spec = result
	local report = Validate.run(spec, { stage = name ~= LOBBY })
	if spec.Name ~= name then
		table.insert(report.errors, string.format("%s: spec.Name %q differs from module name", name, tostring(spec.Name)))
	end
	local out = {
		Name = spec.Name,
		Size = spec.Size,
		Parts = spec.Parts,
		Markers = spec.Markers,
		Gimmicks = spec.Gimmicks or {},
		Validation = { Errors = report.errors, Warnings = report.warnings, Stats = report.stats },
	}
	if report.grid and report.reach then
		local g = report.grid
		out.Reach = { Res = g.res, NX = g.nx, NZ = g.nz, X0 = g.x0, Z0 = g.z0, Cells = report.reach }
	end
	fs.writeFile("build/maps/" .. name .. ".json", serde.encode("json", out, false))
	local st = report.stats
	print(string.format(
		"%s %s: %d parts, %d markers, red weight %s, reach %s%%, traps %s, reds seen from spawn %s",
		if #report.errors == 0 then "ok  " else "FAIL",
		name,
		#spec.Parts,
		#spec.Markers,
		tostring(st.redWeight),
		tostring(st.reachablePct),
		tostring(st.trapCells),
		tostring(st.redMarkersVisibleFromSpawn)
	))
	for _, e in report.errors do
		print("  error: " .. e)
	end
	for _, w in report.warnings do
		print("  warn:  " .. w)
	end
	if #report.errors > 0 then
		failed += 1
		totalErrors += #report.errors
	end
end

if failed > 0 then
	print(string.format("%d maps, %d failed (%d errors)", #names, failed, totalErrors))
	process.exit(1)
end
print(string.format("%d maps ok", #names))
