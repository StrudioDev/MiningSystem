--[[
	MiningClient.client.luau
	Client-side mining system handling all visuals and "juice".
	
	Features:
	- Tool detection & animations (Idle/Hit)
	- Rock click detection via CollectionService
	- Impact squash/bounce visuals (Elastic easing)
	- Debris particle spawning (physics-based Parts)
	- Health bar BillboardGui
	- Damage text popup
	- Hit/break sound effects
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Remotes = require(game.ReplicatedStorage.Shared.Remotes)

local IDLE_ANIMATION_ID = "rbxassetid://75954724793166"
local HIT_ANIMATION_ID = "rbxassetid://122702014577820"

local ROCK_TAG = "Rock"
local PICKAXE_TAG = "Pickaxe"

local MAX_MINE_DISTANCE = 10

local HIT_SOUND_ID = "rbxassetid://7650220708"
local DEBRIS_LIFETIME = 1.5
local DEBRIS_COUNT = 4

local HIT_FRAME = 33
local ANIMATION_FPS = 60

local HIT_SHAKE_INTENSITY = 0.3
local HIT_SHAKE_DURATION = 0.15
local BREAK_SHAKE_INTENSITY = 1.2
local BREAK_SHAKE_DURATION = 0.3

local ContentProvider = game:GetService("ContentProvider")
local preloadSound = Instance.new("Sound")
preloadSound.SoundId = HIT_SOUND_ID
ContentProvider:PreloadAsync({preloadSound})

local soundDuration = preloadSound.TimeLength
if soundDuration <= 0 then
	soundDuration = 0.5
end
preloadSound:Destroy()

local MINE_COOLDOWN = soundDuration + 0.1

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local currentTool: Tool? = nil
local idleAnimTrack: AnimationTrack? = nil
local hitAnimTrack: AnimationTrack? = nil
local lastMineTime = 0
local rockHealthBars: { [BasePart]: { gui: BillboardGui, bar: Frame, text: TextLabel } } = {}

local isMining = false
local currentMiningTarget: BasePart? = nil

local function applyScreenShake(intensity: number, duration: number)
	local camera = workspace.CurrentCamera
	if not camera then return end
	
	local startTime = tick()
	local originalCFrame = camera.CFrame
	
	local shakeConnection
	shakeConnection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		
		if elapsed >= duration then
			shakeConnection:Disconnect()
			return
		end
		
		local progress = elapsed / duration
		local currentIntensity = intensity * (1 - progress)
		
		local shakeOffset = Vector3.new(
			(math.random() - 0.5) * 2 * currentIntensity,
			(math.random() - 0.5) * 2 * currentIntensity,
			(math.random() - 0.5) * 2 * currentIntensity * 0.5
		)
		
		camera.CFrame = camera.CFrame * CFrame.new(shakeOffset)
	end)
end

local function isPickaxe(tool: Tool?): boolean
	if not tool then return false end
	return CollectionService:HasTag(tool, PICKAXE_TAG)
end

local function getHumanoid(): Humanoid?
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end

local function getAnimator(): Animator?
	local humanoid = getHumanoid()
	if not humanoid then return nil end
	return humanoid:FindFirstChildOfClass("Animator")
end

local function createAnimationTrack(animationId: string): AnimationTrack?
	if animationId == "rbxassetid://0" then return nil end
	
	local animator = getAnimator()
	if not animator then return nil end
	
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	
	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	
	animation:Destroy()
	
	if success then
		return track
	else
		warn("[MiningClient] Failed to load animation:", animationId)
		return nil
	end
end

local function stopIdleAnimation()
	if idleAnimTrack then
		idleAnimTrack:Stop()
		idleAnimTrack:Destroy()
		idleAnimTrack = nil
	end
end

local function startIdleAnimation()
	stopIdleAnimation()
	
	idleAnimTrack = createAnimationTrack(IDLE_ANIMATION_ID)
	if idleAnimTrack then
		idleAnimTrack.Looped = true
		idleAnimTrack.Priority = Enum.AnimationPriority.Movement
		idleAnimTrack:Play(0.1, 0.5)
	end
end

local function playHitAnimation(onHitFrame: (() -> ())?)
	local track = createAnimationTrack(HIT_ANIMATION_ID)
	if track then
		track.Looped = false
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0.1, 0.5)
		
		local hitTime = HIT_FRAME / ANIMATION_FPS
		
		if onHitFrame then
			task.delay(hitTime, function()
				if track and track.IsPlaying then
					onHitFrame()
				end
			end)
		end
		
		track.Stopped:Once(function()
			track:Destroy()
		end)
	else
		if onHitFrame then
			onHitFrame()
		end
	end
