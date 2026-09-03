--[[
    menotics_camera_drone - Flight & Tracking Logic
    Smooth, antishake camera drone physics with autonomous builder drone tracking.
]]--

local config = dofile(minetest.get_modpath("menotics_camera_drone") .. "/config.lua")

local logic = {}
logic.config = config

-- Live hot-reload of config.lua without needing to restart Minetest
function logic.reload_config()
    local modpath = minetest.get_modpath("menotics_camera_drone")
    local ok, new_conf = pcall(dofile, modpath .. "/config.lua")
    if ok and type(new_conf) == "table" then
        for k, v in pairs(new_conf) do
            config[k] = v
        end
        logic.config = config
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- Mathematical Helpers
-------------------------------------------------------------------------------

local atan2 = math.atan2 or math.atan

-- Convert 3D direction vector to yaw (radians)
function logic.dir_to_yaw(dir)
    if minetest.dir_to_yaw then
        return minetest.dir_to_yaw(dir)
    end
    return atan2(-dir.x, dir.z)
end

-- Convert 3D direction vector to pitch (radians)
function logic.dir_to_pitch(dir)
    if minetest.dir_to_pitch then
        return minetest.dir_to_pitch(dir)
    end
    local horiz = math.sqrt(dir.x * dir.x + dir.z * dir.z)
    return -atan2(dir.y, horiz)
end

-- Convert horizontal yaw (radians) to 2D horizontal unit direction vector
function logic.yaw_to_dir(yaw)
    if minetest.yaw_to_dir then
        local d = minetest.yaw_to_dir(yaw)
        return { x = d.x, y = 0, z = d.z }
    end
    return {
        x = -math.sin(yaw),
        y = 0,
        z = math.cos(yaw)
    }
end

-- Clamp a value between min and max
function logic.clamp(val, min_v, max_v)
    if val < min_v then return min_v end
    if val > max_v then return max_v end
    return val
end

-- Smoothly interpolate an angle (radians) towards a target angle without wrapping jitter
function logic.smooth_angle(current, target, max_delta)
    local diff = (target - current + math.pi) % (2 * math.pi) - math.pi
    if math.abs(diff) <= max_delta then
        return target
    end
    return current + (diff > 0 and max_delta or -max_delta)
end

-- Smooth exponential velocity transition (dampens harsh acceleration/deceleration)
function logic.lerp_velocity(current, target, smooth_factor, dtime)
    local factor = math.min(1.0, dtime * (smooth_factor or 6.0))
    local vx = current.x + (target.x - current.x) * factor
    local vy = current.y + (target.y - current.y) * factor
    local vz = current.z + (target.z - current.z) * factor
    -- Snap to zero when negligible to avoid floating-point micro-drift
    if math.abs(target.x) < 0.01 and math.abs(vx) < 0.05 then vx = 0 end
    if math.abs(target.y) < 0.01 and math.abs(vy) < 0.05 then vy = 0 end
    if math.abs(target.z) < 0.01 and math.abs(vz) < 0.05 then vz = 0 end
    return { x = vx, y = vy, z = vz }
end

-- Calculate horizontal distance between two 3D positions
function logic.horizontal_distance(pos1, pos2)
    local dx = pos1.x - pos2.x
    local dz = pos1.z - pos2.z
    return math.sqrt(dx * dx + dz * dz)
end

-- Check if a node is a tree (trunk/leaves/branches) or plant foliage
function logic.is_tree_node(node_name)
    if not node_name or node_name == "air" or node_name == "ignore" then
        return false
    end
    local g_leaves = minetest.get_item_group(node_name, "leaves")
    if g_leaves and g_leaves > 0 then return true end
    local g_tree = minetest.get_item_group(node_name, "tree")
    if g_tree and g_tree > 0 then return true end
    local g_flora = minetest.get_item_group(node_name, "flora")
    if g_flora and g_flora > 0 then return true end
    local g_plant = minetest.get_item_group(node_name, "plant")
    if g_plant and g_plant > 0 then return true end
    local g_bush = minetest.get_item_group(node_name, "bush")
    if g_bush and g_bush > 0 then return true end
    local g_decay = minetest.get_item_group(node_name, "leafdecay")
    if g_decay and g_decay > 0 then return true end

    local name = node_name:lower()
    if name:find("leaves") or name:find("needle") or name:find("tree") or
       name:find("trunk") or name:find("branch") or name:find("foliage") or
       name:find("sapling") or name:find("vines") or name:find("bush") or
       name:find("log") then
        return true
    end
    return false
