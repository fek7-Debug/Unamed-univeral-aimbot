--[[
	=====================================================================
	MOBILE HUB MENU — Standalone Luau UI Template + Static-Cache ESP Engine
	Built 100% programmatically with Instance.new + Drawing API.
	Designed for Roblox mobile executors (Delta / Android touch).
	Layout uses UDim2.fromScale — no offset sizing on UI.
	ESP rendering is 100% cached (Drawing.new) — zero GC pressure per frame.
	Refactor: True 3D Bounding Box → 2D Projection (adaptive to R6/R15 scale).
	Addition: Team Check tab, Name/Studs ESP, conditional team notification.
	PATCH: Background Team Sync thread — spectator / dynamic team safety.
	Addition: Aimbot (Smooth/Lock-on) + FOV Circle (cached Drawing.new).
	Addition: Aimbot Wallcheck (cached RaycastParams — 0 per-frame GC).
	Addition: Player tab — Universal WalkSpeed / JumpPower / InfJump / Noclip.
	=====================================================================
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

-- =====================================================================
-- GLOBAL CONFIG
-- =====================================================================
_G.UIConfig = {
	MenuOpen = true,
	ActiveTab = "Combat",
	MenuSize = UDim2.fromScale(0.86, 0.66),
	MenuPosition = UDim2.fromScale(0.5, 0.5),
	FABPosition = UDim2.fromScale(0.87, 0.74),
	Toggles = {},
	Sliders = {},
	Actions = {},
	Dropdowns = {},
	Theme = {
		Background = Color3.fromRGB(24, 26, 32),
		Sidebar = Color3.fromRGB(18, 20, 24),
		Panel = Color3.fromRGB(28, 31, 38),
		Row = Color3.fromRGB(33, 37, 45),
		Accent = Color3.fromRGB(0, 200, 255),
		AccentDeep = Color3.fromRGB(0, 120, 170),
		Text = Color3.fromRGB(236, 241, 246),
		SubText = Color3.fromRGB(138, 148, 164),
		Stroke = Color3.fromRGB(58, 64, 78),
		ToggleOff = Color3.fromRGB(62, 68, 82),
		ToggleOn = Color3.fromRGB(0, 200, 255),
	},
}

local Theme = _G.UIConfig.Theme

-- =====================================================================
-- CLEANUP PREVIOUS INSTANCE
-- =====================================================================
local previousGui = PlayerGui:FindFirstChild("MobileHubUI")
if previousGui then previousGui:Destroy() end
local previousESP = PlayerGui:FindFirstChild("MobileHubESPRef")
if previousESP then previousESP:Destroy() end

-- =====================================================================
-- INSTANCE HELPERS
-- =====================================================================
local function create(className, properties, parent)
	local instance = Instance.new(className)
	for property, value in pairs(properties) do
		instance[property] = value
	end
	instance.Parent = parent
	return instance
end

local function addCorner(parent, radiusScale)
	return create("UICorner", { CornerRadius = UDim.new(radiusScale, 0) }, parent)
end

local function addStroke(parent, color, thickness, transparency)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, parent)
end

local function addGradient(parent, topColor, bottomColor, rotation)
	return create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, topColor),
			ColorSequenceKeypoint.new(1, bottomColor),
		}),
		Rotation = rotation or 90,
	}, parent)
end

local function addText(parent, properties)
	local merged = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextColor3 = Theme.Text,
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
	}
	for key, value in pairs(properties) do
		merged[key] = value
	end
	local maxSize = merged.MaxTextSize or 20
	local minSize = merged.MinTextSize or 8
	merged.MaxTextSize = nil
	merged.MinTextSize = nil
	local label = create("TextLabel", merged, parent)
	create("UITextSizeConstraint", {
		MaxTextSize = maxSize,
		MinTextSize = minSize,
	}, label)
	return label
end

local layoutCounter = 0
local function nextLayoutOrder()
	layoutCounter = layoutCounter + 1
	return layoutCounter
end

-- =====================================================================
-- TOUCH TRACKING (for Aimbot activation)
-- =====================================================================
local activeTouchCount = 0
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.UserInputType == Enum.UserInputType.Touch then
		activeTouchCount = activeTouchCount + 1
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		activeTouchCount = activeTouchCount + 1
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		activeTouchCount = math.max(0, activeTouchCount - 1)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		activeTouchCount = math.max(0, activeTouchCount - 1)
	end
end)

-- =====================================================================
-- AIMBOT WALLCHECK — STATIC RAYCAST PARAMS
-- =====================================================================
local aimbotRaycastParams = RaycastParams.new()
aimbotRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
aimbotRaycastParams.IgnoreWater = true
aimbotRaycastParams.FilterDescendantsInstances = { Camera }

local lastLocalCharacter = nil

-- =====================================================================
-- PLAYER MODULES — CONFIGURATION STATE
-- =====================================================================
local PlayerState = {
	WalkSpeedEnabled = false,
	WalkSpeedValue = 16,
	JumpPowerEnabled = false,
	JumpPowerValue = 50,
	InfiniteJumpEnabled = false,
	NoclipEnabled = false,
}
_G.UIConfig.PlayerState = PlayerState

-- =====================================================================
-- ROOT SCREEN GUI
-- =====================================================================
local screenGui = create("ScreenGui", {
	Name = "MobileHubUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 999,
}, PlayerGui)

-- =====================================================================
-- MAIN WINDOW FRAME
-- =====================================================================
local mainFrame = create("Frame", {
	Name = "MainFrame",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = _G.UIConfig.MenuPosition,
	Size = _G.UIConfig.MenuSize,
	BackgroundColor3 = Theme.Background,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Visible = true,
	ZIndex = 5,
}, screenGui)
addCorner(mainFrame, 0.045)
addGradient(mainFrame, Color3.new(1, 1, 1), Color3.fromRGB(196, 202, 214), 90)
addStroke(mainFrame, Theme.Stroke, 1.5, 0.35)

-- =====================================================================
-- WINDOW OPEN / CLOSE
-- =====================================================================
local menuOpen = true

local function openMenu()
	if menuOpen then return end
	menuOpen = true
	_G.UIConfig.MenuOpen = true
	mainFrame.Visible = true
	mainFrame.Size = UDim2.fromScale(0, 0)
	TweenService:Create(mainFrame,
		TweenInfo.new(0.32, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = _G.UIConfig.MenuSize }):Play()
end

local function closeMenu()
	if not menuOpen then return end
	menuOpen = false
	_G.UIConfig.MenuOpen = false
	local t = TweenService:Create(mainFrame,
		TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
		{ Size = UDim2.fromScale(0, 0) })
	t:Play()
	t.Completed:Once(function()
		if not menuOpen then mainFrame.Visible = false end
	end)
end

local function toggleMenu()
	if menuOpen then closeMenu() else openMenu() end
end

_G.UIConfig.OpenMenu = openMenu
_G.UIConfig.CloseMenu = closeMenu
_G.UIConfig.ToggleMenu = toggleMenu

-- =====================================================================
-- TOP BAR
-- =====================================================================
local topBar = create("Frame", {
	Name = "TopBar",
	Size = UDim2.fromScale(1, 0.13),
	Position = UDim2.fromScale(0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 6,
}, mainFrame)

local accentDot = create("Frame", {
	Name = "AccentDot",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0.035, 0.5),
	Size = UDim2.fromScale(0.012, 0.34),
	BackgroundColor3 = Theme.Accent,
	BorderSizePixel = 0,
	ZIndex = 7,
}, topBar)
create("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, accentDot)
addCorner(accentDot, 1)
addStroke(accentDot, Theme.Accent, 1, 0.2)

addText(topBar, {
	Name = "Title",
	Text = "MOBILE HUB",
	Font = Enum.Font.GothamBold,
	TextColor3 = Theme.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.fromScale(0.5, 0.55),
	Position = UDim2.fromScale(0.065, 0.22),
	MaxTextSize = 22, MinTextSize = 10,
	ZIndex = 7,
})

addText(topBar, {
	Name = "Subtitle",
	Text = "touch interface template",
	Font = Enum.Font.Gotham,
	TextColor3 = Theme.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.fromScale(0.5, 0.3),
	Position = UDim2.fromScale(0.065, 0.62),
	MaxTextSize = 12, MinTextSize = 7,
	ZIndex = 7,
})

local closeButton = create("TextButton", {
	Name = "CloseButton",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(0.955, 0.5),
	Size = UDim2.fromScale(0.05, 0.55),
	BackgroundColor3 = Color3.fromRGB(38, 42, 52),
	BorderSizePixel = 0,
	Text = "X",
	Font = Enum.Font.GothamBold,
	TextColor3 = Theme.SubText,
	TextScaled = true,
	AutoButtonColor = false,
	ZIndex = 8,
}, topBar)
create("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, closeButton)
create("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 8 }, closeButton)
addCorner(closeButton, 0.28)
local closeStroke = addStroke(closeButton, Theme.Stroke, 1, 0.4)

closeButton.Activated:Connect(function() closeMenu() end)
closeButton.MouseEnter:Connect(function()
	TweenService:Create(closeButton, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(200, 60, 70) }):Play()
	TweenService:Create(closeStroke, TweenInfo.new(0.15), { Color = Color3.fromRGB(255, 110, 120), Transparency = 0.1 }):Play()
end)
closeButton.MouseLeave:Connect(function()
	TweenService:Create(closeButton, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(38, 42, 52) }):Play()
	TweenService:Create(closeStroke, TweenInfo.new(0.15), { Color = Theme.Stroke, Transparency = 0.4 }):Play()
end)

local topDivider = create("Frame", {
	Name = "TopDivider",
	Size = UDim2.fromScale(1, 0.004),
	Position = UDim2.fromScale(0, 0.13),
	BackgroundColor3 = Theme.Stroke,
	BorderSizePixel = 0,
	ZIndex = 6,
}, mainFrame)
addGradient(topDivider, Color3.fromRGB(90, 98, 116), Color3.fromRGB(40, 44, 54), 0)

-- =====================================================================
-- SIDEBAR
-- =====================================================================
local sidebar = create("Frame", {
	Name = "Sidebar",
	Size = UDim2.fromScale(0.22, 0.87),
	Position = UDim2.fromScale(0, 0.13),
	BackgroundColor3 = Theme.Sidebar,
	BorderSizePixel = 0,
	ZIndex = 6,
}, mainFrame)
addGradient(sidebar, Color3.new(1, 1, 1), Color3.fromRGB(180, 186, 198), 90)

create("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.022, 0),
}, sidebar)

