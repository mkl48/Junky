-- Junky scaffold
-- SetupSSJA.lua
-- Plinko Labs
--
-- Run in Roblox Studio's Command Bar to lay down the recommended SSJA project
-- structure with a tiny working Ping/Pong domain that runs end-to-end on boot:
--
--   ReplicatedStorage/Shared/Assets/                shared assets (empty)
--   ReplicatedStorage/Shared/Modules/Packages/      Junky + deps live here
--   ReplicatedStorage/Shared/Modules/Utility/       Junction, Manifest, priority maps
--   ReplicatedStorage/Shared/Modules/Services/      SessionService (both sides)
--   ReplicatedStorage/Client/Modules/Controllers/   PingController (client)
--   ServerStorage/Modules/Managers/                 PingManager (server-only)
--   ServerScriptService/ServerBootstrap             server entry point
--   StarterPlayerScripts/ClientBootstrap            client entry point
--
-- Requires the Junky package present. Put it at ReplicatedStorage.Shared.Modules
-- .Packages.Junky (Wally configured to that path, or move it there after the
-- command-line installer drops it at ReplicatedStorage.Junky). The generated
-- Bootstraps look there first, then fall back to ReplicatedStorage.Packages.Junky
-- and ReplicatedStorage.Junky, so any of those work.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")

local function folder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function script_(parent: Instance, className: string, name: string, source: string)
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local s = Instance.new(className)
	s.Name = name
	;(s :: any).Source = source
	s.Parent = parent
	return s
end

-- The Junky-finder both Bootstraps embed: this architecture's path first, then
-- the default Wally and no-Wally installer locations.
local FIND_JUNKY = [====[
local function findJunky()
	local rs = game:GetService("ReplicatedStorage")
	local shared = rs:FindFirstChild("Shared")
	if shared then
		local modules = shared:FindFirstChild("Modules")
		local packages = modules and modules:FindFirstChild("Packages")
		if packages and packages:FindFirstChild("Junky") then
			return require(packages.Junky)
		end
	end
	local packages = rs:FindFirstChild("Packages")
	if packages and packages:FindFirstChild("Junky") then
		return require(packages.Junky)
	end
	return require(rs:WaitForChild("Junky"))
end
]====]

-- ReplicatedStorage/Shared -----------------------------------------------------

local Shared = folder(ReplicatedStorage, "Shared")
folder(Shared, "Assets")

local SharedModules = folder(Shared, "Modules")
folder(SharedModules, "Packages") -- Junky + deps live here
local Utility = folder(SharedModules, "Utility")
local Services = folder(SharedModules, "Services")

script_(Utility, "ModuleScript", "Junction", [====[
-- The routing topology. Declare every event here, once, with where it goes.
return {
	Network = {
		System = {
			Ping = { Destination = "PingManager" },     -- client -> server
			Pong = { Destination = "PingController" },   -- server -> client
		},
	},
	Local = {},
}
]====])

script_(Utility, "ModuleScript", "Manifest", [====[
-- Read-only game config. Deep-frozen at boot; never mutate at runtime.
return {
	Enums = {},
	Keybinds = {},
	PlayerSettings = { MaxHealth = 100, BaseSpeed = 16 },
	GameConfig = {},
}
]====])

script_(Utility, "ModuleScript", "ClassPriorityMap", [====[
-- Tier-based boot order for Controllers and Managers (ascending tier).
return {
	[1] = { "PingController", "PingManager" },
}
]====])

script_(Utility, "ModuleScript", "StandalonePriorityMap", [====[
-- Numeric boot order for Services (ascending).
return {
	SessionService = 1,
}
]====])

script_(Services, "ModuleScript", "SessionService", [====[
-- A Service owns one slice of state and is decoupled from how data reaches it.
local SessionService = {}
SessionService.State = {}

function SessionService:Start(context)
	-- :Start is optional for Services; here just to show the hook.
	print("[SessionService] ready on", context.Side)
end

return SessionService
]====])

-- ReplicatedStorage/Client -----------------------------------------------------

local Client = folder(ReplicatedStorage, "Client")
local ClientModules = folder(Client, "Modules")
folder(ClientModules, "Packages") -- client-only deps (empty)
folder(ClientModules, "Utility") -- client-only helpers (empty)
local Controllers = folder(ClientModules, "Controllers")

script_(Controllers, "ModuleScript", "PingController", [====[
-- Client half of the System domain. Sends a Ping on boot, awaits the Pong.
local PingController = {}

function PingController:Start(context)
	local System = context:Network("System")

	System:Subscribe("Pong", function(sentAt)
		print(("[PingController] pong! round trip ~%.3fs"):format(os.clock() - sentAt))
	end)

	task.delay(1, function()
		System:Post("Ping", os.clock())
	end)
end

return PingController
]====])

-- ServerStorage ----------------------------------------------------------------

local ServerModules = folder(ServerStorage, "Modules")
local Managers = folder(ServerModules, "Managers")
folder(ServerModules, "Packages") -- server-only deps (empty)
folder(ServerModules, "Utility") -- server-only helpers (empty)

script_(Managers, "ModuleScript", "PingManager", [====[
-- Server half of the System domain. Receives Ping, replies Pong to the sender.
local PingManager = {}

function PingManager:Start(context)
	local System = context:Network("System")

	-- Server-side Network subscribers get the sending Player as a trailing arg.
	System:Subscribe("Ping", function(sentAt, player)
		print("[PingManager] ping from", player.Name)
		System:PostTo(player, "Pong", sentAt)
	end)
end

return PingManager
]====])

-- ServerScriptService ----------------------------------------------------------

script_(ServerScriptService, "Script", "ServerBootstrap", [====[
-- The single server entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

]====] .. FIND_JUNKY .. [====[

local Junky = findJunky()
local Utility = ReplicatedStorage:WaitForChild("Shared").Modules.Utility
local Services = ReplicatedStorage.Shared.Modules.Services

Junky.Configure({
	Junction = require(Utility.Junction),
	Manifest = require(Utility.Manifest),
	ClassPriority = require(Utility.ClassPriorityMap),
	StandalonePriority = require(Utility.StandalonePriorityMap),
	Modules = {
		ServerStorage:WaitForChild("Modules"),
		Services,
	},
})

print("[ServerBootstrap] Junky configured (Server)")
]====])

-- StarterPlayerScripts ---------------------------------------------------------

script_(StarterPlayerScripts, "LocalScript", "ClientBootstrap", [====[
-- The single client entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

]====] .. FIND_JUNKY .. [====[

local Junky = findJunky()
local SharedModules = ReplicatedStorage:WaitForChild("Shared").Modules
local ClientModules = ReplicatedStorage:WaitForChild("Client").Modules

Junky.Configure({
	Junction = require(SharedModules.Utility.Junction),
	Manifest = require(SharedModules.Utility.Manifest),
	ClassPriority = require(SharedModules.Utility.ClassPriorityMap),
	StandalonePriority = require(SharedModules.Utility.StandalonePriorityMap),
	Modules = {
		ClientModules,
		SharedModules.Services,
	},
})

print("[ClientBootstrap] Junky configured (Client)")
]====])

print("[Junky] SSJA project scaffolded. Press Play -- expect a Ping/Pong round trip in the output.")
