-- Dumps every enemy's shell list (world-space rest pose) to build/models/<Kind>.json
-- for tools/model_preview/render.py. Run from the repo root: lune run tools/model_preview/dump.luau
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local EnemyBody = require("../../src/shared/Models/EnemyBody")
local Enemies = require("../../src/shared/Config/Enemies")

fs.writeDir("build/models")
local count = 0
for kind, cfg in pairs(Enemies) do
	if type(cfg) == "table" and type(cfg.Body) == "string" then
		for _, style in ipairs(EnemyBody.Styles) do
		local shells = EnemyBody.shells(kind, cfg.Body, cfg.Accent or "#222222", style)
		if shells then
			local out = {}
			for _, s in ipairs(shells) do
				local bone = EnemyBody.Bones[s.Bone]
				assert(bone, "unknown bone " .. tostring(s.Bone))
				table.insert(out, {
					Shape = s.Shape,
					Size = s.Size,
					Pos = { bone[1] + s.Pos[1], bone[2] + s.Pos[2], bone[3] + s.Pos[3] },
					Rot = s.Rot or { 0, 0, 0 },
					Color = s.Color,
					Material = s.Material or "SmoothPlastic",
					Name = s.Name or s.Bone,
				})
			end
			local label = kind .. " · " .. (EnemyBody.StyleNames[style] or style)
			fs.writeFile("build/models/" .. kind .. "_" .. style .. ".json", serde.encode("json", { Kind = label, Shells = out }))
			count += 1
		end
		end
	end
end
print(("%d models dumped"):format(count))
