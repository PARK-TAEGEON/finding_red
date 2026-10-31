--!strict
-- Asset registry (CONTRACT §3.8). Owner: orchestrator.
-- Assets.get("Weapon/Pistol") clones ReplicatedStorage.Assets.Weapon.Pistol, or returns nil
-- so the caller can fall back to its code-built model.
local Assets = {}

function Assets.get(key: string): Instance?
	local root = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local node: Instance? = root
	for part in string.gmatch(key, "[^/]+") do
		if not node then
			return nil
		end
		node = node:FindFirstChild(part)
	end
	if node and node ~= root then
		return node:Clone()
	end
	return nil
end

function Assets.has(key: string): boolean
	local clone = Assets.get(key)
	if clone then
		clone:Destroy()
		return true
	end
	return false
end

return Assets
