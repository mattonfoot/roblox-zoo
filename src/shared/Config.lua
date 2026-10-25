--!strict
-- Game balance and definitions shared by server and client.

export type Visual = {
	shape: string, -- "quadruped" or "biped"
	bodyColor: Color3,
	headColor: Color3,
	legColor: Color3,
	bodySize: Vector3,
	headSize: Vector3,
	legLength: number,
	extras: { string },
}

export type Species = {
	id: string,
	name: string,
	price: number, -- cost to buy a baby
	food: string, -- id of the food it eats
	mealSize: number, -- food units eaten per meal
	growTime: number, -- seconds of being fed needed to reach adult
	income: number, -- coins per second from visitors, adults only
	sellPrice: number, -- what an adult sells for
	rating: number, -- zoo rating each adult adds
	speed: number, -- wander speed in studs/second
	habitat: Color3, -- pen floor colour
	habitatMaterial: Enum.Material,
	visual: Visual,
}

export type Food = {
	id: string,
	name: string,
	emoji: string,
	ring: number, -- which wild ring it grows in (further = rarer)
	yield: number, -- units gathered per forage
	harvestTime: number, -- seconds to forage with basic gloves
}

export type Ring = {
	name: string,
	inner: number, -- distance from the centre of the map
	outer: number,
	color: Color3,
	material: Enum.Material,
}

export type Equipment = {
	id: string,
	name: string,
	emoji: string,
	description: string,
	tierNames: { string },
	values: { number }, -- value at level 0, 1, 2, ... (index = level + 1)
}

local Config = {}

Config.StartingCoins = 150
Config.PenCapacity = 3
Config.PenSize = 24
Config.PenPrices = { 0, 0, 200, 500, 1200, 3000, 7000, 15000 }
Config.MaxPlots = 6

-- Hunger and health
Config.HungerMax = 100
Config.HungerDrainPerSecond = 100 / 240 -- a full belly lasts four minutes
Config.EatThreshold = 40 -- animals eat from the pen's food store below this
Config.WellFedThreshold = 50 -- below this, animals grow at half speed
Config.HealthMax = 100
Config.StarveDamagePerSecond = 100 / 90 -- a starving animal dies after 90 seconds
Config.HealthRegenPerSecond = 2

Config.BabyStageEnd = 0.4 -- growth fraction where a baby becomes a juvenile
Config.StageScale = { Baby = 0.45, Juvenile = 0.7, Adult = 1 }

Config.BreedCooldown = 60 -- seconds between births in one pen
Config.BreedChancePerSecond = 1 / 20
Config.BreedMinHunger = 30

Config.DiscoveryRewardMultiplier = 2 -- first adult of a species pays price * this
Config.DiscoveryRating = 5 -- rating per species in the Zoo Book
Config.BabySellFraction = 0.5 -- non-adults sell for this share of their price

Config.AutosaveInterval = 60

-- Foraging
Config.StockDistance = 20 -- how close to a pen sign you must be to stock it
Config.NodesPerFood = 8
Config.NodeRegrowTime = 20
Config.ChestsPerRing = { 4, 3, 3, 2 }
Config.ChestRespawnTime = 45
Config.ChestCoinRewards = { 60, 200, 600, 1500 } -- when a chest has no upgrade left for you

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Wild areas around the zoo. Rarer food grows further out.
Config.Rings = {
	{ name = "Meadow", inner = 200, outer = 300, color = rgb(140, 195, 95), material = Enum.Material.Grass },
	{ name = "Plains", inner = 300, outer = 420, color = rgb(195, 185, 105), material = Enum.Material.Grass },
	{ name = "Forest", inner = 420, outer = 560, color = rgb(60, 115, 55), material = Enum.Material.LeafyGrass },
	{ name = "Savanna", inner = 560, outer = 720, color = rgb(210, 165, 95), material = Enum.Material.Sand },
} :: { Ring }

Config.Foods = {
	{ id = "Carrot", name = "Carrots", emoji = "🥕", ring = 1, yield = 5, harvestTime = 2 },
	{ id = "Fish", name = "Fish", emoji = "🐟", ring = 1, yield = 5, harvestTime = 2.5 },
	{ id = "Hay", name = "Hay", emoji = "🌾", ring = 2, yield = 6, harvestTime = 3 },
	{ id = "Bamboo", name = "Bamboo", emoji = "🎋", ring = 3, yield = 8, harvestTime = 3.5 },
	{ id = "Meat", name = "Meat", emoji = "🥩", ring = 3, yield = 8, harvestTime = 3.5 },
	{ id = "Leaves", name = "Acacia Leaves", emoji = "🌿", ring = 4, yield = 10, harvestTime = 4 },
	{ id = "Melon", name = "Melons", emoji = "🍉", ring = 4, yield = 10, harvestTime = 4 },
} :: { Food }

