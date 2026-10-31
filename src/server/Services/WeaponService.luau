--!strict
-- Weapons: loadouts, ammo, shot validation, melee, pickups, explosions (CONTRACT §1.9, §2.7). Owner: A.
-- Server-authoritative. Clients only claim "I shot from O toward D and hit enemy Id at P";
-- every number is re-checked with WeaponMath + raycasts against Stage:GeometryParams().
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local WeaponMath = require(Shared.WeaponMath)
local WeaponsConfig = require(Shared.Config.Weapons)
local WeaponModels = require(Shared.Models.WeaponModels)
-- Agent B owns this file and may still be filling it: read it defensively as untyped data.
local EnemiesConfig: { [string]: any } = require(Shared.Config.Enemies) :: any

type Spec = WeaponsConfig.WeaponSpec

local WeaponService = {}

local PICKUP_TAG = "WeaponPickupDisplay"
local PICKUP_REACH = 4
local PICKUP_INTERVAL = 0.2
local RELOAD_SERVER_FACTOR = 0.9 -- server finishes a little early so the client's "done" never races it

type PlayerState = {
	Owned: { [string]: boolean },
	RoundOnly: { [string]: boolean },
	List: { string },
	Has: { [string]: boolean },
	Mag: { [string]: number },
	Ammo: { [string]: number },
	Equipped: string?,
	LastShot: { [string]: number },
	ReloadToken: number,
	ReloadWeapon: string?,
}

type Pickup = { MarkerId: string, Weapon: string, Pos: Vector3, Model: Model }

local ctx: Types.Context
local effectRemote: RemoteEvent
local feedbackRemote: RemoteEvent
local states: { [Player]: PlayerState } = {}
local claimed: { [Player]: { [string]: boolean } } = {}
local pickups: { Pickup } = {}
local pickupFolder: Folder? = nil

-- Helpers --------------------------------------------------------------------------------------
local function specOf(id: any): Spec?
	if type(id) ~= "string" or id == "Order" or id == "Default" then
		return nil
	end
	local spec = WeaponsConfig[id]
	if type(spec) ~= "table" or type(spec.Kind) ~= "string" then
		return nil
	end
	return spec :: Spec
end

