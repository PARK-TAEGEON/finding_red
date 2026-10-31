--!strict
-- First/third person camera, zoom (aim / sniper scope) and look sensitivity (CONTRACT §3.5). Owner: A.
-- HUDController (C) calls SetFirstPerson by phase/Life; WeaponController calls SetZoom when aiming;
-- the pause menu calls SetSensitivity (we also follow the player's "Sensitivity" attribute).
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local CameraController = {}

local DEFAULT_FOV = 70
local THIRD_PERSON_ZOOM = 12
local MAX_ZOOM = 30

local player = Players.LocalPlayer
local firstPerson = false
local baseSensitivity = 1
local zoomFov: number? = nil
local fovTween: Tween? = nil

local function camera(): Camera?
	return workspace.CurrentCamera
end

-- Scale mouse sensitivity with the zoom so the sniper scope is not twitchy.
local function applySensitivity()
	local scale = 1
	if zoomFov then
		scale = math.tan(math.rad(zoomFov) / 2) / math.tan(math.rad(DEFAULT_FOV) / 2)
	end
	UserInputService.MouseDeltaSensitivity = math.clamp(baseSensitivity * scale, 0.01, 10)
end

local function applyMouse()
	if firstPerson then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false -- WeaponController draws the crosshair
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

function CameraController.Init(self: Types.CameraController, ctx: Types.ClientContext) end

function CameraController.Start(self: Types.CameraController)
	local cam = camera()
	if cam then
		cam.FieldOfView = DEFAULT_FOV
	end
	local function readAttribute()
		local value = player:GetAttribute("Sensitivity")
		if type(value) == "number" then
			CameraController.SetSensitivity(self, value)
		end
	end
	player:GetAttributeChangedSignal("Sensitivity"):Connect(readAttribute)
	readAttribute()

	-- The default camera scripts own MouseBehavior: LockFirstPerson locks the mouse to the centre
	-- every frame unless a Modal GuiButton (pause menu) is visible.
	-- Hide the OS cursor only while it is actually locked, so a Modal pause menu (C) still shows it.
	RunService:BindToRenderStep("FR_CameraMouse", Enum.RenderPriority.Camera.Value + 1, function()
		if firstPerson then
			local want = UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter
			if UserInputService.MouseIconEnabled ~= want then
				UserInputService.MouseIconEnabled = want
			end
		end
	end)

	player.CharacterAdded:Connect(function()
		-- Re-apply after respawn: the camera module re-reads CameraMode when the character changes.
		task.defer(function()
			CameraController.SetFirstPerson(self, firstPerson)
		end)
	end)
	CameraController.SetFirstPerson(self, false)
end

local applied = false -- SetFirstPerson called at least once

function CameraController.SetFirstPerson(self: Types.CameraController, on: boolean)
	local wasFirst = firstPerson or not applied
	applied = true
	firstPerson = on
	if on then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
	else
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = MAX_ZOOM
		if wasFirst then
			-- Push the camera out of first person: briefly force the minimum zoom, then release it.
			player.CameraMinZoomDistance = THIRD_PERSON_ZOOM
			task.delay(0.1, function()
				if not firstPerson then
					player.CameraMinZoomDistance = 0.5
				end
			end)
		end
		CameraController.SetZoom(self, nil)
	end
	applyMouse()
end

function CameraController.SetZoom(self: Types.CameraController, fov: number?)
	local target = DEFAULT_FOV
	if fov ~= nil and fov == fov and fov >= 1 and fov <= 120 then
		target = fov
		zoomFov = fov
	else
		zoomFov = nil
	end
	applySensitivity()
	local cam = camera()
	if not cam then
		return
	end
	if fovTween then
		fovTween:Cancel()
	end
	local tween = TweenService:Create(
		cam,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = target }
	)
	fovTween = tween
	tween:Play()
end

function CameraController.SetSensitivity(self: Types.CameraController, value: number)
	if type(value) ~= "number" or value ~= value then
		return
	end
	baseSensitivity = math.clamp(value, 0.2, 3)
	applySensitivity()
	-- Touch look speed: Roblox's touch camera ignores MouseDeltaSensitivity and exposes no
	-- scriptable sensitivity, so mobile uses the player's Roblox settings (see report).
end

return CameraController