Config.FoodById = {} :: { [string]: Food }
for _, food in Config.Foods do
	Config.FoodById[food.id] = food
end

-- Equipment found in chests. Level 0 is what you start with.
Config.Equipment = {
	{
		id = "Gloves",
		name = "Gloves",
		emoji = "🧤",
		description = "Forage faster",
		tierNames = { "Bare Hands", "Work Gloves", "Sturdy Gloves", "Expert Gloves", "Legendary Gloves" },
		values = { 1, 0.75, 0.55, 0.4, 0.3 }, -- foraging time multiplier
	},
	{
		id = "Backpack",
		name = "Backpack",
		emoji = "🎒",
		description = "Carry more food",
		tierNames = { "Small Pouch", "Satchel", "Backpack", "Explorer Pack", "Legendary Pack" },
		values = { 15, 25, 40, 60, 90 }, -- food units you can carry
	},
	{
		id = "Pantry",
		name = "Pantry",
		emoji = "🏠",
		description = "Bigger pen food stores",
		tierNames = { "Small Bin", "Crate", "Pantry", "Storehouse", "Legendary Silo" },
		values = { 30, 50, 80, 120, 180 }, -- food units each pen can store
	},
} :: { Equipment }

Config.EquipmentById = {} :: { [string]: Equipment }
for _, equipment in Config.Equipment do
	Config.EquipmentById[equipment.id] = equipment
end

Config.MaxEquipmentLevel = 4