end

-- Check if a position is inside a tree or solid block
function logic.is_blocked_by_tree_or_solid(pos)
    if not minetest.get_node_or_nil then return false end
    local bpos = {
        x = math.floor(pos.x + 0.5),
        y = math.floor(pos.y + 0.5),
        z = math.floor(pos.z + 0.5),
    }
    local node = minetest.get_node_or_nil(bpos)
    if not node or node.name == "air" or node.name == "ignore" then
        return false
    end
    if logic.is_tree_node(node.name) then
        return true, "tree", node.name
    end
    local def = minetest.registered_nodes and minetest.registered_nodes[node.name]
    if def and def.walkable then
        return true, "solid", node.name
    end
    return false
end

-- Check if position or player head/eye view is inside tree foliage
function logic.is_in_tree(pos)
    local blocked, kind = logic.is_blocked_by_tree_or_solid(pos)
    if blocked and kind == "tree" then return true end
    local eye_pos = { x = pos.x, y = pos.y + 1.2, z = pos.z }
    local eye_blocked, eye_kind = logic.is_blocked_by_tree_or_solid(eye_pos)
    if eye_blocked and eye_kind == "tree" then return true end
    return false
end

-- Given a coordinate (X, Z), scan vertically to find the highest tree/leaf/foliage node
function logic.find_tree_canopy_top(x, start_y, z, max_scan)
    if not minetest.get_node_or_nil then return nil end
    max_scan = max_scan or 25
    local highest_tree_y = nil
    for y = math.floor(start_y - 5), math.floor(start_y + max_scan) do
        local check_pos = { x = x, y = y, z = z }
        local blocked, kind = logic.is_blocked_by_tree_or_solid(check_pos)
        if blocked and kind == "tree" then
            highest_tree_y = y
        end
    end
    return highest_tree_y
end

-- Check if direct line-of-sight from camera to builder drone passes through trees/foliage
function logic.has_tree_los_obstruction(from_pos, to_pos)
    local dir = vector.subtract(to_pos, from_pos)
    local dist = vector.length(dir)
    if dist < 1.5 then return false end
    local step_vec = vector.normalize(dir)
    local step_size = 0.8
    local num_steps = math.floor((dist - 1.2) / step_size)
    for i = 1, num_steps do
        local check_pos = vector.add(from_pos, vector.multiply(step_vec, i * step_size))
        local blocked, kind = logic.is_blocked_by_tree_or_solid(check_pos)
        if blocked and kind == "tree" then
            return true, check_pos
        end
    end
    return false
end

