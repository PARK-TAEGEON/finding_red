--!strict
-- Touch buttons (CONTRACT §1.6, §3.5). Owner: C. Only built when UserInputService.TouchEnabled.
-- Roblox's default thumbstick + camera drag stay; we add round buttons on the right:
-- 공격 (hold), 조준 (toggle), 점프, 달리기 (toggle), 무기변경, and 부활 (hold, when possible).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

local UI = script.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Actions = require(UI:WaitForChild("Actions"))

local MobileControls = {}

local player = Players.LocalPlayer
local ctx: Types.ClientContext
local C = Kit.Colors

type Hold = { Button: TextButton, Release: () -> () }

local gui: ScreenGui
local attackButton: TextButton
local aimButton: TextButton
local cycleButton: TextButton
local sprintButton: TextButton
local jumpButton: TextButton
local reviveButton: TextButton
local holds: { Hold } = {}
local aiming = false
local attacking = false

local function weapon(): Types.WeaponController
	return ctx.Controllers.Weapon
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
end

-- Positioned by its center, in "units" measured from the bottom-right corner.
local function roundButton(text: string, color: Color3, cx: number, cy: number, size: number, unit: number): TextButton
	local b = Kit.button(gui, text, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -cx * unit, 1, -cy * unit),
		Size = UDim2.fromOffset(size * unit, size * unit),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.15,
		AutoButtonColor = false,
		Font = Kit.Title,
	})
	Kit.round(b)
	Kit.stroke(b, C.White, 3)
	Kit.padding(b, math.floor(size * unit * 0.2))
	return b
end

-- Hold button: onDown when a finger lands on it, onUp when that finger lifts (anywhere).
local function holdButton(button: TextButton, onDown: () -> (), onUp: () -> ())
	local active: InputObject? = nil
	local function release()
		if active then
			active = nil
			button.BackgroundTransparency = 0.15
			onUp()
		end
	end
	button.InputBegan:Connect(function(input)
		if active or not isPress(input) then
			return
		end
		active = input
		button.BackgroundTransparency = 0
		onDown()
	end)
	UserInputService.InputEnded:Connect(function(input)
		local a = active
		if a and (rawequal(input, a) or (a.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == a.UserInputType)) then
			release()
		end
	end)
	table.insert(holds, { Button = button, Release = release })
end

local function tapButton(button: TextButton, onTap: () -> ())
	button.InputBegan:Connect(function(input)
		if isPress(input) then
			onTap()
		end
	end)
end

local function setAim(on: boolean)
	if aiming == on then
		return
	end
	aiming = on
	aimButton.BackgroundColor3 = if on then C.Gold else C.PanelLight
	pcall(function()
		weapon():Aim(on)
	end)
end

local function refresh()
	local canAct = Actions.canAct()
	local life = Actions.myLife()
	attackButton.Visible = canAct
	aimButton.Visible = canAct
	cycleButton.Visible = canAct
	sprintButton.Visible = life == "Alive"
	jumpButton.Visible = life ~= "Downed"
	reviveButton.Visible = Actions.reviving() ~= nil or Actions.reviveCandidate() ~= nil
	sprintButton.BackgroundColor3 = if Actions.isSprinting() then C.Gold else C.PanelLight
	if not canAct then
		setAim(false)
	end
	-- Hidden buttons never stay "held".
	for _, h in ipairs(holds) do
		if not h.Button.Visible then
			h.Release()
		end
	end
end

local function build()
	gui = Kit.gui("FindingRedMobile", 6, player:WaitForChild("PlayerGui"))
	local camera = workspace.CurrentCamera
	local shortSide = if camera then math.min(camera.ViewportSize.X, camera.ViewportSize.Y) else 400
	-- Roblox's own jump button sits in the bottom-right corner (~1 unit); ours go around it.
	local unit = if shortSide < 500 then 52 else 76

	attackButton = roundButton("공격", C.Red, 2.75, 1.0, 1.35, unit)
	aimButton = roundButton("조준", C.PanelLight, 4.2, 0.85, 0.95, unit)
	cycleButton = roundButton("무기변경", C.PanelLight, 4.0, 2.15, 0.85, unit)
	sprintButton = roundButton("달리기", C.PanelLight, 2.7, 2.45, 0.85, unit)
	jumpButton = roundButton("점프", C.Blue, 1.2, 2.45, 0.85, unit)
	reviveButton = roundButton("부활", C.Green, 1.9, 3.75, 1.15, unit)
	reviveButton.Visible = false

	holdButton(attackButton, function()
		attacking = true
		pcall(function()
			weapon():Attack(true)
		end)
	end, function()
		if attacking then
			attacking = false
			pcall(function()
				weapon():Attack(false)
			end)
		end
	end)
	tapButton(aimButton, function()
		setAim(not aiming)
	end)
	tapButton(cycleButton, function()
		pcall(function()
			weapon():Cycle()
		end)
	end)
	tapButton(sprintButton, function()
		Actions.toggleSprint()
		refresh()
	end)
	tapButton(jumpButton, Actions.jump)
	holdButton(reviveButton, function()
		Actions.startRevive()
	end, function()
		Actions.stopRevive()
	end)
end

function MobileControls.Init(self: Types.MobileControls, c: Types.ClientContext)
	ctx = c
end

function MobileControls.Start(self: Types.MobileControls)
	if not UserInputService.TouchEnabled then
		return
	end
	build()
	Actions.onState(function()
		refresh()
	end)
	player:GetAttributeChangedSignal("Life"):Connect(refresh)
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum >= 0.1 then
			accum = 0
			refresh()
		end
	end)
	refresh()
end

return MobileControls
