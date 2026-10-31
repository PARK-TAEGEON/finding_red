--!strict
-- Collapse-in-place deaths and lingering bodies (CONTRACT §1.12.2). Owner: B. Server only.
--
-- On death the rig becomes a limp ragdoll: the Humanoid is removed (so it can no longer force limb
-- collision off or stand the body up), every Motor6D except the RootJoint is swapped for a
-- BallSocketConstraint with loose R6 limits, and the body gets a small shove (1–3 studs) away from
-- the attacker plus a tip-over spin, so the knees buckle and it falls forward or backward.
-- Once the body is calm (or after a few seconds) every part is anchored with collision off: it
-- lies on the floor until the stage is cleared, cannot sink through the floor and cannot jitter.
--
-- Collision groups (registered once here):
--   FR_Enemy  live enemies           FR_Corpse  bodies (collide with the world only)
--   FR_Player player characters      Corpses ignore players, live enemies and other corpses.
-- All corpse parts are CanQuery = false (bullets, line of sight and radar raycasts pass through)
-- and CanTouch = false. Network ownership of every limb assembly stays with the server.
-- Bodies are capped (EnemyLogic.CORPSE.Cap); the oldest gets the model attribute `Fade` = true
-- (EnemyFX fades it locally) and is destroyed a second later.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyLogic = require(ReplicatedStorage.Shared.EnemyLogic)

local Corpse = {}

Corpse.ENEMY_GROUP = "FR_Enemy"
Corpse.CORPSE_GROUP = "FR_Corpse"
Corpse.PLAYER_GROUP = "FR_Player"

local C = EnemyLogic.CORPSE
local CHECK_INTERVAL = 0.1
local FADE_SECONDS = 1
local VOID_DEPTH = 60 -- a body this far below its death spot fell out of the map: remove it
-- Toppling over moves the legs ~1 stud on its own; travel beyond MaxSlide + this is shove/slide.
local TOPPLE_ALLOWANCE = 1.5

local groupsReady = false

type Body = {
	Model: Model,
	Parts: { BasePart },
	Core: BasePart, -- torso (or root): fall / upright checks
	Feet: { BasePart }, -- legs (or core): horizontal travel checks
	Start: Vector3, -- core position at death
	FeetStart: Vector3,
	Born: number,
	NextCheck: number,
	Calm: number,
	Frozen: boolean,
	Nudged: boolean,
	TipAxis: Vector3,
}

local bodies: { Body } = {} -- oldest first, frozen or settling
local settling: { Body } = {}
local stepConn: RBXScriptConnection? = nil

-- Collision groups ---------------------------------------------------------------------------------
local function setPartGroup(inst: Instance, group: string)
	if inst:IsA("BasePart") then
		inst.CollisionGroup = group
	end
end

local function tagCharacter(character: Model)
	if not groupsReady then
		return
	end
	for _, d in ipairs(character:GetDescendants()) do
		setPartGroup(d, Corpse.PLAYER_GROUP)
	end
	character.DescendantAdded:Connect(function(d)
		setPartGroup(d, Corpse.PLAYER_GROUP)
	end)
end

local function watchPlayer(player: Player)
	if player.Character then
		tagCharacter(player.Character)
	end
	player.CharacterAdded:Connect(tagCharacter)
end

