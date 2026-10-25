--!strict
-- All of the player's on-screen UI: coin/rating HUD, pen manager, Zoo Book and notifications.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stateUpdate = remotes:WaitForChild("StateUpdate") :: RemoteEvent
local openPenEvent = remotes:WaitForChild("OpenPen") :: RemoteEvent
local notifyEvent = remotes:WaitForChild("Notify") :: RemoteEvent
local actionEvent = remotes:WaitForChild("Action") :: RemoteEvent

---------------------------------------------------------------------------
-- Style
---------------------------------------------------------------------------

local FONT = Enum.Font.FredokaOne
local PANEL = Color3.fromRGB(250, 243, 225)
local PANEL_DARK = Color3.fromRGB(230, 215, 185)
local TEXT = Color3.fromRGB(70, 50, 30)
local GREEN = Color3.fromRGB(90, 170, 80)
local ORANGE = Color3.fromRGB(235, 150, 50)
local RED = Color3.fromRGB(210, 80, 70)
local BLUE = Color3.fromRGB(70, 140, 210)
local GREY = Color3.fromRGB(160, 155, 145)

local NOTIFY_COLORS = {
	info = BLUE,
	success = GREEN,
	warning = ORANGE,
	error = RED,
}

local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

local function create(className: string, props: { [string]: any }, children: { any }?): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

local function corner(radius: number?): Instance
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

local function padding(px: number): Instance
	return create("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

local function label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = TEXT,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in props do
		if k ~= "MaxTextSize" then
			defaults[k] = v
		end
	end
	return create("TextLabel", defaults, { create("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 22 }) })
end

local function button(text: string, color: Color3, onClick: () -> ()): TextButton
	local b = create("TextButton", {
		BackgroundColor3 = color,
		Font = FONT,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		AutoButtonColor = true,
	}, {
		corner(8),
		create("UITextSizeConstraint", { MaxTextSize = 20 }),
		create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
		create("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = color:Lerp(Color3.new(0, 0, 0), 0.3),
			Thickness = 2,
		}),
	})
	b.Activated:Connect(onClick)
	return b
end

local function bar(fill: number, color: Color3, text: string): Frame
	return create("Frame", {
		BackgroundColor3 = PANEL_DARK,
		Size = UDim2.new(1, 0, 0, 16),
	}, {
		corner(6),
		create("Frame", {
			Name = "Fill",
			BackgroundColor3 = color,
			Size = UDim2.fromScale(math.clamp(fill, 0, 1), 1),
		}, { corner(6) }),
		label({
			Name = "Text",
			Size = UDim2.fromScale(1, 1),
			Text = text,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.5,
			ZIndex = 2,
			MaxTextSize = 13,
		}),
	})
end

local function setBar(frame: Instance, fill: number, text: string)
	local fillFrame = frame:FindFirstChild("Fill") :: Frame
	fillFrame.Size = UDim2.fromScale(math.clamp(fill, 0, 1), 1)
	local textLabel = frame:FindFirstChild("Text") :: TextLabel
	textLabel.Text = text
end

---------------------------------------------------------------------------
-- Root and HUD
---------------------------------------------------------------------------

local screen = create("ScreenGui", {
	Name = "ZooUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

local hud = create("Frame", {
	Name = "HUD",
	BackgroundColor3 = PANEL,
	Position = UDim2.fromOffset(12, 12),
	Size = UDim2.fromOffset(230, 140),
	Parent = screen,
}, { corner(12), padding(8) })

local coinsLabel = label({
	Text = "🪙 0",
	Size = UDim2.new(1, 0, 0, 28),
	MaxTextSize = 26,
	Parent = hud,
})
local ratingLabel = label({
	Text = "⭐ Rating 0",
	Position = UDim2.fromOffset(0, 30),
	Size = UDim2.new(1, 0, 0, 22),
	MaxTextSize = 20,
	Parent = hud,
})

local zooBookPanel: Frame
local renderZooBook: () -> ()

local bookButton = button("📖 Zoo Book", BLUE, function()
	zooBookPanel.Visible = not zooBookPanel.Visible
	if zooBookPanel.Visible then
		renderZooBook()
	end
end)
bookButton.Position = UDim2.fromOffset(0, 58)
bookButton.Size = UDim2.new(1, 0, 0, 30)
bookButton.Parent = hud

local feedAllButton = button("🥕 Feed all pens", ORANGE, function()
	actionEvent:FireServer("FeedAll")
end)
feedAllButton.Position = UDim2.fromOffset(0, 92)
feedAllButton.Size = UDim2.new(1, 0, 0, 30)
feedAllButton.Parent = hud

---------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------

local toastList = create("Frame", {
	Name = "Toasts",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -90),
	Size = UDim2.new(0.9, 0, 0, 300),
	Parent = screen,
}, {
	create("UISizeConstraint", { MaxSize = Vector2.new(420, 300) }),
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
	}),
})

local toastOrder = 0
local function showToast(text: string, kind: string)
	toastOrder += 1
	local toast = create("Frame", {
		BackgroundColor3 = NOTIFY_COLORS[kind] or BLUE,
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = toastOrder,
		Parent = toastList,
	}, {
		corner(10),
		padding(6),
		label({
			Text = text,
			Size = UDim2.fromScale(1, 1),
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			MaxTextSize = 18,
		}),
	})
	-- Keep at most 5 on screen.
	local toasts = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #toasts - 5 do
		toasts[i]:Destroy()
	end
	task.delay(4, function()
		if toast.Parent then
			local tween = TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			toast:Destroy()
		end
	end)
end

notifyEvent.OnClientEvent:Connect(function(text: string, kind: string)
	showToast(text, kind)
end)

---------------------------------------------------------------------------
-- Pen panel
---------------------------------------------------------------------------

type AnimalState = {
	id: string,
	species: string,
	stage: string,
	growth: number,
	hunger: number,
	sellPrice: number,
}
type PenState = {
	unlocked: boolean,
	price: number,
	species: string?,
	animals: { AnimalState },
}
type State = {
	coins: number,
	rating: number,
	discovered: { [string]: boolean },
	pens: { PenState },
}

local state: State? = nil
local openPenIndex: number? = nil
local openSign: BasePart? = nil
local penSignature = ""
local animalRows: { [string]: Frame } = {}

local penPanel = create("Frame", {
	Name = "PenPanel",
	BackgroundColor3 = PANEL,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(340, 440),
	Visible = false,
	Parent = screen,
}, { corner(14), padding(10), create("UISizeConstraint", { MaxSize = Vector2.new(340, 440) }) })

local penTitle = label({
	Text = "Pen",
	Size = UDim2.new(1, -40, 0, 32),
	MaxTextSize = 26,
	Parent = penPanel,
})

local closePenButton = button("✕", RED, function()
	penPanel.Visible = false
	openPenIndex = nil
	openSign = nil
end)
closePenButton.AnchorPoint = Vector2.new(1, 0)
closePenButton.Position = UDim2.new(1, 0, 0, 0)
closePenButton.Size = UDim2.fromOffset(36, 36)
closePenButton.Parent = penPanel

local penBody = create("ScrollingFrame", {
	Name = "Body",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 44),
	Size = UDim2.new(1, 0, 1, -44),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = GREY,
	Parent = penPanel,
}, {
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}),
})

