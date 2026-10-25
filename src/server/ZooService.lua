--!strict
-- Core zoo logic: plots, pens, animals, food stores, growth, health, breeding, income and actions.
--
-- The server owns all game state. Each animal is a small "marker" instance
-- (tagged ZooAnimal) whose attributes hold its species, stage and wander target.
-- Clients build and animate the actual animal models from those markers, so the
-- server only sends a few attribute changes instead of moving parts every frame.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local ForageService = require(script.Parent.ForageService)
local WorldBuilder = require(script.Parent.WorldBuilder)

type Species = Config.Species

type Animal = {
	id: string,
	species: Species,
	growth: number,
	hunger: number,
	health: number,
	stage: string,
	marker: Configuration,
	position: Vector3, -- where the animal is heading (or resting)
	nextMoveAt: number,
	warnedStarving: boolean,
}

type Pen = {
	index: number,
	unlocked: boolean,
	animals: { Animal },
	breedCooldown: number,
	storeFood: string?,
	storeAmount: number,
	world: WorldBuilder.Pen,
}

export type Zoo = {
	player: Player,
	plot: WorldBuilder.Plot,
	coins: number,
	pens: { Pen },
	discovered: { [string]: boolean },
	inventory: { [string]: number },
	equipment: { [string]: number },
	canSave: boolean,
	loaded: boolean,
	lastActionAt: number,
	coinsValue: IntValue,
	ratingValue: IntValue,
}

local ZooService = {}

local plots: { WorldBuilder.Plot } = {}
local plotOwners: { [number]: Player } = {}
local zoos: { [Player]: Zoo } = {}

local stateUpdate: RemoteEvent
local openPen: RemoteEvent
local notifyEvent: RemoteEvent
local actionEvent: RemoteEvent

local LOCKED_FLOOR = Color3.fromRGB(95, 95, 95)
local EMPTY_FLOOR = Color3.fromRGB(110, 160, 80)

local function notify(player: Player, text: string, kind: string?)
	notifyEvent:FireClient(player, text, kind or "info")
end

local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

---------------------------------------------------------------------------
-- State helpers
---------------------------------------------------------------------------

local function carried(zoo: Zoo): number
	local total = 0
	for _, amount in zoo.inventory do
		total += amount
	end
	return total
end

local function backpackCapacity(zoo: Zoo): number
	return Config.getEquipmentValue("Backpack", zoo.equipment.Backpack or 0)
end

local function storeCapacity(zoo: Zoo): number
	return Config.getEquipmentValue("Pantry", zoo.equipment.Pantry or 0)
end

local function computeRating(zoo: Zoo): number
	local rating = 0
	for _, pen in zoo.pens do
		for _, animal in pen.animals do
			if animal.stage == "Adult" then
				rating += animal.species.rating
			end
		end
	end
	for _ in zoo.discovered do
		rating += Config.DiscoveryRating
	end
	return rating
end

local function serialize(zoo: Zoo): DataService.SaveData
	local pens = {}
	for _, pen in zoo.pens do
		local animals = {}
		for _, animal in pen.animals do
			table.insert(animals, {
				species = animal.species.id,
				growth = math.floor(animal.growth * 10) / 10,
				hunger = math.floor(animal.hunger * 10) / 10,
				health = math.ceil(animal.health * 10) / 10,
			})
		end
		table.insert(pens, {
			unlocked = pen.unlocked,
			animals = animals,
			storeFood = pen.storeFood,
			storeAmount = math.floor(pen.storeAmount * 10) / 10,
		})
	end
	return {
		version = 2,
		coins = math.floor(zoo.coins),
		pens = pens,
		discovered = table.clone(zoo.discovered),
		inventory = table.clone(zoo.inventory),
		equipment = table.clone(zoo.equipment),
	}
end

local function penSpecies(pen: Pen): Species?
	local first = pen.animals[1]
	return if first then first.species else nil
end

