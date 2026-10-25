--!strict
-- Builds and animates animal models on the client.
-- The server creates a tagged "ZooAnimal" marker per animal with attributes:
--   Species (string), Stage (string), Hungry (bool), Target (Vector3), Speed (number)
-- This script turns each marker into a model that walks toward its Target.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local AnimalBuilder = require(ReplicatedStorage.Shared.AnimalBuilder)

local camera = workspace.CurrentCamera
local MAX_ANIMATE_DISTANCE = 300

type Tracked = {
	marker: Instance,
	model: Model,
	position: Vector3,
	yaw: number,
	stage: string,
	hungerGui: BillboardGui,
	bobClock: number,
	connections: { RBXScriptConnection },
}

local tracked: { [Instance]: Tracked } = {}

local folder = Instance.new("Folder")
folder.Name = "ClientAnimals"
folder.Parent = workspace

local function applyStage(entry: Tracked, stage: string)
	entry.stage = stage
	local scale = Config.StageScale[stage] or 1
	entry.model:ScaleTo(scale)
	local species = Config.SpeciesById[entry.marker:GetAttribute("Species") :: string]
	if species then
		local v = species.visual
		local height = v.legLength + v.bodySize.Y + v.headSize.Y
		if table.find(v.extras, "longNeck") then
			height += 4.5
		end
		-- The bubble is attached to the body, so offset from the body's centre.
		local bodyCenter = v.legLength + v.bodySize.Y / 2
		entry.hungerGui.StudsOffsetWorldSpace = Vector3.new(0, (height - bodyCenter) * scale + 1.2, 0)
	end
end

local function onMarkerAdded(marker: Instance)
	if tracked[marker] then
		return
	end
	local speciesId = marker:GetAttribute("Species")
	if type(speciesId) ~= "string" or not Config.SpeciesById[speciesId] then
		return
	end
	local target = marker:GetAttribute("Target")
	local position = if typeof(target) == "Vector3" then target else Vector3.zero

	local model = AnimalBuilder.build(speciesId)
	local yaw = math.random() * math.pi * 2
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))

	-- Bubble above starving or hurt animals: a food icon and a health bar.
	local hungerGui = Instance.new("BillboardGui")
	hungerGui.Name = "HungerBubble"
	hungerGui.Size = UDim2.fromOffset(60, 52)
	hungerGui.MaxDistance = 80
	hungerGui.Adornee = model:FindFirstChild("Body") :: BasePart
	local label = Instance.new("TextLabel")
	label.Name = "Icon"
	label.Size = UDim2.new(1, 0, 0, 36)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Text = "🍖"
	label.Parent = hungerGui
	local barBack = Instance.new("Frame")
	barBack.Name = "HealthBar"
	barBack.Position = UDim2.fromOffset(4, 40)
	barBack.Size = UDim2.new(1, -8, 0, 8)
	barBack.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	barBack.BorderSizePixel = 0
	barBack.Parent = hungerGui
	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack
	hungerGui.Parent = model

	model.Parent = folder

	local entry: Tracked = {
		marker = marker,
		model = model,
		position = position,
		yaw = yaw,
		stage = "Adult",
		hungerGui = hungerGui,
		bobClock = math.random() * 10,
		connections = {},
	}
	tracked[marker] = entry
	applyStage(entry, (marker:GetAttribute("Stage") :: string?) or "Baby")

	local function updateBubble()
		local hungry = marker:GetAttribute("Hungry") == true
		local health = (marker:GetAttribute("Health") :: number?) or 1
		hungerGui.Enabled = hungry or health < 1
		label.Text = if hungry then "🍖" else "❤️"
		barFill.Size = UDim2.fromScale(math.clamp(health, 0, 1), 1)
	end
	updateBubble()

	table.insert(
		entry.connections,
		marker:GetAttributeChangedSignal("Stage"):Connect(function()
			local stage = marker:GetAttribute("Stage")
			if type(stage) == "string" and stage ~= entry.stage then
				applyStage(entry, stage)
			end
		end)
	)
	table.insert(
		entry.connections,
		marker:GetAttributeChangedSignal("Hungry"):Connect(function()
			updateBubble()
		end)
	)
	table.insert(entry.connections, marker:GetAttributeChangedSignal("Health"):Connect(updateBubble))
end

local function onMarkerRemoved(marker: Instance)
	local entry = tracked[marker]
	if not entry then
		return
	end
	tracked[marker] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	entry.model:Destroy()
end

local function angleDifference(a: number, b: number): number
	return (b - a + math.pi) % (2 * math.pi) - math.pi
end

RunService.Heartbeat:Connect(function(dt)
	local cameraPosition = camera.CFrame.Position
	for marker, entry in tracked do
		local target = marker:GetAttribute("Target")
		local speed = marker:GetAttribute("Speed")
		if typeof(target) ~= "Vector3" or type(speed) ~= "number" then
			continue
		end

		local offset = target - entry.position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local distance = flat.Magnitude
		local moving = distance > 0.05

		if moving then
			local step = math.min(distance, speed * dt)
			entry.position += flat.Unit * step
			-- The model's front is -Z, so this yaw points it along its path.
			local desiredYaw = math.atan2(-flat.X, -flat.Z)
			entry.yaw += angleDifference(entry.yaw, desiredYaw) * math.min(1, dt * 8)
		end
		-- Keep height in sync with the target (floor top).
		entry.position = Vector3.new(entry.position.X, target.Y, entry.position.Z)

		if (entry.position - cameraPosition).Magnitude > MAX_ANIMATE_DISTANCE then
			continue
		end

		local bob = 0
		if moving then
			entry.bobClock += dt * speed * 1.5
			bob = math.abs(math.sin(entry.bobClock)) * 0.25 * (Config.StageScale[entry.stage] or 1)
		end
		entry.model:PivotTo(CFrame.new(entry.position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, entry.yaw, 0))
	end
end)

CollectionService:GetInstanceAddedSignal("ZooAnimal"):Connect(onMarkerAdded)
CollectionService:GetInstanceRemovedSignal("ZooAnimal"):Connect(onMarkerRemoved)
for _, marker in CollectionService:GetTagged("ZooAnimal") do
	task.spawn(onMarkerAdded, marker)
end
