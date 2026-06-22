-- Menotics Camera Drone - Drone Logic
-- Handles camera positioning, recording state, and globalstep updates

local modname = "menotics_drone"
local insecure = menotics_drone.insecure
local os = insecure.os
local io = insecure.io

menotics_drone.drone_logic = {}

-- Constants for drone positioning
local DRONE_HEIGHT = 3 -- blocks above player
local DRONE_DISTANCE = 5 -- blocks behind player
local LERP_FACTOR = 0.1 -- Smoothing factor (0-1, higher = snappier)

-- Track active drone cameras per player
local drone_cameras = {}

-- Initialize recording for a player
function menotics_drone.drone_logic.start_recording(player_name)
    local player = minetest.get_player_by_name(player_name)
    if not player then return false end
    
    -- Check if already recording
    if menotics_drone.recording_players[player_name] then
        minetest.chat_send_player(player_name, "Recording already in progress.")
        return false
    end
    
    -- Create temp directory for frames
    local temp_dir = insecure.os.tmpname()
    -- Remove the temp file and create as directory
    insecure.os.remove(temp_dir)
    insecure.os.execute('mkdir "' .. temp_dir .. '"')
    
    -- Initialize recording data
    menotics_drone.recording_players[player_name] = {
        active = true,
        start_time = insecure.os.time(),
        temp_dir = temp_dir,
        frame_count = 0,
        last_frame_time = 0,
        audio_file = nil,
        audio_pid = nil
    }
    
    -- Start audio capture
    local audio_success, audio_msg = menotics_drone.ffmpeg_handler.start_audio_capture(player_name, temp_dir)
    if not audio_success then
        minetest.log("warning", "[Menotics Drone] Audio capture failed: " .. audio_msg)
        minetest.chat_send_player(player_name, "Warning: Audio capture may have failed. Video will be silent if this persists.")
    end
    
    -- Enable drone camera
    menotics_drone.drone_logic.enable_drone_camera(player_name)
    
    minetest.chat_send_player(player_name, "Recording started! Max duration: 90 seconds. Click again to stop early.")
    
    return true
end

-- Stop recording for a player
function menotics_drone.drone_logic.stop_recording(player_name)
    local data = menotics_drone.recording_players[player_name]
    if not data then
        return false
    end
    
    -- Disable drone camera
    menotics_drone.drone_logic.disable_drone_camera(player_name)
    
    -- Finalize recording
    menotics_drone.ffmpeg_handler.finalize_recording(player_name)
    
    -- Clear recording data
    menotics_drone.recording_players[player_name] = nil
    
    return true
end

-- Enable drone camera for a player
function menotics_drone.drone_logic.enable_drone_camera(player_name)
    local player = minetest.get_player_by_name(player_name)
    if not player then return end
    
    drone_cameras[player_name] = {
        current_offset = {x = 0, y = DRONE_HEIGHT, z = DRONE_DISTANCE},
        target_offset = {x = 0, y = DRONE_HEIGHT, z = DRONE_DISTANCE}
    }
    
    minetest.chat_send_player(player_name, "Drone camera activated! Camera is positioned 3 blocks high and 5 blocks behind you.")
end

-- Disable drone camera for a player
function menotics_drone.drone_logic.disable_drone_camera(player_name)
    local player = minetest.get_player_by_name(player_name)
    if not player then return end
    
    -- Reset eye offset to default
    player:set_eye_offset({x = 0, y = 0, z = 0})
    
    drone_cameras[player_name] = nil
end

-- Calculate drone offset based on player yaw
function menotics_drone.drone_logic.calculate_drone_offset(player_yaw)
    -- Convert yaw to radians
    local yaw_rad = math.rad(player_yaw)
    
    -- Calculate offset relative to player's facing direction
    -- Behind the player means opposite to their look direction
    local x_offset = math.sin(yaw_rad) * DRONE_DISTANCE
    local z_offset = math.cos(yaw_rad) * DRONE_DISTANCE
    
    return {
        x = -x_offset, -- Negative because we want behind
        y = DRONE_HEIGHT,
        z = -z_offset
    }
end

-- Linear interpolation between two vectors
function menotics_drone.drone_logic.lerp_vector(current, target, factor)
    return {
        x = current.x + (target.x - current.x) * factor,
        y = current.y + (target.y - current.y) * factor,
        z = current.z + (target.z - current.z) * factor
    }
