-- Junky
-- Router.lua
-- Plinko Labs
--
-- The in-process engine behind Context. It owns:
--
--   1. The Junction map        -- the static topology of where every event goes.
--   2. The subscriber registry -- who listens, tagged by owning module.
--   3. The responder registry  -- who answers Requests (one responder per event).
--   4. The guard registry      -- veto predicates that gate a Post/Request.
--   5. The Await registry       -- one-shot latches keyed by "Domain.Name".
--
-- Posting resolves a Junction entry to a destination (Dynamic(source) beats
-- Destination), runs guards, then delivers in-process (Local) or hands to Network
-- (Network). Delivery is destination-filtered: only subscribers owned by the
-- resolved destination receive the event -- a subscriber cannot receive an event
-- the Junction did not route to it.

local Reaction = require(script.Parent.Reaction)

local Router = {}
Router.__index = Router

type SubRecord = { Owner: string, Handler: (...any) -> () }
type GuardRecord = { Owner: string, Predicate: (...any) -> boolean }
type Responder = { Owner: string, Handler: (...any) -> any }

function Router.new(junctionMap, side: string)
	local self = setmetatable({}, Router)
	self.Junction = junctionMap or {}
	self.Side = side
	self._subscribers = {} -- [ns][domain][name] = { SubRecord, ... }
	self._responders = {} -- [ns][domain][name] = Responder
	self._guards = {} -- [ns][domain][name] = { GuardRecord, ... }
	self._awaitLatch = {} -- [key] = { value } ; presence means latched
	self._awaitWaiters = {} -- [key] = { Reaction, ... }
	self._network = nil
	return self
end

function Router:SetNetwork(network)
	self._network = network
end

-- nested-table helpers -----------------------------------------------------

local function reach(root, ns: string, domain: string, name: string, create: boolean)
	local nsT = root[ns]
	if not nsT then
		if not create then
			return nil
		end
		nsT = {}
		root[ns] = nsT
	end
	local dT = nsT[domain]
	if not dT then
		if not create then
			return nil
		end
		dT = {}
		nsT[domain] = dT
	end
	return dT
end

-- Junction resolution ------------------------------------------------------

function Router:_entry(ns: string, domain: string, name: string)
	local dT = reach(self.Junction, ns, domain, name, false)
	return dT and dT[name]
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

-- guards -------------------------------------------------------------------

function Router:Guard(owner: string, ns: string, domain: string, name: string, predicate: (...any) -> boolean)
	local dT = reach(self._guards, ns, domain, name, true)
	local list = dT[name]
	if not list then
		list = {}
		dT[name] = list
	end
	local record: GuardRecord = { Owner = owner, Predicate = predicate }
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

function Router:_passesGuards(ns: string, domain: string, name: string, packed): boolean
	local dT = reach(self._guards, ns, domain, name, false)
	local list = dT and dT[name]
	if not list then
		return true
	end
	for _, record in table.clone(list) do
		local ok, allowed = pcall(record.Predicate, table.unpack(packed, 1, packed.n))
		if not ok then
			warn(("[Junky] guard on %s.%s.%s (%s) errored: %s"):format(ns, domain, name, record.Owner, tostring(allowed)))
			return false
		end
		if allowed == false then
			return false
		end
	end
	return true
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
	local latched = self._awaitLatch[key]
	if latched then
		return Reaction.resolved(latched[1])
	end

	local reaction = Reaction.new()
	local waiters = self._awaitWaiters[key]
	if not waiters then
		waiters = {}
		self._awaitWaiters[key] = waiters
	end
	table.insert(waiters, reaction)
	return reaction
end

-- subscribe / deliver ------------------------------------------------------

function Router:Subscribe(owner: string, ns: string, domain: string, name: string, handler: (...any) -> ())
	local dT = reach(self._subscribers, ns, domain, name, true)
	local list = dT[name]
	if not list then
		list = {}
		dT[name] = list
	end
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

function Router:Deliver(ns: string, domain: string, name: string, destination: string?, packed, trailing: any)
	self:_signalAwait(domain, name, packed[1])

	local dT = reach(self._subscribers, ns, domain, name, false)
	local list = dT and dT[name]
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

-- responders ---------------------------------------------------------------

function Router:Respond(owner: string, ns: string, domain: string, name: string, handler: (...any) -> any)
	local dT = reach(self._responders, ns, domain, name, true)
	if dT[name] then
		warn(("[Junky] responder for %s.%s.%s replaced (was %s, now %s)"):format(ns, domain, name, dT[name].Owner, owner))
	end
	dT[name] = { Owner = owner, Handler = handler } :: Responder

	return {
		Cancel = function()
			if dT[name] and dT[name].Owner == owner then
				dT[name] = nil
			end
		end,
	}
end

-- Invoke the responder for an event, honoring destination filtering. Returns the
-- responder's value (or nil + an error string on failure).
function Router:Invoke(ns: string, domain: string, name: string, destination: string?, packed, trailing: any): (any, string?)
	local dT = reach(self._responders, ns, domain, name, false)
	local responder = dT and dT[name]
	if not responder then
		return nil, ("no responder for %s.%s.%s"):format(ns, domain, name)
	end
	if destination and responder.Owner ~= destination then
		return nil, ("%s.%s.%s routes to %s but its responder is owned by %s"):format(ns, domain, name, destination, responder.Owner)
	end

	local args
	if trailing ~= nil then
		local n = packed.n
		args = table.move(packed, 1, n, 1, table.create(n + 1))
		args[n + 1] = trailing
		args.n = n + 1
	else
		args = packed
	end

	local ok, result = pcall(responder.Handler, table.unpack(args, 1, args.n))
	if not ok then
		return nil, tostring(result)
	end
	return result, nil
