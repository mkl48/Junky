-- Example
-- server/ServerBootstrap.server.lua
-- Plinko Labs
--
-- The single server entry point. Lives in ServerScriptService. There is exactly
-- one of these per side. It points Junky at the config + module folders and calls
-- Configure; Junky does the rest (discovery, ordering, Context injection).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Junky = require(ReplicatedStorage.Packages.Junky)
local Shared = ReplicatedStorage.Shared

local app = Junky.Configure({
	Junction = require(Shared.Junction),
	Manifest = require(Shared.Manifest),
	ClassPriority = require(Shared.ClassPriorityMap),
	StandalonePriority = require(Shared.StandalonePriorityMap),

	-- Managers live here; shared Services live in ReplicatedStorage. Junky
	-- side-filters automatically (Managers boot on the server, Controllers do not).
	Modules = {
		ServerScriptService.Modules,
		ReplicatedStorage.Shared.Services,
	},
})

print("[ServerBootstrap] Junky configured (Server)")
-- print(app:Inspect()) -- uncomment to dump the live routing topology
