<div align="center">

# Junction

**Single Script Junction Architecture (SSJA) for Roblox.**
One Bootstrap. One routing map. One Context. Modules never require each other.

<img src="https://img.shields.io/badge/Junction-v0.1.0-6C3EF4?style=for-the-badge" alt="version" />
<img src="https://img.shields.io/badge/Luau-Roblox-00A2FF?style=for-the-badge" alt="luau" />
<img src="https://img.shields.io/badge/License-MIT-22c55e?style=for-the-badge" alt="license" />
<img src="https://img.shields.io/badge/Plinko%20Labs-Built%20By-e11d48?style=for-the-badge" alt="plinko labs" />

</div>

---

## What it is

Junction is a game-framework runtime that implements **SSJA** — the Junction evolution of
Single Script Architecture. It gives you three guarantees:

1. **A single Bootstrap per side** owns the whole module lifecycle.
2. **All communication routes through a Junction** — a static map of every event and where it goes.
3. **Context is the only shared surface** — Controllers, Managers, and Services never `require` each other.

Networking is backed by [Substance](https://github.com/mkl48) (`ker/substance`): the Network
namespace rides a single typed channel, and you never touch a `RemoteEvent` yourself.

---

## Installation

```toml
# wally.toml
[dependencies]
Junction  = "ker/junction@0.1.0"
Substance = "ker/substance@0.1.0"
```

```sh
wally install
```

Junction finds Substance on its own (Wally sibling, `ReplicatedStorage.Packages`, or
`ReplicatedStorage`). To be explicit, pass `Substance = require(...)` in the Ignite config.

---

## Concepts

| Piece | Role |
| --- | --- |
| **Bootstrap** | `Junction.Ignite(config)` — one call per side. Discovers modules, orders them, injects Context, calls `:Start`. |
| **Junction** | A static `{ Network, Local }` table. Every event declares a `Destination` (and optional `Dynamic` resolver). The single source of truth for routing. |
| **Context** | Injected into every `:Start`. The only way modules talk: `Post`, `Subscribe`, `Await`, `GetPackage`, `GetUtility`, `GetService`. |
| **Controller** | Client-side domain wrapper. Coupled to a Manager. `:Start` required. |
| **Manager** | Server-side domain wrapper. Coupled to a Controller. `:Start` required. |
| **Service** | Domain logic + state owner. Both sides. Decoupled. `:Start` optional. |
| **Manifest** | Read-only config, deep-frozen at boot. `Context:GetPackage("Manifest")`. |

Modules are plain `ModuleScript`s. Junction classifies them by name suffix —
`*Controller`, `*Manager`, `*Service` — and side-filters automatically (Controllers boot on
the client, Managers on the server, Services on both).

---

## The two namespaces

Every event belongs to exactly one namespace, and the Junction declares which:

- **`Network`** — crosses the client ↔ server boundary. Transported by Substance.
- **`Local`** — stays in-process on one side. Resolved directly by the Router.

> Same side → `Local`. Crosses the wire → `Network`. A server module sending to a client is
> always `Network`, even when it feels like a "local" response.

---

## Quick start

```lua
-- ServerScriptService/ServerBootstrap.server.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Junction = require(ReplicatedStorage.Packages.Junction)
local Shared = ReplicatedStorage.Shared

Junction.Ignite({
    Junction            = require(Shared.Junction),
    Manifest            = require(Shared.Manifest),
    ClassPriority       = require(Shared.ClassPriorityMap),
    StandalonePriority  = require(Shared.StandalonePriorityMap),
    Modules             = { ServerScriptService.Modules, Shared.Services },
})
```

The client Bootstrap is the same call from `StarterPlayerScripts` — Junction detects the side.

A Junction map:

```lua
return {
    Network = {
        Character = {
            Damaged = { Destination = "CharacterManager" },   -- client -> server
            Ragdoll = { Destination = "CharacterController" }, -- server -> client
        },
    },
    Local = {
        Ability = {
            Used = { Destination = "CharacterController" },    -- client -> client
        },
    },
}
```

A module:

```lua
-- CharacterController.lua  (client)
local CharacterController = {}

function CharacterController:Start(context)
    local Network = context:Network("Character")
    local Ability = context:Local("Ability")

    Ability:Subscribe("Used", function(combo)
        Network:Post("Damaged", combo)        -- to the server
    end)

    Network:Subscribe("Ragdoll", function(state)
        -- server's authoritative result
    end)
end

return CharacterController
```

The full Character Combat flow — two controllers, a manager, two services, and both
Bootstraps — is in [`examples/`](examples).

---

## Context API

```lua
context:Post(namespace, domain, name, ...)             -- fire and forget
context:Subscribe(namespace, domain, name, handler)    --> Subscription (:Cancel())
context:Await(key)                                     --> Reaction, resolves on first post of key
context:GetPackage(name)                               -- Manifest and any extra packages
context:GetUtility(name)
context:GetService(name)                               -- a booted module (Manager -> its Service)
context:Network(domain)                                --> scoped Network object
context:Local(domain)                                  --> scoped Local object
```

Scoped shorthand (preferred) — bind namespace + domain once:

```lua
local Network = context:Network("Character")
local Ability = context:Local("Ability")

Network:Post("Damaged", hitData)         -- client -> server, OR server -> all clients
Network:PostTo(player, "Ragdoll", state) -- server -> one client
Network:Broadcast("RoundOver", payload)  -- server -> all clients (explicit)
Network:Subscribe("Damaged", function(hitData, player) end)  -- player is appended on the server

Ability:Post("Used", combo)
Ability:Subscribe("Used", handler)       --> Subscription
```

**Direction is implicit.** On the client, `Network:Post` goes up to the server. On the server,
`Network:Post` goes down to every client; `Network:PostTo` targets one. Server-side Network
subscribers receive the **sending Player as a trailing argument** — never trust a player field
inside the payload.

---

## Dynamic routing

A Junction entry can override its `Destination` based on who posted, with a `Dynamic(source)`
resolver. `Dynamic` wins when it returns a value; otherwise `Destination` is used.

```lua
Used = {
    Destination = "CharacterController",
    Dynamic = function(source)
        if source == "ComboController" then
            return "CharacterController"
        end
        return nil  -- fall back to Destination
    end,
}
```

Delivery is **destination-filtered**: an event is delivered only to subscribers owned by the
module the Junction resolved to. A subscriber cannot receive an event the Junction didn't route
to it — which is exactly what keeps the topology honest.

---

## Await vs Subscribe

`Context:Await(key)` returns a `Reaction` that resolves the **first** time `"Domain.Name"` is
posted on this side, and latches — late awaiters resolve immediately with that first value.

```lua
context:Await("Match.Started"):Next(function(payload)
    -- one-shot readiness gate; great for boot-order-insensitive dependencies
end)
```

It is **one-shot**. For events that fire repeatedly (e.g. `Player.DataLoaded`, once per player)
use `Subscribe`. Await is for "has this happened yet?", Subscribe is for "tell me every time."

The `Reaction` surface (`:Next`, `:Throw`, `:Conclusion`, `:Await`, `:Cancel`) mirrors
Substance's Reaction.

---

## Boot order

```lua
-- ClassPriorityMap — tiers, ascending. Controllers + Managers.
return {
    [1] = { "CharacterController", "CharacterManager" },
    [2] = { "ComboController" },
}

-- StandalonePriorityMap — numeric, ascending. Services.
return {
    PlayerService    = 1,
    CharacterService = 2,
}
```

Class-tier modules `:Start` before Services. Cross-group timing dependencies should be handled
with `Await`, not by reordering. Modules absent from both maps boot last with a warning. All
`:Start` calls are wrapped so one module erroring doesn't abort the boot.

---

## Rules Junction enforces (or assumes)

| | Rule | Enforced by |
| --- | --- | --- |
| 1 | Never `require` another Controller / Manager / Service | convention (use Context) |
| 2 | All inter-module talk goes through Context | the API surface |
| 3 | Only Junction touches RemoteEvents | `Network` is the sole transport |
| 4 | Junction is the only routing definition | posting an undeclared event warns |
| 5 | Manifest is read-only | deep-frozen at boot |
| 6 | Controllers/Managers implement `:Start` | warns if missing |
| 7 | Services implement `:Start` only when needed | optional |
| 8 | A Manager may call its own Service | `Context:GetService` |

---

## Scaffolding

Two Roblox Studio Command Bar scripts in [`scaffold/`](scaffold):

- **`CreateJunction.lua`** — drops the whole Junction package as a `ModuleScript` tree under
  `ReplicatedStorage.Junction` (no Wally needed). A snapshot of `src/`; regenerate after edits.
- **`SetupSSJA.lua`** — lays down the recommended project structure (`Shared/`, `Services/`,
  server/client `Modules/`, both Bootstraps) with a tiny Ping/Pong domain that runs end-to-end
  on Play, so a new project boots immediately.

---

## Notes & differences from the spec

- **NetworkController / NetworkManager are built in.** You don't write them; the `Network`
  layer is the transport. Modules named `NetworkController`/`NetworkManager` are ignored.
- **Server → client is `Network`, not `Local`.** The spec's §9 routes `Ragdoll` through
  `Local`; since it crosses the boundary it is correctly `Network` here.
- **Network payloads should be a single value** (idiomatically one table). Multiple positional
  args work, but Roblox drops trailing `nil`s across the wire regardless of framework.

---

<div align="center">

**SSJA · Single Script Junction Architecture · Plinko Labs**

</div>
