local ffi = require("ffi")

-- Configuration
local USE_TTF = true   -- Set to true to enable text rendering (requires SDL3_ttf)
local USE_IMAGE = true -- Set to true to enable background image (requires SDL3_image)

-- SDL3 FFI definitions
ffi.cdef [[
    // Basic SDL types
    typedef struct SDL_Window SDL_Window;
    typedef struct SDL_Renderer SDL_Renderer;
    typedef struct SDL_Texture SDL_Texture;
    typedef struct SDL_Surface SDL_Surface;

    typedef enum {
        SDL_PIXELFORMAT_UNKNOWN = 0,
        SDL_PIXELFORMAT_RGBA32 = 376840196
    } SDL_PixelFormat;

    typedef enum {
        SDL_TEXTUREACCESS_STATIC = 0,
        SDL_TEXTUREACCESS_STREAMING = 1
    } SDL_TextureAccess;

    typedef struct {
        float x, y, w, h;
    } SDL_FRect;

    typedef struct {
        int x, y, w, h;
    } SDL_Rect;

    typedef struct {
        float x, y;
    } SDL_FPoint;

    /* Use an opaque event buffer to avoid ABI/layout mismatches with SDL3's
       SDL_Event. Accessing nested union fields via FFI can cause memory
       corruption if the C layout differs. We'll only read the event type and
       query mouse/keyboard state via safe API calls. */
    typedef struct {
        unsigned int type;
        unsigned char data[128];
    } SDL_Event;

    // Event types
    static const unsigned int SDL_EVENT_QUIT = 0x100;
    static const unsigned int SDL_EVENT_KEY_DOWN = 0x300;
    static const unsigned int SDL_EVENT_KEY_UP = 0x301;
    static const unsigned int SDL_EVENT_MOUSE_BUTTON_DOWN = 0x401;
    static const unsigned int SDL_EVENT_MOUSE_BUTTON_UP = 0x402;
    static const unsigned int SDL_EVENT_MOUSE_MOTION = 0x400;

    // Key codes
    static const int SDLK_ESCAPE = 27;

    // Mouse buttons
    static const unsigned char SDL_BUTTON_LEFT = 1;

    // Function declarations
    int SDL_Init(unsigned int flags);
    void SDL_Quit(void);
    SDL_Window* SDL_CreateWindow(const char* title, int w, int h, unsigned int flags);
    void SDL_DestroyWindow(SDL_Window* window);
    SDL_Renderer* SDL_CreateRenderer(SDL_Window* window, const char* name);
    void SDL_DestroyRenderer(SDL_Renderer* renderer);

    int SDL_SetRenderDrawColor(SDL_Renderer* renderer, unsigned char r, unsigned char g, unsigned char b, unsigned char a);
    int SDL_RenderClear(SDL_Renderer* renderer);
    int SDL_RenderPresent(SDL_Renderer* renderer);
    int SDL_RenderFillRect(SDL_Renderer* renderer, const SDL_FRect* rect);
    int SDL_RenderTexture(SDL_Renderer* renderer, SDL_Texture* texture, const SDL_FRect* srcrect, const SDL_FRect* dstrect);
    int SDL_RenderTextureRotated(SDL_Renderer* renderer, SDL_Texture* texture, const SDL_FRect* srcrect, const SDL_FRect* dstrect, double angle, const SDL_FPoint* center, int flip);

    bool SDL_PollEvent(SDL_Event* event);
    void SDL_Delay(unsigned int ms);
    unsigned long SDL_GetTicks(void);

    // Image loading (assuming SDL_image is available)
    SDL_Surface* IMG_Load(const char* file);
    SDL_Surface* SDL_LoadBMP(const char* file);
    SDL_Texture* SDL_CreateTextureFromSurface(SDL_Renderer* renderer, SDL_Surface* surface);
    void SDL_DestroySurface(SDL_Surface* surface);
    void SDL_DestroyTexture(SDL_Texture* texture);

    // Mouse state (use float pointers per SDL3 API)
    unsigned int SDL_GetMouseState(float* x, float* y);
    unsigned int SDL_GetRelativeMouseState(float* x, float* y);
    // Keyboard state (returns pointer to an array indexed by SDL_Scancode)
    unsigned char* SDL_GetKeyboardState(int* numkeys);

    // Common scancode for Escape (SDL scancode values are stable across SDL2/3)
    static const int SDL_SCANCODE_ESCAPE = 41;

    // SDL_ttf types and functions
    typedef struct TTF_Font TTF_Font;

    typedef struct {
        unsigned char r, g, b, a;
    } SDL_Color;

    bool TTF_Init(void);
    void TTF_Quit(void);
    TTF_Font* TTF_OpenFont(const char* file, float ptsize);
    void TTF_CloseFont(TTF_Font* font);
    SDL_Surface* TTF_RenderText_Solid(TTF_Font* font, const char* text, size_t length, SDL_Color fg);
    SDL_Surface* TTF_RenderText_Blended(TTF_Font* font, const char* text, size_t length, SDL_Color fg);
]]

-- Load SDL3 library
local sdl = ffi.load("SDL3")
-- local img = ffi.load("SDL3_image")

