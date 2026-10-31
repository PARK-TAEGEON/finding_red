--!strict
-- Server enemy system (CONTRACT §1.4, §1.8, §2.6, §3.4). Owner: B.
-- Spawns R6 enemies from EnemySpawn markers, runs their brains (pure EnemyLogic) at 10 Hz,
-- executes the decisions with Humanoid:MoveTo (Pathfinding only when blocked), owns enemy HP,
-- kill reporting, knockback/stun and the position history used for lag compensation.
-- v0.5: Reds chase and hit like Whites (Config Behavior = "Chase"); deaths collapse in place into a
-- limp ragdoll that stays on the floor until ClearAll (Enemy/Corpse.luau).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Rules = require(Shared.Rules)
local EnemyLogic = require(Shared.EnemyLogic)
local EnemiesConfig = require(Shared.Config.Enemies)
local EnemyModels = require(Shared.Models.EnemyModels)
local Corpse = require(script.Parent.Enemy.Corpse)

type Vec3 = EnemyLogic.Vec3
type EnemyConfig = EnemiesConfig.EnemyConfig

-- Tuning -------------------------------------------------------------------------------------
local THINK_INTERVAL = 0.1 -- brain tick per enemy (10 Hz)
local HISTORY_KEEP = 0.6 -- seconds of position history (sampled at 10 Hz)
local LOS_CACHE_SECONDS = 0.3
local LOS_RAYS_PER_FRAME = 40
local PATHS_PER_SECOND = 8 -- server-wide PathfindingService budget
local PATH_LIFETIME = 5
local STUCK_WINDOW = 0.8 -- seconds between progress checks
local STUCK_MOVE = 0.8 -- studs of progress expected per window
local FALL_DEPTH = 80 -- below home ground = fell out of the world
local ROOT_HEIGHT = 3 -- R6 root centre above the feet
local DEFAULT_ZONE = 12
local KNOCKBACK = { Speed = 45, Lift = 20, MaxAir = 1.2 }
local SUPPORTED: { [string]: boolean } = { Red = true, White = true }

type Target = {
	Id: number,
	Player: Player,
	Character: Model,
	Root: BasePart,
	Head: BasePart?,
	Info: EnemyLogic.PlayerInfo,
}

type Enemy = {
	Id: number,
	Kind: string,
	Cfg: EnemyConfig,
	Model: Model,
	Root: BasePart,
	Hum: Humanoid,
	Head: BasePart?,
	AlertGui: BillboardGui?,
	HPFill: Frame?,
	HPGui: BillboardGui?,
	Brain: EnemyLogic.Brain,
	HP: number,
	MaxHP: number,
	Dead: boolean,
	Removed: boolean,
	HomeGround: number,
	NextThink: number,
	HistT: { number },
	HistP: { Vector3 },
	-- movement
	Goal: Vector3?,
	Moving: boolean,
	MoveGoal: Vector3?,
	MoveIssuedAt: number,
	ProgressAt: number,
	ProgressPos: Vector3,
	StuckLevel: number,
	StuckFlag: boolean,
	Path: { PathWaypoint }?,
	PathIndex: number,
	PathGoal: Vector3?,
	PathExpires: number,
	PathBusy: boolean,
	PathObj: Path?,
	Speed: number,
	-- senses
	Los: { [number]: { T: number, V: boolean } },
	WalkChecks: number,
	CanSee: (id: number) -> boolean,
	Walkable: (from: Vec3, to: Vec3) -> boolean,
	-- physics / presentation
	Flying: number?,
	FlyDir: Vector3,
	Tracks: EnemyModels.Tracks,
	Anim: string,
	AlertToken: number,
	Attacks: number,
	LastState: string,
	Conns: { RBXScriptConnection },
}

local EnemyService = {}

local ctx: Types.Context
local folder: Folder
local effectRemote: RemoteEvent? = nil

local enemies: { [number]: Enemy } = {}
local kindById: { [number]: string } = {}
local nextId = 0 -- never reset: ids are unique for the server lifetime
local spawnSerial = 0

local frame = 0
local losBudget = LOS_RAYS_PER_FRAME
local pathTokens = PATHS_PER_SECOND

