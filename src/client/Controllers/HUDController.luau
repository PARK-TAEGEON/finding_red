--!strict
-- STUB (orchestrator). Owner: C.
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local HUDController = {}

function HUDController.Init(self: Types.HUDController, ctx: Types.ClientContext) end
function HUDController.Start(self: Types.HUDController) end
function HUDController.Toast(self: Types.HUDController, text: string) end

return HUDController
