--!strict
-- STUB (orchestrator). Owner: C. Replace with the real implementation (OX DataService port).
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local DataService = {}

function DataService.Init(self: Types.DataService, ctx: Types.Context) end
function DataService.Start(self: Types.DataService) end
function DataService.Get(self: Types.DataService, player: Player): Types.Profile?
	return nil
end
function DataService.Mutate(self: Types.DataService, player: Player, fn: (Types.Profile) -> boolean): boolean
	return false
end
function DataService.Save(self: Types.DataService, player: Player, release: boolean): boolean
	return false
end
function DataService.ApplyResult(
	self: Types.DataService,
	player: Player,
	resultId: string,
	stageId: string,
	flags: number,
	seconds: number,
	gold: number,
	redKills: number
): boolean
	return false
end
function DataService.UnlockedStages(self: Types.DataService, player: Player): { string }
	return { "1-1" }
end

return DataService
