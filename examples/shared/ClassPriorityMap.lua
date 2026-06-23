-- Example
-- shared/ClassPriorityMap.lua
-- Plinko Labs
--
-- Tier-based boot order for Controllers and Managers. All modules in a lower tier
-- :Start before any in a higher tier. Order within a tier is not guaranteed.
-- (NetworkController / NetworkManager are built into Junction and are not listed.)

return {
	[1] = { "CharacterController", "CharacterManager" },
	[2] = { "ComboController" },
}
