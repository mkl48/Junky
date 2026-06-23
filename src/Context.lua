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
