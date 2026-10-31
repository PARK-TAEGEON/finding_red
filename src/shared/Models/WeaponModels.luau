--!strict
-- Weapon models built from Parts (CONTRACT §3.8). Owner: A.
-- Every weapon model: PrimaryPart "Handle" at the grip, "Muzzle" attachment, front = -Z.
-- A real asset at ReplicatedStorage.Assets.Weapon.<Id> (Model or Tool with a Handle) wins over the
-- code-built fallback. All parts are anchored and non-colliding/non-query so they never block shots.
local Assets = require(script.Parent.Parent.Assets)

local WeaponModels = {}

export type Hold = {
	Offset: CFrame, -- weapon pivot relative to the camera (hip)
	Aim: CFrame?, -- weapon pivot relative to the camera while aiming (nil = no ADS pose)
	Right: Vector3, -- right hand position relative to the weapon pivot
	Left: Vector3, -- left hand position relative to the weapon pivot
}

local SKIN = Color3.fromRGB(234, 184, 146)
local SLEEVE = Color3.fromRGB(52, 86, 160)

-- Viewmodel layout per weapon (camera space: +X right, +Y up, -Z forward).
WeaponModels.Holds = {
	Bat = {
		Offset = CFrame.new(0.95, -1.05, -1.7) * CFrame.Angles(math.rad(55), math.rad(-15), 0),
		Aim = nil,
		Right = Vector3.new(0, 0, 0.05),
		Left = Vector3.new(0, 0, 0.45),
	},
	Pistol = {
		Offset = CFrame.new(0.55, -0.62, -1.55),
		Aim = CFrame.new(0, -0.47, -1.35),
		Right = Vector3.new(0, -0.26, 0.08),
		Left = Vector3.new(-0.1, -0.32, 0.12),
	},
	Sniper = {
		Offset = CFrame.new(0.62, -0.7, -1.35),
		Aim = CFrame.new(0, -0.6, -1.0),
		Right = Vector3.new(0, -0.24, 0.08),
		Left = Vector3.new(0, -0.08, -1.25),
	},
} :: { [string]: Hold }

local DEFAULT_HOLD: Hold = {
	Offset = CFrame.new(0.6, -0.65, -1.45),
	Aim = CFrame.new(0, -0.5, -1.2),
	Right = Vector3.new(0, -0.25, 0.08),
	Left = Vector3.new(0, -0.1, -1.0),
}

function WeaponModels.hold(id: string): Hold
	return WeaponModels.Holds[id] or DEFAULT_HOLD
end

