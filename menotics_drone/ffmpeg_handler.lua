-- Menotics Camera Drone - FFmpeg Handler
-- Handles all FFmpeg operations for video and audio capture

local modname = "menotics_drone"
local insecure = menotics_drone.insecure
local os = insecure.os
local io = insecure.io

menotics_drone.ffmpeg_handler = {}

-- Detect OS type
function menotics_drone.ffmpeg_handler.detect_os()
    local setting = minetest.settings:get("menotics_drone.os_type")
    if setting and setting ~= "auto" then
        return setting
    end
    
    -- Auto-detect
    local path_sep = package.config:sub(1,1)
    if path_sep == "\\" then
        return "windows"
    elseif os.execute("uname -s 2>/dev/null | grep -q Darwin") then
        return "mac"
    else
        return "linux"
    end
end

-- Get audio device name from settings
function menotics_drone.ffmpeg_handler.get_audio_device()
    return minetest.settings:get("menotics_drone.audio_device_name") or ""
end

-- Build FFmpeg command for audio capture
function menotics_drone.ffmpeg_handler.build_audio_capture_cmd(output_file)
    local os_type = menotics_drone.ffmpeg_handler.detect_os()
    local audio_device = menotics_drone.ffmpeg_handler.get_audio_device()
    
    if os_type == "windows" then
        if audio_device == "" then
            audio_device = "Stereo Mix" -- Default fallback
        end
        return string.format('ffmpeg -y -f dshow -i audio="%s" -acodec pcm_s16le -ar 44100 -ac 2 "%s"', 
            audio_device, output_file)
    elseif os_type == "linux" then
        -- Try pulse first, fallback to alsa
        return string.format('ffmpeg -y -f pulse -i default -acodec pcm_s16le -ar 44100 -ac 2 "%s" 2>/dev/null || ffmpeg -y -f alsa -i default -acodec pcm_s16le -ar 44100 -ac 2 "%s"',
            output_file, output_file)
    elseif os_type == "mac" then
        if audio_device == "" then
            audio_device = "0" -- Default device index
        end
        return string.format('ffmpeg -y -f avfoundation -i ":%s" -acodec pcm_s16le -ar 44100 -ac 2 "%s"',
            audio_device, output_file)
    end
    
    return nil
end

-- Start audio capture process
function menotics_drone.ffmpeg_handler.start_audio_capture(player_name, temp_dir)
    local audio_file = temp_dir .. "/audio.wav"
    local cmd = menotics_drone.ffmpeg_handler.build_audio_capture_cmd(audio_file)
    
    if not cmd then
        return false, "Unsupported OS"
    end
    
    -- Run in background
    local os_type = menotics_drone.ffmpeg_handler.detect_os()
    if os_type == "windows" then
        cmd = 'start /B ' .. cmd
    else
        cmd = cmd .. ' &'
    end
    
    local result = os.execute(cmd)
    if result then
        menotics_drone.recording_players[player_name].audio_file = audio_file
        menotics_drone.recording_players[player_name].audio_pid = result
        return true, audio_file
    end
    
    return false, "Failed to start audio capture"
end

-- Stop audio capture process
function menotics_drone.ffmpeg_handler.stop_audio_capture(player_name)
    local data = menotics_drone.recording_players[player_name]
    if not data or not data.audio_pid then
        return
    end
    
    local os_type = menotics_drone.ffmpeg_handler.detect_os()
    if os_type == "windows" then
        -- Kill by process name (ffmpeg)
        os.execute('taskkill /F /IM ffmpeg.exe')
    else
        -- Kill specific PID
        os.execute('kill ' .. tostring(data.audio_pid))
    end
    
    data.audio_pid = nil
end

-- Build FFmpeg command to create video from frames
function menotics_drone.ffmpeg_handler.build_video_from_frames_cmd(temp_dir, output_file, fps)
    -- Create video from image sequence, crop to 9:16 vertical format
    -- Assuming frames are named frame_0001.png, frame_0002.png, etc.
    local frame_pattern = temp_dir .. "/frame_%04d.png"
    
    -- First create video at original resolution
    local temp_video = temp_dir .. "/temp_video.mp4"
    local cmd = string.format('ffmpeg -y -framerate %d -i "%s" -c:v libx264 -pix_fmt yuv420p -vf "crop=ih*(9/16):ih:(iw-ih*(9/16))/2:0,pad=ih*(9/16):ih:(ow-iw)/2:(oh-ih)/2" "%s"',
        fps, frame_pattern, temp_video)
    
    return cmd, temp_video