create("UIPadding", {
	PaddingTop = UDim.new(0.04, 0),
	PaddingBottom = UDim.new(0.04, 0),
	PaddingLeft = UDim.new(0.02, 0),
	PaddingRight = UDim.new(0.02, 0),
}, sidebar)

create("Frame", {
	Name = "SidebarDivider",
	Size = UDim2.fromScale(0.003, 0.87),
	Position = UDim2.fromScale(0.22, 0.13),
	BackgroundColor3 = Theme.Stroke,
	BorderSizePixel = 0,
	ZIndex = 6,
}, mainFrame)

-- =====================================================================
-- CONTENT HOLDER
-- =====================================================================
local contentHolder = create("Frame", {
	Name = "ContentHolder",
	Size = UDim2.fromScale(0.78, 0.87),
	Position = UDim2.fromScale(0.22, 0.13),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 6,
}, mainFrame)

-- =====================================================================
-- TABS (now includes "Player")
-- =====================================================================
local tabNames = { "Combat", "Visuals", "Player", "Team Check", "Settings" }
local tabData = {}

for index, tabName in ipairs(tabNames) do
	local scroll = create("ScrollingFrame", {
		Name = tabName .. "Panel",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Accent,
		ScrollBarImageTransparency = 0.25,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		Visible = false,
		ZIndex = 6,
	}, contentHolder)

	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.018, 0),
	}, scroll)

	create("UIPadding", {
		PaddingTop = UDim.new(0.025, 0),
		PaddingBottom = UDim.new(0.03, 0),
		PaddingLeft = UDim.new(0.01, 0),
		PaddingRight = UDim.new(0.01, 0),
	}, scroll)

	tabData[tabName] = { Frame = scroll, Button = nil, Stroke = nil, Order = index }
end