-- Per-frame snapshot of targetable players ------------------------------------------------------
local snapFrame = -1
local targetList: { Target } = {}
local targetInfos: { EnemyLogic.PlayerInfo } = {}
local targetById: { [number]: Target } = {}

local function refreshTargets()
	if snapFrame == frame then
		return
	end
	snapFrame = frame
	targetList, targetInfos, targetById = {}, {}, {}
	xpcall(function()
		local flow = ctx.Services.Flow
		if not flow:IsPlaying() then
			return
		end
		for _, player in ipairs(flow:GetParty()) do
			if player.Parent == Players and flow:GetLife(player) == "Alive" then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if character and root and root:IsA("BasePart") then
					local head = character:FindFirstChild("Head")
					local p = root.Position
					local t: Target = {
						Id = player.UserId,
						Player = player,
						Character = character,
						Root = root,
						Head = if head and head:IsA("BasePart") then head else nil,
						Info = { Id = player.UserId, Pos = { p.X, p.Y, p.Z } },
					}
					table.insert(targetList, t)
					table.insert(targetInfos, t.Info)
					targetById[t.Id] = t
				end
			end
		end
	end, function(err)
		warn("[EnemyService] player snapshot failed: " .. tostring(err))
	end)
end

-- Raycast params: map geometry only ------------------------------------------------------------
local paramsCache: RaycastParams? = nil
local paramsAt = -math.huge

local function geoParams(): RaycastParams
	local now = os.clock()
	if paramsCache and now - paramsAt < 1 then
		return paramsCache :: RaycastParams
	end
	local base: RaycastParams? = nil
	local ok, res = pcall(function()
		return ctx.Services.Stage:GeometryParams()
	end)
	if ok then
		base = res
	end
	local params: RaycastParams
	if base and base.FilterType == Enum.RaycastFilterType.Include then
		params = base
	else
		-- Exclude-style (or missing) params: make sure enemies and characters never block.
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local list: { Instance } = {}
		if base then
			for _, inst in ipairs(base.FilterDescendantsInstances) do
				table.insert(list, inst)
			end
			params.IgnoreWater = base.IgnoreWater
			params.RespectCanCollide = base.RespectCanCollide
			params.CollisionGroup = base.CollisionGroup
		end
		table.insert(list, folder)
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				table.insert(list, player.Character)
			end
		end
		params.FilterDescendantsInstances = list
	end
	paramsCache = params
	paramsAt = now
	return params
end

local function invalidateParams()
	paramsCache = nil
end

local function groundBelow(origin: Vector3, depth: number): number?
	local hit = workspace:Raycast(origin, Vector3.new(0, -depth, 0), geoParams())
	return if hit then hit.Position.Y else nil
end

-- Helpers ------------------------------------------------------------------------------------------
local function toV3(v: Vec3): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

local function toVec(v: Vector3): Vec3
	return { v.X, v.Y, v.Z }
end

local function flat(v: Vector3): number
	return math.sqrt(v.X * v.X + v.Z * v.Z)
end

local function finiteVector(v: any): boolean
	return Net.isVector(v, 1e6)
end

local function fireEffect(kind: string, data: { [string]: any })
	local remote = effectRemote
	if remote then
		remote:FireAllClients(kind, data)
	end
end

local function setState(e: Enemy, state: string)
	if e.LastState ~= state then
		e.LastState = state
		e.Model:SetAttribute("State", state)
	end
end

local function setHP(e: Enemy, hp: number)
	e.HP = hp
	e.Model:SetAttribute("HP", hp)
	local fill = e.HPFill
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(hp / math.max(1, e.MaxHP), 0, 1), 1)
	end
end

-- Animation ------------------------------------------------------------------------------------
local function playAnim(e: Enemy, want: string, speed: number?)
	local walk, idle = e.Tracks.Walk, e.Tracks.Idle
	if e.Anim ~= want then
		e.Anim = want
		pcall(function()
			if want == "Walk" then
				if idle then
					idle:Stop(0.2)
				end
				if walk then
					walk:Play(0.15)
				end
			elseif want == "Idle" then
				if walk then
					walk:Stop(0.2)
				end
				if idle then
					idle:Play(0.2)
				end
			else
				if walk then
					walk:Stop(0.1)
				end
				if idle then
					idle:Stop(0.1)
				end
			end
		end)
	end
	if want == "Walk" and walk and speed then
		pcall(function()
			walk:AdjustSpeed(math.max(0.4, speed / EnemyModels.WALK_ANIM_SPEED))
		end)
	end
