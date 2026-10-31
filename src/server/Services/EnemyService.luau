--!strict
-- STUB (orchestrator). Owner: B. Replace with the real enemy system.
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local EnemyService = {}

function EnemyService.Init(self: Types.EnemyService, ctx: Types.Context) end
function EnemyService.Start(self: Types.EnemyService) end
function EnemyService.SpawnStage(self: Types.EnemyService, handle: Types.StageHandle, redCount: number) end
function EnemyService.ClearAll(self: Types.EnemyService) end
function EnemyService.Damage(
	self: Types.EnemyService,
	id: number,
	amount: number,
	byPlayer: Player?,
	cause: Types.KillCause,
	from: Vector3?
): boolean
	return false
end
function EnemyService.Knockback(self: Types.EnemyService, id: number, direction: Vector3, stunSeconds: number) end
function EnemyService.IsAlive(self: Types.EnemyService, id: number): boolean
	return false
end
function EnemyService.GetKind(self: Types.EnemyService, id: number): string?
	return nil
end
function EnemyService.GetRadius(self: Types.EnemyService, id: number): number
	return 2
end
function EnemyService.PositionAt(self: Types.EnemyService, id: number, serverTime: number): Vector3?
	return nil
end
function EnemyService.QueryRadius(self: Types.EnemyService, center: Vector3, radius: number): { number }
	return {}
end

return EnemyService