-- Find optimal vantage point that avoids trees, branches, and LOS obstructions
function logic.find_optimal_vantage_pos(target_pos, preferred_angle, target_dist, desired_y, min_safe_y)
    if not config.TREE_AVOIDANCE then
        return {
            pos = {
                x = target_pos.x + preferred_angle.x * target_dist,
                y = desired_y,
                z = target_pos.z + preferred_angle.z * target_dist,
            },
            angle = preferred_angle,
            elevated = false,
        }
    end

    local base_rad = atan2(preferred_angle.z, preferred_angle.x)
    -- Sample candidate angular offsets from preferred heading: 0, +/-20 deg, +/-40 deg, up to 180 deg
    local offsets = { 0, 0.35, -0.35, 0.70, -0.70, 1.05, -1.05, 1.40, -1.40, 1.75, -1.75, 2.10, -2.10, 2.50, -2.50, 3.14 }

    local best_candidate = nil
    local best_score = -999999

    for _, off in ipairs(offsets) do
        local ang = base_rad + off
        local dir_x = math.cos(ang)
        local dir_z = math.sin(ang)

        local cand_x = target_pos.x + dir_x * target_dist
        local cand_z = target_pos.z + dir_z * target_dist
        local cand_y = desired_y

        -- Check if candidate position or player head is inside a tree
        local in_tree = logic.is_in_tree({ x = cand_x, y = cand_y, z = cand_z })

        -- Check if canopy directly at/beneath is too close
        local canopy_top = logic.find_tree_canopy_top(cand_x, cand_y, cand_z, 20)
        local clearance_needed = config.TREE_CLEARANCE_HEIGHT or 3

        local elevated = false
        if canopy_top and canopy_top + clearance_needed > cand_y then
            cand_y = canopy_top + clearance_needed
            elevated = true
            in_tree = logic.is_in_tree({ x = cand_x, y = cand_y, z = cand_z })
        end

        local cand_pos = { x = cand_x, y = cand_y, z = cand_z }
        local eye_pos = { x = cand_x, y = cand_y + 1.2, z = cand_z }
        local has_los_tree = logic.has_tree_los_obstruction(cand_pos, target_pos) or
                             logic.has_tree_los_obstruction(eye_pos, target_pos)

        -- Score candidate: penalize tree collisions, LOS obstructions, and elevation
        local score = 100 - math.abs(off) * 15
        if in_tree then
            score = score - 1000
        end
        if has_los_tree then
            score = score - 500
        end
        if elevated then
            score = score - 50
        end

        if score > best_score then
            best_score = score
            best_candidate = {
                pos = cand_pos,
                angle = { x = dir_x, z = dir_z },
                elevated = elevated,
                blocked = (in_tree or has_los_tree),
            }
            -- If completely unobstructed, not elevated, and offset == 0, ideal!
            if not in_tree and not has_los_tree and not elevated and off == 0 then
                break
            end
        end
    end

    if best_candidate and not best_candidate.blocked then
        return best_candidate
    end

    -- If all horizontal angles have tree obstructions, elevate above canopy and sightline trees
    if best_candidate then
        local top = logic.find_tree_canopy_top(best_candidate.pos.x, best_candidate.pos.y, best_candidate.pos.z, 25)
        if top and top + (config.TREE_CLEARANCE_HEIGHT or 3) > best_candidate.pos.y then
            best_candidate.pos.y = top + (config.TREE_CLEARANCE_HEIGHT or 3)
            best_candidate.elevated = true
        end
        local los_blocked, block_pos = logic.has_tree_los_obstruction(best_candidate.pos, target_pos)
        if los_blocked and block_pos then
            local tree_top = logic.find_tree_canopy_top(block_pos.x, block_pos.y, block_pos.z, 25)
            if tree_top then
                local elevated_y = tree_top + (config.TREE_CLEARANCE_HEIGHT or 3) + 2
                if elevated_y > best_candidate.pos.y then
                    best_candidate.pos.y = elevated_y
                    best_candidate.elevated = true
                end
            end
        end
        return best_candidate
    end

    return {
        pos = {
            x = target_pos.x + preferred_angle.x * target_dist,
            y = desired_y,
            z = target_pos.z + preferred_angle.z * target_dist,
        },
        angle = preferred_angle,
        elevated = false,
    }
end

-- Check if drone is resting on solid ground (ignoring tree leaves)
function logic.is_on_ground(drone_pos)
    if not minetest.get_node_or_nil then return false end
    local check_pos = {
        x = math.floor(drone_pos.x + 0.5),
        y = math.floor(drone_pos.y - 0.6 + 0.5),
        z = math.floor(drone_pos.z + 0.5),
    }
    local node = minetest.get_node_or_nil(check_pos)
    if not node then return false end
    if node.name == "air" or node.name == "ignore" then return false end
    -- Tree foliage must not count as landing ground
    if logic.is_tree_node(node.name) then return false end
    local def = minetest.registered_nodes and minetest.registered_nodes[node.name]
    return (def and def.walkable == true)
end

-- Set player visual animation (sitting or standing)
function logic.set_player_sitting(player, sitting)
    if not player or not player:is_player() then return end
    local anim = sitting and "sit" or "stand"
    if player_api and player_api.set_animation then
        player_api.set_animation(player, anim, 30)
    elseif default and default.player_set_animation then
        default.player_set_animation(player, anim, 30)
    else
        local range = sitting and { x = 81, y = 160 } or { x = 0, y = 79 }
        pcall(function() player:set_animation(range, 30, 0) end)
    end
end

-------------------------------------------------------------------------------
-- Target Detection
-------------------------------------------------------------------------------