end

-- Line of sight / walkability (budgeted) -------------------------------------------------------
local function canSee(e: Enemy, t: Target): boolean
	local now = os.clock()
	local cached = e.Los[t.Id]
	if cached and now - cached.T < LOS_CACHE_SECONDS then
		return cached.V
	end
	if losBudget <= 0 then
		return if cached then cached.V else false
	end
	losBudget -= 1
	local head = e.Head
	local from = if head then head.Position else e.Root.Position + Vector3.new(0, 1.5, 0)
	local targetHead = t.Head
	local to = if targetHead then targetHead.Position else t.Root.Position
	local hit = workspace:Raycast(from, to - from, geoParams())
	local visible = hit == nil or hit.Instance:IsDescendantOf(t.Character)
	e.Los[t.Id] = { T = now, V = visible }
	return visible
end

local function walkable(e: Enemy, from: Vec3, to: Vec3): boolean
	e.WalkChecks += 1
	if e.WalkChecks > 12 then
		return true -- out of probes this tick; stuck detection covers mistakes
	end
	local rootY = e.Root.Position.Y
	local feetY = rootY - ROOT_HEIGHT
	if math.abs(feetY - e.HomeGround) > 4 then
		return true -- off its home level (knocked down / fell): let pathfinding sort it out
	end
	local params = geoParams()
	local down = workspace:Raycast(Vector3.new(to[1], e.HomeGround + 4, to[3]), Vector3.new(0, -9, 0), params)
	if not down or math.abs(down.Position.Y - e.HomeGround) > 3.5 then
		return false -- no floor at the home level there (platform edge, hole)
	end
	local a = Vector3.new(from[1], feetY + 1.6, from[3])
	local b = Vector3.new(to[1], feetY + 1.6, to[3])
	return workspace:Raycast(a, b - a, params) == nil
end

-- Movement --------------------------------------------------------------------------------------
local function issueMove(e: Enemy, target: Vector3, now: number)
	local last = e.MoveGoal
	if not e.Moving or not last or (last - target).Magnitude > 0.75 or now - e.MoveIssuedAt > 2 then
		e.Hum:MoveTo(target)
		e.MoveGoal = target
		e.MoveIssuedAt = now
		e.Moving = true
	end
end

local function stopMoving(e: Enemy)
	e.Goal = nil
	e.Path = nil
	e.StuckLevel = 0
	if e.Moving then
		e.Moving = false
		e.MoveGoal = nil
		e.Hum:MoveTo(e.Root.Position)
	end
end

local function requestPath(e: Enemy, goal: Vector3)
	if e.PathBusy or pathTokens < 1 then
		return
	end
	pathTokens -= 1
	e.PathBusy = true
	local from = e.Root.Position
	task.spawn(function()
		local path = e.PathObj
		if not path then
			local created = PathfindingService:CreatePath({
				AgentRadius = 2,
				AgentHeight = 5,
				AgentCanJump = true,
				AgentCanClimb = false,
				WaypointSpacing = 4,
			})
			e.PathObj = created
			path = created
		end
		local p = path :: Path
		local ok = pcall(function()
			p:ComputeAsync(from, goal)
		end)
		e.PathBusy = false
		if e.Dead or e.Removed then
			return
		end
		if ok and p.Status == Enum.PathStatus.Success then
			local waypoints = p:GetWaypoints()
			if #waypoints >= 2 then
				e.Path = waypoints
				e.PathIndex = 2
				e.PathGoal = goal
				e.PathExpires = os.clock() + PATH_LIFETIME
			end
		end
	end)
end

