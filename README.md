# Menotics Camera Drone

A **Luanti / Minetest** mod that adds an attachable stone block camera drone engineered for smooth, cinematic viewing with zero chat window spam.

It features two operational modes:
1. **Manual Free Flight Mode**: Full manual control over flight, speed, altitude, and unrestricted native 60+ FPS mouse camera look.
2. **Autonomous Vantage Point & Lock-On Mode**: When the builder drone (`menotics_llm_city_builder_drone:builder_drone`) is active, the camera drone automatically cruises to an elevated vantage point **22 blocks away** horizontally and **6 blocks above** the builder drone to observe the construction site. It firmly **locks your FPV view onto the builder drone** so you cannot look away from the construction, while maintaining rock-solid, shake-free stationing. It dynamically repositions only when the builder moves outside the observation corridor or travels to a new site.

---

## Zero Chat Clutter

The camera drone operates **completely silently**. No notifications, mounting alerts, control hints, or status messages are pushed to the chat window. All instructions, controls, recipes, and command references are fully documented in this README instead.

---

## Antishake & Stabilization Architecture

Earlier camera drone implementations suffered from severe view shaking, twitching, and jitter. This mod has been engineered with a multi-layered stabilization system:

1. **Firm View Lock with Anti-Jitter Deadband**:
   - In Autonomous Tracking Mode, your view is firmly locked onto the builder drone so you cannot rotate away.
   - To eliminate the 20-Hz camera jitter from constant server-client packet fighting, an angular deadband is employed: redundant packets are not flooded while stationary, keeping the camera view rock-solid steady while immediately snapping back any attempt to turn away with the mouse.
2. **Smooth Exponential Velocity Damping (`SMOOTH_FACTOR = 6.0`)**:
   - Velocity transitions (accelerating, turning, braking, and stopping) are exponentially smoothed over time instead of slamming instant velocity changes into the physics engine.
3. **Proportional Ease-Out Deceleration (`DECEL_DISTANCE = 6.0`)**:
   - As the drone approaches its vantage station, its speed gracefully scales down with distance rather than crashing from top speed to zero.
4. **Zero-Teleport Stationing**:
   - Position snapping via `set_pos` has been eliminated during flight and arrival. The drone glides smoothly to rest, preventing client-side coordinate resets and rubberbanding.
5. **Hysteresis Observation Corridor (20–24 Blocks)**:
   - While the builder drone moves around a structure placing blocks, the camera drone remains completely static. Repositioning only triggers if the builder drone moves outside the 20–24 block horizontal corridor, changes elevation by more than 0.8 blocks, or engages in fast travel (> 5 m/s).
6. **Smooth Angular Slerp (`ROTATION_SMOOTH_SPEED = 2.0 rad/s`)**:
   - The drone entity smoothly turns toward the target drone using angular difference interpolation, preventing sudden heading snaps.

---

## Crafting & Getting Started

### Crafting Recipe
Craft a placeable Camera Drone block in the crafting grid:

| | Crafting Grid | |
| :---: | :---: | :---: |
| Stone (`default:stone`) | Stone (`default:stone`) | Stone (`default:stone`) |
| Stone (`default:stone`) | Glass (`default:glass`) | Stone (`default:stone`) |
| Stone (`default:stone`) | Stone (`default:stone`) | Stone (`default:stone`) |

- **Output**: `menotics_camera_drone:drone_block` (Camera Drone Stone Block)

### Placing & Mounting
1. **Place the Block**: Place the `Camera Drone (Stone Block)` anywhere on the ground.
2. **Mount the Drone**: Right-click the placed stone block. The block transforms into an active flying drone entity and automatically mounts you into the pilot seat.
3. **First-Person View (FPV)**: While mounted, the stone block model automatically turns invisible (`HIDE_STONE_WHEN_MOUNTED = true`) for a completely unobstructed panoramic view.
4. **Mount Existing Drone**: You can also right-click any idle camera drone in the world to mount it.

