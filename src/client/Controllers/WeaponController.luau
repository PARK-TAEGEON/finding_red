--!strict
-- Client weapons: input (LMB/RMB/R/1-4/Q), viewmodel, client raycast + Fire claims, aim/scope,
-- reload, crosshair/hit marker, tracers and pickup displays (CONTRACT §2.7, §3.5). Owner: A.
-- The server re-validates everything; this side only mirrors rate/ammo to avoid spamming the remote.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local WeaponMath = require(Shared.WeaponMath)
local WeaponsConfig = require(Shared.Config.Weapons)

local WeaponFolder = script.Parent:WaitForChild("Weapon")
local Viewmodel = require(WeaponFolder:WaitForChild("Viewmodel"))
local Overlay = require(WeaponFolder:WaitForChild("Overlay"))
local Fx = require(WeaponFolder:WaitForChild("Fx"))
local ThirdPerson = require(WeaponFolder:WaitForChild("ThirdPerson"))

type Spec = WeaponsConfig.WeaponSpec

local WeaponController = {}

local player = Players.LocalPlayer
local ctx: Types.ClientContext
local fireRemote: RemoteEvent
local reloadRemote: RemoteEvent
local equipRemote: RemoteEvent

local enabled = false
local list: { string } = {}
local equipped: string? = nil
local lastLocalEquip = -math.huge
local lastEquipResend = 0
local localMag: { [string]: number } = {}
local localAmmo: { [string]: number } = {}
local lastShotClock: { [string]: number } = {}
local nextFire: { [string]: number } = {}
local triggerHeld = false
local aiming = false
local scoped = false
local reloadWeapon: string? = nil
local reloadUntil = 0

local SLOT_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
}