end

-- Mux video with audio
function menotics_drone.ffmpeg_handler.mux_video_audio(video_file, audio_file, output_file)
    local cmd = string.format('ffmpeg -y -i "%s" -i "%s" -c:v copy -c:a aac -shortest "%s"',
        video_file, audio_file, output_file)
    return os.execute(cmd)
end

-- Create silent video (fallback when audio fails)
function menotics_drone.ffmpeg_handler.create_silent_video(temp_dir, output_file, fps)
    local frame_pattern = temp_dir .. "/frame_%04d.png"
    local cmd = string.format('ffmpeg -y -framerate %d -i "%s" -c:v libx264 -pix_fmt yuv420p -vf "crop=ih*(9/16):ih:(iw-ih*(9/16))/2:0,pad=ih*(9/16):ih:(ow-iw)/2:(oh-ih)/2" -an "%s"',
        fps, frame_pattern, output_file)
    return os.execute(cmd)
end

-- Finalize recording: stitch frames, mux audio, cleanup
function menotics_drone.ffmpeg_handler.finalize_recording(player_name)
    local data = menotics_drone.recording_players[player_name]
    if not data then
        return false, "No recording data found"
    end
    
    local temp_dir = data.temp_dir
    local fps = tonumber(minetest.settings:get("menotics_drone.fps")) or 20
    local output_dir = minetest.get_modpath(modname) .. "/recordings"
    
    -- Create output directory if it doesn't exist
    os.execute('mkdir "' .. output_dir .. '"')
    
    -- Generate output filename with timestamp
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local output_file = output_dir .. "/drone_recording_" .. player_name .. "_" .. timestamp .. ".mp4"
    
    -- Stop audio capture first
    menotics_drone.ffmpeg_handler.stop_audio_capture(player_name)
    
    -- Small delay to ensure audio file is flushed
    insecure.socket = insecure.require("socket")
    if insecure.socket then
        insecure.socket.sleep(0.5)
    end
    
    local success = false
    local final_output = output_file
    
    -- Check if we have audio
    if data.audio_file and os.rename(data.audio_file, data.audio_file) then
        -- Audio file exists, try to mux
        local cmd, temp_video = menotics_drone.ffmpeg_handler.build_video_from_frames_cmd(temp_dir, output_file, fps)
        
        if os.execute(cmd) then
            -- Video created successfully, now mux with audio
            if menotics_drone.ffmpeg_handler.mux_video_audio(temp_video, data.audio_file, output_file) then
                success = true
            else
                minetest.log("warning", "[Menotics Drone] Audio mux failed, creating silent video")
            end
        end
        
        -- Cleanup temp video
        if temp_video then
            os.remove(temp_video)
        end
    end
    
    -- Fallback to silent video if audio failed
    if not success then
        minetest.chat_send_player(player_name, "Audio capture failed. Saved silent video. Check your audio device settings.")
        success = menotics_drone.ffmpeg_handler.create_silent_video(temp_dir, output_file, fps)
    end
    
    -- Cleanup temp directory
    menotics_drone.ffmpeg_handler.cleanup_temp_dir(temp_dir)
    
    if success then
        minetest.chat_send_player(player_name, "Recording saved to: " .. output_file)
        return true, output_file
    else
        minetest.chat_send_player(player_name, "Failed to save recording. Check logs.")
        return false, "Finalization failed"
    end
end

-- Cleanup temporary directory
function menotics_drone.ffmpeg_handler.cleanup_temp_dir(temp_dir)
    if not temp_dir then return end
    
    local os_type = menotics_drone.ffmpeg_handler.detect_os()
    if os_type == "windows" then
        os.execute('rmdir /s /q "' .. temp_dir .. '"')
    else
        os.execute('rm -rf "' .. temp_dir .. '"')
    end
end

-- List audio devices (for /drone_audio_setup command)
function menotics_drone.ffmpeg_handler.list_audio_devices()
    local os_type = menotics_drone.ffmpeg_handler.detect_os()
    local cmd
    
    if os_type == "windows" then
        cmd = 'ffmpeg -list_devices true -f dshow -i dummy 2>&1 | findstr "DirectShow"'
    elseif os_type == "linux" then
        cmd = 'pactl list sources | grep "Name:"'
    elseif os_type == "mac" then
        cmd = 'ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep "Audio"'
    end
    
    if cmd then
        local handle = io.popen(cmd)
        if handle then
            local result = handle:read("*a")
            handle:close()
            return result
        end
    end
    
    return "Unable to list audio devices for this OS."
end
