<div align="center">

# Junky

**Single Script Junction Architecture (SSJA) for Roblox.**
One `Configure`. One routing map. One Context. Modules never require each other.

<img src="https://img.shields.io/badge/Junky-v0.1.0-6C3EF4?style=for-the-badge" alt="version" />
<img src="https://img.shields.io/badge/Luau-Roblox-00A2FF?style=for-the-badge" alt="luau" />
<img src="https://img.shields.io/badge/License-MIT-22c55e?style=for-the-badge" alt="license" />
<img src="https://img.shields.io/badge/Plinko%20Labs-Built%20By-e11d48?style=for-the-badge" alt="plinko labs" />

</div>

---

## What it is

Junky is a game-framework runtime that implements **SSJA** — the Junction evolution of
Single Script Architecture. Three guarantees:

1. **A single Bootstrap per side** (`Junky.Configure`) owns the whole module lifecycle.
2. **All communication routes through a Junction** — a static map of every event and where it goes.
3. **Context is the only shared surface** — Controllers, Managers, and Services never `require` each other.

Networking is backed by [Substance](https://github.com/mkl48) (`ker/substance`): the Network
namespace rides typed channels (a `RemoteEvent` for `Post`, a `RemoteFunction` for `Request`),
and you never touch a remote yourself.

> **Naming:** the *library* is **Junky**. The *routing map* is still "the **Junction**" —
> `config.Junction`, with `Junction.Network` / `Junction.Local`.

---

## Installation

```toml
# wally.toml
[dependencies]
Junky     = "ker/junky@0.1.0"
Substance = "ker/substance@0.1.0"
```

```sh
wally install
```

Junky finds Substance on its own (Wally sibling, `ReplicatedStorage.Packages`, or
`ReplicatedStorage`). To be explicit, pass `Substance = require(...)` in the config.

### Command line (no Wally)

Paste this one snippet into the Studio command bar; it fetches and runs the full installer over
HTTP (enable *Game Settings → Security → Allow HTTP Requests*), recreating the whole `Junky` tree
under `ReplicatedStorage`:

```lua
local h = game:GetService("HttpService")
loadstring(h:GetAsync("https://raw.githubusercontent.com/mkl48/Junky/master/dist/install.luau"))()
```

([`dist/bootstrap.luau`](dist/bootstrap.luau) is the same with error handling + a no-`loadstring`
fallback.) Or, offline, paste the whole [`dist/install.luau`](dist/install.luau) directly. Junky
still needs **Substance** present — install it the same way, or via Wally.

Regenerate the installer from `src/` any time with:

```sh
lune run scripts/build-installer
```

---

## Project structure

The recommended layout — sides split by container, modules grouped by role.
[`scaffold/SetupSSJA.lua`](scaffold/SetupSSJA.lua) lays this down with a working Ping/Pong domain.

```
ReplicatedStorage/
  Shared/
    Assets/                       shared assets
    Modules/
      Packages/      Junky/       the framework package (+ Substance)
      Utility/                    Junction, Manifest, ClassPriorityMap, StandalonePriorityMap
      Services/                   *Service modules (both sides)
  Client/
    Modules/
      Packages/                   client-only deps
      Utility/                    client-only helpers
      Controllers/                *Controller modules (client)

ServerScriptService/
  ServerBootstrap                 server entry point (Script)

ServerStorage/
  Modules/
    Managers/                     *Manager modules (server-only, not replicated)
    Packages/                     server-only deps
    Utility/                      server-only helpers

StarterPlayer/StarterPlayerScripts/
  ClientBootstrap                 client entry point (LocalScript)
```

Discovery is **recursive and name-based** — a Bootstrap passes root folders and Junky finds every
`ModuleScript` under them, classifying by suffix (`*Controller`/`*Manager`/`*Service`) and
side-filtering. The folders above are organization for you; Junky doesn't require these exact
paths. Managers live in `ServerStorage` so their source never replicates to clients.

---

## Concepts

| Piece | Role |
| --- | --- |
| **Configure** | `Junky.Configure(config)` — one call per side. Discovers modules, validates the Junction, calls `:Start` in priority order, returns an **app handle**. |
| **Junction** | A static `{ Network, Local }` table. Every event declares a `Destination` (and optional `Dynamic` resolver). The single source of truth for routing. |
| **Context** | Injected into `:Start`. The only way modules talk: `Post`, `Subscribe`, `Request`, `Respond`, `Guard`, `Once`, `Await`, `Get*`. |
| **Controller** | Client-side domain wrapper. Coupled to a Manager. |
| **Manager** | Server-side domain wrapper. Coupled to a Controller. |
| **Service** | Domain logic + state owner. Both sides. Decoupled. |
| **Manifest** | Read-only config, deep-frozen at boot. `Context:GetPackage("Manifest")`. |

Modules are plain `ModuleScript`s. Junky classifies them by name suffix —
`*Controller`, `*Manager`, `*Service` — and side-filters automatically (Controllers boot on the
client, Managers on the server, Services on both).

---

## The two namespaces

- **`Network`** — crosses the client ↔ server boundary. Transported by Substance.
- **`Local`** — stays in-process on one side. Resolved directly by the Router.

> Same side → `Local`. Crosses the wire → `Network`. A server module sending to a client is
> always `Network`, even when it feels like a "local" response.

---

## Lifecycle

```lua
local Module = {}

function Module:Start(context) end   -- the boot hook. Controllers/Managers implement it; Services may.
function Module:Stop()         end   -- optional. Runs on app:Stop().

return Module
```

`:Start` is the single boot hook. Modules are required up front but never touch each other; only
the order of `:Start` matters, and that comes from the priority maps. For timing-sensitive
dependencies between modules, use [`Context:Await`](#reactions) rather than relying on exact boot
order.

`Junky.Configure` returns an **app handle**:

```lua
local app = Junky.Configure({ ... })

app:Inspect()   -- live routing topology snapshot (subscribers, responders, guards, await latches)
app:Stop()      -- :Stop every module (reverse order) + cancel all their subscriptions/cleanups
app.Modules     -- { [name] = moduleTable }
app.Context     -- a free-standing Context for glue/tests
```

---

## Quick start

```lua
-- ServerScriptService/ServerBootstrap (Script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Junky = require(ReplicatedStorage.Shared.Modules.Packages.Junky)
local Utility = ReplicatedStorage.Shared.Modules.Utility

Junky.Configure({
    Junction            = require(Utility.Junction),
    Manifest            = require(Utility.Manifest),
    ClassPriority       = require(Utility.ClassPriorityMap),
    StandalonePriority  = require(Utility.StandalonePriorityMap),
    Modules             = { ServerStorage.Modules, ReplicatedStorage.Shared.Modules.Services },
})
```

The client Bootstrap is the same call from `StarterPlayerScripts`, passing
`{ ReplicatedStorage.Client.Modules, ReplicatedStorage.Shared.Modules.Services }` — Junky detects
the side and boots only the Controllers.

A Junction map:

```lua
return {
    Network = {
        Character = {
            Damaged     = { Destination = "CharacterManager" },   -- client -> server
            Ragdoll     = { Destination = "CharacterController" }, -- server -> client
            QueryHealth = { Destination = "CharacterManager" },    -- client -> server request
        },
    },
    Local = {
        Ability = {
            Used = { Destination = "CharacterController" },        -- client -> client
        },
    },
}
```

A module:

```lua
local CharacterController = {}

function CharacterController:Start(context)
    local Network = context:Network("Character")
    local Ability = context:Local("Ability")

    Ability:Subscribe("Used", function(combo)
        Network:Post("Damaged", combo)               -- to the server
    end)
    Network:Subscribe("Ragdoll", function(state) end) -- server's authoritative result

    Network:Request("QueryHealth")                    -- ask the server
        :Timeout(5)
        :Next(function(health) print("HP:", health) end)
        :Catch(warn)
end

return CharacterController
```

The full Character Combat flow is in [`examples/`](examples).

---

## Context API

```lua
-- fire and forget
context:Post(namespace, domain, name, ...)
context:Subscribe(namespace, domain, name, handler)   --> Subscription (:Cancel())
context:Once(namespace, domain, name, handler)         --> Subscription (auto-cancels after first)

-- request / response
context:Request(namespace, domain, name, ...)          --> Reaction (resolves with the response)
context:Respond(namespace, domain, name, handler)      --> Subscription (handler returns the response)

-- policy & timing
context:Guard(namespace, domain, name, predicate)      --> Subscription (return false to veto)
context:Await(key)                                     --> Reaction (resolves on first post of "Domain.Name")

-- access
context:GetPackage(name)   -- Manifest + any extra packages
context:GetUtility(name)
context:GetService(name)   -- a booted module (Manager -> its Service)

-- lifecycle & diagnostics
context:OnCleanup(fn)      -- runs on app:Stop()
context:Inspect()          -- live topology snapshot

-- scoped shorthands
context:Network(domain)    --> { Post, PostTo, Broadcast, Request, RequestFrom, Subscribe, Once, Respond, Guard }
context:Local(domain)      --> { Post, Request, Subscribe, Once, Respond, Guard }
```

Scoped shorthand (preferred) — bind namespace + domain once:

```lua
local Network = context:Network("Character")
local Ability = context:Local("Ability")

Network:Post("Damaged", hitData)         -- client -> server, OR server -> all clients
Network:PostTo(player, "Ragdoll", state) -- server -> one client
Network:Broadcast("RoundOver", payload)  -- server -> all clients
Network:Request("QueryHealth"):Next(...) -- client -> server, returns a Reaction
Network:Subscribe("Damaged", function(hitData, player) end)  -- player appended on the server

Ability:Post("Used", combo)
Ability:Respond("Resolve", function(combo) return verdict end)
```

**Direction is implicit.** On the client, `Network:Post`/`:Request` go up to the server. On the
server, `Network:Post` goes down to every client; `:PostTo`/`:RequestFrom` target one. Server-side
Network subscribers/responders receive the **sending Player as a trailing argument** — never trust
a player field inside the payload.

---

## Request / Response

`Request` returns a [`Reaction`](#reactions). Network requests ride a `RemoteFunction`; Local
requests invoke an in-process responder. Exactly one `Respond` handler answers a given event.

```lua
-- server
function CharacterManager:Start(context)
    context:Network("Character"):Respond("QueryHealth", function(_payload, player)
        return context:GetService("CharacterService"):GetHealth(player)
    end)
end

-- client
context:Network("Character"):Request("QueryHealth")
    :Timeout(5)
    :Next(function(hp) print("my hp:", hp) end)
    :Catch(function(err) warn("query failed:", err) end)
```

---

## Guards

A guard is a veto predicate that runs **before** a `Post`/`Request` leaves the source. Return
`false` to drop the event at the topology edge — validation, rate-limiting, sanity checks, all in
one place rather than scattered through handlers.

```lua
Network:Guard("Damaged", function(hitData)
    return type(hitData) == "table" and hitData.Damage > 0
end)
```

---

## Reactions

The handle from `Await` and `Request`. Surface mirrors Substance's Reaction:

```lua
reaction
    :Next(fn)         -- on resolve
    :Throw(fn)        -- on reject  (alias :Catch)
    :Map(fn)          -- transform into a new Reaction
    :Timeout(seconds) -- reject "timeout" if still pending
    :Conclusion(fn)   -- finally
    :Await()          -- yield for the value (errors on reject)
    :Cancel()
```

`Context:Await(key)` resolves the **first** time `"Domain.Name"` is posted on this side, and
latches — late awaiters resolve immediately. It is **one-shot**; for events that fire repeatedly
use `Subscribe`. Await answers "has this happened yet?", Subscribe answers "tell me every time."

---

## Dynamic routing

A Junction entry can override its `Destination` based on who posted, via `Dynamic(source)`.
`Dynamic` wins when it returns a value; otherwise `Destination` is used.

```lua
Used = {
    Destination = "CharacterController",
    Dynamic = function(source)
        return source == "ComboController" and "CharacterController" or nil
    end,
}
```

Delivery is **destination-filtered**: an event reaches only subscribers owned by the module the
Junction resolved to. A subscriber cannot receive an event the Junction didn't route to it.

---

## Boot order & validation

```lua
-- ClassPriorityMap — tiers, ascending. Controllers + Managers.
return { [1] = { "CharacterController", "CharacterManager" }, [2] = { "ComboController" } }

-- StandalonePriorityMap — numeric, ascending. Services.
return { PlayerService = 1, CharacterService = 2 }
```

Class-tier modules run before Services within each phase. Modules absent from both maps boot last
with a warning. At boot, Junky also **validates the Junction**: any `Local` destination that names
no module on this side is flagged (a likely typo). Every `:Start`/`:Stop` is wrapped so one
module erroring doesn't abort the boot.

---

## Rules Junky enforces (or assumes)

| | Rule | Enforced by |
| --- | --- | --- |
| 1 | Never `require` another Controller / Manager / Service | convention (use Context) |
| 2 | All inter-module talk goes through Context | the API surface |
| 3 | Only Junky touches RemoteEvents/Functions | `Network` is the sole transport |
| 4 | Junction is the only routing definition | undeclared posts warn; Local destinations validated |
| 5 | Manifest is read-only | deep-frozen at boot |
| 6 | Controllers/Managers implement `:Start` | warns if missing |
| 7 | Services implement lifecycle only when needed | all hooks optional |
| 8 | A Manager may call its own Service | `Context:GetService` |

---

## Scaffolding

To install the package itself without Wally, use the [command-line installer](#command-line-no-wally)
(`dist/install.luau`, generated from `src/`). To scaffold a project around it, run the Studio
Command Bar script in [`scaffold/`](scaffold):

- **`SetupSSJA.lua`** — lays down the recommended project structure (`Shared/`, `Services/`,
  server/client `Modules/`, both Bootstraps) with a tiny Ping/Pong domain that runs end-to-end on
  Play.

---

## Notes & differences from the spec

- **NetworkController / NetworkManager are built in.** You don't write them; the `Network` layer
  is the transport. Modules named `NetworkController`/`NetworkManager` are ignored.
- **Server → client is `Network`, not `Local`.** The spec's §9 routes `Ragdoll` through `Local`;
  since it crosses the boundary it is correctly `Network` here.
- **Network payloads should be a single value** (idiomatically one table). Multiple positional
  args work, but Roblox drops trailing `nil`s across the wire regardless of framework.

---

<div align="center">

**SSJA · Single Script Junction Architecture · Plinko Labs**

</div>
