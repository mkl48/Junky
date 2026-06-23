-- Example
-- client/ClientBootstrap.client.lua
-- Plinko Labs
--
-- The single client entry point. Lives in StarterPlayerScripts. Same call as the
-- server -- Junky detects the side and boots only the client-appropriate modules
-- (Controllers + client Services).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Junky = require(ReplicatedStorage.Packages.Junky)
local Shared = ReplicatedStorage.Shared
local LocalPlayer = Players.LocalPlayer

Junky.Configure({
	Junction = require(Shared.Junction),
	Manifest = require(Shared.Manifest),
	ClassPriority = require(Shared.ClassPriorityMap),
	StandalonePriority = require(Shared.StandalonePriorityMap),

	Modules = {
		LocalPlayer.PlayerScripts.Modules,
		ReplicatedStorage.Shared.Services,
	},
})

print("[ClientBootstrap] Junky configured (Client)")