end

local function createImpactEffect(rock: BasePart)
	local originalSize = rock:GetAttribute("OriginalSize") or rock.Size
	
	if not rock:GetAttribute("OriginalSize") then
		rock:SetAttribute("OriginalSize", rock.Size)
	end
	
	local squashFactor = 0.85
	local expandFactor = 1.08
	local squashedSize = Vector3.new(
		originalSize.X * expandFactor,
		originalSize.Y * squashFactor,
		originalSize.Z * expandFactor
	)
	
	local squashTweenInfo = TweenInfo.new(
		0.08,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	
	local bounceTweenInfo = TweenInfo.new(
		0.35,
		Enum.EasingStyle.Elastic,
		Enum.EasingDirection.Out
	)
	
	local squashTween = TweenService:Create(rock, squashTweenInfo, { Size = squashedSize })
	local bounceTween = TweenService:Create(rock, bounceTweenInfo, { Size = originalSize })
	
	squashTween:Play()
	squashTween.Completed:Once(function()
		bounceTween:Play()
	end)
end

local function spawnDebris(rock: BasePart)
	local rockColor = rock.Color
	local rockMaterial = rock.Material
	local rockPosition = rock.Position
	
	for i = 1, DEBRIS_COUNT do
		local debris = Instance.new("Part")
		debris.Name = "MiningDebris"
		debris.Size = Vector3.new(
			math.random(3, 6) / 10,
			math.random(3, 6) / 10,
			math.random(3, 6) / 10
		)
		debris.Color = rockColor
		debris.Material = rockMaterial
		debris.Anchored = false
		debris.CanCollide = true
		debris.CanQuery = false
		debris.CanTouch = false
		
		local spawnOffset = Vector3.new(
			math.random(-10, 10) / 10,
			rock.Size.Y / 2 + 0.5,
			math.random(-10, 10) / 10
		)
		debris.Position = rockPosition + spawnOffset
		
		debris.Orientation = Vector3.new(
			math.random(0, 360),
			math.random(0, 360),
			math.random(0, 360)
		)
		
		debris.Parent = workspace
		
		local velocity = Vector3.new(
			math.random(-8, 8),
			math.random(8, 15),
			math.random(-8, 8)
		)
		debris:ApplyImpulse(velocity * debris:GetMass())
		
		debris:ApplyAngularImpulse(Vector3.new(
			math.random(-2, 2),
			math.random(-2, 2),
			math.random(-2, 2)
		))
		
		Debris:AddItem(debris, DEBRIS_LIFETIME)
	end
end

local function updateHealthBar(rock: BasePart, currentHealth: number, maxHealth: number)
	local data = rockHealthBars[rock]
	
	if not data then
		local gui = Instance.new("BillboardGui")
		gui.Name = "RockHealthBar"
		gui.Size = UDim2.new(4, 0, 0.6, 0)
		gui.StudsOffset = Vector3.new(0, rock.Size.Y / 2 + 1.5, 0)
		gui.AlwaysOnTop = false
		gui.MaxDistance = 30
		gui.Adornee = rock
		gui.Parent = rock
		
		local background = Instance.new("Frame")
		background.Name = "Background"
		background.Size = UDim2.new(1, 0, 1, 0)
		background.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
		background.BorderSizePixel = 0
		background.Parent = gui
		
		local bgCorner = Instance.new("UICorner")
		bgCorner.CornerRadius = UDim.new(0.3, 0)
		bgCorner.Parent = background
		
		local bar = Instance.new("Frame")
		bar.Name = "HealthBar"
		bar.Size = UDim2.new(1, 0, 1, 0)
		bar.BackgroundColor3 = Color3.fromRGB(60, 180, 60)
		bar.BorderSizePixel = 0
		bar.Parent = background
		
		local barCorner = Instance.new("UICorner")
		barCorner.CornerRadius = UDim.new(0.3, 0)
		barCorner.Parent = bar
		
		local text = Instance.new("TextLabel")
		text.Name = "HealthText"
		text.Size = UDim2.new(1, 0, 1, 0)
		text.BackgroundTransparency = 1
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0.5
		text.TextScaled = true
		text.Font = Enum.Font.GothamBold
		text.Parent = background
		
		data = { gui = gui, bar = bar, text = text }
		rockHealthBars[rock] = data
	end
	
	local healthPercent = math.clamp(currentHealth / maxHealth, 0, 1)
	
	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(data.bar, tweenInfo, {
		Size = UDim2.new(healthPercent, 0, 1, 0)
	})
	tween:Play()
	
	data.text.Text = string.format("%d/%d", math.max(0, currentHealth), maxHealth)
	
	local color = Color3.fromRGB(
		math.floor(180 + (1 - healthPercent) * 75),
		math.floor(180 * healthPercent),
		60
	)
	data.bar.BackgroundColor3 = color
end

local function removeHealthBar(rock: BasePart)
	local data = rockHealthBars[rock]
	if data then
		data.gui:Destroy()
		rockHealthBars[rock] = nil
	end
end

local function showDamageText(rock: BasePart, damage: number)
	local randomAngle = math.random() * math.pi * 2
	local randomSpeed = math.random(15, 30) / 10
	local directionX = math.cos(randomAngle) * randomSpeed
	local directionZ = math.sin(randomAngle) * randomSpeed
	local upwardSpeed = math.random(50, 70) / 10
	
	local gui = Instance.new("BillboardGui")
	gui.Name = "DamageText"
	gui.Size = UDim2.new(3, 0, 1.5, 0)
	gui.StudsOffset = Vector3.new(
		0,
		rock.Size.Y / 2 + 2,
		0
	)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 50
	gui.Adornee = rock
	gui.Parent = rock
	
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.new(1, 0, 1, 0)
	text.BackgroundTransparency = 1
	text.Text = "-" .. tostring(damage)
	text.TextColor3 = Color3.fromRGB(255, 80, 80)
	text.TextStrokeColor3 = Color3.new(0, 0, 0)
	text.TextStrokeTransparency = 0.3
	text.TextScaled = true
	text.Font = Enum.Font.GothamBlack
	text.Parent = gui
	
	local startOffset = gui.StudsOffset
	local duration = 0.8
	local gravity = 8
	local startTime = tick()
	
	local scaleTween = TweenService:Create(text, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(1.4, 0, 1.4, 0)
	})
	scaleTween:Play()
	
	local moveConnection
	moveConnection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local progress = math.clamp(elapsed / duration, 0, 1)
		
		if progress >= 1 then
			moveConnection:Disconnect()
			return
		end
		
		local x = startOffset.X + directionX * progress
		local z = startOffset.Z + directionZ * progress
		local y = startOffset.Y + (upwardSpeed * progress) - (gravity * progress * progress)
		
		gui.StudsOffset = Vector3.new(x, y, z)
	end)
	
	task.delay(0.3, function()
		local fadeTween = TweenService:Create(text, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
			TextStrokeTransparency = 1
		})
		fadeTween:Play()
	end)
	
	Debris:AddItem(gui, 1)
