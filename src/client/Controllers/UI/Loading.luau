--!strict
-- Full-screen loading overlay between stages (CONTRACT §1.12.4). Owner: C.
-- "Loading..." + progress bar + a code-drawn scene (our Red and two Whites resting on a bench,
-- blocky Frames only, no images) + one random tip. Covers the map build and teleport.
local TweenService = game:GetService("TweenService")

local Kit = require(script.Parent.Kit)

export type Loading = {
	Show: (minSeconds: number) -> (),
	Finish: () -> (),
	IsShown: () -> boolean,
}

local Loading = {}

local TIPS = {
	"레드만 잡으세요! 화이트를 잡으면 깔끔 도장을 놓쳐요",
	"화이트는 방망이로 밀어내면 벌점이 없어요",
	"레이더의 빨간 점이 레드예요",
	"기준 시간 안에 깨면 빠름 도장을 받아요",
	"쓰러진 동료 옆에서 E를 길게 누르면 살릴 수 있어요",
	"시작 방 바닥의 무기를 챙기고 문을 여세요",
	"레드는 걷는 것보다 느려요. 뒤로 빠지며 쏘세요",
	"높은 곳의 레드는 저격총으로 노려 보세요",
	"도장은 판마다 따로 모여요. 하나씩 채워 보세요",
}

local C = Kit.Colors
local BG = Color3.fromRGB(18, 22, 34)
local WHITE_BODY = Color3.fromRGB(236, 238, 244)
local WHITE_LEG = Color3.fromRGB(196, 200, 212)
local VISOR = Color3.fromRGB(24, 26, 32)
local EYE = Color3.fromRGB(255, 226, 40)

local function block(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, z: number): Frame
	local f = Kit.frame(parent, {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = color,
		ZIndex = z,
	})
	Kit.corner(f, UDim.new(0, 4))
	return f
end

type Figure = { Head: Frame, BaseY: number }

-- A seated blocky figure, front view, centred at cx. The seat top is at y = 140.
local function figure(parent: Instance, cx: number, red: boolean): Figure
	local body = if red then C.Red else WHITE_BODY
	local leg = if red then C.RedDark else WHITE_LEG
	local z = 4
	block(parent, cx - 22 - 13, 92, 12, 42, body, z) -- left arm
	block(parent, cx + 22 + 1, 92, 12, 42, body, z) -- right arm
	block(parent, cx - 22, 88, 44, 54, body, z) -- torso
	block(parent, cx - 19, 140, 17, 50, leg, z + 1) -- legs hanging over the seat
	block(parent, cx + 2, 140, 17, 50, leg, z + 1)
	block(parent, cx - 21, 186, 21, 9, C.Ink, z + 2) -- shoes
	block(parent, cx + 1, 186, 21, 9, C.Ink, z + 2)
	local headY = 42
	local head = block(parent, cx - 23, headY, 46, 42, body, z + 1)
	if red then
		-- little horns, yellow eyes, a row of teeth
		for _, hx in ipairs({ 6, 30 }) do
			Kit.frame(head, {
				Position = UDim2.fromOffset(hx, -6),
				Size = UDim2.fromOffset(10, 10),
				Rotation = 45,
				BackgroundColor3 = C.RedDark,
				ZIndex = z,
			})
		end
		for _, ex in ipairs({ 9, 27 }) do
			local eye = Kit.frame(head, {
				Position = UDim2.fromOffset(ex, 11),
				Size = UDim2.fromOffset(10, 10),
				BackgroundColor3 = EYE,
				ZIndex = z + 2,
			})
			Kit.round(eye)
		end
		local mouth = Kit.frame(head, {
			Position = UDim2.fromOffset(10, 27),
			Size = UDim2.fromOffset(26, 8),
			BackgroundColor3 = C.White,
			ZIndex = z + 2,
		})
		for i = 1, 3 do
			Kit.frame(mouth, {
				Position = UDim2.fromOffset(i * 6.5 - 1, 0),
				Size = UDim2.fromOffset(2, 8),
				BackgroundColor3 = C.RedDark,
				ZIndex = z + 3,
			})
		end
	else
		local visor = Kit.frame(head, {
			Position = UDim2.fromOffset(5, 13),
			Size = UDim2.fromOffset(36, 13),
			BackgroundColor3 = VISOR,
			ZIndex = z + 2,
		})
		Kit.corner(visor, UDim.new(0, 5))
		Kit.frame(visor, {
			Position = UDim2.fromOffset(5, 3),
			Size = UDim2.fromOffset(10, 3),
			BackgroundColor3 = Color3.fromRGB(110, 120, 140),
			ZIndex = z + 3,
		})
	end
	return { Head = head, BaseY = headY }
end

