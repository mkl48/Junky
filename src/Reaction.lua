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
