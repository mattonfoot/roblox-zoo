--!strict
-- Core zoo logic: plots, pens, animals, feeding, growth, breeding, income and actions.
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
local WorldBuilder = require(script.Parent.WorldBuilder)

type Species = Config.Species

type Animal = {
	id: string,
	species: Species,
	growth: number,
	hunger: number,
	stage: string,
	marker: Configuration,
	position: Vector3, -- where the animal is heading (or resting)
	nextMoveAt: number,
}

type Pen = {
	index: number,
	unlocked: boolean,
	animals: { Animal },
	breedCooldown: number,
	world: WorldBuilder.Pen,
}

type Zoo = {
	player: Player,
	plot: WorldBuilder.Plot,
	coins: number,
	pens: { Pen },
	discovered: { [string]: boolean },
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

local remotes: Folder
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
			})
		end
		table.insert(pens, { unlocked = pen.unlocked, animals = animals })
	end
	return {
		version = 1,
		coins = math.floor(zoo.coins),
		pens = pens,
		discovered = table.clone(zoo.discovered),
	}
end

local function penSpecies(pen: Pen): Species?
	local first = pen.animals[1]
	return if first then first.species else nil
end

local function buildClientState(zoo: Zoo)
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
				sellPrice = Config.getSellPrice(animal.species, animal.growth),
			})
		end
		local species = penSpecies(pen)
		table.insert(pens, {
			unlocked = pen.unlocked,
			price = Config.getPenPrice(pen.index),
			species = if species then species.id else nil,
			animals = animals,
		})
	end
	return {
		coins = math.floor(zoo.coins),
		rating = computeRating(zoo),
		discovered = zoo.discovered,
		pens = pens,
	}
end

local function pushState(zoo: Zoo)
	if not zoo.loaded then
		return
	end
	local rating = computeRating(zoo)
	zoo.coinsValue.Value = math.floor(zoo.coins)
	zoo.ratingValue.Value = rating
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

