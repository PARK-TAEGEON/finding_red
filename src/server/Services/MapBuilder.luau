--!strict
-- MapBuilder. Owner: D. Turns a Types.MapSpec (pure data, CONTRACT §3.7) into a Model:
--   <Model name>
--     Geometry/  anchored parts (world geometry; StageService.GeometryParams includes only this folder)
--     Markers/   invisible 1×1×1 tagged parts with attributes (the Board marker becomes the chalkboard)
-- Not a service: StageService calls MapBuilder.build / MapBuilder.setBoardLines.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local MapBuilder = {}

export type Built = {
	Model: Model,
	Geometry: Folder,
	Markers: Folder,
}

local BOARD_COLOR = Color3.fromRGB(46, 78, 58)
local CHALK = Color3.fromRGB(242, 242, 232)
local LIGHT_COLOR = Color3.fromRGB(255, 226, 170)

local function material(name: string): Enum.Material
	local ok, value = pcall(function(): any
		return (Enum.Material :: any)[name]
	end)
	if ok and typeof(value) == "EnumItem" then
		return value :: any
	end
	warn(("[MapBuilder] unknown material %q, using SmoothPlastic"):format(tostring(name)))
	return Enum.Material.SmoothPlastic
end

local function color(hex: string): Color3
	local ok, value = pcall(Color3.fromHex, hex)
	if ok then
		return value
	end
	warn(("[MapBuilder] bad color %q"):format(tostring(hex)))
	return Color3.fromRGB(163, 162, 165)
end

local function cframeOf(origin: Vector3, pos: Types.Vec3, rot: Types.Vec3?): CFrame
	local cf = CFrame.new(origin + Vector3.new(pos[1], pos[2], pos[3]))
	if rot then
		cf *= CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
	end
	return cf
end

local function makePart(spec: Types.MapPart, origin: Vector3): BasePart
	local part: BasePart
	if spec.Shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if spec.Shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		elseif spec.Shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		else
			p.Shape = Enum.PartType.Block
		end
		part = p
	end
	part.Name = spec.Name or spec.Shape
	part.Anchored = true
	part.Size = Vector3.new(spec.Size[1], spec.Size[2], spec.Size[3])
	part.CFrame = cframeOf(origin, spec.Pos, spec.Rot)
	part.Color = color(spec.Color)
	part.Material = material(spec.Material)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = spec.Transparency or 0
	local collide = spec.Collide ~= false
	part.CanCollide = collide
	-- decoration (seams, window strips, grid posts) never blocks rays or touches
	part.CanQuery = collide
	part.CanTouch = false
	if not collide then
		part.CastShadow = false
	end
	if spec.Name == "Light" then
		local light = Instance.new("PointLight")
		light.Range = 26
		light.Brightness = 1.4
		light.Color = LIGHT_COLOR
		light.Shadows = false
		light.Parent = part
	end
	return part
end

-- Chalkboard text ---------------------------------------------------------------------

local LINE_LAYOUT: { { y: number, h: number, font: Enum.Font } } = {
	{ y = 0.05, h = 0.30, font = Enum.Font.GothamBlack },
	{ y = 0.38, h = 0.28, font = Enum.Font.GothamBold },
	{ y = 0.70, h = 0.24, font = Enum.Font.Gotham },
}

local function makeBoardGui(board: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0 -- readable at night too
	gui.ResetOnSpawn = false
	for i, l in LINE_LAYOUT do
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. i
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.05, l.y)
		label.Size = UDim2.fromScale(0.9, l.h)
		label.Font = l.font
		label.TextColor3 = CHALK
		label.TextScaled = true
		label.TextWrapped = true
		label.Text = ""
		label.Parent = gui
	end
	gui.Parent = board
end

-- Sets up to 3 lines; extra lines are joined into the last one.
function MapBuilder.setBoardLines(board: BasePart, lines: { string })
	local gui = board:FindFirstChild("BoardGui")
	if not gui then
		return
	end
	local shown = { lines[1] or "", lines[2] or "", lines[3] or "" }
	if #lines > 3 then
		local rest = {}
		for i = 3, #lines do
			table.insert(rest, lines[i])
		end
		shown[3] = table.concat(rest, "  ")
	end
	for i = 1, 3 do
		local label = gui:FindFirstChild("Line" .. i)
		if label and label:IsA("TextLabel") then
			label.Text = shown[i]
		end
	end
end

local function makeMarker(spec: Types.MapMarker, origin: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = spec.Id or spec.Tag
	part.Anchored = true
	part.Size = Vector3.one
	part.CFrame = cframeOf(origin, spec.Pos, spec.Rot)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	if spec.Attr then
		for key, value in spec.Attr do
			part:SetAttribute(key, value)
		end
	end
	if spec.Id then
		part:SetAttribute("MarkerId", spec.Id)
	end
	CollectionService:AddTag(part, spec.Tag)
	if spec.Tag == "Board" then
		-- the board marker becomes the visible dark-green chalkboard panel
		local attr: { [string]: any } = spec.Attr or {}
		local w = if type(attr.Width) == "number" then attr.Width else 12
		local h = if type(attr.Height) == "number" then attr.Height else 7
		part.Size = Vector3.new(w, h, 0.4)
		part.Transparency = 0
		part.Color = BOARD_COLOR
		part.Material = Enum.Material.SmoothPlastic
		part.CanCollide = true
		part.CanQuery = true
		part.CastShadow = true
		makeBoardGui(part)
	end
	return part
end

-- Builds `spec` as Model `name` under `parent`, shifted by `origin` (map origin = floor center).
function MapBuilder.build(spec: Types.MapSpec, name: string, origin: Vector3, parent: Instance): Built
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("MapName", spec.Name)
	local geometry = Instance.new("Folder")
	geometry.Name = "Geometry"
	geometry.Parent = model
	local markers = Instance.new("Folder")
	markers.Name = "Markers"
	markers.Parent = model
	for _, p in spec.Parts do
		makePart(p, origin).Parent = geometry
	end
	for _, m in spec.Markers do
		makeMarker(m, origin).Parent = markers
	end
	local floor = geometry:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		model.PrimaryPart = floor
	end
	model.Parent = parent
	return { Model = model, Geometry = geometry, Markers = markers }
end

-- Every tagged BasePart under `root`, grouped by tag (tags only, so hand-built maps work too).
function MapBuilder.collectMarkers(root: Instance): { [string]: { BasePart } }
	local out: { [string]: { BasePart } } = {}
	for _, inst in root:GetDescendants() do
		if inst:IsA("BasePart") then
			for _, tag in CollectionService:GetTags(inst) do
				local list = out[tag]
				if not list then
					list = {}
					out[tag] = list
				end
				table.insert(list, inst)
			end
		end
	end
	return out
end

return MapBuilder