end

-- Globalstep function to update all drone cameras
function menotics_drone.drone_logic.globalstep(dtime)
    for player_name, camera_data in pairs(drone_cameras) do
        local player = minetest.get_player_by_name(player_name)
        if not player then
            -- Player disconnected, cleanup
            menotics_drone.drone_logic.disable_drone_camera(player_name)
            if menotics_drone.recording_players[player_name] then
                menotics_drone.drone_logic.stop_recording(player_name)
            end
            goto continue
        end
        
        -- Get player's current position and look direction
        local player_pos = player:get_pos()
        local player_look_dir = player:get_look_dir()
        local player_yaw = math.deg(math.atan2(player_look_dir.x, player_look_dir.z))
        
        -- Calculate target offset based on player's yaw
        local target_offset = menotics_drone.drone_logic.calculate_drone_offset(player_yaw)
        
        -- Smoothly interpolate current offset toward target
        camera_data.current_offset = menotics_drone.drone_logic.lerp_vector(
            camera_data.current_offset,
            target_offset,
            LERP_FACTOR
        )
        
        -- Set eye offset to simulate drone camera
        -- The offset is applied relative to the player's eye position
        player:set_eye_offset(camera_data.current_offset)
        
        -- Handle screenshot capture if recording
        local recording_data = menotics_drone.recording_players[player_name]
        if recording_data and recording_data.active then
            menotics_drone.drone_logic.capture_frame(player_name, recording_data)
            
            -- Check for max duration (90 seconds)
            local max_duration = tonumber(minetest.settings:get("menotics_drone.max_duration")) or 90
            local elapsed = insecure.os.time() - recording_data.start_time
            
            if elapsed >= max_duration then
                minetest.chat_send_player(player_name, "Maximum recording duration reached (90 seconds). Saving...")
                menotics_drone.drone_logic.stop_recording(player_name)
            end
        end
        
        ::continue::
    end
end

-- Capture a single frame for recording
function menotics_drone.drone_logic.capture_frame(player_name, recording_data)
    local fps = tonumber(minetest.settings:get("menotics_drone.fps")) or 20
    local frame_interval = 1.0 / fps
    local current_time = insecure.os.time() -- This gives seconds, need better precision
    
    -- Use get_us_time for better precision if available
    local precise_time = minetest.get_us_time and minetest.get_us_time() / 1000000 or current_time
    
    if precise_time - recording_data.last_frame_time >= frame_interval then
        recording_data.frame_count = recording_data.frame_count + 1
        recording_data.last_frame_time = precise_time
        
        -- Request screenshot
        local frame_filename = string.format("%s/frame_%04d.png", recording_data.temp_dir, recording_data.frame_count)
        
        -- Take screenshot (this saves to screenshots dir by default, we'll need to move it)
        minetest.take_screenshot({
            player = player_name,
            callback = function(filename)
                -- Move screenshot to our temp directory
                if filename then
                    insecure.os.rename(filename, frame_filename)
                end
            end
        })
    end
end

-- Handle player death
function menotics_drone.drone_logic.on_dieplayer(player)
    local player_name = player:get_player_name()
    
    if menotics_drone.recording_players[player_name] then
        minetest.chat_send_player(player_name, "Recording interrupted by death. Saving partial clip...")
        menotics_drone.drone_logic.stop_recording(player_name)
    end
    
    menotics_drone.drone_logic.disable_drone_camera(player_name)
end

-- Handle player disconnect
function menotics_drone.drone_logic.on_leaveplayer(player)
    local player_name = player:get_player_name()
    
    if menotics_drone.recording_players[player_name] then
        minetest.log("action", "[Menotics Drone] Player disconnected during recording. Cleaning up...")
        menotics_drone.drone_logic.stop_recording(player_name)
    end
    
    menotics_drone.drone_logic.disable_drone_camera(player_name)
end

-- Register globalstep
minetest.register_globalstep(function(dtime)
    menotics_drone.drone_logic.globalstep(dtime)
end)

-- Register death handler
minetest.register_on_dieplayer(function(player)
    menotics_drone.drone_logic.on_dieplayer(player)
end)

-- Register disconnect handler
minetest.register_on_leaveplayer(function(player)
    menotics_drone.drone_logic.on_leaveplayer(player)
end)
