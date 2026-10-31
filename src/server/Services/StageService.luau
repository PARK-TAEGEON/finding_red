--!strict
-- STUB (orchestrator). Owner: D. Replace with the real map loader.
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local StageService = {}

local current: Types.StageHandle? = nil

function StageService.Init(self: Types.StageService, ctx: Types.Context) end
function StageService.Start(self: Types.StageService) end
function StageService.Load(self: Types.StageService, stageId: string): Types.StageHandle
	local model = Instance.new("Model")
	model.Name = "Stage"
	model.Parent = workspace
	local handle: Types.StageHandle = { StageId = stageId, Model = model, Markers = {} }
	current = handle
	return handle
end
function StageService.Unload(self: Types.StageService)
	if current then
		current.Model:Destroy()
		current = nil
	end
end
function StageService.Current(self: Types.StageService): Types.StageHandle?
	return current
end
function StageService.LobbySpawn(self: Types.StageService, index: number): CFrame
	return CFrame.new(index * 4, 5, 0)
end
function StageService.SetBoard(self: Types.StageService, lines: { string }) end
function StageService.SetLobbyBoard(self: Types.StageService, text: string) end
function StageService.GeometryParams(self: Types.StageService): RaycastParams
	return RaycastParams.new()
end

return StageService
