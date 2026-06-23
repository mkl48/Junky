-- Junction
-- Types.lua
-- Plinko Labs
--
-- Shared type surface for the SSJA runtime. Nothing here executes; it exists so
-- Controllers / Managers / Services can annotate against a single Context type.

export type Side = "Server" | "Client"

export type Namespace = "Network" | "Local"

-- A single Junction entry: a static Destination plus an optional Dynamic resolver
-- that overrides Destination based on who posted the event.
export type JunctionEntry = {
	Destination: string?,
	Dynamic: ((source: string) -> string?)?,
}

export type DomainMap = { [string]: JunctionEntry }
export type NamespaceMap = { [string]: DomainMap }

-- The routing topology. The single source of truth for where events go.
export type JunctionMap = {
	Network: NamespaceMap?,
	Local: NamespaceMap?,
}

export type Subscription = {
	Cancel: (self: Subscription) -> (),
}

-- A one-shot async handle resolved when an Await key is first posted. Mirrors the
-- surface of Substance's Reaction so the two feel identical in use.
export type Reaction = {
	Next: (self: Reaction, fn: (any) -> any) -> Reaction,
	Throw: (self: Reaction, fn: (any) -> any) -> Reaction,
	Conclusion: (self: Reaction, fn: () -> ()) -> Reaction,
	Await: (self: Reaction) -> any,
	Cancel: (self: Reaction) -> (),
}

export type NetworkScope = {
	Post: (self: NetworkScope, name: string, ...any) -> (),
	PostTo: (self: NetworkScope, target: Player, name: string, ...any) -> (),
	Broadcast: (self: NetworkScope, name: string, ...any) -> (),
	Subscribe: (self: NetworkScope, name: string, handler: (...any) -> ()) -> Subscription,
}

export type LocalScope = {
	Post: (self: LocalScope, name: string, ...any) -> (),
	Subscribe: (self: LocalScope, name: string, handler: (...any) -> ()) -> Subscription,
}

export type Context = {
	Side: Side,
	Source: string,
	Post: (self: Context, namespace: Namespace, domain: string, name: string, ...any) -> (),
	Subscribe: (self: Context, namespace: Namespace, domain: string, name: string, handler: (...any) -> ()) -> Subscription,
	Network: (self: Context, domain: string) -> NetworkScope,
	Local: (self: Context, domain: string) -> LocalScope,
	GetPackage: (self: Context, name: string) -> any,
	GetUtility: (self: Context, name: string) -> any,
	GetService: (self: Context, name: string) -> any,
	Await: (self: Context, key: string) -> Reaction,
}

-- A module is anything with an optional :Start. Controllers / Managers must
-- implement it; Services may.
export type Module = {
	Start: ((self: any, context: Context) -> ())?,
	[any]: any,
}

export type Config = {
	-- The routing topology. Required.
	Junction: JunctionMap,
	-- Read-only game config, exposed as Context:GetPackage("Manifest").
	Manifest: any?,
	-- Instance(s) to scan for module scripts. ModuleScripts whose name ends in
	-- Controller / Manager / Service are booted.
	Modules: (Instance | { Instance })?,
	-- Tier-based boot order for Controllers and Managers.
	ClassPriority: { [number]: { string } }?,
	-- Numeric boot order for Services.
	StandalonePriority: { [string]: number }?,
	-- Extra named packages exposed via Context:GetPackage.
	Packages: { [string]: any }?,
	-- Named utilities exposed via Context:GetUtility.
	Utilities: { [string]: any }?,
	-- Override side detection. Defaults to RunService:IsServer().
	Side: Side?,
	-- Explicit Substance module. Auto-resolved from Packages/ReplicatedStorage if omitted.
	Substance: any?,
}

return {}
