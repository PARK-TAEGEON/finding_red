--!strict
-- STUB (orchestrator). Owner: A.
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local CameraController = {}

function CameraController.Init(self: Types.CameraController, ctx: Types.ClientContext) end
function CameraController.Start(self: Types.CameraController) end
function CameraController.SetFirstPerson(self: Types.CameraController, on: boolean) end
function CameraController.SetZoom(self: Types.CameraController, fov: number?) end
function CameraController.SetSensitivity(self: Types.CameraController, value: number) end

return CameraController