Config.Species = {
	{
		id = "Rabbit",
		name = "Rabbit",
		price = 40,
		food = "Carrot",
		mealSize = 1,
		growTime = 45,
		income = 1,
		sellPrice = 90,
		rating = 1,
		speed = 6,
		habitat = rgb(106, 170, 78),
		habitatMaterial = Enum.Material.Grass,
		visual = {
			shape = "quadruped",
			bodyColor = rgb(235, 225, 215),
			headColor = rgb(240, 232, 222),
			legColor = rgb(225, 215, 205),
			bodySize = Vector3.new(1.6, 1.4, 2.2),
			headSize = Vector3.new(1.2, 1.2, 1.2),
			legLength = 0.5,
			extras = { "longEars", "puffTail" },
		},
	},
	{
		id = "Penguin",
		name = "Penguin",
		price = 120,
		food = "Fish",
		mealSize = 1,
		growTime = 75,
		income = 3,
		sellPrice = 260,
		rating = 2,
		speed = 3,
		habitat = rgb(215, 235, 245),
		habitatMaterial = Enum.Material.Ice,
		visual = {
			shape = "biped",
			bodyColor = rgb(30, 30, 35),
			headColor = rgb(30, 30, 35),
			legColor = rgb(245, 160, 40),
			bodySize = Vector3.new(1.6, 2.4, 1.4),
			headSize = Vector3.new(1.1, 1.1, 1.1),
			legLength = 0.3,
			extras = { "whiteBelly", "beak", "flippers" },
		},
	},
	{
		id = "Goat",
		name = "Goat",
		price = 300,
		food = "Hay",
		mealSize = 2,
		growTime = 100,
		income = 6,
		sellPrice = 600,
		rating = 4,
		speed = 5,
		habitat = rgb(140, 135, 120),
		habitatMaterial = Enum.Material.Slate,
		visual = {
			shape = "quadruped",
			bodyColor = rgb(200, 190, 170),
			headColor = rgb(210, 200, 180),
			legColor = rgb(170, 160, 140),
			bodySize = Vector3.new(1.8, 1.8, 3.2),
			headSize = Vector3.new(1.1, 1.3, 1.5),
			legLength = 1.6,
			extras = { "horns", "beard" },
		},
	},
	{
		id = "Zebra",
		name = "Zebra",
		price = 700,
		food = "Hay",
		mealSize = 2,
		growTime = 140,
		income = 12,
		sellPrice = 1400,
		rating = 7,
		speed = 7,
		habitat = rgb(205, 185, 120),
		habitatMaterial = Enum.Material.Sand,
		visual = {
			shape = "quadruped",
			bodyColor = rgb(245, 245, 245),
			headColor = rgb(245, 245, 245),
			legColor = rgb(240, 240, 240),
			bodySize = Vector3.new(2.2, 2.2, 4.2),
			headSize = Vector3.new(1.2, 1.4, 2.0),
			legLength = 2.4,
			extras = { "stripes", "mane" },
		},
	},
	{
		id = "Panda",
		name = "Panda",
		price = 1500,
		food = "Bamboo",
		mealSize = 3,
		growTime = 180,
		income = 25,
		sellPrice = 3000,
		rating = 11,
		speed = 2.5,
		habitat = rgb(80, 150, 70),
		habitatMaterial = Enum.Material.LeafyGrass,
		visual = {
			shape = "quadruped",
			bodyColor = rgb(245, 245, 245),
			headColor = rgb(245, 245, 245),
			legColor = rgb(25, 25, 25),
			bodySize = Vector3.new(3.0, 2.8, 3.8),
			headSize = Vector3.new(2.2, 2.0, 2.0),
			legLength = 1.2,
			extras = { "roundEars", "eyePatches" },
		},
	},
	{
		id = "Lion",
		name = "Lion",
		price = 3000,
		food = "Meat",
		mealSize = 3,
		growTime = 240,
		income = 45,
		sellPrice = 6000,
		rating = 16,
		speed = 6,
		habitat = rgb(215, 180, 100),
		habitatMaterial = Enum.Material.Sand,
		visual = {
			shape = "quadruped",
			bodyColor = rgb(215, 160, 80),
			headColor = rgb(225, 170, 90),
			legColor = rgb(205, 150, 70),
			bodySize = Vector3.new(2.4, 2.4, 4.4),
			headSize = Vector3.new(1.8, 1.8, 1.8),
			legLength = 2.0,
			extras = { "lionMane", "tail" },
		},
	},
	{
		id = "Giraffe",
		name = "Giraffe",
		price = 6000,
		food = "Leaves",
		mealSize = 4,
		growTime = 300,
		income = 80,
		sellPrice = 12000,
		rating = 22,
		speed = 4,
		habitat = rgb(190, 175, 110),
		habitatMaterial = Enum.Material.Ground,
		visual = {
			shape = "quadruped",
			bodyColor = rgb(230, 180, 90),
			headColor = rgb(230, 180, 90),
			legColor = rgb(220, 170, 85),
			bodySize = Vector3.new(2.4, 2.6, 4.0),
			headSize = Vector3.new(1.0, 1.2, 2.0),
			legLength = 4.0,
			extras = { "longNeck", "spots", "ossicones" },
		},
	},
	{
		id = "Elephant",
		name = "Elephant",
		price = 12000,
		food = "Melon",
		mealSize = 5,
		growTime = 360,
		income = 150,
		sellPrice = 24000,
		rating = 30,
		speed = 3,
		habitat = rgb(150, 115, 80),
		habitatMaterial = Enum.Material.Mud,
		visual = {
			shape = "quadruped",
			bodyColor = rgb(140, 140, 150),
			headColor = rgb(145, 145, 155),
			legColor = rgb(130, 130, 140),
			bodySize = Vector3.new(4.4, 4.0, 6.0),
			headSize = Vector3.new(2.8, 2.8, 2.4),
			legLength = 2.8,
			extras = { "trunk", "bigEars", "tusks" },
		},
	},
} :: { Species }

Config.SpeciesById = {} :: { [string]: Species }
for _, species in Config.Species do
	Config.SpeciesById[species.id] = species
end

function Config.getStage(species: Species, growth: number): string
	local fraction = growth / species.growTime
	if fraction >= 1 then
		return "Adult"
	elseif fraction >= Config.BabyStageEnd then
		return "Juvenile"
	end
	return "Baby"
end

function Config.getSellPrice(species: Species, growth: number): number
	if growth >= species.growTime then
		return species.sellPrice
	end
	return math.floor(species.price * Config.BabySellFraction)
end

function Config.getPenPrice(penIndex: number): number
	return Config.PenPrices[penIndex] or math.huge
end

function Config.getEquipmentValue(equipmentId: string, level: number): number
	local equipment = Config.EquipmentById[equipmentId]
	return equipment.values[math.clamp(level, 0, Config.MaxEquipmentLevel) + 1]
end

return Config