### Collecting & Dismantling
- To pick up and collect an idle camera drone, **Punch / Dig** it (with your hand or any tool). It drops the `menotics_camera_drone:drone_block` item and removes the entity.

---

## Complete Controls Reference

| Key / Action | In Manual Mode | In Autonomous Tracking Mode |
| :--- | :--- | :--- |
| **Punch Drone / Dig (Left Click)** | **Dismount immediately** | **Dismount immediately** |
| **Shift (Sneak) [Hold 0.4s]** | Descend / Dismount on ground | **Dismount immediately** |
| **Space + Shift** | **Instant Mid-Air Dismount** | **Unbind Tracking** (Switches to manual flight) |
| **Right Click Drone** | Dismount immediately | Dismount immediately |
| **W / S** | Fly Forward / Fly Backward | Autopilot cruise to vantage |
| **A / D** | Fly Left (Strafe) / Fly Right | Autopilot cruise to vantage |
| **Space (Jump)** | Ascend (Fly Up) | Maintained at relative vantage altitude |
| **Shift (Sneak)** | Descend (Fly Down) | Autopilot height management |
| **E (Aux1)** | Fast Flight Boost (24 m/s) | Autopilot speed |
| **Mouse Look** | Full 360° camera freedom | Smooth look around observation site |

---

## Player Safety & Immersion

- **Mid-Air Dismounting**: You can safely dismount from any altitude, whether flying manually or tracking the builder drone.
- **Fall Damage Immunity**: While riding the drone, fall damage is disabled. Upon detaching in mid-air, you receive **6 seconds of fall damage immunity** (`MIDAIR_DISMOUNT_GRACE_TIME = 6.0`) to guarantee a safe touchdown.
- **Suffocation & Drowning Immunity**: Because the drone has structure pass-through (`PASS_THROUGH_BLOCKS = true`), mounted players have their breath automatically maintained, allowing you to fly through solid structures and underwater without drowning or taking wall damage.
- **Sitting Pose**: The player character visually sits on the drone while mounted.
- **Model Reappearance**: When you dismount, the stone block drone entity instantly reappears in the world facing the direction you were looking.

---

## Operational Modes

### 1. Manual Free Flight Mode
- Enabled when no builder drone is present, or when you unbind tracking with **Space + Shift**.
- Fly anywhere using standard WASD and Space/Shift controls.
- Hold **E (Aux1)** to engage high-speed cruise (24 m/s).
- Smooth velocity damping ensures gentle starts and glides when releasing movement keys.

### 2. Autonomous Builder Drone Tracking Mode
- Automatically engages when `menotics_llm_city_builder_drone:builder_drone` is detected in the loaded area.
- **Vantage Station**: Automatically navigates to **22 blocks away** horizontally and **1 block above** the builder drone (`builder_drone.y + TARGET_ALTITUDE`).
- **Firm FPV View Lock**: Firmly locks your camera orientation directly onto the builder drone so you cannot look away from the construction.
- **Rock-Solid Stationing**: While the builder drone moves within the 20–24 block corridor, the camera drone stays completely still.
- **Continuous Vertical Tracking**: Smoothly glides straight to the target altitude whenever `TARGET_ALTITUDE` changes.
- **Dynamic Catch-Up**: If the builder drone flies to a distant construction site, the camera drone accelerates dynamically up to 28 m/s to follow it.
- **Unbind / Re-bind**: Press **Space + Shift** or run `/camera_drone unbind` to take manual control. Run `/camera_drone bind` to re-engage tracking.
- **Dismount**: Hold **Sneak (Shift)** for 0.4s or Left-click (punch/dig) to dismount safely.

---

## Chat Commands Reference

All commands execute silently without pushing messages to the chat window:

