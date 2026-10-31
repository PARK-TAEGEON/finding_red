--!strict
-- Tiny UI construction kit for C's HUD/Lobby/Mobile (no images: Frames, UICorner, UIStroke, text). Owner: C.
local Kit = {}

Kit.Colors = {
	Ink = Color3.fromRGB(30, 32, 40),
	Panel = Color3.fromRGB(28, 34, 52),
	PanelLight = Color3.fromRGB(46, 56, 84),
	White = Color3.fromRGB(255, 255, 255),
	Gold = Color3.fromRGB(255, 205, 50),
	Red = Color3.fromRGB(235, 55, 55),
	RedDark = Color3.fromRGB(150, 25, 30),
	Green = Color3.fromRGB(80, 210, 100),
	GreenDark = Color3.fromRGB(35, 120, 60),
	Blue = Color3.fromRGB(70, 150, 255),
	Gray = Color3.fromRGB(150, 155, 165),
	Board = Color3.fromRGB(38, 78, 58),
	Wood = Color3.fromRGB(130, 85, 45),
	Chalk = Color3.fromRGB(245, 245, 230),
}

Kit.Title = Enum.Font.FredokaOne
Kit.Body = Enum.Font.GothamBold

function Kit.apply(inst: Instance, props: { [string]: any }?)
	if props then
		for key, value in pairs(props) do
			(inst :: any)[key] = value
		end
	end
end

function Kit.corner(parent: Instance, radius: UDim?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 12)
	c.Parent = parent
	return c
end

function Kit.round(parent: Instance): UICorner
	return Kit.corner(parent, UDim.new(1, 0))
end

function Kit.stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Kit.Colors.Ink
	s.Thickness = thickness or 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Kit.textStroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Kit.Colors.Ink
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

function Kit.gui(name: string, order: number, parent: Instance): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.DisplayOrder = order
	g.Parent = parent
	return g
end

function Kit.frame(parent: Instance, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Kit.Colors.Panel
	Kit.apply(f, props)
	f.Parent = parent
	return f
end

function Kit.label(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Text = text
	l.Font = Kit.Body
	l.TextColor3 = Kit.Colors.White
	l.TextScaled = true
	l.Size = UDim2.fromScale(1, 1)
	Kit.apply(l, props)
	l.Parent = parent
	return l
end

function Kit.button(parent: Instance, text: string, props: { [string]: any }?): TextButton
	local b = Instance.new("TextButton")
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Text = text
	b.Font = Kit.Title
	b.TextColor3 = Kit.Colors.White
	b.TextScaled = true
	b.BackgroundColor3 = Kit.Colors.Blue
	Kit.apply(b, props)
	b.Parent = parent
	return b
end

function Kit.padding(parent: Instance, px: number): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
	return p
end

function Kit.list(parent: Instance, horizontal: boolean, gap: number, align: Enum.HorizontalAlignment?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, gap)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = align or Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Parent = parent
	return l
end

function Kit.clear(parent: Instance, keepClass: { string }?)
	for _, child in ipairs(parent:GetChildren()) do
		if not (keepClass and table.find(keepClass, child.ClassName)) then
			child:Destroy()
		end
	end
end

function Kit.formatTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local keyColors: { [string]: Color3 } = {
	Red = Color3.fromRGB(235, 55, 55),
	Blue = Color3.fromRGB(70, 150, 255),
	Yellow = Color3.fromRGB(255, 210, 40),
	Green = Color3.fromRGB(80, 210, 100),
	Purple = Color3.fromRGB(170, 90, 230),
	Orange = Color3.fromRGB(255, 150, 40),
	White = Color3.fromRGB(240, 240, 240),
}

-- Key colors may be names ("Red"), BrickColor names or "#RRGGBB".
function Kit.keyColor(name: string): Color3
	if keyColors[name] then
		return keyColors[name]
	end
	if string.sub(name, 1, 1) == "#" then
		local ok, c = pcall(Color3.fromHex, name)
		if ok then
			return c
		end
	end
	local ok, color = pcall(function(): Color3
		return ((BrickColor.new :: any)(name) :: BrickColor).Color
	end)
	if ok then
		return color
	end
	return Kit.Colors.Gray
end

return Kit