-- Searches for active builder drone entities in the loaded world
function logic.find_builder_drone(drone_pos)
    local target_obj = nil
    local target_pos = nil
    local min_dist = math.huge

    if minetest.luaentities then
        for _, entity in pairs(minetest.luaentities) do
            if entity and entity.name == config.TARGET_ENTITY_NAME and entity.object then
                local obj = entity.object
                local pos = obj:get_pos()
                if pos then
                    local d = vector.distance(drone_pos, pos)
                    if d < min_dist then
                        min_dist = d
                        target_obj = obj
                        target_pos = pos
                    end
                end
            end
        end
    end

    return target_obj, target_pos, min_dist
end

-------------------------------------------------------------------------------
-- Flight Loop Step
-------------------------------------------------------------------------------

function logic.on_step(self, dtime)
    local object = self.object
    if not object then return end

    -- Periodically check and hot-reload config.lua so changes apply live in-game
    self._conf_timer = (self._conf_timer or 0) + dtime
    if self._conf_timer >= 1.5 then
        self._conf_timer = 0
        logic.reload_config()
    end

    local drone_pos = object:get_pos()
    if not drone_pos then return end

    -- Check driver
    local driver = self.driver
    if not driver then
        if self.driver_name then
            local p = minetest.get_player_by_name(self.driver_name)
            if p and p:is_player() then
                self.driver = p
                driver = p
            end
        end
        if not driver and minetest.get_connected_players then
            for _, player in ipairs(minetest.get_connected_players()) do
                local parent = player:get_attach()
                if parent and parent == object then
                    self.driver = player
                    self.driver_name = player:get_player_name()
                    driver = player
                    break
                end
            end
        end
    end

    if driver then
        if not driver:is_player() then
            self.driver = nil
            self.driver_name = nil
            driver = nil
        else
            self.driver_name = driver:get_player_name()
            logic.set_player_sitting(driver, true)
            -- Prevent suffocation/drowning when passing through solid blocks
            if config.PASS_THROUGH_BLOCKS then
                driver:set_breath(11)
            end
            -- Ensure stone block drone entity stays completely invisible in FPV while mounted
            if config.HIDE_STONE_WHEN_MOUNTED and not self._hidden_applied then
                local trans = logic.TRANSPARENT_TEXTURE or "menotics_camera_drone_transparent.png"
                self.object:set_properties({
                    is_visible = false,
                    visual_size = { x = 0, y = 0 },
                    pointable = false,
                    selectionbox = { 0, 0, 0, 0, 0, 0 },
                    textures = { trans, trans, trans, trans, trans, trans },
                })
                self._hidden_applied = true
            end
        end
    else
        self._hidden_applied = false
    end

    -- Look for city builder drone (unless player manually unbound tracking)
    local target_obj, target_pos, _ = nil, nil, nil
    if not self.tracking_unbound then
        target_obj, target_pos, _ = logic.find_builder_drone(drone_pos)
    end

    if target_obj and target_pos then
        -----------------------------------------------------------------------
        -- AUTONOMOUS TRACKING MODE (Builder Drone is present)
        -----------------------------------------------------------------------
        self.mode = "tracking"

        -- Allow driver to dismount or unbind even while tracking
        if driver then
            local ctrl = driver:get_player_control()

            -- Toggle unbind tracking lock with Jump + Sneak (Space + Shift)
            if ctrl.jump and ctrl.sneak then
                self.tracking_unbound = true
                self.sneak_time = 0
                self.view_aligned = false
                self.station_angle = nil
                self.station_pos = nil
                return
            end

            -- Instant dismount on Left Mouse Button (LMB / Punch / Dig)
            if ctrl.LMB or ctrl.dig then
                logic.dismount_player(self, true)
                return
            end

            -- Dismount when holding Sneak (Shift)
            if ctrl.sneak then
                self.sneak_time = (self.sneak_time or 0) + dtime
                local threshold = config.SNEAK_DISMOUNT_HOLD_TIME or 0.4
                if self.sneak_time >= threshold then
                    self.sneak_time = 0
                    logic.dismount_player(self, true)
                    return
                end
            else
                self.sneak_time = 0
            end
        end

        -- Calculate target speed to detect rapid transit to distant construction sites
        local target_speed = 0
        local target_vel = (target_obj.get_velocity and target_obj:get_velocity()) or nil
        if target_vel then
            target_speed = vector.length(target_vel)
        elseif self.last_target_pos and dtime > 0 then
            target_speed = vector.distance(target_pos, self.last_target_pos) / dtime
        end
        self.last_target_pos = { x = target_pos.x, y = target_pos.y, z = target_pos.z }

        -- Only treat fast movement (e.g. traveling to another site > 5 m/s) as transit.
        local target_fast_transit = (target_speed > 5.0)

        -- Desired altitude:
        -- If USE_RELATIVE_ALTITUDE is true: target_pos.y + config.TARGET_ALTITUDE
        -- (can be negative to fly below the builder drone, closer to ground)
        -- If USE_RELATIVE_ALTITUDE is false: config.TARGET_ALTITUDE (exact world Y level)
        local base_desired_y
        if config.USE_RELATIVE_ALTITUDE then
            base_desired_y = target_pos.y + config.TARGET_ALTITUDE
        else
            base_desired_y = config.TARGET_ALTITUDE
        end

        -- Auto-unstuck check: if drone is physically inside tree leaves, climb immediately
        local unstuck_y = nil
        if config.AUTO_UNSTUCK_FROM_TREES and logic.is_in_tree(drone_pos) then
            local top = logic.find_tree_canopy_top(drone_pos.x, drone_pos.y, drone_pos.z, 25)
            if top then
                unstuck_y = top + (config.TREE_CLEARANCE_HEIGHT or 3)
            end
        end

        local desired_y = (self.station_pos and self.station_pos.y) or base_desired_y
        if unstuck_y and unstuck_y > desired_y then
            desired_y = unstuck_y
        end

        -- Continuous vertical tracking towards desired_y
        local dy = desired_y - drone_pos.y
        local abs_dy = math.abs(dy)
        local vy = 0
        if abs_dy > 0.05 then
            local sign = dy > 0 and 1 or -1
            local v_speed = math.min(12.0, math.max(1.0, abs_dy * 3.0))
            vy = sign * v_speed
        end

        local horiz_dist = logic.horizontal_distance(drone_pos, target_pos)
        local min_dist = config.MIN_DISTANCE or 20
        local max_dist = config.MAX_DISTANCE or 24
        local avoid_dist = config.COLLISION_AVOID_DISTANCE or 16

        -- Stationed check: stay rock-solid static horizontally while target stays in corridor
        -- AND view remains clear of tree foliage and obstructions
        if self.stationed then
            local view_obstructed = false
            if config.TREE_AVOIDANCE then
                self._los_check_timer = (self._los_check_timer or 0) + dtime
                if self._los_check_timer >= 0.4 then
                    self._los_check_timer = 0
                    local in_tree = logic.is_in_tree(drone_pos)
                    local eye_pos = { x = drone_pos.x, y = drone_pos.y + 1.2, z = drone_pos.z }
                    local los_blocked = logic.has_tree_los_obstruction(drone_pos, target_pos) or
                                        logic.has_tree_los_obstruction(eye_pos, target_pos)
                    if in_tree or los_blocked then
                        view_obstructed = true
                    end
                end
            end

            if horiz_dist > max_dist or horiz_dist < min_dist or target_fast_transit or view_obstructed then
                self.stationed = false
                self.station_angle = nil
                self.station_pos = nil
            else
                -- While stationed horizontally, hold X/Z static, but continuously glide Y to desired_y!
                local cur_vel = object:get_velocity() or { x = 0, y = 0, z = 0 }
                local target_vel = { x = 0, y = vy, z = 0 }
                object:set_velocity(logic.lerp_velocity(cur_vel, target_vel, config.SMOOTH_FACTOR or 6.0, dtime))
                object:set_acceleration({ x = 0, y = 0, z = 0 })
            end
        end

        -- If not stationed, smoothly navigate horizontally to optimal vantage point
        if not self.stationed then
            if not self.station_angle or not self.station_pos then
                local dx = drone_pos.x - target_pos.x
                local dz = drone_pos.z - target_pos.z
                local len = math.sqrt(dx * dx + dz * dz)
                if len < 0.1 then
                    dx = 0
                    dz = 1
                    len = 1
                end
                local preferred_angle = { x = dx / len, z = dz / len }
                local vantage = logic.find_optimal_vantage_pos(
                    target_pos,
                    preferred_angle,
                    config.TARGET_DISTANCE,
                    base_desired_y
                )
                self.station_angle = vantage.angle
                self.station_pos = vantage.pos
                self.vantage_elevated = vantage.elevated

                -- Recompute desired_y with new station_pos
                desired_y = (self.station_pos and self.station_pos.y) or base_desired_y
                if unstuck_y and unstuck_y > desired_y then
                    desired_y = unstuck_y
                end
                dy = desired_y - drone_pos.y
                abs_dy = math.abs(dy)
                if abs_dy > 0.05 then
                    local sign = dy > 0 and 1 or -1
                    local v_speed = math.min(12.0, math.max(1.0, abs_dy * 3.0))
                    vy = sign * v_speed
                else
                    vy = 0
                end
            end

            local target_h_x = target_pos.x + self.station_angle.x * config.TARGET_DISTANCE
            local target_h_z = target_pos.z + self.station_angle.z * config.TARGET_DISTANCE
            local h_dx = target_h_x - drone_pos.x
            local h_dz = target_h_z - drone_pos.z
            local h_dist = math.sqrt(h_dx * h_dx + h_dz * h_dz)

            if horiz_dist < avoid_dist then
                -- Collision avoidance: push directly away horizontally without forcing altitude upwards
                local retreat_speed = config.AUTOPILOT_MAX_SPEED or 28.0
                local target_vel = {
                    x = self.station_angle.x * retreat_speed,
                    y = vy,
                    z = self.station_angle.z * retreat_speed,
                }
                local cur_vel = object:get_velocity() or { x = 0, y = 0, z = 0 }
                object:set_velocity(logic.lerp_velocity(cur_vel, target_vel, config.SMOOTH_FACTOR or 6.0, dtime))
                object:set_acceleration({ x = 0, y = 0, z = 0 })

            elseif h_dist <= 1.0 and abs_dy <= 1.5 and not target_fast_transit then
                -- Arrived at vantage corridor horizontally and vertically
                self.stationed = true
                local cur_vel = object:get_velocity() or { x = 0, y = 0, z = 0 }
                object:set_velocity(logic.lerp_velocity(cur_vel, { x = 0, y = vy, z = 0 }, config.SMOOTH_FACTOR or 6.0, dtime))
                object:set_acceleration({ x = 0, y = 0, z = 0 })

            else
                -- Fly towards vantage corridor horizontally while smoothly tracking Y
                local h_dir_x = h_dx / h_dist
                local h_dir_z = h_dz / h_dist
                local decel_dist = config.DECEL_DISTANCE or 6.0
                local base_speed = math.max(config.AUTOPILOT_SPEED or 16.0, target_speed + 2.0)
                local max_speed = config.AUTOPILOT_MAX_SPEED or 28.0

                local desired_h_speed
                if h_dist > decel_dist then
                    desired_h_speed = math.min(max_speed, base_speed + (h_dist - decel_dist) * 1.0)
                else
                    desired_h_speed = math.max(2.0, base_speed * (h_dist / decel_dist))
                end

                local target_vel = {
                    x = h_dir_x * desired_h_speed,
                    y = vy,
                    z = h_dir_z * desired_h_speed,
                }
                local cur_vel = object:get_velocity() or { x = 0, y = 0, z = 0 }
                object:set_velocity(logic.lerp_velocity(cur_vel, target_vel, config.SMOOTH_FACTOR or 6.0, dtime))
                object:set_acceleration({ x = 0, y = 0, z = 0 })
            end
        end

        -- Smoothly rotate the stone drone entity to face the builder drone
        local to_target = vector.subtract(target_pos, drone_pos)
        local dir_to_target = vector.normalize(to_target)
        local target_yaw = logic.dir_to_yaw(dir_to_target)
        local target_pitch = logic.dir_to_pitch(dir_to_target)

        local cur_yaw = object:get_yaw() or target_yaw
        local max_rot = (config.ROTATION_SMOOTH_SPEED or 2.0) * dtime
        local new_yaw = logic.smooth_angle(cur_yaw, target_yaw, max_rot)
        object:set_yaw(new_yaw)

        -- Lock player head/camera view onto the builder drone in FPV mode so the player cannot look away
        if driver then
            local cur_look_h = driver:get_look_horizontal()
            local cur_look_v = driver:get_look_vertical()
            local diff_h = math.abs((target_yaw - cur_look_h + math.pi) % (2 * math.pi) - math.pi)
            local diff_v = math.abs(target_pitch - cur_look_v)

            if diff_h > 0.005 or diff_v > 0.005 or not self.view_aligned then
                driver:set_look_horizontal(target_yaw)
                driver:set_look_vertical(target_pitch)
                self.view_aligned = true
            end
        end

    else
        -----------------------------------------------------------------------
        -- MANUAL FREE FLIGHT MODE (No Builder Drone or tracking is unbound)
        -----------------------------------------------------------------------
        self.mode = "manual"
        self.stationed = false
        self.view_aligned = false
        self.station_angle = nil
        self.station_pos = nil

        if driver then
            local ctrl = driver:get_player_control()
            local look_yaw = driver:get_look_horizontal()

            local speed = ctrl.aux1 and config.MANUAL_FAST_SPEED or config.MANUAL_FLY_SPEED
            local forward = logic.yaw_to_dir(look_yaw)
            local right = { x = forward.z, y = 0, z = -forward.x }

            local move_x = 0
            local move_z = 0
            local move_y = 0

            if ctrl.up then
                move_x = move_x + forward.x
                move_z = move_z + forward.z
            end
            if ctrl.down then
                move_x = move_x - forward.x
                move_z = move_z - forward.z
            end
            if ctrl.right then
                move_x = move_x + right.x
                move_z = move_z + right.z
            end
            if ctrl.left then
                move_x = move_x - right.x
                move_z = move_z - right.z
            end

            -- Normalize horizontal movement vector
            local h_len = math.sqrt(move_x * move_x + move_z * move_z)
            if h_len > 0.001 then
                move_x = (move_x / h_len) * speed
                move_z = (move_z / h_len) * speed
            else
                move_x = 0
                move_z = 0
            end

            -- Vertical ascent/descent
            if ctrl.jump then
                move_y = move_y + config.MANUAL_VERTICAL_SPEED
            end

            -- Instant mid-air dismount combo: Jump + Sneak (Space + Shift)
            if ctrl.jump and ctrl.sneak then
                logic.dismount_player(self, true)
                return
            end

            -- Instant dismount on Left Mouse Button (LMB / Punch / Dig)
            if ctrl.LMB or ctrl.dig then
                logic.dismount_player(self, true)
                return
            end

            if ctrl.sneak then
                -- Descend while flying
                move_y = move_y - config.MANUAL_VERTICAL_SPEED

                -- Dismount if drone is landed on solid ground or held stationary in mid-air
                local grounded = logic.is_on_ground(drone_pos)
                if grounded or (config.ALLOW_MIDAIR_DISMOUNT and h_len < 0.001 and not ctrl.jump) then
                    self.sneak_time = (self.sneak_time or 0) + dtime
                    local threshold = grounded and (config.SNEAK_DISMOUNT_HOLD_TIME or 0.4) or 1.2
                    if self.sneak_time >= threshold then
                        logic.dismount_player(self, true)
                        self.sneak_time = 0
                        return
                    end
                else
                    self.sneak_time = 0
                end
            else
                self.sneak_time = 0
            end

            -- Smooth velocity transitions in manual flight
            local desired_vel = { x = move_x, y = move_y, z = move_z }
            local cur_vel = object:get_velocity() or { x = 0, y = 0, z = 0 }
            object:set_velocity(logic.lerp_velocity(cur_vel, desired_vel, config.SMOOTH_FACTOR or 6.0, dtime))
            object:set_acceleration({ x = 0, y = 0, z = 0 })
        else
            -- No driver and no builder drone: smoothly hover to stationary stop
            local cur_vel = object:get_velocity() or { x = 0, y = 0, z = 0 }
            object:set_velocity(logic.lerp_velocity(cur_vel, { x = 0, y = 0, z = 0 }, config.SMOOTH_FACTOR or 6.0, dtime))
            object:set_acceleration({ x = 0, y = 0, z = 0 })
        end
    end
