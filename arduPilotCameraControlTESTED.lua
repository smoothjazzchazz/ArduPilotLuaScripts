
--[[
Waypoint-Based Camera Control System for ArduPilot
For use with Pixhawk flight controllers and camera gimbals
]]

-- Configuration parameters
local CAMERA_CONFIG = {
    SERVO_PAN_CHANNEL = 6,     -- Pan servo channel
    SERVO_TILT_CHANNEL = 7,    -- Tilt servo channel
    PAN_MIN = 1000,            -- Min PWM value for pan servo
    PAN_MAX = 2000,            -- Max PWM value for pan servo
    TILT_MIN = 1100,           -- Min PWM value for tilt servo
    TILT_MAX = 1900,           -- Max PWM value for tilt servo
    GIMBAL_STABILIZE = true,   -- Enable gimbal stabilization
}

-- Initialize camera control system
function init()
    gcs:send_text(6, "CameraControl: Initializing camera system")
    if CAMERA_CONFIG.GIMBAL_STABILIZE then
        enable_gimbal_stabilization()
    end
    return update, 100  -- 10Hz update rate
end

--[[
Set Camera Gimbal Orientation
Controls both pan and tilt servos
@param pan_deg Pan angle in degrees (-180 to 180)
@param tilt_deg Tilt angle in degrees (-90 to 90)
]]
function set_gimbal_orientation(pan_deg, tilt_deg)
    -- Constrain values to valid ranges
    pan_deg = constrain(pan_deg, -180, 180)
    tilt_deg = constrain(tilt_deg, -90, 90)
    
    -- Map angle ranges to PWM values
    local pan_pwm = map_value(pan_deg, -180, 180, CAMERA_CONFIG.PAN_MIN, CAMERA_CONFIG.PAN_MAX)
    local tilt_pwm = map_value(tilt_deg, -90, 90, CAMERA_CONFIG.TILT_MIN, CAMERA_CONFIG.TILT_MAX)
    
    -- Set servo outputs
    SRV_Channels:set_output_pwm(CAMERA_CONFIG.SERVO_PAN_CHANNEL, pan_pwm)
    SRV_Channels:set_output_pwm(CAMERA_CONFIG.SERVO_TILT_CHANNEL, tilt_pwm)
    
    return true
end

--[[
Enable Gimbal Stabilization
Configures gimbal to maintain level regardless of vehicle attitude
]]
function enable_gimbal_stabilization()
    -- Send MAVLink command to enable stabilization
    -- MAV_CMD_DO_MOUNT_CONFIGURE = 204
    -- param1: mount mode (2 = mavlink targeting)
    -- param2: stabilize roll (1 = yes)
    -- param3: stabilize pitch (1 = yes)
    -- param4: stabilize yaw (1 = yes)
    vehicle:command_long(204, 0, 0, 2, 1, 1, 1, 0, 0, 0)
    gcs:send_text(6, "CameraControl: Gimbal stabilization enabled")
end

--[[
Point Camera at GPS Location
Directs the camera gimbal toward a specific GPS coordinate
@param lat Target latitude
@param lng Target longitude
@param alt Target altitude in meters
]]
function point_camera_at_location(lat, lng, alt)
    -- Get vehicle's current position
    local current_pos = ahrs:get_position()
    if not current_pos then
        gcs:send_text(3, "CameraControl: Unable to get current position")
        return false
    end
    
    -- Calculate bearing and elevation to target
    local bearing = current_pos:get_bearing(lat, lng)
    
    -- Calculate distance to target
    local distance = current_pos:get_distance(lat, lng)
    
    -- Calculate vertical angle (elevation)
    local alt_diff = alt - current_pos:alt()
    local elevation = math.deg(math.atan2(alt_diff, distance))
    
    -- Adjust for vehicle heading to get relative pan angle
    local vehicle_yaw = math.deg(ahrs:get_yaw())
    local relative_pan = wrap_180(bearing - vehicle_yaw)
    
    -- Set gimbal orientation
    return set_gimbal_orientation(relative_pan, elevation)
end

--[[
Track Moving Target
Continuously points camera at a defined target position
@param target_lat Target latitude 
@param target_lng Target longitude
@param target_alt Target altitude in meters
]]
function track_target(target_lat, target_lng, target_alt)
    -- Schedule regular updates to keep pointing at target
    local function tracking_update()
        if not point_camera_at_location(target_lat, target_lng, target_alt) then
            return
        end
        return tracking_update, 100  -- Continue tracking at 10Hz
    end
    
    gcs:send_text(6, "CameraControl: Tracking target at " .. 
                    string.format("%.6f,%.6f", target_lat, target_lng))
    return tracking_update, 100
end

