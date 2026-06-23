-- Junky
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

-- A deferred handle (from Await / Request). Mirrors Substance's Reaction.
export type Reaction = {
	Next: (self: Reaction, fn: (any) -> any) -> Reaction,
	Throw: (self: Reaction, fn: (any) -> any) -> Reaction,
	Catch: (self: Reaction, fn: (any) -> any) -> Reaction,
	Conclusion: (self: Reaction, fn: () -> ()) -> Reaction,
	Map: (self: Reaction, fn: (any) -> any) -> Reaction,
	Timeout: (self: Reaction, seconds: number) -> Reaction,
	Await: (self: Reaction) -> any,
	Cancel: (self: Reaction) -> (),
}

export type NetworkScope = {
	Post: (self: NetworkScope, name: string, ...any) -> (),
	PostTo: (self: NetworkScope, target: Player, name: string, ...any) -> (),
	Broadcast: (self: NetworkScope, name: string, ...any) -> (),
	Request: (self: NetworkScope, name: string, ...any) -> Reaction,
	RequestFrom: (self: NetworkScope, target: Player, name: string, ...any) -> Reaction,
	Subscribe: (self: NetworkScope, name: string, handler: (...any) -> ()) -> Subscription,
	Once: (self: NetworkScope, name: string, handler: (...any) -> ()) -> Subscription,
	Respond: (self: NetworkScope, name: string, handler: (...any) -> any) -> Subscription,
	Guard: (self: NetworkScope, name: string, predicate: (...any) -> boolean) -> Subscription,
}

export type LocalScope = {
	Post: (self: LocalScope, name: string, ...any) -> (),
	Request: (self: LocalScope, name: string, ...any) -> Reaction,
	Subscribe: (self: LocalScope, name: string, handler: (...any) -> ()) -> Subscription,
	Once: (self: LocalScope, name: string, handler: (...any) -> ()) -> Subscription,
	Respond: (self: LocalScope, name: string, handler: (...any) -> any) -> Subscription,
	Guard: (self: LocalScope, name: string, predicate: (...any) -> boolean) -> Subscription,
}

export type Context = {
	Side: Side,
	Source: string,

	Post: (self: Context, namespace: Namespace, domain: string, name: string, ...any) -> (),
	Subscribe: (self: Context, namespace: Namespace, domain: string, name: string, handler: (...any) -> ()) -> Subscription,
	Once: (self: Context, namespace: Namespace, domain: string, name: string, handler: (...any) -> ()) -> Subscription,
	Request: (self: Context, namespace: Namespace, domain: string, name: string, ...any) -> Reaction,
	Respond: (self: Context, namespace: Namespace, domain: string, name: string, handler: (...any) -> any) -> Subscription,
	Guard: (self: Context, namespace: Namespace, domain: string, name: string, predicate: (...any) -> boolean) -> Subscription,
	Await: (self: Context, key: string) -> Reaction,

	GetPackage: (self: Context, name: string) -> any,
	GetUtility: (self: Context, name: string) -> any,
	GetService: (self: Context, name: string) -> any,

	OnCleanup: (self: Context, fn: () -> ()) -> (),
	Inspect: (self: Context) -> any,

	Network: (self: Context, domain: string) -> NetworkScope,
	Local: (self: Context, domain: string) -> LocalScope,
}

-- The handle returned by Junky.Configure.
export type App = {
	Side: Side,
	Modules: { [string]: any },
	Context: Context,
	Inspect: (self: App) -> any,
	Stop: (self: App) -> (),
}

-- A module. :Init and :Start both receive the Context; :Stop receives nothing.
-- Controllers/Managers implement at least one of :Init/:Start; Services are free
-- to implement none.
export type Module = {
	Init: ((self: any, context: Context) -> ())?,
	Start: ((self: any, context: Context) -> ())?,
	Stop: ((self: any) -> ())?,
	[any]: any,
}

export type Config = {
	Junction: JunctionMap,
	Manifest: any?,
	Modules: (Instance | { Instance })?,
	ClassPriority: { [number]: { string } }?,
	StandalonePriority: { [string]: number }?,
	Packages: { [string]: any }?,
	Utilities: { [string]: any }?,
	Side: Side?,
	Substance: any?,
}

return {}
