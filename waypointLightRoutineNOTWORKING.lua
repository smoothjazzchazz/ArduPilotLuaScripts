--[[
Waypoint-Based Drone Lighting Control System
For use with ArduPilot and Pixhawk with LED controller or similar hardware
]]

-- Configuration for lighting system
local LIGHTING_CONFIG = {
    PWM_CHANNELS = {
        MAIN_LIGHT = 9,        -- Main light PWM channel
        RED_LIGHT = 10,        -- Red light PWM channel
        GREEN_LIGHT = 11,      -- Green light PWM channel
        BLUE_LIGHT = 12,       -- Blue light PWM channel
    },
    
    MAX_BRIGHTNESS = 1900,     -- Maximum PWM value for full brightness
    MIN_BRIGHTNESS = 1000,     -- Minimum PWM value (usually off)
    
    -- Pre-defined light patterns
    PATTERNS = {
        STROBE = 1,
        ALTERNATE = 2,
        PULSE = 3,
        RAINBOW = 4,
    },
    
    UPDATE_FREQ_HZ = 20,       -- Lighting update frequency
}

-- Global state variables
local current_pattern = nil
local pattern_running = false
local light_state = {
    main = 0,
    red = 0,
    green = 0,
    blue = 0
}

-- Initialize lighting system
function init()
    gcs:send_text(6, "LightControl: Initializing lighting system")
    -- Initialize all lights to off
    set_light_levels(0, 0, 0, 0)
    return update, 1000 / LIGHTING_CONFIG.UPDATE_FREQ_HZ
end

--[[
Set Light Levels
Controls brightness of all light channels
@param main_level Main light brightness (0-100%)
@param red_level Red light brightness (0-100%)
@param green_level Green light brightness (0-100%)
@param blue_level Blue light brightness (0-100%)
]]
function set_light_levels(main_level, red_level, green_level, blue_level)
    -- Store current state
    light_state.main = main_level
    light_state.red = red_level
    light_state.green = green_level
    light_state.blue = blue_level
    
    -- Map percentage values to PWM values
    local main_pwm = map_value(main_level, 0, 100, 
                              LIGHTING_CONFIG.MIN_BRIGHTNESS, 
                              LIGHTING_CONFIG.MAX_BRIGHTNESS)
    
    local red_pwm = map_value(red_level, 0, 100, 
                             LIGHTING_CONFIG.MIN_BRIGHTNESS, 
                             LIGHTING_CONFIG.MAX_BRIGHTNESS)
    
    local green_pwm = map_value(green_level, 0, 100, 
                               LIGHTING_CONFIG.MIN_BRIGHTNESS, 
                               LIGHTING_CONFIG.MAX_BRIGHTNESS)
    
    local blue_pwm = map_value(blue_level, 0, 100, 
                              LIGHTING_CONFIG.MIN_BRIGHTNESS, 
                              LIGHTING_CONFIG.MAX_BRIGHTNESS)
    
    -- Set PWM values
    SRV_Channels:set_output_pwm(LIGHTING_CONFIG.PWM_CHANNELS.MAIN_LIGHT, main_pwm)
    SRV_Channels:set_output_pwm(LIGHTING_CONFIG.PWM_CHANNELS.RED_LIGHT, red_pwm)
    SRV_Channels:set_output_pwm(LIGHTING_CONFIG.PWM_CHANNELS.GREEN_LIGHT, green_pwm)
    SRV_Channels:set_output_pwm(LIGHTING_CONFIG.PWM_CHANNELS.BLUE_LIGHT, blue_pwm)
    
    return true
end

--[[
Set RGB Color
Sets RGB lights to specified color
@param r Red component (0-100%)
@param g Green component (0-100%)
@param b Blue component (0-100%) 
@param brightness Overall brightness (0-100%)
]]
function set_rgb_color(r, g, b, brightness)
    brightness = brightness or 100
    
    -- Scale RGB values by brightness
    local red_level = (r * brightness) / 100
    local green_level = (g * brightness) / 100
    local blue_level = (b * brightness) / 100
    
    -- Apply to lights
    set_light_levels(0, red_level, green_level, blue_level)
    
    return true
end

--[[
Start Light Pattern
Begin a predefined lighting pattern
@param pattern_id Pattern ID from LIGHTING_CONFIG.PATTERNS
@param duration Duration in seconds (0 = indefinite)
@param speed Pattern speed (1-10)
]]
function start_light_pattern(pattern_id, duration, speed)
    -- Stop any currently running pattern
    stop_light_pattern()
    
    pattern_running = true
    current_pattern = pattern_id
    speed = speed or 5
    
    -- Pattern handler functions
    local pattern_handlers = {
        [LIGHTING_CONFIG.PATTERNS.STROBE] = function() 
            return run_strobe_pattern(speed) 
        end,
        [LIGHTING_CONFIG.PATTERNS.ALTERNATE] = function() 
            return run_alternate_pattern(speed) 
        end,
        [LIGHTING_CONFIG.PATTERNS.PULSE] = function() 
            return run_pulse_pattern(speed) 
        end,
        [LIGHTING_CONFIG.PATTERNS.RAINBOW] = function() 
            return run_rainbow_pattern(speed) 
        end
    }
    
    -- Start the selected pattern
    if pattern_handlers[pattern_id] then
        gcs:send_text(6, "LightControl: Starting pattern " .. pattern_id)
        
        -- If duration specified, schedule pattern stop
        if duration and duration > 0 then
            local function stop_pattern_later()
                stop_light_pattern()
            end
            -- Convert duration to milliseconds
            return pattern_handlers[pattern_id](), stop_pattern_later, duration * 1000
        else
            return pattern_handlers[pattern_id]()
        end
    else
        gcs:send_text(3, "LightControl: Invalid pattern ID")
        return false
    end