local function drive(e: Enemy, goal: Vector3?, now: number)
	if not goal then
		stopMoving(e)
		return
	end
	local pos = e.Root.Position
	local previous = e.Goal
	if not previous or (previous - goal).Magnitude > 6 then
		e.ProgressAt = now
		e.ProgressPos = pos
		e.StuckLevel = 0
	end
	e.Goal = goal

	local path = e.Path
	if path then
		local pathGoal = e.PathGoal
		if not pathGoal or (pathGoal - goal).Magnitude > 6 or now > e.PathExpires then
			e.Path = nil
		else
			local wp = path[e.PathIndex]
			while wp and flat(wp.Position - pos) < 2.5 do
				e.PathIndex += 1
				wp = path[e.PathIndex]
			end
			if wp then
				if wp.Action == Enum.PathWaypointAction.Jump then
					e.Hum.Jump = true
				end
				issueMove(e, wp.Position, now)
			else
				e.Path = nil
			end
		end
	end
	if not e.Path then
		issueMove(e, goal, now)
	end

	if now - e.ProgressAt >= STUCK_WINDOW then
		local moved = flat(pos - e.ProgressPos)
		if moved < STUCK_MOVE and flat(goal - pos) > 3 then
			e.StuckLevel += 1
			if e.StuckLevel == 1 then
				e.Hum.Jump = true -- low obstacle: hop first
			else
				e.StuckFlag = true -- brain re-plans wander/flee goals
				requestPath(e, goal) -- chase/return go around
			end
		else
			e.StuckLevel = 0
		end
		e.ProgressAt = now
		e.ProgressPos = pos
	end
end

local function face(e: Enemy, at: Vector3)
	local pos = e.Root.Position
	local look = Vector3.new(at.X - pos.X, 0, at.Z - pos.Z)
	if look.Magnitude < 0.1 then
		return
	end
	e.Root.CFrame = CFrame.lookAt(pos, pos + look)
end

-- Overhead "!" ---------------------------------------------------------------------------------------
local function showAlert(e: Enemy)
	local gui = e.AlertGui
	if not gui then
		return
	end
	e.AlertToken += 1
	local token = e.AlertToken
	gui.Enabled = true
	task.delay(EnemyLogic.ALERT_SECONDS, function()
		if e.AlertToken == token and gui.Parent then
			gui.Enabled = false
		end
	end)
end

-- Death / removal ---------------------------------------------------------------------------------------
-- Live bookkeeping ends at death; the model is handed to Corpse (or destroyed when quiet).
local function detach(e: Enemy)
	e.Removed = true
	for _, c in ipairs(e.Conns) do
		c:Disconnect()
	end
	table.clear(e.Conns)
	if enemies[e.Id] == e then
		enemies[e.Id] = nil
	end
end

local function remove(e: Enemy)
	if e.Removed then
		return
	end
	detach(e)
	e.Model:Destroy()
end

local function randomFlatDir(): Vector3
	local a = math.random() * 2 * math.pi
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

-- quiet = fell out of the world / vanished: no collapse, no effect, removed at once.
local function die(e: Enemy, byPlayer: Player?, cause: Types.KillCause, from: Vector3?, quiet: boolean)
	if e.Dead then
		return
	end
	e.Dead = true
	EnemyLogic.kill(e.Brain)
	local pos = if e.Root.Parent then e.Root.Position else Vector3.zero
	if e.Model.Parent then
		setHP(e, 0)
		setState(e, "Dead")
		e.Path = nil
		e.Moving = false
		playAnim(e, "None")
		local hp = e.HPGui
		if hp then
			hp.Enabled = false
		end
		local alert = e.AlertGui
		if alert then
			alert.Enabled = false
		end
	end
	if not quiet and e.Root.Parent and e.Model.Parent then
		detach(e)
		local model = e.Model
		local ok, err = pcall(function()
			Corpse.collapse(model, from)
		end)
		if not ok then
			warn("[EnemyService] collapse failed: " .. tostring(err))
			e.Model:Destroy()
		end
		fireEffect("EnemyDeath", { Id = e.Id, Pos = pos, From = from, Kind = e.Kind })
	else
		remove(e)
	end
	-- Last, because StageFlow may end the stage (and call ClearAll) from inside ReportKill.
	local ok, err = pcall(function()
		ctx.Services.Flow:ReportKill(e.Kind, byPlayer, cause)
	end)
	if not ok then
		warn("[EnemyService] ReportKill failed: " .. tostring(err))
	end
end