end

-------------------------------------------------------------------------------
-- Player Mount & Dismount
-------------------------------------------------------------------------------

function logic.mount_player(self, player)
    if not player or not player:is_player() then return end

    -- Detach previous driver if any
    if self.driver and self.driver ~= player then
        logic.dismount_player(self, true)
    end

    self.driver = player
    self.driver_name = player:get_player_name()
    self.sneak_time = 0
    self.view_aligned = false
    self.station_angle = nil
    self.station_pos = nil

    -- Protect player from fall damage and suffocation/drowning while operating the drone
    local armors = player:get_armor_groups() or {}
    self.orig_armor_groups = table.copy(armors)
    armors.fall_damage_add_percent = -100
    armors.drowning = 0
    player:set_armor_groups(armors)
    if config.PASS_THROUGH_BLOCKS then
        player:set_breath(11)
    end

    -- Attach player to the stone block drone entity
    player:set_attach(self.object, "", config.ATTACH_OFFSET, config.ATTACH_ROTATION)
    player:set_eye_offset(config.EYE_OFFSET_FIRST_PERSON, config.EYE_OFFSET_THIRD_PERSON)

    -- Hide stone block drone entity in FPV while mounted:
    -- Setting is_visible = false, visual_size = {x=0, y=0}, transparent textures, and pointable = false
    -- completely eliminates any chance of the cube mesh or bounding box being rendered.
    if config.HIDE_STONE_WHEN_MOUNTED and self.object then
        local trans = logic.TRANSPARENT_TEXTURE or "menotics_camera_drone_transparent.png"
        self.object:set_properties({
            is_visible = false,
            visual_size = { x = 0, y = 0 },
            pointable = false,
            selectionbox = { 0, 0, 0, 0, 0, 0 },
            textures = { trans, trans, trans, trans, trans, trans },
        })
        self._hidden_applied = true
    end

    -- Set visual sitting pose
    logic.set_player_sitting(player, true)
