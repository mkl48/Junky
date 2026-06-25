-- Junky
-- Bootstrap.lua
-- Plinko Labs
--
-- The single entry point for a side. Bootstrap:
--   1. stands up the Router + Network (the transport),
--   2. builds the shared runtime (injected Packages, Utilities, frozen Manifest, Player),
--   3. discovers module scripts and classifies them by name suffix,
--   4. filters by side (Controllers -> client, Managers -> server; Services boot on
--      whichever side discovers them -- so a Service is side-scoped by where it lives),
--   5. validates the Junction against what it found,
--   6. calls every module's :Start in priority order, each with its own Context,
--   7. returns a handle with :Inspect() and :Stop().
--
-- :Start is the single boot hook. Modules are required up front but never touch
-- each other; only the order of :Start matters, and that comes from the priority
-- maps. Timing-sensitive cross-module dependencies use Context:Await.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Router = require(script.Parent.Router)
local Network = require(script.Parent.Network)
local Context = require(script.Parent.Context)
local Priority = require(script.Parent.Priority)

local Bootstrap = {}

local RESERVED = {
	NetworkController = true,
	NetworkManager = true,
}

local function classify(name: string): string?
	if name:match("Controller$") then
		return "Controller"
	elseif name:match("Manager$") then
		return "Manager"
	elseif name:match("Service$") then
		return "Service"
	end
	return nil
end

local function deepFreeze(value: any): any
	if type(value) ~= "table" or table.isfrozen(value) then
		return value
	end
	for _, child in value do
		deepFreeze(child)
	end
	table.freeze(value)
	return value
end

local function collectModuleScripts(roots: { Instance }): { ModuleScript }
	local found = {}
	local seen = {}

	local function add(instance: Instance)
		if instance:IsA("ModuleScript") and not seen[instance] then
			seen[instance] = true
			table.insert(found, instance)
		end
	end

	for _, root in roots do
		add(root)
		for _, descendant in root:GetDescendants() do
			add(descendant)
		end
	end

	return found
end

-- Warn about Local destinations that name no module on this side (a likely typo).
-- Network destinations live on the other side, so they cannot be checked here.
local function validateJunction(junctionMap, present, side: string)
	local localMap = junctionMap.Local
	if not localMap then
		return
	end
	for domain, byDomain in localMap do
		for name, entry in byDomain do
			local destination = entry.Destination
			if destination and not present[destination] then
				warn(("[Junky] Local %s.%s routes to '%s', which is not a module on the %s side")
					:format(domain, name, destination, side))
			end
		end
	end
end

function Bootstrap.Boot(config, substance)
	assert(config and config.Junction, "[Junky] Configure requires config.Junction")

	local side = config.Side or (RunService:IsServer() and "Server" or "Client")

	local router = Router.new(config.Junction, side)
	local network = Network.new(router, side, substance)
	router:SetNetwork(network)
	network:Start()

	-- shared runtime ------------------------------------------------------
	-- Injected dependencies, reachable via Context:GetPackage. `Inject` is the
	-- name to use; `Packages` is accepted as an alias. Later sources win.
	local packages = {}
	for _, source in { config.Packages, config.Inject } do
		if source then
			for name, value in source do
				packages[name] = value
			end
		end
	end
	if config.Manifest ~= nil then
		packages.Manifest = deepFreeze(config.Manifest)
	end

	local instances = {} -- [name] = module table
	local kinds = {} -- [name] = "Controller" | "Manager" | "Service"

	-- The acting player: the LocalPlayer on the client, nil on the server (where
	-- there is no single player). Surfaced as Context.Player.
	local player = if side == "Client" then Players.LocalPlayer else nil

	local runtime = {
		Side = side,
		Player = player,
		Router = router,
		Network = network,
		Packages = packages,
		Utilities = config.Utilities or {},
		Modules = instances,
	}

	-- discover + classify + side-filter -----------------------------------
	local roots: { Instance }
	if config.Modules == nil then
		roots = {}
	elseif typeof(config.Modules) == "Instance" then
		roots = { config.Modules }
	else
		roots = config.Modules
	end

	for _, moduleScript in collectModuleScripts(roots) do
		local name = moduleScript.Name

		if RESERVED[name] then
			warn(("[Junky] '%s' is built into Junky and is ignored as a user module"):format(name))
			continue
		end

		local kind = classify(name)
		if not kind then
			continue
		end
		if kind == "Controller" and side ~= "Client" then
			continue
		end
		if kind == "Manager" and side ~= "Server" then
			continue
		end
		if instances[name] then
			warn(("[Junky] duplicate module name '%s' -- the second one is ignored"):format(name))
			continue
		end

		local ok, result = pcall(require, moduleScript)
		if not ok then
			warn(("[Junky] failed to require '%s': %s"):format(name, tostring(result)))
			continue
		end

		instances[name] = result
		kinds[name] = kind
	end

	-- order ---------------------------------------------------------------
	local present = {}
	for name in instances do
		present[name] = true
	end

	validateJunction(config.Junction, present, side)

	local order, unprioritized = Priority.Order(config.ClassPriority, config.StandalonePriority, present)
	for _, name in unprioritized do
		warn(("[Junky] %s has no entry in any priority map -- booting it last"):format(name))
	end

	-- one Context per module ----------------------------------------------
	local contexts = {}
	for _, name in order do
		contexts[name] = Context.new(name, runtime)
	end

	-- :Start in priority order -- the single boot hook. Controllers and Managers
	-- must implement it; Services may. Cross-module timing is handled by the
	-- priority maps and Context:Await, not by a second phase.
	for _, name in order do
		local moduleTable = instances[name]
		local kind = kinds[name]
		if type(moduleTable) == "table" and type(moduleTable.Start) == "function" then
			local ok, err = pcall(moduleTable.Start, moduleTable, contexts[name])
			if not ok then
				warn(("[Junky] %s:Start() errored: %s"):format(name, tostring(err)))
			end
		elseif kind ~= "Service" then
			warn(("[Junky] %s is a %s and must implement :Start()"):format(name, kind))
		end
	end

	-- handle --------------------------------------------------------------
	local stopped = false
	local handle = {
		Side = side,
		Router = router,
		Network = network,
		Modules = instances,
		Context = Context.new("Junky", runtime),
	}

	function handle:Inspect()
		return router:Inspect()
	end

	-- Tear down in reverse boot order: :Stop each module, then drop its routing
	-- entries and run its OnCleanup callbacks.
	function handle:Stop()
		if stopped then
			return
		end
		stopped = true
		for index = #order, 1, -1 do
			local name = order[index]
			local moduleTable = instances[name]
			if type(moduleTable) == "table" and type(moduleTable.Stop) == "function" then
				local ok, err = pcall(moduleTable.Stop, moduleTable)
				if not ok then
					warn(("[Junky] %s:Stop() errored: %s"):format(name, tostring(err)))
				end
			end
			contexts[name]:_teardown()
		end
	end

	return handle
end

return Bootstrap
