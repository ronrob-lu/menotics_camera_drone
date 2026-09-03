--[[
    menotics_camera_drone - Minetest / Luanti Mod
    Attachable stone block camera drone with manual flight and autonomous builder drone tracking.
    License: MIT (2026 ronrob-lu)
]]--

local modpath = minetest.get_modpath("menotics_camera_drone")
local config = dofile(modpath .. "/config.lua")
local logic = dofile(modpath .. "/logic.lua")

local STONE_TEXTURE = "menotics_camera_drone_stone.png"
if minetest.registered_nodes and minetest.registered_nodes["default:stone"] then
    STONE_TEXTURE = "default_stone.png"
end
local TRANSPARENT_TEXTURE = "menotics_camera_drone_transparent.png"

logic.STONE_TEXTURE = STONE_TEXTURE
logic.TRANSPARENT_TEXTURE = TRANSPARENT_TEXTURE

-------------------------------------------------------------------------------
-- Entity Registration: Camera Drone (Stone Block)
-------------------------------------------------------------------------------

minetest.register_entity("menotics_camera_drone:drone", {
    initial_properties = {
        physical = not (config.PASS_THROUGH_BLOCKS == true),
        collide_with_objects = not (config.PASS_THROUGH_BLOCKS == true),
        collisionbox = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 },
        selectionbox = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 },
        visual = "cube",
        visual_size = { x = 1, y = 1 },
        textures = {
            STONE_TEXTURE, -- Top
            STONE_TEXTURE, -- Bottom
            STONE_TEXTURE, -- Right (+X)
            STONE_TEXTURE, -- Left (-X)
            STONE_TEXTURE, -- Back (+Z)
            STONE_TEXTURE, -- Front (-Z)
        },
        static_save = true,
        pointable = true,
    },

    driver = nil,
    mode = "manual",       -- "manual" or "tracking"
    stationed = false,    -- true when resting at static vantage point
    tracking_unbound = false, -- true when driver manually unbinds from tracking
    sneak_time = 0,

    on_activate = function(self, staticdata, dtime_s)
        self.object:set_armor_groups({ cracky = 2, snappy = 2, fleshy = 100 })
        if config.PASS_THROUGH_BLOCKS then
            self.object:set_properties({
                physical = false,
                collide_with_objects = false,
            })
        end
        if staticdata and staticdata ~= "" then
            local data = minetest.deserialize(staticdata)
            if data then
                self.stationed = data.stationed or false
                self.mode = data.mode or "manual"
                self.tracking_unbound = data.tracking_unbound or false
                self.driver_name = data.driver_name
            end
        end
        if config.HIDE_STONE_WHEN_MOUNTED and (self.driver or self.driver_name) then
            self.object:set_properties({
                is_visible = false,
                visual_size = { x = 0, y = 0 },
                pointable = false,
                selectionbox = { 0, 0, 0, 0, 0, 0 },
            })
        else
            self.object:set_properties({
                is_visible = true,
                visual_size = { x = 1, y = 1 },
                pointable = true,
                selectionbox = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 },
            })
        end
    end,

    get_staticdata = function(self)
        local dname = (self.driver and self.driver:is_player()) and self.driver:get_player_name() or self.driver_name
        return minetest.serialize({
            stationed = self.stationed,
            mode = self.mode,
            tracking_unbound = self.tracking_unbound,
            driver_name = dname,
        })
    end,

    on_step = function(self, dtime)
        logic.on_step(self, dtime)
    end,

    on_rightclick = function(self, clicker)
        if not clicker or not clicker:is_player() then return end

        if self.driver == clicker then
            -- Dismount if clicked by current driver (mid-air safe)
            logic.dismount_player(self, true)
        else
            -- Mount player onto stone block drone
            logic.mount_player(self, clicker)
        end
    end,

    on_punch = function(self, puncher)
        if not puncher or not puncher:is_player() then return end

        -- If the driver is punching while mounted, instantly dismount
        if self.driver == puncher then
            logic.dismount_player(self, true)
            return
        end

        -- If not attached, punching it (with pickaxe, sword, tool, or hand) destroys it and drops the item
        logic.dismount_player(self, true)
        local pos = self.object:get_pos()
        if pos then
            minetest.add_item(pos, "menotics_camera_drone:drone_block")
            if minetest.sound_play then
                minetest.sound_play("default_dig_cracky", { pos = pos, gain = 0.8 }, true)
            end
        end
        self.object:remove()
    end,
})

