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
