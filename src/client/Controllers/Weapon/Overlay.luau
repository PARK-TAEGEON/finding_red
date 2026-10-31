--!strict
-- Weapon screen overlay: crosshair, hit marker, sniper scope (CONTRACT §3.5 HUD split: A draws these).
-- Owner: A. Pure UI built from Frames (no image assets).
local TweenService = game:GetService("TweenService")

local Overlay = {}

local gui: ScreenGui
local crosshair: Frame
local hitMarker: Frame
local hitLines: { Frame } = {}
local scope: Frame
local hitToken = 0
local crosshairWanted = false
local enabled = false
local scoped = false

local function frame(parent: Instance, name: string, size: UDim2, pos: UDim2, color: Color3, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Active = false
	f.Parent = parent
	return f
end

local function outlined(f: Frame)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.45
	stroke.Thickness = 1
	stroke.Parent = f
end

local function buildCrosshair(parent: Instance): Frame
	local root = frame(parent, "Crosshair", UDim2.fromOffset(40, 40), UDim2.fromScale(0.5, 0.5), Color3.new(1, 1, 1))
	root.BackgroundTransparency = 1
	local white = Color3.new(1, 1, 1)
	local dot = frame(root, "Dot", UDim2.fromOffset(4, 4), UDim2.fromScale(0.5, 0.5), white)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
	outlined(dot)
	-- four short ticks around the centre
	local ticks: { { Name: string, Size: UDim2, Pos: UDim2 } } = {
		{ Name = "Top", Size = UDim2.fromOffset(2, 8), Pos = UDim2.new(0.5, 0, 0.5, -10) },
		{ Name = "Bottom", Size = UDim2.fromOffset(2, 8), Pos = UDim2.new(0.5, 0, 0.5, 10) },
		{ Name = "Left", Size = UDim2.fromOffset(8, 2), Pos = UDim2.new(0.5, -10, 0.5, 0) },
		{ Name = "Right", Size = UDim2.fromOffset(8, 2), Pos = UDim2.new(0.5, 10, 0.5, 0) },
	}
	for _, t in ipairs(ticks) do
		outlined(frame(root, t.Name, t.Size, t.Pos, white))
	end
	return root
end

local function buildHitMarker(parent: Instance): Frame
	local root = frame(parent, "HitMarker", UDim2.fromOffset(44, 44), UDim2.fromScale(0.5, 0.5), Color3.new(1, 1, 1))
	root.BackgroundTransparency = 1
	root.Visible = false
	-- An X made of four short diagonal bars, leaving the centre clear.
	for i, angle in ipairs({ 45, 135, 225, 315 }) do
		local r = math.rad(angle)
		local bar = frame(
			root,
			"Bar" .. i,
			UDim2.new(0.3, 0, 0, 3),
			UDim2.fromScale(0.5 + math.cos(r) * 0.3, 0.5 + math.sin(r) * 0.3),
			Color3.new(1, 1, 1)
		)
		bar.Rotation = angle
		outlined(bar)
		table.insert(hitLines, bar)
	end
	return root
end

local function buildScope(parent: Instance): Frame
	-- A square "lens" holder centred on screen; its UICorner makes it a circle and a thick black
	-- UIStroke fills the corners around the circle. Four huge black bars cover the rest of the screen.
	local holder = frame(parent, "Scope", UDim2.fromScale(0.92, 0.92), UDim2.fromScale(0.5, 0.5), Color3.new(0, 0, 0))
	holder.BackgroundTransparency = 1
	holder.Visible = false
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = holder

	local lens = frame(holder, "Lens", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Color3.new(0, 0, 0))
	lens.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = lens
	local ring = Instance.new("UIStroke")
	ring.Color = Color3.new(0, 0, 0)
	ring.Thickness = 400
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = lens

	local black = Color3.new(0, 0, 0)
	frame(holder, "L", UDim2.new(0, 6000, 0, 12000), UDim2.new(0, 1, 0.5, 0), black, Vector2.new(1, 0.5))
	frame(holder, "R", UDim2.new(0, 6000, 0, 12000), UDim2.new(1, -1, 0.5, 0), black, Vector2.new(0, 0.5))
	frame(holder, "T", UDim2.new(1, 0, 0, 6000), UDim2.new(0.5, 0, 0, 1), black, Vector2.new(0.5, 1))
	frame(holder, "B", UDim2.new(1, 0, 0, 6000), UDim2.new(0.5, 0, 1, -1), black, Vector2.new(0.5, 0))

	-- Reticle: thin black cross with a gap, and a small red centre dot.
	local thin = Color3.fromRGB(10, 10, 10)
	frame(holder, "H1", UDim2.new(0.45, 0, 0, 2), UDim2.new(0, 0, 0.5, 0), thin, Vector2.new(0, 0.5))
	frame(holder, "H2", UDim2.new(0.45, 0, 0, 2), UDim2.new(1, 0, 0.5, 0), thin, Vector2.new(1, 0.5))
	frame(holder, "V1", UDim2.new(0, 2, 0.45, 0), UDim2.new(0.5, 0, 0, 0), thin, Vector2.new(0.5, 0))
	frame(holder, "V2", UDim2.new(0, 2, 0.45, 0), UDim2.new(0.5, 0, 1, 0), thin, Vector2.new(0.5, 1))
	local dot = frame(holder, "Dot", UDim2.fromOffset(4, 4), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(255, 50, 50))
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	return holder
end

local function refresh()
	crosshair.Visible = enabled and crosshairWanted and not scoped
	scope.Visible = enabled and scoped
	if not enabled then
		hitMarker.Visible = false
	end
end

function Overlay.init(playerGui: Instance)
	gui = Instance.new("ScreenGui")
	gui.Name = "FR_WeaponOverlay"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 0 -- C's HUD should use a higher DisplayOrder so ammo text stays above the scope
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	scope = buildScope(gui)
	crosshair = buildCrosshair(gui)
	hitMarker = buildHitMarker(gui)
	gui.Parent = playerGui
	refresh()
end

function Overlay.setEnabled(on: boolean)
	enabled = on
	refresh()
end

function Overlay.setCrosshair(on: boolean)
	crosshairWanted = on
	refresh()
end

function Overlay.setScope(on: boolean)
	scoped = on
	refresh()
end

-- White X on a hit, red X when the kill was a penalty (non-target). Bigger on kills.
function Overlay.hit(killed: boolean, penalty: boolean)
	if not enabled then
		return
	end
	hitToken += 1
	local token = hitToken
	local color = if penalty then Color3.fromRGB(255, 50, 50) else Color3.new(1, 1, 1)
	for _, bar in ipairs(hitLines) do
		bar.BackgroundColor3 = color
		bar.BackgroundTransparency = 0
	end
	local size = if killed then 60 else 44
	hitMarker.Size = UDim2.fromOffset(size * 1.3, size * 1.3)
	hitMarker.Visible = true
	TweenService:Create(hitMarker, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(size, size),
	}):Play()
	task.delay(if killed then 0.45 else 0.25, function()
		if hitToken ~= token then
			return
		end
		for _, bar in ipairs(hitLines) do
			TweenService:Create(bar, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
		end
		task.delay(0.13, function()
			if hitToken == token then
				hitMarker.Visible = false
			end
		end)
	end)
end

return Overlay
