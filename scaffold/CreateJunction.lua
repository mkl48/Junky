-- Junction scaffold
-- Auto-generated from src/ -- regenerate after any src/ edit; this is a snapshot, not live-synced.
-- Run in Roblox Studio's Command Bar to build the full Junction ModuleScript tree under ReplicatedStorage.
-- (Junction also needs Substance present -- run CreateSubstance, or install both via Wally.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local existing = ReplicatedStorage:FindFirstChild("Junction")
if existing then
	existing:Destroy()
end

local n_Junction = Instance.new("ModuleScript")
n_Junction.Name = "Junction"
n_Junction.Source = [====[
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
]====]

local n_Bootstrap = Instance.new("ModuleScript")
n_Bootstrap.Name = "Bootstrap"
n_Bootstrap.Source = [====[
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
]====]
n_Bootstrap.Parent = n_Junction

local n_Context = Instance.new("ModuleScript")
n_Context.Name = "Context"
n_Context.Source = [====[
-- Junction
-- Context.lua
-- Plinko Labs
--
-- Context is the only surface a module ever talks through. Bootstrap builds one
-- Context per module, each bound to that module's name as its `Source`, so the
-- Junction's Dynamic(source) resolvers know who is posting without the caller
-- ever passing it.
--
-- The scoped shorthands -- Context:Network(domain) / Context:Local(domain) -- bind
-- a namespace + domain once so calls read as Network:Post("Damaged", data).

local Context = {}
Context.__index = Context

local NetworkScope = {}
NetworkScope.__index = NetworkScope

local LocalScope = {}
LocalScope.__index = LocalScope

function Context.new(source: string, runtime)
	local self = setmetatable({}, Context)
	self.Source = source
	self.Side = runtime.Side
	self._runtime = runtime
	self._networkScopes = {}
	self._localScopes = {}
	return self
end

function Context:Post(namespace: string, domain: string, name: string, ...)
	if namespace == "Local" then
		self._runtime.Router:PostLocal(self.Source, domain, name, ...)
	elseif namespace == "Network" then
		self._runtime.Router:PostNetwork(self.Source, domain, name, nil, ...)
	else
		error(("[Junction] unknown namespace '%s' (expected 'Network' or 'Local')"):format(tostring(namespace)))
	end
end

function Context:Subscribe(namespace: string, domain: string, name: string, handler: (...any) -> ())
	return self._runtime.Router:Subscribe(self.Source, namespace, domain, name, handler)
end

function Context:Network(domain: string)
	local scope = self._networkScopes[domain]
	if not scope then
		scope = setmetatable({ _ctx = self, _domain = domain }, NetworkScope)
		self._networkScopes[domain] = scope
	end
	return scope
end

function Context:Local(domain: string)
	local scope = self._localScopes[domain]
	if not scope then
		scope = setmetatable({ _ctx = self, _domain = domain }, LocalScope)
		self._localScopes[domain] = scope
	end
	return scope
end

function Context:GetPackage(name: string): any
	return self._runtime.Packages[name]
end

function Context:GetUtility(name: string): any
	return self._runtime.Utilities[name]
end

-- Returns a booted module by name. Intended for the one sanctioned direct call in
-- SSJA: a Manager reaching its own domain Service. Everything else should go
-- through Post / Subscribe.
function Context:GetService(name: string): any
	return self._runtime.Modules[name]
end

function Context:Await(key: string)
	return self._runtime.Router:Await(key)
end

-- Network scope ------------------------------------------------------------
-- On the client, :Post sends to the server. On the server, :Post (and the
-- explicit :Broadcast) fire to all clients, while :PostTo targets one.

function NetworkScope:Post(name: string, ...)
	local ctx = self._ctx
	ctx._runtime.Router:PostNetwork(ctx.Source, self._domain, name, nil, ...)
end

function NetworkScope:PostTo(target: Player, name: string, ...)
	local ctx = self._ctx
	assert(ctx.Side == "Server", "[Junction] Network:PostTo can only be called on the server")
	ctx._runtime.Router:PostNetwork(ctx.Source, self._domain, name, target, ...)
end

function NetworkScope:Broadcast(name: string, ...)
	local ctx = self._ctx
	assert(ctx.Side == "Server", "[Junction] Network:Broadcast can only be called on the server")
	ctx._runtime.Router:PostNetwork(ctx.Source, self._domain, name, nil, ...)
end

function NetworkScope:Subscribe(name: string, handler: (...any) -> ())
	local ctx = self._ctx
	return ctx._runtime.Router:Subscribe(ctx.Source, "Network", self._domain, name, handler)
end

-- Local scope --------------------------------------------------------------

function LocalScope:Post(name: string, ...)
	local ctx = self._ctx
	ctx._runtime.Router:PostLocal(ctx.Source, self._domain, name, ...)
end

function LocalScope:Subscribe(name: string, handler: (...any) -> ())
	local ctx = self._ctx
	return ctx._runtime.Router:Subscribe(ctx.Source, "Local", self._domain, name, handler)
end

return Context
]====]
n_Context.Parent = n_Junction

local n_Network = Instance.new("ModuleScript")
n_Network.Name = "Network"
n_Network.Source = [====[
-- Junction
-- Network.lua
-- Plinko Labs
--
-- The Network component plays the NetworkController / NetworkManager role from the
-- SSJA spec: it is the only part of Junction that touches the wire. Everything
-- else is blind to transport. It is backed by Substance -- a single Strict channel
-- carries every Network-namespace event as a typed envelope.
--
-- Envelope shape:
--   d  = domain          (string)
--   n  = name            (string)
--   to = destination     (string; "" when the Junction resolved no destination)
--   a  = packed args     (array)
--
-- Direction is handled by Substance: a client :Post fires to the server, a server
-- :Post with no target fires to all clients, and a server :Post with a target
-- fires to that one client. On arrival the envelope is unpacked and handed to the
-- Router, which delivers it to the destination module's subscribers.

local Network = {}
Network.__index = Network

local CHANNEL = "JunctionBus"

function Network.new(router, side: string, substance)
	local self = setmetatable({}, Network)
	self.Router = router
	self.Side = side
	self.Substance = substance
	self._bus = nil
	return self
end

function Network:Start()
	local Substance = self.Substance
	local Type = Substance.Type

	-- One typed envelope, one channel, both sides. Validation runs in Studio only.
	local Envelope = Substance.Define("JunctionEnvelope", {
		d = Type.string(),
		n = Type.string(),
		to = Type.string(),
		a = Type.array(Type.any()),
	})
	Envelope:Compose(CHANNEL, "Strict")
	self._bus = Envelope

	Envelope:Subscribe(function(envelope, player)
		self:_receive(envelope, player)
	end)
end

function Network:Send(domain: string, name: string, destination: string?, target: Player?, packed)
	local arr = table.move(packed, 1, packed.n, 1, table.create(packed.n))
	local envelope = {
		d = domain,
		n = name,
		to = destination or "",
		a = arr,
	}
	-- Fire-and-forget. Substance returns a Reaction; we intentionally drop it.
	self._bus:Post(envelope, target)
end

function Network:_receive(envelope, player: Player?)
	local destination = if envelope.to ~= "" then envelope.to else nil
	local packed = table.pack(table.unpack(envelope.a))
	self.Router:Receive(envelope.d, envelope.n, destination, packed, player)
end

return Network
]====]
n_Network.Parent = n_Junction

local n_Priority = Instance.new("ModuleScript")
n_Priority.Name = "Priority"
n_Priority.Source = [====[
-- Junction
-- Priority.lua
-- Plinko Labs
--
-- Resolves the two priority maps into one flat boot order:
--
--   1. ClassPriorityMap     -- tier-based, ascending tier number. Controllers and
--                              Managers. Order within a tier is not guaranteed.
--   2. StandalonePriorityMap -- numeric, ascending. Services.
--
-- Class modules boot before Services; cross-group timing dependencies are meant to
-- be handled with Context:Await rather than by reordering. Any discovered module
-- absent from both maps is appended last so nothing is silently dropped.

local Priority = {}

function Priority.Order(
	classMap: { [number]: { string } }?,
	standaloneMap: { [string]: number }?,
	present: { [string]: boolean }
): ({ string }, { string })
	local ordered = {}
	local seen = {}
	local unprioritized = {}

	if classMap then
		local tiers = {}
		for tier in classMap do
			table.insert(tiers, tier)
		end
		table.sort(tiers)

		for _, tier in tiers do
			for _, name in classMap[tier] do
				if present[name] and not seen[name] then
					seen[name] = true
					table.insert(ordered, name)
				end
			end
		end
	end

	if standaloneMap then
		local services = {}
		for name, priority in standaloneMap do
			if present[name] and not seen[name] then
				table.insert(services, { name = name, priority = priority })
			end
		end
		table.sort(services, function(a, b)
			return a.priority < b.priority
		end)

		for _, item in services do
			seen[item.name] = true
			table.insert(ordered, item.name)
		end
	end

	for name in present do
		if not seen[name] then
			seen[name] = true
			table.insert(ordered, name)
			table.insert(unprioritized, name)
		end
	end

	return ordered, unprioritized
end

return Priority
]====]
n_Priority.Parent = n_Junction

local n_Reaction = Instance.new("ModuleScript")
n_Reaction.Name = "Reaction"
n_Reaction.Source = [====[
-- Junction
-- Reaction.lua
-- Plinko Labs
--
-- The async handle returned by Context:Await. It is a one-shot deferred: it sits
-- Pending until the awaited key is first posted anywhere on this side, then
-- resolves with that first payload. The method surface (:Next / :Throw /
-- :Conclusion / :Await / :Cancel) deliberately mirrors Substance's Reaction so the
-- two are interchangeable at call sites.
--
-- Unlike Substance's Reaction, this one is resolved externally (by the Router when
-- a key fires) rather than by running an attempt function, which is why it lives in
-- Junction rather than reusing Substance's internal module.

local Reaction = {}
Reaction.__index = Reaction

type State = "Pending" | "Resolved" | "Rejected" | "Cancelled"

export type Reaction = {
	Next: (self: Reaction, fn: (any) -> any) -> Reaction,
	Throw: (self: Reaction, fn: (any) -> any) -> Reaction,
	Conclusion: (self: Reaction, fn: () -> ()) -> Reaction,
	Await: (self: Reaction) -> any,
	Cancel: (self: Reaction) -> (),
}

function Reaction.new(): Reaction
	local self = setmetatable({}, Reaction)
	self._state = "Pending" :: State
	self._value = nil :: any
	self._next = {}
	self._throw = {}
	self._finally = {}
	return (self :: any) :: Reaction
end

function Reaction:_settle(state: State, value: any)
	if self._state ~= "Pending" then
		return
	end
	self._state = state
	self._value = value

	local handlers = if state == "Resolved" then self._next else self._throw
	for _, fn in handlers do
		task.spawn(fn, value)
	end
	for _, fn in self._finally do
		task.spawn(fn)
	end

	table.clear(self._next)
	table.clear(self._throw)
	table.clear(self._finally)
end

-- Called by the Router. Not part of the public Reaction surface.
function Reaction:Resolve(value: any)
	self:_settle("Resolved", value)
end

function Reaction:Reject(reason: any)
	self:_settle("Rejected", reason)
end

function Reaction:Next(fn: (any) -> any): Reaction
	if self._state == "Resolved" then
		task.spawn(fn, self._value)
	elseif self._state == "Pending" then
		table.insert(self._next, fn)
	end
	return self
end

function Reaction:Throw(fn: (any) -> any): Reaction
	if self._state == "Rejected" then
		task.spawn(fn, self._value)
	elseif self._state == "Pending" then
		table.insert(self._throw, fn)
	end
	return self
end

function Reaction:Conclusion(fn: () -> ()): Reaction
	if self._state ~= "Pending" then
		task.spawn(fn)
	else
		table.insert(self._finally, fn)
	end
	return self
end

function Reaction:Await(): any
	while self._state == "Pending" do
		task.wait()
	end
	if self._state == "Resolved" then
		return self._value
	end
	error(self._value, 0)
end

function Reaction:Cancel()
	self:_settle("Cancelled", "cancelled")
end

return Reaction
]====]
n_Reaction.Parent = n_Junction

