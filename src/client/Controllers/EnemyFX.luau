--!strict
-- Client-side enemy effects (CONTRACT §1.8, §1.11). Owner: B. Purely cosmetic, never authoritative.
-- Watches workspace.Enemies models:
--   State -> "Alert": "!" pop + Alert sound      State -> "Stunned": spinning stars
--   HP drops: brief white flash                    Attack counter: WhiteAttack sound + arm swing
-- Effect "EnemyDeath": RedDeath sound + corpse fade-out before the server removes it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Types = require(ReplicatedStorage.Shared.Types)
local Net = require(ReplicatedStorage.Shared.Net)

local EnemyFX = {}

local ctx: Types.ClientContext

type Watch = {
	Model: Model,
	Conns: { RBXScriptConnection },
	LastHP: number,
	Stun: BillboardGui?,
	SwingC0: CFrame?,
}

local watched: { [Model]: Watch } = {}
local byId: { [number]: Model } = {}

local function headOf(model: Model): BasePart?
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return model.PrimaryPart
end

local function posOf(model: Model): Vector3?
	local head = headOf(model)
	return if head then head.Position else nil
end

local function flash(model: Model)
	local h = Instance.new("Highlight")
	h.Name = "HitFlash"
	h.Adornee = model
	h.FillColor = Color3.new(1, 1, 1)
	h.FillTransparency = 0.1
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = model
	TweenService:Create(h, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = 1 }):Play()
	task.delay(0.22, function()
		h:Destroy()
	end)
end

local function popAlert(model: Model)
	local head = headOf(model)
	local gui = head and head:FindFirstChild("Alert")
	local mark = gui and gui:FindFirstChild("Mark")
	local scale = mark and mark:FindFirstChild("Pop")
	if scale and scale:IsA("UIScale") then
		scale.Scale = 0.2
		TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function setStunned(w: Watch, on: boolean)
	if on and not w.Stun then
		local head = headOf(w.Model)
		if not head then
			return
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "StunFX"
		gui.Size = UDim2.new(2.2, 0, 1.1, 0)
		gui.StudsOffset = Vector3.new(0, 1.9, 0)
		gui.LightInfluence = 0
		gui.MaxDistance = 120
		gui.Parent = head
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(1, 1)
		label.Text = "★ ★ ★"
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = Color3.fromRGB(255, 230, 90)
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		TweenService:Create(label, TweenInfo.new(0.6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }):Play()
		w.Stun = gui
	elseif not on and w.Stun then
		(w.Stun :: BillboardGui):Destroy()
		w.Stun = nil
	end
end

local function swing(w: Watch)
	local torso = w.Model:FindFirstChild("Torso")
	local shoulder = torso and torso:FindFirstChild("Right Shoulder")
	if not shoulder or not shoulder:IsA("Motor6D") then
		return
	end
	local base = w.SwingC0 or shoulder.C0
	w.SwingC0 = base
	local tween = TweenService:Create(
		shoulder,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
		{ C0 = base * CFrame.Angles(0, 0, math.rad(100)) }
	)
	tween.Completed:Connect(function()
		if shoulder.Parent then
			shoulder.C0 = base
		end
	end)
	tween:Play()
end

local function fadeOut(model: Model, delay: number, duration: number)
	local parts: { BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		elseif d:IsA("LayerCollector") then
			(d :: LayerCollector).Enabled = false
		end
	end
	task.delay(delay, function()
		local started = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			local a = math.clamp((os.clock() - started) / duration, 0, 1)
			for _, p in ipairs(parts) do
				if p.Parent then
					p.LocalTransparencyModifier = a
				end
			end
			if a >= 1 or not model.Parent then
				conn:Disconnect()
			end
		end)
	end)
end

local function unwatch(model: Model)
	local w = watched[model]
	if not w then
		return
	end
	for _, c in ipairs(w.Conns) do
		c:Disconnect()
	end
	watched[model] = nil
	local id = model:GetAttribute("EnemyId")
	if type(id) == "number" and byId[id] == model then
		byId[id] = nil
	end
end

local function watch(inst: Instance)
	if not inst:IsA("Model") or watched[inst] then
		return
	end
	local model = inst :: Model
	local hp = model:GetAttribute("HP")
	local w: Watch = {
		Model = model,
		Conns = {},
		LastHP = if type(hp) == "number" then hp else math.huge,
		Stun = nil,
		SwingC0 = nil,
	}
	watched[model] = w
	local function register()
		local id = model:GetAttribute("EnemyId")
		if type(id) == "number" then
			byId[id] = model
		end
	end
	register()
	table.insert(w.Conns, model:GetAttributeChangedSignal("EnemyId"):Connect(register))
	table.insert(
		w.Conns,
		model:GetAttributeChangedSignal("State"):Connect(function()
			local state = model:GetAttribute("State")
			if state == "Alert" then
				ctx.PlaySound("Alert", posOf(model))
				popAlert(model)
			end
			setStunned(w, state == "Stunned")
		end)
	)
	table.insert(
		w.Conns,
		model:GetAttributeChangedSignal("HP"):Connect(function()
			local now = model:GetAttribute("HP")
			if type(now) ~= "number" then
				return
			end
			if now < w.LastHP then
				flash(model)
			end
			w.LastHP = now
		end)
	)
	table.insert(
		w.Conns,
		model:GetAttributeChangedSignal("Attack"):Connect(function()
			ctx.PlaySound("WhiteAttack", posOf(model))
			swing(w)
		end)
	)
	if model:GetAttribute("State") == "Stunned" then
		setStunned(w, true)
	end
end

local function onEffect(kind: any, data: any)
	if type(data) ~= "table" then
		return
	end
	if kind == "EnemyDeath" then
		local pos = data.Pos
		ctx.PlaySound("RedDeath", if typeof(pos) == "Vector3" then pos else nil)
		local id = data.Id
		local model = if type(id) == "number" then byId[id] else nil
		if model then
			local w = watched[model]
			if w then
				setStunned(w, false)
			end
			fadeOut(model, 1.6, 0.8)
		end
	end
end

function EnemyFX.Init(self: Types.EnemyFX, c: Types.ClientContext)
	ctx = c
end

function EnemyFX.Start(self: Types.EnemyFX)
	Net.event(ctx.Remotes, "Effect").OnClientEvent:Connect(onEffect)
	task.spawn(function()
		local folder = workspace:WaitForChild("Enemies")
		for _, child in ipairs(folder:GetChildren()) do
			watch(child)
		end
		folder.ChildAdded:Connect(watch)
		folder.ChildRemoved:Connect(function(child)
			if child:IsA("Model") then
				unwatch(child)
			end
		end)
	end)
end

return EnemyFX