-- Try to load SDL3_ttf (optional, controlled by USE_TTF flag)
local ttf = nil
local ttf_available = false
if USE_TTF then
    local ok, result = pcall(function() return ffi.load("SDL3_ttf") end)
    if ok then
        ttf = result
        ttf_available = true
        print("SDL3_ttf loaded successfully")
    else
        print("SDL3_ttf not found, text rendering will be disabled")
    end
else
    print("SDL3_ttf disabled by configuration")
end

-- Try to load SDL3_image (optional, controlled by USE_IMAGE flag)
local img = nil
local image_available = false
if USE_IMAGE then
    local ok, result = pcall(function() return ffi.load("SDL3_image") end)
    if ok then
        img = result
        image_available = true
        print("SDL3_image loaded successfully")
    else
        print("SDL3_image not found, background image will be disabled")
    end
else
    print("SDL3_image disabled by configuration")
end

-- Initialize SDL
local SDL_INIT_VIDEO = 0x00000020
sdl.SDL_Init(SDL_INIT_VIDEO)

-- Initialize SDL_ttf (only if available)
if ttf_available and ttf and not ttf.TTF_Init() then
    print("Warning: TTF_Init failed, text rendering will be disabled")
    ttf_available = false
end

-- Create window and renderer
local window = sdl.SDL_CreateWindow("Arcade Ball in SDL3", 800, 600, 0)
local renderer = sdl.SDL_CreateRenderer(window, nil)

-- Game state variables
-- Make the ball larger by default (1.0 = full size of the image)
local scale = 1.0
local ball_size = 128 -- Assume ball image is 128x128 since we can't load the actual image
local ball_radius = scale * ball_size / 2

-- Bounds
local x_min, x_max, y_max = 0, 400, 400
local border = 10
local columns_width = 30
local columns_height = y_max + ball_radius - border

x_min = border + columns_width + ball_radius

-- Ball physics
local x = 250
local y = 150
-- Increase initial horizontal speed so movement is noticeable on start
local speed_x = 50
local speed_y = 5
local ball_rotation = 0
local ball_rotation_speed = 0
local attenuation = 0.99

-- Input state
local keys_down = {}
local mouse_down = false
local last_mouse_x, last_mouse_y = 0.0, 0.0
local ball_grabbed = false
local grab_offset_x, grab_offset_y = 0, 0

-- Wall system: flexible table-based wall definitions
-- Each wall is a table with:
--   x, y: top-left corner position
--   w, h: width and height
--   type: "vertical", "horizontal", "platform" (one-way from top), or "tilted"
--   color: RGBA table (default white)
--   angle: rotation in radians (default 0, used for tilted walls)
local walls = {}

-- Add a wall to the walls table
local function addWall(x, y, w, h, wall_type, color, angle)
    table.insert(walls, {
        x = x,
        y = y,
        w = w,
        h = h,
        type = wall_type or "solid",
        color = color or { 255, 255, 255, 255 }, -- default white
        angle = angle or 0                       -- rotation in radians
    })
end

local function clearWalls()
    walls = {}
end

local function initializeWalls()
    clearWalls()

    -- Left column (vertical wall)
    addWall(border, border, columns_width, columns_height, "vertical")

    -- Right column (vertical wall)
    addWall(x_max + ball_radius, border, columns_width, columns_height, "vertical")

    -- Horizontal floor
    addWall(border, columns_height + border, x_max + ball_radius + columns_width - border, columns_width, "horizontal")

    -- Ceiling (top wall)
    addWall(border, border - columns_width, x_max + ball_radius + columns_width - border, columns_width, "horizontal",
        { 150, 150, 150, 255 })

    -- Mid-height horizontal wall (half-width, connected to left wall)
    local mid_height = border + columns_height / 2
    local half_width = (x_max - x_min) / 2
    addWall(border + columns_width, mid_height, half_width, 15, "horizontal", { 180, 180, 200, 255 })

    -- Tilted wall (angled ramp in bottom-right corner)
    local ramp_x = x_max - 80
    local ramp_y = columns_height + border - 60
    addWall(ramp_x, ramp_y, 100, 15, "tilted", { 200, 180, 150, 255 }, -math.pi / 4) -- -45 degrees

    -- Optional: Add ceiling (commented out by default)
    -- addWall(border, border - columns_width, x_max + ball_radius + columns_width - border, columns_width, "horizontal", {100, 100, 100, 255})

    -- Optional: Add platforms (commented out by default)
    -- addWall(150, 250, 100, 15, "platform", {200, 150, 100, 255})
    -- addWall(300, 180, 120, 15, "platform", {150, 200, 100, 255})
end

-- Font and text rendering
local font = nil
local function loadFont()
    if not ttf then
        return
    end

    local font_paths = {
        "assets/DejaVuSans.ttf"
    }

    for _, path in ipairs(font_paths) do
        font = ttf.TTF_OpenFont(path, 24)
        if font ~= ffi.NULL then
            print("Loaded font from:", path)
            return
        end
    end

    print("Warning: No font found, text rendering disabled")
    font = nil
