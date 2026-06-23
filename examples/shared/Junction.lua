-- Example
-- shared/Junction.lua
-- Plinko Labs
--
-- The routing topology for the Character Combat example. Every event the game can
-- fire is declared here exactly once, with where it goes. Nothing else in the game
-- decides routing.
--
-- Namespace rule: Network crosses the client <-> server boundary; Local stays on
-- one side. (The spec's section 9 routes a server->client "Ragdoll" through Local;
-- here it is correctly a Network event, since it crosses the boundary.)

local Junction = {}

Junction.Network = {
	Character = {
		-- client -> server: a confirmed hit
		Damaged = { Destination = "CharacterManager" },
		-- server -> client: the resulting state, sent back to the hit player
		Ragdoll = { Destination = "CharacterController" },
	},
}

Junction.Local = {
	Player = {
		-- server -> server: PlayerService announces a loaded profile
		DataLoaded = { Destination = "CharacterService" },
	},
	Ability = {
		-- client -> client: ComboController hands a finished combo to CharacterController
		Used = {
			Destination = "CharacterController",
			-- Example of a Dynamic resolver: route elsewhere based on the poster.
			Dynamic = function(source)
				if source == "ComboController" then
					return "CharacterController"
				end
				return nil
			end,
		},
	},
}

return Junction
