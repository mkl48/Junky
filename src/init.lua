-- Junction
-- init.lua
-- Plinko Labs
--
-- SSJA -- Single Script Junction Architecture.
--
-- One Bootstrap owns the lifecycle, one Junction defines the routing topology, one
-- Context is the only surface modules talk through. Modules (Controllers,
-- Managers, Services) never require one another -- they Post and Subscribe.
--
-- Usage (one Bootstrap script per side):
--
--   local Junction = require(ReplicatedStorage.Packages.Junction)
--
--   Junction.Ignite({
--       Junction = require(Shared.Junction),       -- the routing map
--       Manifest = require(Shared.Manifest),       -- read-only config
--       Modules = { ServerScriptService.Modules, Shared.Services },
--       ClassPriority = require(Shared.ClassPriorityMap),
--       StandalonePriority = require(Shared.StandalonePriorityMap),
--   })
--
-- Junction figures out the side from RunService, finds Substance automatically,
-- boots every module in priority order and injects a Context into each :Start.

local Bootstrap = require(script.Bootstrap)
local Reaction = require(script.Reaction)
local Types = require(script.Types)

export type Context = Types.Context
export type Config = Types.Config
export type JunctionMap = Types.JunctionMap
export type Subscription = Types.Subscription
export type Reaction = Types.Reaction

local Junction = {}

-- The Await handle type, exposed for code that constructs reactions directly.
Junction.Reaction = Reaction

local function resolveSubstance(explicit: any): any
	if explicit then
		return explicit
	end

	local candidates = {}

	-- Wally places dependencies as siblings of the consuming package.
	if script.Parent then
		table.insert(candidates, script.Parent:FindFirstChild("Substance"))
	end

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local packagesFolder = ReplicatedStorage:FindFirstChild("Packages")
	if packagesFolder then
		table.insert(candidates, packagesFolder:FindFirstChild("Substance"))
	end
	table.insert(candidates, ReplicatedStorage:FindFirstChild("Substance"))

	for _, candidate in candidates do
		if candidate then
			return require(candidate)
		end
	end

	error(
		"[Junction] could not locate Substance. Install ker/substance, or pass it explicitly: "
			.. "Junction.Ignite({ Substance = require(path.to.Substance), ... })"
	)
end

-- Boots this side: stands up the bus, discovers modules, injects Context, and
-- calls :Start in priority order. Call exactly once per side.
function Junction.Ignite(config: Types.Config)
	local substance = resolveSubstance(config and config.Substance)
	return Bootstrap.Ignite(config, substance)
end

return Junction