-- Knockback flight -----------------------------------------------------------------------------------
local function land(e: Enemy, groundY: number?)
	e.Flying = nil
	local root = e.Root
	e.Hum.PlatformStand = false
	root.AssemblyAngularVelocity = Vector3.zero
	local p = root.Position
	local y = if groundY then groundY + ROOT_HEIGHT else p.Y
	local pos = Vector3.new(p.X, y, p.Z)
	local look = -e.FlyDir
	if look.Magnitude < 0.1 then
		look = Vector3.zAxis
	end
	e.Model:PivotTo(CFrame.lookAt(pos, pos + look))
	if groundY then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	pcall(function()
		e.Hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)
	playAnim(e, "Idle")
end

local function updateFlight(e: Enemy, now: number)
	local started = e.Flying
	if not started then
		return
	end
	local elapsed = now - started
	local root = e.Root
	if elapsed > 0.25 and root.AssemblyLinearVelocity.Y <= 1 then
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -(ROOT_HEIGHT + 1.5), 0), geoParams())
		if hit then
			land(e, hit.Position.Y)
			return
		end
	end
	if elapsed > KNOCKBACK.MaxAir then
		land(e, nil) -- still airborne (knocked off a ledge): stand up and fall normally
	end
end

-- Brain tick -------------------------------------------------------------------------------------------
local function record(e: Enemy, serverNow: number, pos: Vector3)
	local times, points = e.HistT, e.HistP
	table.insert(times, serverNow)
	table.insert(points, pos)
	while #times > 2 and times[1] < serverNow - HISTORY_KEEP do
		table.remove(times, 1)
		table.remove(points, 1)
	end
end

local function melee(e: Enemy, userId: number)
	local t = targetById[userId]
	local m = e.Cfg.Melee
	if not t or not m then
		return
	end
	local rootPos = e.Root.Position
	if (t.Root.Position - rootPos).Magnitude > m.Range + 1.5 then
		return
	end
	e.Attacks += 1
	e.Model:SetAttribute("Attack", e.Attacks)
	local ok, err = pcall(function()
		ctx.Services.Flow:DamagePlayer(t.Player, m.Damage, e.Kind, rootPos)
	end)
	if not ok then
		warn("[EnemyService] DamagePlayer failed: " .. tostring(err))
	end
end

local function think(e: Enemy, now: number, serverNow: number)
	local root = e.Root
	if not root.Parent or not e.Model.Parent then
		die(e, nil, "Other", nil, true)
		return
	end
	local pos = root.Position
	record(e, serverNow, pos)
	if pos.Y < e.HomeGround - FALL_DEPTH then
		die(e, nil, "Other", nil, true)
		return
	end
	if e.Flying then
		updateFlight(e, now)
		if e.Flying then
			return
		end
	end

	refreshTargets()
	e.WalkChecks = 0
	local stuck = e.StuckFlag
	e.StuckFlag = false
	local action = EnemyLogic.step(e.Brain, e.Cfg, {
		Now = now,
		Pos = toVec(pos),
		Players = targetInfos,
		CanSee = e.CanSee,
		Walkable = e.Walkable,
		Stuck = stuck,
	})

	setState(e, action.State)
	if action.Alert then
		showAlert(e)
	end
	if action.Speed ~= e.Speed then
		e.Speed = action.Speed
		e.Hum.WalkSpeed = action.Speed
	end
	local goal = action.Goal
	drive(e, if goal then toV3(goal) else nil, now)
	local faceAt = action.Face
	if faceAt and not goal then
		face(e, toV3(faceAt))
	end
	local attack = action.Attack
	if attack then
		melee(e, attack)
	end
	-- Humanoid.Running normally drives walk/idle; this catches a missed "stopped" event.
	if e.Anim == "Walk" and not e.Moving and flat(root.AssemblyLinearVelocity) < 0.5 then
		playAnim(e, "Idle")
	end
end

-- Spawning ------------------------------------------------------------------------------------------------
local function numberAttr(inst: Instance, name: string, default: number): number
	local v = inst:GetAttribute(name)
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return default
end

