-- Example
-- client/CharacterController.lua
-- Plinko Labs
--
-- The client half of the Character domain. Subscriptions are wired in :Init;
-- :Start kicks off a one-off QueryHealth request to show request/response. It
-- never references ComboController, CharacterManager, or CharacterService directly.

local CharacterController = {}

function CharacterController:Init(context)
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

function CharacterController:Start(context)
	local Network = context:Network("Character")

	-- Request/response: ask the server for our health, with a 5s timeout.
	Network:Request("QueryHealth")
		:Timeout(5)
		:Next(function(health)
			print("[CharacterController] server reports my health is", health)
		end)
		:Catch(function(err)
			warn("[CharacterController] QueryHealth failed:", err)
		end)
end

return CharacterController
