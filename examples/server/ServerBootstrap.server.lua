-- Example
-- server/ServerBootstrap.server.lua
-- Plinko Labs
--
-- The single server entry point. Lives in ServerScriptService. There is exactly
-- one of these per side. It points Junction at the config + module folders and
-- ignites; Junction does the rest (discovery, ordering, Context injection).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Junction = require(ReplicatedStorage.Packages.Junction)
local Shared = ReplicatedStorage.Shared

Junction.Ignite({
	Junction = require(Shared.Junction),
	Manifest = require(Shared.Manifest),
	ClassPriority = require(Shared.ClassPriorityMap),
	StandalonePriority = require(Shared.StandalonePriorityMap),

	-- Managers live here; shared Services live in ReplicatedStorage. Junction
	-- side-filters automatically (Managers boot on the server, Controllers do not).
	Modules = {
		ServerScriptService.Modules,
		ReplicatedStorage.Shared.Services,
	},
})

print("[ServerBootstrap] Junction ignited (Server)")
