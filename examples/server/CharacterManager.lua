-- Example
-- server/CharacterManager.lua
-- Plinko Labs
--
-- The server half of the Character domain and the counterpart of
-- CharacterController. It receives the network hit, applies authoritative logic
-- via its own Service, and posts the result back to the originating client.
--
-- Note the sanctioned exception: a Manager may call its own domain Service. It
-- does so through Context:GetService, never through require.

local CharacterManager = {}

function CharacterManager:Start(context)
	local Network = context:Network("Character")
	local CharacterService = context:GetService("CharacterService")

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
