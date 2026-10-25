--!strict
-- Builds the map: ground, a central road, and one zoo plot per player slot.
-- Each plot has 8 fenced pens along a central path, with a sign post per pen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldBuilder = {}

export type Pen = {
	index: number,
	center: CFrame, -- top surface centre of the pen floor
	floor: Part,
	trough: Part,
	troughFill: Part,
	sign: Part,
	prompt: ProximityPrompt,
	statusLabel: TextLabel,
	animalsFolder: Folder,
}

export type Plot = {
	index: number,
	cframe: CFrame,
	folder: Folder,
	entrance: CFrame,
	ownerLabel: TextLabel,
	pens: { Pen },
}

local WOOD = Color3.fromRGB(125, 85, 50)
local PATH = Color3.fromRGB(190, 170, 140)
local LOCKED_FLOOR = Color3.fromRGB(95, 95, 95)

local PLOT_WIDTH = 76
local PLOT_DEPTH = 116
local PEN_ROW_X = 19 -- distance from the centre path to a pen's centre
local PEN_ZS = { -40, -12, 16, 44 }
local FLOOR_TOP = 0.8

local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

local function makeLabel(parent: Instance, text: string, textColor: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = textColor
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = parent
	return label
end

function WorldBuilder.buildEnvironment(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Environment"

	makePart({
		Name = "Ground",
		Size = Vector3.new(1600, 2, 1600),
		CFrame = CFrame.new(0, -1, 0),
		Color = Color3.fromRGB(95, 155, 70),
		Material = Enum.Material.Grass,
		Parent = folder,
	})

	-- Wild rings around the zoo, drawn as flat discs from the outside in.
	-- Rarer food grows in the outer rings.
	for ringIndex = #Config.Rings, 1, -1 do
		local ring = Config.Rings[ringIndex]
		makePart({
			Name = ring.name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, ring.outer * 2, ring.outer * 2),
			CFrame = CFrame.new(0, -0.1 + 0.02 * (#Config.Rings - ringIndex + 1), 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = ring.color,
			Material = ring.material,
			Parent = folder,
		})
	end
	makePart({
		Name = "ZooGrounds",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, Config.Rings[1].inner * 2, Config.Rings[1].inner * 2),
		CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(95, 155, 70),
		Material = Enum.Material.Grass,
		Parent = folder,
	})

	-- Signs at the edge of each ring saying what food grows there.
	for ringIndex, ring in Config.Rings do
		local foods = {}
		for _, food in Config.Foods do
			if food.ring == ringIndex then
				table.insert(foods, food.emoji .. " " .. food.name)
			end
		end
		local text = ring.name .. "\n" .. table.concat(foods, "  ")
		for i = 0, 3 do
			local angle = i * math.pi / 2 + math.pi / 4
			local position = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (ring.inner + 4)
			local facing = CFrame.lookAt(position, Vector3.new(0, 0, 0))
			makePart({
				Name = "RingSignPost",
				Size = Vector3.new(0.6, 6, 0.6),
				CFrame = facing * CFrame.new(0, 3, 0),
				Color = WOOD,
				Material = Enum.Material.Wood,
				Parent = folder,
			})
			local board = makePart({
				Name = "RingSign",
				Size = Vector3.new(9, 3.5, 0.4),
				CFrame = facing * CFrame.new(0, 6.5, 0),
				Color = Color3.fromRGB(240, 225, 190),
				Material = Enum.Material.WoodPlanks,
				Parent = folder,
			})
			for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
				local gui = Instance.new("SurfaceGui")
				gui.Face = face
				gui.PixelsPerStud = 30
				gui.Parent = board
				makeLabel(gui, text, Color3.fromRGB(90, 55, 25))
			end
		end
	end

	makePart({
		Name = "Road",
		Size = Vector3.new(300, 0.2, 24),
		CFrame = CFrame.new(0, 0.1, 0),
		Color = Color3.fromRGB(70, 70, 75),
		Material = Enum.Material.Asphalt,
		Parent = folder,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 0.5, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(240, 200, 80)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Parent = folder

	-- A welcome arch across the west end of the road.
	local welcome = makePart({
		Name = "WelcomeSign",
		Size = Vector3.new(24, 6, 1),
		CFrame = CFrame.new(-140, 14, 0) * CFrame.Angles(0, math.pi / 2, 0),
		Color = WOOD,
		Material = Enum.Material.Wood,
		Parent = folder,
	})
	for _, side in { -1, 1 } do
		makePart({
			Name = "WelcomePost",
			Size = Vector3.new(1, 14, 1),
			CFrame = CFrame.new(-140, 7, side * 11),
			Color = WOOD,
			Material = Enum.Material.Wood,
			Parent = folder,
		})
	end
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.PixelsPerStud = 40
		gui.Parent = welcome
		makeLabel(gui, "🦁 Zoo Tycoon 🐘", Color3.fromRGB(255, 230, 120))
	end

	folder.Parent = workspace
	return folder
end

local function buildFence(parent: Instance, center: CFrame, size: number)
	local half = size / 2
	local postSpacing = 4
	local height = 3.5

	local sides = {
		{ from = Vector3.new(-half, 0, -half), to = Vector3.new(half, 0, -half) },
		{ from = Vector3.new(half, 0, -half), to = Vector3.new(half, 0, half) },
		{ from = Vector3.new(half, 0, half), to = Vector3.new(-half, 0, half) },
		{ from = Vector3.new(-half, 0, half), to = Vector3.new(-half, 0, -half) },
	}

	for _, side in sides do
		local delta = side.to - side.from
		local length = delta.Magnitude
		local direction = delta.Unit
		local posts = math.floor(length / postSpacing)
		for i = 0, posts - 1 do
			local p = side.from + direction * (i * postSpacing)
			makePart({
				Name = "Post",
				Size = Vector3.new(0.6, height, 0.6),
				CFrame = center * CFrame.new(p.X, height / 2, p.Z),
				Color = WOOD,
				Material = Enum.Material.Wood,
				Parent = parent,
			})
		end
		local mid = (side.from + side.to) / 2
		for _, railY in { 1.2, 2.8 } do
			local railMid = mid + Vector3.new(0, railY, 0)
			makePart({
				Name = "Rail",
				Size = Vector3.new(0.3, 0.3, length),
				CFrame = center * CFrame.lookAt(railMid, railMid + direction),
				Color = WOOD,
				Material = Enum.Material.Wood,
				Parent = parent,
			})
		end
	end
end

local function buildPen(plotFolder: Folder, plotCFrame: CFrame, index: number, side: number, localZ: number): Pen
	local penFolder = Instance.new("Folder")
	penFolder.Name = "Pen" .. index
	penFolder.Parent = plotFolder

	local size = Config.PenSize
	local localCenter = CFrame.new(side * PEN_ROW_X, 0, localZ)
	local floorCFrame = plotCFrame * localCenter * CFrame.new(0, FLOOR_TOP - 0.3, 0)
	local center = plotCFrame * localCenter * CFrame.new(0, FLOOR_TOP, 0)

	local floor = makePart({
		Name = "Floor",
		Size = Vector3.new(size, 0.6, size),
		CFrame = floorCFrame,
		Color = LOCKED_FLOOR,
		Material = Enum.Material.Concrete,
		Parent = penFolder,
	})

	buildFence(penFolder, center, size)

	-- Feed trough on the path side of the pen.
	local troughCFrame = center * CFrame.new(-side * (size / 2 - 2.5), 0.5, size / 2 - 5)
	local trough = makePart({
		Name = "Trough",
		Size = Vector3.new(2, 1, 5),
		CFrame = troughCFrame,
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
		CanCollide = false,
		Parent = penFolder,
	})
	local troughFill = makePart({
		Name = "TroughFill",
		Size = Vector3.new(1.6, 0.2, 4.6),
		CFrame = troughCFrame * CFrame.new(0, 0.45, 0),
		Color = Color3.fromRGB(200, 180, 60),
		Material = Enum.Material.Grass,
		Transparency = 1,
		CanCollide = false,
		Parent = penFolder,
	})

	-- Sign post on the path, facing the path, holds the interaction prompt.
	local signBase = plotCFrame * CFrame.new(side * (PEN_ROW_X - size / 2 - 2), 0, localZ)
	makePart({
		Name = "SignPost",
		Size = Vector3.new(0.5, 4, 0.5),
		CFrame = signBase * CFrame.new(0, 2, 0),
		Color = WOOD,
		Material = Enum.Material.Wood,
		Parent = penFolder,
	})
	local sign = makePart({
		Name = "Sign",
		Size = Vector3.new(3.5, 2.2, 0.3),
		-- Face the sign toward the path (the sign's front is its -Z axis).
		CFrame = signBase * CFrame.new(0, 4.5, 0) * CFrame.Angles(0, side * math.rad(90), 0),
		Color = Color3.fromRGB(240, 225, 190),
		Material = Enum.Material.WoodPlanks,
		Parent = penFolder,
	})
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.PixelsPerStud = 50
	signGui.Parent = sign
	makeLabel(signGui, "Pen " .. index, Color3.fromRGB(90, 55, 25))

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 50)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.MaxDistance = 70
	billboard.Parent = sign
	local statusLabel = makeLabel(billboard, "", Color3.new(1, 1, 1))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Manage pen"
	prompt.ObjectText = "Pen " .. index
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = sign

	local animalsFolder = Instance.new("Folder")
	animalsFolder.Name = "Animals"
	animalsFolder.Parent = penFolder

	return {
		index = index,
		center = center,
		floor = floor,
		trough = trough,
		troughFill = troughFill,
		sign = sign,
		prompt = prompt,
		statusLabel = statusLabel,
		animalsFolder = animalsFolder,
	}
end

function WorldBuilder.buildPlot(index: number): Plot
	-- Three plots north of the road and three south, all opening onto the road.
	local column = (index - 1) % 3
	local north = index <= 3
	local x = (column - 1) * 90
	local z = if north then -(12 + PLOT_DEPTH / 2) else 12 + PLOT_DEPTH / 2
	-- The plot's local -Z points at the road.
	local rotation = if north then math.pi else 0
	local plotCFrame = CFrame.new(x, 0, z) * CFrame.Angles(0, rotation, 0)

	local folder = Instance.new("Folder")
	folder.Name = "Plot" .. index

	makePart({
		Name = "Base",
		Size = Vector3.new(PLOT_WIDTH, 0.4, PLOT_DEPTH),
		CFrame = plotCFrame * CFrame.new(0, 0.2, 0),
		Color = Color3.fromRGB(120, 175, 90),
		Material = Enum.Material.Grass,
		Parent = folder,
	})
	makePart({
		Name = "Path",
		Size = Vector3.new(12, 0.5, PLOT_DEPTH),
		CFrame = plotCFrame * CFrame.new(0, 0.25, 0),
		Color = PATH,
		Material = Enum.Material.Cobblestone,
		Parent = folder,
	})

	-- Entrance arch with the owner's name.
	local archZ = -PLOT_DEPTH / 2 + 1
	for _, side in { -1, 1 } do
		makePart({
			Name = "ArchPost",
			Size = Vector3.new(1.2, 12, 1.2),
			CFrame = plotCFrame * CFrame.new(side * 7, 6, archZ),
			Color = WOOD,
			Material = Enum.Material.Wood,
			Parent = folder,
		})
	end
	local archSign = makePart({
		Name = "ArchSign",
		Size = Vector3.new(16, 3.5, 0.8),
		CFrame = plotCFrame * CFrame.new(0, 11, archZ),
		Color = Color3.fromRGB(60, 120, 60),
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	local ownerLabel: TextLabel? = nil
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.PixelsPerStud = 40
		gui.Parent = archSign
		local label = makeLabel(gui, "Empty Zoo", Color3.fromRGB(255, 245, 200))
		if face == Enum.NormalId.Front then
			ownerLabel = label
		else
			-- Keep both faces in sync.
			label.Name = "BackLabel"
		end
	end

	local pens = {}
	for i, penZ in PEN_ZS do
		table.insert(pens, buildPen(folder, plotCFrame, i * 2 - 1, -1, penZ))
		table.insert(pens, buildPen(folder, plotCFrame, i * 2, 1, penZ))
	end

	folder.Parent = workspace

	return {
		index = index,
		cframe = plotCFrame,
		folder = folder,
		-- Just inside the arch, facing into the zoo.
		entrance = plotCFrame * CFrame.new(0, 4, -PLOT_DEPTH / 2 + 6) * CFrame.Angles(0, math.pi, 0),
		ownerLabel = ownerLabel :: TextLabel,
		pens = pens,
	}
end

function WorldBuilder.setOwnerName(plot: Plot, text: string)
	plot.ownerLabel.Text = text
	local archSign = plot.folder:FindFirstChild("ArchSign")
	if archSign then
		for _, gui in archSign:GetChildren() do
			local back = gui:FindFirstChild("BackLabel")
			if back and back:IsA("TextLabel") then
				back.Text = text
			end
		end
	end
end

return WorldBuilder
