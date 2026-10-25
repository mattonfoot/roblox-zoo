--!strict
-- Food foraging and treasure chests out in the wild rings around the zoo.
--
-- Food nodes (carrot patches, fish ponds, hay bales...) grow in the ring for
-- their food: rarer food is further away. Players hold a prompt to forage,
-- which fills their backpack. Nodes regrow after a short time.
--
-- Chests appear at random spots in each ring. Opening one upgrades a random
-- piece of equipment, up to a level that depends on how far out the chest is.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Api = {
	getZoo: (player: Player) -> any,
	carried: (zoo: any) -> number,
	capacity: (zoo: any) -> number,
	changed: (zoo: any) -> (),
	notify: (player: Player, text: string, kind: string?) -> (),
}

type Node = {
	food: Config.Food,
	model: Model,
	prompt: ProximityPrompt,
	marker: BillboardGui,
	ready: boolean,
}

local ForageService = {}

local api: Api
local folder: Folder
local usedSpots: { Vector3 } = {}
local holdStarts: { [ProximityPrompt]: { [Player]: number } } = {}

local MIN_GLOVES = Config.EquipmentById.Gloves.values[#Config.EquipmentById.Gloves.values]

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function part(model: Model, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p:SetAttribute("BaseTransparency", p.Transparency)
	p.Parent = model
	return p
end

local function emojiMarker(parent: Instance, text: string, maxDistance: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(44, 44)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.MaxDistance = maxDistance
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
	gui.Parent = parent
	return gui
end

-- Picks a random spot inside a ring that isn't too close to other things.
local function randomSpot(ring: Config.Ring): Vector3
	local best = Vector3.zero
	for _ = 1, 15 do
		local angle = math.random() * math.pi * 2
		-- sqrt keeps points evenly spread over the ring's area.
		local inner, outer = ring.inner + 10, ring.outer - 10
		local radius = math.sqrt(inner * inner + math.random() * (outer * outer - inner * inner))
		local spot = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		best = spot
		local clear = true
		for _, used in usedSpots do
			if (used - spot).Magnitude < 18 then
				clear = false
				break
			end
		end
		if clear then
			break
		end
	end
	table.insert(usedSpots, best)
	return best
end

local function releaseSpot(spot: Vector3)
	for i, used in usedSpots do
		if (used - spot).Magnitude < 0.1 then
			table.remove(usedSpots, i)
			return
		end
	end
end

---------------------------------------------------------------------------
-- Food node models. Each returns the part that holds the prompt.
---------------------------------------------------------------------------

local function buildFoodModel(model: Model, foodId: string, at: CFrame): Part
	if foodId == "Carrot" then
		local base = part(model, {
			Name = "Base",
			Size = Vector3.new(5, 0.6, 5),
			CFrame = at * CFrame.new(0, 0.3, 0),
			Color = rgb(110, 75, 45),
			Material = Enum.Material.Ground,
		})
		for i = 1, 4 do
			local x, z = (i % 2) * 2 - 1, (if i > 2 then 1 else -1)
			part(model, {
				Name = "Carrot",
				Size = Vector3.new(0.5, 0.9, 0.5),
				CFrame = at * CFrame.new(x * 1.2, 0.9, z * 1.2),
				Color = rgb(240, 130, 30),
				CanCollide = false,
			})
			part(model, {
				Name = "Leaves",
				Size = Vector3.new(0.6, 0.8, 0.2),
				CFrame = at * CFrame.new(x * 1.2, 1.7, z * 1.2),
				Color = rgb(70, 160, 50),
				CanCollide = false,
			})
		end
		return base
	elseif foodId == "Fish" then
		local base = part(model, {
			Name = "Base",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 9, 9),
			CFrame = at * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = rgb(60, 130, 200),
			Material = Enum.Material.Glass,
			Transparency = 0.2,
			CanCollide = false,
		})
		for i = 1, 2 do
			part(model, {
				Name = "Fish",
				Size = Vector3.new(0.4, 0.4, 1.2),
				CFrame = at * CFrame.new(i * 2 - 3, 0.45, i - 1.5) * CFrame.Angles(0, math.rad(i * 70), 0),
				Color = rgb(250, 150, 60),
				CanCollide = false,
			})
		end
		return base
	elseif foodId == "Hay" then
		local base = part(model, {
			Name = "Base",
			Size = Vector3.new(4, 2.5, 3),
			CFrame = at * CFrame.new(0, 1.25, 0),
			Color = rgb(225, 195, 90),
			Material = Enum.Material.Grass,
		})
		part(model, {
			Name = "Hay",
			Size = Vector3.new(3, 2, 2.5),
			CFrame = at * CFrame.new(2.5, 1, 1.5) * CFrame.Angles(0, math.rad(30), 0),
			Color = rgb(215, 185, 80),
			Material = Enum.Material.Grass,
		})
		return base
	elseif foodId == "Bamboo" then
		local base = part(model, {
			Name = "Base",
			Size = Vector3.new(5, 0.4, 5),
			CFrame = at * CFrame.new(0, 0.2, 0),
			Color = rgb(70, 110, 50),
			Material = Enum.Material.Grass,
		})
		for i = 1, 6 do
			local angle = i * math.pi / 3
			local height = 7 + (i % 3) * 1.5
			part(model, {
				Name = "Stalk",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(height, 0.5, 0.5),
				CFrame = at * CFrame.new(math.cos(angle) * 1.5, height / 2, math.sin(angle) * 1.5) * CFrame.Angles(
					0,
					0,
					math.rad(90)
				),
				Color = rgb(120, 175, 70),
				Material = Enum.Material.Wood,
			})
		end
		return base
	elseif foodId == "Meat" then
		local base = part(model, {
			Name = "Base",
			Size = Vector3.new(3, 2.4, 3),
			CFrame = at * CFrame.new(0, 1.2, 0),
			Color = rgb(130, 90, 55),
			Material = Enum.Material.WoodPlanks,
		})
		part(model, {
			Name = "Meat",
			Size = Vector3.new(2.2, 0.6, 1.4),
			CFrame = at * CFrame.new(0, 2.7, 0),
			Color = rgb(200, 70, 70),
			CanCollide = false,
		})
		part(model, {
			Name = "Bone",
			Size = Vector3.new(0.3, 0.3, 2.2),
			CFrame = at * CFrame.new(0, 2.8, 0) * CFrame.Angles(0, math.rad(90), 0),
			Color = rgb(245, 240, 225),
			CanCollide = false,
		})
		return base
	elseif foodId == "Leaves" then
		local base = part(model, {
			Name = "Base",
			Size = Vector3.new(1.2, 9, 1.2),
			CFrame = at * CFrame.new(0, 4.5, 0),
			Color = rgb(110, 75, 45),
			Material = Enum.Material.Wood,
		})
		part(model, {
			Name = "Canopy",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.8, 12, 12),
			CFrame = at * CFrame.new(0, 9.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = rgb(85, 140, 55),
			Material = Enum.Material.LeafyGrass,
		})
		return base
	else -- Melon
		local base = part(model, {
			Name = "Base",
			Size = Vector3.new(6, 0.4, 5),
			CFrame = at * CFrame.new(0, 0.2, 0),
			Color = rgb(110, 75, 45),
			Material = Enum.Material.Ground,
		})
		for i = 1, 3 do
			part(model, {
				Name = "Melon",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.8, 1.8, 1.8),
				CFrame = at * CFrame.new(i * 1.8 - 3.6, 1.2, (i % 2) - 0.5),
				Color = rgb(60, 130, 50),
			})
		end
		return base
	end
end

local function setNodeReady(node: Node, ready: boolean)
	node.ready = ready
	node.prompt.Enabled = ready
	node.marker.Enabled = ready
	for _, child in node.model:GetChildren() do
		if child:IsA("BasePart") then
			local baseTransparency = (child:GetAttribute("BaseTransparency") :: number?) or 0
			child.Transparency = if ready then baseTransparency else math.max(baseTransparency, 0.75)
		end
	end
end

local function requiredHoldTime(zoo: any, food: Config.Food): number
	return food.harvestTime * Config.getEquipmentValue("Gloves", zoo.equipment.Gloves or 0)
end

local function trackHolds(prompt: ProximityPrompt)
	holdStarts[prompt] = {}
	prompt.PromptButtonHoldBegan:Connect(function(player)
		local starts = holdStarts[prompt]
		if starts then
			starts[player] = os.clock()
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player)
		-- Keep the start time briefly: Triggered can arrive just after this.
		local started = holdStarts[prompt] and holdStarts[prompt][player]
		task.delay(0.5, function()
			local starts = holdStarts[prompt]
			if starts and starts[player] == started then
				starts[player] = nil
			end
		end)
	end)
