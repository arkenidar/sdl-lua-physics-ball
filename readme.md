# 🎮 SDL Lua Physics Ball

An interactive physics simulation game built with **LuaJIT** and **SDL3**, featuring a bouncing ball with realistic physics, tilted walls, and Box2D-style collision detection.

## ✨ Features

- **Realistic Physics Engine** - Box2D-style collision detection with proper separation and velocity-based response
- **Flexible Wall System** - Support for vertical, horizontal, platform (one-way), and tilted walls
- **Interactive Ball Control** - Click and drag to grab and throw the ball with visual feedback
- **Tilted Wall Support** - Rotated walls with proper collision normals and ball rotation on slopes
- **Anti-Tunneling** - Velocity limiting and substep integration prevent ball from phasing through walls
- **Scanline Rendering** - Efficient polygon fill algorithm for drawing rotated rectangles
- **Visual Feedback** - Yellow ring when ball is grabbed, gray ring on hover
- **Real-time Stats** - FPS counter, speed, and position display

## 📋 Requirements

| Component | Required | Description |
|-----------|----------|-------------|
| **LuaJIT** | ✅ Yes | Just-In-Time compiler for Lua with FFI support |
| **SDL3** | ✅ Yes | Simple DirectMedia Layer 3 for graphics and input |
| **SDL3_ttf** | ⚠️ Optional | TrueType font rendering (disable with USE_TTF = false) |
| **SDL3_image** | ⚠️ Optional | Image loading for backgrounds (disable with USE_IMAGE = false) |

## 🔧 Installation

### Debian 13

```bash
# Install all dependencies in one command
sudo apt install luajit libsdl3-dev libsdl3-ttf-dev libsdl3-image-dev
```

### Other Linux (Ubuntu/Debian-based)

```bash
# Install LuaJIT
sudo apt-get install luajit

# Install SDL3 libraries (if available in your distribution)
sudo apt-get install libsdl3-dev libsdl3-ttf-dev libsdl3-image-dev

# If SDL3 is not available, you may need to build from source
# Check SDL website for latest builds: https://github.com/libsdl-org/SDL
```

### Windows

**Note:** The project includes batch files for Windows:
- `app-mconsole.cmd` - Run with console window
- `app-mwindows.cmd` - Run without console window

See `windows-os/bundle--mingw-copy-here--textual-informations.txt` for Windows-specific setup instructions.

## 🚀 How to Run

```bash
luajit app.lua
```

Or on Windows, double-click one of the batch files:
- `app-mconsole.cmd` - Shows debug output in console
- `app-mwindows.cmd` - Clean window without console

## 🎮 Controls

| Action | Control | Description |
|--------|---------|-------------|
| **Grab Ball** | Left Click (near ball) | Click within 1.5× ball radius to grab |
| **Drag Ball** | Hold & Drag | Move mouse while holding to drag ball |
| **Throw Ball** | Release Click | Release to throw with current velocity |
| **Apply Force** | Click & Drag (away from ball) | Push ball without grabbing it |
| **Exit** | ESC | Close the game |

### Visual Indicators

- **Yellow Ring** - Ball is currently grabbed
- **Gray Ring** - Mouse is hovering near ball (within grab range)

## 🏗️ Project Structure

```
sdl-lua-physics-ball/
├── app.lua                    # Main game file (950+ lines)
├── readme.html                # HTML documentation
├── readme.md                  # This file
├── app-mconsole.cmd           # Windows launcher (with console)
├── app-mwindows.cmd           # Windows launcher (no console)
├── assets/                    # Optional assets folder
│   ├── ball-shiny.bmp         # Ball texture (optional)
│   ├── DejaVuSans.ttf         # Font for text rendering (optional)
│   └── background.jpg         # Background image (optional)
└── windows-os/                # Windows-specific files
    ├── bundle--mingw-copy-here.cmd
    ├── bundle--mingw-copy-here--textual-informations.txt
    ├── copy-dlls.sh
    └── deplist.py
```

## ⚙️ Configuration

Edit the configuration flags at the top of `app.lua`:

```lua
-- Configuration
local USE_TTF = true   -- Set to false to disable text rendering
local USE_IMAGE = true -- Set to false to disable background image
```

## 🔬 Technical Details

### Physics Engine

- **Gravity:** 1 unit per frame
- **Friction:** 0.99 attenuation coefficient (1% energy loss per frame)
- **Restitution:** 0.6 (60% energy retention on bounce)
- **Max Speed:** 200 units/second (prevents tunneling)
- **Substeps:** Up to 5 substeps per frame based on velocity

