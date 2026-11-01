--!strict
-- Code-built R6 enemy rigs (CONTRACT §1.8, §2.6, §3.8). Owner: B.
-- `build(kind)` returns a Model: HumanoidRootPart (PrimaryPart), Torso, Head, Left/Right Arm,
-- Left/Right Leg, Roblox-standard R6 Motor6Ds (RootJoint, Neck, Left/Right Shoulder, Left/Right Hip)
-- so the classic R6 animations drive it, and a Humanoid (RigType R6) with an Animator.
-- A reviewer-provided ReplicatedStorage.Assets.Enemy.<Kind> rig is used instead when present.
-- Overhead GUIs (on the Head): "HPBar" (Back/Fill frames) and "Alert" ("!" label, disabled).
local Shared = script.Parent.Parent
local Assets = require(Shared.Assets)
local EnemiesConfig = require(Shared.Config.Enemies)
local EnemyBody = require(Shared.Models.EnemyBody)

local EnemyModels = {}

EnemyModels.WALK_ANIM = "rbxassetid://180426354"
EnemyModels.IDLE_ANIM = "rbxassetid://180435571"
EnemyModels.WALK_ANIM_SPEED = 14.5 -- R6 Animate script scales walk playback by speed / 14.5

local LIMBS = { "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

function EnemyModels.color(hex: string): Color3
	local ok, c = pcall(Color3.fromHex, hex)
	if ok then
		return c
	end
	return Color3.new(1, 0, 1)
end

local function part(model: Model, name: string, size: Vector3, color: Color3, collide: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = collide
	p.CanQuery = true
	p.CanTouch = true
	p.CastShadow = true
	p.Parent = model
	return p
end

local function motor(name: string, parent: BasePart, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = c0
	m.C1 = c1
	m.Parent = parent
	return m
end

-- Small cosmetic part welded to `to` (massless, no collision, still queryable for hits).
local function decor(model: Model, to: BasePart, name: string, size: Vector3, color: Color3, offset: CFrame): Part
	local p = part(model, name, size, color, false)
	p.Massless = true
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = to.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = to
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	return p
end

local function frame(parent: Instance, name: string, pos: UDim2, size: UDim2, color: Color3, rotation: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = pos
	f.Size = size
	f.Rotation = rotation or 0
	f.Parent = parent
	return f
end


-- Visible body (orchestrator, design pass 2026-11-01): the R6 bones stay for animation, joints and
-- ragdoll but turn invisible; EnemyBody's shells are welded on top so the silhouette is slim and
-- rounded instead of the stock blocky R6. Shells are massless, non-colliding and queryable (hits).
local function shellPart(shape: string, size: Vector3): BasePart
	if shape == "Wedge" then
		local w = Instance.new("WedgePart")
		w.Size = size
		return w
	end
	local p = Instance.new("Part")
	if shape == "Ball" then
		local d = math.min(size.X, size.Y, size.Z)
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(d, d, d)
	elseif shape == "Cylinder" then
		local d = math.min(size.Y, size.Z)
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(size.X, d, d)
	else
		p.Size = size
		if shape == "Ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
	end
	return p
end

local function applyShells(model: Model, kind: string, bones: { [string]: BasePart }, body: string, accent: string): boolean
	local shells = EnemyBody.shells(kind, body, accent)
	if not shells then
		return false
	end
	for name, bone in pairs(bones) do
		if name ~= "HumanoidRootPart" then
			bone.Transparency = 1
			bone.CastShadow = false
		end
	end
	for _, s in ipairs(shells) do
		local bone = bones[s.Bone]
		if bone then
			local sp = shellPart(s.Shape, Vector3.new(s.Size[1], s.Size[2], s.Size[3]))
			sp.Name = s.Name or "Shell"
			sp.Color = EnemyModels.color(s.Color)
			local okMat, mat = pcall(function()
				return (Enum.Material :: any)[s.Material or "SmoothPlastic"]
			end)
			sp.Material = if okMat and mat then mat else Enum.Material.SmoothPlastic
			if s.Material == "Glass" then
				sp.Reflectance = 0.25
			end
			sp.TopSurface = Enum.SurfaceType.Smooth
			sp.BottomSurface = Enum.SurfaceType.Smooth
			sp.Anchored = false
			sp.CanCollide = false
			sp.CanTouch = false
			sp.CanQuery = true
			sp.Massless = true
			sp.CastShadow = s.Material ~= "Neon"
			local rot = s.Rot or { 0, 0, 0 }
			local offset = CFrame.new(s.Pos[1], s.Pos[2], s.Pos[3])
				* CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
			sp.CFrame = bone.CFrame * offset
			local w = Instance.new("Weld")
			w.Part0 = bone
			w.Part1 = sp
			w.C0 = offset
			w.Parent = sp
			sp.Parent = model
		end
	end
	return true
end

local BLACK = Color3.fromRGB(20, 18, 22)
local WHITE = Color3.fromRGB(250, 250, 250)

-- Red face: yellow angry eyes under slanted brows, black mouth with white teeth.
local function redFace(head: BasePart, accent: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.3
	gui.ClipsDescendants = true
	gui.Parent = head
	-- eyes
	for i, x in ipairs({ 0.14, 0.58 }) do
		local eye = frame(gui, "Eye" .. i, UDim2.fromScale(x, 0.2), UDim2.fromScale(0.28, 0.3), accent, if i == 1 then 12 else -12)
		frame(eye, "Pupil", UDim2.fromScale(if i == 1 then 0.55 else 0.15, 0.3), UDim2.fromScale(0.3, 0.55), BLACK)
	end
	-- brows "\ /"
	frame(gui, "BrowL", UDim2.fromScale(0.1, 0.1), UDim2.fromScale(0.36, 0.1), BLACK, 22)
	frame(gui, "BrowR", UDim2.fromScale(0.54, 0.1), UDim2.fromScale(0.36, 0.1), BLACK, -22)
	-- mouth + teeth
	local mouth = frame(gui, "Mouth", UDim2.fromScale(0.2, 0.62), UDim2.fromScale(0.6, 0.3), BLACK)
	for k = 0, 3 do
		frame(mouth, "ToothTop" .. k, UDim2.fromScale(0.04 + k * 0.24, 0), UDim2.fromScale(0.18, 0.42), WHITE)
	end
	for k = 0, 2 do
		frame(mouth, "ToothBottom" .. k, UDim2.fromScale(0.16 + k * 0.24, 0.58), UDim2.fromScale(0.18, 0.42), WHITE)
	end
end

-- White face: wide black visor (a real part so it reads at distance) with a thin glint.
local function whiteFace(model: Model, head: BasePart, accent: Color3)
	local visor = decor(model, head, "Visor", Vector3.new(1.8, 0.45, 0.16), accent, CFrame.new(0, 0.08, -0.52))
	visor.Material = Enum.Material.Glass
	visor.Reflectance = 0.25
	local glint = decor(model, head, "Glint", Vector3.new(0.5, 0.08, 0.05), WHITE, CFrame.new(-0.45, 0.18, -0.61))
	glint.Material = Enum.Material.Neon
	glint.CanQuery = true
end

local function overhead(head: BasePart)
	local bar = Instance.new("BillboardGui")
	bar.Name = "HPBar"
	bar.Size = UDim2.new(2.6, 0, 0.3, 0)
	bar.StudsOffset = Vector3.new(0, EnemyBody.HeadTop + 0.45, 0)
	bar.LightInfluence = 0
	bar.MaxDistance = 120
	bar.AlwaysOnTop = false
	bar.Parent = head
	local back = frame(bar, "Back", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), BLACK)
	back.BackgroundTransparency = 0.3
	local fill = frame(back, "Fill", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Color3.fromRGB(92, 226, 80))
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	corner:Clone().Parent = fill

	local alert = Instance.new("BillboardGui")
	alert.Name = "Alert"
	alert.Size = UDim2.new(2.4, 0, 2.4, 0)
	alert.StudsOffset = Vector3.new(0, EnemyBody.HeadTop + 1.9, 0)
	alert.LightInfluence = 0
	alert.MaxDistance = 160
	alert.AlwaysOnTop = true
	alert.Enabled = false
	alert.Parent = head
	local mark = Instance.new("TextLabel")
	mark.Name = "Mark"
	mark.BackgroundTransparency = 1
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.Size = UDim2.fromScale(1, 1)
	mark.Text = "!"
	mark.Font = Enum.Font.GothamBlack
	mark.TextScaled = true
	mark.TextColor3 = Color3.fromRGB(255, 226, 64)
	mark.TextStrokeColor3 = BLACK
	mark.TextStrokeTransparency = 0
	mark.Parent = alert
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = mark
end

local function setupHumanoid(model: Model, speed: number): Humanoid
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		local h = Instance.new("Humanoid")
		h.RigType = Enum.HumanoidRigType.R6
		h.Parent = model
		hum = h
	end
	local h = hum :: Humanoid
	h.HipHeight = 0
	h.MaxHealth = 100
	h.Health = 100
	h.WalkSpeed = speed
	h.UseJumpPower = true
	h.JumpPower = 45
	h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	h.NameDisplayDistance = 0
	h.BreakJointsOnDeath = false
	h.RequiresNeck = false
	-- HP lives in the model attribute; the Humanoid must never die, sit or ragdoll on its own.
	for _, s in ipairs({
		Enum.HumanoidStateType.Dead,
		Enum.HumanoidStateType.Seated,
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.Climbing,
	}) do
		h:SetStateEnabled(s, false)
	end
	if not h:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = h
	end
	return h
end

local function buildR6(kind: string, cfg: EnemiesConfig.EnemyConfig?): Model
	local body = EnemyModels.color(if cfg then cfg.Body else "#AAAAAA")
	local accent = EnemyModels.color(if cfg then cfg.Accent else "#222222")
	local legs = body:Lerp(Color3.new(0, 0, 0), 0.22)

	local model = Instance.new("Model")
	model.Name = kind

	local root = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1), body, false)
	root.Transparency = 1
	root.CastShadow = false
	root.RootPriority = 1
	local torso = part(model, "Torso", Vector3.new(2, 2, 1), body, true)
	local head = part(model, "Head", Vector3.new(2, 1, 1), body, true)
	local la = part(model, "Left Arm", Vector3.new(1, 2, 1), body, false)
	local ra = part(model, "Right Arm", Vector3.new(1, 2, 1), body, false)
	local ll = part(model, "Left Leg", Vector3.new(1, 2, 1), legs, false)
	local rl = part(model, "Right Leg", Vector3.new(1, 2, 1), legs, false)

	-- Roblox-standard R6 joint frames.
	local base = CFrame.new(0, 3, 0)
	root.CFrame = base
	torso.CFrame = base
	head.CFrame = base * CFrame.new(0, 1.5, 0)
	la.CFrame = base * CFrame.new(-1.5, 0, 0)
	ra.CFrame = base * CFrame.new(1.5, 0, 0)
	ll.CFrame = base * CFrame.new(-0.5, -2, 0)
	rl.CFrame = base * CFrame.new(0.5, -2, 0)
	motor("RootJoint", root, root, torso, CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor("Neck", torso, torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor("Right Shoulder", torso, torso, ra, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Shoulder", torso, torso, la, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	motor("Right Hip", torso, torso, rl, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Hip", torso, torso, ll, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))

	local shelled = applyShells(model, kind, {
		HumanoidRootPart = root,
		Torso = torso,
		Head = head,
		["Left Arm"] = la,
		["Right Arm"] = ra,
		["Left Leg"] = ll,
		["Right Leg"] = rl,
	}, if cfg then cfg.Body else "#AAAAAA", if cfg then cfg.Accent else "#222222")
	if shelled then
		-- face, horns and visor come from the shells
	elseif kind == "Red" then
		redFace(head, accent)
		-- two little horns: readable red silhouette even from behind
		for i, x in ipairs({ -0.6, 0.6 }) do
			local horn = decor(model, head, "Horn" .. i, Vector3.new(0.3, 0.45, 0.3), legs, CFrame.new(x, 0.7, 0) * CFrame.Angles(0, 0, math.rad(if x < 0 then 15 else -15)))
			horn.CanQuery = true
		end
	elseif kind == "White" then
		whiteFace(model, head, accent)
	else
		local band = decor(model, head, "Band", Vector3.new(1.6, 0.3, 0.12), accent, CFrame.new(0, 0.1, -0.52))
		band.Material = Enum.Material.Neon
	end

	model.PrimaryPart = root
	return model
end

-- Builds (or clones from Assets) the rig for `kind`. Always returns a Model with PrimaryPart =
-- HumanoidRootPart, a Humanoid + Animator, and the overhead GUIs on the head. Pivot at origin,
-- feet on y = 0.
function EnemyModels.build(kind: string): Model
	local cfg = EnemiesConfig[kind]
	local model: Model? = nil
	local asset = Assets.get("Enemy/" .. kind)
	if asset then
		local ok = asset:IsA("Model")
			and asset:FindFirstChild("HumanoidRootPart") ~= nil
			and asset:FindFirstChildOfClass("Humanoid") ~= nil
		if ok then
			local m = asset :: Model
			m.Name = kind
			m.PrimaryPart = m:FindFirstChild("HumanoidRootPart") :: BasePart
			model = m
		else
			warn(("[EnemyModels] Assets Enemy/%s is not an R6 rig, using the built-in model"):format(kind))
			asset:Destroy()
		end
	end
	local m = model or buildR6(kind, cfg)
	setupHumanoid(m, if cfg then cfg.Speed else 8)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanQuery = true
			d.Anchored = false
		end
	end
	local head = m:FindFirstChild("Head")
	local anchor = if head and head:IsA("BasePart") then head else m.PrimaryPart
	if anchor and not anchor:FindFirstChild("HPBar") then
		overhead(anchor)
	end
	return m
end

export type Tracks = { Walk: AnimationTrack?, Idle: AnimationTrack? }

-- Loads the classic R6 walk/idle animations. Must be called once the model is in workspace.
-- Any failure (no Animator, asset blocked, offline Studio) degrades to no animation.
function EnemyModels.loadAnimations(hum: Humanoid): Tracks
	local tracks: Tracks = {}
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		return tracks
	end
	local function load(id: string, name: string, priority: Enum.AnimationPriority): AnimationTrack?
		local anim = Instance.new("Animation")
		anim.Name = name
		anim.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(anim)
		end)
		if ok and track then
			local t = track :: AnimationTrack
			t.Looped = true
			t.Priority = priority
			return t
		end
		return nil
	end
	tracks.Walk = load(EnemyModels.WALK_ANIM, "Walk", Enum.AnimationPriority.Movement)
	tracks.Idle = load(EnemyModels.IDLE_ANIM, "Idle", Enum.AnimationPriority.Idle)
	return tracks
end

EnemyModels.LIMBS = LIMBS

return EnemyModels
