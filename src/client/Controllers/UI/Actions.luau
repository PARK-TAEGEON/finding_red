--!strict
-- Shared client actions for HUD (keyboard) and MobileControls (touch): sprint, jump, revive,
-- plus a tiny state-changed signal published by HUDController. Owner: C.
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local GameConfig = require(Shared.Config.Game)

local Actions = {}

local ctx: Types.ClientContext? = nil
local player = Players.LocalPlayer
local sprinting = false
local reviveTarget: Player? = nil
local listeners: { (Types.MatchState) -> () } = {}
local DOOR_MAX_RISE = 8 -- matches StageFlow

function Actions.init(c: Types.ClientContext)
	ctx = c
end

-- State signal ---------------------------------------------------------------------
function Actions.onState(fn: (Types.MatchState) -> ())
	table.insert(listeners, fn)
end

function Actions.publish(state: Types.MatchState)
	for _, fn in ipairs(listeners) do
		task.spawn(fn, state)
	end
end

function Actions.state(): Types.MatchState?
	return if ctx then ctx.State() else nil
end

-- Own stage flags from the `StageFlags` attribute (JSON id -> flags).
function Actions.stageFlags(): { [string]: number }
	local raw = player:GetAttribute("StageFlags")
	local out: { [string]: number } = {}
	if type(raw) ~= "string" then
		return out
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if ok and type(decoded) == "table" then
		for id, flags in pairs(decoded) do
			if type(id) == "string" and type(flags) == "number" then
				out[id] = flags
			end
		end
	end
	return out
end

-- Life ------------------------------------------------------------------------------
function Actions.lifeOf(p: Player): string
	local life = p:GetAttribute("Life")
	return if type(life) == "string" then life else "Alive"
end

function Actions.myLife(): string
	return Actions.lifeOf(player)
end

function Actions.inParty(userId: number): boolean
	local state = Actions.state()
	return state ~= nil and table.find(state.Party, userId) ~= nil
end

-- Playing, in the party and Alive: the only time weapons/first person are on.
function Actions.canAct(): boolean
	local state = Actions.state()
	return state ~= nil and state.Phase == "Playing" and Actions.myLife() == "Alive" and Actions.inParty(player.UserId)
end

function Actions.humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function Actions.root(p: Player?): BasePart?
	local character = (p or player).Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Sprint (client-side WalkSpeed; the server sets 4 while Downed) --------------------
function Actions.applySpeed()
	local humanoid = Actions.humanoid()
	if not humanoid then
		return
	end
	local life = Actions.myLife()
	if life == "Downed" then
		humanoid.WalkSpeed = GameConfig.DownedWalkSpeed
	elseif life == "Alive" and sprinting then
		humanoid.WalkSpeed = GameConfig.SprintSpeed
	else
		humanoid.WalkSpeed = GameConfig.WalkSpeed
	end
end

function Actions.isSprinting(): boolean
	return sprinting
end

function Actions.setSprint(on: boolean)
	sprinting = on
	Actions.applySpeed()
end

function Actions.toggleSprint()
	Actions.setSprint(not sprinting)
end

function Actions.jump()
	local humanoid = Actions.humanoid()
	if humanoid and Actions.myLife() ~= "Downed" then
		humanoid.Jump = true
	end
end

-- Revive ----------------------------------------------------------------------------
-- Nearest Downed teammate within ReviveRange while I can act.
function Actions.reviveCandidate(): Player?
	if not Actions.canAct() then
		return nil
	end
	local state = Actions.state()
	local mine = Actions.root()
	if not state or not mine then
		return nil
	end
	local best: Player? = nil
	local bestDistance = GameConfig.ReviveRange
	for _, userId in ipairs(state.Party) do
		local other = Players:GetPlayerByUserId(userId)
		if other and other ~= player and Actions.lifeOf(other) == "Downed" then
			local root = Actions.root(other)
			if root then
				local d = (root.Position - mine.Position).Magnitude
				if d <= bestDistance then
					best, bestDistance = other, d
				end
			end
		end
	end
	return best
