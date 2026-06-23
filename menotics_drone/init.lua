-- Menotics Camera Drone Mod
-- Core initialization and settings registration

local modname = "menotics_drone"
menotics_drone = menotics_drone or {}

-- Settings will be loaded from settingtypes.txt automatically
-- No need to register them manually with deprecated API

-- Get insecure environment for file/OS operations
local insecure = minetest.request_insecure_environment()
if not insecure then
    minetest.log("error", "[Menotics Drone] Failed to get insecure environment. Mod will not function.")
    return
end

menotics_drone.insecure = insecure
menotics_drone.recording_players = {} -- Table to track recording state per player
menotics_drone.temp_dirs = {} -- Track temp directories per player

-- Load dependencies
dofile(minetest.get_modpath(modname) .. "/ffmpeg_handler.lua")
dofile(minetest.get_modpath(modname) .. "/drone_logic.lua")
dofile(minetest.get_modpath(modname) .. "/items.lua")

minetest.log("action", "[Menotics Drone] Mod initialized successfully")
