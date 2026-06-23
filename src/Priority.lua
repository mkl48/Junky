-- Junky
-- Priority.lua
-- Plinko Labs
--
-- Resolves the two priority maps into one flat boot order:
--
--   1. ClassPriorityMap     -- tier-based, ascending tier number. Controllers and
--                              Managers. Order within a tier is not guaranteed.
--   2. StandalonePriorityMap -- numeric, ascending. Services.
--
-- Class modules boot before Services; cross-group timing dependencies are meant to
-- be handled with Context:Await rather than by reordering. Any discovered module
-- absent from both maps is appended last so nothing is silently dropped.

local Priority = {}

function Priority.Order(
	classMap: { [number]: { string } }?,
	standaloneMap: { [string]: number }?,
	present: { [string]: boolean }
): ({ string }, { string })
	local ordered = {}
	local seen = {}
	local unprioritized = {}

	if classMap then
		local tiers = {}
		for tier in classMap do
			table.insert(tiers, tier)
		end
		table.sort(tiers)

		for _, tier in tiers do
			for _, name in classMap[tier] do
				if present[name] and not seen[name] then
					seen[name] = true
					table.insert(ordered, name)
				end
			end
		end
	end

	if standaloneMap then
		local services = {}
		for name, priority in standaloneMap do
			if present[name] and not seen[name] then
				table.insert(services, { name = name, priority = priority })
			end
		end
		table.sort(services, function(a, b)
			return a.priority < b.priority
		end)

		for _, item in services do
			seen[item.name] = true
			table.insert(ordered, item.name)
		end
	end

	for name in present do
		if not seen[name] then
			seen[name] = true
			table.insert(ordered, name)
			table.insert(unprioritized, name)
		end
	end

	return ordered, unprioritized
end

return Priority