-- Registers the groups and starts tagging player characters. Safe to call more than once.
function Corpse.setup()
	if groupsReady then
		return
	end
	local ok, err = pcall(function()
		for _, name in ipairs({ Corpse.ENEMY_GROUP, Corpse.CORPSE_GROUP, Corpse.PLAYER_GROUP }) do
			if not PhysicsService:IsCollisionGroupRegistered(name) then
				PhysicsService:RegisterCollisionGroup(name)
			end
		end
		-- Corpses touch the world ("Default") only.
		PhysicsService:CollisionGroupSetCollidable(Corpse.CORPSE_GROUP, Corpse.CORPSE_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(Corpse.CORPSE_GROUP, Corpse.ENEMY_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(Corpse.CORPSE_GROUP, Corpse.PLAYER_GROUP, false)
	end)
	if not ok then
		warn("[EnemyService] collision groups unavailable, corpses may bump players: " .. tostring(err))
		return
	end
	groupsReady = true
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
end

-- Puts every part of a live enemy model in the enemy group (no-op if groups failed).
function Corpse.tagEnemy(model: Model)
	if not groupsReady then
		return
	end
	for _, d in ipairs(model:GetDescendants()) do
		setPartGroup(d, Corpse.ENEMY_GROUP)
	end
end

-- Ragdoll joints --------------------------------------------------------------------------------------
-- R6 joints in rest-pose part space. Both attachments share one orientation (R6 parts are axis-
-- aligned with the torso at rest); the attachment X axis is the cone axis of the joint limit.
-- Pivots lie on the Motor6D rotation axes, so a mid-animation pose does not snap.
type JointSpec = { P0: Vector3, P1: Vector3, Down: boolean, Upper: number, Twist: number }
local R6_JOINTS: { [string]: JointSpec } = {
	Neck = { P0 = Vector3.new(0, 1, 0), P1 = Vector3.new(0, -0.5, 0), Down = false, Upper = 35, Twist = 40 },
	["Right Shoulder"] = { P0 = Vector3.new(1.5, 0.5, 0), P1 = Vector3.new(0, 0.5, 0), Down = true, Upper = 110, Twist = 70 },
	["Left Shoulder"] = { P0 = Vector3.new(-1.5, 0.5, 0), P1 = Vector3.new(0, 0.5, 0), Down = true, Upper = 110, Twist = 70 },
	["Right Hip"] = { P0 = Vector3.new(0.5, -1, 0), P1 = Vector3.new(0, 1, 0), Down = true, Upper = 85, Twist = 30 },
	["Left Hip"] = { P0 = Vector3.new(-0.5, -1, 0), P1 = Vector3.new(0, 1, 0), Down = true, Upper = 85, Twist = 30 },
}

local function frame(pos: Vector3, down: boolean): CFrame
	if down then
		return CFrame.fromMatrix(pos, Vector3.new(0, -1, 0), Vector3.new(0, 0, -1))
	end
	return CFrame.fromMatrix(pos, Vector3.new(0, 1, 0), Vector3.new(0, 0, 1))
end

local function socket(name: string, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame, upper: number, twist: number)
	local a0 = Instance.new("Attachment")
	a0.Name = "Rag_" .. name .. "_0"
	a0.CFrame = c0
	a0.Parent = p0
	local a1 = Instance.new("Attachment")
	a1.Name = "Rag_" .. name .. "_1"
	a1.CFrame = c1
	a1.Parent = p1
	local s = Instance.new("BallSocketConstraint")
	s.Name = "Rag_" .. name
	s.Attachment0 = a0
	s.Attachment1 = a1
	s.LimitsEnabled = true
	s.UpperAngle = upper
	s.TwistLimitsEnabled = true
	s.TwistLowerAngle = -twist
	s.TwistUpperAngle = twist
	s.Restitution = 0
	s.Parent = p0
end

-- Swaps every Motor6D (except the root <-> torso joint) for a ball socket.
local function ragdollJoints(model: Model, root: BasePart?)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			local m = d :: Motor6D
			local p0, p1 = m.Part0, m.Part1
			if p0 and p1 and p0 ~= root and p1 ~= root and m.Enabled then
				local spec = R6_JOINTS[m.Name]
				local isStd = spec ~= nil and p0.Name == "Torso"
				if isStd then
					local j = spec :: JointSpec
					socket(m.Name, p0, p1, frame(j.P0, j.Down), frame(j.P1, j.Down), j.Upper, j.Twist)
				else
					-- unknown rig joint: hinge point and frames straight from the motor
					socket(m.Name, p0, p1, m.C0, m.C1, 70, 45)
				end
				m.Enabled = false
			end
		end
	end
end

local function stopAnimations(hum: Humanoid)
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		pcall(function()
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end)
	end
end

local function serverOwn(part: BasePart)
	if part.Anchored or not part:IsDescendantOf(workspace) then
		return
	end
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
end

-- Freezing / eviction ---------------------------------------------------------------------------------------
local function removeFrom(list: { Body }, b: Body)
	local i = table.find(list, b)
	if i then
		table.remove(list, i)
	end
end

local function freeze(b: Body)
	if b.Frozen then
		return
	end
	b.Frozen = true
	removeFrom(settling, b)
	for _, p in ipairs(b.Parts) do
		if p.Parent then
			p.AssemblyLinearVelocity = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
			p.Anchored = true
			p.CanCollide = false -- anchored now: nothing to support, nothing to bump
		end
	end
end

local function discard(b: Body, fade: boolean)
	removeFrom(settling, b)
	removeFrom(bodies, b)
	b.Frozen = true
	local model = b.Model
	if fade and model.Parent then
		model:SetAttribute("Fade", true)
		task.delay(FADE_SECONDS, function()
			model:Destroy()
		end)
	else
		model:Destroy()
	end
end

local function evict()
	local n = EnemyLogic.corpsesToEvict(#bodies, C.Cap)
	for _ = 1, n do
		local oldest = bodies[1]
		if oldest then
			discard(oldest, true)
		end
	end
end

local function centre(list: { BasePart }): Vector3
	local sum, n = Vector3.zero, 0
	for _, p in ipairs(list) do
		sum += p.Position
		n += 1
	end
	return if n > 0 then sum / n else Vector3.zero
end

-- Settling loop (10 Hz per body) ---------------------------------------------------------------------------
local function check(b: Body, now: number)
	if not b.Model.Parent or not b.Core.Parent then
		discard(b, false)
		return
	end
	local core = b.Core
	local pos = core.Position
	if pos.Y < b.Start.Y - VOID_DEPTH then
		discard(b, false)
		return
	end
	-- Keep the shove small: past MaxSlide, horizontal motion is removed (falling is kept).
	local feet = centre(b.Feet)
	local off = Vector3.new(feet.X - b.FeetStart.X, 0, feet.Z - b.FeetStart.Z)
	if off.Magnitude > C.MaxSlide + TOPPLE_ALLOWANCE then
		for _, p in ipairs(b.Parts) do
			if p.Parent and not p.Anchored then
				local v = p.AssemblyLinearVelocity
				if Vector3.new(v.X, 0, v.Z):Dot(off) > 0 then
					p.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
				end
			end
		end
	end
	local fastest = 0
	for _, p in ipairs(b.Parts) do
		if p.Parent then
			fastest = math.max(fastest, p.AssemblyLinearVelocity.Magnitude)
		end
	end
	b.Calm = if fastest < C.CalmSpeed then b.Calm + 1 else 0
	local elapsed = now - b.Born
	-- Balanced upright by bad luck (e.g. propped on a crate): tip it once more.
	if not b.Nudged and elapsed >= C.MinSettle and core.CFrame.UpVector.Y > 0.8 then
		b.Nudged = true
		b.Calm = 0
		core.AssemblyAngularVelocity = b.TipAxis * C.TipSpeed * 1.5
		return
	end
	local falling = core.AssemblyLinearVelocity.Y < -3
	if EnemyLogic.corpseShouldFreeze(elapsed, b.Calm, falling) then
		freeze(b)
	end
end

local function ensureLoop()
	if stepConn then
		return
	end
	stepConn = RunService.Heartbeat:Connect(function()
		if #settling == 0 then
			return
		end
		local now = os.clock()
		for i = #settling, 1, -1 do
			local b = settling[i]
			if b and now >= b.NextCheck then
				b.NextCheck = now + CHECK_INTERVAL
				local ok, err = pcall(function()
					check(b, now)
				end)
				if not ok then
					warn("[EnemyService] corpse settle failed: " .. tostring(err))
					freeze(b)
				end
			end
		end
	end)
end

-- Public -----------------------------------------------------------------------------------------------------
-- Turns a dying enemy model into a limp body that collapses where it stands.
-- `from` = attacker / shot origin (push direction), nil = random.
function Corpse.collapse(model: Model, from: Vector3?)
	ensureLoop()
	local root = model.PrimaryPart
	local torsoInst = model:FindFirstChild("Torso")
	local torso: BasePart? = if torsoInst and torsoInst:IsA("BasePart") then torsoInst else nil
	local core = torso or root
	if not core then
		model:Destroy()
		return
	end

	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		stopAnimations(hum)
		hum.PlatformStand = true
	end

	-- Every part: corpse group, invisible to raycasts and touch. Body parts collide with the world
	-- so the ragdoll lands on the floor; cosmetic (massless) parts and the root never collide.
	local parts: { BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local p = d :: BasePart
			p.CanQuery = false
			p.CanTouch = false
			if groupsReady then
				p.CollisionGroup = Corpse.CORPSE_GROUP
			end
			p.CanCollide = p ~= root and not p.Massless
			p.Anchored = false
			table.insert(parts, p)
		end
	end
	if root then
		root.CanCollide = false
	end

	ragdollJoints(model, root)
	if hum then
		hum:Destroy() -- a Humanoid would keep forcing R6 limb collision off and try to stand up
	end

	-- Shove + tip-over. Torso/head move most, legs barely: the feet act as the pivot, the knees
	-- (hips) buckle and the body drops forward or backward.
	local p = core.Position
	local fromVec: EnemyLogic.Vec3? = if from then { from.X, from.Y, from.Z } else nil
	local push, sign = EnemyLogic.deathPush({ p.X, p.Y, p.Z }, fromVec, math.random)
	local dir = Vector3.new(push[1], 0, push[3])
	local fall = dir * sign
	local tipAxis = Vector3.yAxis:Cross(fall) -- spin that moves the top of the body along `fall`
	local shove = dir * C.PushSpeed
	for _, part in ipairs(parts) do
		serverOwn(part)
	end
	for _, part in ipairs(parts) do
		-- Massless cosmetics are welded into another part's assembly: setting their velocity
		-- would overwrite that part's (assembly velocity is shared).
		if part.Massless and part ~= core then
			continue
		end
		local v = shove * 0.4
		if part == core or part == root then
			v = shove + Vector3.new(0, -2.5, 0)
		elseif part.Name == "Head" then
			v = shove * 1.2 + fall * 1.5
		elseif part.Name == "Left Leg" or part.Name == "Right Leg" then
			v = shove * 0.15
		end
		part.AssemblyLinearVelocity = v
	end
	core.AssemblyAngularVelocity = tipAxis * C.TipSpeed

	local feet: { BasePart } = {}
	for _, name in ipairs({ "Left Leg", "Right Leg" }) do
		local leg = model:FindFirstChild(name)
		if leg and leg:IsA("BasePart") then
			table.insert(feet, leg)
		end
	end
	if #feet == 0 then
		table.insert(feet, core)
	end

	local now = os.clock()
	local b: Body = {
		Model = model,
		Parts = parts,
		Core = core,
		Feet = feet,
		Start = p,
		FeetStart = centre(feet),
		Born = now,
		NextCheck = now + CHECK_INTERVAL,
		Calm = 0,
		Frozen = false,
		Nudged = false,
		TipAxis = tipAxis,
	}
	table.insert(bodies, b)
	table.insert(settling, b)
	-- Ownership is per assembly; re-assert once the new joint layout has been processed.
	task.defer(function()
		if not b.Frozen then
			for _, part in ipairs(parts) do
				serverOwn(part)
			end
		end
	end)
	evict()
end

-- Forget every body (the models are destroyed by the caller's folder clear).
function Corpse.clear()
	for _, b in ipairs(bodies) do
		b.Frozen = true
		if b.Model.Parent then
			b.Model:Destroy()
		end
	end
	table.clear(bodies)
	table.clear(settling)
end

function Corpse.count(): number
	return #bodies
end

return Corpse
