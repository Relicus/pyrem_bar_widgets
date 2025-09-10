# Build Time Estimator v2 for Beyond All Reason

[![License: GPL v2](https://img.shields.io/badge/License-GPL%20v2-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)
[![BAR Compatible](https://img.shields.io/badge/BAR-Compatible-green.svg)](https://www.beyondallreason.info/)
[![Version](https://img.shields.io/badge/Version-2.0-brightgreen.svg)](https://github.com/pyrem/bar-widgets)

A sophisticated build time estimation widget for [Beyond All Reason](https://www.beyondallreason.info/) that provides real-time, economy-aware predictions for unit construction times.

## 🎯 Features

### Core Functionality
- **⏱️ Real-Time Build Time Estimates** - Calculates accurate construction times based on available builders
- **💰 Economy-Aware Predictions** - Accounts for metal/energy constraints and storage levels
- **🔨 Smart Builder Detection** - Automatically detects builders in range and selected units
- **🏗️ Nano Turret Support** - Includes nano turrets in build power calculations
- **👁️ Spectator Mode** - Fully functional in spectator mode for casting and observing

### Visual Indicators
- **🟢 Green** - Economy can fully support construction
- **🟡 Yellow** - Partial economy support (60-99% efficiency)
- **🔴 Red** - Economy bottleneck detected
- **📊 Resource Display** - Shows metal/energy consumption rates and storage levels

### Interactive Features
- **Hold `backtick` (`)** - View only idle builders
- **Hover over constructions** - See completion time for units being built
- **Dynamic updates** - Refreshes calculations as economy changes

## 📦 Installation

### Method 1: Direct Download
1. Download `build_time_estimator_v2.lua`
2. Place in your BAR widgets folder:
   - **Windows**: `C:\Users\[YourName]\AppData\Local\Beyond All Reason\data\LuaUI\Widgets\`
   - **Linux**: `~/.local/share/Beyond All Reason/data/LuaUI/Widgets/`
   - **Mac**: `~/Library/Application Support/Beyond All Reason/data/LuaUI/Widgets/`

### Method 2: Git Clone
```bash
cd ~/.local/share/Beyond All Reason/data/LuaUI/Widgets/
git clone https://github.com/pyrem/bar-build-timer.git
cp bar-build-timer/build_time_estimator_v2.lua ./
```

### Activation
1. Launch Beyond All Reason
2. Press `F11` to open Widget Selector
3. Find "⏱️ Build Time Estimator v2" and enable it
4. (Optional) Press `Ctrl+F11` to adjust widget position

## 🎮 Usage

### Basic Usage
1. **Select a building to construct** - The widget activates when placing buildings
2. **View time estimate** - Shows above your cursor with builder count
3. **Check economy status** - Color coding indicates if you can afford continuous construction

### Advanced Features

#### Idle Builder Check
Hold the **backtick key (`)** to instantly filter and show only idle builders in range. This helps you:
- Identify unused construction capacity
- Optimize builder assignments
- Spot idle nano turrets

#### Construction Monitoring
Hover over any unit under construction to see:
- Remaining build time
- Current build power applied
- Resource consumption rates
- Storage availability
- Progress percentage

### Display Information

```
⏱️ 45s                    <- Build time estimate
(3 builders, 2 turrets)   <- Active builders count
Usage • 125 M/s • 450 E/s <- Resource consumption
Storage • 2.5k M • 8k E   <- Available storage
```

## 🔧 Configuration

The widget works out-of-the-box with sensible defaults. Advanced users can modify these constants in the code:

```lua
local UPDATE_FREQUENCY = 15        -- Frames between updates (15 = 0.5s)
local HOVER_CHECK_FREQUENCY = 6    -- Hover check rate (6 = 0.2s)
local CACHE_UPDATE_FREQUENCY = 45  -- Cache refresh rate (45 = 1.5s)
```

## 📊 Performance

### Optimizations
- **Frame-based throttling** - Updates only when necessary
- **Intelligent caching** - Reduces API calls
- **Selective rendering** - Only draws when active
- **Efficient calculations** - Uses squared distance for range checks

### Resource Usage
- **CPU**: Minimal (< 1% impact)
- **Memory**: ~100KB
- **FPS Impact**: Negligible

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development Setup
1. Clone the repository
2. Make your changes
3. Test in-game with `/luaui reload`
4. Submit a pull request

### Code Style
- Use local variables for performance
- Comment complex logic
- Follow BAR widget conventions
- Test in both player and spectator modes

## 🐛 Known Issues

- Build time may show `∞` if no builders are available
- Estimates assume continuous resource income
- Does not account for commander assistance bonuses

## 📝 Changelog

### Version 2.0 (Sept 10 - 2025)
- Added spectator mode support
- Implemented economy-aware predictions
- Added nano turret detection
- Improved performance with caching
- Added hover information for constructions
- Color-coded economy indicators
- Idle builder filtering with backtick key

### Version 1.0 (Sept 7 - 2025)
- Initial release
- Basic build time calculation
- Builder detection

## 📄 License

This project is licensed under the GNU General Public License v2.0 or later - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Beyond All Reason](https://www.beyondallreason.info/) development team
- Spring RTS engine developers
- BAR community for testing and feedback

## 📞 Support

- **Bug Reports**: [Create an issue](https://github.com/pyrem/bar-build-timer/issues)
- **Discord**: Find me on the [BAR Discord](https://discord.gg/beyond-all-reason)
- **BAR Forums**: [Beyond All Reason Forums](https://www.beyondallreason.info/forums)

## 🎮 Other BAR Widgets

Check out my other widgets for Beyond All Reason:
- [Smart Turrets](https://github.com/pyrem/bar-smart-turrets) - Intelligent nano turret automation
- [Nano Auto-Build](https://github.com/pyrem/bar-nano-autobuild) - Automatic construction assistance
- [More widgets...](https://github.com/pyrem/bar-widgets)

---

**Made with ❤️ for the Beyond All Reason community**
