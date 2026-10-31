--!strict
-- Pause menu (CONTRACT §1.6): 계속하기 / 회전 감도 / 로비로. Owner: C.
local UserInputService = game:GetService("UserInputService")

local Kit = require(script.Parent.Kit)

export type PauseMenu = {
	Open: () -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
	SetSensitivity: (value: number) -> (),
}

export type Callbacks = {
	OnClose: () -> (),
	OnSensitivity: (value: number, final: boolean) -> (),
	OnLobbyInfo: () -> (),
}

local PauseMenu = {}

local MIN, MAX = 0.2, 3

function PauseMenu.new(parent: Instance, callbacks: Callbacks): PauseMenu
	local root = Kit.button(parent, "", {
		Name = "Pause",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		AutoButtonColor = false,
		Modal = true, -- frees the mouse while open
		Visible = false,
		ZIndex = 40,
	})
	local panel = Kit.frame(root, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 330),
		BackgroundColor3 = Kit.Colors.Panel,
		ZIndex = 41,
	})
	Kit.corner(panel, UDim.new(0, 20))
	Kit.stroke(panel, Kit.Colors.White, 4)
	local title = Kit.label(panel, "일시정지", {
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(1, -40, 0, 48),
		Font = Kit.Title,
		ZIndex = 42,
	})
	Kit.textStroke(title, Kit.Colors.Ink, 2)

	local resume = Kit.button(panel, "계속하기", {
		Position = UDim2.fromOffset(40, 76),
		Size = UDim2.new(1, -80, 0, 56),
		BackgroundColor3 = Kit.Colors.Green,
		ZIndex = 42,
	})
	Kit.corner(resume, UDim.new(0, 14))
	Kit.stroke(resume, Kit.Colors.Ink, 3)
	Kit.padding(resume, 10)

	local sensLabel = Kit.label(panel, "회전 감도 1.0", {
		Position = UDim2.fromOffset(40, 144),
		Size = UDim2.new(1, -80, 0, 26),
		ZIndex = 42,
	})
	local track = Kit.frame(panel, {
		Position = UDim2.fromOffset(52, 184),
		Size = UDim2.new(1, -104, 0, 14),
		BackgroundColor3 = Kit.Colors.PanelLight,
		Active = true,
		ZIndex = 42,
	})
	Kit.round(track)
	Kit.stroke(track, Kit.Colors.Ink, 2)
	local fill = Kit.frame(track, {
		Size = UDim2.fromScale(0.5, 1),
		BackgroundColor3 = Kit.Colors.Blue,
		ZIndex = 43,
	})
	Kit.round(fill)
	local knob = Kit.frame(track, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = Kit.Colors.White,
		ZIndex = 44,
	})
	Kit.round(knob)
	Kit.stroke(knob, Kit.Colors.Ink, 3)

	local lobby = Kit.button(panel, "로비로", {
		Position = UDim2.fromOffset(40, 228),
		Size = UDim2.new(1, -80, 0, 48),
		BackgroundColor3 = Kit.Colors.PanelLight,
		ZIndex = 42,
	})
	Kit.corner(lobby, UDim.new(0, 14))
	Kit.stroke(lobby, Kit.Colors.Ink, 3)
	Kit.padding(lobby, 10)
	Kit.label(panel, "로비로 가려면 결과 화면에서 '로비로'에 투표하세요", {
		Position = UDim2.fromOffset(20, 288),
		Size = UDim2.new(1, -40, 0, 20),
		TextColor3 = Kit.Colors.Gray,
		ZIndex = 42,
	})

	local value = 1
	local dragging: InputObject? = nil

	local function render()
		local alpha = (value - MIN) / (MAX - MIN)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		sensLabel.Text = string.format("회전 감도 %.1f", value)
	end

	local function setFromX(x: number, final: boolean)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		value = math.floor((MIN + alpha * (MAX - MIN)) * 10 + 0.5) / 10
		render()
		callbacks.OnSensitivity(value, final)
	end

	local function beginDrag(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = input
			setFromX(input.Position.X, false)
		end
	end
	track.InputBegan:Connect(beginDrag)
	knob.InputBegan:Connect(beginDrag)
	UserInputService.InputChanged:Connect(function(input)
		local d = dragging
		if not d then
			return
		end
		if
			(d.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)
			or rawequal(input, d)
		then
			setFromX(input.Position.X, false)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local d = dragging
		if d and (rawequal(input, d) or input.UserInputType == d.UserInputType) then
			dragging = nil
			setFromX(input.Position.X, true)
		end
	end)

	local function close()
		if root.Visible then
			root.Visible = false
			dragging = nil
			callbacks.OnClose()
		end
	end
	resume.Activated:Connect(close)
	lobby.Activated:Connect(callbacks.OnLobbyInfo)

	render()
	return {
		Open = function()
			root.Visible = true
		end,
		Close = close,
		IsOpen = function()
			return root.Visible
		end,
		SetSensitivity = function(v: number)
			if dragging then
				return
			end
			value = math.clamp(v, MIN, MAX)
			render()
		end,
	}
end

return PauseMenu