local function buildClientState(zoo: Zoo)
	local capacity = storeCapacity(zoo)
	local pens = {}
	for _, pen in zoo.pens do
		local animals = {}
		for _, animal in pen.animals do
			table.insert(animals, {
				id = animal.id,
				species = animal.species.id,
				stage = animal.stage,
				growth = math.clamp(animal.growth / animal.species.growTime, 0, 1),
				hunger = animal.hunger / Config.HungerMax,
				health = animal.health / Config.HealthMax,
				sellPrice = Config.getSellPrice(animal.species, animal.growth),
			})
		end
		local species = penSpecies(pen)
		table.insert(pens, {
			unlocked = pen.unlocked,
			price = Config.getPenPrice(pen.index),
			species = if species then species.id else nil,
			animals = animals,
			storeFood = pen.storeFood,
			storeAmount = math.floor(pen.storeAmount),
			storeCapacity = capacity,
		})
	end
	return {
		coins = math.floor(zoo.coins),
		rating = computeRating(zoo),
		discovered = zoo.discovered,
		inventory = zoo.inventory,
		carried = carried(zoo),
		capacity = backpackCapacity(zoo),
		equipment = zoo.equipment,
		pens = pens,
	}
end

local function pushState(zoo: Zoo)
	if not zoo.loaded then
		return
	end
	zoo.coinsValue.Value = math.floor(zoo.coins)
	zoo.ratingValue.Value = computeRating(zoo)
	stateUpdate:FireClient(zoo.player, buildClientState(zoo))
end

---------------------------------------------------------------------------
-- Visuals
---------------------------------------------------------------------------

local function resetPenVisual(worldPen: WorldBuilder.Pen)
	worldPen.floor.Color = LOCKED_FLOOR
	worldPen.floor.Material = Enum.Material.Concrete
	worldPen.troughFill.Transparency = 1
	worldPen.statusLabel.Text = ""
end

local function setTroughFill(pen: Pen, fraction: number)
	local fill = pen.world.troughFill
	if fraction <= 0 then
		fill.Transparency = 1
		return
	end
	fill.Transparency = 0
	-- Grow the fill upward from the bottom of the trough.
	local height = 0.1 + 0.7 * math.clamp(fraction, 0, 1)
	local trough = pen.world.trough
	fill.Size = Vector3.new(fill.Size.X, height, fill.Size.Z)
	fill.CFrame = trough.CFrame * CFrame.new(0, -trough.Size.Y / 2 + 0.1 + height / 2, 0)
	local food = if pen.storeFood then pen.storeFood else ""
	fill.Color = if food == "Fish"
		then Color3.fromRGB(120, 170, 210)
		elseif food == "Meat" then Color3.fromRGB(190, 80, 80)
		elseif food == "Melon" then Color3.fromRGB(90, 160, 70)
		elseif food == "Carrot" then Color3.fromRGB(240, 140, 40)
		else Color3.fromRGB(200, 180, 60)
end

local function refreshPenVisual(zoo: Zoo, pen: Pen)
	local world = pen.world
	if not pen.unlocked then
		world.floor.Color = LOCKED_FLOOR
		world.floor.Material = Enum.Material.Concrete
		world.troughFill.Transparency = 1
		world.statusLabel.Text = "🔒 Unlock: " .. formatNumber(Config.getPenPrice(pen.index)) .. " coins"
		return
	end

	local capacity = storeCapacity(zoo)
	setTroughFill(pen, pen.storeAmount / capacity)

	local species = penSpecies(pen)
	if not species then
		world.floor.Color = EMPTY_FLOOR
		world.floor.Material = Enum.Material.Grass
		world.statusLabel.Text = "Empty pen — buy an animal!"
		return
	end

	world.floor.Color = species.habitat
	world.floor.Material = species.habitatMaterial

	local starving, hungry = 0, 0
	for _, animal in pen.animals do
		if animal.hunger <= 0 then
			starving += 1
		elseif animal.hunger <= Config.EatThreshold then
			hungry += 1
		end
	end

	local food = Config.FoodById[species.food]
	local text = string.format(
		"%s ×%d  %s %d/%d",
		species.name,
		#pen.animals,
		food.emoji,
		math.floor(pen.storeAmount),
		capacity
	)
	if starving > 0 then
		text ..= "  ⚠️ Starving!"
	elseif hungry > 0 and pen.storeAmount < 1 then
		text ..= "  🍽️ Needs food"
	end
	world.statusLabel.Text = text