local function spawnEnemy(marker: BasePart, kind: string): Enemy?
	local cfg = EnemiesConfig[kind]
	if not cfg then
		return nil
	end
	local zone = math.clamp(numberAttr(marker, "Zone", DEFAULT_ZONE), 0, 500)
	local mpos = marker.Position
	local params = geoParams()
	local homeGround = groundBelow(mpos + Vector3.new(0, 1, 0), 8) or (mpos.Y - 0.5)

	-- random point in the zone, on the home level, reachable in a straight line from home
	local spawnPos = Vector3.new(mpos.X, homeGround, mpos.Z)
	for _ = 1, 10 do
		local r = zone * 0.85 * math.sqrt(math.random())
		local a = math.random() * 2 * math.pi
		local x, z = mpos.X + math.cos(a) * r, mpos.Z + math.sin(a) * r
		local g = groundBelow(Vector3.new(x, homeGround + 4, z), 9)
		if g and math.abs(g - homeGround) <= 3.5 then
			local from = Vector3.new(mpos.X, homeGround + 1.6, mpos.Z)
			local to = Vector3.new(x, g + 1.6, z)
			if workspace:Raycast(from, to - from, params) == nil then
				spawnPos = Vector3.new(x, g, z)
				break
			end
		end
	end

	local model = EnemyModels.build(kind)
	local root = model.PrimaryPart
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		model:Destroy()
		warn("[EnemyService] broken rig for " .. kind)
		return nil
	end
	nextId += 1
	local id = nextId
	spawnSerial += 1
	local hasKey = marker:GetAttribute("HasKey") == true
	model:SetAttribute("EnemyId", id)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("HasKey", hasKey)
	local keyColor = marker:GetAttribute("KeyColor")
	if hasKey and type(keyColor) == "string" then
		model:SetAttribute("KeyColor", keyColor)
	end
	model:SetAttribute("State", "Idle")
	model:SetAttribute("HP", cfg.HP)
	model:SetAttribute("MaxHP", cfg.HP)
	model:SetAttribute("Attack", 0)
	model.Name = ("%s_%d"):format(kind, id)
	Corpse.tagEnemy(model) -- live enemies pass through corpses
	model:PivotTo(CFrame.new(spawnPos + Vector3.new(0, ROOT_HEIGHT, 0)) * CFrame.Angles(0, math.random() * 2 * math.pi, 0))
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local head = model:FindFirstChild("Head")
	local headPart: BasePart? = if head and head:IsA("BasePart") then head else nil
	local guiHost: Instance = headPart or root
	local alertGui = guiHost:FindFirstChild("Alert")
	local hpGui = guiHost:FindFirstChild("HPBar")
	local fill = hpGui and hpGui:FindFirstChild("Fill", true)

	local now = os.clock()
	local home = { mpos.X, homeGround + ROOT_HEIGHT, mpos.Z } -- zone centre = the marker
	local e: Enemy
	e = {
		Id = id,
		Kind = kind,
		Cfg = cfg,
		Model = model,
		Root = root,
		Hum = hum,
		Head = headPart,
		AlertGui = if alertGui and alertGui:IsA("BillboardGui") then alertGui else nil,
		HPFill = if fill and fill:IsA("Frame") then fill else nil,
		HPGui = if hpGui and hpGui:IsA("BillboardGui") then hpGui else nil,
		Brain = EnemyLogic.new(kind, cfg, home, zone, now),
		HP = cfg.HP,
		MaxHP = cfg.HP,
		Dead = false,
		Removed = false,
		HomeGround = homeGround,
		NextThink = now + (spawnSerial % 10) * (THINK_INTERVAL / 10),
		HistT = {},
		HistP = {},
		Goal = nil,
		Moving = false,
		MoveGoal = nil,
		MoveIssuedAt = 0,
		ProgressAt = now,
		ProgressPos = root.Position,
		StuckLevel = 0,
		StuckFlag = false,
		Path = nil,
		PathIndex = 1,
		PathGoal = nil,
		PathExpires = 0,
		PathBusy = false,
		PathObj = nil,
		Speed = cfg.Speed,
		Los = {},
		WalkChecks = 0,
		CanSee = function(_: number): boolean
			return false
		end,
		Walkable = function(_: Vec3, _: Vec3): boolean
			return true
		end,
		Flying = nil,
		FlyDir = Vector3.zAxis,
		Tracks = {},
		Anim = "",
		AlertToken = 0,
		Attacks = 0,
		LastState = "Idle",
		Conns = {},
	}
	e.CanSee = function(playerId: number): boolean
		local t = targetById[playerId]
		return t ~= nil and canSee(e, t)
	end
	e.Walkable = function(from: Vec3, to: Vec3): boolean
		return walkable(e, from, to)
	end
	hum.WalkSpeed = cfg.Speed

	e.Tracks = EnemyModels.loadAnimations(hum)
	playAnim(e, "Idle")
	table.insert(
		e.Conns,
		hum.Running:Connect(function(speed: number)
			if e.Dead or e.Flying then
				return
			end
			if speed > 0.75 then
				playAnim(e, "Walk", speed)
			else
				playAnim(e, "Idle")
			end
		end)
	)
	table.insert(
		e.Conns,
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) and not e.Removed and not e.Dead then
				-- destroyed by someone else (e.g. FallenPartsDestroyHeight): count it quietly
				task.defer(function()
					if not e.Dead and not e.Removed then
						die(e, nil, "Other", nil, true)
					end
				end)
			end
		end)
	)

	enemies[id] = e
	kindById[id] = kind
	return e