-- Server time at which the player saw the world they shot at: now minus replication delay and
-- interpolation (review fix #4). The server clamps T to [now-0.4, now+0.1].
local function seenTime(): number
	local ping = 0
	pcall(function()
		ping = game:GetService("Players").LocalPlayer:GetNetworkPing()
	end)
	return workspace:GetServerTimeNow() - math.clamp(ping, 0, 0.25) - 0.1
end

local function specOf(id: string?): Spec?
	if id == nil or id == "Order" or id == "Default" then
		return nil
	end
	local spec = WeaponsConfig[id]
	if type(spec) ~= "table" or type(spec.Kind) ~= "string" then
		return nil
	end
	return spec :: Spec
end

local function alive(): boolean
	local life = player:GetAttribute("Life")
	return life == nil or life == "Alive"
end

local function camera(): Camera?
	return workspace.CurrentCamera
end

local function preferred(ids: { string }): string?
	if table.find(ids, "Pistol") then
		return "Pistol"
	end
	return ids[1]
end

-- Raycast ---------------------------------------------------------------------------------------
local function enemyModelOf(inst: Instance): Model?
	local node: Instance? = inst
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute("EnemyId") ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- Returns (hit position or nil, enemy id or nil).
local function castShot(origin: Vector3, dir: Vector3, range: number): (Vector3?, number?)
	local exclude: { Instance } = {}
	local cam = camera()
	if cam then
		table.insert(exclude, cam)
	end
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(exclude, other.Character) -- no friendly fire: shots pass through players
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	for _ = 1, 6 do
		params.FilterDescendantsInstances = exclude
		local hit = workspace:Raycast(origin, dir * range, params)
		if not hit then
			return nil, nil
		end
		local enemy = enemyModelOf(hit.Instance)
		if enemy then
			local id = enemy:GetAttribute("EnemyId")
			if enemy:GetAttribute("State") == "Dead" or type(id) ~= "number" then
				table.insert(exclude, enemy) -- corpses flying away do not stop bullets
			else
				return hit.Position, id
			end
		elseif hit.Instance.Transparency >= 0.95 and not hit.Instance.CanCollide then
			table.insert(exclude, hit.Instance) -- invisible triggers
		else
			return hit.Position, nil
		end
	end
	return nil, nil
end

-- Equip / aim / reload ---------------------------------------------------------------------------------
local function refreshVisuals()
	local spec = specOf(equipped)
	local showModel = enabled and equipped ~= nil and not scoped
	Viewmodel.setVisible(showModel)
	Overlay.setEnabled(enabled)
	Overlay.setCrosshair(enabled and spec ~= nil)
	Overlay.setScope(enabled and scoped)
end

local function setAim(on: boolean)
	local spec = specOf(equipped)
	if on and (not enabled or not alive() or not spec or spec.Kind == "Melee" or reloadWeapon ~= nil) then
		on = false
	end
	if on == aiming then
		return
	end
	aiming = on
	scoped = on and spec ~= nil and spec.Scope == true
	ctx.Controllers.Camera:SetZoom(if on and spec then (spec.AimFov or 55) else nil)
	Viewmodel.setAim(on and not scoped)
	refreshVisuals()
end

local function cancelLocalReload()
	reloadWeapon = nil
	Viewmodel.cancelReload()
end

local function equip(id: string, tellServer: boolean)
	if id == equipped or not table.find(list, id) then
		return
	end
	cancelLocalReload()
	setAim(false)
	equipped = id
	Viewmodel.setWeapon(id)
	refreshVisuals()
	if tellServer then
		lastLocalEquip = os.clock()
		equipRemote:FireServer(id)
	end
end

local function startReload(): boolean
	local id = equipped
	local spec = specOf(id)
	if not id or not spec or spec.Mag == nil or reloadWeapon ~= nil then
		return false
	end
	if not WeaponMath.canReload(spec.Mag, localMag[id] or 0, localAmmo[id] or 0) then
		return false
	end
	setAim(false)
	reloadWeapon = id
	local duration = spec.Reload or 1
	reloadUntil = os.clock() + duration
	Viewmodel.startReload(duration)
	ctx.PlaySound("Reload")
	reloadRemote:FireServer(id)
	return true
end

local function finishReloadIfDue()
	local id = reloadWeapon
	if id and os.clock() >= reloadUntil then
		reloadWeapon = nil
		local spec = specOf(id)
		if spec then
			localMag[id], localAmmo[id] = WeaponMath.reload(spec.Mag, localMag[id] or 0, localAmmo[id] or 0)
		end
		-- If the server never reloaded (request dropped), fall back to its numbers shortly after.
		local doneAt = os.clock()
		task.delay(0.6, function()
			if (lastShotClock[id] or -math.huge) < doneAt and reloadWeapon == nil then
				local mag, ammo = player:GetAttribute("Mag_" .. id), player:GetAttribute("Ammo_" .. id)
				if type(mag) == "number" and type(ammo) == "number" then
					localMag[id], localAmmo[id] = mag, ammo
				end
			end
		end)
	end
end

-- Fire ----------------------------------------------------------------------------------------------------
local function fire(fresh: boolean)
	if not enabled or not alive() or ctx.State().Phase ~= "Playing" then
		return
	end
	local id = equipped
	local spec = specOf(id)
	if not id or not spec then
		return
	end
	if spec.Kind ~= "Melee" and spec.Kind ~= "Hitscan" then
		return -- Throw/Projectile: later wave
	end
	if not fresh and not spec.Auto then
		return
	end
	local now = os.clock()
	if now < (nextFire[id] or 0) or reloadWeapon ~= nil then
		return
	end
	local cam = camera()
	if not cam then
		return
	end
	local camCf = cam.CFrame
	local origin, dir = camCf.Position, camCf.LookVector
	local head = player.Character and player.Character:FindFirstChild("Head")
	local headPos = if head and head:IsA("BasePart") then head.Position else nil

	if spec.Kind == "Melee" then
		nextFire[id] = now + 1 / spec.Rate
		Viewmodel.swing()
		ctx.PlaySound(spec.Sound)
		if headPos and (origin - headPos).Magnitude > 4 then
			origin = headPos
		end
		fireRemote:FireServer({
			R = ctx.State().RoundId,
			W = id,
			O = origin,
			D = dir,
			T = seenTime(),
		})
		return
	end

	if (localMag[id] or 0) <= 0 then
		nextFire[id] = now + 0.3
		ctx.PlaySound("DryFire")
		startReload()
		return
	end

	local hitPos, enemyId = castShot(origin, dir, spec.Range)
	-- Third-person safety: the server wants the origin near the head, so re-aim from the head
	-- toward what the camera ray hit.
	if headPos and (origin - headPos).Magnitude > 4 then
		local target = hitPos or (origin + dir * spec.Range)
		origin = headPos
		dir = (target - headPos).Unit
	end

	nextFire[id] = now + 1 / spec.Rate
	lastShotClock[id] = now
	localMag[id] = (localMag[id] or 0) - 1
	fireRemote:FireServer({
		R = ctx.State().RoundId,
		W = id,
		O = origin,
		D = dir,
		T = seenTime(),
		Id = enemyId,
		P = hitPos,
	})

	Viewmodel.kick(1)
	ctx.PlaySound(spec.Sound)
	local muzzle = Viewmodel.muzzlePosition() or (origin + dir * 1.5 - Vector3.new(0, 0.4, 0))
	local endPos = hitPos or (origin + dir * math.min(spec.Range, 400))
	if not scoped then
		Fx.flash(muzzle)
	end
	Fx.tracer(muzzle, endPos)
	if hitPos then
		Fx.impact(hitPos, enemyId ~= nil)
	end
	if (localMag[id] or 0) <= 0 and (localAmmo[id] or 0) > 0 then
		task.delay(math.min(0.3, 1 / spec.Rate), function()
			if equipped == id and enabled then
				startReload()
			end
		end)
	end
end

-- Attribute sync (server is the truth) ---------------------------------------------------------------------
local function readWeapons()
	list = WeaponMath.parseList(player:GetAttribute("Weapons"))
	if #list == 0 then
		cancelLocalReload()
		setAim(false)
		equipped = nil
		Viewmodel.setWeapon(nil)
		refreshVisuals()
		return
	end
	if equipped == nil or not table.find(list, equipped) then
		local serverEquipped = player:GetAttribute("Equipped")
		local pick = if type(serverEquipped) == "string" and table.find(list, serverEquipped)
			then serverEquipped
			else preferred(list)
		if pick then
			equip(pick, false)
		end
	end
end

local function readEquipped()
	local value = player:GetAttribute("Equipped")
	if type(value) ~= "string" or value == equipped then
		return
	end
	-- Ignore echoes right after a local switch; otherwise the server changed it (new round loadout).
	if os.clock() - lastLocalEquip > 0.6 and table.find(list, value) then
		equip(value, false)
	end
end

local function readAmmo(id: string)
	local mag = player:GetAttribute("Mag_" .. id)
	local ammo = player:GetAttribute("Ammo_" .. id)
	if type(ammo) == "number" then
		localAmmo[id] = ammo
	end
	if type(mag) == "number" then
		local current = localMag[id]
		-- A late update for an earlier shot must not hand back rounds we already fired locally.
		if current == nil or mag <= current or os.clock() - (lastShotClock[id] or -math.huge) > 0.5 then
			localMag[id] = mag
		end
	end
end

-- Remote events -----------------------------------------------------------------------------------------------
local function otherShooterMuzzle(userId: number, fallback: Vector3): Vector3
	local held = ThirdPerson.muzzle(userId)
	if held then
		return held
	end
	local other = Players:GetPlayerByUserId(userId)
	local character = other and other.Character
	local arm = character and (character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand"))
	if arm and arm:IsA("BasePart") then
		return (arm.CFrame * CFrame.new(0, -arm.Size.Y / 2, -0.5)).Position
	end
	return fallback
end

local function otherRootPos(userId: number): Vector3?
	local other = Players:GetPlayerByUserId(userId)
	local root = other and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function onEffect(kind: any, data: any)
	if type(data) ~= "table" then
		return
	end
	local userId = data.UserId
	local mine = userId == player.UserId
	if kind == "Shot" then
		if mine or typeof(data.From) ~= "Vector3" or typeof(data.To) ~= "Vector3" then
			return
		end
		local from = otherShooterMuzzle(userId, data.From)
		Fx.tracer(from, data.To)
		local spec = specOf(if type(data.W) == "string" then data.W else nil)
		ctx.PlaySound(if spec then spec.Sound else "PistolShot", data.From)
	elseif kind == "Melee" then
		local pos = if type(userId) == "number" then otherRootPos(userId) else nil
		if not mine then
			ctx.PlaySound("BatSwing", pos)
		end
		if data.Target ~= nil then
			ctx.PlaySound("BatHit", if mine then nil else pos)
		end
	elseif kind == "Explosion" then
		if typeof(data.Pos) == "Vector3" and type(data.Radius) == "number" then
			Fx.explosion(data.Pos, data.Radius)
		end
	end
end

local function onFeedback(data: any)
	if type(data) ~= "table" then
		return
	end
	if data.Kind == "Hit" then
		local killed, penalty = data.Killed == true, data.Penalty == true
		Overlay.hit(killed, penalty)
		ctx.PlaySound("HitMarker")
		if penalty then
			ctx.PlaySound("PenaltyKill")
		end
	elseif data.Kind == "PickedUp" then
		if data.Marker ~= nil then
			Fx.hidePickup(tostring(data.Marker))
		end
		ctx.PlaySound("Pickup")
	end
end

-- Contract API ---------------------------------------------------------------------------------------------------
function WeaponController.Init(self: Types.WeaponController, c: Types.ClientContext)
	ctx = c
	fireRemote = Net.event(c.Remotes, "Fire")
	reloadRemote = Net.event(c.Remotes, "Reload")
	equipRemote = Net.event(c.Remotes, "Equip")
end

function WeaponController.Start(self: Types.WeaponController)
	Overlay.init(player:WaitForChild("PlayerGui"))
	Fx.init()
	ThirdPerson.init()

	player:GetAttributeChangedSignal("Weapons"):Connect(readWeapons)
	player:GetAttributeChangedSignal("Equipped"):Connect(readEquipped)
	for _, id in ipairs(WeaponsConfig.Order) do
		player:GetAttributeChangedSignal("Mag_" .. id):Connect(function()
			readAmmo(id)
		end)
		player:GetAttributeChangedSignal("Ammo_" .. id):Connect(function()
			readAmmo(id)
		end)
		readAmmo(id)
	end
	readWeapons()
	player:GetAttributeChangedSignal("Life"):Connect(function()
		if not alive() then
			triggerHeld = false
			setAim(false)
		end
	end)

	Net.event(ctx.Remotes, "Effect").OnClientEvent:Connect(onEffect)
	Net.event(ctx.Remotes, "Feedback").OnClientEvent:Connect(onFeedback)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			WeaponController.Attack(self, true)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			WeaponController.Aim(self, true)
		elseif input.KeyCode == Enum.KeyCode.R then
			WeaponController.Reload(self)
		elseif input.KeyCode == Enum.KeyCode.Q then
			WeaponController.Cycle(self)
		else
			local slot = SLOT_KEYS[input.KeyCode]
			if slot and enabled and list[slot] then
				equip(list[slot], true)
			end
		end
	end)
	-- Releases are handled even when a GUI ate them, so the trigger/aim never stick.
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			WeaponController.Attack(self, false)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			WeaponController.Aim(self, false)
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		triggerHeld = false
		setAim(false)
	end)

	RunService:BindToRenderStep("FR_Viewmodel", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		finishReloadIfDue()
		if triggerHeld then
			fire(false)
		end
		local speed, grounded = 0, true
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") then
			local v = root.AssemblyLinearVelocity
			speed = Vector3.new(v.X, 0, v.Z).Magnitude
		end
		if humanoid then
			grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		end
		Viewmodel.update(dt, speed, grounded)

		-- If an Equip request was throttled away, re-send once a second until the server agrees.
		local serverEquipped = player:GetAttribute("Equipped")
		local now = os.clock()
		if
			enabled
			and equipped
			and serverEquipped ~= nil
			and serverEquipped ~= equipped
			and now - lastLocalEquip > 1
			and now - lastEquipResend > 1
		then
			lastEquipResend = now
			equipRemote:FireServer(equipped)
		end
	end)
	refreshVisuals()
end

function WeaponController.SetEnabled(self: Types.WeaponController, on: boolean)
	if enabled == on then
		return
	end
	enabled = on
	if not on then
		triggerHeld = false
		setAim(false)
	end
	refreshVisuals()
end

function WeaponController.Attack(self: Types.WeaponController, down: boolean)
	-- Start room (Countdown, v0.5): clicks do nothing at all — no swing, no dry fire, and a held
	-- trigger does not start auto-fire the moment the door opens (fire() also checks the phase).
	triggerHeld = down and enabled and ctx.State().Phase == "Playing"
	if down then
		fire(true)
	end
end

function WeaponController.Aim(self: Types.WeaponController, on: boolean)
	setAim(on)
end

function WeaponController.Reload(self: Types.WeaponController)
	if enabled and alive() then
		startReload()
	end
end

function WeaponController.Cycle(self: Types.WeaponController)
	if not enabled then
		return
	end
	local nextId = WeaponMath.cycle(list, equipped, 1)
	if nextId then
		equip(nextId, true)
	end
end

return WeaponController
