--!strict
-- Client-side weapon effects: tracers, muzzle flash, impact puffs, explosions, pickup displays
-- (spin/bob locally, hide the ones *I* picked up). Owner: A.
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Fx = {}

local PICKUP_TAG = "WeaponPickupDisplay"

local folder: Folder? = nil

local function fxFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local created = Instance.new("Folder")
	created.Name = "FR_WeaponFx"
	created.Parent = workspace
	folder = created
	return created
end

local function fxPart(size: Vector3, cf: CFrame, color: Color3, transparency: number?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Transparency = transparency or 0
	p.Parent = fxFolder()
	return p
end

-- Thin glowing line from `from` to `to`, fading quickly.
function Fx.tracer(from: Vector3, to: Vector3, color: Color3?, width: number?)
	local offset = to - from
	local len = offset.Magnitude
	if len < 0.5 or len ~= len then
		return
	end
	local w = width or 0.08
	local p = fxPart(
		Vector3.new(w, w, len),
		CFrame.lookAt(from + offset / 2, to),
		color or Color3.fromRGB(255, 236, 160),
		0.15
	)
	TweenService:Create(p, TweenInfo.new(0.12, Enum.EasingStyle.Linear), { Transparency = 1, Size = Vector3.new(w * 0.3, w * 0.3, len) })
		:Play()
	Debris:AddItem(p, 0.2)
end

function Fx.flash(at: Vector3, size: number?)
	local s = size or 0.45
	local p = fxPart(Vector3.new(s, s, s), CFrame.new(at), Color3.fromRGB(255, 210, 90), 0.1)
	p.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Range = 8
	light.Brightness = 3
	light.Parent = p
	TweenService:Create(p, TweenInfo.new(0.06), { Transparency = 1 }):Play()
	Debris:AddItem(p, 0.1)
end

function Fx.impact(at: Vector3, isEnemy: boolean)
	local color = if isEnemy then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(200, 190, 170)
	local p = fxPart(Vector3.new(0.35, 0.35, 0.35), CFrame.new(at), color, 0.2)
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.SmoothPlastic
	TweenService:Create(p, TweenInfo.new(0.25), { Transparency = 1, Size = Vector3.new(1, 1, 1) }):Play()
	Debris:AddItem(p, 0.3)
end

function Fx.explosion(at: Vector3, radius: number)
	local r = math.clamp(radius, 1, 60)
	local ball = fxPart(Vector3.new(1, 1, 1), CFrame.new(at), Color3.fromRGB(255, 140, 40), 0.1)
	ball.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 80)
	light.Range = r * 2
	light.Brightness = 4
	light.Parent = ball
	TweenService:Create(ball, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(r * 2, r * 2, r * 2),
		Transparency = 1,
	}):Play()
	local smoke = fxPart(Vector3.new(1, 1, 1), CFrame.new(at), Color3.fromRGB(60, 60, 60), 0.4)
	smoke.Shape = Enum.PartType.Ball
	smoke.Material = Enum.Material.SmoothPlastic
	TweenService:Create(smoke, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(r * 1.4, r * 1.4, r * 1.4),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ball, 0.5)
	Debris:AddItem(smoke, 1)
end

-- Pickup displays -------------------------------------------------------------------------------------
type Display = { Model: Model, Weapon: Model?, Base: CFrame?, Centre: Vector3?, Phase: number, Hidden: boolean }
local displays: { [Instance]: Display } = {}
local hiddenMarkers: { [string]: boolean } = {}

local function setHidden(d: Display, hidden: boolean)
	d.Hidden = hidden
	for _, x in ipairs(d.Model:GetDescendants()) do
		if x:IsA("BasePart") then
			x.LocalTransparencyModifier = if hidden then 1 else 0
		elseif x:IsA("BillboardGui") then
			x.Enabled = not hidden
		elseif x:IsA("Light") then
			x.Enabled = not hidden
		end
	end
end

local function markerOf(model: Instance): string?
	local id = model:GetAttribute("MarkerId")
	if id == nil then
		return nil
	end
	return tostring(id)
end

local function track(inst: Instance)
	if not inst:IsA("Model") or displays[inst] then
		return
	end
	local d: Display =
		{ Model = inst, Weapon = nil, Base = nil, Centre = nil, Phase = math.random() * math.pi * 2, Hidden = false }
	displays[inst] = d
	local marker = markerOf(inst)
	if marker and hiddenMarkers[marker] then
		-- descendants may still be streaming in; hide now and again shortly after
		setHidden(d, true)
		task.delay(0.5, function()
			if displays[inst] == d and d.Hidden then
				setHidden(d, true)
			end
		end)
	end
end

local function untrack(inst: Instance)
	local d = displays[inst]
	if not d then
		return
	end
	displays[inst] = nil
	local marker = markerOf(inst)
	if marker then
		-- The display is gone (round over): forget the claim so next round's display shows again.
		hiddenMarkers[marker] = nil
	end
end

-- Called on Feedback PickedUp: hide that display on this client only.
function Fx.hidePickup(marker: string)
	hiddenMarkers[marker] = true
	for _, d in pairs(displays) do
		if markerOf(d.Model) == marker then
			setHidden(d, true)
		end
	end
end

local function spin(dt: number)
	local t = os.clock()
	for inst, d in pairs(displays) do
		if not inst.Parent then
			continue
		end
		if d.Weapon == nil or d.Weapon.Parent ~= inst then
			local w = inst:FindFirstChild("Weapon")
			if w and w:IsA("Model") then
				d.Weapon = w
				d.Base = w:GetPivot()
				d.Centre = (w:GetBoundingBox()).Position
			else
				continue
			end
		end
		local weapon, base, centre = d.Weapon, d.Base, d.Centre
		if weapon and base and centre and not d.Hidden then
			local bob = math.sin(t * 2 + d.Phase) * 0.3
			local angle = (t * 1.6 + d.Phase) % (math.pi * 2)
			-- spin around the vertical axis through the gun's centre, bobbing up and down
			weapon:PivotTo(CFrame.new(centre + Vector3.new(0, bob, 0)) * CFrame.Angles(0, angle, 0) * CFrame.new(-centre) * base)
		end
	end
end

function Fx.init()
	for _, inst in ipairs(CollectionService:GetTagged(PICKUP_TAG)) do
		track(inst)
	end
	CollectionService:GetInstanceAddedSignal(PICKUP_TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(PICKUP_TAG):Connect(untrack)
	RunService.RenderStepped:Connect(spin)
end

return Fx