local function clearBody()
	for _, child in penBody:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	animalRows = {}
end

local function addToBody(instance: GuiObject, order: number)
	instance.LayoutOrder = order
	instance.Parent = penBody
end

local function penFeedCost(pen: PenState): number
	local cost = 0
	for _, animal in pen.animals do
		if animal.hunger < 0.99 then
			cost += Config.SpeciesById[animal.species].feedCost
		end
	end
	return cost
end

local function buildSpeciesCard(penIndex: number, species: Config.Species, coins: number): Frame
	local affordable = coins >= species.price
	local card = create("Frame", {
		BackgroundColor3 = PANEL_DARK,
		Size = UDim2.new(1, -8, 0, 64),
	}, { corner(10), padding(6) })
	label({
		Text = species.name,
		Size = UDim2.new(0.6, 0, 0, 24),
		Parent = card,
	})
	label({
		Text = string.format(
			"Adult earns %s/s • grows in %ds",
			formatNumber(species.income),
			species.growTime
		),
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(0.62, 0, 0, 22),
		MaxTextSize = 14,
		TextColor3 = Color3.fromRGB(110, 90, 70),
		Parent = card,
	})
	local buy = button("🪙 " .. formatNumber(species.price), if affordable then GREEN else GREY, function()
		actionEvent:FireServer("BuyAnimal", penIndex, species.id)
	end)
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Position = UDim2.new(1, 0, 0.5, 0)
	buy.Size = UDim2.new(0.36, 0, 0, 44)
	buy.Parent = card
	return card
