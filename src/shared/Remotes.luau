--[[
	Remotes.luau
	Shared module providing access to RemoteEvents for mining system.
	
	Usage:
		local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
		Remotes.Mine:FireServer(rock)  -- Client
		Remotes.Mine.OnServerEvent:Connect(...)  -- Server
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)

if not RemotesFolder then
	error("[Remotes] Could not find ReplicatedStorage.Remotes folder! Check your Rojo project.")
end

Remotes.Mine = RemotesFolder:WaitForChild("Mine")

Remotes.MineResult = RemotesFolder:WaitForChild("MineResult")

return Remotes
