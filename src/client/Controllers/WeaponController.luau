--!strict
-- STUB (orchestrator). Owner: A.
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local WeaponController = {}

function WeaponController.Init(self: Types.WeaponController, ctx: Types.ClientContext) end
function WeaponController.Start(self: Types.WeaponController) end
function WeaponController.SetEnabled(self: Types.WeaponController, on: boolean) end
function WeaponController.Attack(self: Types.WeaponController, down: boolean) end
function WeaponController.Aim(self: Types.WeaponController, on: boolean) end
function WeaponController.Reload(self: Types.WeaponController) end
function WeaponController.Cycle(self: Types.WeaponController) end

return WeaponController
