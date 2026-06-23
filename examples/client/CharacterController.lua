-- Example
-- client/CharacterController.lua
-- Plinko Labs
--
-- The client half of the Character domain. It listens for a local combo, forwards
-- the hit to the server, and reacts to the server's authoritative response -- all
-- through Context. It never references ComboController, CharacterManager, or
-- CharacterService directly.

local CharacterController = {}

function CharacterController:Start(context)
	local Network = context:Network("Character")
	local Ability = context:Local("Ability")

	-- Local: ComboController -> here.
	Ability:Subscribe("Used", function(comboData)
		print("[CharacterController] combo used, sending to server:", comboData.Combo)
		Network:Post("Damaged", comboData) -- crosses to the server
	end)

	-- Network: server -> here. The server decides the real outcome.
	Network:Subscribe("Ragdoll", function(state)
		print(("[CharacterController] server says Health=%d Status=%s -- playing ragdoll")
			:format(state.Health, state.Status))
		-- play ragdoll animation using `state`
	end)
end

return CharacterController
