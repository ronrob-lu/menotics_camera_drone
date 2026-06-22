-- Menotics Camera Drone Mod
-- Core initialization and settings registration

local modname = "menotics_drone"
menotics_drone = menotics_drone or {}

-- Register settings
minetest.register_setting("menotics_drone.audio_device_name", "", "string", "Name of the audio device for system audio capture (Windows: Stereo Mix device name, Linux: pulse/alsa device, macOS: device index)")
minetest.register_setting("menotics_drone.os_type", "auto", "string", "Operating system type: auto, windows, linux, mac")
minetest.register_setting("menotics_drone.fps", "20", "int", "Frames per second for recording (15-24 recommended)")
minetest.register_setting("menotics_drone.max_duration", "90", "int", "Maximum recording duration in seconds")

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
