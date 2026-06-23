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
