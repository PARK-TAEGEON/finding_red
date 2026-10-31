--!strict
-- Server bootstrap. Owner: orchestrator.
-- Every service is required with its contract type, so a signature mismatch fails type checking.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)

local Services = script.Parent.Services
local Data: Types.DataService = require(Services.DataService)
local Flow: Types.StageFlow = require(Services.StageFlow)
local Stage: Types.StageService = require(Services.StageService)
local Enemy: Types.EnemyService = require(Services.EnemyService)
local Weapon: Types.WeaponService = require(Services.WeaponService)

local ctx: Types.Context = {
	Services = { Data = Data, Flow = Flow, Stage = Stage, Enemy = Enemy, Weapon = Weapon },
	Remotes = Net.create(),
}

-- Flow last: it starts the match loop once everything else is ready.
Stage:Init(ctx)
Data:Init(ctx)
Enemy:Init(ctx)
Weapon:Init(ctx)
Flow:Init(ctx)

Stage:Start()
Data:Start()
Enemy:Start()
Weapon:Start()
Flow:Start()

game:GetService("Players").PlayerRemoving:Connect(function(player)
	Net.forget(player)
end)

print("[FindingRed] server ready")
