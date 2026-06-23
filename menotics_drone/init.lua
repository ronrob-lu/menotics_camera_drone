-- Menotics Camera Drone Mod (Secure Version)
-- Core initialization - no insecure environment needed
-- This version only captures screenshots, no video/audio compilation

local modname = "menotics_drone"
menotics_drone = menotics_drone or {}

-- Settings will be loaded from settingtypes.txt automatically
-- No need to register them manually with deprecated API

menotics_drone.recording_players = {} -- Table to track recording state per player
menotics_drone.temp_dirs = {} -- Track temp directories per player (stored in worldpath)

-- Load dependencies
dofile(minetest.get_modpath(modname) .. "/drone_logic.lua")
dofile(minetest.get_modpath(modname) .. "/items.lua")

minetest.log("action", "[Menotics Drone] Secure mod initialized successfully")
