--[[
    menotics_camera_drone - Configuration
    All distance, coordinate, and speed units are in blocks (meters).
]]--

local config = {
    ---------------------------------------------------------------------------
    -- TARGET DRONE SETTINGS
    ---------------------------------------------------------------------------
    -- Entity name of the city builder drone to watch
    TARGET_ENTITY_NAME = "menotics_llm_city_builder_drone:builder_drone",

    -- Flying altitude when tracking the builder drone (in blocks)
    -- If USE_RELATIVE_ALTITUDE is true: builder_drone.y + TARGET_ALTITUDE
    -- NOTE: Can be negative! E.g. 0 = same level as builder drone, -4 = 4 blocks below it (closer to ground).
    -- If USE_RELATIVE_ALTITUDE is false: exact world Y-level (e.g. 11 = fly at world Y=11).
    TARGET_ALTITUDE = 1,
    USE_RELATIVE_ALTITUDE = true,

    -- Desired horizontal distance to hold from the builder drone (in blocks)
    TARGET_DISTANCE = 22,

    -- Distance threshold band around TARGET_DISTANCE:
    MIN_DISTANCE = 20,
    MAX_DISTANCE = 24,

    -- Collision safety buffer (blocks):
    COLLISION_AVOID_DISTANCE = 16,

    ---------------------------------------------------------------------------
    -- TREE & OBSTACLE CLEARANCE
    ---------------------------------------------------------------------------
    -- Automatically avoids trees, branches, and foliage to guarantee a clear view.
    -- Dynamically selects an unobstructed angle, or elevates above tree canopy
    -- if foliage blocks direct line of sight to the builder drone.
    TREE_AVOIDANCE = true,
    TREE_CLEARANCE_HEIGHT = 3,
    AUTO_UNSTUCK_FROM_TREES = true,

    ---------------------------------------------------------------------------
    -- STRUCTURE & COLLISION SETTINGS
    ---------------------------------------------------------------------------
    -- If true, the camera drone is non-physical / intangible (noclip) and can fly
    -- directly through walls, buildings, roofs, and structures without hanging or colliding.
    PASS_THROUGH_BLOCKS = true,

    ---------------------------------------------------------------------------
    -- MOVEMENT & FLIGHT SPEEDS (in blocks per second)
    ---------------------------------------------------------------------------
    MANUAL_FLY_SPEED = 12.0,       -- Normal manual flight speed
    MANUAL_FAST_SPEED = 24.0,      -- Fast manual flight speed (holding Aux1 / E)
    MANUAL_VERTICAL_SPEED = 8.0,   -- Ascending / descending speed
    AUTOPILOT_SPEED = 16.0,        -- Cruising speed when flying to observation station
    AUTOPILOT_MAX_SPEED = 32.0,    -- Maximum speed when catching up to a fast-moving target drone
    ARRIVAL_TOLERANCE = 1.5,       -- Distance tolerance (blocks) to consider vantage point reached

    ---------------------------------------------------------------------------
    -- SMOOTHING & STABILIZATION (Antishake)
    ---------------------------------------------------------------------------
    SMOOTH_FACTOR = 6.0,           -- Exponential smoothing factor for velocity transitions
    ROTATION_SMOOTH_SPEED = 2.0,   -- Max rotation speed (radians/sec) for smooth turning
    DECEL_DISTANCE = 6.0,          -- Distance (blocks) from vantage point where smooth braking begins

    ---------------------------------------------------------------------------
    -- PLAYER ATTACHMENT & CONTROLS
    ---------------------------------------------------------------------------
    -- When true, hides the stone block drone entity while a player is mounted,
    -- providing an unobstructed first-person view (FPV) camera.
    HIDE_STONE_WHEN_MOUNTED = true,

    -- Offset of the player sitting on top of the stone block entity
    ATTACH_OFFSET = { x = 0, y = 1, z = 0 },
    ATTACH_ROTATION = { x = 0, y = 0, z = 0 },

    -- Eye offset adjustment while attached (X, Y, Z)
    EYE_OFFSET_FIRST_PERSON = { x = 0, y = 0, z = 0 },
    EYE_OFFSET_THIRD_PERSON = { x = 0, y = 0, z = 0 },

    -- Allow dismounting anywhere, including in mid-air and while tracking the builder drone
    ALLOW_MIDAIR_DISMOUNT = true,
    -- Seconds to protect the player from fall damage after dismounting in mid-air
    MIDAIR_DISMOUNT_GRACE_TIME = 6.0,
    -- How long (seconds) to hold Sneak (Shift) to dismount while mounted
    SNEAK_DISMOUNT_HOLD_TIME = 0.4,
}

return config
