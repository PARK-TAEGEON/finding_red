--!strict
-- STUB (orchestrator). Owner: A. Replace with the real weapon system.
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local WeaponService = {}

function WeaponService.Init(self: Types.WeaponService, ctx: Types.Context) end
function WeaponService.Start(self: Types.WeaponService) end
function WeaponService.PrepareStage(self: Types.WeaponService, handle: Types.StageHandle) end
function WeaponService.ClearStage(self: Types.WeaponService) end
function WeaponService.GiveLoadout(self: Types.WeaponService, player: Player) end
function WeaponService.StripLoadout(self: Types.WeaponService, player: Player) end
function WeaponService.AddAmmoPercent(self: Types.WeaponService, player: Player, percent: number) end
function WeaponService.Explode(
	self: Types.WeaponService,
	center: Vector3,
	radius: number,
	enemyDamage: number,
	playerDamage: number,
	byPlayer: Player?
) end

return WeaponService
