-- Example
-- shared/Manifest.lua
-- Plinko Labs
--
-- Static, read-only game config. Injected into Context and reachable as
-- Context:GetPackage("Manifest"). Junky deep-freezes it at boot, so any attempt
-- to mutate it at runtime will error.

return {
	Enums = {
		CharacterStatus = { Alive = "Alive", Dead = "Dead", Stunned = "Stunned" },
	},
	Keybinds = {
		Attack = Enum.KeyCode.Z,
		Dodge = Enum.KeyCode.X,
		Block = Enum.KeyCode.C,
	},
	PlayerSettings = {
		MaxHealth = 100,
		BaseSpeed = 16,
	},
	GameConfig = {
		RoundDuration = 300,
		MaxPlayers = 20,
	},
}