end

--[[
Stop Light Pattern
Stops currently running light pattern and turns off lights
]]
function stop_light_pattern()
    if pattern_running then
        pattern_running = false
        current_pattern = nil
        -- Turn off all lights
        set_light_levels(0, 0, 0, 0)
        gcs:send_text(6, "LightControl: Pattern stopped")
    end
    return true
end

-- Pattern implementation functions
function run_strobe_pattern(speed)
    -- Local variables for pattern state
    local state = false
    local delay = 1000 / speed
    
    -- Pattern update function
    local function pattern_update()
        if not pattern_running then return end
        
        -- Toggle strobe state
        state = not state
        if state then
            set_light_levels(100, 0, 0, 0) -- Main light on
        else
            set_light_levels(0, 0, 0, 0)   -- All lights off
        end
        
        -- Continue pattern
        return pattern_update, delay
    end
    
    return pattern_update, delay
end

function run_alternate_pattern(speed)
    -- Local variables for pattern state
    local state = 0  -- 0=red, 1=green, 2=blue
    local delay = 2000 / speed
    
    -- Pattern update function
    local function pattern_update()
        if not pattern_running then return end
        
        -- Cycle through colors
        if state == 0 then
            set_rgb_color(100, 0, 0, 100)    -- Red
            state = 1
        elseif state == 1 then
            set_rgb_color(0, 100, 0, 100)    -- Green
            state = 2
        else
            set_rgb_color(0, 0, 100, 100)    -- Blue
            state = 0
        end
        
        -- Continue pattern
        return pattern_update, delay
    end
    
    return pattern_update, delay
end

function run_pulse_pattern(speed)
    -- Local variables for pattern state
    local brightness = 0
    local increasing = true
    local step = 5 * (speed / 5)
    local delay = 100
    
    -- Pattern update function
    local function pattern_update()
        if not pattern_running then return end
        
        -- Update brightness
        if increasing then
            brightness = brightness + step
            if brightness >= 100 then
                brightness = 100
                increasing = false
            end
        else
            brightness = brightness - step
            if brightness <= 0 then
                brightness = 0
                increasing = true
            end
        end
        
        -- Apply current brightness to main light
        set_light_levels(brightness, 0, 0, 0)
        
        -- Continue pattern
        return pattern_update, delay
    end
    
    return pattern_update, delay
end

function run_rainbow_pattern(speed)
    -- Local variables for pattern state
    local hue = 0  -- 0-360 degrees
    local step = 5 * (speed / 5)
    local delay = 100
    
    -- Pattern update function
    local function pattern_update()
        if not pattern_running then return end
        
        -- Update hue (rotate through color wheel)
        hue = hue + step
        if hue >= 360 then hue = 0 end
        
        -- Convert HSV to RGB (simplified)
        local rgb = hsv_to_rgb(hue, 100, 100)
        set_rgb_color(rgb.r, rgb.g, rgb.b)
        
        -- Continue pattern
        return pattern_update, delay
    end
    
    return pattern_update, delay
end

--[[
Convert HSV to RGB
Utility function for color space conversion
@param h Hue (0-360 degrees)
@param s Saturation (0-100%)
@param v Value/Brightness (0-100%) 
@return Table with r,g,b components (0-100%)
]]
function hsv_to_rgb(h, s, v)
    -- Normalize values
    h = h % 360
    s = s / 100
    v = v / 100
    
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    
    local r, g, b
    if h < 60 then
        r, g, b = c, x, 0
    elseif h < 120 then
        r, g, b = x, c, 0
    elseif h < 180 then
        r, g, b = 0, c, x
    elseif h < 240 then
        r, g, b = 0, x, c
    elseif h < 300 then
        r, g, b = x, 0, c
    else
        r, g, b = c, 0, x
    end
    
    -- Convert to percentage (0-100)
    return {
        r = (r + m) * 100,
        g = (g + m) * 100,
        b = (b + m) * 100
    }
end

-- Utility function for value mapping
function map_value(x, in_min, in_max, out_min, out_max)
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min
end

-- Main update function
function update()
    -- Check if we're at a waypoint to trigger lighting actions
    local wp_num = get_current_waypoint()
    if wp_num and is_at_waypoint() then
        process_waypoint_lighting_actions(wp_num)
    end
    
    return update, 1000 / LIGHTING_CONFIG.UPDATE_FREQ_HZ
end

--[[
Process Lighting Actions at Waypoints
Define and execute lighting patterns at specific waypoints
@param wp_num Current waypoint number
]]
function process_waypoint_lighting_actions(wp_num)
    -- Map of waypoint numbers to lighting actions
    local lighting_actions = {
        [4] = function() 
            -- Land light on
            set_light_levels(100, 0, 0, 0)
        end,
        [6] = function() 
            -- Strobe pattern for 10 seconds
            start_light_pattern(LIGHTING_CONFIG.PATTERNS.STROBE, 10, 8)
        end,
        [9] = function() 
            -- Red warning light
            set_rgb_color(100, 0, 0)
        end,
        [12] = function() 
            -- Rainbow effect during a specific segment
            start_light_pattern(LIGHTING_CONFIG.PATTERNS.RAINBOW, 15, 3)
        end,
        [15] = function() 
            -- All lights off
            set_light_levels(0, 0, 0, 0)
        end
    }
    
    -- Execute lighting action if defined for this waypoint
    if lighting_actions[wp_num] then
        gcs:send_text(6, "LightControl: Action for waypoint " .. wp_num)
        lighting_actions[wp_num]()
    end
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