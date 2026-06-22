-- Menotics Camera Drone - Item Definition and Crafting
-- Defines the camera drone item, crafting recipe, and interaction handlers

local modname = "menotics_drone"

-- Generate a high-tech texture for the drone item
local drone_texture = "menotics_drone_camera.png"

-- Register the camera drone item
minetest.register_craftitem("menotics_drone:camera_drone", {
    description = "Menotics Camera Drone\nLeft/Right-click to toggle recording\nCreates vertical 9:16 video shorts with audio",
    inventory_image = drone_texture,
    wield_image = drone_texture,
    stack_max = 1,
    
    -- On use (right-click) - toggle recording
    on_use = function(itemstack, user, pointed_thing)
        local player_name = user:get_player_name()
        
        if menotics_drone.recording_players[player_name] then
            -- Stop recording
            menotics_drone.drone_logic.stop_recording(player_name)
        else
            -- Start recording
            menotics_drone.drone_logic.start_recording(player_name)
        end
        
        return itemstack
    end,
    
    -- On punch (left-click) - also toggle recording
    on_punch = function(itemstack, user, pointed_thing)
        local player_name = user:get_player_name()
        
        if menotics_drone.recording_players[player_name] then
            -- Stop recording
            menotics_drone.drone_logic.stop_recording(player_name)
        else
            -- Start recording
            menotics_drone.drone_logic.start_recording(player_name)
        end
        
        return itemstack
    end,
})

-- Crafting recipe: Steel ingots, mesecon conductors, glass, and diamond
-- Shape:
-- S G S
-- M D M
-- S C S
-- S = Steel Ingot, G = Glass, M = Mesecon Conductor, D = Diamond, C = Copper Ingot
minetest.register_craft({
    output = "menotics_drone:camera_drone",
    recipe = {
        {"default:steel_ingot", "default:glass", "default:steel_ingot"},
        {"mesecon:conductor", "default:diamond", "mesecon:conductor"},
        {"default:steel_ingot", "default:copper_ingot", "default:steel_ingot"},
    }
})

-- Alternative simpler recipe if default materials aren't available
minetest.register_craft({
    output = "menotics_drone:camera_drone",
    recipe = {
        {"group:metal_ingot", "default:glass", "group:metal_ingot"},
        {"group:mesecon_conductor", "default:diamond", "group:mesecon_conductor"},
        {"group:metal_ingot", "group:metal_ingot", "group:metal_ingot"},
    }
})

-- Chat command to list audio devices
minetest.register_chatcommand("drone_audio_setup", {
    description = "List available audio devices for Menotics Drone recording",
    func = function(player_name)
        local device_list = menotics_drone.ffmpeg_handler.list_audio_devices()
        
        minetest.chat_send_player(player_name, "=== Available Audio Devices ===")
        
        -- Split and send each line
        for line in device_list:gmatch("[^\r\n]+") do
            minetest.chat_send_player(player_name, line)
        end
        
        minetest.chat_send_player(player_name, "===============================")
        minetest.chat_send_player(player_name, "Set your audio device name with: /set menotics_drone.audio_device_name <device_name>")
        minetest.chat_send_player(player_name, "For Windows: Use 'Stereo Mix' or your desktop audio device name")
        minetest.chat_send_player(player_name, "For Linux: Usually 'default' works with PulseAudio")
        minetest.chat_send_player(player_name, "For macOS: Use the device index number (e.g., '0')")
        
        return true
    end
})

-- Help command
minetest.register_chatcommand("drone_help", {
    description = "Show help for Menotics Camera Drone",
    func = function(player_name)
        minetest.chat_send_player(player_name, "=== Menotics Camera Drone Help ===")
        minetest.chat_send_player(player_name, "1. Craft the Camera Drone item")
        minetest.chat_send_player(player_name, "2. Hold it and left/right-click to start recording")
        minetest.chat_send_player(player_name, "3. The drone camera follows 3 blocks high, 5 blocks behind you")
        minetest.chat_send_player(player_name, "4. Recording stops automatically at 90 seconds or click again to stop early")
        minetest.chat_send_player(player_name, "5. Videos are saved to: <mod_folder>/recordings/")
        minetest.chat_send_player(player_name, "")
        minetest.chat_send_player(player_name, "Audio Setup:")
        minetest.chat_send_player(player_name, "- Run /drone_audio_setup to list available audio devices")
        minetest.chat_send_player(player_name, "- Set your device: /set menotics_drone.audio_device_name <name>")
        minetest.chat_send_player(player_name, "- FFmpeg must be installed system-wide!")
        return true
    end
})
