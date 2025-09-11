# Changelog - Build Time Estimator v2

All notable changes to the Build Time Estimator v2 widget for Beyond All Reason.

## [2.7.5] - 2025-01-XX

### Fixed
- **Text-background alignment**: Perfect vertical alignment between text and background
  - Fixed font alignment offset calculations for "tc" (top-center) mode
  - Corrected height calculation to remove unnecessary spacing for last line
  - Fixed bottom padding adjustment to modify background size instead of position
  - Text now properly contained within background bounds

- **Bottom padding logic**: Background sizing and positioning
  - Padding adjustments now applied to background dimensions rather than position
  - Prevents text from shifting outside background when reducing padding
  - Maintains proper text centering within background

### Improved
- **Display consistency**: Unified formatting across all modes
  - Added brackets to idle mode display for consistent formatting with normal mode
  - Removed "Ready:" prefix from idle mode for cleaner appearance
  - Removed "[X guarding]" indicators for simpler, cleaner unit counts
  - Added BP/s display to build placement mode (matching hover mode)

- **Color system**: Consistent economy-based colors across all modes
  - Removed idle mode color forcing - colors now work the same in all modes
  - Timer color: White for good economy (for distinction from other elements)
  - Storage colors: Green/Red based on resource availability in all modes
  - Economy status colors: Red (unaffordable), Yellow (60-99%), White (good)

- **Code optimization**: Better conditional rendering
  - Wrapped spectator-only renderPlayerInfo calls in proper if statements
  - Improved code readability and reduced unnecessary function calls
  - More efficient rendering for non-spectator players

## [2.7.4] - 2025-01-XX

### Fixed
- **Unit targeting**: Now uses Spring.TraceScreenRay for consistency with game default
  - Accurately targets units under cursor instead of using cylinder search
  - Matches game's default targeting behavior

### Improved
- **UI backgrounds**: Added semi-transparent rounded rectangle backgrounds behind text
  - Better readability on busy/gray backgrounds
  - 60% opacity black backgrounds with 8px rounded corners
  - Properly aligned with text content
  - Dynamically sized based on content and mode

## [2.7.3] - 2025-01-XX

### Refined
- **Resource display**: Cleaner information hierarchy
  - Shows both usage rates (M/s, E/s) AND total costs (M, E)
  - Removed redundant production constraint display
  - BP/s font size adjusted to 16 for better visual balance
  - Usage rates shown above remaining/required resources

## [2.7.2] - 2025-01-XX

### Improved
- **Readability**: Better fonts and spacing
  - BP/s at size 16, other info at size 14 (was 12)
  - Proper spacing between lines (no overlap)
  - Clean, readable display

## [2.7.1] - 2025-01-XX

### Fixed
- **Hover team switching**: Teams now persist permanently (no auto-reset)
- **Selection behavior**: Selecting units clears hover lock and switches to selected team
- **Visual feedback**: Shows pending hover switch with progress percentage

## [2.7.0] - 2025-01-XX

### Fixed
- **Spectator mode**: Now properly tracks selected player's units
- **Team switching**: Auto-switches to show build power of selected units' team
- **Accuracy**: Shows correct BP/s, usage rates, and build times for each player

### Added
- **Hover switching**: Hover over any unit for 1 second to auto-switch to their team (spectator only)

---

## Development Notes

### Architecture Improvements
The widget has undergone significant refactoring to implement DRY (Don't Repeat Yourself) principles:

- **17 utility functions** extracted for code reuse
- **~300 lines of duplicated code** eliminated
- **Performance optimizations** with unit type validation functions
- **Centralized resource formatting** and display functions
- **Improved maintainability** with single source of truth for all logic

### Performance Features
- Smart caching system for unit data
- Throttled calculations to maintain 30+ FPS
- Optimized unit type checking with lookup tables
- Frame-based update scheduling

### Code Organization
- Player & team management functions
- Economy & resource calculation engine
- Unit analysis & validation utilities
- UI rendering & display system
- Performance & caching optimizations
