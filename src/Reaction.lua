-- Junky
-- Reaction.lua
-- Plinko Labs
--
-- The async handle returned by Context:Await and Context:Request. It is a deferred
-- resolved externally (by the Router when a key fires, or by a request response).
-- Its method surface mirrors Substance's Reaction so the two are interchangeable
-- at call sites: :Next / :Throw / :Catch / :Conclusion / :Map / :Timeout / :Await /
-- :Cancel.

local Reaction = {}
Reaction.__index = Reaction

type State = "Pending" | "Resolved" | "Rejected" | "Cancelled"

export type Reaction = {
	Next: (self: Reaction, fn: (any) -> any) -> Reaction,
	Throw: (self: Reaction, fn: (any) -> any) -> Reaction,
	Catch: (self: Reaction, fn: (any) -> any) -> Reaction,
	Conclusion: (self: Reaction, fn: () -> ()) -> Reaction,
	Map: (self: Reaction, fn: (any) -> any) -> Reaction,
	Timeout: (self: Reaction, seconds: number) -> Reaction,
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

-- A reaction that is already resolved with `value`. Used for cached/latched paths.
function Reaction.resolved(value: any): Reaction
	local reaction = Reaction.new()
	reaction:Resolve(value)
	return reaction
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

-- Resolve / Reject are driven by the framework (Router, Network). Left unprefixed
-- so the runtime can settle a reaction it handed out.
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

function Reaction:Catch(fn: (any) -> any): Reaction
	return self:Throw(fn)
end

function Reaction:Conclusion(fn: () -> ()): Reaction
	if self._state ~= "Pending" then
		task.spawn(fn)
	else
		table.insert(self._finally, fn)
	end
	return self
end

-- Transform the resolved value into a new Reaction. Errors in `fn` reject the child.
function Reaction:Map(fn: (any) -> any): Reaction
	local child = Reaction.new()
	self:Next(function(value)
		local ok, result = pcall(fn, value)
		if ok then
			child:Resolve(result)
		else
			child:Reject(result)
		end
	end)
	self:Throw(function(reason)
		child:Reject(reason)
	end)
	return child
end

-- Reject with "timeout" if still pending after `seconds`.
function Reaction:Timeout(seconds: number): Reaction
	task.delay(seconds, function()
		if self._state == "Pending" then
			self:Reject("timeout")
		end
	end)
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