end

local function buildAnimalRow(penIndex: number, animal: AnimalState): Frame
	local species = Config.SpeciesById[animal.species]
	local row = create("Frame", {
		BackgroundColor3 = PANEL_DARK,
		Size = UDim2.new(1, -8, 0, 78),
	}, { corner(10), padding(6) })
	label({
		Name = "Title",
		Text = animal.stage .. " " .. species.name,
		Size = UDim2.new(0.62, 0, 0, 22),
		Parent = row,
	})
	local growthBar = bar(0, GREEN, "")
	growthBar.Name = "Growth"
	growthBar.Position = UDim2.fromOffset(0, 26)
	growthBar.Size = UDim2.new(0.62, 0, 0, 18)
	growthBar.Parent = row
	local hungerBar = bar(0, ORANGE, "")
	hungerBar.Name = "Hunger"
	hungerBar.Position = UDim2.fromOffset(0, 48)
	hungerBar.Size = UDim2.new(0.62, 0, 0, 18)
	hungerBar.Parent = row

	local sell = button("Sell", RED, function()
		actionEvent:FireServer("SellAnimal", penIndex, animal.id)
	end)
	sell.Name = "Sell"
	sell.AnchorPoint = Vector2.new(1, 0.5)
	sell.Position = UDim2.new(1, 0, 0.5, 0)
	sell.Size = UDim2.new(0.34, 0, 0, 44)
	sell.Parent = row
	return row
end

local function updateAnimalRow(row: Frame, animal: AnimalState)
	local growthText = if animal.stage == "Adult"
		then "Fully grown!"
		else string.format("Growing %d%%", math.floor(animal.growth * 100))
	setBar(row:FindFirstChild("Growth") :: Frame, animal.growth, growthText)
	local hungerText = if animal.hunger <= 0 then "Hungry!" else string.format("Food %d%%", math.ceil(animal.hunger * 100))
	setBar(row:FindFirstChild("Hunger") :: Frame, animal.hunger, hungerText)
	local sell = row:FindFirstChild("Sell") :: TextButton
	sell.Text = "Sell 🪙" .. formatNumber(animal.sellPrice)
	local title = row:FindFirstChild("Title") :: TextLabel
	title.Text = animal.stage .. " " .. Config.SpeciesById[animal.species].name
end

local footerButtons: { [string]: TextButton } = {}

