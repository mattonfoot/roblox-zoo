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
}

export type SavedPen = {
	unlocked: boolean,
	animals: { SavedAnimal },
}

export type SaveData = {
	version: number,
	coins: number,
	pens: { SavedPen },
	discovered: { [string]: boolean },
}

local DataService = {}

local DATA_VERSION = 1
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
		})
	end
	return {
		version = DATA_VERSION,
		coins = Config.StartingCoins,
		pens = pens,
		discovered = {},
	}
end

-- Cleans loaded data so bad or old saves can't break the game.
local function sanitize(raw: any): SaveData
	local data = DataService.newData()
	if type(raw) ~= "table" then
		return data
	end
	if type(raw.coins) == "number" and raw.coins == raw.coins then
		data.coins = math.max(0, math.floor(raw.coins))
	end
	if type(raw.discovered) == "table" then
		for id, value in raw.discovered do
			if Config.SpeciesById[id] and value == true then
				data.discovered[id] = true
			end
		end
	end
	if type(raw.pens) == "table" then
		for i, pen in data.pens do
			local rawPen = raw.pens[i]
			if type(rawPen) == "table" then
				pen.unlocked = pen.unlocked or rawPen.unlocked == true
				if pen.unlocked and type(rawPen.animals) == "table" then
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
								growth = math.clamp(tonumber(a.growth) or 0, 0, species.growTime),
								hunger = math.clamp(tonumber(a.hunger) or 0, 0, Config.HungerMax),
							})
						end
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
