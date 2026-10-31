--!strict
-- Third-person weapons for OTHER players (v0.5, cosmetic, client-only — nothing is replicated).
-- Reads each teammate's replicated `Equipped` attribute and keeps a code-built weapon model on their
-- right hand, moved every frame (anchored, non-colliding, non-query parts → never blocks shots).
-- The local player is first-person with the viewmodel, so they are skipped. Owner: A.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local WeaponModels = require(Shared.Models.WeaponModels)

local ThirdPerson = {}

type Entry = {
	Player: Player,
	Id: string?,
	Model: Model?,
	Conns: { RBXScriptConnection },
}

local localPlayer = Players.LocalPlayer
local entries: { [Player]: Entry } = {}
local folder: Folder? = nil
local MAX_DRAW_DISTANCE = 250

-- Grip relative to the arm part. R6 "Right Arm": +Y up the arm, hand at Y = -1, -Z = forward when
-- the arm hangs, so guns point forward at the hip and the bat rests tilted up and forward.
local R6_GRIP: { [string]: CFrame } = {
	Bat = CFrame.new(0, -1.05, -0.1) * CFrame.Angles(math.rad(55), 0, 0),
}
local R6_GUN = CFrame.new(0, -1.05, -0.15)
-- R15 "RightHand": the hand part itself.
local R15_GRIP: { [string]: CFrame } = {
	Bat = CFrame.new(0, -0.1, -0.05) * CFrame.Angles(math.rad(55), 0, 0),
}
local R15_GUN = CFrame.new(0, -0.15, -0.1)

local function fxFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local created = Instance.new("Folder")
	created.Name = "FR_ThirdPersonWeapons"
	created.Parent = workspace
	folder = created
	return created
end

local function validWeapon(id: any): boolean
	return type(id) == "string" and id ~= "" and #id <= 16
end

local function shouldShow(p: Player): boolean
	local life = p:GetAttribute("Life")
	return validWeapon(p:GetAttribute("Equipped")) and life ~= "Out" and life ~= "Spectating"
end

local function armOf(p: Player): (BasePart?, CFrame?)
	local character = p.Character
	if not character then
		return nil, nil
	end
	local r6 = character:FindFirstChild("Right Arm")
	if r6 and r6:IsA("BasePart") then
		return r6, nil
	end
	local r15 = character:FindFirstChild("RightHand")
	if r15 and r15:IsA("BasePart") then
		return r15, R15_GUN
	end
	return nil, nil
end

local function gripFor(id: string, isR15: boolean): CFrame
	if isR15 then
		return R15_GRIP[id] or R15_GUN
	end
	return R6_GRIP[id] or R6_GUN
end

local function refresh(entry: Entry)
	local p = entry.Player
	local want: string? = nil
	if shouldShow(p) then
		want = p:GetAttribute("Equipped") :: string
	end
	if want == entry.Id and (want == nil or entry.Model ~= nil) then
		return
	end
	if entry.Model then
		entry.Model:Destroy()
		entry.Model = nil
	end
	entry.Id = want
	if want then
		local ok, model = pcall(WeaponModels.worldModel, want)
		if ok and model then
			model.Name = ("TP_%d_%s"):format(p.UserId, want)
			model.Parent = fxFolder()
			entry.Model = model
		end
	end
end

local function untrack(p: Player)
	local entry = entries[p]
	if not entry then
		return
	end
	entries[p] = nil
	for _, c in ipairs(entry.Conns) do
		c:Disconnect()
	end
	if entry.Model then
		entry.Model:Destroy()
	end
end

local function track(p: Player)
	if p == localPlayer or entries[p] then
		return
	end
	local entry: Entry = { Player = p, Id = nil, Model = nil, Conns = {} }
	entries[p] = entry
	local function onChange()
		refresh(entry)
	end
	table.insert(entry.Conns, p:GetAttributeChangedSignal("Equipped"):Connect(onChange))
	table.insert(entry.Conns, p:GetAttributeChangedSignal("Life"):Connect(onChange))
	refresh(entry)
end

local function step()
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else nil
	for p, entry in pairs(entries) do
		local model, id = entry.Model, entry.Id
		if model and id then
			local arm, r15 = armOf(p)
			local show = arm ~= nil
				and arm.Parent ~= nil
				and (camPos == nil or (arm.Position - camPos).Magnitude <= MAX_DRAW_DISTANCE)
			if show and arm then
				if model.Parent == nil then
					model.Parent = fxFolder()
				end
				model:PivotTo(arm.CFrame * gripFor(id, r15 ~= nil))
			elseif model.Parent ~= nil then
				model.Parent = nil -- no character / respawning / far away: keep the model, just hide it
			end
		end
	end
end

-- Muzzle of a teammate's third-person weapon (tracer start), or nil if none is shown.
function ThirdPerson.muzzle(userId: number): Vector3?
	local p = Players:GetPlayerByUserId(userId)
	local entry = p and entries[p]
	local model = entry and entry.Model
	if model and model.Parent then
		return WeaponModels.muzzlePosition(model)
	end
	return nil
end

function ThirdPerson.init()
	for _, p in ipairs(Players:GetPlayers()) do
		track(p)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	local warned = false
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(function(): any
			step()
			return nil
		end)
		if not ok and not warned then
			warned = true -- cosmetic only: report once, never spam
			warn("[ThirdPerson] " .. tostring(err))
		end
	end)
end

return ThirdPerson