local function renderPen()
	if not openPenIndex or not state then
		return
	end
	local currentState = state :: State
	local penIndex = openPenIndex :: number
	local pen = currentState.pens[penIndex]
	if not pen then
		return
	end

	-- Rebuild only when the layout changes; otherwise update text in place so
	-- buttons keep working while the player clicks them.
	local parts = { tostring(penIndex), tostring(pen.unlocked), pen.species or "-" }
	for _, animal in pen.animals do
		table.insert(parts, animal.id)
	end
	if not pen.species or #pen.animals == 0 then
		-- Shop cards change colour when the player can afford them.
		for _, species in Config.Species do
			table.insert(parts, tostring(currentState.coins >= species.price))
		end
	end
	local signature = table.concat(parts, "|")
	local rebuild = signature ~= penSignature
	penSignature = signature

	local species = if pen.species then Config.SpeciesById[pen.species] else nil
	penTitle.Text = if species
		then string.format("Pen %d — %s", penIndex, species.name)
		else string.format("Pen %d", penIndex)

	if rebuild then
		clearBody()
		footerButtons = {}
		if not pen.unlocked then
			addToBody(
				label({
					Text = "🔒 This pen is locked. Unlock it to raise more animals!",
					Size = UDim2.new(1, -8, 0, 48),
					TextWrapped = true,
					MaxTextSize = 18,
				}),
				1
			)
			local unlock = button("Unlock for 🪙 " .. formatNumber(pen.price), GREEN, function()
				actionEvent:FireServer("UnlockPen", penIndex)
			end)
			unlock.Size = UDim2.new(1, -8, 0, 44)
			addToBody(unlock, 2)
		elseif #pen.animals == 0 then
			addToBody(
				label({
					Text = "Pick a baby animal to raise. Feed it so it grows into an adult that earns coins from visitors!",
					Size = UDim2.new(1, -8, 0, 54),
					TextWrapped = true,
					MaxTextSize = 15,
				}),
				1
			)
			for i, s in Config.Species do
				addToBody(buildSpeciesCard(penIndex, s, currentState.coins), i + 1)
			end
		else
			for i, animal in pen.animals do
				local row = buildAnimalRow(penIndex, animal)
				animalRows[animal.id] = row
				addToBody(row, i)
			end

			local feed = button("🥕 Feed", ORANGE, function()
				actionEvent:FireServer("FeedPen", penIndex)
			end)
			feed.Size = UDim2.new(1, -8, 0, 44)
			addToBody(feed, 100)
			footerButtons.feed = feed

			if species and #pen.animals < Config.PenCapacity then
				local buyMore = button("", GREEN, function()
					actionEvent:FireServer("BuyAnimal", penIndex, species.id)
				end)
				buyMore.Size = UDim2.new(1, -8, 0, 44)
				addToBody(buyMore, 101)
				footerButtons.buyMore = buyMore
			end

			addToBody(
				label({
					Name = "Tip",
					Text = "",
					Size = UDim2.new(1, -8, 0, 40),
					TextWrapped = true,
					MaxTextSize = 14,
					TextColor3 = Color3.fromRGB(110, 90, 70),
				}),
				102
			)
		end
	end

	-- In-place updates.
	for _, animal in pen.animals do
		local row = animalRows[animal.id]
		if row then
			updateAnimalRow(row, animal)
		end
	end
	if footerButtons.feed then
		local cost = penFeedCost(pen)
		footerButtons.feed.Text = if cost > 0 then "🥕 Feed for 🪙 " .. formatNumber(cost) else "🥕 Everyone is full"
	end
	if footerButtons.buyMore and species then
		footerButtons.buyMore.Text = string.format("Buy another %s 🪙 %s", species.name, formatNumber(species.price))
	end
	local tip = penBody:FindFirstChild("Tip") :: TextLabel?
	if tip and species then
		local adults = 0
		for _, animal in pen.animals do
			if animal.stage == "Adult" then
				adults += 1
			end
		end
		if #pen.animals >= Config.PenCapacity then
			tip.Text = "This pen is full. Sell an animal to make room."
		elseif adults >= 2 then
			tip.Text = "💕 Two well-fed adults may have a baby soon!"
		else
			tip.Text = "Tip: two well-fed adults in a pen can have babies."
		end
	end
end

openPenEvent.OnClientEvent:Connect(function(penIndex: number)
	openPenIndex = penIndex
	penSignature = ""
	penPanel.Visible = true
	renderPen()
end)

---------------------------------------------------------------------------
-- Zoo Book
---------------------------------------------------------------------------

zooBookPanel = create("Frame", {
	Name = "ZooBook",
	BackgroundColor3 = PANEL,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(460, 380),
	Visible = false,
	Parent = screen,
}, { corner(14), padding(12) })

local bookTitle = label({
	Text = "📖 Zoo Book",
	Size = UDim2.new(1, -40, 0, 32),
	MaxTextSize = 26,
	Parent = zooBookPanel,
})
local closeBook = button("✕", RED, function()
	zooBookPanel.Visible = false
end)
closeBook.AnchorPoint = Vector2.new(1, 0)
closeBook.Position = UDim2.new(1, 0, 0, 0)
closeBook.Size = UDim2.fromOffset(36, 36)
closeBook.Parent = zooBookPanel

label({
	Text = "Raise each animal to adulthood to fill your Zoo Book. Every new species gives a big coin bonus!",
	Position = UDim2.fromOffset(0, 36),
	Size = UDim2.new(1, 0, 0, 36),
	TextWrapped = true,
	MaxTextSize = 15,
	Parent = zooBookPanel,
})