end

local function clearAll()
	for _, e in pairs(enemies) do
		e.Dead = true
		remove(e)
	end
	enemies = {}
	kindById = {}
	Corpse.clear()
	if folder then
		folder:ClearAllChildren()
	end
	invalidateParams()
end

-- Contract API --------------------------------------------------------------------------------------------
function EnemyService.Init(self: Types.EnemyService, c: Types.Context)
	ctx = c
	Corpse.setup()
	local existing = workspace:FindFirstChild("Enemies")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		local f = Instance.new("Folder")
		f.Name = "Enemies"
		f.Parent = workspace
		folder = f
	end
	local ok, remote = pcall(Net.event, c.Remotes, "Effect")
	if ok then
		effectRemote = remote
	else
		warn("[EnemyService] Effect remote missing")
	end
end

function EnemyService.Start(self: Types.EnemyService)
	RunService.Heartbeat:Connect(function(dt: number)
		frame += 1
		losBudget = LOS_RAYS_PER_FRAME
		pathTokens = math.min(PATHS_PER_SECOND, pathTokens + dt * PATHS_PER_SECOND)
		if next(enemies) == nil then
			return
		end
		local now = os.clock()
		local serverNow = workspace:GetServerTimeNow()
		for _, e in pairs(enemies) do
			if not e.Dead and not e.Removed and now >= e.NextThink then
				e.NextThink += THINK_INTERVAL
				if e.NextThink < now then
					e.NextThink = now + THINK_INTERVAL
				end
				xpcall(think, function(err)
					warn(("[EnemyService] brain %d failed: %s"):format(e.Id, tostring(err)))
				end, e, now, serverNow)
			end
		end
	end)
end

