-- Junky
-- init.lua
-- Plinko Labs
--
-- SSJA -- Single Script Junction Architecture.
--
-- One Bootstrap owns the lifecycle, one Junction map defines the routing topology,
-- one Context is the only surface modules talk through. Modules (Controllers,
-- Managers, Services) never require one another -- they Post, Request and Subscribe.
--
-- Usage (one Bootstrap script per side):
--
--   local Junky = require(ReplicatedStorage.Packages.Junky)
--
--   local app = Junky.Configure({
--       Junction = require(Shared.Junction),       -- the routing map
--       Manifest = require(Shared.Manifest),       -- read-only config
--       Modules = { ServerScriptService.Modules, Shared.Services },
--       ClassPriority = require(Shared.ClassPriorityMap),
--       StandalonePriority = require(Shared.StandalonePriorityMap),
--   })
--
--   -- app:Inspect()  -> live topology snapshot
--   -- app:Stop()     -> teardown (rare; mostly for tests / soft restarts)
--
-- Junky detects the side from RunService, finds Substance automatically, validates
-- the Junction, and calls every module's :Start in priority order, injecting a
-- Context into each.

local Bootstrap = require(script.Bootstrap)
local Reaction = require(script.Reaction)
local Types = require(script.Types)

export type Context = Types.Context
export type Config = Types.Config
export type App = Types.App
export type JunctionMap = Types.JunctionMap
export type Subscription = Types.Subscription
export type Reaction = Types.Reaction

local Junky = {}

-- The Await/Request handle type, exposed for code that constructs reactions directly.
Junky.Reaction = Reaction

-- The app from the most recent Configure on this side. Lets diagnostics call
-- Junky.Inspect() without threading the handle around.
local active = nil

local function resolveSubstance(explicit: any): any
	if explicit then
		return explicit
	end

	local candidates = {}
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
		"[Junky] could not locate Substance. Install ker/substance, or pass it explicitly: "
			.. "Junky.Configure({ Substance = require(path.to.Substance), ... })"
	)
end

-- Configures and boots this side. Call exactly once per side. Returns the app
-- handle (:Inspect, :Stop, .Context, .Modules).
function Junky.Configure(config: Types.Config): Types.App
	local substance = resolveSubstance(config and config.Substance)
	active = Bootstrap.Boot(config, substance)
	return active
end

-- The live routing topology of the active app, or nil if Configure hasn't run.
function Junky.Inspect()
	return if active then active:Inspect() else nil
end

return Junky
