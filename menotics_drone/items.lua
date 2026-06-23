-- Menotics Camera Drone - Item Definition (Secure Version)
-- Defines the camera drone item for screenshot capture
-- No insecure environment needed

local modname = "menotics_drone"

-- Generate a high-tech texture for the drone item
local drone_texture = "menotics_drone_camera.png"

-- Register the camera drone item
minetest.register_craftitem("menotics_drone:camera_drone", {
    description = "Menotics Camera Drone (Secure)\nLeft/Right-click to toggle screenshot mode\nCaptures screenshots at set FPS",
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
minetest.register_craft({
    output = "menotics_drone:camera_drone",
    recipe = {
        {"default:steel_ingot", "default:glass", "default:steel_ingot"},
        {"mesecon:conductor", "default:diamond", "mesecon:conductor"},
        {"default:steel_ingot", "default:copper_ingot", "default:steel_ingot"},
    }
})

-- Alternative simpler recipe
minetest.register_craft({
    output = "menotics_drone:camera_drone",
    recipe = {
        {"group:metal_ingot", "default:glass", "group:metal_ingot"},
        {"group:mesecon_conductor", "default:diamond", "group:mesecon_conductor"},
        {"group:metal_ingot", "group:metal_ingot", "group:metal_ingot"},
    }
})

-- Help command
minetest.register_chatcommand("drone_help", {
    description = "Show help for Menotics Camera Drone (Secure Version)",
    func = function(player_name)
        minetest.chat_send_player(player_name, "=== Menotics Camera Drone (Secure) Help ===")
        minetest.chat_send_player(player_name, "1. Craft the Camera Drone item")
        minetest.chat_send_player(player_name, "2. Hold it and left/right-click to start screenshot mode")
        minetest.chat_send_player(player_name, "3. The drone camera follows 3 blocks high, 5 blocks behind you")
        minetest.chat_send_player(player_name, "4. Screenshots are captured at the configured FPS")
        minetest.chat_send_player(player_name, "5. Click again to stop capturing")
        minetest.chat_send_player(player_name, "")
        minetest.chat_send_player(player_name, "Note: This is the SECURE version.")
        minetest.chat_send_player(player_name, "- No video compilation (screenshots only)")
        minetest.chat_send_player(player_name, "- No audio recording")
        minetest.chat_send_player(player_name, "- Screenshots saved to world's screenshots folder")
        minetest.chat_send_player(player_name, "")
        minetest.chat_send_player(player_name, "Settings:")
        minetest.chat_send_player(player_name, "- /set menotics_drone.fps <number> (default: 20)")
        return true
    end
})