end

local function renderText(text, x, y, r, g, b)
    if not ttf_available or not font or font == ffi.NULL then
        return
    end

    local color = ffi.new("SDL_Color", { r = r or 255, g = g or 255, b = b or 255, a = 255 })
    local surface = ttf and ttf.TTF_RenderText_Blended(font, text, #text, color) or nil

    if surface == nil or surface == ffi.NULL then
        return
    end

    local texture = sdl.SDL_CreateTextureFromSurface(renderer, surface)
    sdl.SDL_DestroySurface(surface)

    if texture == nil or texture == ffi.NULL then
        return
    end

    -- Use a reasonable text size (approximate)
    local text_w = #text * 14
    local text_h = 24

    -- Draw black background rectangle with some padding
    local padding = 4
    sdl.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)
    local bg_rect = ffi.new("SDL_FRect",
        { x = x - padding, y = y - padding, w = text_w + padding * 2, h = text_h + padding * 2 })
    sdl.SDL_RenderFillRect(renderer, bg_rect)

    -- Draw the text
    local dst = ffi.new("SDL_FRect", { x = x, y = y, w = text_w, h = text_h })
    sdl.SDL_RenderTexture(renderer, texture, ffi.NULL, dst)
    sdl.SDL_DestroyTexture(texture)
end

