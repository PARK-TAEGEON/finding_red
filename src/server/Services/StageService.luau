--!strict
-- StageService (CONTRACT §3.4, §3.7). Owner: D.
-- Builds workspace.Lobby at the origin on Start, and workspace.Stage at Config.Game.StageOrigin on Load.
-- Markers are found by CollectionService tags only. Sets Lighting for the stage's Sky (Day / Night).
-- v0.5: every stage has a start room; its white door (Geometry parts named Kit.Names.Door) is built closed and
-- OpenStartDoor slides it (server CFrame tween, 0.6 s) by the StartDoor marker's `Slide` offset, then turns its
-- collision off.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Config = Shared:WaitForChild("Config")
local Stages = require(Config:WaitForChild("Stages"))
local GameConfig = require(Config:WaitForChild("Game"))

local Server = script.Parent.Parent
local MapsFolder = Server:WaitForChild("Maps")
local Kit = require(Server.Maps.Kit)
local MapBuilder = require(script.Parent.MapBuilder)

local StageService = {}

local _ctx: Types.Context? = nil
local lobby: MapBuilder.Built? = nil
local stage: MapBuilder.Built? = nil
local current: Types.StageHandle? = nil
local lobbySpawns: { BasePart } = {}
local lobbyBoard: BasePart? = nil
local stageBoard: BasePart? = nil

local LOBBY_TEXT = "파인딩 레드\n준비 버튼을 누르면 시작해요\n레드만 잡으세요!"

local DOOR_NAME: string = Kit.Names.Door
local DOOR_OPEN_SECONDS = 0.6

type DoorState = {
	parts: { BasePart },
	closed: { CFrame },
	offset: Vector3,
	center: Vector3, -- door center, closed (world)
	open: boolean,
}
local door: DoorState? = nil

-- Lighting ---------------------------------------------------------------------------

local SKIES = {
	Day = {
		ClockTime = 14,
		Brightness = 2.2,
		Ambient = Color3.fromRGB(105, 105, 112),
		OutdoorAmbient = Color3.fromRGB(150, 150, 150),
		ExposureCompensation = 0,
		FogColor = Color3.fromRGB(200, 220, 240),
	},
	Night = {
		-- moonlit but playable: high ambient so Reds stay visible, lamps add warm pools
		ClockTime = 0,
		Brightness = 1.2,
		Ambient = Color3.fromRGB(88, 92, 125),
		OutdoorAmbient = Color3.fromRGB(118, 124, 165),
		ExposureCompensation = 0.35,
		FogColor = Color3.fromRGB(20, 26, 48),
	},
}

local function applySky(sky: string)
	local s = SKIES[sky] or SKIES.Day
	Lighting.ClockTime = s.ClockTime
	Lighting.Brightness = s.Brightness
	Lighting.Ambient = s.Ambient
	Lighting.OutdoorAmbient = s.OutdoorAmbient
	Lighting.ExposureCompensation = s.ExposureCompensation
	Lighting.FogColor = s.FogColor
	Lighting.FogStart = 0
	Lighting.FogEnd = 100000
end

-- Helpers ---------------------------------------------------------------------------

local function originOf(v: any): Vector3
	if type(v) == "table" then
		return Vector3.new(v[1] or 0, v[2] or 0, v[3] or 0)
	end
	return Vector3.zero
end

local function loadSpec(mapName: string): Types.MapSpec
	local module = MapsFolder:FindFirstChild(mapName)
	assert(module and module:IsA("ModuleScript"), "[StageService] missing map module " .. mapName)
	local build: any = (require :: any)(module)
	assert(type(build) == "function", "[StageService] map module must return a function: " .. mapName)
	local spec: Types.MapSpec = build(Kit)
	return spec
end

local function splitLines(text: string): { string }
	local lines = {}
	for line in string.gmatch(text .. "\n", "(.-)\n") do
		table.insert(lines, line)
	end
	return lines
end

local function sortedById(list: { BasePart }): { BasePart }
	local copy = table.clone(list)
	table.sort(copy, function(a, b)
		local ia, ib = a:GetAttribute("MarkerId"), b:GetAttribute("MarkerId")
		return tostring(ia or a.Name) < tostring(ib or b.Name)
	end)
	return copy
end

-- "x,y,z" -> Vector3 (nil if malformed)
local function parseVector(s: any): Vector3?
	if type(s) ~= "string" then
		return nil
	end
	local a, b, c = string.match(s, "^%s*([%-%d%.eE]+)%s*,%s*([%-%d%.eE]+)%s*,%s*([%-%d%.eE]+)%s*$")
	local x, y, z = tonumber(a), tonumber(b), tonumber(c)
	if x == nil or y == nil or z == nil then
		return nil
	end
	return Vector3.new(x, y, z)
end

-- Finds the start door of a freshly built (closed) stage. Door parts = BaseParts named DOOR_NAME that are
-- not markers (the StartDoor marker part may carry the same name). Hand-built maps: same names/tags work.
local function setupDoor(model: Model, markers: { [string]: { BasePart } }): DoorState?
	local parts: { BasePart } = {}
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") and inst.Name == DOOR_NAME and #CollectionService:GetTags(inst) == 0 then
			table.insert(parts, inst)
		end
	end
	local marker = (markers.StartDoor or {})[1]
	if #parts == 0 then
		if marker then
			warn("[StageService] StartDoor marker without door parts")
			return { parts = {}, closed = {}, offset = Vector3.zero, center = marker.Position, open = false }
		end
		return nil
	end
	-- the biggest part is the door slab; the rest (handles) ride along
	local main = parts[1]
	for _, p in parts do
		if p.Size.X * p.Size.Y * p.Size.Z > main.Size.X * main.Size.Y * main.Size.Z then
			main = p
		end
	end
	local offset = if marker then parseVector(marker:GetAttribute("Slide")) else nil
	if offset == nil then
		-- no Slide attribute: slide along the slab's long horizontal axis by its width
		if main.Size.X >= main.Size.Z then
			offset = -main.CFrame.RightVector * main.Size.X
		else
			offset = -main.CFrame.LookVector * main.Size.Z
		end
	end
	local closed: { CFrame } = {}
	for i, p in parts do
		closed[i] = p.CFrame -- MapBuilder just built it: closed, slab collidable, handles not
	end
	return {
		parts = parts,
		closed = closed,
		offset = offset :: Vector3,
		center = if marker then marker.Position else main.Position,
		open = false,
	}