end

---------------------------------------------------------------------------
-- Animals
---------------------------------------------------------------------------

local function randomPointInPen(pen: Pen, species: Species): Vector3
	-- Keep big animals away from the fence.
	local margin = math.max(2.5, species.visual.bodySize.Z / 2 + 1.5)
	local half = Config.PenSize / 2 - margin
	local offset = Vector3.new((math.random() * 2 - 1) * half, 0, (math.random() * 2 - 1) * half)
	return pen.world.center:PointToWorldSpace(offset)
end

local function animalSpeed(animal: Animal): number
	local speed = animal.species.speed * Config.StageScale[animal.stage]
	if animal.hunger <= 0 then
		speed *= 0.4
	end
	return math.max(1, speed)
end

local function updateMarker(animal: Animal)
	local marker = animal.marker
	marker:SetAttribute("Stage", animal.stage)
	marker:SetAttribute("Hungry", animal.hunger <= 0)
	-- Rounded so the attribute only replicates when it visibly changes.
	marker:SetAttribute("Health", math.ceil(animal.health / Config.HealthMax * 20) / 20)
end

local function spawnAnimal(
	pen: Pen,
	speciesId: string,
	growth: number,
	hunger: number,
	health: number,
	near: Vector3?
): Animal
	local species = Config.SpeciesById[speciesId]
	local position = near or randomPointInPen(pen, species)

	local marker = Instance.new("Configuration")
	marker.Name = species.name
	local animal: Animal = {
		id = HttpService:GenerateGUID(false),
		species = species,
		growth = growth,
		hunger = hunger,
		health = health,
		stage = Config.getStage(species, growth),
		marker = marker,
		position = position,
		nextMoveAt = os.clock() + math.random() * 3,
		warnedStarving = false,
	}
	marker:SetAttribute("Species", species.id)
	marker:SetAttribute("Target", position)
	marker:SetAttribute("Speed", animalSpeed(animal))
	updateMarker(animal)
	CollectionService:AddTag(marker, "ZooAnimal")
	marker.Parent = pen.world.animalsFolder

	table.insert(pen.animals, animal)
	return animal
end

local function removeAnimal(pen: Pen, animal: Animal)
	local index = table.find(pen.animals, animal)
	if index then
		table.remove(pen.animals, index)
	end
	animal.marker:Destroy()
end

local function wander(pen: Pen, animal: Animal, now: number)
	if now < animal.nextMoveAt then
		return
	end
	local target = randomPointInPen(pen, animal.species)
	local speed = animalSpeed(animal)
	local travelTime = (target - animal.position).Magnitude / speed
	animal.position = target
	animal.nextMoveAt = now + travelTime + 1 + math.random() * 4
	animal.marker:SetAttribute("Speed", speed)
	animal.marker:SetAttribute("Target", target)
end

---------------------------------------------------------------------------
-- Simulation
---------------------------------------------------------------------------

local function discover(zoo: Zoo, species: Species)
	if zoo.discovered[species.id] then
		return
	end
	zoo.discovered[species.id] = true
	local reward = species.price * Config.DiscoveryRewardMultiplier
	zoo.coins += reward
	notify(
		zoo.player,
		string.format("📖 New in your Zoo Book: %s! +%s coins", species.name, formatNumber(reward)),
		"success"
	)

	local count = 0
	for _ in zoo.discovered do
		count += 1
	end
	if count == #Config.Species then
		notify(zoo.player, "🏆 You raised every animal! Your Zoo Book is complete!", "success")
	end
end