-- Create a simple ball texture (since we can't load the PNG in this example)
local ball_texture = nil
local function createBallTexture()
    -- Try to load a BMP named "ball-shiny.bmp" from common locations.
    local candidates = {
        "./ball-shiny.bmp",
        "ball-shiny.bmp",
        "assets/ball-shiny.bmp",
        "./assets/ball-shiny.bmp"
    }

    local surface = nil
    for _, path in ipairs(candidates) do
        surface = sdl.SDL_LoadBMP(path)
        if surface ~= nil and surface ~= ffi.NULL then
            print("Loaded ball bitmap from:", path)
            break
        end
    end

    if surface == nil or surface == ffi.NULL then
        print("Warning: ball-shiny.bmp not found; using procedural ball")
        ball_texture = nil
        return
    end

    ball_texture = sdl.SDL_CreateTextureFromSurface(renderer, surface)
    sdl.SDL_DestroySurface(surface)

    if ball_texture == nil or ball_texture == ffi.NULL then
        print("Warning: failed to create texture from surface; using procedural ball")
        ball_texture = nil
    end
end

-- Background image texture
local background_texture = nil
local function loadBackgroundImage()
    if not image_available or not img then
        return
    end

    local image_paths = {
        "assets/background.jpg",
        "assets/image.jpg"
    }

    for _, path in ipairs(image_paths) do
        local surface = img.IMG_Load(path)
        if surface ~= nil and surface ~= ffi.NULL then
            background_texture = sdl.SDL_CreateTextureFromSurface(renderer, surface)
            sdl.SDL_DestroySurface(surface)

            if background_texture ~= nil and background_texture ~= ffi.NULL then
                print("Loaded background image from:", path)
                return
            end
        end
    end

    print("Info: No background image found, using solid color")
end

-- Timing
local last_time = tonumber(sdl.SDL_GetTicks())
local frame_count = 0
local fps = 0
local fps_update_time = tonumber(sdl.SDL_GetTicks())

local function getDeltaTime()
    local current_time = tonumber(sdl.SDL_GetTicks())
    local dt = (current_time - last_time) / 1000.0 -- Convert to seconds (Lua number)
    last_time = current_time

    -- Update FPS counter
    frame_count = frame_count + 1
    if current_time - fps_update_time >= 1000 then
        fps = frame_count
        frame_count = 0
        fps_update_time = current_time
    end

    return dt
end

-- Lightweight runtime logger to observe motion without flooding output
local log_last = tonumber(sdl.SDL_GetTicks())
local log_interval_ms = 250

-- Drawing helper functions
local function drawRect(x, y, w, h)
    local rect = ffi.new("SDL_FRect", { x = x, y = y, w = w, h = h })
    sdl.SDL_RenderFillRect(renderer, rect)
end

-- Draw a single pixel with alpha blending (for antialiasing)
local function drawPixelAlpha(x, y, r, g, b, alpha)
    -- Clamp alpha to 0-255 range
    alpha = math.max(0, math.min(255, alpha))
    if alpha > 0 then
        sdl.SDL_SetRenderDrawColor(renderer, r, g, b, alpha)
        local rect = ffi.new("SDL_FRect", { x = x, y = y, w = 1, h = 1 })
        sdl.SDL_RenderFillRect(renderer, rect)
    end
end

local function drawBall(x, y, rotation)
    -- If we have a loaded texture, render it (rotated around its center).
    if ball_texture and ball_texture ~= ffi.NULL then
        local w = ball_size * scale
        local h = ball_size * scale
        local dst = ffi.new("SDL_FRect", { x = x, y = y, w = w, h = h })
        local center = ffi.new("SDL_FPoint", { x = w / 2, y = h / 2 })
        local angle_deg = rotation * 180.0 / math.pi
        sdl.SDL_RenderTextureRotated(renderer, ball_texture, ffi.NULL, dst, angle_deg, center, 0)
        return
    end

    -- Fallback: draw a filled circle approximation
    local radius = ball_radius
    sdl.SDL_SetRenderDrawColor(renderer, 255, 255, 0, 255) -- Yellow ball
    for dy = -radius, radius do
        for dx = -radius, radius do
            if dx * dx + dy * dy <= radius * radius then
                local rect = ffi.new("SDL_FRect", { x = x + dx, y = y + dy, w = 1, h = 1 })
                sdl.SDL_RenderFillRect(renderer, rect)
            end
        end
    end
end

-- Game update function
local function update(dt)
    -- Limit velocity to prevent tunneling
    local max_speed = 200
    local speed_mag = math.sqrt(speed_x * speed_x + speed_y * speed_y)
    if speed_mag > max_speed then
        local scale = max_speed / speed_mag
        speed_x = speed_x * scale
        speed_y = speed_y * scale
    end

    -- Vertical: gravity and vertical velocity
    local gravity = 1
    speed_y = speed_y + gravity

    -- Subdivide movement for high speeds to prevent tunneling
    -- Calculate total movement this frame
    local movement_x = dt * speed_x * 10
    local movement_y = dt * speed_y * 10
    local movement_dist = math.sqrt(movement_x * movement_x + movement_y * movement_y)

    -- Split movement into multiple substeps if moving fast
    -- Use ball radius * 0.5 as the maximum step size to ensure collision detection
    local substeps = math.max(1, math.ceil(movement_dist / (ball_radius * 0.5)))

    -- Limit substeps to prevent performance issues (5 substeps max)
    substeps = math.min(substeps, 5)

    local step_x = movement_x / substeps
    local step_y = movement_y / substeps
    -- Wall collision detection and physics - Box2D-style approach
    local ball_angle = math.pi / 32
    local ball_rotation_speed_cumulative = 0
    local touching_horizontal = false
    local touching_vertical_left = false
    local touching_vertical_right = false

    -- Helper: Check if circle intersects rectangle (AABB)
    -- Returns: collision_bool, closest_x, closest_y, dx, dy, distance
    local function circleRectCollision(cx, cy, radius, rx, ry, rw, rh)
        -- Find closest point on AABB (axis-aligned bounding box) to circle center
        -- Clamp circle center to rectangle bounds
        local closest_x = math.max(rx, math.min(cx, rx + rw))
        local closest_y = math.max(ry, math.min(cy, ry + rh))

        -- Vector from closest point to circle center
        local dx = cx - closest_x
        local dy = cy - closest_y
        local distance_sq = dx * dx + dy * dy

        -- Collision if distance is less than radius
        return distance_sq < (radius * radius), closest_x, closest_y, dx, dy, math.sqrt(distance_sq)
    end

    for step = 1, substeps do
        x = x + step_x
        y = y + step_y

        for _, wall in ipairs(walls) do
            local wall_left = wall.x
            local wall_right = wall.x + wall.w
            local wall_top = wall.y
            local wall_bottom = wall.y + wall.h

            local collides, closest_x, closest_y, dx, dy, dist

            -- Handle tilted walls differently using local space transformation
            if wall.type == "tilted" and wall.angle ~= 0 then
                -- Transform ball position to wall's local space (rotate around wall center)
                -- This allows us to do AABB collision detection on the rotated wall
                local wall_cx = wall.x + wall.w / 2
                local wall_cy = wall.y + wall.h / 2

                -- Apply inverse rotation (-angle) using rotation matrix
                local cos_a = math.cos(-wall.angle)
                local sin_a = math.sin(-wall.angle)
                local rel_x = x - wall_cx
                local rel_y = y - wall_cy
                local local_x = rel_x * cos_a - rel_y * sin_a + wall_cx
                local local_y = rel_x * sin_a + rel_y * cos_a + wall_cy

                -- Do collision detection in local space (wall is axis-aligned here)
                local local_collides, local_closest_x, local_closest_y, local_dx, local_dy, local_dist =
                    circleRectCollision(
                        local_x, local_y, ball_radius, wall.x, wall.y, wall.w, wall.h
                    )

                if local_collides then
                    -- Normalize collision vector in local space
                    if local_dist > 0.001 then
                        local_dx = local_dx / local_dist
                        local_dy = local_dy / local_dist
                    end

                    -- Transform collision normal back to world space using forward rotation
                    cos_a = math.cos(wall.angle)
                    sin_a = math.sin(wall.angle)
                    dx = local_dx * cos_a - local_dy * sin_a
                    dy = local_dx * sin_a + local_dy * cos_a

                    -- Push ball out along collision normal
                    local penetration = ball_radius - local_dist
                    x = x + dx * penetration
                    y = y + dy * penetration

                    -- Calculate velocity component along collision normal (dot product)
                    local vel_dot = speed_x * dx + speed_y * dy

                    if vel_dot < 0 then -- Moving into wall (negative dot product)
                        -- Reflect velocity along normal with damping (coefficient 1.2 = 20% bounce)
                        -- Formula: v' = v - (1 + restitution) * (v · n) * n
                        speed_x = speed_x - 1.2 * vel_dot * dx
                        speed_y = speed_y - 1.2 * vel_dot * dy

                        -- Calculate tangent vector (perpendicular to normal, for sliding)
                        local tx = -dy
                        local ty = dx

                        -- Velocity along tangent (parallel to surface, sliding direction)
                        local tangent_vel = speed_x * tx + speed_y * ty

                        -- Apply friction to tangent velocity (5% energy loss)
                        tangent_vel = tangent_vel * 0.95

                        -- Add rotation based on tangent velocity (ball rolling on slope)
                        ball_rotation_speed_cumulative = ball_rotation_speed_cumulative + tangent_vel * ball_angle

                        -- Check if resting on surface (low normal velocity)
                        if math.abs(vel_dot) < 5 then
                            touching_horizontal = true
                        end
                    end
                end
            else
                -- Axis-aligned wall collision
                collides, closest_x, closest_y, dx, dy, dist = circleRectCollision(
                    x, y, ball_radius, wall_left, wall_top, wall.w, wall.h
                )

                if collides then
                    local penetration = ball_radius - dist

                    -- Normalize collision vector to get collision normal
                    if dist > 0.001 then
                        dx = dx / dist
                        dy = dy / dist
                    else
                        -- Edge case: ball center is inside rectangle
                        -- Push out in direction of minimum separation
                        local push_left = x - wall_left
                        local push_right = wall_right - x
                        local push_up = y - wall_top
                        local push_down = wall_bottom - y

                        -- Find which edge is closest and use that as collision normal
                        local min_push = math.min(push_left, push_right, push_up, push_down)
                        if min_push == push_left then
                            dx, dy = -1, 0 -- Push left
                        elseif min_push == push_right then
                            dx, dy = 1, 0  -- Push right
                        elseif min_push == push_up then
                            dx, dy = 0, -1 -- Push up
                        else
                            dx, dy = 0, 1  -- Push down
                        end
                        penetration = ball_radius
                    end

                    -- Separate ball from wall
                    x = x + dx * penetration
                    y = y + dy * penetration

                    -- Determine collision axis and apply response
                    local is_vertical_collision = math.abs(dy) > math.abs(dx)

                    if is_vertical_collision then
                        -- Vertical collision (floor/ceiling)
                        if wall.type == "platform" and dy < 0 then
                            -- Platform with one-way collision: only collide from above (dy > 0)
                            -- Ball is coming from below (dy < 0), so skip this collision
                        elseif wall.type == "horizontal" or wall.type == "platform" then
                            -- Bounce with damping (60% energy retention)
                            local vel_dot = speed_x * dx + speed_y * dy
                            if vel_dot < 0 then -- Moving into wall
                                speed_y = -speed_y * 0.6
                                touching_horizontal = true

                                -- Stop vertical bouncing if speed is very low (resting)
                                if math.abs(speed_y) < 2 then
                                    speed_y = 0
                                end
                            end
                        end
                    else
                        -- Horizontal collision (left/right walls)
                        if wall.type == "vertical" or wall.type == "horizontal" then
                            local vel_dot = speed_x * dx + speed_y * dy
                            if vel_dot < 0 then -- Moving into wall
                                speed_x = -speed_x * 0.6

                                if dx > 0 then
                                    touching_vertical_right = true
                                else
                                    touching_vertical_left = true
                                end
                            end
                        end
                    end
                end
            end
        end -- end of wall loop
    end     -- end of substep loop

    -- Apply friction based on wall contact
    if touching_horizontal then
        speed_x = speed_x * attenuation
        ball_rotation_speed_cumulative = ball_rotation_speed_cumulative + ball_angle * speed_x

        if math.abs(speed_x) < 0.1 then
            speed_x = 0
        end
    end

    if touching_vertical_left then
        speed_y = speed_y * attenuation
        ball_rotation_speed_cumulative = ball_rotation_speed_cumulative + ball_angle * speed_y
    end

    if touching_vertical_right then
        speed_y = speed_y * attenuation
        ball_rotation_speed_cumulative = ball_rotation_speed_cumulative - ball_angle * speed_y
    end

    -- Ball rotation
    if ball_rotation_speed_cumulative ~= 0 then
        ball_rotation_speed = ball_rotation_speed_cumulative
    end
    ball_rotation_speed = ball_rotation_speed * attenuation
    ball_rotation = ball_rotation + dt * ball_rotation_speed
end

-- Game draw function
local function draw()
    -- Clear screen with black background
    sdl.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)
    sdl.SDL_RenderClear(renderer)

    -- Draw background image if available (semi-transparent overlay)
    if background_texture and background_texture ~= ffi.NULL then
        local bg_rect = ffi.new("SDL_FRect", { x = 0, y = 0, w = 800, h = 600 })
        sdl.SDL_RenderTexture(renderer, background_texture, ffi.NULL, bg_rect)
    end

    -- Draw ball
    drawBall(x - ball_radius, y - ball_radius, ball_rotation)

    -- Helper function: Draw an antialiased ring using Xiaolin Wu-style algorithm
    local function drawRingAntialiased(center_x, center_y, inner_radius, outer_radius, r, g, b, a)
        -- Bounding box for the ring
        local min_y = math.floor(center_y - outer_radius - 1)
        local max_y = math.ceil(center_y + outer_radius + 1)

        -- For each scanline in the bounding box
        for scan_y = min_y, max_y do
            local dy = scan_y - center_y
            local dy_sq = dy * dy

            -- Calculate intersection points with outer and inner circles
            local outer_radius_sq = outer_radius * outer_radius
            local inner_radius_sq = inner_radius * inner_radius

            if dy_sq <= outer_radius_sq then
                -- Scanline intersects outer circle
                local outer_x_offset = math.sqrt(outer_radius_sq - dy_sq)
                local x_left_outer = center_x - outer_x_offset
                local x_right_outer = center_x + outer_x_offset

                if dy_sq <= inner_radius_sq then
                    -- Scanline also intersects inner circle (ring region)
                    local inner_x_offset = math.sqrt(inner_radius_sq - dy_sq)
                    local x_left_inner = center_x - inner_x_offset
                    local x_right_inner = center_x + inner_x_offset

                    -- LEFT SEGMENT: from outer left edge to inner left edge
                    local left_start = math.floor(x_left_outer)
                    local left_end = math.floor(x_left_inner)

                    -- Outer left edge pixel - fractional coverage (pixel partially covered)
                    local outer_left_frac = 1 - (x_left_outer - left_start)
                    if outer_left_frac > 0.01 then
                        drawPixelAlpha(left_start, scan_y, r, g, b, a * outer_left_frac)
                    end

                    -- Solid pixels in left segment
                    sdl.SDL_SetRenderDrawColor(renderer, r, g, b, a)
                    if left_end > left_start then
                        drawRect(left_start + 1, scan_y, left_end - left_start, 1)
                    end

                    -- Inner left edge pixel - fractional coverage
                    local inner_left_frac = x_left_inner - left_end
                    if inner_left_frac > 0.01 then
                        drawPixelAlpha(left_end + 1, scan_y, r, g, b, a * inner_left_frac)
                    end

                    -- RIGHT SEGMENT: from inner right edge to outer right edge
                    local right_start = math.floor(x_right_inner)
                    local right_end = math.floor(x_right_outer)

                    -- Inner right edge pixel - fractional coverage
                    local inner_right_frac = 1 - (x_right_inner - right_start)
                    if inner_right_frac > 0.01 then
                        drawPixelAlpha(right_start, scan_y, r, g, b, a * inner_right_frac)
                    end

                    -- Solid pixels in right segment
                    sdl.SDL_SetRenderDrawColor(renderer, r, g, b, a)
                    if right_end > right_start then
                        drawRect(right_start + 1, scan_y, right_end - right_start, 1)
                    end

                    -- Outer right edge pixel - fractional coverage
                    local outer_right_frac = x_right_outer - right_end
                    if outer_right_frac > 0.01 then
                        drawPixelAlpha(right_end + 1, scan_y, r, g, b, a * outer_right_frac)
                    end
                else
                    -- Scanline is outside inner circle, draw full width with antialiasing
                    local start_x = math.floor(x_left_outer)
                    local end_x = math.floor(x_right_outer)

                    -- Left edge antialiasing
                    local left_frac = 1 - (x_left_outer - start_x)
                    if left_frac > 0.01 then
                        drawPixelAlpha(start_x, scan_y, r, g, b, a * left_frac)
                    end

                    -- Solid middle
                    sdl.SDL_SetRenderDrawColor(renderer, r, g, b, a)
                    if end_x > start_x then
                        drawRect(start_x + 1, scan_y, end_x - start_x, 1)
                    end

                    -- Right edge antialiasing
                    local right_frac = x_right_outer - end_x
                    if right_frac > 0.01 then
                        drawPixelAlpha(end_x + 1, scan_y, r, g, b, a * right_frac)
                    end
                end
            end
        end
    end

    -- Visual feedback for ball grab state
    if ball_grabbed then
        -- Draw bright ring around grabbed ball with antialiasing
        local inner_radius = ball_radius + 5
        local outer_radius = ball_radius + 8
        drawRingAntialiased(x, y, inner_radius, outer_radius, 255, 220, 0, 255)
    else
        -- Show hover hint when mouse is near ball
        local mx = ffi.new("float[1]")
        local my = ffi.new("float[1]")
        sdl.SDL_GetMouseState(mx, my)
        local cur_mx = (tonumber(mx[0]) or 0.0)
        local cur_my = (tonumber(my[0]) or 0.0)
        local dx = cur_mx - x
        local dy = cur_my - y
        local dist_sq = dx * dx + dy * dy
        local hover_radius = ball_radius * 1.5

        if dist_sq <= (hover_radius * hover_radius) then
            -- Draw subtle ring for hover state with antialiasing
            local inner_radius = ball_radius + 4
            local outer_radius = ball_radius + 6
            drawRingAntialiased(x, y, inner_radius, outer_radius, 200, 200, 200, 255)
        end
    end

    -- Draw all walls dynamically
    for _, wall in ipairs(walls) do
        local c = wall.color
        sdl.SDL_SetRenderDrawColor(renderer, c[1], c[2], c[3], c[4])

        if wall.type == "tilted" and wall.angle ~= 0 then
            -- Draw rotated rectangle with antialiased edges using scanline algorithm
            local cx = wall.x + wall.w / 2
            local cy = wall.y + wall.h / 2
            local cos_a = math.cos(wall.angle)
            local sin_a = math.sin(wall.angle)

            -- Calculate all 4 corners in world space using rotation matrix
            -- Rotation matrix: [cos -sin] [local_x]   [world_x]
            --                  [sin  cos] [local_y] = [world_y]
            local hw = wall.w / 2
            local hh = wall.h / 2
            local corners = {
                { x = -hw * cos_a - (-hh) * sin_a + cx, y = -hw * sin_a + (-hh) * cos_a + cy }, -- Top-left
                { x = hw * cos_a - (-hh) * sin_a + cx,  y = hw * sin_a + (-hh) * cos_a + cy },  -- Top-right
                { x = hw * cos_a - hh * sin_a + cx,     y = hw * sin_a + hh * cos_a + cy },     -- Bottom-right
                { x = -hw * cos_a - hh * sin_a + cx,    y = -hw * sin_a + hh * cos_a + cy }     -- Bottom-left
            }

            -- Find Y-axis bounding box for scanline iteration
            local min_y = math.min(corners[1].y, corners[2].y, corners[3].y, corners[4].y)
            local max_y = math.max(corners[1].y, corners[2].y, corners[3].y, corners[4].y)

            -- Scanline fill algorithm with antialiasing: for each horizontal line, find edge intersections
            for scan_y = math.floor(min_y) - 1, math.ceil(max_y) + 1 do
                local intersections = {}

                -- Find intersections of horizontal scanline with all 4 edges of polygon
                for i = 1, 4 do
                    local j = (i % 4) + 1 -- Next corner (wraps around)
                    local y1, y2 = corners[i].y, corners[j].y
                    local x1, x2 = corners[i].x, corners[j].x

                    -- Check if scanline crosses this edge (edge straddles the scanline)
                    if (y1 <= scan_y and y2 > scan_y) or (y2 <= scan_y and y1 > scan_y) then
                        -- Linear interpolation to find x coordinate at scanline intersection
                        local t = (scan_y - y1) / (y2 - y1)
                        local intersect_x = x1 + t * (x2 - x1)
                        table.insert(intersections, intersect_x)
                    end
                end

                -- Sort intersections left to right and draw antialiased horizontal line segments
                table.sort(intersections)
                for i = 1, #intersections - 1, 2 do
                    local x_left = intersections[i]
                    local x_right = intersections[i + 1]

                    local x_start = math.floor(x_left)
                    local x_end = math.floor(x_right)

                    -- Antialiased left edge pixel
                    local left_frac = x_left - x_start
                    if left_frac > 0.01 then
                        drawPixelAlpha(x_start, scan_y, c[1], c[2], c[3], c[4] * (1 - left_frac))
                    end

                    -- Solid middle segment
                    sdl.SDL_SetRenderDrawColor(renderer, c[1], c[2], c[3], c[4])
                    if x_end > x_start then
                        drawRect(x_start + 1, scan_y, x_end - x_start, 1)
                    end

                    -- Antialiased right edge pixel
                    local right_frac = 1 - (x_right - x_end)
                    if right_frac > 0.01 then
                        drawPixelAlpha(x_end + 1, scan_y, c[1], c[2], c[3], c[4] * right_frac)
                    end
                end
            end
        else
            drawRect(wall.x, wall.y, wall.w, wall.h)
        end
    end

    -- Draw FPS counter and game info (centered between walls)
    local text_x = border + columns_width + (x_max - x_min) / 2 - 100
    renderText("FPS: " .. fps, text_x, 10, 128, 128, 128)
    renderText("Speed: " .. string.format("%.1f, %.1f", speed_x, speed_y), text_x, 40, 128, 128, 128)
    renderText("Pos: " .. string.format("%.0f, %.0f", x, y), text_x, 70, 128, 128, 128)

    -- Present the rendered frame
    sdl.SDL_RenderPresent(renderer)
