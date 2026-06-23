-- Junction
-- Bootstrap.lua
-- Plinko Labs
--
-- The single entry point for a side. Bootstrap:
--   1. stands up the Router + Network (the transport),
--   2. builds the shared runtime (Packages, Utilities, frozen Manifest),
--   3. discovers module scripts and classifies them by name suffix,
--   4. filters by side (Controllers -> client, Managers -> server, Services -> both),
--   5. calls :Start(Context) in priority order, each with its own Context.
--
-- Modules are required up front but never touch each other -- only :Start runs
-- logic, and the order of :Start is the only order that matters.

local RunService = game:GetService("RunService")

local Router = require(script.Parent.Router)
local Network = require(script.Parent.Network)
local Context = require(script.Parent.Context)
local Priority = require(script.Parent.Priority)

local Bootstrap = {}

-- NetworkController / NetworkManager are built into Junction; if a project still
-- ships modules by those names they are ignored rather than booted.
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
	if type(value) ~= "table" then
		return value
	end
	for _, child in value do
		deepFreeze(child)
	end
	if not table.isfrozen(value) then
		table.freeze(value)
	end
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

function Bootstrap.Ignite(config, substance)
	assert(config and config.Junction, "[Junction] Ignite requires config.Junction")

	local side = config.Side or (RunService:IsServer() and "Server" or "Client")

	local router = Router.new(config.Junction, side)
	local network = Network.new(router, side, substance)
	router:SetNetwork(network)
	network:Start()

	-- shared runtime ------------------------------------------------------
	local packages = {}
	if config.Packages then
		for name, value in config.Packages do
			packages[name] = value
		end
	end
	if config.Manifest ~= nil then
		packages.Manifest = deepFreeze(config.Manifest)
	end

	-- Booted modules, exposed via Context:GetService. The table is filled below
	-- but referenced by the runtime now, so by the time any :Start runs every
	-- module is reachable. This is the one sanctioned direct-call path (a Manager
	-- calling its own domain Service); everything else goes through Post/Subscribe.
	local instances = {} -- [name] = module table
	local kinds = {} -- [name] = "Controller" | "Manager" | "Service"

	local runtime = {
		Side = side,
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
			warn(("[Junction] '%s' is built into Junction and is ignored as a user module"):format(name))
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
			warn(("[Junction] duplicate module name '%s' -- the second one is ignored"):format(name))
			continue
		end

		local ok, result = pcall(require, moduleScript)
		if not ok then
			warn(("[Junction] failed to require '%s': %s"):format(name, tostring(result)))
			continue
		end

		instances[name] = result
		kinds[name] = kind
	end

	-- order + Start -------------------------------------------------------
	local present = {}
	for name in instances do
		present[name] = true
	end

	local order, unprioritized = Priority.Order(config.ClassPriority, config.StandalonePriority, present)
	for _, name in unprioritized do
		warn(("[Junction] %s has no entry in any priority map -- booting it last"):format(name))
	end

	for _, name in order do
		local moduleTable = instances[name]
		local kind = kinds[name]
		local context = Context.new(name, runtime)

		if type(moduleTable) == "table" and type(moduleTable.Start) == "function" then
			local ok, err = pcall(moduleTable.Start, moduleTable, context)
			if not ok then
				warn(("[Junction] %s:Start() errored: %s"):format(name, tostring(err)))
			end
		elseif kind ~= "Service" then
			warn(("[Junction] %s is a %s and must implement :Start()"):format(name, kind))
		end
	end

	return {
		Side = side,
		Router = router,
		Network = network,
		Modules = instances,
		-- A free-standing Context for code that boots modules but also needs the
		-- bus itself (tests, glue, late wiring).
		Context = Context.new("Bootstrap", runtime),
	}
end

return Bootstrap