-- Animals eat from the pen's food store when they get hungry.
local function eat(pen: Pen, animal: Animal)
	if animal.hunger > Config.EatThreshold or pen.storeAmount <= 0 then
		return
	end
	if pen.storeFood ~= animal.species.food then
		return
	end
	local meal = animal.species.mealSize
	local eaten = math.min(meal, pen.storeAmount)
	pen.storeAmount -= eaten
	if pen.storeAmount < 0.001 then
		pen.storeAmount = 0
	end
	animal.hunger = math.min(Config.HungerMax, animal.hunger + Config.HungerMax * eaten / meal)
end

local function tickZoo(zoo: Zoo, dt: number, now: number)
	local income = 0
	for _, pen in zoo.pens do
		local adults = 0
		local totalHunger = 0
		local dead: { Animal } = {}

		for _, animal in pen.animals do
			local species = animal.species
			local wasHungry = animal.hunger <= 0
			local oldHealthKey = math.ceil(animal.health / Config.HealthMax * 20)

			animal.hunger = math.max(0, animal.hunger - Config.HungerDrainPerSecond * dt)
			eat(pen, animal)

			if animal.hunger > 0 then
				-- Fed: grow, earn and heal.
				if animal.growth < species.growTime then
					local rate = if animal.hunger >= Config.WellFedThreshold then 1 else 0.5
					animal.growth = math.min(species.growTime, animal.growth + dt * rate)
				else
					income += species.income * dt
				end
				animal.health = math.min(Config.HealthMax, animal.health + Config.HealthRegenPerSecond * dt)
				if animal.health >= Config.HealthMax * 0.75 then
					animal.warnedStarving = false
				end
			else
				-- Starving: lose health.
				animal.health = math.max(0, animal.health - Config.StarveDamagePerSecond * dt)
				if not animal.warnedStarving and animal.health <= Config.HealthMax * 0.5 then
					animal.warnedStarving = true
					notify(
						zoo.player,
						string.format("⚠️ Your %s in pen %d is starving! Bring it food fast!", species.name, pen.index),
						"error"
					)
				end
			end

			if animal.health <= 0 then
				table.insert(dead, animal)
				continue
			end
			totalHunger += animal.hunger

			local isHungry = animal.hunger <= 0
			local stage = Config.getStage(species, animal.growth)
			local healthKey = math.ceil(animal.health / Config.HealthMax * 20)
			if stage ~= animal.stage or wasHungry ~= isHungry or healthKey ~= oldHealthKey then
				local grewUp = stage ~= animal.stage and stage == "Adult"
				animal.stage = stage
				updateMarker(animal)
				if grewUp then
					discover(zoo, species)
				end
				if isHungry and not wasHungry then
					notify(
						zoo.player,
						string.format("🍽️ Your %s in pen %d is out of food!", species.name, pen.index),
						"warning"
					)
				end
			end

			if animal.stage == "Adult" then
				adults += 1
			end
			wander(pen, animal, now)
		end

		for _, animal in dead do
			removeAnimal(pen, animal)
			notify(
				zoo.player,
				string.format("💀 Your %s in pen %d starved to death.", animal.species.name, pen.index),
				"error"
			)
		end

		-- Breeding: two well-fed adults and a free spot can produce a baby.
		pen.breedCooldown = math.max(0, pen.breedCooldown - dt)
		local species = penSpecies(pen)
		if
			species
			and adults >= 2
			and #pen.animals < Config.PenCapacity
			and pen.breedCooldown <= 0
			and totalHunger / #pen.animals >= Config.BreedMinHunger
			and math.random() < Config.BreedChancePerSecond * dt
		then
			pen.breedCooldown = Config.BreedCooldown
			local parent = pen.animals[math.random(1, #pen.animals)]
			spawnAnimal(pen, species.id, 0, Config.HungerMax, Config.HealthMax, parent.position)
			notify(zoo.player, string.format("🍼 A baby %s was born in pen %d!", species.name, pen.index), "success")
		end

		refreshPenVisual(zoo, pen)
	end
	zoo.coins += income
end

---------------------------------------------------------------------------
-- Player actions
---------------------------------------------------------------------------

local function getPen(zoo: Zoo, penIndex: any): Pen?
	if type(penIndex) ~= "number" or penIndex ~= math.floor(penIndex) then
		return nil
	end
	return zoo.pens[penIndex]
end

local function spend(zoo: Zoo, amount: number): boolean
	if zoo.coins < amount then
		notify(zoo.player, "Not enough coins! You need " .. formatNumber(amount) .. ".", "error")
		return false
	end
	zoo.coins -= amount
	return true
end

local function isNearPen(zoo: Zoo, pen: Pen): boolean
	local character = zoo.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - pen.world.sign.Position).Magnitude <= Config.StockDistance
end

local actions: { [string]: (zoo: Zoo, ...any) -> () } = {}

function actions.UnlockPen(zoo: Zoo, penIndex: any)
	local pen = getPen(zoo, penIndex)
	if not pen or pen.unlocked then
		return
	end
	if spend(zoo, Config.getPenPrice(pen.index)) then
		pen.unlocked = true
		refreshPenVisual(zoo, pen)
		notify(zoo.player, string.format("🔓 Pen %d unlocked!", pen.index), "success")
	end
end

function actions.BuyAnimal(zoo: Zoo, penIndex: any, speciesId: any)
	local pen = getPen(zoo, penIndex)
	local species = if type(speciesId) == "string" then Config.SpeciesById[speciesId] else nil
	if not pen or not species or not pen.unlocked then
		return
	end
	local current = penSpecies(pen)
	if current and current ~= species then
		notify(zoo.player, "Each pen can only hold one kind of animal.", "error")
		return
	end
	if #pen.animals >= Config.PenCapacity then
		notify(zoo.player, "This pen is full!", "error")
		return
	end
	if spend(zoo, species.price) then
		if pen.storeFood ~= species.food then
			if pen.storeFood and pen.storeAmount >= 1 then
				local old = Config.FoodById[pen.storeFood]
				notify(zoo.player, string.format("The old %s in this pen's store went to waste.", old.name), "warning")
			end
			pen.storeFood = species.food
			pen.storeAmount = 0
		end
		spawnAnimal(pen, species.id, 0, Config.HungerMax, Config.HealthMax)
		refreshPenVisual(zoo, pen)
		local food = Config.FoodById[species.food]
		notify(
			zoo.player,
			string.format("🐾 A baby %s joined pen %d! It eats %s %s.", species.name, pen.index, food.emoji, food.name),
			"success"
		)
	end
end

function actions.StockPen(zoo: Zoo, penIndex: any)
	local pen = getPen(zoo, penIndex)
	if not pen or not pen.unlocked then
		return
	end
	local species = penSpecies(pen)
	if not species then
		notify(zoo.player, "Buy an animal first so you know what food to store.", "info")
		return
	end
	if not isNearPen(zoo, pen) then
		notify(zoo.player, "Walk up to the pen's sign to fill its food store.", "error")
		return
	end
	local food = Config.FoodById[species.food]
	local have = zoo.inventory[food.id] or 0
	if have <= 0 then
		notify(
			zoo.player,
			string.format(
				"You have no %s %s. Forage it in the %s!",
				food.emoji,
				food.name,
				Config.Rings[food.ring].name
			),
			"error"
		)
		return
	end
	pen.storeFood = food.id
	local space = math.floor(storeCapacity(zoo) - pen.storeAmount)
	if space <= 0 then
		notify(zoo.player, "This pen's food store is full!", "info")
		return
	end
	local amount = math.min(have, space)
	pen.storeAmount += amount
	if have - amount > 0 then
		zoo.inventory[food.id] = have - amount
	else
		zoo.inventory[food.id] = nil
	end
	refreshPenVisual(zoo, pen)
	notify(zoo.player, string.format("Stored %d %s %s in pen %d.", amount, food.emoji, food.name, pen.index), "success")
end

function actions.SellAnimal(zoo: Zoo, penIndex: any, animalId: any)
	local pen = getPen(zoo, penIndex)
	if not pen or type(animalId) ~= "string" then
		return
	end
	for _, animal in pen.animals do
		if animal.id == animalId then
			local price = Config.getSellPrice(animal.species, animal.growth)
			zoo.coins += price
			removeAnimal(pen, animal)
			refreshPenVisual(zoo, pen)
			notify(
				zoo.player,
				string.format("💰 Sold a %s for %s coins.", animal.species.name, formatNumber(price)),
				"success"
			)
			return
		end
	end
end

function actions.DropFood(zoo: Zoo, foodId: any)
	if type(foodId) ~= "string" or not zoo.inventory[foodId] then
		return
	end
	zoo.inventory[foodId] = nil
	local food = Config.FoodById[foodId]
	if food then
		notify(zoo.player, string.format("Dropped your %s %s.", food.emoji, food.name), "info")
	end
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

-- Boots set how fast the player walks.
local function applyWalkSpeed(zoo: Zoo)
	local character = zoo.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Config.getEquipmentValue("Boots", zoo.equipment.Boots or 0)
	end
end

local function teleportToPlot(zoo: Zoo, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root and zoos[zoo.player] == zoo then
		task.wait(0.2) -- let the default spawn finish first
		character:PivotTo(zoo.plot.entrance)
		applyWalkSpeed(zoo)
	end
end

local function claimPlot(player: Player): WorldBuilder.Plot?
	for index, plot in plots do
		if not plotOwners[index] then
			plotOwners[index] = player
			return plot
		end
	end
	return nil
end

local function releasePlot(zoo: Zoo)
	for _, pen in zoo.pens do
		for _, animal in table.clone(pen.animals) do
			removeAnimal(pen, animal)
		end
		resetPenVisual(pen.world)
		pen.world.prompt:SetAttribute("OwnerUserId", 0)
	end
	WorldBuilder.setOwnerName(zoo.plot, "Empty Zoo")
	plotOwners[zoo.plot.index] = nil
end

local function onPlayerAdded(player: Player)
	local plot = claimPlot(player)
	if not plot then
		task.delay(3, function()
			if player.Parent then
				notify(player, "All zoos are taken on this server. Try another server!", "error")
			end
		end)
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coinsValue = Instance.new("IntValue")
	coinsValue.Name = "Coins"
	coinsValue.Parent = leaderstats
	local ratingValue = Instance.new("IntValue")
	ratingValue.Name = "Rating"
	ratingValue.Parent = leaderstats
	leaderstats.Parent = player

	local pens: { Pen } = {}
	for i, worldPen in plot.pens do
		table.insert(pens, {
			index = i,
			unlocked = false,
			animals = {},
			breedCooldown = 0,
			storeFood = nil,
			storeAmount = 0,
			world = worldPen,
		})
		worldPen.prompt:SetAttribute("OwnerUserId", player.UserId)
	end

	local zoo: Zoo = {
		player = player,
		plot = plot,
		coins = 0,
		pens = pens,
		discovered = {},
		inventory = {},
		equipment = {},
		canSave = false,
		loaded = false,
		lastActionAt = 0,
		coinsValue = coinsValue,
		ratingValue = ratingValue,
	}
	zoos[player] = zoo
	WorldBuilder.setOwnerName(plot, player.DisplayName .. "'s Zoo")

	player.CharacterAdded:Connect(function(character)
		teleportToPlot(zoo, character)
	end)
	if player.Character then
		task.spawn(teleportToPlot, zoo, player.Character)
	end

	local data, canSave = DataService.load(player)
	if zoos[player] ~= zoo then
		return -- left while loading
	end

	zoo.coins = data.coins
	zoo.discovered = data.discovered
	zoo.inventory = data.inventory
	zoo.equipment = data.equipment
	zoo.canSave = canSave
	for i, savedPen in data.pens do
		local pen = pens[i]
		if pen then
			pen.unlocked = savedPen.unlocked
			pen.storeFood = savedPen.storeFood
			pen.storeAmount = savedPen.storeAmount
			for _, saved in savedPen.animals do
				spawnAnimal(pen, saved.species, saved.growth, saved.hunger, saved.health)
			end
			-- Older saves have no store yet: match it to the animals.
			local species = penSpecies(pen)
			if species and pen.storeFood ~= species.food then
				pen.storeFood = species.food
				pen.storeAmount = 0
			end
			refreshPenVisual(zoo, pen)
		end
	end
	zoo.loaded = true
	applyWalkSpeed(zoo)
	pushState(zoo)

	if not canSave then
		notify(player, "Saving is off in this session, so progress won't be kept.", "warning")
	end
end

local function saveZoo(zoo: Zoo)
	if zoo.canSave and zoo.loaded then
		DataService.save(zoo.player, serialize(zoo))
	end
end

local function onPlayerRemoving(player: Player)
	local zoo = zoos[player]
	if not zoo then
		return
	end
	zoos[player] = nil
	saveZoo(zoo)
	releasePlot(zoo)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

local function createRemotes()
	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	local function remote(name: string): RemoteEvent
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = remotes
		return event
	end
	stateUpdate = remote("StateUpdate")
	openPen = remote("OpenPen")
	notifyEvent = remote("Notify")
	actionEvent = remote("Action")
	remotes.Parent = ReplicatedStorage
end

function ZooService.start()
	createRemotes()
	WorldBuilder.buildEnvironment()

	for i = 1, Config.MaxPlots do
		local plot = WorldBuilder.buildPlot(i)
		table.insert(plots, plot)
		for penIndex, worldPen in plot.pens do
			resetPenVisual(worldPen)
			worldPen.prompt:SetAttribute("OwnerUserId", 0)
			CollectionService:AddTag(worldPen.prompt, "PenPrompt")
			worldPen.prompt.Triggered:Connect(function(player)
				local zoo = zoos[player]
				if zoo and zoo.loaded and zoo.plot == plot then
					openPen:FireClient(player, penIndex)
				else
					local owner = plotOwners[i]
					notify(player, if owner then "This is " .. owner.DisplayName .. "'s zoo!" else "This zoo is empty.", "info")
				end
			end)
		end
	end

	-- Foraging and chests live in their own module and talk to zoos through this.
	ForageService.start({
		getZoo = function(player: Player): any
			local zoo = zoos[player]
			return if zoo and zoo.loaded then zoo else nil
		end,
		carried = function(zoo: any): number
			return carried(zoo)
		end,
		capacity = function(zoo: any): number
			return backpackCapacity(zoo)
		end,
		changed = function(zoo: any)
			applyWalkSpeed(zoo)
			-- Pantry upgrades change every pen's store size.
			for _, pen in (zoo :: Zoo).pens do
				refreshPenVisual(zoo, pen)
			end
			pushState(zoo)
		end,
		notify = notify,
	})

	actionEvent.OnServerEvent:Connect(function(player, actionName, ...)
		local zoo = zoos[player]
		if not zoo or not zoo.loaded or type(actionName) ~= "string" then
			return
		end
		local handler = actions[actionName]
		if not handler then
			return
		end
		local now = os.clock()
		if now - zoo.lastActionAt < 0.15 then
			return
		end
		zoo.lastActionAt = now
		handler(zoo, ...)
		pushState(zoo)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Simulation tick.
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1)
			local now = os.clock()
			local dt = math.min(now - last, 5)
			last = now
			for _, zoo in zoos do
				if zoo.loaded then
					tickZoo(zoo, dt, now)
					pushState(zoo)
				end
			end
		end
	end)

	-- Autosave.
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for _, zoo in zoos do
				task.spawn(saveZoo, zoo)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for _, zoo in zoos do
			pending += 1
			task.spawn(function()
				saveZoo(zoo)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return ZooService