-- Part helpers ------------------------------------------------------------------------------
local function prep(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

local function piece(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	prep(p)
	p.Parent = parent
	return p
end

local BLOCK = Enum.PartType.Block
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
-- Cylinders run along X; this turns them to run along Z (the barrel axis).
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0)

local function muzzle(handle: BasePart, at: Vector3)
	local a = Instance.new("Attachment")
	a.Name = "Muzzle"
	a.Position = at
	a.Parent = handle
end

local function newModel(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	return m
end

-- Code-built weapons (grip at origin) --------------------------------------------------------------
local function buildBat(): Model
	local m = newModel("Bat")
	local wood = Color3.fromRGB(214, 158, 98)
	local handle = piece(m, "Handle", CYL, Vector3.new(1.3, 0.2, 0.2), ALONG_Z, wood, Enum.Material.Wood)
	piece(m, "Tape", CYL, Vector3.new(0.7, 0.23, 0.23), CFrame.new(0, 0, 0.2) * ALONG_Z, Color3.fromRGB(200, 40, 40))
	piece(m, "Knob", CYL, Vector3.new(0.12, 0.34, 0.34), CFrame.new(0, 0, 0.66) * ALONG_Z, wood, Enum.Material.Wood)
	piece(m, "Neck", CYL, Vector3.new(0.8, 0.3, 0.3), CFrame.new(0, 0, -1.0) * ALONG_Z, wood, Enum.Material.Wood)
	piece(m, "Barrel", CYL, Vector3.new(1.6, 0.48, 0.48), CFrame.new(0, 0, -2.15) * ALONG_Z, wood, Enum.Material.Wood)
	piece(m, "Stripe", CYL, Vector3.new(0.14, 0.5, 0.5), CFrame.new(0, 0, -1.6) * ALONG_Z, Color3.fromRGB(255, 205, 40))
	piece(m, "Cap", BALL, Vector3.new(0.48, 0.48, 0.48), CFrame.new(0, 0, -2.95), wood, Enum.Material.Wood)
	muzzle(handle, handle.CFrame:ToObjectSpace(CFrame.new(0, 0, -2.2)).Position)
	m.PrimaryPart = handle
	return m
end

local function buildPistol(): Model
	local m = newModel("Pistol")
	local dark = Color3.fromRGB(38, 40, 46)
	local metal = Color3.fromRGB(70, 74, 84)
	local handle = piece(m, "Handle", BLOCK, Vector3.new(0.22, 0.58, 0.3), CFrame.new(0, -0.2, 0.06) * CFrame.Angles(math.rad(-14), 0, 0), dark)
	piece(m, "Slide", BLOCK, Vector3.new(0.26, 0.26, 1.0), CFrame.new(0, 0.2, -0.3), metal, Enum.Material.Metal)
	piece(m, "Frame", BLOCK, Vector3.new(0.22, 0.14, 0.8), CFrame.new(0, 0.03, -0.32), dark)
	piece(m, "Barrel", CYL, Vector3.new(0.1, 0.14, 0.14), CFrame.new(0, 0.2, -0.82) * ALONG_Z, Color3.fromRGB(20, 20, 22))
	piece(m, "Guard", BLOCK, Vector3.new(0.06, 0.16, 0.3), CFrame.new(0, -0.08, -0.2), dark)
	piece(m, "FrontSight", BLOCK, Vector3.new(0.05, 0.07, 0.06), CFrame.new(0, 0.36, -0.74), Color3.fromRGB(255, 120, 40), Enum.Material.Neon)
	piece(m, "RearSight", BLOCK, Vector3.new(0.14, 0.06, 0.06), CFrame.new(0, 0.36, 0.14), dark)
	-- Handle is tilted; place the muzzle in handle space so it ends at the barrel tip.
	muzzle(handle, handle.CFrame:ToObjectSpace(CFrame.new(0, 0.2, -0.88)).Position)
	m.PrimaryPart = handle
	return m
end

local function buildSniper(): Model
	local m = newModel("Sniper")
	local body = Color3.fromRGB(58, 74, 58)
	local dark = Color3.fromRGB(30, 32, 36)
	local wood = Color3.fromRGB(120, 84, 52)
	local handle = piece(m, "Handle", BLOCK, Vector3.new(0.2, 0.5, 0.28), CFrame.new(0, -0.18, 0.08) * CFrame.Angles(math.rad(-14), 0, 0), dark)
	piece(m, "Receiver", BLOCK, Vector3.new(0.3, 0.32, 1.7), CFrame.new(0, 0.12, -0.25), body, Enum.Material.Metal)
	piece(m, "Stock", BLOCK, Vector3.new(0.26, 0.42, 1.1), CFrame.new(0, 0.02, 1.15), wood, Enum.Material.Wood)
	piece(m, "Butt", BLOCK, Vector3.new(0.28, 0.6, 0.12), CFrame.new(0, -0.03, 1.72), dark)
	piece(m, "Handguard", BLOCK, Vector3.new(0.26, 0.24, 1.0), CFrame.new(0, 0.08, -1.45), wood, Enum.Material.Wood)
	piece(m, "Barrel", CYL, Vector3.new(2.3, 0.14, 0.14), CFrame.new(0, 0.16, -2.15) * ALONG_Z, dark, Enum.Material.Metal)
	piece(m, "Brake", CYL, Vector3.new(0.28, 0.22, 0.22), CFrame.new(0, 0.16, -3.3) * ALONG_Z, dark, Enum.Material.Metal)
	piece(m, "Scope", CYL, Vector3.new(1.2, 0.26, 0.26), CFrame.new(0, 0.5, -0.25) * ALONG_Z, dark, Enum.Material.Metal)
	piece(m, "ScopeFront", CYL, Vector3.new(0.3, 0.34, 0.34), CFrame.new(0, 0.5, -0.9) * ALONG_Z, dark, Enum.Material.Metal)
	piece(m, "Lens", CYL, Vector3.new(0.02, 0.3, 0.3), CFrame.new(0, 0.5, -1.06) * ALONG_Z, Color3.fromRGB(90, 200, 255), Enum.Material.Neon)
	piece(m, "Mount1", BLOCK, Vector3.new(0.1, 0.16, 0.1), CFrame.new(0, 0.34, -0.55), dark)
	piece(m, "Mount2", BLOCK, Vector3.new(0.1, 0.16, 0.1), CFrame.new(0, 0.34, 0.05), dark)
	piece(m, "Bolt", BALL, Vector3.new(0.16, 0.16, 0.16), CFrame.new(0.22, 0.2, 0.2), Color3.fromRGB(150, 150, 160), Enum.Material.Metal)
	local tip = CFrame.new(0, 0.16, -3.45)
	muzzle(handle, handle.CFrame:ToObjectSpace(tip).Position)
	m.PrimaryPart = handle
	return m
end

-- Generic placeholder for MVP weapons that have no model yet.
local function buildGeneric(id: string): Model
	local m = newModel(id)
	local dark = Color3.fromRGB(45, 48, 54)
	local handle = piece(m, "Handle", BLOCK, Vector3.new(0.22, 0.5, 0.3), CFrame.new(0, -0.18, 0.06), dark)
	piece(m, "Body", BLOCK, Vector3.new(0.3, 0.34, 1.8), CFrame.new(0, 0.14, -0.4), Color3.fromRGB(80, 90, 70), Enum.Material.Metal)
	piece(m, "Barrel", CYL, Vector3.new(0.8, 0.16, 0.16), CFrame.new(0, 0.16, -1.6) * ALONG_Z, dark)
	muzzle(handle, handle.CFrame:ToObjectSpace(CFrame.new(0, 0.16, -2.0)).Position)
	m.PrimaryPart = handle
	return m
end

local BUILDERS: { [string]: () -> Model } = {
	Bat = buildBat,
	Pistol = buildPistol,
	Sniper = buildSniper,
}

-- Asset path ---------------------------------------------------------------------------------------
local function fromAsset(id: string): Model?
	local inst = Assets.get("Weapon/" .. id)
	if not inst then
		return nil
	end
	local model: Model
	if inst:IsA("Model") then
		model = inst
	else
		-- Tool or Folder: move its children into a Model.
		model = newModel(id)
		for _, child in ipairs(inst:GetChildren()) do
			child.Parent = model
		end
		inst:Destroy()
	end
	local handle = model:FindFirstChild("Handle", true)
	if not handle or not handle:IsA("BasePart") then
		warn(("[WeaponModels] asset Weapon/%s has no Handle part; using the built-in model"):format(id))
		model:Destroy()
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			prep(d)
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy() -- everything is anchored; joints would only fight PivotTo
		end
	end
	model.Name = id
	model.PrimaryPart = handle
	return model
end

-- Public -------------------------------------------------------------------------------------------
-- Weapon model with its pivot at the grip (Handle), front -Z.
function WeaponModels.build(id: string): Model
	local asset = fromAsset(id)
	if asset then
		return asset
	end
	local builder = BUILDERS[id]
	local model: Model = if builder then builder() else buildGeneric(id)
	-- Code-built parts sit around the origin (= grip). Make that the pivot, whatever the handle's tilt.
	local handle = model.PrimaryPart
	if handle then
		handle.PivotOffset = handle.CFrame:Inverse()
	end
	return model
end

-- Muzzle attachment (falls back to the handle) for tracers / flashes.
function WeaponModels.muzzle(model: Model): Instance?
	local m = model:FindFirstChild("Muzzle", true)
	if m and m:IsA("Attachment") then
		return m
	end
	return model.PrimaryPart
end

function WeaponModels.muzzlePosition(model: Model): Vector3
	local m = WeaponModels.muzzle(model)
	if m and m:IsA("Attachment") then
		return m.WorldPosition
	elseif m and m:IsA("BasePart") then
		return m.Position
	end
	return model:GetPivot().Position
end

export type Arm = { Model: Model, Sleeve: BasePart, Hand: BasePart }

-- One first-person arm. Place it every frame with WeaponModels.placeArm.
function WeaponModels.arm(name: string, skin: Color3?, sleeve: Color3?): Arm
	local m = newModel(name)
	local s = piece(m, "Sleeve", BLOCK, Vector3.new(0.42, 0.42, 1), CFrame.new(), sleeve or SLEEVE)
	local h = piece(m, "Hand", BLOCK, Vector3.new(0.34, 0.34, 0.4), CFrame.new(), skin or SKIN)
	m.PrimaryPart = s
	return { Model = m, Sleeve = s, Hand = h }
end

-- Stretch the arm from shoulder to hand (world space).
function WeaponModels.placeArm(arm: Arm, shoulder: Vector3, hand: Vector3)
	local offset = hand - shoulder
	local len = offset.Magnitude
	if len < 0.05 then
		return
	end
	local dir = offset / len
	local up = if math.abs(dir.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local sleeveLen = math.max(0.1, len - 0.2)
	arm.Sleeve.Size = Vector3.new(0.42, 0.42, sleeveLen)
	arm.Sleeve.CFrame = CFrame.lookAt(shoulder + dir * (sleeveLen / 2), hand, up)
	arm.Hand.CFrame = CFrame.lookAt(hand, hand + dir, up)
end

-- Pickup display (server): container Model with a spinning "Weapon" child, a glowing "Ring" and a
-- name label. The client spins/bobs "Weapon" locally (see Controllers/Weapon/Fx).
function WeaponModels.display(id: string, name: string, groundCf: CFrame): Model
	local container = newModel("Pickup_" .. id)
	local ring = piece(
		container,
		"Ring",
		CYL,
		Vector3.new(0.2, 5, 5),
		CFrame.new(groundCf.Position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(255, 214, 64),
		Enum.Material.Neon
	)
	ring.Transparency = 0.35
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 120)
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = ring

	local weapon = WeaponModels.build(id)
	weapon.Name = "Weapon"
	pcall(function()
		weapon:ScaleTo(1.6)
	end)
	-- Centre the gun over the ring (the grip is not the middle of a long gun).
	local cf, size = weapon:GetBoundingBox()
	local centreOffset = weapon:GetPivot():ToObjectSpace(cf).Position
	local top = groundCf.Position + Vector3.new(0, 2.6, 0)
	weapon:PivotTo(CFrame.new(top) * CFrame.Angles(0, 0, math.rad(-20)) * CFrame.new(-centreOffset))
	weapon.Parent = container
	container.PrimaryPart = ring

	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(160, 36)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.2 + size.Y / 2, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.Adornee = ring
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = name
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 230, 120)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Parent = ring
	return container
end

-- Supply boxes (v0.5 §1.12.6) ---------------------------------------------------------------------
-- Health: white box with a red cross on every side and the top. Ammo: green box with a yellow stripe.
-- Built around the origin; the caller moves the pivot.
local function buildHealthBox(): Model
	local m = newModel("HealthBox")
	local s = 1.6
	local box = piece(m, "Box", BLOCK, Vector3.new(s, s, s), CFrame.new(), Color3.fromRGB(245, 245, 245))
	local red = Color3.fromRGB(220, 30, 40)
	local o, w, l = s + 0.04, 0.42, 1.1
	-- Each bar only pokes out of the box along one axis, so each face shows exactly one cross.
	piece(m, "CrossZ1", BLOCK, Vector3.new(w, l, o), CFrame.new(), red)
	piece(m, "CrossZ2", BLOCK, Vector3.new(l, w, o), CFrame.new(), red)
	piece(m, "CrossX1", BLOCK, Vector3.new(o, l, w), CFrame.new(), red)
	piece(m, "CrossX2", BLOCK, Vector3.new(o, w, l), CFrame.new(), red)
	piece(m, "CrossY1", BLOCK, Vector3.new(w, o, l), CFrame.new(), red)
	piece(m, "CrossY2", BLOCK, Vector3.new(l, o, w), CFrame.new(), red)
	m.PrimaryPart = box
	return m
end

local function buildAmmoBox(): Model
	local m = newModel("AmmoBox")
	local green = Color3.fromRGB(70, 120, 50)
	local box = piece(m, "Box", BLOCK, Vector3.new(2, 1.2, 1.3), CFrame.new(), green)
	piece(m, "Lid", BLOCK, Vector3.new(2.06, 0.18, 1.36), CFrame.new(0, 0.52, 0), Color3.fromRGB(52, 92, 38))
	piece(m, "Stripe", BLOCK, Vector3.new(2.04, 0.3, 1.34), CFrame.new(0, -0.05, 0), Color3.fromRGB(250, 210, 40))
	piece(m, "Grip", BLOCK, Vector3.new(0.7, 0.14, 0.2), CFrame.new(0, 0.72, 0), Color3.fromRGB(40, 40, 44))
	local brass = Color3.fromRGB(214, 170, 70)
	for i = -1, 1 do
		piece(m, "Round" .. (i + 2), CYL, Vector3.new(0.5, 0.16, 0.16), CFrame.new(i * 0.3, 0.86, 0.35) * CFrame.Angles(0, 0, math.rad(90)), brass, Enum.Material.Metal)
	end
	m.PrimaryPart = box
	return m
end

-- Display container like WeaponModels.display: a "Ring" (PrimaryPart) on the ground and an "Item"
-- model the client spins/bobs (Controllers/Weapon/Fx). kind = "Health" | "Ammo".
function WeaponModels.supplyDisplay(kind: string, groundCf: CFrame): Model
	local container = newModel("Pickup_" .. kind)
	local isHealth = kind == "Health"
	local glow = if isHealth then Color3.fromRGB(255, 90, 90) else Color3.fromRGB(120, 230, 90)
	local ring = piece(
		container,
		"Ring",
		CYL,
		Vector3.new(0.2, 3.6, 3.6),
		CFrame.new(groundCf.Position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		glow,
		Enum.Material.Neon
	)
	ring.Transparency = 0.4
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = 8
	light.Brightness = 1.2
	light.Parent = ring

	local item = if isHealth then buildHealthBox() else buildAmmoBox()
	item.Name = "Item"
	item:PivotTo(CFrame.new(groundCf.Position + Vector3.new(0, 1.9, 0)))
	item.Parent = container
	container.PrimaryPart = ring
	return container
end

-- Third-person weapon (client-only cosmetic on other players, v0.5): the normal weapon model, scaled
-- to character size. Same pivot (grip) and front (-Z).
function WeaponModels.worldModel(id: string): Model
	local model = WeaponModels.build(id)
	pcall(function()
		model:ScaleTo(0.85)
	end)
	return model
end

return WeaponModels
