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
    -- Horizontal velocity
    local increment_horizontal = dt * speed_x * 10
    x = x + increment_horizontal

    -- Vertical: gravity and vertical velocity
    local gravity = 1
    speed_y = speed_y + gravity

    local increment_vertical = dt * speed_y * 10
    y = y + increment_vertical

    -- Horizontal rebounds (left and right)
    if x < x_min then
        x = x_min
        speed_x = speed_x * 0.6
        speed_x = -speed_x
    end
    if x > x_max then
        x = x_max
        speed_x = speed_x * 0.6
        speed_x = -speed_x
    end

    -- Vertical rebound (bottom rebound)
    if y > y_max then
        y = y_max
        speed_y = speed_y * 0.6
        speed_y = -speed_y

        -- Stop bouncing if speed is very low (resting on ground)
        if math.abs(speed_y) < 2 then
            speed_y = 0
        end
    end

    -- Ball rotation calculations
    local ball_angle = math.pi / 32
    local ball_rotation_speed_cumulative = 0

    -- Friction (bottom, horizontal)
    if y == y_max then
        speed_x = speed_x * attenuation
        ball_rotation_speed_cumulative = ball_rotation_speed_cumulative + ball_angle * speed_x

        -- Stop horizontal movement if speed is very low
        if math.abs(speed_x) < 0.1 then
            speed_x = 0
        end
    end

    -- Friction (left, vertical)
    if x == x_min then
        speed_y = speed_y * attenuation
        ball_rotation_speed_cumulative = ball_rotation_speed_cumulative + ball_angle * speed_y
    end

    -- Friction (right, vertical)
    if x == x_max then
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

    -- Draw walls with white color
    sdl.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)

    -- Left column
    drawRect(border, border, columns_width, columns_height)

    -- Right column
    drawRect(x_max + ball_radius, border, columns_width, columns_height)

    -- Horizontal floor
    drawRect(border, columns_height + border, x_max + ball_radius + columns_width - border, columns_width)

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
            -- start tracking mouse; coords read but not logged
            local mx = ffi.new("float[1]")
            local my = ffi.new("float[1]")
            sdl.SDL_GetMouseState(mx, my)
            mouse_down = true
            last_mouse_x = (tonumber(mx[0]) or 0.0)
            last_mouse_y = (tonumber(my[0]) or 0.0)
        elseif event.type == ffi.C.SDL_EVENT_MOUSE_BUTTON_UP then
            mouse_down = false
        elseif event.type == ffi.C.SDL_EVENT_MOUSE_MOTION then
            -- Use absolute coords and compute delta from last seen position.
            local mx = ffi.new("float[1]")
            local my = ffi.new("float[1]")
            sdl.SDL_GetMouseState(mx, my)
            local cur_mx = (tonumber(mx[0]) or 0.0)
            local cur_my = (tonumber(my[0]) or 0.0)
            local dx = cur_mx - last_mouse_x
            local dy = cur_my - last_mouse_y
            if mouse_down then
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
