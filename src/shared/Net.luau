--!strict
-- Remote creation/lookup and argument validation helpers. Owner: orchestrator.
local Net = {}

Net.Events = {
	"State",
	"Ready",
	"Vote",
	"Fire",
	"Reload",
	"Throw",
	"Equip",
	"Interact",
	"Setting",
	"Effect",
	"Feedback",
	"Request",
}

local FOLDER = "Remotes"

-- Server: create ReplicatedStorage.Remotes with every RemoteEvent. Call once from Main.server.
function Net.create(): Folder
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local existing = ReplicatedStorage:FindFirstChild(FOLDER)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER
	for _, name in ipairs(Net.Events) do
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	return folder
end

-- Client: wait for the folder created by the server.
function Net.get(): Folder
	local folder = game:GetService("ReplicatedStorage"):WaitForChild(FOLDER)
	return folder :: Folder
end

function Net.event(remotes: Folder, name: string): RemoteEvent
	local event = remotes:FindFirstChild(name)
	assert(event and event:IsA("RemoteEvent"), "unknown remote " .. name)
	return event :: RemoteEvent
end

-- Validation -------------------------------------------------------------------
local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

function Net.isNumber(value: any, min: number?, max: number?): boolean
	if type(value) ~= "number" or not finite(value) then
		return false
	end
	if min and value < min then
		return false
	end
	if max and value > max then
		return false
	end
	return true
end

function Net.isVector(value: any, maxMagnitude: number?): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local v = value :: Vector3
	if not (finite(v.X) and finite(v.Y) and finite(v.Z)) then
		return false
	end
	return v.Magnitude <= (maxMagnitude or 1e5)
end

function Net.isString(value: any, maxLength: number?): boolean
	return type(value) == "string" and #value <= (maxLength or 64)
end

-- Per-player, per-key rate limit. Returns true when the call is allowed.
local nextAllowed: { [Player]: { [string]: number } } = {}
function Net.throttle(player: Player, key: string, interval: number): boolean
	local now = os.clock()
	local byKey = nextAllowed[player]
	if not byKey then
		byKey = {}
		nextAllowed[player] = byKey
	end
	if now < (byKey[key] or 0) then
		return false
	end
	byKey[key] = now + interval
	return true
end

function Net.forget(player: Player)
	nextAllowed[player] = nil
end

return Net