end

local function playHitSound(rock: BasePart)
	local sound = Instance.new("Sound")
	sound.SoundId = HIT_SOUND_ID
	sound.Volume = 0.8
	sound.PlaybackSpeed = 0.9 + math.random() * 0.2
	sound.Parent = rock
	sound:Play()
	
	Debris:AddItem(sound, 2)
end

local function attemptMine(rock: BasePart)
	local now = tick()
	if now - lastMineTime < MINE_COOLDOWN then
		return
	end
	lastMineTime = now
	
	if not isPickaxe(currentTool) then
		return
	end
	
	local character = player.Character
	if not character then return end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end
	
	local distance = (rock.Position - humanoidRootPart.Position).Magnitude
	if distance > MAX_MINE_DISTANCE then
		return
	end
	
	if not CollectionService:HasTag(rock, ROCK_TAG) then
		return
	end
	
	playHitAnimation(function()
		createImpactEffect(rock)
		spawnDebris(rock)
		playHitSound(rock)
		
		Remotes.Mine:FireServer(rock)
	end)
end

local function startMiningLoop()
	task.spawn(function()
		while isMining and currentMiningTarget do
			if not currentMiningTarget or not currentMiningTarget.Parent then
				isMining = false
				currentMiningTarget = nil
				break
			end
			
			local target = mouse.Target
			if target ~= currentMiningTarget then
				if target and CollectionService:HasTag(target, ROCK_TAG) then
					currentMiningTarget = target
				else
					isMining = false
					currentMiningTarget = nil
					break
				end
			end
			
			attemptMine(currentMiningTarget)
			
			task.wait(0.1)
		end
	end)
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local target = mouse.Target
		if target and CollectionService:HasTag(target, ROCK_TAG) then
			isMining = true
			currentMiningTarget = target
			startMiningLoop()
		end
	end
