-- Example
-- server/CharacterManager.lua
-- Plinko Labs
--
-- The server half of the Character domain and the counterpart of
-- CharacterController. It receives the network hit, applies authoritative logic
-- via its own Service, posts the result back, and answers QueryHealth requests.
--
-- It wires a Guard, a responder, and a subscriber in :Start. Note the sanctioned
-- exception: a Manager may call its own domain Service via Context:GetService,
-- never through require.

local CharacterManager = {}

function CharacterManager:Start(context)
	local Network = context:Network("Character")
	local CharacterService = context:GetService("CharacterService")

	-- Guard: drop nonsense hits at the topology edge before any handler sees them.
	-- A guard returning false vetoes the post.
	Network:Guard("Damaged", function(hitData)
		return type(hitData) == "table" and type(hitData.Damage) == "number" and hitData.Damage > 0
	end)

	-- Responder: answer a request with a value. The client gets it as a Reaction.
	Network:Respond("QueryHealth", function(_payload, player)
		return CharacterService:GetHealth(player)
	end)

	-- Server-side Network subscribers receive the sending Player as a trailing
	-- argument -- never trust the player field inside the payload itself.
	Network:Subscribe("Damaged", function(hitData, player)
		local state = CharacterService:ApplyDamage(player, hitData)
		print(("[CharacterManager] %s took %d -> Health=%d"):format(player.Name, hitData.Damage, state.Health))

		-- Authoritative result back to that one client.
		Network:PostTo(player, "Ragdoll", state)
	end)
end

return CharacterManager
