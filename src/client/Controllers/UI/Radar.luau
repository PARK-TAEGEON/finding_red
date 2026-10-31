--!strict
-- Circular radar (CONTRACT §3.5): radius 120 studs, rotates with the camera (up = camera forward).
-- Red dots = Kind "Red" enemies that are not Dead, white = other enemies, green = teammates. Owner: C.
local Players = game:GetService("Players")

local Kit = require(script.Parent.Kit)

export type Radar = {
	Frame: Frame,
	Update: (state: { Party: { number } }) -> (),
}

local Radar = {}

local RANGE = 120
local ENEMY_LIMIT = 60

function Radar.new(parent: Instance, sizePx: number): Radar
	local frame = Kit.frame(parent, {
		Name = "Radar",
		Size = UDim2.fromOffset(sizePx, sizePx),
		BackgroundColor3 = Color3.fromRGB(20, 40, 30),
		BackgroundTransparency = 0.25,
	})
	Kit.round(frame)
	Kit.stroke(frame, Kit.Colors.White, 3)
	-- range rings
	for _, scale in ipairs({ 0.5 }) do
		local ring = Kit.frame(frame, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(scale, scale),
			BackgroundTransparency = 1,
		})
		Kit.round(ring)
		local s = Kit.stroke(ring, Kit.Colors.White, 1)
		s.Transparency = 0.6
	end
	-- self marker: small arrow
	local me = Kit.label(frame, "▲", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(14, 14),
		TextColor3 = Kit.Colors.Gold,
		Font = Kit.Title,
		ZIndex = 5,
	})
	Kit.textStroke(me, Kit.Colors.Ink, 1)

	local pool: { Frame } = {}
	local radiusPx = sizePx / 2 - 6

	local function dot(i: number): Frame
		local existing = pool[i]
		if existing then
			return existing
		end
		local d = Kit.frame(frame, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(9, 9),
			ZIndex = 4,
		})
		Kit.round(d)
		Kit.stroke(d, Kit.Colors.Ink, 1)
		pool[i] = d
		return d
	end

	local function update(state: { Party: { number } })
		local used = 0
		local camera = workspace.CurrentCamera
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if camera and root and root:IsA("BasePart") then
			local look = camera.CFrame.LookVector
			local forward = Vector3.new(look.X, 0, look.Z)
			if forward.Magnitude < 1e-3 then
				forward = Vector3.new(0, 0, -1)
			end
			forward = forward.Unit
			local right = Vector3.new(-forward.Z, 0, forward.X)
			local origin = root.Position

			local function plot(position: Vector3, color: Color3, clampToRim: boolean, big: boolean)
				local rel = position - origin
				local x, y = rel:Dot(right), rel:Dot(forward)
				local distance = math.sqrt(x * x + y * y)
				local onRim = false
				if distance > RANGE then
					if not clampToRim then
						return
					end
					x, y = x / distance * RANGE, y / distance * RANGE
					onRim = true
				end
				used += 1
				local d = dot(used)
				d.Visible = true
				d.BackgroundColor3 = color
				d.BackgroundTransparency = if onRim then 0.45 else 0
				d.Size = if big then UDim2.fromOffset(11, 11) else UDim2.fromOffset(8, 8)
				d.Position = UDim2.new(0.5, x / RANGE * radiusPx, 0.5, -y / RANGE * radiusPx)
			end

			local enemies = workspace:FindFirstChild("Enemies")
			if enemies then
				local count = 0
				for _, model in ipairs(enemies:GetChildren()) do
					if count >= ENEMY_LIMIT then
						break
					end
					if model:IsA("Model") and model:GetAttribute("State") ~= "Dead" then
						count += 1
						local isRed = model:GetAttribute("Kind") == "Red"
						local pivot = model.PrimaryPart and model.PrimaryPart.Position or model:GetPivot().Position
						plot(pivot, if isRed then Kit.Colors.Red else Kit.Colors.White, isRed, isRed)
					end
				end
			end
			for _, userId in ipairs(state.Party) do
				local other = Players:GetPlayerByUserId(userId)
				if other and other ~= Players.LocalPlayer then
					local otherChar = other.Character
					local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
					if otherRoot and otherRoot:IsA("BasePart") then
						plot(otherRoot.Position, Kit.Colors.Green, true, false)
					end
				end
			end
		end
		for i = used + 1, #pool do
			pool[i].Visible = false
		end
	end

	return { Frame = frame, Update = update }
end

return Radar