end

local function onInputEnded(input: InputObject, gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isMining = false
		currentMiningTarget = nil
	end
end

local function onTouchTap(touchPositions: { Vector2 }, gameProcessed: boolean)
	if gameProcessed then return end
	
	local target = mouse.Target
	if target and CollectionService:HasTag(target, ROCK_TAG) then
		attemptMine(target)
	end
end

local function onToolEquipped(tool: Tool)
	currentTool = tool
	
	if isPickaxe(tool) then
		startIdleAnimation()
	end
end

local function onToolUnequipped(tool: Tool)
	if currentTool == tool then
		currentTool = nil
	end
	
	stopIdleAnimation()
end

local function setupCharacter(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			onToolEquipped(child)
		end
	end)
	
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			onToolUnequipped(child)
		end
	end)
	
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			onToolEquipped(child)
			break
		end
	end
end

Remotes.MineResult.OnClientEvent:Connect(function(rock: BasePart, damage: number, newHealth: number, maxHealth: number, isBroken: boolean)
	showDamageText(rock, damage)
	
	if isBroken then
		removeHealthBar(rock)
		applyScreenShake(BREAK_SHAKE_INTENSITY, BREAK_SHAKE_DURATION)
	else
		updateHealthBar(rock, newHealth, maxHealth)
		applyScreenShake(HIT_SHAKE_INTENSITY, HIT_SHAKE_DURATION)
	end
end)

UserInputService.InputBegan:Connect(onInputBegan)
UserInputService.InputEnded:Connect(onInputEnded)
UserInputService.TouchTap:Connect(onTouchTap)

if player.Character then
	setupCharacter(player.Character)
end

player.CharacterAdded:Connect(setupCharacter)

CollectionService:GetInstanceRemovedSignal(ROCK_TAG):Connect(function(rock)
	if rock:IsA("BasePart") then
		removeHealthBar(rock)
	end
end)

print("[MiningClient] Initialized successfully!")
