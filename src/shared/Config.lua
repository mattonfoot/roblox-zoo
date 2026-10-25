--!strict
-- Game balance and animal definitions shared by server and client.

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
	feedCost: number, -- cost to feed one animal
	growTime: number, -- seconds of being fed needed to reach adult
	income: number, -- coins per second from visitors, adults only
	sellPrice: number, -- what an adult sells for
	rating: number, -- zoo rating each adult adds
	speed: number, -- wander speed in studs/second
	habitat: Color3, -- pen floor colour
	habitatMaterial: Enum.Material,
	visual: Visual,
}

local Config = {}

Config.StartingCoins = 150
Config.PenCapacity = 3
Config.PenSize = 24
Config.PenPrices = { 0, 0, 200, 500, 1200, 3000, 7000, 15000 }
Config.MaxPlots = 6

Config.HungerMax = 100
Config.HungerDrainPerSecond = 100 / 120 -- a full belly lasts two minutes
Config.WellFedThreshold = 50 -- below this, animals grow at half speed

Config.BabyStageEnd = 0.4 -- growth fraction where a baby becomes a juvenile
Config.StageScale = { Baby = 0.45, Juvenile = 0.7, Adult = 1 }

Config.BreedCooldown = 60 -- seconds between births in one pen
Config.BreedChancePerSecond = 1 / 20
Config.BreedMinHunger = 30

Config.DiscoveryRewardMultiplier = 2 -- first adult of a species pays price * this
Config.DiscoveryRating = 5 -- rating per species in the Zoo Book
Config.BabySellFraction = 0.5 -- non-adults sell for this share of their price

Config.AutosaveInterval = 60

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Config.Species = {
	{
		id = "Rabbit",
		name = "Rabbit",
		price = 40,
		feedCost = 3,
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
		feedCost = 6,
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
		feedCost = 10,
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
		feedCost = 20,
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
		feedCost = 35,
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
		feedCost = 60,
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
		feedCost = 100,
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
		feedCost = 180,
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

return Config