function Loading.new(parent: Instance): Loading
	local gui = Kit.gui("FindingRedLoading", 50, parent)
	local root = Instance.new("CanvasGroup")
	root.Name = "Loading"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = BG
	root.BorderSizePixel = 0
	root.Visible = false
	root.Active = true -- swallow clicks while covering the screen
	root.Parent = gui

	local content = Kit.frame(root, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(480, 380),
		BackgroundTransparency = 1,
	})
	local scale = Instance.new("UIScale")
	scale.Parent = content

	-- scene: ground, bench, three figures
	local scene = Kit.frame(content, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(440, 210),
		BackgroundTransparency = 1,
	})
	block(scene, 0, 200, 440, 6, Color3.fromRGB(60, 68, 88), 1) -- ground
	block(scene, 50, 70, 340, 12, C.Wood, 2) -- backrest
	block(scene, 70, 82, 10, 58, C.Wood, 2) -- backrest posts
	block(scene, 360, 82, 10, 58, C.Wood, 2)
	block(scene, 40, 136, 360, 14, Color3.fromRGB(150, 100, 55), 3) -- seat
	block(scene, 62, 150, 12, 50, C.Wood, 2) -- legs
	block(scene, 366, 150, 12, 50, C.Wood, 2)
	local figures = {
		figure(scene, 120, false),
		figure(scene, 220, true),
		figure(scene, 320, false),
	}

	local title = Kit.label(content, "Loading...", {
		Position = UDim2.fromOffset(20, 222),
		Size = UDim2.new(1, -40, 0, 46),
		Font = Kit.Title,
		TextColor3 = C.White,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Kit.textStroke(title, C.Ink, 2)
	local track = Kit.frame(content, {
		Position = UDim2.fromOffset(20, 276),
		Size = UDim2.new(1, -40, 0, 20),
		BackgroundColor3 = Color3.fromRGB(44, 52, 72),
	})
	Kit.round(track)
	Kit.stroke(track, C.White, 2)
	local fill = Kit.frame(track, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Red })
	Kit.round(fill)
	local tip = Kit.label(content, "", {
		Position = UDim2.fromOffset(20, 312),
		Size = UDim2.new(1, -40, 0, 30),
		TextColor3 = C.Chalk,
	})

	local shown = false
	local finishing = false
	local token = 0
	local shownAt = 0
	local minShow = 1.5
	local tweens: { Tween } = {}

	local function stopTweens()
		for _, t in ipairs(tweens) do
			t:Cancel()
		end
		tweens = {}
	end

	local function play(inst: Instance, info: TweenInfo, goal: { [string]: any }): Tween
		local t = TweenService:Create(inst, info, goal)
		table.insert(tweens, t)
		t:Play()
		return t
	end

	local function fit()
		local camera = workspace.CurrentCamera
		if camera then
			local vp = camera.ViewportSize
			scale.Scale = math.clamp(math.min(vp.X / 540, vp.Y / 430), 0.5, 1.3)
		end
	end

	local finish: () -> ()

	local function show(minSeconds: number)
		if shown and not finishing then
			return
		end
		token += 1
		local myToken = token
		shown, finishing = true, false
		shownAt = os.clock()
		minShow = math.max(0.2, minSeconds)
		stopTweens()
		fit()
		tip.Text = TIPS[math.random(1, #TIPS)]
		title.Text = "Loading..."
		fill.Size = UDim2.fromScale(0, 1)
		root.GroupTransparency = 1
		root.Visible = true
		play(root, TweenInfo.new(0.12), { GroupTransparency = 0 })
		-- bar creeps to 90 % over the minimum time; Finish completes it
		play(fill, TweenInfo.new(minShow, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(0.9, 1),
		})
		-- figures bob, a little out of step
		for i, f in ipairs(figures) do
			f.Head.Position = UDim2.fromOffset(f.Head.Position.X.Offset, f.BaseY)
			play(
				f.Head,
				TweenInfo.new(0.45 + i * 0.07, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, i * 0.12),
				{ Position = UDim2.fromOffset(f.Head.Position.X.Offset, f.BaseY - 4) }
			)
		end
		-- "Loading", "Loading.", ... and a safety timeout
		task.spawn(function()
			local dots = 0
			while token == myToken and shown do
				dots = (dots + 1) % 4
				title.Text = "Loading" .. string.rep(".", dots)
				task.wait(0.3)
				if os.clock() - shownAt > 15 and token == myToken and not finishing then
					finish()
				end
			end
		end)
	end

	finish = function()
		if not shown or finishing then
			return
		end
		finishing = true
		local myToken = token
		task.spawn(function()
			local remaining = minShow - (os.clock() - shownAt)
			if remaining > 0 then
				task.wait(remaining)
			end
			if token ~= myToken then
				return
			end
			TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(1, 1) }):Play()
			task.wait(0.2)
			if token ~= myToken then
				return
			end
			TweenService:Create(root, TweenInfo.new(0.3), { GroupTransparency = 1 }):Play()
			task.wait(0.32)
			if token ~= myToken then
				return
			end
			stopTweens()
			root.Visible = false
			shown, finishing = false, false
		end)
	end

	return {
		Show = show,
		Finish = finish,
		IsShown = function()
			return shown and not finishing
		end,
	}
end

return Loading
