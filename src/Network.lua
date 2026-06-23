-- Junky
-- Network.lua
-- Plinko Labs
--
-- The only part of Junky that touches the wire (the NetworkController /
-- NetworkManager role). Backed by Substance with two channels:
--
--   * "JunkyBus"   (Strict / RemoteEvent)    -- fire-and-forget Post.
--   * "JunkySolve" (Solve  / RemoteFunction)  -- Request/Response.
--
-- Both carry the same typed envelope:
--   d  = domain   n = name   to = destination ("" if none)   a = packed args
--
-- Direction is handled by Substance: a client send fires/invokes the server; a
-- server send with no target fires all clients; a server send with a target hits
-- that one client. On arrival the envelope is unpacked and handed to the Router --
-- Deliver for Signals, Answer (which returns a value) for Solves.

local Reaction = require(script.Parent.Reaction)

local Network = {}
Network.__index = Network

local SIGNAL_CHANNEL = "JunkyBus"
local SOLVE_CHANNEL = "JunkySolve"

function Network.new(router, side: string, substance)
	local self = setmetatable({}, Network)
	self.Router = router
	self.Side = side
	self.Substance = substance
	self._signal = nil
	self._solve = nil
	return self
end

function Network:Start()
	local Substance = self.Substance
	local Type = Substance.Type

	local function envelopeAtom(name: string)
		return Substance.Define(name, {
			d = Type.string(),
			n = Type.string(),
			to = Type.string(),
			a = Type.array(Type.any()),
		})
	end

	-- fire-and-forget channel
	local signal = envelopeAtom("JunkySignalEnvelope")
	signal:Compose(SIGNAL_CHANNEL, "Strict")
	signal:Subscribe(function(envelope, player)
		self:_onSignal(envelope, player)
	end)
	self._signal = signal

	-- request/response channel
	local solve = envelopeAtom("JunkySolveEnvelope")
	solve:Compose(SOLVE_CHANNEL, "Solve")
	solve:Subscribe(function(envelope, player)
		return self:_onSolve(envelope, player)
	end)
	self._solve = solve
end

local function pack(domain, name, destination, packed)
	local arr = table.move(packed, 1, packed.n, 1, table.create(packed.n))
	return {
		d = domain,
		n = name,
		to = destination or "",
		a = arr,
	}
end

local function unpackArgs(envelope)
	return table.pack(table.unpack(envelope.a))
end

local function destOf(envelope): string?
	return if envelope.to ~= "" then envelope.to else nil
end

-- Post: fire-and-forget. Substance returns a Reaction we intentionally drop.
function Network:Send(domain: string, name: string, destination: string?, target: Player?, packed)
	self._signal:Post(pack(domain, name, destination, packed), target)
end

-- Request: returns a Junky Reaction resolved with the responder's value.
function Network:Request(domain: string, name: string, destination: string?, target: Player?, packed)
	local reaction = Reaction.new()
	local solveReaction = self._solve:Post(pack(domain, name, destination, packed), target)

	-- Substance's Solve Post yields the RemoteFunction return through its own
	-- Reaction; bridge it onto ours so callers always get the Junky surface.
	solveReaction:Next(function(response)
		reaction:Resolve(response)
	end)
	solveReaction:Throw(function(err)
		reaction:Reject(err)
	end)

	return reaction
end

function Network:_onSignal(envelope, player: Player?)
	self.Router:Receive(envelope.d, envelope.n, destOf(envelope), unpackArgs(envelope), player)
end

function Network:_onSolve(envelope, player: Player?): any
	return self.Router:Answer(envelope.d, envelope.n, destOf(envelope), unpackArgs(envelope), player)
end

return Network