end

local function buildLobby()
	local old = workspace:FindFirstChild("Lobby")
	if old then
		old:Destroy()
	end
	local built = MapBuilder.build(loadSpec("Lobby"), "Lobby", Vector3.zero, workspace)
	lobby = built
	local markers = MapBuilder.collectMarkers(built.Model)
	lobbySpawns = sortedById(markers.PlayerSpawn or {})
	local boards = markers.Board or {}
	lobbyBoard = boards[1]
	if lobbyBoard then
		MapBuilder.setBoardLines(lobbyBoard, splitLines(LOBBY_TEXT))
	end
	if #lobbySpawns == 0 then
		warn("[StageService] lobby has no PlayerSpawn markers")
	end
end

-- Service API ---------------------------------------------------------------------------

function StageService.Init(self: Types.StageService, c: Types.Context)
	_ctx = c
end

function StageService.Start(self: Types.StageService)
	applySky("Day")
	buildLobby()
end

function StageService.Load(self: Types.StageService, stageId: string): Types.StageHandle
	local cfg = Stages[stageId]
	assert(type(cfg) == "table" and type(cfg.Map) == "string", "[StageService] unknown stage " .. tostring(stageId))
	StageService.Unload(self)
	local old = workspace:FindFirstChild("Stage")
	if old then
		old:Destroy()
	end
	local spec = loadSpec(cfg.Map)
	local built = MapBuilder.build(spec, "Stage", originOf(GameConfig.StageOrigin), workspace)
	built.Model:SetAttribute("StageId", stageId)
	stage = built
	local markers = MapBuilder.collectMarkers(built.Model)
	local handle: Types.StageHandle = { StageId = stageId, Model = built.Model, Markers = markers }
	current = handle
	local boards = markers.Board or {}
	stageBoard = boards[1]
	if stageBoard then
		MapBuilder.setBoardLines(stageBoard, { "LEVEL " .. stageId, tostring(cfg.Name or ""), "" })
	end
	door = setupDoor(built.Model, markers)
	if door == nil then
		warn("[StageService] stage " .. stageId .. " has no start door")
	end
	applySky(if cfg.Sky == "Night" then "Night" else "Day")
	return handle
end

function StageService.Unload(self: Types.StageService)
	if stage then
		stage.Model:Destroy()
	end
	stage = nil
	current = nil
	stageBoard = nil
	door = nil
	applySky("Day")
end

function StageService.Current(self: Types.StageService): Types.StageHandle?
	return current
end

-- Root-part CFrame standing on lobby spawn ((index - 1) mod n) + 1, facing the lobby board.
function StageService.LobbySpawn(self: Types.StageService, index: number): CFrame
	local n = #lobbySpawns
	if n == 0 then
		return CFrame.new(0, 5, 0)
	end
	local i = ((math.floor(index) - 1) % n) + 1
	local spawn = lobbySpawns[i]
	return spawn.CFrame + Vector3.new(0, 0.5, 0)
end

function StageService.SetBoard(self: Types.StageService, lines: { string })
	if stageBoard and stageBoard.Parent then
		MapBuilder.setBoardLines(stageBoard, lines)
	end
end

-- Slides the start door into its wall over DOOR_OPEN_SECONDS, then makes it non-collidable (and invisible to
-- raycasts). Idempotent: later calls (or calls with no stage / no door) do nothing.
function StageService.OpenStartDoor(self: Types.StageService)
	local d = door
	if d == nil or d.open then
		return
	end
	d.open = true
	local info = TweenInfo.new(DOOR_OPEN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for i, p in d.parts do
		if p.Parent then
			TweenService:Create(p, info, { CFrame = d.closed[i] + d.offset }):Play()
		end
	end
	task.delay(DOOR_OPEN_SECONDS, function()
		for i, p in d.parts do
			if p.Parent then
				p.CFrame = d.closed[i] + d.offset
				p.CanCollide = false
				p.CanQuery = false
			end
		end
	end)
end

-- Door center (world, closed position; the StartDoor marker) for StageFlow's distance check. nil without a stage.
function StageService.StartDoorPosition(self: Types.StageService): Vector3?
	if current == nil or door == nil then
		return nil
	end
	return door.center
end

function StageService.SetLobbyBoard(self: Types.StageService, text: string)
	if lobbyBoard and lobbyBoard.Parent then
		MapBuilder.setBoardLines(lobbyBoard, splitLines(text))
	end
end

-- World geometry only (lobby + current stage Geometry folders): no markers, enemies or characters.
-- A fresh RaycastParams per call, so callers may keep or modify theirs safely.
function StageService.GeometryParams(self: Types.StageService): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local include: { Instance } = {}
	if lobby and lobby.Geometry.Parent then
		table.insert(include, lobby.Geometry)
	end
	if stage and stage.Geometry.Parent then
		table.insert(include, stage.Geometry)
	end
	params.FilterDescendantsInstances = include
	params.IgnoreWater = true
	return params
end

return StageService
