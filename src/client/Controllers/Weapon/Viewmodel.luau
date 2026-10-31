--!strict
-- First-person viewmodel: code-built arms + weapon parented to the camera, posed every frame with
-- idle bob, walk bob, recoil kick, bat swing, reload tilt, equip raise and aim (ADS). Owner: A.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local WeaponModels = require(Shared.Models.WeaponModels)

local Viewmodel = {}

local player = Players.LocalPlayer

local rig: Model? = nil
local weaponModel: Model? = nil
local rightArm: WeaponModels.Arm? = nil
local leftArm: WeaponModels.Arm? = nil
local hold: WeaponModels.Hold? = nil
local currentId: string? = nil

local visible = false
local aiming = false
local aimAlpha = 0
local walkPhase = 0
local walkAmount = 0
local kick = 0 -- recoil, decays to 0
local kickScale = 1
local swingStart = -1
local SWING_TIME = 0.38
local reloadStart = -1
local reloadDuration = 0
local equipStart = -1
local EQUIP_TIME = 0.25

local SHOULDER_R = Vector3.new(0.95, -1.75, 0.35)
local SHOULDER_L = Vector3.new(-0.95, -1.75, 0.35)

local function skinColor(): Color3?
	local character = player.Character
	local colors = character and character:FindFirstChildOfClass("BodyColors")
	if colors then
		return colors.RightArmColor3
	end
	return nil
end

local function shirtColor(): Color3?
	local character = player.Character
	local colors = character and character:FindFirstChildOfClass("BodyColors")
	if colors then
		return colors.TorsoColor3
	end
	return nil
end

local function camera(): Camera?
	return workspace.CurrentCamera
end

local function attach()
	local r = rig
	local cam = camera()
	if not r then
		return
	end
	if visible and cam then
		if r.Parent ~= cam then
			r.Parent = cam
		end
	elseif r.Parent ~= nil then
		r.Parent = nil
	end
end

function Viewmodel.setWeapon(id: string?)
	if id == currentId and rig then
		return
	end
	if rig then
		rig:Destroy()
		rig, weaponModel, rightArm, leftArm, hold = nil, nil, nil, nil, nil
	end
	currentId = id
	reloadStart, swingStart, kick = -1, -1, 0
	if not id then
		return
	end
	local model = Instance.new("Model")
	model.Name = "FR_Viewmodel"
	local w = WeaponModels.build(id)
	w.Parent = model
	local skin, sleeve = skinColor(), shirtColor()
	local r = WeaponModels.arm("RightArm", skin, sleeve)
	local l = WeaponModels.arm("LeftArm", skin, sleeve)
	r.Model.Parent = model
	l.Model.Parent = model
	rig, weaponModel, rightArm, leftArm = model, w, r, l
	hold = WeaponModels.hold(id)
	kickScale = if id == "Sniper" then 2.2 elseif id == "Pistol" then 1 else 1.3
	equipStart = os.clock()
	attach()
end

function Viewmodel.setVisible(on: boolean)
	visible = on
	attach()
end

function Viewmodel.setAim(on: boolean)
	aiming = on
end

function Viewmodel.kick(amount: number?)
	kick = math.min(kick + (amount or 1), 2)
end

function Viewmodel.swing()
	swingStart = os.clock()
end

function Viewmodel.startReload(duration: number)
	reloadStart = os.clock()
	reloadDuration = math.max(0.1, duration)
end

function Viewmodel.cancelReload()
	reloadStart = -1
end

function Viewmodel.muzzlePosition(): Vector3?
	local w = weaponModel
	if w and rig and rig.Parent then
		return WeaponModels.muzzlePosition(w)
	end
	return nil
end

local function smooth(current: number, target: number, speed: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-speed * dt))
end

-- moveSpeed: horizontal speed of the character in studs/s.
function Viewmodel.update(dt: number, moveSpeed: number, grounded: boolean)
	local cam = camera()
	local w, h = weaponModel, hold
	if not visible or not rig or not cam or not w or not h then
		return
	end
	if rig.Parent ~= cam then
		rig.Parent = cam
	end
	local now = os.clock()

	aimAlpha = smooth(aimAlpha, if aiming and h.Aim then 1 else 0, 14, dt)
	local walkTarget = if grounded then math.clamp(moveSpeed / 16, 0, 1.5) else 0
	walkAmount = smooth(walkAmount, walkTarget, 8, dt)
	walkPhase += dt * (5 + 5 * walkAmount)
	kick = smooth(kick, 0, 10, dt)

	local base = h.Offset
	if h.Aim and aimAlpha > 0.001 then
		base = h.Offset:Lerp(h.Aim, aimAlpha)
	end
	local sway = 1 - aimAlpha * 0.85
	local bob = Vector3.new(
		math.sin(walkPhase) * 0.06 * walkAmount,
		-math.abs(math.cos(walkPhase)) * 0.06 * walkAmount + math.sin(now * 1.7) * 0.012,
		0
	) * sway

	-- equip: raise from below
	local equipT = math.clamp((now - equipStart) / EQUIP_TIME, 0, 1)
	local down = (1 - equipT) ^ 2
	local equipCf = CFrame.new(0, -0.9 * down, 0) * CFrame.Angles(-0.8 * down, 0, 0)

	-- reload: tilt down and roll
	local reloadCf = CFrame.new()
	if reloadStart >= 0 then
		local p = (now - reloadStart) / reloadDuration
		if p >= 1 then
			reloadStart = -1
		else
			local tilt = math.sin(math.pi * math.clamp(p, 0, 1))
			reloadCf = CFrame.new(0, -0.25 * tilt, 0.1 * tilt) * CFrame.Angles(-0.55 * tilt, 0, 0.6 * tilt)
		end
	end

	-- bat swing (camera-space rotation around the grip): short wind-up to the right, then a fast
	-- strike that sweeps the tip from upper-right across to the left and forward, and back.
	local swingCf = CFrame.new()
	if swingStart >= 0 then
		local s = (now - swingStart) / SWING_TIME
		if s >= 1 then
			swingStart = -1
		else
			local wind = if s < 0.18 then math.sin(math.pi * s / 0.18) else 0
			local strike = if s >= 0.12 then math.sin(math.pi * math.clamp((s - 0.12) / 0.88, 0, 1)) else 0
			local grip = base.Position
			swingCf = CFrame.new(grip)
				* CFrame.new(-0.7 * strike, 0.1 * strike, -0.2 * strike)
				* CFrame.Angles(-0.6 * strike, 0, 0)
				* CFrame.Angles(0, 0, 1.9 * strike - 0.3 * wind)
				* CFrame.new(-grip)
		end
	end

	-- recoil: pitch the muzzle up and push back
	local k = kick * kickScale
	local recoilCf = CFrame.new(0, 0.02 * k, 0.12 * k) * CFrame.Angles(0.09 * k, 0, 0)

	local camCf = cam.CFrame
	local final = camCf * CFrame.new(bob) * swingCf * base * equipCf * reloadCf * recoilCf
	w:PivotTo(final)

	local ra, la = rightArm, leftArm
	if ra then
		WeaponModels.placeArm(ra, camCf * (SHOULDER_R + bob), final * h.Right)
	end
	if la then
		WeaponModels.placeArm(la, camCf * (SHOULDER_L + bob), final * h.Left)
	end
end

return Viewmodel