end

-- posting ------------------------------------------------------------------

function Router:PostLocal(source: string, domain: string, name: string, ...)
	local entry = self:_entry("Local", domain, name)
	if not entry then
		warn(("[Junky] no Local Junction entry for %s.%s (posted by %s)"):format(domain, name, source))
	end

	local packed = table.pack(...)
	if not self:_passesGuards("Local", domain, name, packed) then
		return
	end

	local destination = self:_resolveDestination(entry, source)
	self:Deliver("Local", domain, name, destination, packed, nil)
end

function Router:PostNetwork(source: string, domain: string, name: string, target: Player?, ...)
	local entry = self:_entry("Network", domain, name)
	if not entry then
		warn(("[Junky] no Network Junction entry for %s.%s (posted by %s)"):format(domain, name, source))
	end

	local packed = table.pack(...)
	if not self:_passesGuards("Network", domain, name, packed) then
		return
	end

	local destination = self:_resolveDestination(entry, source)

	-- Same-side awaiters resolve at post time, in addition to the receiving side.
	self:_signalAwait(domain, name, packed[1])

	if self._network then
		self._network:Send(domain, name, destination, target, packed)
	end
end

-- requests -----------------------------------------------------------------

function Router:RequestLocal(source: string, domain: string, name: string, ...)
	local entry = self:_entry("Local", domain, name)
	if not entry then
		warn(("[Junky] no Local Junction entry for %s.%s (requested by %s)"):format(domain, name, source))
	end
	local packed = table.pack(...)

	if not self:_passesGuards("Local", domain, name, packed) then
		return Reaction.new() -- stays pending; the request was vetoed
	end

	local destination = self:_resolveDestination(entry, source)
	local result, err = self:Invoke("Local", domain, name, destination, packed, nil)
	if err then
		local reaction = Reaction.new()
		reaction:Reject(err)
		return reaction
	end
	return Reaction.resolved(result)
end

function Router:RequestNetwork(source: string, domain: string, name: string, target: Player?, ...)
	local entry = self:_entry("Network", domain, name)
	if not entry then
		warn(("[Junky] no Network Junction entry for %s.%s (requested by %s)"):format(domain, name, source))
	end
	local packed = table.pack(...)

	if not self:_passesGuards("Network", domain, name, packed) then
		return Reaction.new()
	end

	local destination = self:_resolveDestination(entry, source)
	if not self._network then
		local reaction = Reaction.new()
		reaction:Reject("network unavailable")
		return reaction
	end
	return self._network:Request(domain, name, destination, target, packed)
end

-- Called by Network when a Signal envelope arrives from the other side.
function Router:Receive(domain: string, name: string, destination: string?, packed, sender: Player?)
	self:Deliver("Network", domain, name, destination, packed, sender)
end

-- Called by Network when a Solve (request) envelope arrives. Returns the response.
function Router:Answer(domain: string, name: string, destination: string?, packed, sender: Player?): any
	local result, err = self:Invoke("Network", domain, name, destination, packed, sender)
	if err then
		warn(("[Junky] request %s.%s could not be answered: %s"):format(domain, name, err))
		return nil
	end
	return result
end

-- lifecycle / introspection ------------------------------------------------

-- Remove every subscriber, responder and guard owned by a module. Used by
-- handle:Stop and module teardown.
function Router:CancelOwner(owner: string)
	for _, byNs in self._subscribers do
		for _, byDomain in byNs do
			for _, list in byDomain do
				for index = #list, 1, -1 do
					if list[index].Owner == owner then
						table.remove(list, index)
					end
				end
			end
		end
	end
	for _, byNs in self._responders do
		for _, byDomain in byNs do
			for name, responder in byDomain do
				if responder.Owner == owner then
					byDomain[name] = nil
				end
			end
		end
	end
	for _, byNs in self._guards do
		for _, byDomain in byNs do
			for _, list in byDomain do
				for index = #list, 1, -1 do
					if list[index].Owner == owner then
						table.remove(list, index)
					end
				end
			end
		end
	end
end

-- A snapshot of the live routing topology, for diagnostics.
function Router:Inspect()
	local function flatten(root, valueFn)
		local out = {}
		for ns, byNs in root do
			for domain, byDomain in byNs do
				for name, value in byDomain do
					out[("%s.%s.%s"):format(ns, domain, name)] = valueFn(value)
				end
			end
		end
		return out
	end

	local subscribers = flatten(self._subscribers, function(list)
		local owners = {}
		for _, record in list do
			table.insert(owners, record.Owner)
		end
		return owners
	end)

	local responders = flatten(self._responders, function(responder)
		return responder.Owner
	end)

	local guards = flatten(self._guards, function(list)
		return #list
	end)

	local latched = {}
	for key in self._awaitLatch do
		table.insert(latched, key)
	end

	return {
		Side = self.Side,
		Subscribers = subscribers,
		Responders = responders,
		Guards = guards,
		AwaitLatched = latched,
	}
end

return Router