| Command | Description |
| :--- | :--- |
| `/camera_drone` | Spawns and immediately mounts a camera drone at your position. |
| `/camera_drone dismount` | Safely dismounts from the drone with fall damage immunity. |
| `/dismount` | Shortcut command to dismount from the camera drone. |
| `/kill_drones [all]` | **Kills and removes all camera drones** (add `all` to also remove dummy builder drones). |
| `/camera_drone remove` (or `kill`) | Removes all camera drone entities in the loaded area. |
| `/camera_drone reload` | **Hot-reloads `config.lua` live** without restarting Minetest! |
| `/camera_drone altitude <num>` | Sets target altitude in config. |
| `/camera_drone distance <num>` | Sets target distance in config. |
| `/camera_drone unstuck` | Instantly elevates the drone out of any tree foliage into clear air. |

### Testing & Debug Commands
| Command | Description |
| :--- | :--- |
| `/spawn_dummy_builder_drone [dist]` | Spawns a mock builder drone in front of you (default: 20 blocks away). |
| `/move_dummy_builder_drone <dist>` | Repositions the mock builder drone to test corridor and catch-up speed. |
| `/remove_dummy_builder_drone` | Removes mock builder drones to return camera drone to manual flight. |

---

## Configuration Reference (`config.lua`)

All behavior and physics settings can be customized in [`config.lua`](config.lua):

```lua
-- TARGET DRONE SETTINGS
TARGET_ENTITY_NAME = "menotics_llm_city_builder_drone:builder_drone"
TARGET_ALTITUDE = 1                -- Observation altitude offset (can be 0 or negative like -3 for ground view!)
USE_RELATIVE_ALTITUDE = true       -- true = target.y + TARGET_ALTITUDE, false = exact world Y level

-- OBSERVATION DISTANCES & CORRIDOR
TARGET_DISTANCE = 22               -- Target horizontal vantage distance (blocks)
MIN_DISTANCE = 20                  -- Inner corridor threshold (stay static above this)
MAX_DISTANCE = 24                  -- Outer corridor threshold (stay static below this)
COLLISION_AVOID_DISTANCE = 16      -- Emergency retreat distance buffer

-- TREE & OBSTACLE CLEARANCE
TREE_AVOIDANCE = true              -- Automatically avoids trees and foliage when picking vantage angle
TREE_CLEARANCE_HEIGHT = 3          -- Blocks above tree canopy to elevate if trees are detected
AUTO_UNSTUCK_FROM_TREES = true     -- Actively climbs out of tree foliage into clear open air

-- STRUCTURE PASS-THROUGH
PASS_THROUGH_BLOCKS = true         -- Non-physical noclip through structures

-- FLIGHT SPEEDS (blocks / second)
MANUAL_FLY_SPEED = 12.0            -- Normal manual speed
MANUAL_FAST_SPEED = 24.0           -- Boosted manual speed (Aux1 / E)
MANUAL_VERTICAL_SPEED = 8.0        -- Ascend / descend speed
AUTOPILOT_SPEED = 16.0             -- Cruising speed to vantage point
AUTOPILOT_MAX_SPEED = 32.0         -- Maximum catch-up speed
ARRIVAL_TOLERANCE = 1.5            -- Station arrival radius (blocks)

-- SMOOTHING & STABILIZATION (Antishake)
SMOOTH_FACTOR = 6.0                -- Exponential velocity damping factor
ROTATION_SMOOTH_SPEED = 2.0        -- Yaw rotation speed (radians/sec)
DECEL_DISTANCE = 6.0               -- Proportional braking distance zone

-- PLAYER ATTACHMENT & CONTROLS
HIDE_STONE_WHEN_MOUNTED = true     -- Hide drone stone mesh in FPV while mounted
ALLOW_MIDAIR_DISMOUNT = true       -- Allow dismounting mid-air anywhere
MIDAIR_DISMOUNT_GRACE_TIME = 6.0   -- Fall damage immunity duration on dismount (seconds)
SNEAK_DISMOUNT_HOLD_TIME = 0.4     -- Sneak hold duration to dismount (seconds)
```

---

## License

MIT License (c) 2026 ronrob-lu. See [LICENSE](LICENSE) for details.

