--!strict
-- Loads and saves each player's zoo with DataStoreService.
-- If DataStores are unavailable (for example in Studio without API access),
-- the game still runs; progress just isn't saved.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type SavedAnimal = {
	species: string,
	growth: number,
	hunger: number,
	health: number,
}

export type SavedPen = {
	unlocked: boolean,
	animals: { SavedAnimal },
	storeFood: string?, -- which food the store holds
	storeAmount: number,
}

export type SaveData = {
	version: number,
	coins: number,
	pens: { SavedPen },
	discovered: { [string]: boolean },
	inventory: { [string]: number },
	equipment: { [string]: number },
}

local DataService = {}

local DATA_VERSION = 2
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("ZooTycoon_v1")
	end)
	if ok then
		store = result
	else
		warn("[Zoo] DataStore unavailable, progress will not be saved:", result)
	end
end

local function key(player: Player): string
	return "player_" .. player.UserId
end

function DataService.newData(): SaveData
	local pens = {}
	for i = 1, #Config.PenPrices do
		table.insert(pens, {
			unlocked = Config.getPenPrice(i) == 0,
			animals = {},
			storeFood = nil,
			storeAmount = 0,
		})
	end
	local equipment = {}
	for _, item in Config.Equipment do
		equipment[item.id] = 0
	end
	return {
		version = DATA_VERSION,
		coins = Config.StartingCoins,
		pens = pens,
		discovered = {},
		-- A few carrots so new players can stock their first rabbit pen.
		inventory = { Carrot = 10 },
		equipment = equipment,
	}
end

local function number(value: any, default: number): number
	local n = tonumber(value)
	if n == nil or n ~= n then
		return default
	end
	return n
end

-- Cleans loaded data so bad or old saves can't break the game.
local function sanitize(raw: any): SaveData
	local data = DataService.newData()
	if type(raw) ~= "table" then
		return data
	end
	data.coins = math.max(0, math.floor(number(raw.coins, data.coins)))

	if type(raw.discovered) == "table" then
		for id, value in raw.discovered do
			if Config.SpeciesById[id] and value == true then
				data.discovered[id] = true
			end
		end
	end

	if type(raw.equipment) == "table" then
		for id in data.equipment do
			data.equipment[id] = math.clamp(math.floor(number(raw.equipment[id], 0)), 0, Config.MaxEquipmentLevel)
		end
	end

	if type(raw.inventory) == "table" then
		data.inventory = {}
		local capacity = Config.getEquipmentValue("Backpack", data.equipment.Backpack)
		local carried = 0
		for id, amount in raw.inventory do
			if Config.FoodById[id] then
				local n = math.clamp(math.floor(number(amount, 0)), 0, capacity - carried)
				if n > 0 then
					data.inventory[id] = n
					carried += n
				end
			end
		end
	end

	if type(raw.pens) == "table" then
		local storeCapacity = Config.getEquipmentValue("Pantry", data.equipment.Pantry)
		for i, pen in data.pens do
			local rawPen = raw.pens[i]
			if type(rawPen) ~= "table" then
				continue
			end
			pen.unlocked = pen.unlocked or rawPen.unlocked == true
			if not pen.unlocked then
				continue
			end
			if type(rawPen.storeFood) == "string" and Config.FoodById[rawPen.storeFood] then
				pen.storeFood = rawPen.storeFood
				pen.storeAmount = math.clamp(number(rawPen.storeAmount, 0), 0, storeCapacity)
			end
			if type(rawPen.animals) == "table" then
				local penSpecies: string? = nil
				for _, a in rawPen.animals do
					if #pen.animals >= Config.PenCapacity then
						break
					end
					local species = if type(a) == "table" then Config.SpeciesById[a.species] else nil
					-- A pen only ever holds one species.
					if species and (penSpecies == nil or penSpecies == species.id) then
						penSpecies = species.id
						table.insert(pen.animals, {
							species = species.id,
							growth = math.clamp(number(a.growth, 0), 0, species.growTime),
							hunger = math.clamp(number(a.hunger, Config.HungerMax), 0, Config.HungerMax),
							-- Health was added in version 2; older animals start healthy.
							health = math.clamp(number(a.health, Config.HealthMax), 1, Config.HealthMax),
						})
					end
				end
			end
		end
	end
	return data
end

function DataService.load(player: Player): (SaveData, boolean)
	if not store then
		return DataService.newData(), false
	end
	local dataStore = store :: DataStore
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return dataStore:GetAsync(key(player))
		end)
		if ok then
			return sanitize(result), true
		end
		warn(string.format("[Zoo] Load attempt %d failed for %s: %s", attempt, player.Name, tostring(result)))
		task.wait(attempt)
	end
	-- Loading failed: play with fresh data but don't save over the real data.
	return DataService.newData(), false
end

function DataService.save(player: Player, data: SaveData): boolean
	if not store then
		return false
	end
	local dataStore = store :: DataStore
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			dataStore:SetAsync(key(player), data, { player.UserId })
		end)
		if ok then
			return true
		end
		warn(string.format("[Zoo] Save attempt %d failed for %s: %s", attempt, player.Name, tostring(err)))
		task.wait(attempt)
	end
	return false
end

return DataService