local function vec(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

local function isPenaltyKind(kind: string?): boolean
	if kind == nil then
		return false
	end
	local entry = EnemiesConfig[kind]
	return type(entry) == "table" and entry.Penalty == true
end

local function characterPart(player: Player, name: string): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild(name)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function geometryParams(): RaycastParams
	return ctx.Services.Stage:GeometryParams()
end

-- Enemies and characters never count as cover (defensive: GeometryParams should exclude them anyway).
local function isCover(inst: Instance): boolean
	local model = inst:FindFirstAncestorOfClass("Model")
	while model do
		if model:GetAttribute("EnemyId") ~= nil or Players:GetPlayerFromCharacter(model) then
			return false
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return true
end

-- True when no map geometry lies between `from` and `to` (stops just short of `to`).
local function lineClear(from: Vector3, to: Vector3): boolean
	local offset = to - from
	local dist = offset.Magnitude
	if dist < 0.5 then
		return true
	end
	local dir = offset / dist
	local params = geometryParams()
	local start = from
	local remaining = dist - 0.3
	for _ = 1, 4 do
		if remaining <= 0 then
			return true
		end
		local hit = workspace:Raycast(start, dir * remaining, params)
		if not hit then
			return true
		end
		if isCover(hit.Instance) then
			return false
		end
		local advance = (hit.Position - start).Magnitude + 0.05
		start += dir * advance
		remaining -= advance
	end
	return true
end

local function preferredWeapon(list: { string }): string?
	if table.find(list, "Pistol") then
		return "Pistol"
	end
	return list[1]
end

-- Attributes (CONTRACT §3.3) ------------------------------------------------------------------------
local function writeAmmo(player: Player, st: PlayerState, id: string)
	local spec = specOf(id)
	if spec and spec.Mag ~= nil then
		player:SetAttribute("Mag_" .. id, st.Mag[id] or 0)
		player:SetAttribute("Ammo_" .. id, st.Ammo[id] or 0)
	end
end

local function writeAll(player: Player, st: PlayerState)
	for _, id in ipairs(WeaponsConfig.Order) do
		if st.Has[id] then
			writeAmmo(player, st, id)
		else
			player:SetAttribute("Mag_" .. id, nil)
			player:SetAttribute("Ammo_" .. id, nil)
		end
	end
	player:SetAttribute("Weapons", WeaponMath.joinList(st.List))
	player:SetAttribute("Equipped", st.Equipped)
end

local function clearAttributes(player: Player)
	for _, id in ipairs(WeaponsConfig.Order) do
		player:SetAttribute("Mag_" .. id, nil)
		player:SetAttribute("Ammo_" .. id, nil)
	end
	player:SetAttribute("Weapons", nil)
	player:SetAttribute("Equipped", nil)
end

local function fillAmmo(st: PlayerState, id: string)
	local spec = specOf(id)
	if spec and spec.Mag ~= nil then
		local mag, reserve = WeaponMath.fullAmmo(spec.Mag, spec.Reserve)
		st.Mag[id], st.Ammo[id] = mag, reserve
	end
end

local function cancelReload(st: PlayerState)
	st.ReloadToken += 1
	st.ReloadWeapon = nil
end

-- Recompute the weapon list (owned ∪ default ∪ this round's pickups). New weapons get full ammo.
local function rebuild(st: PlayerState)
	st.List = WeaponMath.loadout(WeaponsConfig.Order, WeaponsConfig.Default, st.Owned, st.RoundOnly)
	local has: { [string]: boolean } = {}
	for _, id in ipairs(st.List) do
		has[id] = true
		if not st.Has[id] then
			fillAmmo(st, id)
		end
	end
	for id in pairs(st.Mag) do
		if not has[id] then
			st.Mag[id], st.Ammo[id] = nil, nil
		end
	end
	st.Has = has
	if st.Equipped == nil or not has[st.Equipped] then
		cancelReload(st)
		st.Equipped = preferredWeapon(st.List)
	end
end

local function setEquipped(player: Player, st: PlayerState, id: string)
	if st.Equipped == id then
		return
	end
	cancelReload(st)
	st.Equipped = id
	player:SetAttribute("Equipped", id)
end

local function sendHit(player: Player, killed: boolean, penalty: boolean, extra: { [string]: any }?)
	local data: { [string]: any } = { Kind = "Hit", Killed = killed, Penalty = penalty }
	if extra then
		for k, v in pairs(extra) do
			data[k] = v
		end
	end
	feedbackRemote:FireClient(player, data)
end

-- Damage an enemy for a player and tell the shooter (hit marker). Returns killed.
local function damageEnemy(player: Player?, id: number, amount: number, cause: Types.KillCause, from: Vector3?): (boolean, boolean)
	local Enemy = ctx.Services.Enemy
	if not Enemy:IsAlive(id) then
		return false, false
	end
	local kind = Enemy:GetKind(id)
	Enemy:Damage(id, amount, player, cause, from)
	-- Damage's boolean is not relied on (contract only says "false for dead enemies"); ask IsAlive.
	local killed = not Enemy:IsAlive(id)
	local penalty = killed and isPenaltyKind(kind)
	return killed, penalty
end

-- Fire ---------------------------------------------------------------------------------------------------
local function fireHitscan(player: Player, st: PlayerState, w: string, spec: Spec, payload: { [string]: any }, o: Vector3, d: Vector3, now: number)
	st.Mag[w] = WeaponMath.spend(spec.Mag, st.Mag[w] or 0)
	writeAmmo(player, st, w)

	local dir = d.Unit
	local endPos = o + dir * spec.Range
	local p, id = payload.P, payload.Id
	if Net.isVector(p) then
		local point = p :: Vector3
		local aimOk = WeaponMath.checkAim(vec(o), vec(dir), vec(point), spec.Range)
		if aimOk then
			endPos = point
			if Net.isNumber(id, 1, 2 ^ 31) and id == math.floor(id) then
				local enemyId = id :: number
				local Enemy = ctx.Services.Enemy
				if Enemy:IsAlive(enemyId) then
					local rewound = Enemy:PositionAt(enemyId, WeaponMath.rewindTime(payload.T, now))
					local lagOk =
						WeaponMath.checkLagComp(if rewound then vec(rewound) else nil, vec(point), Enemy:GetRadius(enemyId))
					if lagOk and lineClear(o, point) then
						local killed, penalty = damageEnemy(player, enemyId, spec.Damage, "Bullet", o)
						sendHit(player, killed, penalty)
					end
				end
			end
		end
	end
	effectRemote:FireAllClients("Shot", { From = o, To = endPos, W = w, UserId = player.UserId })
end

local function fireMelee(player: Player, spec: Spec, d: Vector3, now: number)
	local root = characterPart(player, "HumanoidRootPart")
	if not root then
		return
	end
	local Enemy = ctx.Services.Enemy
	local forward = Vector3.new(d.X, 0, d.Z)
	if forward.Magnitude < 0.1 then
		forward = root.CFrame.LookVector
	end
	local candidates: { WeaponMath.MeleeCandidate } = {}
	local positions: { [number]: Vector3 } = {}
	for _, id in ipairs(Enemy:QueryRadius(root.Position, spec.Range + 4)) do
		if Enemy:IsAlive(id) then
			local pos = Enemy:PositionAt(id, now)
			if pos then
				positions[id] = pos
				table.insert(candidates, { Id = id, Pos = vec(pos), Radius = Enemy:GetRadius(id) })
			end
		end
	end
	local target, flatDir = WeaponMath.meleePick(vec(root.Position), vec(forward), candidates, spec.Range, spec.Cone or 30)
	local targetPos = if target then positions[target] else nil
	if target and (targetPos == nil or not lineClear(root.Position, targetPos)) then
		target = nil
	end
	if target and flatDir then
		local kind = Enemy:GetKind(target)
		if isPenaltyKind(kind) then
			-- Non-target: no damage, shove + stun (CONTRACT §1.9 방망이 넉백).
			local stun = if spec.Knockback then spec.Knockback.Stun else 2
			Enemy:Knockback(target, Vector3.new(flatDir[1], 0, flatDir[3]), stun)
			sendHit(player, false, false, { Knockback = true })
		else
			local killed, penalty = damageEnemy(player, target, spec.Damage, "Melee", root.Position)
			sendHit(player, killed, penalty)
		end
	end
	effectRemote:FireAllClients("Melee", { UserId = player.UserId, Target = target })
end

local function onFire(player: Player, payload: any)
	if not Net.throttle(player, "Fire", 0.03) then
		return
	end
	if type(payload) ~= "table" then
		return
	end
	local st = states[player]
	if not st then
		return
	end
	local Flow = ctx.Services.Flow
	local r, w, o, d = payload.R, payload.W, payload.O, payload.D
	if not Net.isNumber(r) or r ~= Flow:RoundId() then
		return
	end
	if not Net.isString(w, 16) or not st.Has[w] then
		return
	end
	local spec = specOf(w)
	if not spec or (spec.Kind ~= "Hitscan" and spec.Kind ~= "Melee") then
		return -- Throw/Projectile arrive in a later wave
	end
	if not Net.isVector(o) or not Net.isVector(d, 2) then
		return
	end
	local origin, dir = o :: Vector3, d :: Vector3
	if Flow:GetLife(player) ~= "Alive" then
		return
	end
	local head = characterPart(player, "Head")
	if not head then
		return
	end
	-- Firing a weapon you own equips it (remotes are ordered, so this only matters if an Equip got throttled).
	setEquipped(player, st, w)
	if st.ReloadWeapon ~= nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	local shotTime = WeaponMath.shotTime(payload.T, now)
	if not WeaponMath.rateOk(st.LastShot[w], shotTime, spec.Rate) then
		return
	end
	if not WeaponMath.hasAmmo(spec.Mag, st.Mag[w] or 0) then
		return
	end
	if not WeaponMath.checkShot(vec(head.Position), vec(origin), vec(dir)) then
		return
	end
	if not lineClear(head.Position, origin) then
		return
	end
	st.LastShot[w] = shotTime
	if spec.Kind == "Melee" then
		fireMelee(player, spec, dir, now)
	else
		fireHitscan(player, st, w, spec, payload, origin, dir, now)
	end
end

local function onReload(player: Player, weaponId: any)
	if not Net.throttle(player, "Reload", 0.1) then
		return
	end
	local st = states[player]
	if not st or not Net.isString(weaponId, 16) or not st.Has[weaponId] then
		return
	end
	local spec = specOf(weaponId)
	if not spec or spec.Mag == nil then
		return
	end
	if ctx.Services.Flow:GetLife(player) ~= "Alive" then
		return
	end
	setEquipped(player, st, weaponId)
	if st.ReloadWeapon ~= nil then
		return
	end
	if not WeaponMath.canReload(spec.Mag, st.Mag[weaponId] or 0, st.Ammo[weaponId] or 0) then
		return
	end
	st.ReloadToken += 1
	local token = st.ReloadToken
	st.ReloadWeapon = weaponId
	task.delay((spec.Reload or 1) * RELOAD_SERVER_FACTOR, function()
		if states[player] ~= st or st.ReloadToken ~= token then
			return
		end
		st.ReloadWeapon = nil
		if not st.Has[weaponId] then
			return
		end
		st.Mag[weaponId], st.Ammo[weaponId] = WeaponMath.reload(spec.Mag, st.Mag[weaponId] or 0, st.Ammo[weaponId] or 0)
		writeAmmo(player, st, weaponId)
	end)
end

local function onEquip(player: Player, weaponId: any)
	if not Net.throttle(player, "Equip", 0.03) then
		return
	end
	local st = states[player]
	if not st or not Net.isString(weaponId, 16) or not st.Has[weaponId] then
		return
	end
	setEquipped(player, st, weaponId)
end

-- Pickups ------------------------------------------------------------------------------------------------
local function claim(player: Player, st: PlayerState, pk: Pickup)
	local mine = claimed[player]
	if not mine then
		mine = {}
		claimed[player] = mine
	end
	mine[pk.MarkerId] = true
	local spec = specOf(pk.Weapon)
	if not spec then
		return
	end
	if not st.Has[pk.Weapon] then
		st.RoundOnly[pk.Weapon] = true
		rebuild(st)
	end
	fillAmmo(st, pk.Weapon)
	writeAll(player, st)
	feedbackRemote:FireClient(player, {
		Kind = "PickedUp",
		Weapon = pk.Weapon,
		Marker = pk.MarkerId,
		Text = ("%s 획득!"):format(spec.Name),
	})
	effectRemote:FireAllClients("Pickup", { UserId = player.UserId, Marker = pk.MarkerId })
end

local function pickupStep()
	if #pickups == 0 then
		return
	end
	local Flow = ctx.Services.Flow
	for _, player in ipairs(Flow:GetParty()) do
		local st = states[player]
		local root = characterPart(player, "HumanoidRootPart")
		if st and root and Flow:GetLife(player) == "Alive" then
			local mine = claimed[player]
			for _, pk in ipairs(pickups) do
				if not (mine and mine[pk.MarkerId]) and WeaponMath.inReach(vec(root.Position), vec(pk.Pos), PICKUP_REACH, 6) then
					claim(player, st, pk)
					mine = claimed[player]
				end
			end
		end
	end
end

local function groundBelow(pos: Vector3): Vector3
	local hit = workspace:Raycast(pos + Vector3.new(0, 1, 0), Vector3.new(0, -12, 0), geometryParams())
	if hit then
		return hit.Position
	end
	return pos - Vector3.new(0, 0.5, 0)
end

-- Contract API --------------------------------------------------------------------------------------------
function WeaponService.Init(self: Types.WeaponService, c: Types.Context)
	ctx = c
	effectRemote = Net.event(c.Remotes, "Effect")
	feedbackRemote = Net.event(c.Remotes, "Feedback")
end

function WeaponService.Start(self: Types.WeaponService)
	Net.event(ctx.Remotes, "Fire").OnServerEvent:Connect(onFire)
	Net.event(ctx.Remotes, "Reload").OnServerEvent:Connect(onReload)
	Net.event(ctx.Remotes, "Equip").OnServerEvent:Connect(onEquip)

	Players.PlayerRemoving:Connect(function(player)
		local st = states[player]
		if st then
			cancelReload(st)
		end
		states[player] = nil
		claimed[player] = nil
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < PICKUP_INTERVAL then
			return
		end
		acc = 0
		local ok, err = pcall(function(): any
			pickupStep()
			return nil
		end)
		if not ok then
			warn("[WeaponService] pickup step failed: " .. tostring(err))
		end
	end)
end

function WeaponService.PrepareStage(self: Types.WeaponService, handle: Types.StageHandle)
	WeaponService.ClearStage(self)
	local folder = Instance.new("Folder")
	folder.Name = "WeaponPickups"
	local markers = handle.Markers["WeaponPickup"] or {}
	for index, marker in ipairs(markers) do
		local weaponId = marker:GetAttribute("Weapon")
		local rawId = marker:GetAttribute("MarkerId")
		local spec = specOf(weaponId)
		if spec and type(weaponId) == "string" then
			local markerId = if rawId ~= nil and tostring(rawId) ~= "" then tostring(rawId) else ("WeaponPickup" .. index)
			local ground = groundBelow(marker.Position)
			local model = WeaponModels.display(weaponId, spec.Name, CFrame.new(ground))
			model.Name = "Pickup_" .. markerId
			model:SetAttribute("MarkerId", markerId)
			model:SetAttribute("Weapon", weaponId)
			CollectionService:AddTag(model, PICKUP_TAG)
			model.Parent = folder
			table.insert(pickups, { MarkerId = markerId, Weapon = weaponId, Pos = ground, Model = model })
		else
			warn(("[WeaponService] WeaponPickup marker %s has unknown Weapon %s"):format(marker:GetFullName(), tostring(weaponId)))
		end
	end
	folder.Parent = handle.Model
	pickupFolder = folder
	table.clear(claimed)
end

function WeaponService.ClearStage(self: Types.WeaponService)
	if pickupFolder then
		pickupFolder:Destroy()
		pickupFolder = nil
	end
	table.clear(pickups)
	table.clear(claimed)
	for player, st in pairs(states) do
		if next(st.RoundOnly) ~= nil then
			st.RoundOnly = {}
			rebuild(st)
			if player.Parent then
				writeAll(player, st)
			end
		end
	end
end

function WeaponService.GiveLoadout(self: Types.WeaponService, player: Player)
	local owned: { [string]: boolean } = {}
	local profile = ctx.Services.Data:Get(player)
	if profile and type(profile.Owned) == "table" then
		for id, has in pairs(profile.Owned) do
			if has == true and specOf(id) then
				owned[id] = true
			end
		end
	end
	local old = states[player]
	if old then
		cancelReload(old)
	end
	local st: PlayerState = {
		Owned = owned,
		RoundOnly = if old then old.RoundOnly else {},
		List = {},
		Has = {},
		Mag = {},
		Ammo = {},
		Equipped = nil,
		LastShot = {},
		ReloadToken = 0,
		ReloadWeapon = nil,
	}
	rebuild(st) -- fills ammo for every weapon (Has starts empty)
	st.Equipped = preferredWeapon(st.List)
	states[player] = st
	writeAll(player, st)
end

function WeaponService.StripLoadout(self: Types.WeaponService, player: Player)
	local st = states[player]
	if st then
		cancelReload(st)
	end
	states[player] = nil
	clearAttributes(player)
end

function WeaponService.AddAmmoPercent(self: Types.WeaponService, player: Player, percent: number)
	local st = states[player]
	if not st or not Net.isNumber(percent, 0, 1000) then
		return
	end
	for _, id in ipairs(st.List) do
		local spec = specOf(id)
		if spec and spec.Mag ~= nil then
			st.Ammo[id] = WeaponMath.addPercent(spec.Mag, spec.Reserve, st.Mag[id] or 0, st.Ammo[id] or 0, percent)
			writeAmmo(player, st, id)
		end
	end
end

function WeaponService.Explode(
	self: Types.WeaponService,
	center: Vector3,
	radius: number,
	enemyDamage: number,
	playerDamage: number,
	byPlayer: Player?
)
	if not Net.isVector(center) or not Net.isNumber(radius, 0, 500) then
		return
	end
	local Enemy, Flow = ctx.Services.Enemy, ctx.Services.Flow
	if Net.isNumber(enemyDamage, 0) and enemyDamage > 0 then
		local anyHit, anyKilled, anyPenalty = false, false, false
		for _, id in ipairs(Enemy:QueryRadius(center, radius)) do
			if Enemy:IsAlive(id) then
				local killed, penalty = damageEnemy(byPlayer, id, enemyDamage, "Explosion", center)
				anyHit = true
				anyKilled = anyKilled or killed
				anyPenalty = anyPenalty or penalty
			end
		end
		if byPlayer and anyHit and byPlayer.Parent then
			sendHit(byPlayer, anyKilled, anyPenalty)
		end
	end
	-- Player explosions never hurt players (CONTRACT §1.5); monster bombs do.
	if byPlayer == nil and Net.isNumber(playerDamage, 0) and playerDamage > 0 then
		for _, player in ipairs(Flow:GetParty()) do
			local root = characterPart(player, "HumanoidRootPart")
			if root and Flow:GetLife(player) == "Alive" and (root.Position - center).Magnitude <= radius then
				Flow:DamagePlayer(player, playerDamage, "Explosion", center)
			end
		end
	end
	effectRemote:FireAllClients("Explosion", { Pos = center, Radius = radius })
end

return WeaponService
