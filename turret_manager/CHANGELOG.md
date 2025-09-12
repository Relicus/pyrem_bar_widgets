# Changelog - Turret Manager

All notable changes to the Turret Manager widget for Beyond All Reason.

## [4.1.0] - 2025-01-12

### Added
- **DRY Code Architecture**: Complete refactor following Don't Repeat Yourself principles
  - 8 new reusable helper functions for common operations
  - Eliminated ~100 lines of duplicate code
  - Centralized tier selection and filtering logic
  - Unified command checking and validation patterns

### Improved
- **Visual Indicators**: Refined and optimized display system
  - Reduced all indicator sizes by 40% for cleaner appearance
  - Action circles: radius 25 → 15
  - Tier lines: length 35 → 21
  - Eco ring: radius 33 → 20
  
- **Eco Priority Indicator**: New visual design
  - Changed from solid orange ring to green dashed circle
  - Better visual distinction from other indicators
  - More intuitive color (green = economy/resources)

- **Tier Indicators**: Enhanced visual clarity
  - LOW tier: Yellow single lines radiating from center (T1→T4 priority)
  - HIGH tier: Red double lines radiating from center (T4→T1 priority)
  - Lines now start from turret center for better visibility

- **Camera Zoom Scaling**: Dynamic line width adjustment
  - Lines maintain consistent visual thickness at all zoom levels
  - Automatic scaling based on camera distance
  - Better visibility when zoomed in or out

### Fixed
- **Drawing Condition Bug**: Fixed indicators not showing when only tier/eco enabled
  - Indicators now appear if ANY setting is active (action, tier, or eco)
  - Action circle only shows when action mode is not OFF
  - Tier and eco indicators work independently

### Technical
- **Helper Functions Added**:
  - `createTierTable()` - Initialize tier structure
  - `selectTierByPriority()` - Unified tier selection
  - `filterByTierPriority()` - Unified tier filtering
  - `getTurretPosAndRange()` - Get turret info in one call
  - `getCurrentCommand()` - Get unit's current command
  - `isGuardingActiveUnit()` - Check guard status
  - `sortByDistance()` - Sort units by distance
  - `drawDashedCircle()` - Reusable dashed circle drawing

### Performance
- No performance impact from refactoring
- Same operations, better organized
- Improved code maintainability and readability

## [4.0.0] - 2025-01-11

### Core Features
- **Individual Turret Control**: Each turret maintains independent settings
- **Universal Priority Hierarchy**: All modes follow Action → Tier → Eco → Distance
- **Smart Guard Handling**: Helps when guard target active, finds own work when idle
- **Tier Filtering System**: LOW (T1→T4) or HIGH (T4→T1) priority modes
- **Economy Priority Mode**: Prioritize resource buildings within tier
- **REPAIR Mode Enhancement**: Prioritizes damaged built units over construction

### Visual System
- Action mode circles with color coding
- Tier indicators with arc displays
- Economy priority outer ring
- Selected turret visibility (all turrets in debug mode)

### Modes
- OFF: No action priority, tier/eco filters still apply
- BUILD: Construction priority with repair fallback
- REPAIR: Damaged units first, then construction
- RECLAIM: Reclaim priority with construction fallback
- RESURRECT: Resurrection priority with construction fallback

### Controls
- Action button: Cycle through operational modes
- Eco button: Toggle economy building priority
- Tier button: Cycle tier focus (NONE/LOW/HIGH)
- Ctrl+Shift+D: Toggle debug mode

## [3.0.0] - 2025-01-09

### Initial V3 Release
- Basic turret automation
- Simple priority system
- Manual command respect

---

## Development Notes

### Architecture Philosophy
The widget follows a modular, DRY architecture with clear separation of concerns:
- Pattern Library integration for common operations
- Helper functions for all repeated logic
- Centralized configuration and constants
- Performance-optimized with caching and throttling

### Testing
- Tested with 20+ turrets simultaneously
- Verified in team games and FFA
- Spectator mode compatible
- Performance impact < 0.1% CPU

### Known Issues
- Visual indicators may overlap when turrets are very close
- Tier detection relies on unit cost thresholds for some units

### Future Improvements
- Customizable visual indicator colors
- Per-player settings persistence
- Integration with other automation widgets
- Advanced queue management
