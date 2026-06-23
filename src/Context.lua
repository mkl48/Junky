-- Junky
-- Context.lua
-- Plinko Labs
--
-- The only surface a module talks through. Bootstrap builds one Context per module,
-- bound to that module's name as `Source`, so Junction Dynamic(source) resolvers
-- know who is posting without the caller passing it.
--
-- Surface:
--   Post / Subscribe / Once            -- fire-and-forget
--   Request / Respond                  -- request/response (returns a Reaction)
--   Guard                              -- veto predicate on an event
--   Await                              -- one-shot latch on "Domain.Name"
--   GetPackage / GetUtility / GetService
--   OnCleanup                          -- run on module teardown (handle:Stop)
--   Inspect                            -- live topology snapshot
--   Network(domain) / Local(domain)    -- scoped shorthands

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
	self._cleanups = {}
	return self
end

-- generic (namespace-explicit) surface -------------------------------------

function Context:Post(namespace: string, domain: string, name: string, ...)
	local router = self._runtime.Router
	if namespace == "Local" then
		router:PostLocal(self.Source, domain, name, ...)
	elseif namespace == "Network" then
		router:PostNetwork(self.Source, domain, name, nil, ...)
	else
		error(("[Junky] unknown namespace '%s' (expected 'Network' or 'Local')"):format(tostring(namespace)))
	end
end

function Context:Subscribe(namespace: string, domain: string, name: string, handler: (...any) -> ())
	return self._runtime.Router:Subscribe(self.Source, namespace, domain, name, handler)
end

function Context:Once(namespace: string, domain: string, name: string, handler: (...any) -> ())
	local subscription
	subscription = self._runtime.Router:Subscribe(self.Source, namespace, domain, name, function(...)
		subscription.Cancel()
		handler(...)
	end)
	return subscription
end

function Context:Request(namespace: string, domain: string, name: string, ...)
	local router = self._runtime.Router
	if namespace == "Local" then
		return router:RequestLocal(self.Source, domain, name, ...)
	elseif namespace == "Network" then
		return router:RequestNetwork(self.Source, domain, name, nil, ...)
	end
	error(("[Junky] unknown namespace '%s'"):format(tostring(namespace)))
end

function Context:Respond(namespace: string, domain: string, name: string, handler: (...any) -> any)
	return self._runtime.Router:Respond(self.Source, namespace, domain, name, handler)
end

function Context:Guard(namespace: string, domain: string, name: string, predicate: (...any) -> boolean)
	return self._runtime.Router:Guard(self.Source, namespace, domain, name, predicate)
end

function Context:Await(key: string)
	return self._runtime.Router:Await(key)
end

-- packages / services ------------------------------------------------------

function Context:GetPackage(name: string): any
	return self._runtime.Packages[name]
end

function Context:GetUtility(name: string): any
	return self._runtime.Utilities[name]
end

-- The one sanctioned direct call in SSJA: a Manager reaching its own domain
-- Service. Everything else should go through Post / Request / Subscribe.
function Context:GetService(name: string): any
	return self._runtime.Modules[name]
end

-- lifecycle / diagnostics --------------------------------------------------

function Context:OnCleanup(fn: () -> ())
	table.insert(self._cleanups, fn)
end

function Context:Inspect()
	return self._runtime.Router:Inspect()
end

-- Internal: run by Bootstrap's handle:Stop.
function Context:_teardown()
	for _, fn in self._cleanups do
		task.spawn(fn)
	end
	table.clear(self._cleanups)
	self._runtime.Router:CancelOwner(self.Source)
end

-- scoped shorthands --------------------------------------------------------

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

-- Network scope: on the client :Post/:Request go to the server; on the server
-- :Post/:Broadcast fire to all clients and :PostTo/:RequestFrom target one.

function NetworkScope:Post(name: string, ...)
	local ctx = self._ctx
	ctx._runtime.Router:PostNetwork(ctx.Source, self._domain, name, nil, ...)
end

function NetworkScope:PostTo(target: Player, name: string, ...)
	local ctx = self._ctx
	assert(ctx.Side == "Server", "[Junky] Network:PostTo can only be called on the server")
	ctx._runtime.Router:PostNetwork(ctx.Source, self._domain, name, target, ...)
end

function NetworkScope:Broadcast(name: string, ...)
	local ctx = self._ctx
	assert(ctx.Side == "Server", "[Junky] Network:Broadcast can only be called on the server")
	ctx._runtime.Router:PostNetwork(ctx.Source, self._domain, name, nil, ...)
end

function NetworkScope:Request(name: string, ...)
	local ctx = self._ctx
	return ctx._runtime.Router:RequestNetwork(ctx.Source, self._domain, name, nil, ...)
end

function NetworkScope:RequestFrom(target: Player, name: string, ...)
	local ctx = self._ctx
	assert(ctx.Side == "Server", "[Junky] Network:RequestFrom can only be called on the server")
	return ctx._runtime.Router:RequestNetwork(ctx.Source, self._domain, name, target, ...)
end

function NetworkScope:Subscribe(name: string, handler: (...any) -> ())
	local ctx = self._ctx
	return ctx._runtime.Router:Subscribe(ctx.Source, "Network", self._domain, name, handler)
end

function NetworkScope:Once(name: string, handler: (...any) -> ())
	return self._ctx:Once("Network", self._domain, name, handler)
end

function NetworkScope:Respond(name: string, handler: (...any) -> any)
	local ctx = self._ctx
	return ctx._runtime.Router:Respond(ctx.Source, "Network", self._domain, name, handler)
end

function NetworkScope:Guard(name: string, predicate: (...any) -> boolean)
	local ctx = self._ctx
	return ctx._runtime.Router:Guard(ctx.Source, "Network", self._domain, name, predicate)
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

function LocalScope:Once(name: string, handler: (...any) -> ())
	return self._ctx:Once("Local", self._domain, name, handler)
end

function LocalScope:Request(name: string, ...)
	local ctx = self._ctx
	return ctx._runtime.Router:RequestLocal(ctx.Source, self._domain, name, ...)
end

function LocalScope:Respond(name: string, handler: (...any) -> any)
	local ctx = self._ctx
	return ctx._runtime.Router:Respond(ctx.Source, "Local", self._domain, name, handler)
end

function LocalScope:Guard(name: string, predicate: (...any) -> boolean)
	local ctx = self._ctx
	return ctx._runtime.Router:Guard(ctx.Source, "Local", self._domain, name, predicate)
end

return Context