for index, tabName in ipairs(tabNames) do
	local button = create("TextButton", {
		Name = tabName .. "NavButton",
		Size = UDim2.fromScale(0.84, 0.11),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Text = tabName,
		Font = Enum.Font.GothamMedium,
		TextColor3 = Theme.SubText,
		TextScaled = true,
		AutoButtonColor = false,
		LayoutOrder = index,
		ZIndex = 7,
	}, sidebar)
	create("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 9 }, button)
	addCorner(button, 0.24)
	local buttonStroke = addStroke(button, Theme.Stroke, 1, 0.6)
	addGradient(button, Color3.new(1, 1, 1), Color3.fromRGB(198, 204, 216), 90)

	tabData[tabName].Button = button
	tabData[tabName].Stroke = buttonStroke

	button.Activated:Connect(function()
		if _G.UIConfig.ActiveTab == tabName then return end
		_G.UIConfig.ActiveTab = tabName
		for otherName, otherData in pairs(tabData) do
			local isActive = (otherName == tabName)
			otherData.Frame.Visible = isActive
			TweenService:Create(otherData.Button, TweenInfo.new(0.22), {
				BackgroundColor3 = isActive and Theme.Accent or Theme.Panel,
				TextColor3 = isActive and Color3.fromRGB(8, 14, 20) or Theme.SubText,
			}):Play()
			TweenService:Create(otherData.Stroke, TweenInfo.new(0.22), {
				Color = isActive and Theme.Accent or Theme.Stroke,
				Transparency = isActive and 0 or 0.6,
			}):Play()
		end
	end)
end

local function selectTab(tabName)
	local target = tabData[tabName]
	if not target then return end
	_G.UIConfig.ActiveTab = tabName
	for otherName, otherData in pairs(tabData) do
		local isActive = (otherName == tabName)
		otherData.Frame.Visible = isActive
		TweenService:Create(otherData.Button, TweenInfo.new(0.22), {
			BackgroundColor3 = isActive and Theme.Accent or Theme.Panel,
			TextColor3 = isActive and Color3.fromRGB(8, 14, 20) or Theme.SubText,
		}):Play()
		TweenService:Create(otherData.Stroke, TweenInfo.new(0.22), {
			Color = isActive and Theme.Accent or Theme.Stroke,
			Transparency = isActive and 0 or 0.6,
		}):Play()
	end
end

-- =====================================================================
-- SECTION HEADER
-- =====================================================================
local function createSectionHeader(parent, headerText)
	local holder = create("Frame", {
		Name = "Header_" .. headerText,
		Size = UDim2.fromScale(0.94, 0.07),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = nextLayoutOrder(),
		ZIndex = 7,
	}, parent)

	local bar = create("Frame", {
		Name = "AccentBar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(0.008, 0.52),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 8,
	}, holder)
	create("UIAspectRatioConstraint", { AspectRatio = 0.22, DominantAxis = Enum.DominantAxis.Height }, bar)
	addCorner(bar, 1)

	addText(holder, {
		Name = "HeaderLabel",
		Text = headerText,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(0.94, 1),
		Position = UDim2.fromScale(0.028, 0),
		MaxTextSize = 14, MinTextSize = 8,
		ZIndex = 8,
	})
	return holder
end

-- =====================================================================
-- TEAM CHECK — BACKGROUND SYNC
-- =====================================================================
local TeamState = {
	Valid = false,
	MyTeam = nil,
	TeammateSet = {},
}

local function localPlayerHasTeammate()
	local myTeam = LocalPlayer.Team
	if not myTeam then return false end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer and p.Team == myTeam then
			return true
		end
	end
	return false
end

task.spawn(function()
	while true do
		task.wait(1.5)

		local myTeam = LocalPlayer.Team
		local newSet = {}
		local valid = false

		if myTeam ~= nil then
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= LocalPlayer and p.Team ~= nil and p.Team == myTeam then
					newSet[p.UserId] = true
					valid = true
				end
			end
		end

		TeamState.MyTeam = myTeam
		TeamState.TeammateSet = newSet
		TeamState.Valid = valid
	end
end)

-- =====================================================================
-- TEAM CHECK — NOTIFICATION
-- =====================================================================
local function showTeamNotification(success)
	local message = success and "Team Check Active" or "not team found"
	local accentColor = success and Color3.fromRGB(0, 220, 100) or Color3.fromRGB(255, 60, 60)

	local notif = create("Frame", {
		Name = "TeamNotification",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.12),
		Size = UDim2.fromScale(0.58, 0.075),
		BackgroundColor3 = Color3.fromRGB(20, 22, 28),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 250,
	}, screenGui)
	addCorner(notif, 0.5)
	local notifStroke = addStroke(notif, accentColor, 1.5, 1)
	addGradient(notif, Color3.new(1, 1, 1), Color3.fromRGB(200, 205, 215), 90)

	local indicator = create("Frame", {
		Name = "Indicator",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.045, 0.5),
		Size = UDim2.fromScale(0.022, 0.4),
		BackgroundColor3 = accentColor,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 251,
	}, notif)
	create("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, indicator)
	addCorner(indicator, 1)
	local indStroke = addStroke(indicator, accentColor, 1, 1)

	local notifText = addText(notif, {
		Name = "NotifText",
		Text = message,
		Font = Enum.Font.GothamBold,
		TextColor3 = accentColor,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(0.9, 1),
		Position = UDim2.fromScale(0.085, 0),
		MaxTextSize = 20, MinTextSize = 10,
		TextTransparency = 1,
		ZIndex = 251,
	})

	TweenService:Create(notif, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.05,
	}):Play()
	TweenService:Create(notifStroke, TweenInfo.new(0.3), { Transparency = 0.2 }):Play()
	TweenService:Create(indicator, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()
	TweenService:Create(indStroke, TweenInfo.new(0.3), { Transparency = 0.1 }):Play()
	TweenService:Create(notifText, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()

	task.delay(2.0, function()
		if not notif or not notif.Parent then return end
		TweenService:Create(notif, TweenInfo.new(0.65, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(notifStroke, TweenInfo.new(0.65), { Transparency = 1 }):Play()
		TweenService:Create(indicator, TweenInfo.new(0.65), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(indStroke, TweenInfo.new(0.65), { Transparency = 1 }):Play()
		TweenService:Create(notifText, TweenInfo.new(0.65), { TextTransparency = 1 }):Play()

		task.delay(0.75, function()
			if notif and notif.Parent then notif:Destroy() end
		end)
	end)
end

-- =====================================================================
-- TOGGLE WIDGET
-- =====================================================================
local function createToggle(parent, config)
	local toggleName = config.Name or "Toggle"
	local callback = config.Callback or function() end
	local state = config.Default == true

	local row = create("Frame", {
		Name = toggleName .. "_ToggleRow",
		Size = UDim2.fromScale(0.94, 0.155),
		BackgroundColor3 = Theme.Row,
		BorderSizePixel = 0,
		LayoutOrder = nextLayoutOrder(),
		ZIndex = 7,
	}, parent)
	addCorner(row, 0.2)
	addGradient(row, Color3.new(1, 1, 1), Color3.fromRGB(198, 204, 216), 90)
	addStroke(row, Theme.Stroke, 1, 0.55)

	local label = addText(row, {
		Name = "Label",
		Text = toggleName,
		Font = Enum.Font.GothamMedium,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(0.62, 1),
		Position = UDim2.fromScale(0.05, 0),
		MaxTextSize = 19, MinTextSize = 9,
		ZIndex = 8,
	})

	local track = create("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.955, 0.5),
		Size = UDim2.fromScale(0.13, 0.5),
		BackgroundColor3 = state and Theme.ToggleOn or Theme.ToggleOff,
		BorderSizePixel = 0,
		ZIndex = 8,
	}, row)
	create("UIAspectRatioConstraint", { AspectRatio = 1.9, DominantAxis = Enum.DominantAxis.Height }, track)
	addCorner(track, 1)
	local trackStroke = addStroke(track, Theme.Stroke, 1, 0.5)

	local knob = create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = state and UDim2.fromScale(0.76, 0.5) or UDim2.fromScale(0.24, 0.5),
		Size = UDim2.fromScale(0.3, 0.78),
		BackgroundColor3 = Color3.fromRGB(242, 246, 250),
		BorderSizePixel = 0,
		ZIndex = 9,
	}, track)
	create("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, knob)
	addCorner(knob, 1)
	addGradient(knob, Color3.new(1, 1, 1), Color3.fromRGB(190, 198, 210), 90)
	addStroke(knob, Color3.fromRGB(255, 255, 255), 1, 0.4)

	local hitbox = create("TextButton", {
		Name = "Hitbox",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 12,
	}, row)

	local function setToggleState(newState, fireCallback)
		state = newState == true
		TweenService:Create(knob, TweenInfo.new(0.18), {
			Position = state and UDim2.fromScale(0.76, 0.5) or UDim2.fromScale(0.24, 0.5),
		}):Play()
		TweenService:Create(track, TweenInfo.new(0.18), {
			BackgroundColor3 = state and Theme.ToggleOn or Theme.ToggleOff,
		}):Play()
		TweenService:Create(trackStroke, TweenInfo.new(0.18), {
			Color = state and Theme.Accent or Theme.Stroke,
			Transparency = state and 0.15 or 0.5,
		}):Play()
		TweenService:Create(label, TweenInfo.new(0.18), {
			TextColor3 = state and Theme.Text or Theme.SubText,
		}):Play()
		if fireCallback then callback(state) end
	end

	hitbox.Activated:Connect(function() setToggleState(not state, true) end)
	setToggleState(state, false)

	_G.UIConfig.Toggles[toggleName] = {
		Set = function(v) setToggleState(v, false) end,
		Get = function() return state end,
		Frame = row,
	}
	return row
end

-- =====================================================================
-- SLIDER WIDGET
-- =====================================================================
local function createSlider(parent, config)
	local sliderName = config.Name or "Slider"
	local minValue = config.Min or 0
	local maxValue = config.Max or 100
	local suffix = config.Suffix or ""
	local value = config.Default or minValue
	local decimals = config.Decimals or 0
	local callback = config.Callback or function() end

	local function formatValue(v)
		if decimals > 0 then
			return string.format("%." .. decimals .. "f", v) .. suffix
		end
		return tostring(math.floor(v + 0.5)) .. suffix
	end

	local row = create("Frame", {
		Name = sliderName .. "_SliderRow",
		Size = UDim2.fromScale(0.94, 0.21),
		BackgroundColor3 = Theme.Row,
		BorderSizePixel = 0,
		LayoutOrder = nextLayoutOrder(),
		ZIndex = 7,
	}, parent)
	addCorner(row, 0.15)
	addGradient(row, Color3.new(1, 1, 1), Color3.fromRGB(198, 204, 216), 90)
	addStroke(row, Theme.Stroke, 1, 0.55)

	addText(row, {
		Name = "Label",
		Text = sliderName,
		Font = Enum.Font.GothamMedium,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(0.6, 0.34),
		Position = UDim2.fromScale(0.05, 0.09),
		MaxTextSize = 19, MinTextSize = 9,
		ZIndex = 8,
	})

	local valueLabel = addText(row, {
		Name = "ValueLabel",
		Text = formatValue(value),
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromScale(0.3, 0.34),
		Position = UDim2.fromScale(0.65, 0.09),
		MaxTextSize = 19, MinTextSize = 9,
		ZIndex = 8,
	})

	local bar = create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.68),
		Size = UDim2.fromScale(0.9, 0.13),
		BackgroundColor3 = Color3.fromRGB(15, 17, 21),
		BorderSizePixel = 0,
		ZIndex = 8,
	}, row)
	addCorner(bar, 1)
	addStroke(bar, Theme.Stroke, 1, 0.55)

	local fill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 9,
	}, bar)
	addCorner(fill, 1)
	addGradient(fill, Color3.new(1, 1, 1), Color3.fromRGB(180, 214, 255), 0)

	local knob = create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(0.12, 2.2),
		BackgroundColor3 = Color3.fromRGB(244, 248, 252),
		BorderSizePixel = 0,
		ZIndex = 10,
	}, bar)
	create("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, knob)
	addCorner(knob, 1)
	addGradient(knob, Color3.new(1, 1, 1), Color3.fromRGB(196, 204, 216), 90)
	addStroke(knob, Theme.Accent, 1.4, 0.15)

	local hitbox = create("TextButton", {
		Name = "SliderHitbox",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.68),
		Size = UDim2.fromScale(0.98, 0.46),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 14,
	}, row)

	local dragging = false

	local function applyPercent(percent)
		local p = math.clamp(percent, 0, 1)
		value = minValue + ((maxValue - minValue) * p)
		fill.Size = UDim2.fromScale(p, 1)
		knob.Position = UDim2.fromScale(p, 0.5)
		valueLabel.Text = formatValue(value)
	end

	local function setValueFromScreenX(screenX)
		local absX = bar.AbsolutePosition.X
		local absW = bar.AbsoluteSize.X
		if absW <= 0 then return end
		applyPercent((screenX - absX) / absW)
	end

	local function roundedValue(v)
		if decimals > 0 then
			local mult = 10 ^ decimals
			return math.floor(v * mult + 0.5) / mult
		end
		return math.floor(v + 0.5)
	end

	local function setValueDirect(newValue, fireCallback)
		local clamped = math.clamp(newValue, minValue, maxValue)
		local percent = (maxValue ~= minValue) and ((clamped - minValue) / (maxValue - minValue)) or 0
		applyPercent(percent)
		if fireCallback then callback(roundedValue(clamped)) end
	end

	hitbox.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			setValueFromScreenX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
			setValueFromScreenX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			callback(roundedValue(value))
		end
	end)

	setValueDirect(value, false)

	_G.UIConfig.Sliders[sliderName] = {
		Set = function(v) setValueDirect(v, false) end,
		Get = function() return roundedValue(value) end,
		Frame = row,
	}
	return row
end

