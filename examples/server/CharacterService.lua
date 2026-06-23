-- Example
-- server/CharacterService.lua
-- Plinko Labs
--
-- Owner of the Character state slice. It is decoupled: it doesn't care how data
-- arrives. It initializes per-player state when PlayerService announces a loaded
-- profile, and exposes ApplyDamage for its Manager to call.

local CharacterService = {}
CharacterService.State = {}

function CharacterService:Start(context)
	local Player = context:Local("Player")
	local manifest = context:GetPackage("Manifest")

	-- Per-player init. PlayerService posts Player.DataLoaded once per player, so we
	-- Subscribe rather than Await (Await is one-shot; see README).
	Player:Subscribe("DataLoaded", function(data)
		self.State[data.Player] = {
			Health = data.MaxHealth or manifest.PlayerSettings.MaxHealth,
			Status = manifest.Enums.CharacterStatus.Alive,
		}
		print(("[CharacterService] state ready for %s (HP %d)"):format(data.Player.Name, self.State[data.Player].Health))
	end)
end

function CharacterService:ApplyDamage(player, hitData)
	local state = self.State[player]
	if not state then
		return { Health = 0, Status = "Dead" }
	end

	state.Health -= hitData.Damage
	if state.Health <= 0 then
		state.Health = 0
		state.Status = "Dead"
	end
	return state
end

return CharacterService
