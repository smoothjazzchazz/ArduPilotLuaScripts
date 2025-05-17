--[[
ArduPilot Lua Scripts for Waypoint-Based Flight Routines
For use with Pixhawk flight controllers
Requires ArduPilot 4.1+ (I think, I lowkey don't remember the version of ArduPilot I was writing this for)
with Lua scripting enabled
]]


-- Example usage
-- Load the script on the Pixhawk and it will automatically
-- execute the defined actions when reaching specific waypoints
-- in the mission plan.


-- Global configuration settings
local CONFIG = {
    ENABLE_DEBUG = true,         -- Enable debug messages
    WAYPOINT_RADIUS = 5,         -- Distance in meters to consider waypoint reached
    UPDATE_RATE_HZ = 10,         -- Script execution frequency
    MAX_LOITER_TIME = 30,        -- Maximum loiter time in seconds
}


function init()
    -- Register the script with MAVLink
    gcs:send_text(6, "WaypointActions: Script initialized")
    
    -- Set up the update timer
    return update, 1000 / CONFIG.UPDATE_RATE_HZ
end

-- Log debug information if enabled
function log_debug(message)
    if CONFIG.ENABLE_DEBUG then
        gcs:send_text(3, "WaypointActions: " .. message)
    end
end

-- Check for waypoint
function is_at_waypoint()
    if not arming:is_armed() then return false end
    
    local mode = vehicle:get_mode()
    if mode ~= 10 and mode ~= 3 and mode ~= 4 then 
        -- Not in AUTO, GUIDED or RTL mode
        return false 
    end
    
    -- Get distance to current waypoint
    local wp_dist = mission:get_current_nav_distance()
    return wp_dist ~= nil and wp_dist < CONFIG.WAYPOINT_RADIUS
end

-- Get current waypoint number
function get_current_waypoint()
    return mission:get_current_nav_id()
end

-- Main update function called at configured rate
function update()
    if not arming:is_armed() then
        return update, 1000 / CONFIG.UPDATE_RATE_HZ
    end
    
    -- Check if we're at a waypoint
    if is_at_waypoint() then
        local wp_num = get_current_waypoint()
        log_debug("At waypoint " .. tostring(wp_num))
        
        -- Execute actions based on waypoint
        execute_waypoint_action(wp_num)
    end
    
    return update, 1000 / CONFIG.UPDATE_RATE_HZ
end

--[[
Execute Circle Maneuver
Performs a circular pattern at current location
@param radius Circle radius in meters
@param loops Number of loops to perform
@param clockwise Boolean, true for clockwise direction
]]
function execute_circle_maneuver(radius, loops, clockwise)
    radius = radius or 15
    loops = loops or 1
    clockwise = clockwise or true
    
    log_debug("Circle maneuver: radius=" .. radius .. "m, loops=" .. loops)
    
    -- Ensure we're in guided mode first
    if vehicle:get_mode() ~= 4 then
        vehicle:set_mode(4) -- Set to GUIDED mode
        gcs:send_text(6, "Switching to GUIDED for circle maneuver")
    end
    
    -- Send CIRCLE_START command
    -- MAVLink command: MAV_CMD_DO_CIRCLE = 217
    -- param1: radius in meters
    -- param2: velocity in m/s
    -- param3: direction (1=clockwise, -1=counterclockwise)
    -- param4: loops (0=continuous, >0=specific number)
    local direction = clockwise and 1 or -1
    vehicle:run_aux_function(1, radius, direction, loops)
    
    return true
end

--[[
Execute Yaw Rotation
Rotates the drone in place at current location
@param degrees Amount to rotate in degrees
@param rate Angular speed in degrees/second
@param direction Direction of rotation (1=clockwise, -1=counterclockwise)
]]
function execute_yaw_rotation(degrees, rate, direction)
    degrees = degrees or 360
    rate = rate or 20
    direction = direction or 1
    
    log_debug("Yaw rotation: degrees=" .. degrees .. ", rate=" .. rate .. "°/s")
    
    -- Need to be in guided mode
    if vehicle:get_mode() ~= 4 then
        vehicle:set_mode(4) -- Set to GUIDED mode
    end

    -- MAVLink command: MAV_CMD_CONDITION_YAW = 115
    -- param1: target angle in degrees
    -- param2: angular speed deg/s
    -- param3: direction: -1 = ccw, 1 = cw
    -- param4: relative=1 or absolute=0
    vehicle:command_long(115, 0, 0, degrees, rate, direction, 1, 0, 0, 0)
    
    return true
end

--[[
Execute Loiter
Makes the drone loiter at current position for specified time
@param duration Time to loiter in seconds
]]
function execute_loiter(duration)
    duration = duration or 10
    
    -- Limit loiter duration for safety
    if duration > CONFIG.MAX_LOITER_TIME then
        duration = CONFIG.MAX_LOITER_TIME
    end
    
    log_debug("Loitering for " .. duration .. " seconds")
    
    -- Switch to loiter mode
    if vehicle:get_mode() ~= 5 then
        vehicle:set_mode(5) -- Set to LOITER mode
        gcs:send_text(6, "Switching to LOITER for " .. duration .. "s")
    end
    
    -- Schedule return to AUTO mode after loiter time
    return_to_auto_after(duration)
    
    return true
end

--[[
Take Photo
Triggers camera to take a photo at current position
@param count Number of photos to take
@param interval Time between photos in seconds
]]
function execute_take_photo(count, interval)
    count = count or 1
    interval = interval or 1
    
    log_debug("Taking " .. count .. " photos")
    
    -- MAVLink command: MAV_CMD_DO_DIGICAM_CONTROL = 203
    -- Param1-5 are 0 for simple trigger
    -- Param6: 1 to trigger camera
    for i = 1, count do
        vehicle:command_long(203, 0, 0, 0, 0, 0, 1, 0, 0, 0)
        if i < count then
            gcs:send_text(6, "Photo " .. i .. " of " .. count)
            luautils.delay(interval * 1000)
        end
    end
    
    return true
end

--[[
Change Flight Speed
Adjusts the flight speed
@param speed New speed in m/s
]]
function set_flight_speed(speed)
    speed = speed or 5
    
    log_debug("Setting speed to " .. speed .. "m/s")
    
    -- MAVLink command: MAV_CMD_DO_CHANGE_SPEED = 178
    -- param1: speed type (0=airspeed, 1=ground speed)
    -- param2: speed in m/s
    -- param3: throttle as a percentage (-1 means no change)
    vehicle:command_long(178, 0, 0, 1, speed, -1, 0, 0, 0, 0)
    
    return true
end

--[[
Return to AUTO mode after specified delay
Helper function for routines that temporarily leave AUTO mode
@param delay_seconds Time in seconds before returning to AUTO
]]
function return_to_auto_after(delay_seconds)
    -- Create a timer to switch back to AUTO mode
    -- In a real implementation, you would use a more robust approach
    local start_time = millis()
    local function check_timer()
        if millis() - start_time >= delay_seconds * 1000 then
            vehicle:set_mode(10) -- 10 = AUTO mode
            gcs:send_text(6, "Returning to AUTO mode")
            return
        end
        return check_timer, 1000
    end
    
    -- Start the timer
    return check_timer, 1000
end

--[[
Execute actions based on waypoint number
Maps waypoint IDs to specific functions
@param wp_num Waypoint number from mission
]]
function execute_waypoint_action(wp_num)
    -- Map of waypoint numbers to actions
    local waypoint_actions = {
        [5] = function() execute_circle_maneuver(20, 1, true) end,
        [8] = function() execute_take_photo(3, 2) end,
        [10] = function() execute_yaw_rotation(360, 30, 1) end,
        [15] = function() set_flight_speed(3) end,
        [20] = function() execute_loiter(15) end
    }
    
    -- Execute the action if defined for this waypoint
    if waypoint_actions[wp_num] then
        log_debug("Executing action for waypoint " .. wp_num)
        waypoint_actions[wp_num]()
    end
end




--[[
Grid Survey Pattern
Performs a grid survey pattern at current location
@param width Width of survey area in meters
@param height Height of survey area in meters
@param spacing Distance between grid lines in meters
]]

function execute_grid_survey(width, height, spacing)
    width = width or 50
    height = height or 50
    spacing = spacing or 10
    
    log_debug("Starting grid survey: " .. width .. "x" .. height .. "m")
    
    -- Need to be in guided mode
    if vehicle:get_mode() ~= 4 then
        vehicle:set_mode(4) -- Set to GUIDED mode
    end
    
    -- Get current position as origin
    local origin = ahrs:get_position()
    if not origin then
        gcs:send_text(6, "Cannot get current position")
        return false
    end
    
    local heading = ahrs:get_yaw() -- Current vehicle heading
    local rows = math.floor(height / spacing)
    local current_altitude = origin:alt()
    
    -- Create grid pattern
    for i = 0, rows do
        local y_offset = i * spacing
        
        -- Calculate points for this row (alternating left-to-right and right-to-left)
        local start_x, end_x
        if i % 2 == 0 then
            start_x = 0
            end_x = width
        else
            start_x = width
            end_x = 0
        end
        
        -- Move to start of row
        local start_point = origin:offset_bearing_and_distance(heading, start_x, y_offset)
        vehicle:set_target_posvel_NED(start_point:lat(), start_point:lng(), current_altitude, 0, 0, 0)
        
        -- Wait until reaching the point (simplified)
        luautils.delay(5000) -- In practice, use position feedback instead
        
        -- Move to end of row
        local end_point = origin:offset_bearing_and_distance(heading, end_x, y_offset)
        vehicle:set_target_posvel_NED(end_point:lat(), end_point:lng(), current_altitude, 0, 0, 0)
        
        -- Take photos along the way
        execute_take_photo(3, 2)
        
        -- Wait until reaching the end point (simplified)
        luautils.delay(5000) -- In practice, use position feedback instead
    end
    
    -- Return to AUTO mode when finished
    vehicle:set_mode(10)
    return true
end