-- =====================================================================
-- ACTION BUTTON WIDGET
-- =====================================================================
local function createActionButton(parent, config)
	local actionName = config.Name or "Action"
	local callback = config.Callback or function() end

	local button = create("TextButton", {
		Name = actionName .. "_ActionButton",
		Size = UDim2.fromScale(0.94, 0.14),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Text = actionName,
		Font = Enum.Font.GothamMedium,
		TextColor3 = Theme.Accent,
		TextScaled = true,
		AutoButtonColor = false,
		LayoutOrder = nextLayoutOrder(),
		ZIndex = 7,
	}, parent)
	create("UITextSizeConstraint", { MaxTextSize = 19, MinTextSize = 9 }, button)
	addCorner(button, 0.22)
	addGradient(button, Color3.new(1, 1, 1), Color3.fromRGB(198, 204, 216), 90)
	local actionStroke = addStroke(button, Theme.Accent, 1, 0.55)

	button.Activated:Connect(function()
		callback()
		TweenService:Create(button, TweenInfo.new(0.12), {
			BackgroundColor3 = Theme.Accent,
			TextColor3 = Color3.fromRGB(8, 14, 20),
		}):Play()
		task.delay(0.16, function()
			TweenService:Create(button, TweenInfo.new(0.2), {
				BackgroundColor3 = Theme.Panel,
				TextColor3 = Theme.Accent,
			}):Play()
		end)
	end)

	button.MouseEnter:Connect(function()
		TweenService:Create(actionStroke, TweenInfo.new(0.15), { Transparency = 0.1 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(actionStroke, TweenInfo.new(0.15), { Transparency = 0.55 }):Play()
	end)

	_G.UIConfig.Actions[actionName] = { Fire = callback, Frame = button }
	return button
end

-- =====================================================================
-- DROPDOWN WIDGET
-- =====================================================================
local function createDropdown(parent, config)
	local dropdownName = config.Name or "Dropdown"
	local options = config.Options or { "Default" }
	local defaultOption = config.Default or options[1]
	local callback = config.Callback or function() end
	local selected = defaultOption
	local expanded = false

	local collapsedHeight = 0.14
	local optionHeight = 0.09
	local optionCount = math.max(#options, 1)
	local expandedHeight = collapsedHeight + optionCount * optionHeight
	local headerRatio = collapsedHeight / expandedHeight

	local holder = create("Frame", {
		Name = dropdownName .. "_DropdownHolder",
		Size = UDim2.fromScale(0.94, collapsedHeight),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = nextLayoutOrder(),
		ZIndex = 7,
	}, parent)

	local header = create("TextButton", {
		Name = "Header",
		Size = UDim2.new(1, 0, headerRatio, 0),
		Position = UDim2.fromScale(0, 0),
		BackgroundColor3 = Theme.Row,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 8,
	}, holder)
	addCorner(header, 0.22)
	addGradient(header, Color3.new(1, 1, 1), Color3.fromRGB(198, 204, 216), 90)
	local headerStroke = addStroke(header, Theme.Stroke, 1, 0.55)

	addText(header, {
		Name = "Label",
		Text = dropdownName,
		Font = Enum.Font.GothamMedium,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(0.6, 1),
		Position = UDim2.fromScale(0.05, 0),
		MaxTextSize = 19, MinTextSize = 9,
		ZIndex = 9,
	})

	local valueLabel = addText(header, {
		Name = "ValueLabel",
		Text = tostring(selected),
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromScale(0.4, 1),
		Position = UDim2.fromScale(0.55, 0),
		MaxTextSize = 17, MinTextSize = 9,
		ZIndex = 9,
	})

	local arrow = addText(header, {
		Name = "Arrow",
		Text = "▼",
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromScale(0.05, 1),
		Position = UDim2.fromScale(0.9, 0),
		MaxTextSize = 12, MinTextSize = 7,
		ZIndex = 9,
	})

	local listContainer = create("Frame", {
		Name = "List",
		Size = UDim2.new(1, 0, 1 - headerRatio, 0),
		Position = UDim2.new(0, 0, headerRatio, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 8,
	}, holder)

	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.008, 0),
	}, listContainer)

	local optionButtons = {}
	for i, optName in ipairs(options) do
		local optBtn = create("TextButton", {
			Name = "Opt_" .. tostring(optName),
			Size = UDim2.new(1, 0, 1 / optionCount, 0),
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			Text = tostring(optName),
			Font = Enum.Font.GothamMedium,
			TextColor3 = Theme.SubText,
			TextScaled = true,
			AutoButtonColor = false,
			LayoutOrder = i,
			ZIndex = 9,
		}, listContainer)
		create("UITextSizeConstraint", { MaxTextSize = 16, MinTextSize = 8 }, optBtn)
		addCorner(optBtn, 0.28)
		local optStroke = addStroke(optBtn, Theme.Stroke, 1, 0.6)

		optBtn.Activated:Connect(function()
			selected = optName
			valueLabel.Text = tostring(selected)
			callback(selected)
			expanded = false
			TweenService:Create(holder, TweenInfo.new(0.22, Enum.EasingStyle.Quart), {
				Size = UDim2.fromScale(0.94, collapsedHeight)
			}):Play()
			TweenService:Create(arrow, TweenInfo.new(0.2), { Rotation = 0 }):Play()
			for _, btn in ipairs(optionButtons) do
				TweenService:Create(btn, TweenInfo.new(0.15), {
					BackgroundColor3 = Theme.Panel,
					TextColor3 = Theme.SubText,
				}):Play()
			end
			TweenService:Create(optBtn, TweenInfo.new(0.15), {
				BackgroundColor3 = Theme.Accent,
				TextColor3 = Color3.fromRGB(8, 14, 20),
			}):Play()
			TweenService:Create(optStroke, TweenInfo.new(0.15), {
				Color = Theme.Accent, Transparency = 0.1
			}):Play()
		end)

		optionButtons[i] = optBtn
	end

	header.Activated:Connect(function()
		expanded = not expanded
		local targetSize = expanded and UDim2.fromScale(0.94, expandedHeight) or UDim2.fromScale(0.94, collapsedHeight)
		TweenService:Create(holder, TweenInfo.new(0.24, Enum.EasingStyle.Quart), { Size = targetSize }):Play()
		TweenService:Create(arrow, TweenInfo.new(0.2), { Rotation = expanded and 180 or 0 }):Play()
		TweenService:Create(headerStroke, TweenInfo.new(0.2), {
			Color = expanded and Theme.Accent or Theme.Stroke,
			Transparency = expanded and 0.1 or 0.55,
		}):Play()
	end)

	for i, btn in ipairs(optionButtons) do
		if options[i] == selected then
			btn.BackgroundColor3 = Theme.Accent
			btn.TextColor3 = Color3.fromRGB(8, 14, 20)
		end
	end

	_G.UIConfig.Dropdowns[dropdownName] = {
		Get = function() return selected end,
		Set = function(v)
			selected = v
			valueLabel.Text = tostring(v)
			callback(v)
		end,
		Frame = holder,
	}
	return holder
end

-- =====================================================================
-- COLOR MAP (shared by ESP and Aimbot)
-- =====================================================================
local COLOR_MAP = {
	["Blanco"]   = Color3.fromRGB(255, 255, 255),
	["Rojo"]     = Color3.fromRGB(255, 60, 60),
	["Verde"]    = Color3.fromRGB(0, 255, 100),
	["Azul"]     = Color3.fromRGB(60, 120, 255),
	["Amarillo"] = Color3.fromRGB(255, 220, 60),
	["Cian"]     = Color3.fromRGB(0, 220, 255),
	["Magenta"]  = Color3.fromRGB(255, 60, 200),
}

-- =====================================================================
-- ESP ENGINE — STATIC CACHED DRAWING OBJECTS
-- =====================================================================
local ESP = {
	MasterEnabled = false,
	BoxEnabled = false,
	TracerEnabled = false,
	HealthEnabled = false,
	PointerEnabled = false,
	SkeletonEnabled = false,
	NameEnabled = false,
	StudsEnabled = false,
	Thickness = 1.0,
	BoxOffset = Vector2.new(0, 0),
	TracerOffset = Vector2.new(0, 0),
	BoxColor = Color3.fromRGB(255, 255, 255),
	TracerColor = Color3.fromRGB(255, 255, 255),
	PointerColor = Color3.fromRGB(255, 60, 60),
	NameColor = Color3.fromRGB(255, 255, 255),
	StudsColor = Color3.fromRGB(255, 220, 60),
	TracerOrigin = "Abajo",
	BoxWidthMultiplier = 0.55,
	TeamCheckBoxHealth = false,
	TeamCheckTracer = false,
	TeamCheckPointer = false,
	TeamCheckNames = false,
	Cache = {},
}
_G.UIConfig.ESP = ESP

-- =====================================================================
-- AIMBOT — CONFIGURATION STATE
-- =====================================================================
local Aimbot = {
	Enabled = false,
	TeamCheck = false,
	Wallcheck = false,
	ShowFOV = false,
	Smoothness = 15,
	FOVRadius = 150,
	TargetPart = "Head",
	FOVColor = Color3.fromRGB(0, 220, 255),
	Active = false,
	CurrentTargetName = nil,
}
_G.UIConfig.Aimbot = Aimbot

-- ESP reference ScreenGui
local espScreenGui = create("ScreenGui", {
	Name = "MobileHubESPRef",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = -100,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

local espScreenFrame = create("Frame", {
	Name = "RefFrame",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, espScreenGui)

-- =====================================================================
-- AIMBOT — FOV CIRCLE (STATIC CACHED — ZERO GC)
-- =====================================================================
local fovCircle = Drawing.new("Circle")
fovCircle.Visible = false
fovCircle.Filled = false
fovCircle.Thickness = 1
fovCircle.Color = Aimbot.FOVColor
fovCircle.Transparency = 1
fovCircle.NumSides = 64
fovCircle.Radius = Aimbot.FOVRadius
fovCircle.Position = Vector2.new(0, 0)
fovCircle.ZIndex = 5

-- Bone maps
local BONE_MAP_R15 = {
	{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}
local BONE_MAP_R6 = {
	{ "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
	{ "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}
local MAX_SKELETON_LINES = 14

local BB_CORNER_SIGNS = {
	Vector3.new(-1, -1, -1), Vector3.new(-1, -1,  1),
	Vector3.new(-1,  1, -1), Vector3.new(-1,  1,  1),
	Vector3.new( 1, -1, -1), Vector3.new( 1, -1,  1),
	Vector3.new( 1,  1, -1), Vector3.new( 1,  1,  1),
}

local function createStaticPlayerCache(player)
	local cache = {
		Player = player,
		Box = Drawing.new("Square"),
		Tracer = Drawing.new("Line"),
		HealthBg = Drawing.new("Square"),
		HealthFill = Drawing.new("Square"),
		Pointer = Drawing.new("Triangle"),
		NameText = Drawing.new("Text"),
		StudsText = Drawing.new("Text"),
		SkeletonLines = {},
	}

	cache.Box.Visible = false
	cache.Box.Filled = false
	cache.Box.Transparency = 1
	cache.Box.Thickness = 1
	cache.Box.Color = Color3.new(1, 1, 1)
	cache.Box.ZIndex = 2

	cache.Tracer.Visible = false
	cache.Tracer.Thickness = 1
	cache.Tracer.Color = Color3.new(1, 1, 1)
	cache.Tracer.Transparency = 1
	cache.Tracer.ZIndex = 2

	cache.HealthBg.Visible = false
	cache.HealthBg.Filled = true
	cache.HealthBg.Color = Color3.fromRGB(15, 15, 15)
	cache.HealthBg.Transparency = 0.35
	cache.HealthBg.ZIndex = 2

	cache.HealthFill.Visible = false
	cache.HealthFill.Filled = true
	cache.HealthFill.Color = Color3.fromRGB(0, 255, 100)
	cache.HealthFill.Transparency = 0.1
	cache.HealthFill.ZIndex = 3

	cache.Pointer.Visible = false
	cache.Pointer.Filled = true
	cache.Pointer.Color = Color3.fromRGB(255, 60, 60)
	cache.Pointer.Transparency = 0.1
	cache.Pointer.Thickness = 1
	cache.Pointer.ZIndex = 4

	cache.NameText.Visible = false
	cache.NameText.Center = true
	cache.NameText.Outline = true
	cache.NameText.OutlineColor = Color3.new(0, 0, 0)
	cache.NameText.Font = 2
	cache.NameText.Size = 14
	cache.NameText.Color = Color3.new(1, 1, 1)
	cache.NameText.Transparency = 1
	cache.NameText.ZIndex = 5

	cache.StudsText.Visible = false
	cache.StudsText.Center = true
	cache.StudsText.Outline = true
	cache.StudsText.OutlineColor = Color3.new(0, 0, 0)
	cache.StudsText.Font = 2
	cache.StudsText.Size = 13
	cache.StudsText.Color = Color3.fromRGB(255, 220, 60)
	cache.StudsText.Transparency = 1
	cache.StudsText.ZIndex = 5

	for i = 1, MAX_SKELETON_LINES do
		local line = Drawing.new("Line")
		line.Visible = false
		line.Thickness = 1
		line.Color = Color3.new(1, 1, 1)
		line.Transparency = 1
		line.ZIndex = 2
		cache.SkeletonLines[i] = line
	end

	return cache
end

local function hideCache(cache)
	cache.Box.Visible = false
	cache.Tracer.Visible = false
	cache.HealthBg.Visible = false
	cache.HealthFill.Visible = false
	cache.Pointer.Visible = false
	cache.NameText.Visible = false
	cache.StudsText.Visible = false
	for _, line in ipairs(cache.SkeletonLines) do
		line.Visible = false
	end
end

local function destroyCache(cache)
	pcall(function() cache.Box:Remove() end)
	pcall(function() cache.Tracer:Remove() end)
	pcall(function() cache.HealthBg:Remove() end)
	pcall(function() cache.HealthFill:Remove() end)
	pcall(function() cache.Pointer:Remove() end)
	pcall(function() cache.NameText:Remove() end)
	pcall(function() cache.StudsText:Remove() end)
	for _, line in ipairs(cache.SkeletonLines) do
		pcall(function() line:Remove() end)
	end
end

local function registerPlayer(player)
	if ESP.Cache[player] then return end
	ESP.Cache[player] = createStaticPlayerCache(player)
end

local function unregisterPlayer(player)
	local cache = ESP.Cache[player]
	if cache then
		destroyCache(cache)
		ESP.Cache[player] = nil
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	registerPlayer(player)
end
Players.PlayerAdded:Connect(registerPlayer)
Players.PlayerRemoving:Connect(unregisterPlayer)

-- Helpers
local function getBonePosition(character, boneName)
	local part = character:FindFirstChild(boneName)
	if part then return part.Position end
	return nil
end

local function worldToScreenVec(worldPos)
	local screenPos, onScreen = Camera:WorldToViewportPoint(worldPos)
	return Vector2.new(screenPos.X, screenPos.Y), (onScreen and screenPos.Z > 0), screenPos.Z
end

-- =====================================================================
-- PLAYER MODULES — UNIVERSAL MOVEMENT ENGINE
-- =====================================================================

-- ---- Continuous applier for WalkSpeed & JumpPower (games may reset them) ----
task.spawn(function()
	while true do
		task.wait(0.15)
		local char = LocalPlayer.Character
		if char then
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				if PlayerState.WalkSpeedEnabled then
					humanoid.WalkSpeed = PlayerState.WalkSpeedValue
				end
				if PlayerState.JumpPowerEnabled then
					humanoid.UseJumpPower = true
					humanoid.JumpPower = PlayerState.JumpPowerValue
				end
			end
		end
	end
end)

-- ---- Infinite Jump (touch / keyboard / gamepad unified via JumpRequest) ----
UserInputService.JumpRequest:Connect(function()
	if not PlayerState.InfiniteJumpEnabled then return end
	local char = LocalPlayer.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if humanoid and hrp and humanoid.Health > 0 then
		-- Force state transition so it works even in air
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		-- Vertical boost keeps momentum consistent on mobile
		local jumpPower = PlayerState.JumpPowerEnabled and PlayerState.JumpPowerValue
			or (humanoid.UseJumpPower and humanoid.JumpPower or 50)
		hrp.Velocity = Vector3.new(
			hrp.Velocity.X,
			math.max(hrp.Velocity.Y, jumpPower),
			hrp.Velocity.Z
		)
	end
end)

-- ---- Universal Noclip (Stepped loop — physical step, safe & efficient) ----
RunService.Stepped:Connect(function()
	if not PlayerState.NoclipEnabled then return end
	local char = LocalPlayer.Character
	if not char then return end
	for _, desc in ipairs(char:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CanCollide = false
		end
	end
end)

-- ---- Auto re-apply on respawn (CharacterAdded) ----
LocalPlayer.CharacterAdded:Connect(function(char)
	local humanoid = char:WaitForChild("Humanoid", 5)
	if humanoid then
		if PlayerState.WalkSpeedEnabled then
			humanoid.WalkSpeed = PlayerState.WalkSpeedValue
		end
		if PlayerState.JumpPowerEnabled then
			humanoid.UseJumpPower = true
			humanoid.JumpPower = PlayerState.JumpPowerValue
		end
	end
end)

-- =====================================================================
-- ESP RENDER LOOP (RenderStepped)
-- =====================================================================
RunService.RenderStepped:Connect(function()
	local masterOn = ESP.MasterEnabled
	local boxOn = ESP.BoxEnabled
	local tracerOn = ESP.TracerEnabled
	local healthOn = ESP.HealthEnabled
	local pointerOn = ESP.PointerEnabled
	local skeletonOn = ESP.SkeletonEnabled
	local nameOn = ESP.NameEnabled
	local studsOn = ESP.StudsEnabled
	local thickness = ESP.Thickness
	local boxOffX, boxOffY = ESP.BoxOffset.X, ESP.BoxOffset.Y
	local tracerOffX, tracerOffY = ESP.TracerOffset.X, ESP.TracerOffset.Y
	local boxColor = ESP.BoxColor
	local tracerColor = ESP.TracerColor
	local pointerColor = ESP.PointerColor
	local nameColor = ESP.NameColor
	local studsColor = ESP.StudsColor
	local boxWidthMul = ESP.BoxWidthMultiplier
	local tracerOriginMode = ESP.TracerOrigin

	local tcBoxHealth = ESP.TeamCheckBoxHealth
	local tcTracer = ESP.TeamCheckTracer
	local tcPointer = ESP.TeamCheckPointer
	local tcNames = ESP.TeamCheckNames
	local teamFilterSafe = TeamState.Valid
	local teammateSet = TeamState.TeammateSet

	if not masterOn then
		for _, cache in pairs(ESP.Cache) do
			hideCache(cache)
		end
		return
	end

	local screenSize = espScreenFrame.AbsoluteSize
	if screenSize.X <= 0 or screenSize.Y <= 0 then
		screenSize = Camera.ViewportSize
	end
	local screenCenter = Vector2.new(screenSize.X * 0.5, screenSize.Y * 0.5)

	local tracerOriginBase
	if tracerOriginMode == "Arriba" then
		tracerOriginBase = Vector2.new(screenSize.X * 0.5, 0)
	elseif tracerOriginMode == "Centro" then
		tracerOriginBase = Vector2.new(screenSize.X * 0.5, screenSize.Y * 0.5)
	else
		tracerOriginBase = Vector2.new(screenSize.X * 0.5, screenSize.Y)
	end
	local tracerOrigin = Vector2.new(
		tracerOriginBase.X + tracerOffX,
		tracerOriginBase.Y + tracerOffY
	)

	local myChar = LocalPlayer.Character
	local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")

	local baseFontName = math.clamp(math.floor(13 * (0.6 + thickness * 0.4) + 0.5), 8, 48)
	local baseFontStuds = math.clamp(math.floor(12 * (0.6 + thickness * 0.4) + 0.5), 8, 48)

	for player, cache in pairs(ESP.Cache) do
		if player == LocalPlayer then
			hideCache(cache)
		else
			local character = player.Character
			local head = character and character:FindFirstChild("Head")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local hrp = character and character:FindFirstChild("HumanoidRootPart")

			if not character or not head or not humanoid or not hrp or humanoid.Health <= 0 then
				hideCache(cache)
			else
				local isSameTeam = false
				if teamFilterSafe and teammateSet[player.UserId] then
					isSameTeam = true
				end
				local hideBoxForTeam = isSameTeam and tcBoxHealth
				local hideTracerForTeam = isSameTeam and tcTracer
				local hidePointerForTeam = isSameTeam and tcPointer
				local hideNamesForTeam = isSameTeam and tcNames

				local bbCFrame, bbSize = character:GetBoundingBox()
				local halfX = bbSize.X * 0.5
				local halfY = bbSize.Y * 0.5
				local halfZ = bbSize.Z * 0.5

				local minX, minY = math.huge, math.huge
				local maxX, maxY = -math.huge, -math.huge
				local anyVisible = false

				for i = 1, 8 do
					local s = BB_CORNER_SIGNS[i]
					local worldCorner = (bbCFrame * CFrame.new(
						s.X * halfX, s.Y * halfY, s.Z * halfZ
					)).Position
					local sp, onScreen = Camera:WorldToViewportPoint(worldCorner)
					if onScreen and sp.Z > 0 then
						anyVisible = true
						if sp.X < minX then minX = sp.X end
						if sp.Y < minY then minY = sp.Y end
						if sp.X > maxX then maxX = sp.X end
						if sp.Y > maxY then maxY = sp.Y end
					end
				end

				local headVec, headVisible = worldToScreenVec(head.Position + Vector3.new(0, 0.5, 0))

				if anyVisible then
					local rawW = maxX - minX
					local rawH = maxY - minY

					local boxW = rawW * boxWidthMul
					local boxH = rawH
					local centerX = (minX + maxX) * 0.5
					local boxX = centerX - (boxW * 0.5) + boxOffX
					local boxY = minY + boxOffY

					if boxOn and not hideBoxForTeam then
						cache.Box.Visible = true
						cache.Box.Position = Vector2.new(boxX, boxY)
						cache.Box.Size = Vector2.new(boxW, boxH)
						cache.Box.Color = boxColor
						cache.Box.Thickness = thickness
						cache.Box.Transparency = 1
					else
						cache.Box.Visible = false
					end

					if tracerOn and not hideTracerForTeam then
						cache.Tracer.Visible = true
						cache.Tracer.From = tracerOrigin
						cache.Tracer.To = Vector2.new(centerX + boxOffX, boxY + boxH * 0.5)
						cache.Tracer.Color = tracerColor
						cache.Tracer.Thickness = thickness
						cache.Tracer.Transparency = 1
					else
						cache.Tracer.Visible = false
					end

					if healthOn and boxOn and not hideBoxForTeam then
						local pct = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
						local barWidth = math.max(2, boxW * 0.08 + thickness * 0.6)
						local barX = boxX - barWidth - 2
						local barY = boxY
						local barH = boxH

						cache.HealthBg.Visible = true
						cache.HealthBg.Position = Vector2.new(barX, barY)
						cache.HealthBg.Size = Vector2.new(barWidth, barH)
						cache.HealthBg.Color = Color3.fromRGB(20, 20, 20)

						cache.HealthFill.Visible = true
						cache.HealthFill.Position = Vector2.new(barX, barY + barH * (1 - pct))
						cache.HealthFill.Size = Vector2.new(barWidth, barH * pct)
						cache.HealthFill.Color = Color3.fromRGB(
							math.floor(255 * (1 - pct)),
							math.floor(255 * pct),
							60
						)
					else
						cache.HealthBg.Visible = false
						cache.HealthFill.Visible = false
					end

					if skeletonOn and not hideBoxForTeam then
						local rigType = humanoid.RigType
						local boneMap = (rigType == Enum.HumanoidRigType.R15) and BONE_MAP_R15 or BONE_MAP_R6
						for i, line in ipairs(cache.SkeletonLines) do
							local pair = boneMap[i]
							if pair then
								local p1 = getBonePosition(character, pair[1])
								local p2 = getBonePosition(character, pair[2])
								if p1 and p2 then
									local v1, vis1 = worldToScreenVec(p1)
									local v2, vis2 = worldToScreenVec(p2)
									if vis1 and vis2 then
										line.Visible = true
										line.From = v1
										line.To = v2
										line.Color = boxColor
										line.Thickness = thickness
									else
										line.Visible = false
									end
								else
									line.Visible = false
								end
							else
								line.Visible = false
							end
						end
					else
						for _, line in ipairs(cache.SkeletonLines) do
							line.Visible = false
						end
					end

					local showName = nameOn and not hideNamesForTeam
					local showStuds = studsOn and not hideNamesForTeam
					if showName or showStuds then
						local nameAnchorY = boxY - (baseFontName * 0.9) - 2
						local nameAnchorX = boxX + boxW * 0.5

						if showName then
							cache.NameText.Visible = true
							cache.NameText.Text = player.Name
							cache.NameText.Position = Vector2.new(nameAnchorX, nameAnchorY)
							cache.NameText.Color = nameColor
							cache.NameText.Size = baseFontName
							cache.NameText.Transparency = 1
						else
							cache.NameText.Visible = false
						end

						if showStuds then
							local studsY
							if showName then
								studsY = nameAnchorY - (baseFontStuds * 0.9) - 2
							else
								studsY = nameAnchorY
							end
							local dist = 0
							if myHRP then
								dist = (myHRP.Position - hrp.Position).Magnitude
							end
							cache.StudsText.Visible = true
							cache.StudsText.Text = string.format("[%d st]", math.floor(dist + 0.5))
							cache.StudsText.Position = Vector2.new(nameAnchorX, studsY)
							cache.StudsText.Color = studsColor
							cache.StudsText.Size = baseFontStuds
							cache.StudsText.Transparency = 1
						else
							cache.StudsText.Visible = false
						end
					else
						cache.NameText.Visible = false
						cache.StudsText.Visible = false
					end
				else
					cache.Box.Visible = false
					cache.Tracer.Visible = false
					cache.HealthBg.Visible = false
					cache.HealthFill.Visible = false
					cache.NameText.Visible = false
					cache.StudsText.Visible = false
					for _, line in ipairs(cache.SkeletonLines) do
						line.Visible = false
					end
				end

				if pointerOn and not hidePointerForTeam then
					local isWithin = anyVisible and headVisible
						and headVec.X >= 0 and headVec.X <= screenSize.X
						and headVec.Y >= 0 and headVec.Y <= screenSize.Y
					if not isWithin then
						local targetScreen
						if headVisible then
							targetScreen = headVec
						else
							targetScreen = Vector2.new(screenSize.X - headVec.X, screenSize.Y - headVec.Y)
						end

						local dir = targetScreen - screenCenter
						if dir.Magnitude < 1e-3 then dir = Vector2.new(0, 1) end
						dir = dir.Unit

						local margin = 42
						local halfW = (screenSize.X * 0.5) - margin
						local halfH = (screenSize.Y * 0.5) - margin
						local tX = halfW / math.max(math.abs(dir.X), 1e-6)
						local tY = halfH / math.max(math.abs(dir.Y), 1e-6)
						local t = math.min(tX, tY)
						local edgePos = screenCenter + dir * t

						local pointerSize = 14 + thickness * 2
						local perp = Vector2.new(-dir.Y, dir.X)
						local tip = edgePos + dir * (pointerSize * 1.1)
						local pA = edgePos + perp * (pointerSize * 0.55)
						local pB = edgePos - perp * (pointerSize * 0.55)

						cache.Pointer.Visible = true
						cache.Pointer.PointA = tip
						cache.Pointer.PointB = pA
						cache.Pointer.PointC = pB
						cache.Pointer.Color = pointerColor
						cache.Pointer.Thickness = thickness
						cache.Pointer.Transparency = 0.15
					else
						cache.Pointer.Visible = false
					end
				else
					cache.Pointer.Visible = false
				end
			end
		end
	end
end)

-- =====================================================================
-- AIMBOT RENDER LOOP (RenderStepped) — FOV + camera + Wallcheck
-- =====================================================================
RunService.RenderStepped:Connect(function()
	local enabled = Aimbot.Enabled
	local showFov = Aimbot.ShowFOV
	local fovRadius = Aimbot.FOVRadius
	local targetBone = Aimbot.TargetPart
	local smoothness = Aimbot.Smoothness
	local teamCheck = Aimbot.TeamCheck
	local wallcheck = Aimbot.Wallcheck
	local fovColor = Aimbot.FOVColor

	local vp = Camera.ViewportSize
	if showFov then
		fovCircle.Visible = true
		fovCircle.Position = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
		fovCircle.Radius = fovRadius
		fovCircle.Color = fovColor
		fovCircle.Thickness = 1
		fovCircle.Transparency = 1
		fovCircle.Filled = false
	else
		fovCircle.Visible = false
	end

	if not enabled then return end
	if activeTouchCount <= 0 then return end

	if wallcheck then
		local myChar = LocalPlayer.Character
		if myChar ~= lastLocalCharacter then
			lastLocalCharacter = myChar
			aimbotRaycastParams.FilterDescendantsInstances = { Camera, myChar }
		end
	end

	local screenCenter = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
	local closestDist = fovRadius
	local bestPart = nil

	local teamSafe = TeamState.Valid
	local teamSet = TeamState.TeammateSet

	local rayOrigin = Camera.CFrame.Position

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local char = player.Character
			if char then
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					local skip = false
					if teamCheck and teamSafe and teamSet[player.UserId] then
						skip = true
					end
					if not skip then
						local part = char:FindFirstChild(targetBone)
						if part then
							local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
							if onScreen and sp.Z > 0 then
								local dx = sp.X - screenCenter.X
								local dy = sp.Y - screenCenter.Y
								local dist = math.sqrt(dx * dx + dy * dy)
								if dist < closestDist then
									local wallBlocked = false
									if wallcheck then
										local dir = part.Position - rayOrigin
										local rayResult = workspace:Raycast(rayOrigin, dir, aimbotRaycastParams)
										if rayResult and not rayResult.Instance:IsDescendantOf(char) then
											wallBlocked = true
										end
									end
									if not wallBlocked then
										closestDist = dist
										bestPart = part
									end
								end
							end
						end
					end
				end
			end
		end
	end

	if bestPart then
		local camCF = Camera.CFrame
		local desiredCF = CFrame.lookAt(camCF.Position, bestPart.Position)
		local alpha = math.clamp(1 / smoothness, 0.033, 1)
		Camera.CFrame = camCF:Lerp(desiredCF, alpha)
	end
end)

-- =====================================================================
-- POPULATE : COMBAT TAB
-- =====================================================================
local combatPanel = tabData["Combat"].Frame

createSectionHeader(combatPanel, "COMBAT MODULES")
createToggle(combatPanel, {
	Name = "Enable Combat",
	Default = false,
	Callback = function(state) print("[Combat] Enable Combat ->", state) end,
})
createToggle(combatPanel, {
	Name = "Auto Attack",
	Default = false,
	Callback = function(state) print("[Combat] Auto Attack ->", state) end,
})

createSectionHeader(combatPanel, "TARGETING")
createSlider(combatPanel, {
	Name = "Attack Range",
	Min = 0, Max = 500, Default = 120, Suffix = " st",
	Callback = function(v) print("[Combat] Attack Range ->", v) end,
})

createSectionHeader(combatPanel, "AIMBOT MODULES")
createToggle(combatPanel, {
	Name = "Aimbot Enabled",
	Default = false,
	Callback = function(state) Aimbot.Enabled = state end,
})
createToggle(combatPanel, {
	Name = "Aimbot Team Check",
	Default = false,
	Callback = function(state) Aimbot.TeamCheck = state end,
})
createToggle(combatPanel, {
	Name = "Aimbot Wallcheck",
	Default = false,
	Callback = function(state) Aimbot.Wallcheck = state end,
})
createToggle(combatPanel, {
	Name = "Show FOV Circle",
	Default = false,
	Callback = function(state) Aimbot.ShowFOV = state end,
})

createSectionHeader(combatPanel, "AIMBOT TUNING")
createSlider(combatPanel, {
	Name = "Aimbot Smoothness",
	Min = 1, Max = 30, Default = 15, Decimals = 0,
	Callback = function(v) Aimbot.Smoothness = v end,
})
createSlider(combatPanel, {
	Name = "Aimbot FOV Radius",
	Min = 10, Max = 600, Default = 150, Decimals = 0,
	Callback = function(v) Aimbot.FOVRadius = v end,
})

createSectionHeader(combatPanel, "AIMBOT TARGETING")
createDropdown(combatPanel, {
	Name = "Aimbot Target Part",
	Options = { "Head", "HumanoidRootPart" },
	Default = "Head",
	Callback = function(part) Aimbot.TargetPart = part end,
})
createDropdown(combatPanel, {
	Name = "FOV Circle Color",
	Options = { "Blanco", "Rojo", "Verde", "Azul", "Amarillo", "Cian", "Magenta" },
	Default = "Cian",
	Callback = function(name) Aimbot.FOVColor = COLOR_MAP[name] or Color3.fromRGB(0, 220, 255) end,
})

-- =====================================================================
-- POPULATE : VISUALS TAB
-- =====================================================================
local visualsPanel = tabData["Visuals"].Frame

createSectionHeader(visualsPanel, "ESP MASTER")
createToggle(visualsPanel, {
	Name = "Master ESP",
	Default = false,
	Callback = function(state) ESP.MasterEnabled = state end,
})

createSectionHeader(visualsPanel, "ESP MODULES")
createToggle(visualsPanel, { Name = "Box ESP", Default = false, Callback = function(s) ESP.BoxEnabled = s end })
createToggle(visualsPanel, { Name = "Tracer ESP", Default = false, Callback = function(s) ESP.TracerEnabled = s end })
createToggle(visualsPanel, { Name = "Health ESP", Default = false, Callback = function(s) ESP.HealthEnabled = s end })
createToggle(visualsPanel, { Name = "Off-Screen Pointer", Default = false, Callback = function(s) ESP.PointerEnabled = s end })
createToggle(visualsPanel, { Name = "Skeleton ESP", Default = false, Callback = function(s) ESP.SkeletonEnabled = s end })
createToggle(visualsPanel, { Name = "Name ESP", Default = false, Callback = function(s) ESP.NameEnabled = s end })
createToggle(visualsPanel, { Name = "Studs ESP", Default = false, Callback = function(s) ESP.StudsEnabled = s end })

createSectionHeader(visualsPanel, "ESP STYLE")
createSlider(visualsPanel, {
	Name = "ESP Thickness",
	Min = 0.1, Max = 10.0, Default = 1.0, Decimals = 1,
	Callback = function(v) ESP.Thickness = v end,
})

createSectionHeader(visualsPanel, "VISUAL MODULES")
createToggle(visualsPanel, { Name = "Full Bright", Default = false, Callback = function(s) print("[Visuals] Full Bright ->", s) end })
createToggle(visualsPanel, { Name = "Player Highlights", Default = false, Callback = function(s) print("[Visuals] Player Highlights ->", s) end })

createSectionHeader(visualsPanel, "CAMERA")
createSlider(visualsPanel, {
	Name = "Field of View",
	Min = 40, Max = 120, Default = 70, Suffix = "°",
	Callback = function(v) print("[Visuals] Field of View ->", v) end,
})

-- =====================================================================
-- POPULATE : PLAYER TAB (NEW)
-- =====================================================================
local playerPanel = tabData["Player"].Frame

createSectionHeader(playerPanel, "UNIVERSAL MOVEMENT")

-- ---- WalkSpeed ----
createToggle(playerPanel, {
	Name = "WalkSpeed Hack",
	Default = false,
	Callback = function(state) PlayerState.WalkSpeedEnabled = state end,
})
createSlider(playerPanel, {
	Name = "WalkSpeed Value",
	Min = 16, Max = 250, Default = 16, Decimals = 0,
	Callback = function(v) PlayerState.WalkSpeedValue = v end,
})

-- ---- JumpPower ----
createToggle(playerPanel, {
	Name = "JumpPower Hack",
	Default = false,
	Callback = function(state) PlayerState.JumpPowerEnabled = state end,
})
createSlider(playerPanel, {
	Name = "JumpPower Value",
	Min = 50, Max = 300, Default = 50, Decimals = 0,
	Callback = function(v) PlayerState.JumpPowerValue = v end,
})

-- ---- Infinite Jump ----
createToggle(playerPanel, {
	Name = "Infinite Jump",
	Default = false,
	Callback = function(state) PlayerState.InfiniteJumpEnabled = state end,
})

-- ---- Noclip ----
createToggle(playerPanel, {
	Name = "Noclip",
	Default = false,
	Callback = function(state)
		PlayerState.NoclipEnabled = state
		-- On disable: restore normal collision on the character's parts
		if not state then
			local char = LocalPlayer.Character
			if char then
				for _, desc in ipairs(char:GetDescendants()) do
					if desc:IsA("BasePart") then
						desc.CanCollide = true
					end
				end
			end
		end
	end,
})

-- =====================================================================
-- POPULATE : TEAM CHECK TAB
-- =====================================================================
local teamCheckPanel = tabData["Team Check"].Frame

createSectionHeader(teamCheckPanel, "TEAM FILTER SETTINGS")

createToggle(teamCheckPanel, {
	Name = "Box & Health Team Check",
	Default = false,
	Callback = function(state)
		ESP.TeamCheckBoxHealth = state
		if state then showTeamNotification(localPlayerHasTeammate()) end
	end,
})
createToggle(teamCheckPanel, {
	Name = "Tracer Team Check",
	Default = false,
	Callback = function(state)
		ESP.TeamCheckTracer = state
		if state then showTeamNotification(localPlayerHasTeammate()) end
	end,
})
createToggle(teamCheckPanel, {
	Name = "Off-Screen Pointer Team Check",
	Default = false,
	Callback = function(state)
		ESP.TeamCheckPointer = state
		if state then showTeamNotification(localPlayerHasTeammate()) end
	end,
})
createToggle(teamCheckPanel, {
	Name = "Names & Studs Team Check",
	Default = false,
	Callback = function(state)
		ESP.TeamCheckNames = state
		if state then showTeamNotification(localPlayerHasTeammate()) end
	end,
})

-- =====================================================================
-- POPULATE : SETTINGS TAB
-- =====================================================================
local settingsPanel = tabData["Settings"].Frame

createSectionHeader(settingsPanel, "ESP POSITION OFFSETS")
createSlider(settingsPanel, {
	Name = "Box ESP Offset X", Min = -200, Max = 200, Default = 0,
	Callback = function(v) ESP.BoxOffset = Vector2.new(v, ESP.BoxOffset.Y) end,
})
createSlider(settingsPanel, {
	Name = "Box ESP Offset Y", Min = -200, Max = 200, Default = 0,
	Callback = function(v) ESP.BoxOffset = Vector2.new(ESP.BoxOffset.X, v) end,
})
createSlider(settingsPanel, {
	Name = "Tracer ESP Offset X", Min = -500, Max = 500, Default = 0,
	Callback = function(v) ESP.TracerOffset = Vector2.new(v, ESP.TracerOffset.Y) end,
})
createSlider(settingsPanel, {
	Name = "Tracer ESP Offset Y", Min = -500, Max = 500, Default = 0,
	Callback = function(v) ESP.TracerOffset = Vector2.new(ESP.TracerOffset.X, v) end,
})

createSectionHeader(settingsPanel, "ESP GEOMETRY CALIBRATION")
createDropdown(settingsPanel, {
	Name = "Tracer Origin Point",
	Options = { "Arriba", "Centro", "Abajo" },
	Default = "Abajo",
	Callback = function(option) ESP.TracerOrigin = option end,
})
createSlider(settingsPanel, {
	Name = "Box Width Multiplier",
	Min = 0.10, Max = 1.20, Default = 0.55, Decimals = 2,
	Callback = function(v) ESP.BoxWidthMultiplier = v end,
})

createSectionHeader(settingsPanel, "ESP COLOR SELECTORS")
local colorOptions = { "Blanco", "Rojo", "Verde", "Azul", "Amarillo", "Cian", "Magenta" }

createDropdown(settingsPanel, {
	Name = "Box ESP Color", Options = colorOptions, Default = "Blanco",
	Callback = function(name) ESP.BoxColor = COLOR_MAP[name] or Color3.new(1, 1, 1) end,
})
createDropdown(settingsPanel, {
	Name = "Tracer ESP Color", Options = colorOptions, Default = "Blanco",
	Callback = function(name) ESP.TracerColor = COLOR_MAP[name] or Color3.new(1, 1, 1) end,
})
createDropdown(settingsPanel, {
	Name = "Off-Screen Pointer Color", Options = colorOptions, Default = "Rojo",
	Callback = function(name) ESP.PointerColor = COLOR_MAP[name] or Color3.fromRGB(255, 60, 60) end,
})
createDropdown(settingsPanel, {
	Name = "Name ESP Color", Options = colorOptions, Default = "Blanco",
	Callback = function(name) ESP.NameColor = COLOR_MAP[name] or Color3.new(1, 1, 1) end,
})
createDropdown(settingsPanel, {
	Name = "Studs ESP Color", Options = colorOptions, Default = "Amarillo",
	Callback = function(name) ESP.StudsColor = COLOR_MAP[name] or Color3.fromRGB(255, 220, 60) end,
})

createSectionHeader(settingsPanel, "INTERFACE")
createToggle(settingsPanel, { Name = "Touch Feedback", Default = true, Callback = function(s) print("[Settings] Touch Feedback ->", s) end })
createToggle(settingsPanel, { Name = "Keep Menu On Top", Default = true, Callback = function(s) print("[Settings] Keep Menu On Top ->", s) end })

createSectionHeader(settingsPanel, "SYSTEM")
createActionButton(settingsPanel, {
	Name = "Reset FAB Position",
	Callback = function() _G.UIConfig.FABPosition = UDim2.fromScale(0.87, 0.74) end,
})
createActionButton(settingsPanel, {
	Name = "Close Menu",
	Callback = function() closeMenu() end,
})

-- =====================================================================
-- FLOATING ACTION BUTTON (DRAGGABLE)
-- =====================================================================
local fab = create("TextButton", {
	Name = "FloatingButton",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = _G.UIConfig.FABPosition,
	Size = UDim2.fromScale(0.08, 0.08),
	BackgroundColor3 = Color3.fromRGB(26, 29, 36),
	BorderSizePixel = 0,
	Text = "★",
	Font = Enum.Font.GothamBold,
	TextColor3 = Theme.Accent,
	TextScaled = true,
	AutoButtonColor = false,
	ZIndex = 60,
}, screenGui)
create("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, fab)
create("UITextSizeConstraint", { MaxTextSize = 26, MinTextSize = 10 }, fab)
addCorner(fab, 1)
addGradient(fab, Color3.new(1, 1, 1), Color3.fromRGB(180, 188, 202), 90)
local fabStroke = addStroke(fab, Theme.Accent, 1.6, 0.15)

local fabDragging = false
local fabMoved = false
local fabDragOrigin = nil
local fabStartPosition = nil

fab.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		fabDragging = true
		fabMoved = false
		fabDragOrigin = Vector2.new(input.Position.X, input.Position.Y)
		fabStartPosition = fab.Position
		TweenService:Create(fab, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(38, 43, 54) }):Play()
		TweenService:Create(fabStroke, TweenInfo.new(0.12), { Transparency = 0 }):Play()
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not fabDragging then return end
	if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end
	local currentPosition = Vector2.new(input.Position.X, input.Position.Y)
	local delta = currentPosition - fabDragOrigin
	if delta.Magnitude > 12 then fabMoved = true end
	local viewport = Camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then return end
	local newScaleX = fabStartPosition.X.Scale + (delta.X / viewport.X)
	local newScaleY = fabStartPosition.Y.Scale + (delta.Y / viewport.Y)
	fab.Position = UDim2.fromScale(math.clamp(newScaleX, 0.08, 0.92), math.clamp(newScaleY, 0.08, 0.92))
	_G.UIConfig.FABPosition = fab.Position
end)

UserInputService.InputEnded:Connect(function(input)
	if not fabDragging then return end
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		fabDragging = false
		TweenService:Create(fab, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(26, 29, 36) }):Play()
		TweenService:Create(fabStroke, TweenInfo.new(0.15), { Transparency = 0.15 }):Play()
		if not fabMoved then toggleMenu() end
	end
end)

-- =====================================================================
-- INITIAL STATE
-- =====================================================================
selectTab("Combat")
_G.UIConfig.ActiveTab = "Combat"
_G.UIConfig.MenuOpen = true
menuOpen = true
mainFrame.Visible = true
mainFrame.Size = _G.UIConfig.MenuSize

print("[MobileHub] Interface + ESP + Aimbot + Wallcheck + Player Movement constructed.")
print("[MobileHub] Tracer Origin:", ESP.TracerOrigin, "| Box Width Multiplier:", ESP.BoxWidthMultiplier)
print("[MobileHub] Aimbot Defaults — Smoothness:", Aimbot.Smoothness, "| FOV:", Aimbot.FOVRadius, "| Wallcheck:", Aimbot.Wallcheck)
print("[MobileHub] Player Defaults — WS:", PlayerState.WalkSpeedValue, "| JP:", PlayerState.JumpPowerValue)