end

-- Checks the player really held the prompt long enough for their gloves.
local function heldLongEnough(prompt: ProximityPrompt, player: Player, required: number): boolean
	local starts = holdStarts[prompt]
	local started = starts and starts[player]
	if not started then
		return false
	end
	return os.clock() - started >= required * 0.85 - 0.2
end

local function createNode(food: Config.Food)
	local ring = Config.Rings[food.ring]
	local spot = randomSpot(ring)
	local model = Instance.new("Model")
	model.Name = food.name
	local at = CFrame.new(spot) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	local base = buildFoodModel(model, food.id, at)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Forage"
	prompt.ObjectText = food.emoji .. " " .. food.name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	-- The client sets the real hold time for its own gloves; the server
	-- checks it. This server value is just the fastest possible.
	prompt.HoldDuration = food.harvestTime * MIN_GLOVES
	prompt:SetAttribute("BaseTime", food.harvestTime)
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = base
	CollectionService:AddTag(prompt, "ForagePrompt")

	local node: Node = {
		food = food,
		model = model,
		prompt = prompt,
		marker = emojiMarker(base, food.emoji, 160),
		ready = true,
	}
	model.Parent = folder
	trackHolds(prompt)

	prompt.Triggered:Connect(function(player)
		local zoo = api.getZoo(player)
		if not zoo then
			return
		end
		if not node.ready then
			api.notify(player, "Someone got here first! It will grow back soon.", "info")
			return
		end
		if not heldLongEnough(prompt, player, requiredHoldTime(zoo, food)) then
			return
		end
		local space = api.capacity(zoo) - api.carried(zoo)
		if space <= 0 then
			api.notify(player, "🎒 Your backpack is full! Take the food back to your pens.", "error")
			return
		end
		local amount = math.min(food.yield, space)
		zoo.inventory[food.id] = (zoo.inventory[food.id] or 0) + amount
		setNodeReady(node, false)
		api.notify(player, string.format("Foraged %d %s %s!", amount, food.emoji, food.name), "success")
		api.changed(zoo)
		task.delay(Config.NodeRegrowTime, function()
			setNodeReady(node, true)
		end)
	end)