local function refreshPenVisual(pen: Pen)
	local world = pen.world
	if not pen.unlocked then
		world.floor.Color = LOCKED_FLOOR
		world.floor.Material = Enum.Material.Concrete
		world.troughFill.Transparency = 1
		world.statusLabel.Text = "🔒 Unlock: " .. formatNumber(Config.getPenPrice(pen.index)) .. " coins"
		return
	end

	local species = penSpecies(pen)
	if not species then
		world.floor.Color = EMPTY_FLOOR
		world.floor.Material = Enum.Material.Grass
		world.troughFill.Transparency = 1
		world.statusLabel.Text = "Empty pen — buy an animal!"
		return
	end

	world.floor.Color = species.habitat
	world.floor.Material = species.habitatMaterial

	local hungry = 0
	local totalHunger = 0
	for _, animal in pen.animals do
		totalHunger += animal.hunger
		if animal.hunger <= 0 then
			hungry += 1
		end
	end
	world.troughFill.Transparency = if totalHunger > 0 then 0 else 1

	local text = string.format("%s ×%d", species.name, #pen.animals)
	if hungry > 0 then
		text ..= "  🍖 Hungry!"
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
end

local function spawnAnimal(pen: Pen, speciesId: string, growth: number, hunger: number, near: Vector3?): Animal
	local species = Config.SpeciesById[speciesId]
	local position = near or randomPointInPen(pen, species)

	local marker = Instance.new("Configuration")
	marker.Name = species.name
	local animal: Animal = {
		id = HttpService:GenerateGUID(false),
		species = species,
		growth = growth,
		hunger = hunger,
		stage = Config.getStage(species, growth),
		marker = marker,
		position = position,
		nextMoveAt = os.clock() + math.random() * 3,
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

local function tickZoo(zoo: Zoo, dt: number, now: number)
	local income = 0
	for _, pen in zoo.pens do
		local adults = 0
		local totalHunger = 0
		for _, animal in pen.animals do
			local species = animal.species
			if animal.hunger > 0 then
				if animal.growth < species.growTime then
					local rate = if animal.hunger >= Config.WellFedThreshold then 1 else 0.5
					animal.growth = math.min(species.growTime, animal.growth + dt * rate)
				else
					income += species.income * dt
				end
			end

			local wasHungry = animal.hunger <= 0
			animal.hunger = math.max(0, animal.hunger - Config.HungerDrainPerSecond * dt)
			totalHunger += animal.hunger

			local stage = Config.getStage(species, animal.growth)
			if stage ~= animal.stage then
				animal.stage = stage
				updateMarker(animal)
				if stage == "Adult" then
					discover(zoo, species)
				end
			elseif wasHungry ~= (animal.hunger <= 0) then
				updateMarker(animal)
				if animal.hunger <= 0 then
					notify(zoo.player, string.format("🍖 Your %s in pen %d is hungry!", species.name, pen.index), "warning")
				end
			end

			if animal.stage == "Adult" then
				adults += 1
			end
			wander(pen, animal, now)
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
			spawnAnimal(pen, species.id, 0, Config.HungerMax, parent.position)
			notify(zoo.player, string.format("🍼 A baby %s was born in pen %d!", species.name, pen.index), "success")
		end

		refreshPenVisual(pen)
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

local function feedCost(pen: Pen): number
	local cost = 0
	for _, animal in pen.animals do
		if animal.hunger < Config.HungerMax - 1 then
			cost += animal.species.feedCost
		end
	end
	return cost
end

local function feedPen(pen: Pen)
	for _, animal in pen.animals do
		local wasHungry = animal.hunger <= 0
		animal.hunger = Config.HungerMax
		if wasHungry then
			updateMarker(animal)
		end
	end
	refreshPenVisual(pen)
end

local actions: { [string]: (zoo: Zoo, ...any) -> () } = {}

function actions.UnlockPen(zoo: Zoo, penIndex: any)
	local pen = getPen(zoo, penIndex)
	if not pen or pen.unlocked then
		return
	end
	if spend(zoo, Config.getPenPrice(pen.index)) then
		pen.unlocked = true
		refreshPenVisual(pen)
		notify(zoo.player, string.format("🔓 Pen %d unlocked!", pen.index), "success")
	end
end

function actions.BuyAnimal(zoo: Zoo, penIndex: any, speciesId: any)
	local pen = getPen(zoo, penIndex)
	local species = type(speciesId) == "string" and Config.SpeciesById[speciesId] or nil
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
		spawnAnimal(pen, species.id, 0, Config.HungerMax)
		refreshPenVisual(pen)
		notify(zoo.player, string.format("🐾 A baby %s joined pen %d!", species.name, pen.index), "success")
	end
end

function actions.FeedPen(zoo: Zoo, penIndex: any)
	local pen = getPen(zoo, penIndex)
	if not pen or #pen.animals == 0 then
		return
	end
	local cost = feedCost(pen)
	if cost == 0 then
		notify(zoo.player, "They're already full!", "info")
		return
	end
	if spend(zoo, cost) then
		feedPen(pen)
		notify(zoo.player, string.format("🥕 Fed pen %d for %s coins.", pen.index, formatNumber(cost)), "success")
	end
end

function actions.FeedAll(zoo: Zoo)
	local fed, spent, skipped = 0, 0, 0
	for _, pen in zoo.pens do
		local cost = feedCost(pen)
		if cost > 0 then
			if zoo.coins >= cost then
				zoo.coins -= cost
				spent += cost
				fed += 1
				feedPen(pen)
			else
				skipped += 1
			end
		end
	end
	if fed == 0 and skipped == 0 then
		notify(zoo.player, "Everyone is already full!", "info")
	elseif skipped > 0 then
		notify(zoo.player, string.format("Fed %d pens. Not enough coins for %d more.", fed, skipped), "warning")
	else
		notify(zoo.player, string.format("🥕 Fed %d pens for %s coins.", fed, formatNumber(spent)), "success")
	end
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
			refreshPenVisual(pen)
			notify(
				zoo.player,
				string.format("💰 Sold a %s for %s coins.", animal.species.name, formatNumber(price)),
				"success"
			)
			return
		end
	end
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

local function teleportToPlot(zoo: Zoo, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root and zoos[zoo.player] == zoo then
		task.wait(0.2) -- let the default spawn finish first
		character:PivotTo(zoo.plot.entrance)
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
	zoo.canSave = canSave
	for i, savedPen in data.pens do
		local pen = pens[i]
		if pen then
			pen.unlocked = savedPen.unlocked
			for _, saved in savedPen.animals do
				spawnAnimal(pen, saved.species, saved.growth, saved.hunger)
			end
			refreshPenVisual(pen)
		end
	end
	zoo.loaded = true
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
	remotes = Instance.new("Folder")
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
