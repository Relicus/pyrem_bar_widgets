# Turret Manager for Beyond All Reason

[![License: GPL v2](https://img.shields.io/badge/License-GPL%20v2-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)
[![BAR Compatible](https://img.shields.io/badge/BAR-Compatible-green.svg)](https://www.beyondallreason.info/)
[![Version](https://img.shields.io/badge/Version-4.1-brightgreen.svg)](https://github.com/pyrem/bar-widgets)
[![DRY Code](https://img.shields.io/badge/Code-DRY%20Principles-orange.svg)](https://en.wikipedia.org/wiki/Don%27t_repeat_yourself)

An advanced nano turret automation widget for [Beyond All Reason](https://www.beyondallreason.info/) that provides intelligent, customizable control over construction turrets with visual feedback and tier-based prioritization.

## 🎯 Features

### Core Functionality
- **🎮 Individual Turret Control** - Each turret maintains independent settings
- **🔄 Smart Guard Handling** - Helps guard targets when active, finds own work when idle
- **📊 Universal Priority System** - Action → Tier → Eco → Distance hierarchy
- **🏗️ Tier Filtering** - LOW (T1→T4) or HIGH (T4→T1) priority modes
- **💰 Economy Priority** - Prioritize resource buildings within tier
- **🔧 Repair Enhancement** - Prioritizes damaged built units over construction

### Visual Indicators (40% smaller, zoom-scaled)
- **Action Circle** (radius 15) - Shows current mode with color coding:
  - 🟡 **Yellow** - BUILD mode
  - 🔵 **Sky Blue** - REPAIR mode
  - 🟢 **Green** - RECLAIM mode
  - 🟣 **Purple** - RESURRECT mode
  
- **Tier Lines** - Radiating from turret center:
  - 🟡 **Yellow Single Lines** - LOW tier (T1→T4 priority)
  - 🔴 **Red Double Lines** - HIGH tier (T4→T1 priority)
  
- **Eco Ring** - Green dashed circle (radius 20):
  - 🟢 Shows when economy priority is active

### Technical Features
- **🚀 DRY Code Architecture** - 8 reusable helper functions
- **📐 Camera Zoom Scaling** - Consistent line thickness at all zoom levels
- **⚡ Performance Optimized** - Smart caching and throttled updates
- **🐛 Debug Mode** - Detailed console output with Ctrl+Shift+D

## 📦 Installation

### Method 1: Direct Download
1. Download `turret_manager.lua`
2. Place in your BAR widgets folder:
   - **Windows**: `C:\Users\[YourName]\AppData\Local\Programs\Beyond-All-Reason\data\LuaUI\Widgets\`
   - **Linux**: `~/.local/share/Beyond All Reason/data/LuaUI/Widgets/`
   - **Mac**: `~/Library/Application Support/Beyond All Reason/data/LuaUI/Widgets/`

### Method 2: Git Clone
```bash
cd ~/.local/share/Beyond All Reason/data/LuaUI/Widgets/
git clone https://github.com/pyrem/bar-turret-manager.git
cp bar-turret-manager/turret_manager.lua ./
```

### Activation
1. Launch Beyond All Reason
2. Press `F11` to open Widget Selector
3. Find "🎯 Turret Manager" and enable it
4. Select nano turrets to see control buttons

## 🎮 Usage

### Basic Controls
1. **Select turrets** - Control buttons appear in command panel
2. **Action Button** - Cycles through modes (OFF→BUILD→REPAIR→RECLAIM→RESURRECT)
3. **Eco Button** - Toggle economy building priority
4. **Tier Button** - Cycle tier focus (NONE→LOW→HIGH)

### Visual Feedback
When you select turrets, you'll see:
- **Action Circle** - Current operational mode
- **Tier Lines** - Active tier filtering
- **Eco Ring** - Economy priority status

All indicators scale with camera zoom for consistent visibility!

### Operational Modes

#### OFF Mode
- No action circle displayed
- Turret still follows tier/eco filters if enabled
- Useful for filtered assistance without specific action priority

#### BUILD Mode (Yellow)
- Prioritizes construction of new buildings
- Falls back to repairs if no construction available
- Best for expansion phases

#### REPAIR Mode (Sky Blue)
- **Prioritizes damaged built units** over construction
- Falls back to construction if no repairs needed
- Essential during battles to maintain defenses

#### RECLAIM Mode (Green)
- Prioritizes reclaiming wrecks and features
- Falls back to construction if nothing to reclaim
- Great for eco management and battlefield cleanup

#### RESURRECT Mode (Purple)
- Prioritizes resurrecting wreckage
- Falls back to construction if nothing to resurrect
- Recover valuable units from battles

### Advanced Strategies

#### Tier + Eco Combinations
- **LOW + ECO**: Build T1 economy first (early game expansion)
- **HIGH + ECO**: Build T4 economy first (late game optimization)
- **LOW + OFF**: General T1→T4 construction priority
- **HIGH + REPAIR**: Prioritize repairing high-tier units

#### Guard Command Intelligence
- Turrets respect guard commands when the target is active
- When guard target is idle, turret finds its own work
- Never wastes time standing idle if work exists

#### Debug Mode (Ctrl+Shift+D)
Shows detailed information:
- Unit tier detection
- Target selection reasoning
- Economy category classification
- Command switching logic

## 📊 Priority System

### Command Hierarchy
1. **User Commands** - Direct orders always have priority
2. **Active Guard** - Helps guard target when it's working
3. **Widget Automation** - Intelligent task selection when idle

### Task Selection
```
Action Mode → Tier Level → Eco Category → Distance
```

Example: BUILD + LOW + ECO will:
1. Look for construction targets
2. Prioritize T1 units over T2/T3/T4
3. Within T1, prioritize economy buildings
4. Within T1 economy, choose closest target

## 🔧 Configuration

### Performance Settings
Edit these constants in the code if needed:
```lua
local UPDATE_FRAMES = 30          -- Update frequency (30 = 1 second)
local RANGE_BUFFER = -25          -- Build range adjustment
local COMPLETION_THRESHOLD = 0.9  -- Near-complete priority threshold
```

### Visual Customization
Indicator sizes and colors can be modified in the DrawWorld function:
- Action circle: radius 15 (line 1502)
- Tier lines: length 21 (lines 1515-1552)
- Eco ring: radius 20 (line 1574)

## 🚀 Technical Details

### DRY Architecture
The widget follows Don't Repeat Yourself principles with:
- 8 reusable helper functions
- Centralized tier logic
- Unified command checking
- ~100 lines of duplicate code eliminated

### Helper Functions
- `createTierTable()` - Initialize tier structure
- `selectTierByPriority()` - Unified tier selection
- `filterByTierPriority()` - Unified tier filtering
- `getTurretPosAndRange()` - Get turret info
- `getCurrentCommand()` - Get unit command
- `isGuardingActiveUnit()` - Check guard status
- `sortByDistance()` - Sort by distance
- `drawDashedCircle()` - Draw dashed circles

### Performance
- **CPU Usage**: < 0.1% with 20+ turrets
- **Memory**: ~200KB
- **FPS Impact**: Negligible
- **Update Rate**: 30 frames (1 second)

## 🤝 Contributing

Contributions welcome! The codebase follows DRY principles for easy modification.

### Development Guidelines
- Use local variables for performance
- Follow existing helper function patterns
- Test with multiple turrets
- Verify in spectator mode
- Comment complex logic

### Testing Checklist
- [ ] Multiple turret selection
- [ ] Mixed settings handling
- [ ] Guard command behavior
- [ ] Tier detection accuracy
- [ ] Visual indicator scaling
- [ ] Debug mode output

## 🐛 Known Issues

- Visual indicators may overlap when turrets are very close
- Some custom units may not have proper tier detection
- Resurrection mode requires wreckage to be in range

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

### Latest Version (4.1.0) (Internal but for you guys v1.0)
- Complete DRY refactor with helper functions
- 40% smaller visual indicators
- Green dashed eco ring
- Camera zoom scaling
- Bug fixes for indicator visibility

## 📄 License

GNU General Public License v2.0 or later - see [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- [Beyond All Reason](https://www.beyondallreason.info/) development team
- Original widget by augustin
- Redesigned by Pyrem
- BAR community for testing and feedback

## 📞 Support
- **Bug Reports**: [GitHub Issues](https://github.com/Relicus/bar-turret-manager/issues)
- **Discord**: Find us on [BAR Discord](https://discord.gg/beyond-all-reason)
- **Forums**: [BAR Forums](https://www.beyondallreason.info/forums)

## 🎮 Related Widgets

Check out these complementary widgets:
- [Build Time Estimator v2](https://github.com/Relicus/pyrem_bar_widgets/blob/main/build_time_estimator_v2.lua) - Real-time build predictions

---

**Made with ❤️ for the Beyond All Reason community**

*Following DRY principles for maintainable, efficient code*