end

-- Main game loop
local running = true
local event = ffi.new("SDL_Event")

print("Starting SDL3 Ball Game...")

-- Load font for text rendering
loadFont()

-- Attempt to load ball texture from disk (falls back to procedural drawing)
createBallTexture()

-- Load background image if SDL3_image is available
loadBackgroundImage()

-- Initialize the wall system
initializeWalls()
print("Initialized " .. #walls .. " walls")

-- Startup timing: record start ticks and give a short grace period where ESC won't quit
local start_ticks = tonumber(sdl.SDL_GetTicks())
local startup_grace_ms = 500 -- milliseconds

-- Ensure there is visible motion at startup
if math.abs(speed_x) + math.abs(speed_y) < 1e-6 then
    speed_x = 50
    speed_y = 5
end

-- Initialize previous ESC state to avoid exiting immediately if ESC is already down
local nk_init = ffi.new("int[1]")
local keys_init = sdl.SDL_GetKeyboardState(nk_init)
local prev_escape_pressed = false
if keys_init ~= nil and keys_init[ffi.C.SDL_SCANCODE_ESCAPE] == 1 then
    prev_escape_pressed = true
else
    prev_escape_pressed = false
end

-- Initialize last mouse position to current mouse state to avoid a large first-delta
do
    local mx = ffi.new("float[1]")
    local my = ffi.new("float[1]")
    sdl.SDL_GetMouseState(mx, my)
    last_mouse_x = (tonumber(mx[0]) or 0.0)
    last_mouse_y = (tonumber(my[0]) or 0.0)
end

while running do
    -- Handle events
    while sdl.SDL_PollEvent(event) do
        -- (logging suppressed to reduce noise)
        if event.type == ffi.C.SDL_EVENT_QUIT then
            print("SDL_EVENT_QUIT received, exiting main loop.")
            running = false
        elseif event.type == ffi.C.SDL_EVENT_KEY_DOWN then
            -- Key down (details available via SDL_GetKeyboardState)
        elseif event.type == ffi.C.SDL_EVENT_KEY_UP then
            -- Key up (details available via SDL_GetKeyboardState)
        elseif event.type == ffi.C.SDL_EVENT_MOUSE_BUTTON_DOWN then
            local mx = ffi.new("float[1]")
            local my = ffi.new("float[1]")
            sdl.SDL_GetMouseState(mx, my)
            local cur_mx = (tonumber(mx[0]) or 0.0)
            local cur_my = (tonumber(my[0]) or 0.0)

            -- Check if clicking near the ball (with generous grab radius)
            local dx = cur_mx - x
            local dy = cur_my - y
            local dist_sq = dx * dx + dy * dy
            local grab_radius = ball_radius * 1.5 -- 50% larger grab area

            if dist_sq <= (grab_radius * grab_radius) then
                ball_grabbed = true
                grab_offset_x = x - cur_mx
                grab_offset_y = y - cur_my
                -- Don't reset velocity immediately for smoother feel
            end

            mouse_down = true
            last_mouse_x = cur_mx
            last_mouse_y = cur_my
        elseif event.type == ffi.C.SDL_EVENT_MOUSE_BUTTON_UP then
            mouse_down = false

            if ball_grabbed then
                -- Apply current velocity as throw
                ball_grabbed = false
            end
        elseif event.type == ffi.C.SDL_EVENT_MOUSE_MOTION then
            local mx = ffi.new("float[1]")
            local my = ffi.new("float[1]")
            sdl.SDL_GetMouseState(mx, my)
            local cur_mx = (tonumber(mx[0]) or 0.0)
            local cur_my = (tonumber(my[0]) or 0.0)
            local dx = cur_mx - last_mouse_x
            local dy = cur_my - last_mouse_y

            if ball_grabbed and mouse_down then
                -- Direct ball positioning with offset
                local target_x = cur_mx + grab_offset_x
                local target_y = cur_my + grab_offset_y

                -- Set velocity based on movement for smooth dragging
                speed_x = (target_x - x) * 5
                speed_y = (target_y - y) * 5
            elseif mouse_down then
                -- Apply force when dragging but not grabbed
                speed_x = speed_x + dx / 2
                speed_y = speed_y + dy / 2
            end

            last_mouse_x = cur_mx
            last_mouse_y = cur_my
        else
            -- other events suppressed
        end
    end

    -- Update game logic
    local dt = getDeltaTime()
    update(dt)

    -- periodic debug logging suppressed

    -- Poll keyboard state and use edge detection for ESC so an already-pressed
    -- ESC at startup doesn't immediately quit.
    local nk = ffi.new("int[1]")
    local keys = sdl.SDL_GetKeyboardState(nk)
    local esc_now = false
    if keys ~= nil and keys[ffi.C.SDL_SCANCODE_ESCAPE] == 1 then
        esc_now = true
    end
    -- Ignore ESC presses during the startup grace period
    local now_ticks = sdl.SDL_GetTicks()
    if now_ticks - start_ticks >= startup_grace_ms then
        if esc_now and not prev_escape_pressed then
            print("ESC pressed, exiting main loop.")
            running = false
        end
    end
    prev_escape_pressed = esc_now

    -- Draw everything
    draw()

    -- Small delay to limit frame rate
    sdl.SDL_Delay(16) -- ~60 FPS
end

-- Cleanup
if ball_texture and ball_texture ~= ffi.NULL then
    sdl.SDL_DestroyTexture(ball_texture)
end
if background_texture and background_texture ~= ffi.NULL then
    sdl.SDL_DestroyTexture(background_texture)
end
if ttf_available and ttf then
    if font and font ~= ffi.NULL then
        ttf.TTF_CloseFont(font)
    end
    ttf.TTF_Quit()
end
sdl.SDL_DestroyRenderer(renderer)
sdl.SDL_DestroyWindow(window)
sdl.SDL_Quit()

print("Game finished successfully!")