local bookGrid = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 80),
	Size = UDim2.new(1, 0, 1, -80),
	Parent = zooBookPanel,
}, {
	create("UIGridLayout", {
		CellSize = UDim2.new(0.25, -6, 0.5, -6),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

renderZooBook = function()
	for _, child in bookGrid:GetChildren() do
		if not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
	local discovered = if state then state.discovered else {}
	local count = 0
	for i, species in Config.Species do
		local found = discovered[species.id] == true
		if found then
			count += 1
		end
		create("Frame", {
			BackgroundColor3 = if found then Color3.fromRGB(200, 230, 180) else PANEL_DARK,
			LayoutOrder = i,
			Parent = bookGrid,
		}, {
			corner(10),
			padding(6),
			create("Frame", {
				BackgroundColor3 = if found then species.visual.bodyColor else GREY,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromScale(0.6, 0.45),
			}, {
				corner(30),
				create("UIAspectRatioConstraint", {}),
				create("UIStroke", { Color = TEXT, Thickness = 2 }),
			}),
			label({
				Text = if found then species.name else "???",
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromScale(1, 0.25),
				TextXAlignment = Enum.TextXAlignment.Center,
				MaxTextSize = 18,
			}),
			label({
				Text = if found then "✔ Raised" else "🪙 " .. formatNumber(species.price),
				Position = UDim2.fromScale(0, 0.75),
				Size = UDim2.fromScale(1, 0.22),
				TextXAlignment = Enum.TextXAlignment.Center,
				MaxTextSize = 14,
				TextColor3 = if found then GREEN else Color3.fromRGB(110, 90, 70),
			}),
		})
	end
	bookTitle.Text = string.format("📖 Zoo Book  %d/%d", count, #Config.Species)
end

---------------------------------------------------------------------------
-- State updates
---------------------------------------------------------------------------

local lastDiscoveredCount = -1

stateUpdate.OnClientEvent:Connect(function(newState: State)
	state = newState
	coinsLabel.Text = "🪙 " .. formatNumber(newState.coins)
	ratingLabel.Text = "⭐ Rating " .. formatNumber(newState.rating)

	local discoveredCount = 0
	for _ in newState.discovered do
		discoveredCount += 1
	end
	bookButton.Text = string.format("📖 Zoo Book %d/%d", discoveredCount, #Config.Species)
	if zooBookPanel.Visible and discoveredCount ~= lastDiscoveredCount then
		renderZooBook()
	end
	lastDiscoveredCount = discoveredCount

	if penPanel.Visible then
		renderPen()
	end
end)

---------------------------------------------------------------------------
-- Only show pen prompts on the player's own zoo
---------------------------------------------------------------------------

local function watchPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local function update()
		prompt.Enabled = prompt:GetAttribute("OwnerUserId") == player.UserId
	end
	update()
	prompt:GetAttributeChangedSignal("OwnerUserId"):Connect(update)
end

CollectionService:GetInstanceAddedSignal("PenPrompt"):Connect(watchPrompt)
for _, prompt in CollectionService:GetTagged("PenPrompt") do
	watchPrompt(prompt)
end

---------------------------------------------------------------------------
-- Fit panels to small screens (phones)
---------------------------------------------------------------------------

-- Shrinks a panel with a UIScale so it fits the screen. widthShare and
-- heightShare are how much of the screen it may take up.
local function fitToScreen(panel: GuiObject, baseSize: Vector2, widthShare: number, heightShare: number)
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = panel
	local function update()
		local available = screen.AbsoluteSize
		if available.X <= 0 or available.Y <= 0 then
			return
		end
		local margin = 24
		local scale = math.min(
			1,
			(available.X * widthShare - margin) / baseSize.X,
			(available.Y * heightShare - margin) / baseSize.Y
		)
		uiScale.Scale = math.max(0.5, scale)
	end
	update()
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
end

fitToScreen(hud, Vector2.new(230, 140), 0.45, 0.35)
fitToScreen(penPanel, Vector2.new(340, 440), 1, 1)
fitToScreen(zooBookPanel, Vector2.new(460, 380), 1, 1)

---------------------------------------------------------------------------
-- Close the pen panel when the player walks away from its sign
---------------------------------------------------------------------------

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if CollectionService:HasTag(prompt, "PenPrompt") and prompt.Parent and prompt.Parent:IsA("BasePart") then
		openSign = prompt.Parent
	end
end)

local closeCheckTimer = 0
RunService.Heartbeat:Connect(function(dt)
	closeCheckTimer += dt
	if closeCheckTimer < 0.5 then
		return
	end
	closeCheckTimer = 0
	local sign = openSign
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if penPanel.Visible and sign and root and root:IsA("BasePart") then
		if (root.Position - sign.Position).Magnitude > 25 then
			penPanel.Visible = false
			openPenIndex = nil
			openSign = nil
		end
	end
end)

-- First-time hint.
task.delay(4, function()
	local onTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local how = if onTouch then "tap the button that pops up" else "press E"
	showToast("Welcome to your zoo! Walk up to a pen sign and " .. how .. " to manage it.", "info")
end)