end

function Actions.reviving(): Player?
	return reviveTarget
end

local function send(kind: string, target: Player)
	local c = ctx
	local state = Actions.state()
	if not c or not state then
		return
	end
	Net.event(c.Remotes, "Interact"):FireServer({ R = state.RoundId, Kind = kind, Target = target.UserId })
end

function Actions.startRevive(): boolean
	local target = Actions.reviveCandidate()
	if not target then
		return false
	end
	if reviveTarget and reviveTarget ~= target then
		send("ReviveStop", reviveTarget)
	end
	reviveTarget = target
	send("ReviveStart", target)
	return true
end

function Actions.stopRevive()
	local target = reviveTarget
	if target then
		reviveTarget = nil
		send("ReviveStop", target)
	end
end

-- Start room + door (CONTRACT §1.12.3) ------------------------------------------------
-- Countdown with EndsAt == nil is loading; with EndsAt set the party is in the start room.
function Actions.isLoading(): boolean
	local state = Actions.state()
	return state ~= nil and state.Phase == "Countdown" and state.EndsAt == nil
end

function Actions.inStartRoom(): boolean
	local state = Actions.state()
	return state ~= nil
		and state.Phase == "Countdown"
		and state.EndsAt ~= nil
		and Actions.inParty(player.UserId)
		and Actions.myLife() == "Alive"
end

-- The StartDoor marker of the current stage (tagged part under workspace.Stage), if any.
local cachedDoor: BasePart? = nil
local nextDoorScan = 0
function Actions.doorPart(): BasePart?
	local stage = workspace:FindFirstChild("Stage")
	if not stage then
		cachedDoor = nil
		return nil
	end
	local door = cachedDoor
	if door and door:IsDescendantOf(stage) then
		return door
	end
	cachedDoor = nil
	if os.clock() < nextDoorScan then
		return nil
	end
	nextDoorScan = os.clock() + 0.5
	for _, inst in ipairs(CollectionService:GetTagged("StartDoor")) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(stage) then
			cachedDoor = inst
			return inst
		end
	end
	return nil
end

-- Flat distance to the door (same rule as the server). nil = this stage has no door marker.
function Actions.doorDistance(): number?
	local door = Actions.doorPart()
	if not door then
		return nil
	end
	local mine = Actions.root()
	if not mine then
		return math.huge
	end
	local a, b = mine.Position, door.Position
	if math.abs(a.Y - b.Y) > DOOR_MAX_RISE then
		return math.huge
	end
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- In the start room and close enough to the door (anywhere when the stage has no door marker;
-- the server allows that case too).
function Actions.canOpenDoor(): boolean
	if not Actions.inStartRoom() then
		return false
	end
	local d = Actions.doorDistance()
	return d == nil or d <= GameConfig.DoorInteractRange
end

local lastDoorSend = 0
function Actions.openDoor(): boolean
	local c = ctx
	local state = Actions.state()
	if not c or not state or not Actions.canOpenDoor() or os.clock() - lastDoorSend < 0.3 then
		return false
	end
	lastDoorSend = os.clock()
	Net.event(c.Remotes, "Interact"):FireServer({ R = state.RoundId, Kind = "OpenDoor" })
	return true
end

-- Called every frame by the HUD: drop a hold whose target got up / left / moved away.
function Actions.watchRevive()
	local target = reviveTarget
	if not target then
		return
	end
	if not target.Parent or Actions.lifeOf(target) ~= "Downed" or not Actions.canAct() then
		Actions.stopRevive()
		return
	end
	local a, b = Actions.root(), Actions.root(target)
	if not a or not b or (a.Position - b.Position).Magnitude > GameConfig.ReviveRange + 1 then
		Actions.stopRevive()
	end
end

return Actions