-------------------------------------------------------------------------------
-- Node & Item Registration
-------------------------------------------------------------------------------

-- Placeable Stone Block node
minetest.register_node("menotics_camera_drone:drone_block", {
    description = "Camera Drone (Stone Block)",
    tiles = { STONE_TEXTURE },
    groups = { cracky = 3, oddly_breakable_by_hand = 1 },
    sounds = minetest.registered_nodes["default:stone"] and minetest.node_sound_stone_defaults and minetest.node_sound_stone_defaults() or nil,

    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        if not clicker or not clicker:is_player() then return end

        -- Remove block and spawn the active flying drone entity
        minetest.remove_node(pos)
        local spawn_pos = { x = pos.x, y = pos.y, z = pos.z }
        local drone = minetest.add_entity(spawn_pos, "menotics_camera_drone:drone")
        if drone then
            local lua_ent = drone:get_luaentity()
            if lua_ent then
                logic.mount_player(lua_ent, clicker)
            end
        end
    end,
})


-- Craft recipe (default:stone or 4 cobblestone fallback)
if minetest.registered_nodes and minetest.registered_nodes["default:stone"] then
    minetest.register_craft({
        output = "menotics_camera_drone:drone_block",
        recipe = {
            { "default:stone", "default:stone", "default:stone" },
            { "default:stone", "default:glass", "default:stone" },
            { "default:stone", "default:stone", "default:stone" },
        }
    })
end

-------------------------------------------------------------------------------
-- Player Leave / Death Cleanup Hook
-------------------------------------------------------------------------------

minetest.register_on_leaveplayer(function(player)
    for _, ent in pairs(minetest.luaentities) do
        if ent.name == "menotics_camera_drone:drone" and ent.driver == player then
            logic.dismount_player(ent, true)
        end
    end
end)

minetest.register_on_dieplayer(function(player)
    for _, ent in pairs(minetest.luaentities) do
        if ent.name == "menotics_camera_drone:drone" and ent.driver == player then
            logic.dismount_player(ent, true)
        end
    end
end)

-------------------------------------------------------------------------------
-- Chat Commands
-------------------------------------------------------------------------------

