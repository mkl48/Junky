-- Junky scaffold
-- SetupSSJA.lua
-- Plinko Labs
--
-- Run in Roblox Studio's Command Bar to lay down the recommended SSJA project
-- structure with a tiny working Ping/Pong domain that runs end-to-end on boot:
--
--   ReplicatedStorage/Shared/            Junction (map), Manifest, priority maps
--   ReplicatedStorage/Shared/Services/   SessionService (both sides)
--   ServerScriptService/Modules/         PingManager + ServerBootstrap
--   StarterPlayerScripts/Modules/        PingController + ClientBootstrap
--
-- Requires the Junky package present (via Wally at ReplicatedStorage.Packages
-- .Junky, or run CreateJunky first to drop it at ReplicatedStorage.Junky). The
-- generated Bootstraps find it either way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
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

-- shared ---------------------------------------------------------------------

local Shared = folder(ReplicatedStorage, "Shared")
local Services = folder(Shared, "Services")

script_(Shared, "ModuleScript", "Junction", [====[
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

script_(Shared, "ModuleScript", "Manifest", [====[
-- Read-only game config. Deep-frozen at boot; never mutate at runtime.
return {
	Enums = {},
	Keybinds = {},
	PlayerSettings = { MaxHealth = 100, BaseSpeed = 16 },
	GameConfig = {},
}
]====])

script_(Shared, "ModuleScript", "ClassPriorityMap", [====[
-- Tier-based boot order for Controllers and Managers (ascending tier).
return {
	[1] = { "PingController", "PingManager" },
}
]====])

script_(Shared, "ModuleScript", "StandalonePriorityMap", [====[
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

-- server ---------------------------------------------------------------------

local ServerModules = folder(ServerScriptService, "Modules")

script_(ServerModules, "ModuleScript", "PingManager", [====[
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

script_(ServerScriptService, "Script", "ServerBootstrap", [====[
-- The single server entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function findJunky()
	local packages = ReplicatedStorage:FindFirstChild("Packages")
	if packages and packages:FindFirstChild("Junky") then
		return require(packages.Junky)
	end
	return require(ReplicatedStorage:WaitForChild("Junky"))
end

local Junky = findJunky()
local Shared = ReplicatedStorage:WaitForChild("Shared")

Junky.Configure({
	Junction = require(Shared.Junction),
	Manifest = require(Shared.Manifest),
	ClassPriority = require(Shared.ClassPriorityMap),
	StandalonePriority = require(Shared.StandalonePriorityMap),
	Modules = {
		ServerScriptService:WaitForChild("Modules"),
		Shared:WaitForChild("Services"),
	},
})

print("[ServerBootstrap] Junky configured (Server)")
]====])

-- client ---------------------------------------------------------------------

local ClientModules = folder(StarterPlayerScripts, "Modules")

script_(ClientModules, "ModuleScript", "PingController", [====[
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

script_(StarterPlayerScripts, "LocalScript", "ClientBootstrap", [====[
-- The single client entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local function findJunky()
	local packages = ReplicatedStorage:FindFirstChild("Packages")
	if packages and packages:FindFirstChild("Junky") then
		return require(packages.Junky)
	end
	return require(ReplicatedStorage:WaitForChild("Junky"))
end

local Junky = findJunky()
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")

Junky.Configure({
	Junction = require(Shared.Junction),
	Manifest = require(Shared.Manifest),
	ClassPriority = require(Shared.ClassPriorityMap),
	StandalonePriority = require(Shared.StandalonePriorityMap),
	Modules = {
		PlayerScripts:WaitForChild("Modules"),
		Shared:WaitForChild("Services"),
	},
})

print("[ClientBootstrap] Junky configured (Client)")
]====])

print("[Junky] SSJA project scaffolded. Press Play -- expect a Ping/Pong round trip in the output.")