local n_Router = Instance.new("ModuleScript")
n_Router.Name = "Router"
n_Router.Source = [====[
-- Junction
-- Router.lua
-- Plinko Labs
--
-- The Router is the in-process engine behind Context. It owns three things:
--
--   1. The Junction map  -- the static topology of where every event goes.
--   2. The subscriber registry  -- who is listening, tagged by owning module.
--   3. The Await registry  -- one-shot latches keyed by "Domain.Name".
--
-- Posting resolves a Junction entry to a destination module (Dynamic(source)
-- takes precedence over Destination), then either delivers in-process (Local) or
-- hands off to Network (Network). Delivery is filtered by destination: only
-- subscribers owned by the resolved destination module receive the event. That is
-- what makes the Junction the single source of truth -- a subscriber cannot
-- receive an event the Junction did not route to it.

local Reaction = require(script.Parent.Reaction)

local Router = {}
Router.__index = Router

type SubRecord = { Owner: string, Handler: (...any) -> () }

function Router.new(junctionMap, side: string)
	local self = setmetatable({}, Router)
	self.Junction = junctionMap or {}
	self.Side = side
	self._subscribers = {} -- [ns][domain][name] = { SubRecord, ... }
	self._awaitLatch = {} -- [key] = { value } ; presence means latched
	self._awaitWaiters = {} -- [key] = { Reaction, ... }
	self._network = nil
	return self
end

function Router:SetNetwork(network)
	self._network = network
end

-- subscriber bucket --------------------------------------------------------

local function bucket(self, ns: string, domain: string, name: string)
	local nsT = self._subscribers[ns]
	if not nsT then
		nsT = {}
		self._subscribers[ns] = nsT
	end
	local dT = nsT[domain]
	if not dT then
		dT = {}
		nsT[domain] = dT
	end
	local list = dT[name]
	if not list then
		list = {}
		dT[name] = list
	end
	return list
end

-- Junction resolution ------------------------------------------------------

function Router:_entry(ns: string, domain: string, name: string)
	local nsT = self.Junction[ns]
	if not nsT then
		return nil
	end
	local dT = nsT[domain]
	if not dT then
		return nil
	end
	return dT[name]
end

function Router:_resolveDestination(entry, source: string): string?
	if not entry then
		return nil
	end
	if entry.Dynamic then
		local resolved = entry.Dynamic(source)
		if resolved then
			return resolved
		end
	end
	return entry.Destination
end

-- Await --------------------------------------------------------------------

function Router:_signalAwait(domain: string, name: string, value: any)
	local key = domain .. "." .. name

	if self._awaitLatch[key] == nil then
		self._awaitLatch[key] = { value }
	end

	local waiters = self._awaitWaiters[key]
	if waiters then
		self._awaitWaiters[key] = nil
		for _, reaction in waiters do
			reaction:Resolve(value)
		end
	end
end

function Router:Await(key: string)
	local reaction = Reaction.new()

	local latched = self._awaitLatch[key]
	if latched then
		reaction:Resolve(latched[1])
		return reaction
	end

	local waiters = self._awaitWaiters[key]
	if not waiters then
		waiters = {}
		self._awaitWaiters[key] = waiters
	end
	table.insert(waiters, reaction)
	return reaction
end

-- delivery -----------------------------------------------------------------

local function fire(handler: (...any) -> (), packed, trailing: any)
	if trailing == nil then
		task.spawn(handler, table.unpack(packed, 1, packed.n))
	else
		local n = packed.n
		local copy = table.move(packed, 1, n, 1, table.create(n + 1))
		copy[n + 1] = trailing
		task.spawn(handler, table.unpack(copy, 1, n + 1))
	end
end

-- Deliver to local subscribers on (ns, domain, name), filtered by destination.
-- `trailing` is appended after the payload args (used to hand the sending Player
-- to server-side Network subscribers).
function Router:Deliver(ns: string, domain: string, name: string, destination: string?, packed, trailing: any)
	self:_signalAwait(domain, name, packed[1])

	local nsT = self._subscribers[ns]
	local list = nsT and nsT[domain] and nsT[domain][name]
	if not list then
		return
	end

	for _, record in table.clone(list) do
		if destination and record.Owner ~= destination then
			continue
		end
		fire(record.Handler, packed, trailing)
	end
end

-- public posting -----------------------------------------------------------

function Router:Subscribe(owner: string, ns: string, domain: string, name: string, handler: (...any) -> ())
	local list = bucket(self, ns, domain, name)
	local record: SubRecord = { Owner = owner, Handler = handler }
	table.insert(list, record)

	return {
		Cancel = function()
			local index = table.find(list, record)
			if index then
				table.remove(list, index)
			end
		end,
	}
end

function Router:PostLocal(source: string, domain: string, name: string, ...)
	local entry = self:_entry("Local", domain, name)
	if not entry then
		warn(("[Junction] no Local Junction entry for %s.%s (posted by %s)"):format(domain, name, source))
	end

	local destination = self:_resolveDestination(entry, source)
	self:Deliver("Local", domain, name, destination, table.pack(...), nil)
end

function Router:PostNetwork(source: string, domain: string, name: string, target: Player?, ...)
	local entry = self:_entry("Network", domain, name)
	if not entry then
		warn(("[Junction] no Network Junction entry for %s.%s (posted by %s)"):format(domain, name, source))
	end

	local destination = self:_resolveDestination(entry, source)
	local packed = table.pack(...)

	-- Resolve same-side awaiters at post time (e.g. a server Service awaiting a
	-- key another server module posts as Network), in addition to the receiving
	-- side resolving them on arrival.
	self:_signalAwait(domain, name, packed[1])

	if self._network then
		self._network:Send(domain, name, destination, target, packed)
	end
end

-- Called by Network when an envelope arrives from the other side.
function Router:Receive(domain: string, name: string, destination: string?, packed, sender: Player?)
	self:Deliver("Network", domain, name, destination, packed, sender)
end

return Router
]====]
n_Router.Parent = n_Junction

