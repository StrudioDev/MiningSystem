--[[
	MiningServer.server.luau
	Server-side mining system handling validation and game logic.
	
	Features:
	- Distance validation (10 studs)
	- Tag validation (Rock and Pickaxe)
	- Health tracking per rock
	- Damage calculation
	- Breaking and respawn logic with visual effects
	- Template-based rock spawning from ReplicatedStorage
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(game.ReplicatedStorage.Shared.Remotes)

local PICKAXE_POWER = 10
local MAX_MINE_DISTANCE = 10
local DEFAULT_ROCK_HEALTH = 100
local RESPAWN_TIME = 1

local ROCK_TAG = "Rock"
local PICKAXE_TAG = "Pickaxe"
local SPAWN_POINT_NAME = "RockSpawn"

local BREAK_SOUND_ID = "rbxassetid://5765856277"
local BREAK_DEBRIS_COUNT = 12

local RockTemplate = ReplicatedStorage:WaitForChild("Rock", 10)
if not RockTemplate then
	error("[MiningServer] Could not find Rock template in ReplicatedStorage!")
end

local rockHealth: { [BasePart]: number } = {}
local rockRespawning: { [BasePart]: boolean } = {}
local spawnPointRocks: { [BasePart]: BasePart } = {}

local function initializeRock(rock: BasePart)
	if rockHealth[rock] then return end
	
	rockHealth[rock] = DEFAULT_ROCK_HEALTH
	rockRespawning[rock] = false
end

local function isHoldingPickaxe(player: Player): boolean
	local character = player.Character
	if not character then return false end
	
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and CollectionService:HasTag(child, PICKAXE_TAG) then
			return true
		end
	end
	
	return false
end

local function getDistanceToRock(player: Player, rock: BasePart): number
	local character = player.Character
	if not character then return math.huge end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return math.huge end
	
	return (rock.Position - humanoidRootPart.Position).Magnitude
end

local function validateMineRequest(player: Player, rock: BasePart): (boolean, string?)
	if not rock or not rock:IsA("BasePart") then
		return false, "Invalid target"
	end
	
	if not CollectionService:HasTag(rock, ROCK_TAG) then
		return false, "Target is not a rock"
	end
	
	if rockRespawning[rock] then
		return false, "Rock is respawning"
	end
	
	if not isHoldingPickaxe(player) then
		return false, "No pickaxe equipped"
	end
	
	local distance = getDistanceToRock(player, rock)
	if distance > MAX_MINE_DISTANCE then
		return false, "Too far from rock"
	end
	
	return true, nil
end

local function spawnRockAtPoint(spawnPoint: BasePart)
	local newRock = RockTemplate:Clone()
	
	newRock.Position = spawnPoint.Position
	newRock.Anchored = true
	
	if not CollectionService:HasTag(newRock, ROCK_TAG) then
		CollectionService:AddTag(newRock, ROCK_TAG)
	end
	
	newRock.Parent = workspace
	
	spawnPointRocks[spawnPoint] = newRock
	
	initializeRock(newRock)
	
	local originalSize = newRock.Size
	newRock.Size = originalSize * 0.01
	
	local tweenInfo = TweenInfo.new(
		0.6,
		Enum.EasingStyle.Elastic,
		Enum.EasingDirection.Out
	)
	
	local tween = TweenService:Create(newRock, tweenInfo, {
		Size = originalSize
	})
	tween:Play()
	
	return newRock
end

local function findSpawnPointForRock(rock: BasePart): BasePart?
	for spawnPoint, spawnedRock in pairs(spawnPointRocks) do
		if spawnedRock == rock then
			return spawnPoint
		end
	end
	return nil
end

local function spawnBreakDebris(rock: BasePart)
	local rockColor = rock.Color
	local rockMaterial = rock.Material
	local rockPosition = rock.Position
	local rockSize = rock.Size
	
	for i = 1, BREAK_DEBRIS_COUNT do
		local debris = Instance.new("Part")
		debris.Name = "BreakDebris"
		debris.Size = Vector3.new(
			math.random(4, 10) / 10,
			math.random(4, 10) / 10,
			math.random(4, 10) / 10
		)
		debris.Color = rockColor
		debris.Material = rockMaterial
		debris.Anchored = false
		debris.CanCollide = true
		debris.CanQuery = false
		debris.CanTouch = false
		
		local spawnOffset = Vector3.new(
			math.random(-10, 10) / 10 * rockSize.X / 2,
			math.random(-5, 10) / 10 * rockSize.Y / 2,
			math.random(-10, 10) / 10 * rockSize.Z / 2
		)
		debris.Position = rockPosition + spawnOffset
		
		debris.Orientation = Vector3.new(
			math.random(0, 360),
			math.random(0, 360),
			math.random(0, 360)
		)
		
		debris.Parent = workspace
		
		local direction = (debris.Position - rockPosition).Unit
		if direction.Magnitude < 0.1 then
			direction = Vector3.new(math.random(-10, 10), 10, math.random(-10, 10)).Unit
		end
		
		local speed = math.random(15, 30)
		local velocity = direction * speed + Vector3.new(0, math.random(10, 20), 0)
		debris:ApplyImpulse(velocity * debris:GetMass())
		
		debris:ApplyAngularImpulse(Vector3.new(
			math.random(-5, 5),
			math.random(-5, 5),
			math.random(-5, 5)
		))
		
		Debris:AddItem(debris, 3)
	end
end

local function playBreakSound(position: Vector3)
	local soundPart = Instance.new("Part")
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.Transparency = 1
	soundPart.Size = Vector3.new(1, 1, 1)
	soundPart.Position = position
	soundPart.Parent = workspace
	
	local sound = Instance.new("Sound")
	sound.SoundId = BREAK_SOUND_ID
	sound.Volume = 1
	sound.PlaybackSpeed = 0.85 + math.random() * 0.3
	sound.Parent = soundPart
	sound:Play()
	
	Debris:AddItem(soundPart, 3)
end

local function breakRock(rock: BasePart)
	local spawnPoint = findSpawnPointForRock(rock)
	
	local rockPosition = rock.Position
	local rockColor = rock.Color
	local rockMaterial = rock.Material
	local rockSize = rock.Size
	
	playBreakSound(rockPosition)
	spawnBreakDebris(rock)
	
	rockHealth[rock] = nil
	rockRespawning[rock] = nil
	
	rock:Destroy()
	
	if spawnPoint then
		task.delay(RESPAWN_TIME, function()
			if spawnPoint and spawnPoint.Parent then
				spawnRockAtPoint(spawnPoint)
			end
		end)
	end
end

local function processMineRequest(player: Player, rock: BasePart)
	local valid, reason = validateMineRequest(player, rock)
	if not valid then
		warn("[MiningServer] Mining rejected for", player.Name, ":", reason)
		return
	end
	
	initializeRock(rock)
	
	local damage = PICKAXE_POWER
	local currentHealth = rockHealth[rock]
	local newHealth = math.max(0, currentHealth - damage)
	rockHealth[rock] = newHealth
	
	local isBroken = newHealth <= 0
	
	Remotes.MineResult:FireClient(player, rock, damage, newHealth, DEFAULT_ROCK_HEALTH, isBroken)
	
	if isBroken then
		breakRock(rock)
	end
end

Remotes.Mine.OnServerEvent:Connect(processMineRequest)

for _, rock in CollectionService:GetTagged(ROCK_TAG) do
	if rock:IsA("BasePart") then
		initializeRock(rock)
	end
end

CollectionService:GetInstanceAddedSignal(ROCK_TAG):Connect(function(rock)
	if rock:IsA("BasePart") then
		initializeRock(rock)
	end
end)

CollectionService:GetInstanceRemovedSignal(ROCK_TAG):Connect(function(rock)
	if rock:IsA("BasePart") then
		rockHealth[rock] = nil
		rockRespawning[rock] = nil
	end
end)

local function initializeSpawnPoints()
	for _, spawnPoint in workspace:GetDescendants() do
		if spawnPoint:IsA("BasePart") and spawnPoint.Name == SPAWN_POINT_NAME then
			spawnPoint.Transparency = 1
			spawnPoint.CanCollide = false
			
			spawnRockAtPoint(spawnPoint)
			print("[MiningServer] Spawned rock at spawn point:", spawnPoint:GetFullName())
		end
	end
end

initializeSpawnPoints()

print("[MiningServer] Initialized successfully!")
