--!strict
-- Builds simple blocky animal models out of parts, so the game needs no uploaded assets.
-- Models are built facing -Z with their feet at y = 0, and the pivot sits on the ground
-- under the body. That lets Model:ScaleTo grow an animal without lifting it off the floor.

local Config = require(script.Parent.Config)

local AnimalBuilder = {}

local BLACK = Color3.fromRGB(25, 25, 25)
local WHITE = Color3.fromRGB(245, 245, 245)
local PINK = Color3.fromRGB(240, 170, 170)
local ORANGE = Color3.fromRGB(245, 160, 40)
local BROWN = Color3.fromRGB(120, 75, 35)
local IVORY = Color3.fromRGB(250, 245, 225)

local function makePart(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	if shape then
		part.Shape = shape
	end
	part.Parent = model
	return part
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function addEyes(model: Model, head: CFrame, headSize: Vector3)
	local eyeSize = math.max(0.2, headSize.X * 0.18)
	local frontZ = -headSize.Z / 2
	for _, side in { -1, 1 } do
		makePart(
			model,
			"Eye",
			Vector3.new(eyeSize, eyeSize, eyeSize),
			head * at(side * headSize.X * 0.25, headSize.Y * 0.15, frontZ),
			BLACK,
			Enum.PartType.Ball
		)
	end
end

local function buildQuadruped(model: Model, v: Config.Visual)
	local body = v.bodySize
	local legLength = v.legLength
	local bodyY = legLength + body.Y / 2
	makePart(model, "Body", body, at(0, bodyY, 0), v.bodyColor)

	-- Legs at the four corners of the body.
	local legWidth = math.min(body.X, body.Z) * 0.28
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			makePart(
				model,
				"Leg",
				Vector3.new(legWidth, legLength + 0.2, legWidth),
				at(sx * (body.X / 2 - legWidth / 2), (legLength + 0.2) / 2, sz * (body.Z / 2 - legWidth / 2)),
				v.legColor
			)
		end
	end

	-- Head, raised on a neck for giraffes.
	local hasLongNeck = table.find(v.extras, "longNeck") ~= nil
	local head: CFrame
	if hasLongNeck then
		local neckHeight = 4.5
		local neckBaseZ = -(body.Z / 2 - 0.5)
		makePart(
			model,
			"Neck",
			Vector3.new(0.9, neckHeight, 0.9),
			at(0, legLength + body.Y + neckHeight / 2 - 0.6, neckBaseZ) * CFrame.Angles(math.rad(-12), 0, 0),
			v.bodyColor
		)
		head = at(0, legLength + body.Y + neckHeight - 0.2, neckBaseZ - 0.9)
	else
		head = at(0, legLength + body.Y * 0.85, -(body.Z / 2 + v.headSize.Z * 0.3))
	end
	makePart(model, "Head", v.headSize, head, v.headColor)
	addEyes(model, head, v.headSize)

	local h = v.headSize
	for _, extra in v.extras do
		if extra == "longEars" then
			for _, side in { -1, 1 } do
				makePart(
					model,
					"Ear",
					Vector3.new(0.3, 1.4, 0.45),
					head * at(side * h.X * 0.25, h.Y / 2 + 0.6, 0.1) * CFrame.Angles(0, 0, side * math.rad(-10)),
					v.headColor
				)
				makePart(
					model,
					"InnerEar",
					Vector3.new(0.15, 1.1, 0.05),
					head * at(side * h.X * 0.25, h.Y / 2 + 0.6, -0.13) * CFrame.Angles(0, 0, side * math.rad(-10)),
					PINK
				)
			end
		elseif extra == "puffTail" then
			makePart(model, "Tail", Vector3.new(0.7, 0.7, 0.7), at(0, bodyY + 0.2, body.Z / 2), WHITE, Enum.PartType.Ball)
		elseif extra == "horns" then
			for _, side in { -1, 1 } do
				makePart(
					model,
					"Horn",
					Vector3.new(0.25, 1.0, 0.25),
					head * at(side * h.X * 0.25, h.Y / 2 + 0.4, 0.3) * CFrame.Angles(math.rad(30), 0, 0),
					Color3.fromRGB(90, 80, 70)
				)
			end
		elseif extra == "beard" then
			makePart(
				model,
				"Beard",
				Vector3.new(0.35, 0.7, 0.3),
				head * at(0, -h.Y / 2 - 0.3, -h.Z * 0.3),
				Color3.fromRGB(240, 235, 225)
			)
		elseif extra == "stripes" then
			for i = -3, 3 do
				makePart(
					model,
					"Stripe",
					Vector3.new(body.X + 0.06, body.Y + 0.06, 0.3),
					at(0, bodyY, i * body.Z / 8),
					BLACK
				)
			end
			for _, side in { -1, 1 } do
				makePart(
					model,
					"HeadStripe",
					Vector3.new(0.06, h.Y * 0.8, 0.25),
					head * at(side * h.X / 2, 0, 0.2),
					BLACK
				)
			end
		elseif extra == "mane" then
			makePart(
				model,
				"Mane",
				Vector3.new(0.35, 0.5, body.Z * 0.45),
				at(0, legLength + body.Y + 0.2, -body.Z * 0.22),
				BLACK
			)
		elseif extra == "roundEars" then
			for _, side in { -1, 1 } do
				makePart(
					model,
					"Ear",
					Vector3.new(0.8, 0.8, 0.8),
					head * at(side * h.X * 0.4, h.Y / 2, 0.2),
					BLACK,
					Enum.PartType.Ball
				)
			end
		elseif extra == "eyePatches" then
			for _, side in { -1, 1 } do
				makePart(
					model,
					"EyePatch",
					Vector3.new(0.6, 0.7, 0.1),
					head * at(side * h.X * 0.25, h.Y * 0.12, -h.Z / 2 + 0.02),
					BLACK
				)
			end
			-- Black shoulder band, like a real panda.
			makePart(
				model,
				"Band",
				Vector3.new(body.X + 0.06, body.Y + 0.06, body.Z * 0.3),
				at(0, bodyY, -body.Z * 0.15),
				BLACK
			)
		elseif extra == "lionMane" then
			makePart(
				model,
				"Mane",
				Vector3.new(h.X * 1.6, h.Y * 1.6, h.Z * 0.9),
				head * at(0, 0, h.Z * 0.35),
				BROWN,
				Enum.PartType.Ball
			)
		elseif extra == "tail" then
			makePart(
				model,
				"Tail",
				Vector3.new(0.25, 0.25, 2.0),
				at(0, bodyY + 0.2, body.Z / 2 + 0.8) * CFrame.Angles(math.rad(35), 0, 0),
				v.bodyColor
			)
			makePart(model, "TailTip", Vector3.new(0.5, 0.5, 0.5), at(0, bodyY - 0.4, body.Z / 2 + 1.6), BROWN, Enum.PartType.Ball)
		elseif extra == "spots" then
			local spotColor = Color3.fromRGB(140, 85, 35)
			for i = 1, 6 do
				local side = if i % 2 == 0 then 1 else -1
				local z = (i - 3.5) * body.Z / 7
				local y = bodyY + (if i % 3 == 0 then 0.5 else -0.3)
				makePart(model, "Spot", Vector3.new(0.08, 0.7, 0.7), at(side * (body.X / 2 + 0.02), y, z), spotColor)
			end
		elseif extra == "ossicones" then
			for _, side in { -1, 1 } do
				makePart(model, "Ossicone", Vector3.new(0.2, 0.6, 0.2), head * at(side * 0.25, h.Y / 2 + 0.3, 0.4), BROWN)
			end
		elseif extra == "trunk" then
			local trunkColor = v.headColor
			makePart(model, "Trunk", Vector3.new(0.8, 1.6, 0.8), head * at(0, -0.6, -h.Z / 2 - 0.3), trunkColor)
			makePart(
				model,
				"Trunk",
				Vector3.new(0.6, 1.6, 0.6),
				head * at(0, -2.0, -h.Z / 2 - 0.5) * CFrame.Angles(math.rad(-15), 0, 0),
				trunkColor
			)
		elseif extra == "bigEars" then
			for _, side in { -1, 1 } do
				makePart(
					model,
					"Ear",
					Vector3.new(0.2, 2.6, 2.0),
					head * at(side * (h.X / 2 + 0.2), 0, 0.4) * CFrame.Angles(0, side * math.rad(-20), 0),
					v.headColor:Lerp(PINK, 0.15)
				)
			end
		elseif extra == "tusks" then
			for _, side in { -1, 1 } do
				makePart(
					model,
					"Tusk",
					Vector3.new(0.25, 0.25, 1.4),
					head * at(side * 0.6, -h.Y / 2 + 0.2, -h.Z / 2 - 0.4) * CFrame.Angles(math.rad(20), 0, 0),
					IVORY
				)
			end
		end
	end
end

local function buildBiped(model: Model, v: Config.Visual)
	local body = v.bodySize
	local legLength = v.legLength
	local bodyY = legLength + body.Y / 2
	makePart(model, "Body", body, at(0, bodyY, 0), v.bodyColor)

	for _, side in { -1, 1 } do
		makePart(
			model,
			"Foot",
			Vector3.new(0.5, legLength + 0.1, 0.8),
			at(side * body.X * 0.25, (legLength + 0.1) / 2, -0.2),
			v.legColor
		)
	end

	local head = at(0, legLength + body.Y + v.headSize.Y / 2 - 0.1, 0)
	makePart(model, "Head", v.headSize, head, v.headColor)
	addEyes(model, head, v.headSize)

	for _, extra in v.extras do
		if extra == "whiteBelly" then
			makePart(
				model,
				"Belly",
				Vector3.new(body.X * 0.75, body.Y * 0.8, 0.1),
				at(0, bodyY - body.Y * 0.05, -body.Z / 2 - 0.01),
				WHITE
			)
		elseif extra == "beak" then
			makePart(model, "Beak", Vector3.new(0.35, 0.25, 0.6), head * at(0, -0.1, -v.headSize.Z / 2 - 0.25), ORANGE)
		elseif extra == "flippers" then
			for _, side in { -1, 1 } do
				makePart(
					model,
					"Flipper",
					Vector3.new(0.2, body.Y * 0.6, 0.6),
					at(side * (body.X / 2 + 0.1), bodyY, 0) * CFrame.Angles(0, 0, side * math.rad(15)),
					v.bodyColor
				)
			end
		end
	end
end

function AnimalBuilder.build(speciesId: string): Model
	local species = Config.SpeciesById[speciesId]
	assert(species, "Unknown species " .. tostring(speciesId))

	local model = Instance.new("Model")
	model.Name = species.name

	if species.visual.shape == "biped" then
		buildBiped(model, species.visual)
	else
		buildQuadruped(model, species.visual)
	end

	model.WorldPivot = CFrame.new()
	return model
end

return AnimalBuilder