### Wall Types

| Type | Behavior |
|------|----------|
| `vertical` | Standard wall for left/right boundaries |
| `horizontal` | Standard wall for floor/ceiling |
| `platform` | One-way collision from above (ball can pass through from below) |
| `tilted` | Rotated wall with angle in radians, ball rolls realistically on slopes |

### Collision Detection Algorithm

**Box2D-Style Approach:**

1. **Circle-to-Rectangle AABB:** Find closest point on rectangle to circle center
2. **Separation First:** Push ball out along collision normal by penetration depth
3. **Velocity Reflection:** Project velocity onto normal and reflect with damping
4. **Substep Integration:** Divide movement into smaller steps to prevent tunneling

### Tilted Wall Physics

Tilted walls use **local space transformation**:

1. Transform ball position to wall's local space using inverse rotation matrix
2. Perform AABB collision detection in local space
3. Transform collision normal back to world space using forward rotation
4. Calculate tangent velocity for realistic rolling behavior

### Rendering

- **Axis-Aligned Walls:** Direct SDL_RenderFillRect calls
- **Tilted Walls:** Scanline algorithm with edge intersection
  - Calculate 4 corners using rotation matrix
  - For each scanline, find edge intersections
  - Draw horizontal line segments between intersection pairs
- **Ball:** Rotated texture (if available) or procedural circle fill

## 🛠️ Customization

### Adding New Walls

Edit the `initializeWalls()` function in `app.lua`:

```lua
-- Add a horizontal platform
addWall(150, 250, 100, 15, "platform", {200, 150, 100, 255})

-- Add a tilted ramp at 30 degrees
addWall(200, 300, 120, 20, "tilted", {180, 200, 150, 255}, math.pi/6)
```

### Wall Function Signature

```lua
addWall(x, y, width, height, type, color, angle)
-- x, y: Top-left corner position
-- width, height: Wall dimensions
-- type: "vertical", "horizontal", "platform", or "tilted"
-- color: {R, G, B, A} table (optional, defaults to white)
-- angle: Rotation in radians (optional, defaults to 0)
```

### Modifying Physics Parameters

```lua
-- In update() function:
local gravity = 1              -- Change gravity strength
local attenuation = 0.99       -- Friction coefficient
local max_speed = 200          -- Maximum velocity

-- In collision response:
speed_y = -speed_y * 0.6       -- Change to 0.8 for bouncier
speed_x = speed_x - 1.2 * ...  -- Change 1.2 to adjust restitution
```

## 📝 Code Organization

The `app.lua` file is organized into these sections:

1. **FFI Definitions** - SDL3 type and function declarations
2. **Library Loading** - Load SDL3, SDL3_ttf, SDL3_image
3. **Initialization** - Create window, renderer, initialize SDL
4. **Game State** - Variables for ball physics, walls, input
5. **Wall System** - addWall(), clearWalls(), initializeWalls()
6. **Asset Loading** - Font, textures, images
7. **Physics Update** - Collision detection and response
8. **Rendering** - Draw ball, walls, UI elements
9. **Main Loop** - Event handling, update, draw cycle
10. **Cleanup** - Resource deallocation

## 🐛 Known Issues

- **SDL3 Availability:** SDL3 is currently in development. You may need to build it from source.
- **Asset Loading:** The game searches multiple paths for assets. Ensure they're in the correct location.
- **Performance:** Substep integration is limited to 5 steps. Extremely high velocities may still cause occasional tunneling.

## 🚧 Future Improvements

- Multiple balls with ball-to-ball collision
- Level editor / save/load level layouts
- Different ball materials (bouncy, sticky, heavy)
- Particle effects for collisions
- Sound effects
- More wall shapes (circles, polygons)
- Joints and constraints (like Box2D)
- Performance optimizations (spatial partitioning)

## 📚 Resources

- [SDL3 Documentation](https://wiki.libsdl.org/SDL3/FrontPage)
- [LuaJIT FFI Documentation](https://luajit.org/ext_ffi.html)
- [Box2D Physics Documentation](https://box2d.org/documentation/)
- [Scanline Rendering Algorithm](https://en.wikipedia.org/wiki/Scanline_rendering)

## 👤 Author

**arkenidar**

Repository: [github.com/arkenidar/sdl-lua-physics-ball](https://github.com/arkenidar/sdl-lua-physics-ball)

## 📄 License

This project uses open-source libraries:

- **SDL3:** zlib license
- **LuaJIT:** MIT license

---

*Last updated: November 20, 2025*
