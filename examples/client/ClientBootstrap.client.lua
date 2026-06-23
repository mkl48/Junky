-- Example
-- client/ClientBootstrap.client.lua
-- Plinko Labs
--
-- The single client entry point. Lives in StarterPlayerScripts. Same call as the
-- server -- Junction detects the side and boots only the client-appropriate
-- modules (Controllers + client Services).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Junction = require(ReplicatedStorage.Packages.Junction)
local Shared = ReplicatedStorage.Shared
local LocalPlayer = Players.LocalPlayer

Junction.Ignite({
	Junction = require(Shared.Junction),
	Manifest = require(Shared.Manifest),
	ClassPriority = require(Shared.ClassPriorityMap),
	StandalonePriority = require(Shared.StandalonePriorityMap),

	Modules = {
		LocalPlayer.PlayerScripts.Modules,
		ReplicatedStorage.Shared.Services,
	},
})

print("[ClientBootstrap] Junction ignited (Client)")
