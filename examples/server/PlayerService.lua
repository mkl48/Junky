-- Example
-- server/PlayerService.lua
-- Plinko Labs
--
-- Owner of the Player session slice. Loads a profile on join and announces it on
-- the Local bus. CharacterService is listening, but PlayerService neither knows
-- nor cares -- it just posts Player.DataLoaded.

local Players = game:GetService("Players")

local PlayerService = {}

function PlayerService:Start(context)
	local Player = context:Local("Player")
	local manifest = context:GetPackage("Manifest")

	local function onPlayer(player)
		-- Pretend this came from a DataStore / ProfileStore load.
		local data = {
			Player = player,
			MaxHealth = manifest.PlayerSettings.MaxHealth,
		}
		Player:Post("DataLoaded", data)
	end

	Players.PlayerAdded:Connect(onPlayer)

	-- Catch players who joined before boot. Deferred so every Service has finished
	-- :Start (and subscribed) before we post -- posts during the synchronous boot
	-- would race subscribers that boot later.
	task.defer(function()
		for _, player in Players:GetPlayers() do
			onPlayer(player)
		end
	end)
end

return PlayerService