minetest.register_chatcommand("camera_drone", {
    params = "[mount | dismount | unbind | bind | remove | kill | altitude <num> | distance <num> | unstuck]",
    description = "Spawn, mount, dismount, unbind tracking, adjust altitude/distance, or remove camera drones",
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false end

        param = param:trim()
        local parts = param:split(" ")
        local cmd = (parts[1] or ""):lower()

        if cmd == "dismount" then
            for _, ent in pairs(minetest.luaentities) do
                if ent.name == "menotics_camera_drone:drone" and ent.driver == player then
                    logic.dismount_player(ent, true)
                    return true, "[Camera Drone] Safely dismounted."
                end
            end
            return false, "[Camera Drone] You are not riding a camera drone."

        elseif cmd == "unbind" then
            for _, ent in pairs(minetest.luaentities) do
                if ent.name == "menotics_camera_drone:drone" and ent.driver == player then
                    ent.tracking_unbound = true
                    ent.station_angle = nil
                    ent.station_pos = nil
                    return true, "[Camera Drone] Tracking unbound. Switched to manual flight."
                end
            end
            return false, "[Camera Drone] You are not riding a camera drone."

        elseif cmd == "bind" then
            for _, ent in pairs(minetest.luaentities) do
                if ent.name == "menotics_camera_drone:drone" and ent.driver == player then
                    ent.tracking_unbound = false
                    ent.station_angle = nil
                    ent.station_pos = nil
                    return true, "[Camera Drone] Tracking bound to builder drone."
                end
            end
            return false, "[Camera Drone] You are not riding a camera drone."

        elseif cmd == "remove" or cmd == "kill" or cmd == "killall" or cmd == "clear" then
            local count = 0
            for _, ent in pairs(minetest.luaentities) do
                if ent.name == "menotics_camera_drone:drone" then
                    if ent.driver then
                        logic.dismount_player(ent, true)
                    end
                    if ent.object then
                        ent.object:remove()
                        count = count + 1
                    end
                end
            end
            for _, p in ipairs(minetest.get_connected_players()) do
                local parent = p:get_attach()
                if parent then
                    local luaent = parent:get_luaentity()
                    if not luaent or luaent.name == "menotics_camera_drone:drone" then
                        p:set_detach()
                        p:set_eye_offset({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
                        logic.set_player_sitting(p, false)
                    end
                end
            end
            return true, "[Camera Drone] Killed " .. count .. " active camera drone(s)."

        elseif cmd == "reload" then
            logic.reload_config()
            for _, ent in pairs(minetest.luaentities) do
                if ent.name == "menotics_camera_drone:drone" then
                    ent.stationed = false
                    ent.station_angle = nil
                    ent.station_pos = nil
                end
            end
            return true, "[Camera Drone] Live reloaded config.lua! (Altitude=" .. config.TARGET_ALTITUDE .. ", Distance=" .. config.TARGET_DISTANCE .. ")"

        elseif cmd == "altitude" then
            local val = tonumber(parts[2])
            if val then
                config.TARGET_ALTITUDE = val
                for _, ent in pairs(minetest.luaentities) do
                    if ent.name == "menotics_camera_drone:drone" then
                        ent.stationed = false
                        ent.station_angle = nil
                        ent.station_pos = nil
                    end
                end
                return true, "[Camera Drone] Target altitude set to " .. val .. " blocks."
            end
            return false, "Usage: /camera_drone altitude <blocks>"

        elseif cmd == "distance" then
            local val = tonumber(parts[2])
            if val then
                config.TARGET_DISTANCE = val
                config.MIN_DISTANCE = math.max(4, val - 2)
                config.MAX_DISTANCE = val + 4
                for _, ent in pairs(minetest.luaentities) do
                    if ent.name == "menotics_camera_drone:drone" then
                        ent.stationed = false
                        ent.station_angle = nil
                        ent.station_pos = nil
                    end
                end
                return true, "[Camera Drone] Target distance set to " .. val .. " blocks."
            end
            return false, "Usage: /camera_drone distance <blocks>"

        elseif cmd == "unstuck" then
            for _, ent in pairs(minetest.luaentities) do
                if ent.name == "menotics_camera_drone:drone" and (ent.driver == player or not ent.driver) then
                    local p = ent.object:get_pos()
                    if p then
                        local top = logic.find_tree_canopy_top(p.x, p.y, p.z, 25)
                        local new_y = (top or p.y) + (config.TREE_CLEARANCE_HEIGHT or 3) + 2
                        ent.object:set_pos({ x = p.x, y = new_y, z = p.z })
                        ent.stationed = false
                        ent.station_angle = nil
                        ent.station_pos = nil
                        return true, "[Camera Drone] Lifted above tree canopy to Y=" .. math.floor(new_y)
                    end
                end
            end
            return false, "[Camera Drone] No active camera drone found."

        else
            -- Clean up any existing drone already ridden by this player
            for _, ent in pairs(minetest.luaentities) do
                if ent.name == "menotics_camera_drone:drone" and ent.driver == player then
                    logic.dismount_player(ent, true)
                    if ent.object then
                        ent.object:remove()
                    end
                end
            end

            -- Default: spawn at player and mount
            local pos = player:get_pos()
            local drone = minetest.add_entity({ x = pos.x, y = pos.y + 0.2, z = pos.z }, "menotics_camera_drone:drone")
            if drone then
                local lua_ent = drone:get_luaentity()
                if lua_ent then
                    logic.mount_player(lua_ent, player)
                    return true, "[Camera Drone] Spawned and mounted in FPV."
                end
            end
            return false, "[Camera Drone] Failed to spawn camera drone."
        end
    end,
})

-- Dedicated /kill_drones chat command
minetest.register_chatcommand("kill_drones", {
    params = "[all | dummy]",
    description = "Remove all camera drones (and optionally dummy builder drones)",
    func = function(name, param)
        param = (param or ""):trim():lower()
        local camera_count = 0
        local dummy_count = 0

        for _, ent in pairs(minetest.luaentities) do
            if ent.name == "menotics_camera_drone:drone" then
                if ent.driver then
                    logic.dismount_player(ent, true)
                end
                if ent.object then
                    ent.object:remove()
                    camera_count = camera_count + 1
                end
            elseif (param == "all" or param == "dummy") and ent.name == config.TARGET_ENTITY_NAME then
                if ent.object then
                    ent.object:remove()
                    dummy_count = dummy_count + 1
                end
            end
        end

        for _, p in ipairs(minetest.get_connected_players()) do
            local parent = p:get_attach()
            if parent then
                local luaent = parent:get_luaentity()
                if not luaent or luaent.name == "menotics_camera_drone:drone" then
                    p:set_detach()
                    p:set_eye_offset({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
                    logic.set_player_sitting(p, false)
                end
            end
        end

        local msg = "[Camera Drone] Killed " .. camera_count .. " camera drone(s)."
        if dummy_count > 0 then
            msg = msg .. " Removed " .. dummy_count .. " dummy builder drone(s)."
        end
        return true, msg
    end,
})

minetest.register_chatcommand("killdrones", {
    params = "[all | dummy]",
    description = "Shortcut for /kill_drones",
    func = function(name, param)
        return minetest.registered_chatcommands["kill_drones"].func(name, param)
    end,
})

-- Convenient shortcut command to dismount from any drone
if not minetest.registered_chatcommands["dismount"] then
    minetest.register_chatcommand("dismount", {
        description = "Dismount from camera drone",
        func = function(name)
            local player = minetest.get_player_by_name(name)
            if not player then return false end
            for _, ent in pairs(minetest.luaentities) do
                if ent.name == "menotics_camera_drone:drone" and ent.driver == player then
                    logic.dismount_player(ent, true)
                    return true
                end
            end
            return false
        end,
    })
end

-------------------------------------------------------------------------------
-- Dummy Builder Drone for Manual Testing (if city builder mod is not present)
-------------------------------------------------------------------------------

if not minetest.registered_entities[config.TARGET_ENTITY_NAME] then
    -- Register mock builder drone entity with ":" prefix to allow cross-mod name override
    pcall(function()
        minetest.register_entity(":" .. config.TARGET_ENTITY_NAME, {
            initial_properties = {
                physical = false,
                visual = "cube",
                visual_size = { x = 1.2, y = 1.2 },
                textures = {
                    STONE_TEXTURE,
                    STONE_TEXTURE,
                    STONE_TEXTURE,
                    STONE_TEXTURE,
                    STONE_TEXTURE,
                    STONE_TEXTURE,
                },
                collisionbox = { -0.6, -0.6, -0.6, 0.6, 0.6, 0.6 },
                selectionbox = { -0.6, -0.6, -0.6, 0.6, 0.6, 0.6 },
                glow = 12,
            },
            on_activate = function(self)
                self.object:set_armor_groups({ immortal = 1 })
            end,
        })
    end)
end

-- Slash commands to easily test tracking & 50-block leash behavior
minetest.register_chatcommand("spawn_dummy_builder_drone", {
    params = "[distance_blocks]",
    description = "Spawn dummy builder drone to test camera drone auto-lock",
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false end

        local dist = tonumber(param) or 25
        local pos = player:get_pos()
        local dir = player:get_look_dir()

        local target_pos = {
            x = pos.x + dir.x * dist,
            y = pos.y + 5,
            z = pos.z + dir.z * dist,
        }

        local obj = minetest.add_entity(target_pos, config.TARGET_ENTITY_NAME)
        if obj then
            return true
        end
        return false
    end,
})

minetest.register_chatcommand("move_dummy_builder_drone", {
    params = "<distance_from_player>",
    description = "Move dummy builder drone to test tracking corridor and dynamic catch-up speed",
    func = function(name, param)
        local dist = tonumber(param)
        if not dist then return false end

        local player = minetest.get_player_by_name(name)
        if not player then return false end

        local pos = player:get_pos()
        local dir = player:get_look_dir()
        local new_pos = {
            x = pos.x + dir.x * dist,
            y = 20,
            z = pos.z + dir.z * dist,
        }

        for _, ent in pairs(minetest.luaentities) do
            if ent.name == config.TARGET_ENTITY_NAME then
                ent.object:set_pos(new_pos)
                return true
            end
        end
        return false
    end,
})

minetest.register_chatcommand("remove_dummy_builder_drone", {
    description = "Remove all dummy builder drones to return camera drone to free flight",
    func = function(name)
        for _, ent in pairs(minetest.luaentities) do
            if ent.name == config.TARGET_ENTITY_NAME then
                ent.object:remove()
            end
        end
        return true
    end,
})

minetest.log("action", "[menotics_camera_drone] Loaded successfully.")