--[[
Execute Camera Sweep
Performs a panning sweep with the camera
@param start_angle Starting pan angle in degrees
@param end_angle Ending pan angle in degrees  
@param speed Degrees per second to sweep
@param take_photos Whether to take photos during sweep
]]
function execute_camera_sweep(start_angle, end_angle, speed, take_photos)
    start_angle = start_angle or -90
    end_angle = end_angle or 90
    speed = speed or 20          -- degrees per second
    take_photos = take_photos or false
    
    -- Calculate sweep duration
    local angle_diff = math.abs(end_angle - start_angle)
    local sweep_time = angle_diff / speed
    
    gcs:send_text(6, "CameraControl: Starting camera sweep from " .. 
                    start_angle .. "° to " .. end_angle .. "°")
    
    -- Set initial position
    set_gimbal_orientation(start_angle, 0)
    
    -- Allow time to reach start position
    luautils.delay(500)
    
    -- Calculate step size for gradual movement
    local steps = 20
    local angle_step = (end_angle - start_angle) / steps
    local step_delay = (sweep_time * 1000) / steps
    
    -- Execute sweep
    for i = 0, steps do
        local current_angle = start_angle + (i * angle_step)
        set_gimbal_orientation(current_angle, 0)
        
        if take_photos and i % 4 == 0 then  -- Take photo every 4th step
            trigger_camera()
        end
        
        luautils.delay(step_delay)
    end
    
    gcs:send_text(6, "CameraControl: Camera sweep completed")
end

--[[
Trigger Camera
Sends command to take a photo
]]
function trigger_camera()
    -- MAVLink command: MAV_CMD_DO_DIGICAM_CONTROL = 203
    -- param1-5 are 0 for simple trigger
    -- param6: 1 to trigger camera
    vehicle:command_long(203, 0, 0, 0, 0, 0, 1, 0, 0, 0)
    return true
end

--[[
Start Video Recording
Begin video recording
]]
function start_recording()
    -- MAVLink command: MAV_CMD_VIDEO_START_CAPTURE = 2500
    -- param1: Camera ID (0 = all cameras)
    -- param2: Frames per second (0 = use default)
    vehicle:command_long(2500, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    gcs:send_text(6, "CameraControl: Starting video recording")
    return true
end

--[[
Stop Video Recording
Stop video recording
]]
function stop_recording()
    -- MAVLink command: MAV_CMD_VIDEO_STOP_CAPTURE = 2501
    -- param1: Camera ID (0 = all cameras)
    vehicle:command_long(2501, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    gcs:send_text(6, "CameraControl: Stopping video recording")
    return true
end

-- Utility functions
function constrain(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
end

function map_value(x, in_min, in_max, out_min, out_max)
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min
end

function wrap_180(angle_deg)
    local res = angle_deg
    while res > 180 do res = res - 360 end
    while res < -180 do res = res + 360 end
    return res
end

-- Main update function
function update()
    -- This function is called at the update rate specified in init()
    -- It can be used for continuous monitoring and control
    return update, 100
end

-- Waypoint-based camera actions
function process_waypoint_camera_actions(wp_num)
    -- Define camera actions for specific waypoints
    local camera_actions = {
        [3] = function() 
            set_gimbal_orientation(0, -45)  -- Look down 45°
            trigger_camera()
        end,
        [5] = function() execute_camera_sweep(-90, 90, 15, true) end,
        [7] = function() 
            start_recording()
            -- Schedule stop recording after 20 seconds
            local function stop_rec_later()
                stop_recording()
            end
            return stop_rec_later, 20000
        end,
        [10] = function()
            -- Point at predetermined landmark
            local landmark_lat = 47.0679
            local landmark_lng = -122.1234
            local landmark_alt = 50
            point_camera_at_location(landmark_lat, landmark_lng, landmark_alt)
            trigger_camera()
        end
    }
    
    -- Execute camera action if defined for this waypoint
    if camera_actions[wp_num] then
        gcs:send_text(6, "CameraControl: Action for waypoint " .. wp_num)
        local callback, delay = camera_actions[wp_num]()
        if callback and delay then
            return callback, delay
        end
    end
end

-- Monitor for waypoint changes and trigger camera actions
function update()
    -- Check if we reached a new waypoint
    local wp_num = get_current_waypoint()
    if wp_num and is_at_waypoint() then
        local current_wp = mission:get_last_reached_wp()
        if current_wp then
            -- Process camera actions for this waypoint
            process_waypoint_camera_actions(current_wp)
        end
    end
    
    return update, 100
end

-- Helper functions for waypoint detection
function get_current_waypoint()
    return mission:get_current_nav_id()
end

function is_at_waypoint()
    if not arming:is_armed() then return false end
    
    local mode = vehicle:get_mode()
    if mode ~= 10 and mode ~= 3 and mode ~= 4 then 
        -- Not in AUTO, GUIDED or RTL mode
        return false 
    end
    
    -- Get distance to current waypoint
    local wp_dist = mission:get_current_nav_distance()
    return wp_dist ~= nil and wp_dist < 5 -- 5m radius
end