end

function logic.dismount_player(self, forced)
    local player = self.driver
    if not player or not player:is_player() then
        self.driver = nil
        self.driver_name = nil
        self._hidden_applied = false
        self.sneak_time = 0
        self.view_aligned = false
        self.station_angle = nil
        self.station_pos = nil
        if self.object then
            local stone = logic.STONE_TEXTURE or "menotics_camera_drone_stone.png"
            self.object:set_properties({
                is_visible = true,
                visual_size = { x = 1, y = 1 },
                pointable = true,
                selectionbox = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 },
                textures = { stone, stone, stone, stone, stone, stone },
            })
        end
        return true
    end

    local pos = self.object and self.object:get_pos()
    local is_grounded = pos and logic.is_on_ground(pos)

    -- Check if mid-air dismount is permitted
    if not forced and not config.ALLOW_MIDAIR_DISMOUNT and not is_grounded then
        return false
    end

    logic.set_player_sitting(player, false)
    player:set_detach()
    player:set_eye_offset({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })

    -- Align stone block yaw with player's final look direction upon dismount
    if self.object and player:is_player() then
        pcall(function()
            self.object:set_yaw(player:get_look_horizontal())
        end)
    end

    -- Restore visibility, scale, and selection box of the stone block drone entity upon dismount
    if self.object then
        local stone = logic.STONE_TEXTURE or "menotics_camera_drone_stone.png"
        self.object:set_properties({
            is_visible = true,
            visual_size = { x = 1, y = 1 },
            pointable = true,
            selectionbox = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 },
            textures = { stone, stone, stone, stone, stone, stone },
        })
    end

    -- Safe landing offset beside the drone and reset vertical velocity
    if pos then
        player:set_pos({ x = pos.x, y = pos.y + 0.6, z = pos.z })
    end
    player:set_velocity({ x = 0, y = 0, z = 0 })

    -- Restore original armor groups after a grace period to prevent fall damage on landing
    local grace_time = config.MIDAIR_DISMOUNT_GRACE_TIME or 6.0
    local orig_armor = self.orig_armor_groups
    minetest.after(grace_time, function()
        if player:is_player() and orig_armor then
            player:set_armor_groups(orig_armor)
        end
    end)

    self.driver = nil
    self.driver_name = nil
    self._hidden_applied = false
    self.sneak_time = 0
    self.view_aligned = false
    self.station_angle = nil
    self.station_pos = nil
    return true
end

return logic
