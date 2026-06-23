-- Example
-- client/ComboController.lua
-- Plinko Labs
--
-- A second client Controller that talks to CharacterController purely through the
-- Local namespace -- never a require. When a combo finishes it posts Ability.Used;
-- the Junction routes that to CharacterController.

local ComboController = {}

function ComboController:Start(context)
	local Ability = context:Local("Ability")

	-- Stand-in for real input. In a game this would be an InputService signal.
	-- Here we fire one demo combo a moment after boot so the flow is observable.
	task.delay(2, function()
		Ability:Post("Used", {
			Player = game:GetService("Players").LocalPlayer,
			Damage = 25,
			Combo = "Z-Z-X",
		})
	end)
end

return ComboController