end

---------------------------------------------------------------------------
-- Chests
---------------------------------------------------------------------------

local function openChest(player: Player, ringIndex: number): boolean
	local zoo = api.getZoo(player)
	if not zoo then
		return false
	end

	-- Chests further out can hold better equipment.
	local maxLevel = math.min(ringIndex, Config.MaxEquipmentLevel)
	local candidates = {}
	for _, item in Config.Equipment do
		if (zoo.equipment[item.id] or 0) < maxLevel then
			table.insert(candidates, item)
		end
	end

	if #candidates == 0 then
		local coins = Config.ChestCoinRewards[ringIndex] or 100
		zoo.coins += coins
		api.notify(
			player,
			string.format(
				"🎁 The chest held %d coins. Search further out than the %s for better gear!",
				coins,
				Config.Rings[ringIndex].name
			),
			"success"
		)
	else
		local item = candidates[math.random(1, #candidates)]
		local level = (zoo.equipment[item.id] or 0) + 1
		zoo.equipment[item.id] = level
		api.notify(
			player,
			string.format("🎁 You found %s %s! %s.", item.emoji, item.tierNames[level + 1], item.description),
			"success"
		)
	end
	api.changed(zoo)
	return true
end

local function spawnChest(ringIndex: number)
	local ring = Config.Rings[ringIndex]
	local spot = randomSpot(ring)
	local model = Instance.new("Model")
	model.Name = "Chest"
	local at = CFrame.new(spot) * CFrame.Angles(0, math.random() * math.pi * 2, 0)

	local base = part(model, {
		Name = "Base",
		Size = Vector3.new(3, 1.8, 2),
		CFrame = at * CFrame.new(0, 0.9, 0),
		Color = rgb(120, 70, 35),
		Material = Enum.Material.WoodPlanks,
	})
	local lid = part(model, {
		Name = "Lid",
		Size = Vector3.new(3.2, 0.7, 2.2),
		CFrame = at * CFrame.new(0, 2.15, 0),
		Color = rgb(240, 190, 50),
		Material = Enum.Material.Metal,
	})
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 220, 120)
	light.Range = 10
	light.Brightness = 2
	light.Parent = lid
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = rgb(255, 230, 120)
	sparkles.Parent = lid
	emojiMarker(base, "🎁", 220)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = "Treasure chest"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = base
	trackHolds(prompt)

	local opened = false
	prompt.Triggered:Connect(function(player)
		if opened or not heldLongEnough(prompt, player, 1) then
			return
		end
		if openChest(player, ringIndex) then
			opened = true
			holdStarts[prompt] = nil
			model:Destroy()
			releaseSpot(spot)
			task.delay(Config.ChestRespawnTime, spawnChest, ringIndex)
		end
	end)

	model.Parent = folder
end

function ForageService.start(serviceApi: Api)
	api = serviceApi
	folder = Instance.new("Folder")
	folder.Name = "Wilds"
	folder.Parent = workspace

	for _, food in Config.Foods do
		for _ = 1, Config.NodesPerFood do
			createNode(food)
		end
	end
	for ringIndex, count in Config.ChestsPerRing do
		for _ = 1, count do
			spawnChest(ringIndex)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		for _, starts in holdStarts do
			starts[player] = nil
		end
	end)
end

return ForageService
