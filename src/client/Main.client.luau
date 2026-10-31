--!strict
-- Client bootstrap. Owner: orchestrator.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Audio = require(Shared.Config.Audio)

local Controllers = script.Parent:WaitForChild("Controllers")
local Camera: Types.CameraController = require(Controllers:WaitForChild("CameraController"))
local Weapon: Types.WeaponController = require(Controllers:WaitForChild("WeaponController"))
local Enemy: Types.EnemyFX = require(Controllers:WaitForChild("EnemyFX"))
local HUD: Types.HUDController = require(Controllers:WaitForChild("HUDController"))
local Lobby: Types.LobbyUI = require(Controllers:WaitForChild("LobbyUI"))
local Mobile: Types.MobileControls = require(Controllers:WaitForChild("MobileControls"))

local current: Types.MatchState = {
	Phase = "Lobby",
	RoundId = 0,
	Target = 0,
	Killed = 0,
	PenaltyKills = 0,
	Party = {},
}

local function playSound(key: string, at: Vector3?)
	local id = Audio[key]
	if not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	if at then
		local holder = Instance.new("Part")
		holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch = true, false, false, false
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.Position = at
		holder.Parent = workspace
		sound.Parent = holder
		sound:Play()
		Debris:AddItem(holder, 5)
	else
		sound.Parent = SoundService
		sound:Play()
		Debris:AddItem(sound, 5)
	end
end

local ctx: Types.ClientContext = {
	Remotes = Net.get(),
	Controllers = { Camera = Camera, Weapon = Weapon, Enemy = Enemy, HUD = HUD, Lobby = Lobby, Mobile = Mobile },
	State = function()
		return current
	end,
	SetState = function(state: Types.MatchState)
		current = state
	end,
	PlaySound = playSound,
}

Camera:Init(ctx)
Weapon:Init(ctx)
Enemy:Init(ctx)
HUD:Init(ctx)
Lobby:Init(ctx)
Mobile:Init(ctx)

Camera:Start()
Weapon:Start()
Enemy:Start()
HUD:Start()
Lobby:Start()
Mobile:Start()
