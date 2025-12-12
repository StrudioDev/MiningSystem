# ⛏️ Roblox Mining System

![Lua](https://img.shields.io/badge/Lua-2C2D72?style=for-the-badge&logo=lua&logoColor=white)
![Rojo](https://img.shields.io/badge/Rojo-000000?style=for-the-badge&logo=roblox&logoColor=white)
![Roblox](https://img.shields.io/badge/Roblox-Studio-000000?style=for-the-badge&logo=roblox&logoColor=white)

A high-quality, game-feel focused mining system for Roblox, built with [Rojo](https://rojo.space/). This system features client-side prediction for satisfying visual feedback ("juice") backed by secure server-side validation.

> **Note**: This system is designed to be "plug-and-play" with minimal configuration required.

---

## ✨ Features

### 🎮 Gameplay Mechanics
- **Hold-to-Mine**: Continuously mine rocks by simply holding the mouse button.
- **Dynamic Cooldown**: Mining speed automatically adjusts to the length of your hit sound (+0.1s buffer).
- **Server Validation**: 
  - Secure distance checks (default 10 studs).
  - Tool verification (requires "Pickaxe" tag).
  - Cooldown tracking to prevent exploiters.
- **Respawn System**: Rocks break and automatically respawn after a configurable time with a smooth scale-in animation.

### 🎨 Visual "Juice" & Game Feel
- **Impact Effects**: Rocks squash and bounce using `Elastic` tweening when hit.
- **Physics Debris**: 3D debris parts spawn and tumble away physically on every hit and break.
- **Screen Shake**: 
  - Subtle shake on every hit.
  - Heavy, impactful shake on rock destruction.
- **Floating Numbers**: Damage text pops out with particle-like physics (arc trajectory + gravity).
- **Health Bars**: Dynamic billboard health bars that appear on interaction and fade/remove on destruction.
- **Animation Blending**: Mining animations blend seamlessly with movement (walk/idle) using AnimationWeights.

## � Visual Showcase

*(Add your screenshots or GIFs here)*

---

## �🛠️ Setup Guide

### 1. Prerequisites
- [Rojo](https://rojo.space/) installed.
- A Roblox place (opened in Roblox Studio).

### 2. Installation
1.  Clone this repository.
2.  Sync the project using Rojo (`rojo serve`).
3.  Ensure the following structure is created in Studio:
    - `ReplicatedStorage.Shared.Remotes`
    - `StarterPlayer.StarterPlayerScripts.Client.MiningClient`
    - `ServerScriptService.Server.MiningServer`

### 3. In-Game Configuration
To make the system work in your place, you need three things:

#### A. Rock Template
1.  Create a Part (or Model) named `Rock`.
2.  Tag it with `Rock` using [CollectionService](https://create.roblox.com/docs/reference/engine/classes/CollectionService) (or a Tag Editor plugin).
3.  Place this `Rock` object inside `ReplicatedStorage`.
    *   *The system clones this template when spawning rocks.*

#### B. Spawn Points
1.  Create Parts in `Workspace` named `RockSpawn`.
2.  Place them wherever you want rocks to spawn.
3.  The server will automatically make these parts transparent and handle spawning.

#### C. Tool Setup
1.  Create a tool (e.g., "Pickaxe").
2.  Add the tag `Pickaxe` to the tool using CollectionService.
3.  *The system checks for this tag before allowing the player to mine.*

---

## ⚙️ Configuration

You can tweak the feel of the system by modifying the constants at the top of the scripts.

### Server (`MiningServer.server.luau`)
```lua
PICKAXE_POWER = 10        -- Damage dealt per hit
MAX_MINE_DISTANCE = 10    -- Max distance (studs) to validate hit
RESPAWN_TIME = 1          -- Time (seconds) before rock respawns
```

### Client (`MiningClient.client.luau`)
```lua
HIT_SHAKE_INTENSITY = 0.3   -- Shake intensity on hit
BREAK_SHAKE_INTENSITY = 1.2 -- Shake intensity on break
HIT_FRAME = 33              -- Animation frame to sync damage event
```

---

## 📁 Project Structure

| Path | Description |
|------|-------------|
| `src/client/MiningClient` | Handles user input, animations, visual effects (particles, tweens, UI). |
| `src/server/MiningServer` | Handles game state, validation, damage logic, rock spawning/respawning. |
| `src/shared/Remotes` | Centralized module for RemoteEvent management. |

---

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| **"Too far from rock"** | Ensure `MAX_MINE_DISTANCE` matches on both client and server (Default: 10 studs). |
| **No Animations** | Verify `IDLE_ANIMATION_ID` and `HIT_ANIMATION_ID` are valid asset IDs you own or are public. |
| **No Damage/Effects** | Ensure your tool is tagged `Pickaxe` and the target is tagged `Rock`. |
| **Schema Errors** | Ensure your `default.project.json` points to the correct Rojo schema URL. |

---

## 📝 License

This project is open source and available under the [MIT License](LICENSE).