function EnemyService.SpawnStage(self: Types.EnemyService, handle: Types.StageHandle, redCount: number)
	if next(enemies) ~= nil then
		clearAll()
	end
	invalidateParams()
	local markers: { BasePart } = handle.Markers["EnemySpawn"] or {}
	local reds: { BasePart } = {}
	local others: { BasePart } = {}
	for _, m in ipairs(markers) do
		if m:IsA("BasePart") then
			local kind = m:GetAttribute("Kind")
			if kind == "Red" then
				table.insert(reds, m)
			elseif type(kind) == "string" then
				table.insert(others, m)
			else
				warn(("[EnemyService] EnemySpawn %s has no Kind"):format(m:GetFullName()))
			end
		end
	end

	local count = math.max(0, math.floor(if type(redCount) == "number" and redCount == redCount then redCount else 0))
	-- Shuffle so the largest-remainder leftovers land on random markers each round
	-- (otherwise 1 Red over 4 equal markers always picks the same corner). Orchestrator fix.
	for i = #reds, 2, -1 do
		local j = math.random(1, i)
		reds[i], reds[j] = reds[j], reds[i]
	end
	if #reds > 0 then
		local weights = {}
		for i, m in ipairs(reds) do
			weights[i] = math.max(0, numberAttr(m, "Weight", 1))
		end
		local counts = Rules.distribute(count, weights)
		for i, m in ipairs(reds) do
			for _ = 1, counts[i] or 0 do
				spawnEnemy(m, "Red")
			end
		end
	elseif count > 0 then
		warn("[EnemyService] no Red EnemySpawn markers; spawning Reds at other markers")
		for i = 1, count do
			local m = others[((i - 1) % math.max(1, #others)) + 1]
			if m then
				spawnEnemy(m, "Red")
			end
		end
	end

	for _, m in ipairs(others) do
		local kind = m:GetAttribute("Kind") :: string
		if SUPPORTED[kind] and EnemiesConfig[kind] then
			local n = math.clamp(math.floor(numberAttr(m, "Count", 1)), 0, 50)
			for _ = 1, n do
				spawnEnemy(m, kind)
			end
		else
			warn(("[EnemyService] enemy kind %s is not implemented yet; skipped"):format(tostring(kind)))
		end
	end
end

function EnemyService.ClearAll(self: Types.EnemyService)
	clearAll()
end

function EnemyService.Damage(
	self: Types.EnemyService,
	id: number,
	amount: number,
	byPlayer: Player?,
	cause: Types.KillCause,
	from: Vector3?
): boolean
	local e = enemies[id]
	if not e or e.Dead or e.Removed then
		return false
	end
	if type(amount) ~= "number" or amount ~= amount or amount < 0 then
		return false
	end
	local origin: Vector3? = if finiteVector(from) then from else nil
	if amount > 0 then
		setHP(e, math.max(0, e.HP - amount))
	end
	if e.HP <= 0 then
		die(e, byPlayer, cause, origin, false)
		return true
	end
	local attacker = if byPlayer then byPlayer.UserId else nil
	if EnemyLogic.damaged(e.Brain, e.Cfg, os.clock(), toVec(e.Root.Position), attacker) then
		e.NextThink = 0 -- react on the next frame
	end
	return false
end

function EnemyService.Knockback(self: Types.EnemyService, id: number, direction: Vector3, stunSeconds: number)
	local e = enemies[id]
	if not e or e.Dead or e.Removed then
		return
	end
	local dir = if finiteVector(direction) then direction else Vector3.zero
	local stun = if type(stunSeconds) == "number" and stunSeconds == stunSeconds then math.clamp(stunSeconds, 0, 10) else 0
	-- A unit vector means "use the default shove"; a longer vector carries the shove speed.
	local speed = if dir.Magnitude > 1.5 then math.min(dir.Magnitude, 120) else KNOCKBACK.Speed
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	flatDir = if flatDir.Magnitude > 1e-3 then flatDir.Unit else randomFlatDir()

	EnemyLogic.stun(e.Brain, os.clock(), stun)
	setState(e, "Stunned")
	stopMoving(e)
	playAnim(e, "None")
	local root = e.Root
	e.Hum.PlatformStand = true
	root.AssemblyLinearVelocity = flatDir * speed + Vector3.new(0, KNOCKBACK.Lift, 0)
	root.AssemblyAngularVelocity = flatDir:Cross(Vector3.yAxis) * -4
	e.Flying = os.clock()
	e.FlyDir = flatDir
	fireEffect("Knockback", { Id = id })
end

function EnemyService.IsAlive(self: Types.EnemyService, id: number): boolean
	local e = enemies[id]
	return e ~= nil and not e.Dead and not e.Removed
end

function EnemyService.GetKind(self: Types.EnemyService, id: number): string?
	return kindById[id]
end

function EnemyService.GetRadius(self: Types.EnemyService, id: number): number
	local kind = kindById[id]
	local cfg = if kind then EnemiesConfig[kind] else nil
	return if cfg then cfg.Radius else 2
end

function EnemyService.PositionAt(self: Types.EnemyService, id: number, serverTime: number): Vector3?
	local e = enemies[id]
	if not e or e.Removed then
		return nil
	end
	local current = e.Root.Position
	if type(serverTime) ~= "number" or serverTime ~= serverTime then
		return current
	end
	local times = e.HistT
	local n = #times
	if n == 0 or serverTime >= times[n] then
		return current
	end
	local i, j, alpha = EnemyLogic.historyAt(times, serverTime)
	if not i or not j then
		return current
	end
	return e.HistP[i]:Lerp(e.HistP[j], alpha)
end

function EnemyService.QueryRadius(self: Types.EnemyService, center: Vector3, radius: number): { number }
	local out = {}
	if not finiteVector(center) or type(radius) ~= "number" or radius ~= radius or radius < 0 then
		return out
	end
	for id, e in pairs(enemies) do
		if not e.Dead and not e.Removed and (e.Root.Position - center).Magnitude <= radius then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

return EnemyService
