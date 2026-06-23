-- Example
-- shared/StandalonePriorityMap.lua
-- Plinko Labs
--
-- Numeric boot order for Services. Lower numbers :Start first. PlayerService owns
-- sessions, so it must be ready before CharacterService initializes per-player
-- state from it.

return {
	PlayerService = 1,
	CharacterService = 2,
}