local n_Types = Instance.new("ModuleScript")
n_Types.Name = "Types"
n_Types.Source = [====[
-- Junction
-- Types.lua
-- Plinko Labs
--
-- Shared type surface for the SSJA runtime. Nothing here executes; it exists so
-- Controllers / Managers / Services can annotate against a single Context type.

export type Side = "Server" | "Client"

export type Namespace = "Network" | "Local"

-- A single Junction entry: a static Destination plus an optional Dynamic resolver
-- that overrides Destination based on who posted the event.
export type JunctionEntry = {
	Destination: string?,
	Dynamic: ((source: string) -> string?)?,
}

export type DomainMap = { [string]: JunctionEntry }
export type NamespaceMap = { [string]: DomainMap }

-- The routing topology. The single source of truth for where events go.
export type JunctionMap = {
	Network: NamespaceMap?,
	Local: NamespaceMap?,
}

export type Subscription = {
	Cancel: (self: Subscription) -> (),
}

-- A one-shot async handle resolved when an Await key is first posted. Mirrors the
-- surface of Substance's Reaction so the two feel identical in use.
export type Reaction = {
	Next: (self: Reaction, fn: (any) -> any) -> Reaction,
	Throw: (self: Reaction, fn: (any) -> any) -> Reaction,
	Conclusion: (self: Reaction, fn: () -> ()) -> Reaction,
	Await: (self: Reaction) -> any,
	Cancel: (self: Reaction) -> (),
}

export type NetworkScope = {
	Post: (self: NetworkScope, name: string, ...any) -> (),
	PostTo: (self: NetworkScope, target: Player, name: string, ...any) -> (),
	Broadcast: (self: NetworkScope, name: string, ...any) -> (),
	Subscribe: (self: NetworkScope, name: string, handler: (...any) -> ()) -> Subscription,
}

export type LocalScope = {
	Post: (self: LocalScope, name: string, ...any) -> (),
	Subscribe: (self: LocalScope, name: string, handler: (...any) -> ()) -> Subscription,
}

export type Context = {
	Side: Side,
	Source: string,
	Post: (self: Context, namespace: Namespace, domain: string, name: string, ...any) -> (),
	Subscribe: (self: Context, namespace: Namespace, domain: string, name: string, handler: (...any) -> ()) -> Subscription,
	Network: (self: Context, domain: string) -> NetworkScope,
	Local: (self: Context, domain: string) -> LocalScope,
	GetPackage: (self: Context, name: string) -> any,
	GetUtility: (self: Context, name: string) -> any,
	GetService: (self: Context, name: string) -> any,
	Await: (self: Context, key: string) -> Reaction,
}

-- A module is anything with an optional :Start. Controllers / Managers must
-- implement it; Services may.
export type Module = {
	Start: ((self: any, context: Context) -> ())?,
	[any]: any,
}

export type Config = {
	-- The routing topology. Required.
	Junction: JunctionMap,
	-- Read-only game config, exposed as Context:GetPackage("Manifest").
	Manifest: any?,
	-- Instance(s) to scan for module scripts. ModuleScripts whose name ends in
	-- Controller / Manager / Service are booted.
	Modules: (Instance | { Instance })?,
	-- Tier-based boot order for Controllers and Managers.
	ClassPriority: { [number]: { string } }?,
	-- Numeric boot order for Services.
	StandalonePriority: { [string]: number }?,
	-- Extra named packages exposed via Context:GetPackage.
	Packages: { [string]: any }?,
	-- Named utilities exposed via Context:GetUtility.
	Utilities: { [string]: any }?,
	-- Override side detection. Defaults to RunService:IsServer().
	Side: Side?,
	-- Explicit Substance module. Auto-resolved from Packages/ReplicatedStorage if omitted.
	Substance: any?,
}

return {}
]====]
n_Types.Parent = n_Junction

n_Junction.Parent = ReplicatedStorage

print("[Junction] scaffold built under ReplicatedStorage.Junction")
