--[[
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 TURRET MANAGER - Intelligent Nano Turret Automation & Control
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Originally created by augustin - Redesigned and enhanced by Pyrem

📋 FEATURES:
• Individual per-turret settings with visual indicators
• Smart guard handling - helps when needed, works independently when idle
• Dynamic task switching based on priority system
• Tier filtering (T1→T4 or T4→T1) with visual indicators
• Economy priority mode with dedicated visual feedback
• Repair prioritization - built units before construction
• DRY code architecture with reusable helper functions
• Camera zoom-aware line scaling for consistent visuals

🎮 ACTION FOCUS OPTIONS:
• OFF: No action circle - turret follows tier/eco filters only
• BUILD (Yellow 🟡): Prioritizes construction, falls back to repairs
• REPAIR (Sky Blue 🔵): Repairs built units first, then construction
• RECLAIM (Green 🟢): Reclaim priority, falls back to construction  
• RESURRECT (Purple 🟣): Resurrection priority, falls back to construction

🎨 VISUAL INDICATORS (40% smaller, zoom-scaled):
• Action Focus Circle (radius 15): Shows current action with color coding
• Tier Lines: Radiating from center
  - LOW (Yellow): Single lines from 4 sides (T1→T4 priority)
  - HIGH (Red): Double lines from 4 sides (T4→T1 priority)
• Eco Ring (Green dashed, radius 20): Shows when eco priority active

📊 PRIORITY SYSTEM:
Command Hierarchy:
1. User direct commands (highest priority)
2. Active guard commands (when guard target needs help)
3. Widget automation (when idle or guard target idle)

Task Priority:
• Action Focus → Tier Level → Eco Category → Distance
• REPAIR focus prioritizes damaged built units over construction

⚙️ CONTROLS:
• Select turrets to see control buttons
• Action button: Cycles action focus (OFF→BUILD→REPAIR→RECLAIM→RESURRECT)
• Eco button: Toggle economy building priority (green dashed ring)
• Tier button: Cycle tier focus (NONE→LOW→HIGH with line indicators)
• Ctrl+Shift+D: Toggle debug mode for detailed output

💡 USAGE TIPS:
• Visual indicators only show for selected turrets (or all in debug mode)
• Indicators appear if ANY setting is active (action, tier, or eco)
• Combine settings for precise control (e.g., LOW+ECO = T1 economy first)
• Guard idle constructors - turret helps when they work, does own tasks when idle
• Line thickness automatically scales with camera zoom for consistency

🔧 TECHNICAL IMPROVEMENTS:
• DRY architecture with 8 reusable helper functions
• Optimized tier selection and filtering logic
• Centralized command checking and validation
• Performance-optimized distance calculations
• ~100 lines of duplicate code eliminated

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--]]

function widget:GetInfo()
    return {
        name = "🎯 Turret Manager (Pyrem)",
        desc = "Intelligent nano turret automation with tier control and visual feedback",
        author = "augustin, redesigned by Pyrem",
        date = "2025-01-12",
        version = "1.0.0",
        layer = 10,
        enabled = true,
        handler = true,
    }
end

--------------------------------------------------------------------------------
-- PATTERN LIBRARY INTEGRATION (WE USE DRY AS MUCH AS POSSIBLE)
--------------------------------------------------------------------------------

-- Distance calculations from Pattern Library
local Distance = {}

Distance.squared = function(ax, az, bx, bz)
    if not (ax and az and bx and bz) then return math.huge end
    local dx, dz = ax - bx, az - bz
    return dx * dx + dz * dz
end

Distance.exact = function(ax, az, bx, bz)
    return math.sqrt(Distance.squared(ax, az, bx, bz))
end

-- Validation patterns from Pattern Library
local Validate = {}

Validate.isAlive = function(unitID)
    if not Spring.ValidUnitID(unitID) then return false end
    local health = Spring.GetUnitHealth(unitID)
    return health and health > 0
end

Validate.isPlayerUnit = function(unitID)
    local unitTeam = Spring.GetUnitTeam(unitID)
    return unitTeam == Spring.GetMyTeamID()
end

Validate.getPosition = function(entityID, isFeature)
    local x, y, z
    if isFeature then
        x, y, z = Spring.GetFeaturePosition(entityID)
    else
        x, y, z = Spring.GetUnitPosition(entityID)
    end
    return x and z and {x = x, y = y, z = z} or nil
end

-- Frame throttling from Pattern Library
local Throttle = {}

Throttle.create = function(frequency)
    local lastFrame = 0
    return function(callback)
        local currentFrame = Spring.GetGameFrame()
        if currentFrame - lastFrame >= frequency then
            lastFrame = currentFrame
            return callback()
        end
    end
end

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

-- Initialize tier table structure
local function createTierTable()
    return {[1] = {}, [2] = {}, [3] = {}, [4] = {}}
end

-- Select tier based on priority (LOW or HIGH)
local function selectTierByPriority(tierUnits, tierFocus)
    if tierFocus == "LOW" then
        -- T1 > T2 > T3 > T4
        for tier = 1, 4 do
            if #tierUnits[tier] > 0 then return tier end
        end
    elseif tierFocus == "HIGH" then
        -- T4 > T3 > T2 > T1
        for tier = 4, 1, -1 do
            if #tierUnits[tier] > 0 then return tier end
        end
    else
        return "ALL"  -- No tier preference
    end
    return nil
end

-- Filter units by tier priority
local function filterByTierPriority(tierUnits, tierFocus)
    local candidates = {}
    
    if tierFocus == "LOW" then
        -- T1 > T2 > T3 > T4
        for tier = 1, 4 do
            for _, unit in ipairs(tierUnits[tier]) do
                table.insert(candidates, unit)
            end
        end
    elseif tierFocus == "HIGH" then
        -- T4 > T3 > T2 > T1
        for tier = 4, 1, -1 do
            for _, unit in ipairs(tierUnits[tier]) do
                table.insert(candidates, unit)
            end
        end
    else
        -- No tier preference - add all
        for tier = 1, 4 do
            for _, unit in ipairs(tierUnits[tier]) do
                table.insert(candidates, unit)
            end
        end
    end
    
    return candidates
end

-- Get turret position and build range
local function getTurretPosAndRange(turretID)
    local tx, ty, tz = Spring.GetUnitPosition(turretID)
    if not tx then return nil end
    
    local turretDefID = Spring.GetUnitDefID(turretID)
    if not turretDefID then return nil end
    
    local buildRange = UnitDefs[turretDefID].buildDistance or 128
    return tx, ty, tz, buildRange, turretDefID
end

-- Get current command for a unit
local function getCurrentCommand(unitID)
    local commands = Spring.GetUnitCommands(unitID, 1)
    if commands and commands[1] then
        return commands[1], commands[1].params and commands[1].params[1]
    end
    return nil, nil
end

-- Force clear all commands from turret
local function forceStopTurret(turretID)
    -- Validate turret ID first
    if not turretID or not Spring.ValidUnitID(turretID) then
        if DEBUG_MODE then
            Spring.Echo("    WARNING: Invalid turret ID in forceStopTurret: " .. tostring(turretID))
        end
        return
    end
    
    if DEBUG_MODE then
        local commands = Spring.GetUnitCommands(turretID, -1)
        if commands and #commands > 0 then
            Spring.Echo("    Clearing " .. #commands .. " commands from turret " .. turretID)
            for i, cmd in ipairs(commands) do
                Spring.Echo("      Removing cmd[" .. i .. "]: " .. cmd.id .. " tag=" .. cmd.tag)
            end
        end
    end
    
    -- First issue stop to interrupt current action
    if CMD_STOP then
        Spring.GiveOrderToUnit(turretID, CMD_STOP, {}, {})
    else
        if DEBUG_MODE then
            Spring.Echo("    WARNING: CMD_STOP is nil!")
        end
    end
    
    -- Then remove all queued commands (if CMD_REMOVE is available)
    if CMD_REMOVE and CMD_REMOVE > 0 then
        local commands = Spring.GetUnitCommands(turretID, -1)
        if commands and #commands > 0 then
            -- Remove in reverse order (newest first)
            for i = #commands, 1, -1 do
                -- Use the format from holo_place: tag directly, not in table
                Spring.GiveOrderToUnit(turretID, CMD_REMOVE, commands[i].tag, 0)
            end
        end
    end
    
    -- Issue stop again to be sure
    if CMD_STOP then
        Spring.GiveOrderToUnit(turretID, CMD_STOP, {}, {})
    end
end

-- Check if unit is guarding an active target
local function isGuardingActiveUnit(unitID)
    local cmd, targetID = getCurrentCommand(unitID)
    if cmd and cmd.id == CMD.GUARD and targetID and Spring.ValidUnitID(targetID) then
        local guardCommands = Spring.GetUnitCommands(targetID, 1)
        return guardCommands and #guardCommands > 0
    end
    return false
end

-- Sort units by distance
local function sortByDistance(units)
    table.sort(units, function(a, b) return a.distance < b.distance end)
    return units
end


-- Draw dashed circle at position
local function drawDashedCircle(x, y, z, radius, dashDegrees, gapDegrees)
    gl.BeginEnd(GL.LINES, function()
        local totalDegrees = dashDegrees + gapDegrees
        for i = 0, 360 - totalDegrees, totalDegrees do
            local angle1 = math.rad(i)
            local angle2 = math.rad(i + dashDegrees)
            gl.Vertex(x + math.cos(angle1) * radius, y, z + math.sin(angle1) * radius)
            gl.Vertex(x + math.cos(angle2) * radius, y, z + math.sin(angle2) * radius)
        end
    end)
end


-- Group candidates by priority level (for strict tie-breaking)
local function groupByPriority(candidates, priorityCalc)
    local groups = {}
    local priorityMap = {}
    
    -- Calculate priorities and group candidates
    for _, candidate in ipairs(candidates) do
        local priority = priorityCalc(candidate, 0)  -- Pass 0 for distance to exclude it
        
        if not priorityMap[priority] then
            priorityMap[priority] = {}
            table.insert(groups, {priority = priority, candidates = priorityMap[priority]})
        end
        
        -- Store candidate with its actual distance for later sorting
        table.insert(priorityMap[priority], candidate)
    end
    
    -- Sort groups by priority (lowest priority value = highest priority)
    table.sort(groups, function(a, b) return a.priority < b.priority end)
    
    -- Within each group, sort by distance
    for _, group in ipairs(groups) do
        sortByDistance(group.candidates)
        
        -- Debug output for priority grouping
        if DEBUG_MODE and #group.candidates > 1 then
            Spring.Echo("    Priority group " .. math.floor(group.priority) .. " has " .. 
                       #group.candidates .. " candidates - using distance as tie-breaker")
            for i, candidate in ipairs(group.candidates) do
                if i <= 3 then  -- Show first 3
                    local id = candidate.id
                    local dist = math.floor(candidate.distance or 0)
                    if candidate.defID then
                        local unitDef = UnitDefs[candidate.defID]
                        if unitDef then
                            Spring.Echo("      [" .. i .. "] " .. unitDef.name .. " at distance " .. dist)
                        end
                    elseif candidate.isFeature then
                        Spring.Echo("      [" .. i .. "] Feature at distance " .. dist)
                    else
                        Spring.Echo("      [" .. i .. "] Target at distance " .. dist)
                    end
                end
            end
        end
    end
    
    return groups
end

--------------------------------------------------------------------------------
-- CONFIGURATION & CONSTANTS
--------------------------------------------------------------------------------

-- Performance & Behavior
local UPDATE_FRAMES = 30               -- Frames between updates (1 second @ 30fps)
local DECAY_CHECK_FRAMES = 60          -- Frames between decay checks
local DECAY_TIME = 200                 -- Frames before structure decays
local DECAY_WARNING = 20               -- Frames before decay to take action
local RANGE_BUFFER = -25               -- Build range adjustment
local COMPLETION_THRESHOLD = 0.9       -- Priority threshold for near-complete
local MANUAL_OVERRIDE_DURATION = 150   -- Frames to respect manual commands

-- Priority Weights
local METAL_WEIGHT = 2
local ENERGY_WEIGHT = 1
local CATEGORY_WEIGHTS = {
    resource = 0,
    defense = 10000,
    other = 20000
}

-- Debug mode
local DEBUG_MODE = false

--------------------------------------------------------------------------------
-- COMMAND DEFINITIONS
--------------------------------------------------------------------------------

-- Spring Command Constants (REQUIRED!)
local CMD_STOP = CMD.STOP or 0
local CMD_REPAIR = CMD.REPAIR or 40
local CMD_RECLAIM = CMD.RECLAIM or 90
local CMD_RESURRECT = CMD.RESURRECT or 125
local CMD_GUARD = CMD.GUARD or 25
local CMD_MOVE = CMD.MOVE or 10
local CMD_BUILD = CMD.BUILD 
local CMD_INSERT = CMD.INSERT or 1
local CMD_REMOVE = CMD.REMOVE or 2

-- Command type constants (required for custom buttons)
local CMDTYPE = CMDTYPE or {}
CMDTYPE.ICON_MODE = 5  -- For mode buttons with multiple states

-- Custom Command IDs
local CMD_SMART_MODE = 28370
local CMD_ECO_PRIORITY = 28371
local CMD_TIER_FOCUS = 28372

-- Priority modes enum
local PRIORITY_MODES = {
    OFF = 0,
    BUILD = 1,
    REPAIR = 2,
    RECLAIM = 3,
    RESURRECT = 4
}

-- Mode configuration table (DRY approach)
local MODE_CONFIG = {
    [PRIORITY_MODES.OFF] = {
        name = "OFF",
        display = "Action Focus",
        message = "Mode OFF - no action priority",
        color = {0.5, 0.5, 0.5, 0.0}  -- Transparent - no circle for OFF
    },
    [PRIORITY_MODES.BUILD] = {
        name = "BUILD",
        display = "Build",
        message = "BUILD mode activated",
        color = {0.9, 0.9, 0.2, 0.8}  -- Yellow
    },
    [PRIORITY_MODES.REPAIR] = {
        name = "REPAIR", 
        display = "Repair",
        message = "REPAIR mode activated",
        color = {0.3, 0.7, 1.0, 0.8}  -- Sky Blue
    },
    [PRIORITY_MODES.RECLAIM] = {
        name = "RECLAIM",
        display = "Reclaim",
        message = "RECLAIM mode activated",
        color = {0.2, 0.9, 0.2, 0.8}  -- Green
    },
    [PRIORITY_MODES.RESURRECT] = {
        name = "RESURRECT",
        display = "Resurrect",
        message = "RESURRECT mode activated",
        color = {0.9, 0.3, 0.9, 0.8}  -- Purple/Pink
    }
}

-- Command descriptions
local CMD_SMART_MODE_DESC = {
    id = CMD_SMART_MODE,
    type = CMDTYPE.ICON_MODE,
    name = "Smart Mode",
    cursor = nil,
    action = "smartturrets_mode",
    tooltip = "Priority mode: OFF → Build → Repair → Reclaim → Resurrect",
    params = {0, "Action Focus", "Build", "Repair", "Reclaim", "Resurrect"}
}

local CMD_ECO_PRIORITY_DESC = {
    id = CMD_ECO_PRIORITY,
    type = CMDTYPE.ICON_MODE,
    name = "ECO Priority",
    cursor = nil,
    action = "smartturrets_eco",
    tooltip = "Toggle economic building priority in Build mode",
    params = {0, "Eco Focus", "Eco Focus"}
}

local CMD_TIER_FOCUS_DESC = {
    id = CMD_TIER_FOCUS,
    type = CMDTYPE.ICON_MODE,
    name = "Tier Focus",
    cursor = nil,
    action = "smartturrets_tier",
    tooltip = "Tier Focus: None (eco priority only) | LowTier: T1→T4 | HighTier: T4→T1",
    params = {0, "Tier Focus", "LowTier", "HighTier"}
}

--------------------------------------------------------------------------------
-- STATE VARIABLES
--------------------------------------------------------------------------------

-- Per-turret settings (DRY: single source of truth)
local turretSettings = {}  -- turretID -> {mode, ecoEnabled, tierFocus}

-- Default settings template
local DEFAULT_SETTINGS = {
    mode = PRIORITY_MODES.OFF,
    ecoEnabled = false,
    tierFocus = "NONE"
}

-- Dynamic data structures
local turretDefIDs = {}        -- Construction turret definitions
local UNIT_TIERS = {}          -- Tier classification cache
local UNIT_CATEGORIES = {}     -- Category classification cache
local UNIT_GROUPS = {}         -- Unit group cache from customParams

-- Turret management
local watchedTurrets = {}      -- Active turret tracking
local manualOverrides = {}     -- Manual command tracking
local constructionTracking = {} -- Decay prevention tracking

-- Throttled update functions
local updateTurrets = Throttle.create(UPDATE_FRAMES)
local checkDecay = Throttle.create(DECAY_CHECK_FRAMES)

--------------------------------------------------------------------------------
-- PER-TURRET SETTINGS MANAGEMENT
--------------------------------------------------------------------------------

local function getTurretSettings(turretID)
    if not turretSettings[turretID] then
        -- Deep copy default settings
        turretSettings[turretID] = {
            mode = DEFAULT_SETTINGS.mode,
            ecoEnabled = DEFAULT_SETTINGS.ecoEnabled,
            tierFocus = DEFAULT_SETTINGS.tierFocus
        }
    end
    return turretSettings[turretID]
end

local function filterTurrets(unitList)
    local turrets = {}
    for _, unitID in ipairs(unitList or {}) do
        local defID = Spring.GetUnitDefID(unitID)
        if defID and turretDefIDs[defID] and Validate.isPlayerUnit(unitID) then
            table.insert(turrets, unitID)
        end
    end
    return turrets
end

-- DRY: Generic mode cycling
local function cycleValue(current, values)
    for i, v in ipairs(values) do
        if v == current then
            return values[(i % #values) + 1]
        end
    end
    return values[1]
end

--------------------------------------------------------------------------------
-- UNIT CLASSIFICATION (Cached)
--------------------------------------------------------------------------------

local function getUnitTier(unitDefID)
    if UNIT_TIERS[unitDefID] then
        return UNIT_TIERS[unitDefID]
    end
    
    local unitDef = UnitDefs[unitDefID]
    if not unitDef then 
        UNIT_TIERS[unitDefID] = 1
        return 1 
    end
    
    local tier = nil
    local tierSource = "default"
    
    -- Check custom params (all variations)
    if unitDef.customParams then
        if unitDef.customParams.techlevel then
            tier = tonumber(unitDef.customParams.techlevel)
            tierSource = "customParams.techlevel"
        elseif unitDef.customParams.techLevel then
            tier = tonumber(unitDef.customParams.techLevel)
            tierSource = "customParams.techLevel"
        elseif unitDef.customParams.tech_level then
            tier = tonumber(unitDef.customParams.tech_level)
            tierSource = "customParams.tech_level"
        end
    end
    
    -- Also check lowercase customparams
    if not tier and unitDef.customparams then
        if unitDef.customparams.techlevel then
            tier = tonumber(unitDef.customparams.techlevel)
            tierSource = "customparams.techlevel"
        elseif unitDef.customparams.techLevel then
            tier = tonumber(unitDef.customparams.techLevel)
            tierSource = "customparams.techLevel"
        end
    end
    
    -- Default to tier 1 if no tech level found
    if not tier then
        tier = 1
        tierSource = "default (no customParams)"
    end
    
    if DEBUG_MODE then
        Spring.Echo("Tech Level: " .. unitDef.name .. " = T" .. tier .. " (source: " .. tierSource .. ")")
    end
    
    UNIT_TIERS[unitDefID] = tier
    return tier
end

local function getUnitGroup(unitDefID)
    if UNIT_GROUPS[unitDefID] then
        return UNIT_GROUPS[unitDefID]
    end
    
    local unitDef = UnitDefs[unitDefID]
    if not unitDef then 
        UNIT_GROUPS[unitDefID] = "other"
        return "other" 
    end
    
    local unitGroup = nil
    
    -- Check custom params for unit group (all variations)
    if unitDef.customParams then
        if unitDef.customParams.unitgroup then
            unitGroup = unitDef.customParams.unitgroup
        elseif unitDef.customParams.unitGroup then
            unitGroup = unitDef.customParams.unitGroup
        elseif unitDef.customParams.unit_group then
            unitGroup = unitDef.customParams.unit_group
        end
    end
    
    -- Also check lowercase customparams
    if not unitGroup and unitDef.customparams then
        if unitDef.customparams.unitgroup then
            unitGroup = unitDef.customparams.unitgroup
        elseif unitDef.customparams.unitGroup then
            unitGroup = unitDef.customparams.unitGroup
        end
    end
    
    -- Default to "other" if no group found
    if not unitGroup then
        unitGroup = "other"
    end
    
    if DEBUG_MODE then
        Spring.Echo("Unit Group: " .. unitDef.name .. " = " .. unitGroup)
    end
    
    UNIT_GROUPS[unitDefID] = unitGroup
    return unitGroup
end

local function getUnitCategory(unitDefID)
    if UNIT_CATEGORIES[unitDefID] then
        return UNIT_CATEGORIES[unitDefID]
    end
    
    local unitDef = UnitDefs[unitDefID]
    if not unitDef then 
        UNIT_CATEGORIES[unitDefID] = "other"
        return "other" 
    end
    
    local category = "other"
    
    -- Check using actual unit properties (no keyword searching)
    
    -- Metal Extractors
    if unitDef.extractsMetal and unitDef.extractsMetal > 0 then
        category = "resource"
    
    -- Energy Production
    elseif unitDef.energyMake and unitDef.energyMake > 0 and 
           unitDef.energyMake > (unitDef.energyUpkeep or 0) then
        category = "resource"
    
    -- Metal Makers (convert energy to metal)
    elseif unitDef.metalMake and unitDef.metalMake > 0 and
           unitDef.energyUpkeep and unitDef.energyUpkeep > 0 then
        category = "resource"
    
    -- Storage buildings
    elseif (unitDef.energyStorage and unitDef.energyStorage > 0) or
           (unitDef.metalStorage and unitDef.metalStorage > 0) then
        category = "resource"
    
    -- Defense structures (has weapons, can't move)
    elseif unitDef.weapons and #unitDef.weapons > 0 and 
           not unitDef.canMove and unitDef.isBuilding then
        category = "defense"
    
    -- Radar/Jammer
    elseif unitDef.radarRadius and unitDef.radarRadius > 0 then
        category = "intel"
    elseif unitDef.jammerRadius and unitDef.jammerRadius > 0 then
        category = "intel"
    
    -- Factories
    elseif unitDef.isFactory then
        category = "factory"
    
    -- Construction units (builders)
    elseif unitDef.isBuilder and unitDef.canMove then
        category = "builder"
    
    -- Static builders (like nano turrets - should not be prioritized)
    elseif unitDef.isBuilder and not unitDef.canMove then
        category = "assist"
    end
    
    if DEBUG_MODE and category == "other" then
        -- Log units that don't fit any category for debugging
        Spring.Echo("  Category 'other': " .. unitDef.name .. 
                   " (factory:" .. tostring(unitDef.isFactory) ..
                   " builder:" .. tostring(unitDef.isBuilder) ..
                   " weapons:" .. tostring(unitDef.weapons and #unitDef.weapons or 0) .. ")")
    end
    
    UNIT_CATEGORIES[unitDefID] = category
    return category
end

--------------------------------------------------------------------------------
-- TURRET DISCOVERY
--------------------------------------------------------------------------------

local function discoverConstructionTurrets()
    turretDefIDs = {}
    
    -- Known turret names
    local knownNames = {"armnanotc", "cornanotc", "legnanotc", "armnanotcplat", "cornanotcplat"}
    for _, name in ipairs(knownNames) do
        local unitDef = UnitDefNames[name]
        if unitDef then
            turretDefIDs[unitDef.id] = true
        end
    end
    
    -- Dynamic discovery
    for unitDefID, unitDef in pairs(UnitDefs) do
        if unitDef and unitDef.isBuilding and not unitDef.canMove and
           unitDef.buildOptions and #unitDef.buildOptions > 0 and
           unitDef.buildDistance and unitDef.buildDistance > 0 then
            
            local name = unitDef.name or ""
            local desc = unitDef.description or ""
            
            if string.find(name, "nano") or string.find(desc:lower(), "nano") or
               string.find(desc:lower(), "construction turret") then
                turretDefIDs[unitDefID] = true
            end
        end
    end
    
    if DEBUG_MODE then
        local count = 0
        for _ in pairs(turretDefIDs) do count = count + 1 end
        Spring.Echo("V4: Discovered " .. count .. " turret types")
    end
end

--------------------------------------------------------------------------------
-- DRY TARGET FINDING SYSTEM
--------------------------------------------------------------------------------

-- Generic target finder (DRY pattern) - now with strict priority grouping
local function findBestTargetGeneric(turretID, turretX, turretZ, buildRange, candidateGetter, priorityCalc)
    local validCandidates = {}
    
    -- First, filter candidates by range and collect valid ones with distances
    for _, candidate in ipairs(candidateGetter()) do
        local pos = candidate.pos or Validate.getPosition(candidate.id, candidate.isFeature)
        
        if pos then
            local dist = Distance.exact(turretX, turretZ, pos.x, pos.z)
            local radius = candidate.radius or 8
            
            if dist <= buildRange + radius + RANGE_BUFFER then
                candidate.distance = dist  -- Store distance for later use
                table.insert(validCandidates, candidate)
            end
        end
    end
    
    -- If no valid candidates, return nil
    if #validCandidates == 0 then
        return nil
    end
    
    -- Group candidates by priority level
    local priorityGroups = groupByPriority(validCandidates, priorityCalc)
    
    -- Select from the highest priority group (first group after sorting)
    if #priorityGroups > 0 and #priorityGroups[1].candidates > 0 then
        local bestCandidate = priorityGroups[1].candidates[1]  -- Already sorted by distance
        
        if DEBUG_MODE and #priorityGroups[1].candidates > 1 then
            Spring.Echo("  -> Multiple targets with same priority, choosing closest: " .. 
                       #priorityGroups[1].candidates .. " candidates at priority " .. 
                       math.floor(priorityGroups[1].priority))
        end
        
        return bestCandidate.id
    end
    
    return nil
end

-- Build target finder - Universal hierarchy: tier→eco→distance
local function findBuildTargets(turretID, settings)
    local myTeamID = Spring.GetMyTeamID()
    
    -- Get turret position and range
    local tx, ty, tz, buildRange, turretDefID = getTurretPosAndRange(turretID)
    if not tx then return nil end
    
    -- Sort units by tier
    local tierUnits = createTierTable()
    
    -- Only get units within build range
    local nearbyUnits = Spring.GetUnitsInCylinder(tx, tz, buildRange + 50)
    
    if DEBUG_MODE then
        Spring.Echo("Turret " .. turretID .. " [tierFocus=" .. settings.tierFocus .. 
                   " eco=" .. tostring(settings.ecoEnabled) .. "] scanning " .. 
                   #(nearbyUnits or {}) .. " nearby units")
    end
    
    for _, unitID in ipairs(nearbyUnits or {}) do
        -- Only check our team's units
        if Spring.GetUnitTeam(unitID) == myTeamID then
            local _, _, _, _, buildProgress = Spring.GetUnitHealth(unitID)
            
            if buildProgress and buildProgress > 0.01 and buildProgress < 1.0 then
                local unitDefID = Spring.GetUnitDefID(unitID)
                if unitDefID then
                    local tier = getUnitTier(unitDefID)
                    local category = getUnitCategory(unitDefID)
                    local unitGroup = getUnitGroup(unitDefID)
                    local ux, _, uz = Spring.GetUnitPosition(unitID)
                    if ux and uz then
                        local distance = Distance.exact(tx, tz, ux, uz)
                        
                        if DEBUG_MODE then
                            local unitDef = UnitDefs[unitDefID]
                            if unitDef then
                                local groupSymbol = unitGroup == "energy" and "⚡" or
                                                   unitGroup == "metal" and "🔩" or
                                                   unitGroup == "utils" and "🔧" or
                                                   unitGroup == "weapon" and "⚔️" or
                                                   unitGroup == "builder" and "🏗️" or
                                                   unitGroup == "buildert2" and "🏗️²" or
                                                   unitGroup == "aa" and "🎯" or "❓"
                                Spring.Echo("  Found: " .. unitDef.name .. " = T" .. tier .. 
                                          " " .. groupSymbol .. "(" .. unitGroup .. ") progress=" .. math.floor(buildProgress * 100) .. 
                                          "% at " .. math.floor(distance) .. " range")
                            end
                        end
                        
                        -- Store unit with distance and unit group for later sorting
                        table.insert(tierUnits[tier], {
                            id = unitID,
                            distance = distance,
                            progress = buildProgress,
                            category = category,
                            unitGroup = unitGroup
                        })
                    end
                end
            end
        end
    end
    
    -- Get current target to check if we should switch
    local cmd, currentTarget = getCurrentCommand(turretID)
    if cmd and cmd.id ~= CMD.REPAIR then
        currentTarget = nil
    end
    
    -- Simple tier-based selection using helper
    local selectedTier = selectTierByPriority(tierUnits, settings.tierFocus)
    
    if DEBUG_MODE and settings.tierFocus ~= "NONE" then
        Spring.Echo((settings.tierFocus == "LOW" and "LowTier" or "HighTier") .. 
                   " mode: T1=" .. #tierUnits[1] .. " T2=" .. #tierUnits[2] .. 
                   " T3=" .. #tierUnits[3] .. " T4=" .. #tierUnits[4] .. 
                   " -> Selected tier: " .. tostring(selectedTier))
        
        -- Show what's in each tier
        for tier = 1, 4 do
            if #tierUnits[tier] > 0 then
                Spring.Echo("  Tier " .. tier .. " units:")
                for i, unit in ipairs(tierUnits[tier]) do
                    local unitDefID = Spring.GetUnitDefID(unit.id)
                    local unitDef = unitDefID and UnitDefs[unitDefID]
                    if unitDef and i <= 3 then  -- Show first 3
                        Spring.Echo("    - " .. unitDef.name .. " (" .. unit.unitGroup .. 
                                   ", progress: " .. math.floor(unit.progress * 100) .. 
                                   "%, dist: " .. math.floor(unit.distance) .. ")")
                    end
                end
            end
        end
        
        if currentTarget then
            local currentDefID = Spring.GetUnitDefID(currentTarget)
            if currentDefID then
                local currentTier = getUnitTier(currentDefID)
                local currentDef = UnitDefs[currentDefID]
                if currentDef then
                    Spring.Echo("  Current target: " .. currentDef.name .. " (T" .. currentTier .. 
                               ") ID=" .. currentTarget)
                end
            end
        end
    end
    
    if selectedTier == "ALL" and DEBUG_MODE and settings.ecoEnabled then
        Spring.Echo("Tier NONE: Eco becomes primary filter (ignoring tier levels)")
    end
    
    -- Collect units based on tier selection
    local units = {}
    if selectedTier == "ALL" then
        -- No tier preference - add all units from all tiers
        for tier = 1, 4 do
            for _, unit in ipairs(tierUnits[tier]) do
                table.insert(units, unit)
            end
        end
    elseif selectedTier and #tierUnits[selectedTier] > 0 then
        units = tierUnits[selectedTier]
    end
    
    -- If we have units to choose from
    if #units > 0 then
        
        local targetUnit = nil
        
        -- Separate units by groups for prioritization
        local groupedUnits = {
            energy_metal = {},
            utils = {},
            weapon = {},
            aa = {},
            builder = {},
            others = {}
        }
        
        -- Categorize all units by their groups
        for _, unit in ipairs(units) do
            if unit.unitGroup == "energy" or unit.unitGroup == "metal" then
                table.insert(groupedUnits.energy_metal, unit)
            elseif unit.unitGroup == "utils" then
                table.insert(groupedUnits.utils, unit)
            elseif unit.unitGroup == "weapon" then
                table.insert(groupedUnits.weapon, unit)
            elseif unit.unitGroup == "aa" then
                table.insert(groupedUnits.aa, unit)
            elseif unit.unitGroup == "builder" or unit.unitGroup == "buildert2" then
                table.insert(groupedUnits.builder, unit)
            else
                table.insert(groupedUnits.others, unit)
            end
        end
        
        -- Sort each group by distance
        for _, group in pairs(groupedUnits) do
            sortByDistance(group)
        end
        
        if DEBUG_MODE then
            local tierLabel = selectedTier == "ALL" and "all tiers" or ("T" .. selectedTier)
            local ecoStatus = settings.ecoEnabled and "ECO ON" or "ECO OFF"
            Spring.Echo("  Unit Groups in " .. tierLabel .. " [" .. ecoStatus .. "]:")
            Spring.Echo("    Energy/Metal: " .. #groupedUnits.energy_metal)
            Spring.Echo("    Utils: " .. #groupedUnits.utils)
            Spring.Echo("    Weapons: " .. #groupedUnits.weapon)
            Spring.Echo("    AA: " .. #groupedUnits.aa)
            Spring.Echo("    Builders: " .. #groupedUnits.builder)
            Spring.Echo("    Others: " .. #groupedUnits.others)
        end
        
        -- Select target based on priority order
        if settings.ecoEnabled then
            -- ECO ON: energy/metal > utils > weapon > aa > builder > others
            if #groupedUnits.energy_metal > 0 then
                targetUnit = groupedUnits.energy_metal[1]
                if DEBUG_MODE then
                    Spring.Echo("  -> ECO PRIORITY: Selected " .. targetUnit.unitGroup .. " (highest priority)")
                end
            elseif #groupedUnits.utils > 0 then
                targetUnit = groupedUnits.utils[1]
                if DEBUG_MODE then
                    Spring.Echo("  -> Selected utils (second priority)")
                end
            elseif #groupedUnits.weapon > 0 then
                targetUnit = groupedUnits.weapon[1]
                if DEBUG_MODE then
                    Spring.Echo("  -> Selected weapon (third priority)")
                end
            elseif #groupedUnits.aa > 0 then
                targetUnit = groupedUnits.aa[1]
                if DEBUG_MODE then
                    Spring.Echo("  -> Selected AA (fourth priority)")
                end
            elseif #groupedUnits.builder > 0 then
                targetUnit = groupedUnits.builder[1]
                if DEBUG_MODE then
                    Spring.Echo("  -> Selected builder (fifth priority)")
                end
            elseif #groupedUnits.others > 0 then
                targetUnit = groupedUnits.others[1]
                if DEBUG_MODE then
                    Spring.Echo("  -> Selected other (lowest priority)")
                end
            end
            
        else
            -- ECO OFF: utils > weapon > aa > builder > energy/metal > others
            if #groupedUnits.utils > 0 then
                targetUnit = groupedUnits.utils[1]
                if DEBUG_MODE then
                    Spring.Echo("  -> Selected utils (highest priority without eco)")
                end
            elseif #groupedUnits.weapon > 0 then
                targetUnit = groupedUnits.weapon[1]
                if DEBUG_MODE then
                    Spring.Echo("  -> Selected weapon (second priority)")
                end
            elseif #groupedUnits.aa > 0 then
                targetUnit = groupedUnits.aa[1]
                if DEBUG_MODE then
                    Spring.Echo("  -> Selected AA (third priority)")
                end
            elseif #groupedUnits.builder > 0 then
                targetUnit = groupedUnits.builder[1]
                if DEBUG_MODE then
                    Spring.Echo("  -> Selected builder (fourth priority)")
                end
            elseif #groupedUnits.energy_metal > 0 then
                targetUnit = groupedUnits.energy_metal[1]
                if DEBUG_MODE then
                    Spring.Echo("  -> Selected energy/metal (fifth priority without eco)")
                end
            elseif #groupedUnits.others > 0 then
                targetUnit = groupedUnits.others[1]
                if DEBUG_MODE then
                    Spring.Echo("  -> Selected other (lowest priority)")
                end
            end
        end
        
        if DEBUG_MODE and targetUnit then
            local targetDefID = Spring.GetUnitDefID(targetUnit.id)
            local targetDef = targetDefID and UnitDefs[targetDefID]
            if targetDef then
                Spring.Echo("    Target: " .. targetDef.name .. " (" .. targetUnit.unitGroup .. 
                           ") at distance " .. math.floor(targetUnit.distance))
            end
        end
        
        if DEBUG_MODE and targetUnit then
            local ecoStatus = settings.ecoEnabled and "[ECO ON]" or "[ECO OFF]"
            local tierLabel = selectedTier == "ALL" and "unit from all tiers" or ("T" .. selectedTier .. " unit")
            Spring.Echo("Selected " .. tierLabel .. " " .. ecoStatus .. " (out of " .. 
                       #tierUnits[1] .. " T1, " .. #tierUnits[2] .. " T2, " ..
                       #tierUnits[3] .. " T3, " .. #tierUnits[4] .. " T4)")
            local targetDefID = Spring.GetUnitDefID(targetUnit.id)
            if targetDefID and UnitDefs[targetDefID] then
                Spring.Echo("  -> Target: " .. UnitDefs[targetDefID].name)
            end
        end
        
        return targetUnit and targetUnit.id or nil
    end
    
    return nil
end

-- Repair target finder with tier support
local function findRepairTargets(turretID, settings)
    local myTeamID = Spring.GetMyTeamID()
    local tx, ty, tz, buildRange = getTurretPosAndRange(turretID)
    if not tx then return {} end
    
    -- Sort units by tier for consistent hierarchy
    local tierUnits = createTierTable()
    
    -- Get damaged units within range
    local nearbyUnits = Spring.GetUnitsInCylinder(tx, tz, buildRange + 50)
    
    for _, unitID in ipairs(nearbyUnits or {}) do
        if Spring.GetUnitTeam(unitID) == myTeamID then
            local health, maxHealth, _, _, buildProgress = Spring.GetUnitHealth(unitID)
            if health and maxHealth and health < maxHealth and health > 0 then
                local unitDefID = Spring.GetUnitDefID(unitID)
                if unitDefID then
                    local tier = getUnitTier(unitDefID)
                    local category = getUnitCategory(unitDefID)
                    local unitGroup = getUnitGroup(unitDefID)
                    local ux, _, uz = Spring.GetUnitPosition(unitID)
                    if ux and uz then
                        local distance = Distance.exact(tx, tz, ux, uz)
                        local radius = UnitDefs[unitDefID].radius or 8
                        
                        if distance <= buildRange + radius + RANGE_BUFFER then
                            -- Determine if unit is already built or under construction
                            local isBuilt = buildProgress and buildProgress >= 0.99
                            
                            if DEBUG_MODE and (not buildProgress or buildProgress < 0.99) then
                                local unitDef = UnitDefs[unitDefID]
                                if unitDef then
                                    Spring.Echo("  Repair target: " .. unitDef.name .. 
                                              " (T" .. tier .. ", " .. unitGroup .. ") " .. 
                                              (isBuilt and "DAMAGED" or "CONSTRUCTING") ..
                                              " progress=" .. math.floor((buildProgress or 1) * 100) .. "%")
                                end
                            end
                            
                            table.insert(tierUnits[tier], {
                                id = unitID,
                                defID = unitDefID,
                                damage = 1 - (health / maxHealth),
                                distance = distance,
                                category = category,
                                unitGroup = unitGroup,
                                tier = tier,
                                radius = radius,
                                isBuilt = isBuilt,
                                buildProgress = buildProgress or 1
                            })
                        end
                    end
                end
            end
        end
    end
    
    -- Apply tier filtering using helper
    return filterByTierPriority(tierUnits, settings.tierFocus)
end

-- Reclaim/Resurrect target finder with tier support
local function findFeatureTargets(turretX, turretZ, buildRange, resurrectOnly, settings)
    local features = Spring.GetFeaturesInRectangle(
        turretX - buildRange, turretZ - buildRange,
        turretX + buildRange, turretZ + buildRange
    )
    
    -- Organize by tier for resurrect, by value tier for reclaim
    local tierFeatures = createTierTable()
    
    for _, featureID in ipairs(features or {}) do
        local featureDefID = Spring.GetFeatureDefID(featureID)
        if featureDefID then
            local featureDef = FeatureDefs[featureDefID]
            local fx, fy, fz = Spring.GetFeaturePosition(featureID)
            if fx and fz then
                local distance = Distance.exact(turretX, turretZ, fx, fz)
                
                if resurrectOnly then
                    -- Only resurrectable features
                    if featureDef and featureDef.resurrectable then
                        local originalDef = UnitDefNames[featureDef.resurrectable]
                        if originalDef then
                            -- Get tier of original unit
                            local tier = getUnitTier(originalDef.id)
                            local category = getUnitCategory(originalDef.id)
                            local unitGroup = getUnitGroup(originalDef.id)
                            
                            table.insert(tierFeatures[tier], {
                                id = featureID,
                                isFeature = true,
                                tier = tier,
                                category = category,
                                unitGroup = unitGroup,
                                distance = distance,
                                value = (originalDef.metalCost or 0) * METAL_WEIGHT + 
                                       (originalDef.energyCost or 0) * ENERGY_WEIGHT,
                                originalDefID = originalDef.id
                            })
                        end
                    end
                else
                    -- Reclaimable features - use value-based tiers
                    local metal, _, energy = Spring.GetFeatureResources(featureID)
                    if metal or energy then
                        local value = (metal or 0) * METAL_WEIGHT + (energy or 0) * ENERGY_WEIGHT
                        
                        -- Pseudo-tier based on value
                        local tier = 1
                        if value > 1000 then
                            tier = 4
                        elseif value > 500 then
                            tier = 3
                        elseif value > 100 then
                            tier = 2
                        end
                        
                        -- Try to detect if it's an eco wreck
                        local category = "other"
                        local name = featureDef.name or ""
                        if string.find(name, "mex") or string.find(name, "solar") or 
                           string.find(name, "wind") or string.find(name, "fusion") then
                            category = "resource"
                        end
                        
                        table.insert(tierFeatures[tier], {
                            id = featureID,
                            isFeature = true,
                            tier = tier,
                            category = category,
                            distance = distance,
                            value = value
                        })
                    end
                end
            end
        end
    end
    
    -- Apply tier filtering using helper
    return filterByTierPriority(tierFeatures, settings.tierFocus)
end

-- Priority calculators for other modes with universal hierarchy

local function calculateRepairPriority(settings)
    return function(candidate, distance)
        local priority = 0
        
        -- HIGHEST PRIORITY: Already built units that are damaged
        if candidate.isBuilt then
            priority = priority - 1000000  -- Massive priority for repairing built units
            
            if DEBUG_MODE then
                local unitDef = UnitDefs[candidate.defID]
                if unitDef and candidate.damage > 0.1 then
                    Spring.Echo("    HIGH PRIORITY REPAIR: " .. unitDef.name .. 
                              " (" .. (candidate.unitGroup or "other") .. ") damage=" .. 
                              math.floor(candidate.damage * 100) .. "%")
                end
            end
        else
            -- Under construction - lower priority
            if DEBUG_MODE then
                local unitDef = UnitDefs[candidate.defID]
                if unitDef then
                    Spring.Echo("    Low priority (constructing): " .. unitDef.name .. 
                              " (" .. (candidate.unitGroup or "other") .. ") progress=" .. 
                              math.floor(candidate.buildProgress * 100) .. "%")
                end
            end
        end
        
        -- Primary: Tier (already filtered in findRepairTargets)
        -- Tier ordering is handled by the order candidates are added
        
        -- Secondary: Unit group priority
        if candidate.unitGroup == "energy" or candidate.unitGroup == "metal" then
            priority = priority - 100000  -- Highest group priority
        elseif candidate.unitGroup == "utils" then
            priority = priority - 50000
        elseif candidate.unitGroup == "weapon" then
            priority = priority - 20000
        end
        
        -- Tertiary: Eco priority (resource category)
        if settings.ecoEnabled and candidate.category == "resource" then
            priority = priority - 10000  -- Eco boost within group
        end
        
        -- Quaternary: Damage level (more damage = higher priority)
        priority = priority - candidate.damage * 1000
        
        -- Distance is now handled separately as a strict tie-breaker
        -- No longer adding distance to priority calculation
        
        return priority
    end
end

local function calculateReclaimPriority(settings)
    return function(candidate, distance)
        local priority = 0
        
        -- Primary: Tier (already ordered in findFeatureTargets)
        
        -- Secondary: Unit group priority (if resurrectible)
        if candidate.unitGroup then
            if candidate.unitGroup == "energy" or candidate.unitGroup == "metal" then
                priority = priority - 100000  -- Highest group priority
            elseif candidate.unitGroup == "utils" then
                priority = priority - 50000
            elseif candidate.unitGroup == "weapon" then
                priority = priority - 20000
            end
        end
        
        -- Tertiary: Eco priority
        if settings.ecoEnabled and candidate.category == "resource" then
            priority = priority - 10000  -- Eco boost
        end
        
        -- Quaternary: Value
        priority = priority - candidate.value
        
        -- Distance is now handled separately as a strict tie-breaker
        -- No longer adding distance to priority calculation
        
        return priority
    end
end

local function calculateResurrectPriority(settings)
    return function(candidate, distance)
        local priority = 0
        
        -- Primary: Tier (already ordered in findFeatureTargets)
        
        -- Secondary: Unit group priority
        if candidate.unitGroup then
            if candidate.unitGroup == "energy" or candidate.unitGroup == "metal" then
                priority = priority - 100000  -- Highest group priority
            elseif candidate.unitGroup == "utils" then
                priority = priority - 50000
            elseif candidate.unitGroup == "weapon" then
                priority = priority - 20000
            end
        end
        
        -- Tertiary: Eco priority
        if settings.ecoEnabled and candidate.category == "resource" then
            priority = priority - 10000  -- Eco boost
        end
        
        -- Quaternary: Unit value
        priority = priority - candidate.value
        
        -- Distance is now handled separately as a strict tie-breaker
        -- No longer adding distance to priority calculation
        
        return priority
    end
end

--------------------------------------------------------------------------------
-- MAIN PROCESSING
--------------------------------------------------------------------------------

local function processSingleTurret(turretID, settings, currentFrame, forceProcess)
    -- If ALL options are OFF/disabled, don't touch the turret at all
    -- BUT: Always process if forceProcess is true (from button clicks)
    if not forceProcess and 
       settings.mode == PRIORITY_MODES.OFF and 
       settings.tierFocus == "NONE" and 
       not settings.ecoEnabled then
        return  -- Widget completely hands off
    end
    
    -- Skip if manually overridden
    if manualOverrides[turretID] and manualOverrides[turretID] > currentFrame then
        if DEBUG_MODE then
            Spring.Echo("Turret " .. turretID .. " skipped - manual override")
        end
        return
    end
    
    -- Smart guard command handling
    if isGuardingActiveUnit(turretID) then
        -- Guard target is busy, keep helping it
        if DEBUG_MODE then
            Spring.Echo("Turret " .. turretID .. " continuing guard duty - target is active")
        end
        return  -- Let the guard command continue
    else
        local cmd, guardTarget = getCurrentCommand(turretID)
        if cmd and cmd.id == CMD.GUARD and guardTarget and Spring.ValidUnitID(guardTarget) then
            -- Guard target is idle, we can do other tasks
            if DEBUG_MODE then
                Spring.Echo("Turret " .. turretID .. " guard target idle - finding other work")
            end
        end
    end
    
    local turretDefID = Spring.GetUnitDefID(turretID)
    if not turretDefID then return end
    
    local buildRange = UnitDefs[turretDefID].buildDistance or 128
    local pos = Validate.getPosition(turretID)
    if not pos then return end
    
    local target = nil
    local cmdID = CMD.REPAIR
    
    -- Priority-based action system with fallbacks
    if settings.mode == PRIORITY_MODES.OFF then
        -- OFF: No action priority, just find any construction work with tier/eco filters
        target = findBuildTargets(turretID, settings)
        cmdID = CMD.REPAIR
        
    elseif settings.mode == PRIORITY_MODES.BUILD then
        -- BUILD: Prioritize construction, fallback to repairs
        target = findBuildTargets(turretID, settings)
        
        if not target then
            -- No construction available, try repairs as fallback
            target = findBestTargetGeneric(
                turretID, pos.x, pos.z, buildRange,
                function() return findRepairTargets(turretID, settings) end,
                calculateRepairPriority(settings)
            )
        end
        cmdID = CMD.REPAIR
        
    elseif settings.mode == PRIORITY_MODES.REPAIR then
        -- REPAIR: Prioritize repairs, fallback to construction
        target = findBestTargetGeneric(
            turretID, pos.x, pos.z, buildRange,
            function() return findRepairTargets(turretID, settings) end,
            calculateRepairPriority(settings)
        )
        
        if not target then
            -- No repairs needed, try construction as fallback
            target = findBuildTargets(turretID, settings)
        end
        cmdID = CMD.REPAIR
        
    elseif settings.mode == PRIORITY_MODES.RECLAIM then
        -- RECLAIM: Prioritize reclaim, fallback to construction
        target = findBestTargetGeneric(
            turretID, pos.x, pos.z, buildRange,
            function() return findFeatureTargets(pos.x, pos.z, buildRange, false, settings) end,
            calculateReclaimPriority(settings)
        )
        
        if target then
            cmdID = CMD.RECLAIM
        else
            -- No reclaim available, try construction as fallback
            target = findBuildTargets(turretID, settings)
            cmdID = CMD.REPAIR
        end
        
    elseif settings.mode == PRIORITY_MODES.RESURRECT then
        -- RESURRECT: Prioritize resurrect, fallback to construction
        target = findBestTargetGeneric(
            turretID, pos.x, pos.z, buildRange,
            function() return findFeatureTargets(pos.x, pos.z, buildRange, true, settings) end,
            calculateResurrectPriority(settings)
        )
        
        if target then
            cmdID = CMD.RESURRECT
        else
            -- No resurrect available, try construction as fallback
            target = findBuildTargets(turretID, settings)
            cmdID = CMD.REPAIR
        end
    end
    
    -- Issue command or stop
    if target then
        -- Check current command (could be REPAIR, RECLAIM, or RESURRECT)
        local currentCmd, currentTarget = getCurrentCommand(turretID)
        local currentCmdID = currentCmd and currentCmd.id or nil
        
        -- For turrets, valid commands are REPAIR, RECLAIM, RESURRECT
        if currentCmd and (currentCmd.id == CMD.REPAIR or 
                           currentCmd.id == CMD.RECLAIM or 
                           currentCmd.id == CMD.RESURRECT) then
            currentTarget = currentCmd.params and currentCmd.params[1] or nil
        else
            currentTarget = nil
            currentCmdID = nil
        end
        
        if DEBUG_MODE then
            Spring.Echo("  -> Current command: " .. (currentCmdID or "none") .. 
                        " target: " .. tostring(currentTarget))
        end
        
        if DEBUG_MODE then
            Spring.Echo("  -> Comparing IDs: current=" .. tostring(currentTarget) .. 
                       " vs new=" .. tostring(target) .. " (equal=" .. tostring(currentTarget == target) .. ")")
            
            if currentTarget then
                local currentDefID = Spring.GetUnitDefID(currentTarget)
                local targetDefID = Spring.GetUnitDefID(target)
                if currentDefID and targetDefID then
                    local currentDef = UnitDefs[currentDefID]
                    local targetDef = UnitDefs[targetDefID]
                    if currentDef and targetDef then
                        local currentTier = getUnitTier(currentDefID)
                        local targetTier = getUnitTier(targetDefID)
                        if currentTarget ~= target then
                            Spring.Echo("SWITCHING: " .. currentDef.name .. " (T" .. currentTier .. 
                                       ") ID=" .. currentTarget .. " -> " .. targetDef.name .. 
                                       " (T" .. targetTier .. ") ID=" .. target)
                        else
                            Spring.Echo("KEEPING: " .. currentDef.name .. " (T" .. currentTier .. 
                                       ") ID=" .. currentTarget .. " [same as selected]")
                        end
                    end
                else
                    Spring.Echo("     Warning: Could not get unit defs for comparison")
                end
            else
                Spring.Echo("     No current target (turret idle or non-repair command)")
            end
        end
        
        -- Check if we need to switch (different target OR different command type)
        local needSwitch = false
        
        if not currentTarget then
            -- No current target, definitely need to set one
            needSwitch = true
        elseif currentTarget ~= target then
            -- Different target
            needSwitch = true
        elseif currentCmdID ~= cmdID then
            -- Same target but different command type (e.g., switching from REPAIR to RECLAIM)
            needSwitch = true
            if DEBUG_MODE then
                Spring.Echo("  -> Command type change: " .. currentCmdID .. " -> " .. cmdID)
            end
        end
        
        if needSwitch then
            -- Force stop all current actions
            forceStopTurret(turretID)
            
            -- Use INSERT to put new command at front of queue (like auto_repair does)
            -- Format: {position, commandID, options, params...}
            -- Position 0 = front of queue, options 0 = no modifiers
            Spring.GiveOrderToUnit(turretID, CMD_INSERT, {0, cmdID, 0, target}, {"alt"})
            
            if DEBUG_MODE then
                local action = cmdID == CMD.REPAIR and "REPAIR" or
                               cmdID == CMD.RECLAIM and "RECLAIM" or
                               cmdID == CMD.RESURRECT and "RESURRECT" or "UNKNOWN"
                Spring.Echo("  -> Switched to " .. action .. " target " .. tostring(target) .. 
                            " (was: " .. tostring(currentTarget) .. ")")
                
                -- Verify the command was accepted
                local newCmd, newTarget = getCurrentCommand(turretID)
                if newCmd then
                    Spring.Echo("    Verification: New command is " .. newCmd.id .. 
                               " targeting " .. tostring(newCmd.params and newCmd.params[1] or "nil"))
                    if newCmd.params and newCmd.params[1] ~= target then
                        Spring.Echo("    WARNING: Command didn't stick! Expected " .. target .. 
                                   " but got " .. tostring(newCmd.params[1]))
                    end
                else
                    Spring.Echo("    WARNING: No command after switch!")
                end
            end
        elseif DEBUG_MODE then
            Spring.Echo("  -> Keeping current target and command")
        end
        
        -- Show selection info when tier focus is active (only in debug mode)
        if DEBUG_MODE and (settings.tierFocus ~= "NONE") then
            local targetDefID = Spring.GetUnitDefID(target)
            local targetName = "unknown"
            if targetDefID then
                local targetDef = UnitDefs[targetDefID]
                if targetDef then
                    local tier = getUnitTier(targetDefID)
                    targetName = targetDef.name .. " (T" .. tier .. ")"
                end
            end
            Spring.Echo("✓ Turret " .. turretID .. " [" .. MODE_CONFIG[settings.mode].name .. 
                       " + " .. settings.tierFocus .. " tier] selected: " .. targetName)
        end
    else
        Spring.GiveOrderToUnit(turretID, CMD_STOP, {}, {})
    end
end

local function processTurrets(specificTurrets, forceProcess)
    local currentFrame = Spring.GetGameFrame()
    local toProcess = specificTurrets or {}
    
    -- If no specific turrets, process all watched turrets
    if #toProcess == 0 then
        for turretID in pairs(watchedTurrets) do
            if Validate.isAlive(turretID) then
                table.insert(toProcess, turretID)
            else
                watchedTurrets[turretID] = nil
                turretSettings[turretID] = nil
            end
        end
    end
    
    if DEBUG_MODE and #toProcess > 0 then
        Spring.Echo("=== UPDATE CYCLE: Processing " .. #toProcess .. " turrets at frame " .. currentFrame .. " ===")
    end
    
    -- Process each turret with its individual settings
    for _, turretID in ipairs(toProcess) do
        local settings = getTurretSettings(turretID)
        processSingleTurret(turretID, settings, currentFrame, forceProcess)
    end
end

--------------------------------------------------------------------------------
-- UI STATE MANAGEMENT
--------------------------------------------------------------------------------

local function getSelectedTurretsState()
    local selected = Spring.GetSelectedUnits()
    local turrets = filterTurrets(selected)
    
    if #turrets == 0 then return nil end
    if #turrets == 1 then 
        return getTurretSettings(turrets[1]), false
    end
    
    -- Check for mixed states
    local firstSettings = getTurretSettings(turrets[1])
    local mixed = false
    
    for i = 2, #turrets do
        local settings = getTurretSettings(turrets[i])
        if settings.mode ~= firstSettings.mode or
           settings.ecoEnabled ~= firstSettings.ecoEnabled or
           settings.tierFocus ~= firstSettings.tierFocus then
            mixed = true
            break
        end
    end
    
    return firstSettings, mixed
end

--------------------------------------------------------------------------------
-- ACTION HANDLERS (DRY)
--------------------------------------------------------------------------------

local ACTION_HANDLERS = {}

-- Create action handlers dynamically
for mode = 1, 4 do
    ACTION_HANDLERS["mode_" .. mode] = function()
        local turrets = filterTurrets(Spring.GetSelectedUnits())
        for _, turretID in ipairs(turrets) do
            local settings = getTurretSettings(turretID)
            settings.mode = mode
            -- Force stop to trigger re-evaluation
            forceStopTurret(turretID)
        end
        Spring.Echo("Turret Manager: " .. MODE_CONFIG[mode].message .. " for " .. #turrets .. " turret(s)")
        processTurrets(turrets, true)  -- Force process on button click
    end
end

ACTION_HANDLERS.toggle_eco = function()
    local turrets = filterTurrets(Spring.GetSelectedUnits())
    for _, turretID in ipairs(turrets) do
        local settings = getTurretSettings(turretID)
        settings.ecoEnabled = not settings.ecoEnabled
        -- Force stop to trigger re-evaluation (even when Action is OFF)
        forceStopTurret(turretID)
        -- Clear any manual override that might be blocking
        manualOverrides[turretID] = nil
    end
    local state = getTurretSettings(turrets[1]).ecoEnabled
    Spring.Echo("Turret Manager: Eco " .. (state and "ON" or "OFF") .. " for " .. #turrets .. " turret(s)")
    processTurrets(turrets, true)  -- Force process on button click
end

ACTION_HANDLERS.toggle_tier = function()
    local turrets = filterTurrets(Spring.GetSelectedUnits())
    local tierValues = {"NONE", "LOW", "HIGH"}
    
    for _, turretID in ipairs(turrets) do
        local settings = getTurretSettings(turretID)
        settings.tierFocus = cycleValue(settings.tierFocus, tierValues)
        -- Force stop to trigger re-evaluation
        forceStopTurret(turretID)
    end
    
    local newFocus = getTurretSettings(turrets[1]).tierFocus
    local message = "Tier focus: " .. (newFocus == "NONE" and "disabled" or 
                    newFocus == "LOW" and "LowTier (T1→T4)" or "HighTier (T4→T1)")
    Spring.Echo("Turret Manager: " .. message .. " for " .. #turrets .. " turret(s)")
    processTurrets(turrets, true)  -- Force process on button click
end

--------------------------------------------------------------------------------
-- WIDGET EVENT HANDLERS
--------------------------------------------------------------------------------

function widget:Initialize()
    -- Set up internationalization for button labels
    local i18n = Spring.I18N
    if i18n then
        -- Smart Mode button labels
        i18n.set("en.ui.orderMenu.Action Focus", "Action Focus")
        i18n.set("en.ui.orderMenu.Build", "Build")
        i18n.set("en.ui.orderMenu.Repair", "Repair")
        i18n.set("en.ui.orderMenu.Reclaim", "Reclaim")
        i18n.set("en.ui.orderMenu.Resurrect", "Resurrect")
        
        -- ECO Priority button labels
        i18n.set("en.ui.orderMenu.Eco Focus", "Eco Focus")
        
        -- Tier Focus button labels
        i18n.set("en.ui.orderMenu.Tier Focus", "Tier Focus")
        i18n.set("en.ui.orderMenu.LowTier", "LowTier")
        i18n.set("en.ui.orderMenu.HighTier", "HighTier")
        
        -- Tooltips
        i18n.set("en.ui.orderMenu.smartturrets_mode_tooltip", "Priority mode: OFF → Build → Repair → Reclaim → Resurrect")
        i18n.set("en.ui.orderMenu.smartturrets_eco_tooltip", "Toggle economic building priority in Build mode")
        i18n.set("en.ui.orderMenu.smartturrets_tier_tooltip", "Tier Focus: None | LowTier: T1→T2→T3→T4 | HighTier: T4→T3→T2→T1")
    end
    
    -- Discover turret types
    discoverConstructionTurrets()
    
    -- Register actions for hotkeys
    if widgetHandler.actionHandler and widgetHandler.actionHandler.AddAction then
        for name, handler in pairs(ACTION_HANDLERS) do
            widgetHandler.actionHandler:AddAction(self, "smartturrets_" .. name, handler, nil, "p")
        end
    end
    
    Spring.Echo("Turret Manager: Initialized with smart targeting system")
    Spring.Echo("  ECO OFF: Action → Tier → Utils>Weapon>AA>Builder → Distance")
    Spring.Echo("  ECO ON: Action → Tier → Energy/Metal>Utils>Weapon>AA>Builder → Distance")
    Spring.Echo("  Select turrets to see control buttons")
    Spring.Echo("  Each turret maintains its own settings")
    Spring.Echo("  Press Ctrl+Shift+D for debug mode")
    
    if DEBUG_MODE then
        Spring.Echo("  Command constant values:")
        Spring.Echo("    CMD_STOP = " .. tostring(CMD_STOP) .. " (should be 0)")
        Spring.Echo("    CMD_REPAIR = " .. tostring(CMD_REPAIR) .. " (should be 40)")
        Spring.Echo("    CMD_RECLAIM = " .. tostring(CMD_RECLAIM) .. " (should be 90)")
        Spring.Echo("    CMD_RESURRECT = " .. tostring(CMD_RESURRECT) .. " (should be 125)")
        Spring.Echo("    CMD_INSERT = " .. tostring(CMD_INSERT) .. " (should be 1)")
        Spring.Echo("    CMD_REMOVE = " .. tostring(CMD_REMOVE) .. " (should be 2)")
    end
    
    -- Find existing turrets
    local myTeamID = Spring.GetMyTeamID()
    local turretCount = 0
    for _, unitID in ipairs(Spring.GetTeamUnits(myTeamID)) do
        local defID = Spring.GetUnitDefID(unitID)
        if defID and turretDefIDs[defID] then
            watchedTurrets[unitID] = true
            turretCount = turretCount + 1
            
            local unitDef = UnitDefs[defID]
            if DEBUG_MODE and unitDef then
                Spring.Echo("  Found turret: " .. unitDef.name .. " (ID: " .. unitID .. ")")
            end
        end
    end
    
    Spring.Echo("Turret Manager: Managing " .. turretCount .. " construction turrets")
    
    -- Debug: Show discovered turret types
    if turretCount == 0 then
        Spring.Echo("WARNING: No construction turrets found!")
        Spring.Echo("  Discovered turret types:")
        for defID in pairs(turretDefIDs) do
            local unitDef = UnitDefs[defID]
            if unitDef then
                Spring.Echo("    - " .. unitDef.name)
            end
        end
    end
end

function widget:CommandsChanged()
    local selectedUnits = Spring.GetSelectedUnits()
    if not selectedUnits or #selectedUnits == 0 then return end
    
    local turrets = filterTurrets(selectedUnits)
    if #turrets == 0 then return end
    
    -- Get state of selected turrets
    local state, mixed = getSelectedTurretsState()
    if not state then return end
    
    -- Update button states
    local cmds = widgetHandler.customCommands
    
    -- Smart Mode button
    CMD_SMART_MODE_DESC.params[1] = mixed and 0 or state.mode
    if mixed then
        CMD_SMART_MODE_DESC.tooltip = "Mixed modes - click to synchronize"
    else
        CMD_SMART_MODE_DESC.tooltip = "Priority mode: OFF → Build → Repair → Reclaim → Resurrect"
    end
    
    -- ECO button
    CMD_ECO_PRIORITY_DESC.params[1] = mixed and 0 or (state.ecoEnabled and 1 or 0)
    
    -- Tier button
    local tierState = 0
    if not mixed then
        if state.tierFocus == "LOW" then tierState = 1
        elseif state.tierFocus == "HIGH" then tierState = 2
        end
    end
    CMD_TIER_FOCUS_DESC.params[1] = tierState
    
    cmds[#cmds + 1] = CMD_SMART_MODE_DESC
    cmds[#cmds + 1] = CMD_ECO_PRIORITY_DESC
    cmds[#cmds + 1] = CMD_TIER_FOCUS_DESC
    
    if DEBUG_MODE then
        Spring.Echo("Added turret buttons - Smart Mode ID: " .. CMD_SMART_MODE_DESC.id .. 
                   ", Eco ID: " .. CMD_ECO_PRIORITY_DESC.id .. 
                   ", Tier ID: " .. CMD_TIER_FOCUS_DESC.id)
    end
end

function widget:CommandNotify(cmdID, cmdParams, cmdOptions)
    if DEBUG_MODE then
        Spring.Echo("CommandNotify called with cmdID: " .. tostring(cmdID) .. 
                   " (SMART=" .. CMD_SMART_MODE .. ", ECO=" .. CMD_ECO_PRIORITY .. 
                   ", TIER=" .. CMD_TIER_FOCUS .. ")")
    end
    
    local turrets = filterTurrets(Spring.GetSelectedUnits())
    if #turrets == 0 then return false end
    
    if cmdID == CMD_SMART_MODE then
        -- Cycle mode for selected turrets
        for _, turretID in ipairs(turrets) do
            local settings = getTurretSettings(turretID)
            settings.mode = (settings.mode + 1) % 5
            -- Force stop to trigger re-evaluation
            forceStopTurret(turretID)
        end
        
        local newMode = getTurretSettings(turrets[1]).mode
        Spring.Echo("Turret Manager: " .. MODE_CONFIG[newMode].display .. " for " .. #turrets .. " turret(s)")
        processTurrets(turrets, true)  -- Force process on button click
        return true
        
    elseif cmdID == CMD_ECO_PRIORITY then
        -- Toggle eco for selected turrets
        for _, turretID in ipairs(turrets) do
            local settings = getTurretSettings(turretID)
            settings.ecoEnabled = not settings.ecoEnabled
            -- Force stop to trigger re-evaluation
            forceStopTurret(turretID)
        end
        
        local state = getTurretSettings(turrets[1]).ecoEnabled
        Spring.Echo("Turret Manager: Eco " .. (state and "ON" or "OFF") .. " for " .. #turrets .. " turret(s)")
        processTurrets(turrets, true)  -- Force process on button click
        return true
        
    elseif cmdID == CMD_TIER_FOCUS then
        -- Cycle tier focus for selected turrets
        local tierValues = {"NONE", "LOW", "HIGH"}
        
        for _, turretID in ipairs(turrets) do
            local settings = getTurretSettings(turretID)
            settings.tierFocus = cycleValue(settings.tierFocus, tierValues)
            -- Force stop to trigger re-evaluation
            forceStopTurret(turretID)
        end
        
        local newFocus = getTurretSettings(turrets[1]).tierFocus
        local message = newFocus == "NONE" and "disabled" or 
                       newFocus == "LOW" and "LowTier" or "HighTier"
        Spring.Echo("Turret Manager: Tier " .. message .. " (value: '" .. newFocus .. "') for " .. #turrets .. " turret(s)")
        processTurrets(turrets, true)  -- Force process on button click
        return true
    end
    
    -- Only track STOP commands as manual override (not repair/move/etc)
    if cmdID == CMD_STOP then
        local currentFrame = Spring.GetGameFrame()
        for _, turretID in ipairs(turrets) do
            manualOverrides[turretID] = currentFrame + 30  -- Only 1 second pause
            if DEBUG_MODE then
                Spring.Echo("Manual stop for turret " .. turretID .. " - pausing for 1 second")
            end
        end
    end
    
    return false
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
    if unitTeam == Spring.GetMyTeamID() and turretDefIDs[unitDefID] then
        watchedTurrets[unitID] = true
        if DEBUG_MODE then
            Spring.Echo("V4: New turret added: " .. unitID)
        end
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    if unitTeam == Spring.GetMyTeamID() then
        watchedTurrets[unitID] = nil
        turretSettings[unitID] = nil
        manualOverrides[unitID] = nil
    end
end

function widget:DrawWorld()
    -- Draw mode indicators on selected turrets (always) and all turrets (debug mode)
    local selectedUnits = Spring.GetSelectedUnits()
    local selectedTurrets = {}
    
    -- Get camera distance for line width scaling
    local camX, camY, camZ = Spring.GetCameraPosition()
    local camHeight = camY or 1000  -- Default if camera position unavailable
    
    -- Build set of selected turrets for quick lookup
    for _, unitID in ipairs(selectedUnits) do
        local defID = Spring.GetUnitDefID(unitID)
        if defID and turretDefIDs[defID] then
            selectedTurrets[unitID] = true
        end
    end
    
    -- Draw indicators
    for turretID in pairs(watchedTurrets) do
        if Validate.isAlive(turretID) then
            local settings = getTurretSettings(turretID)
            
            -- Show indicators if ANY setting is active (action, tier, or eco)
            local hasActiveSettings = settings.mode ~= PRIORITY_MODES.OFF or 
                                    settings.tierFocus ~= "NONE" or 
                                    settings.ecoEnabled
            
            -- Always show indicators for turrets with active settings
            if hasActiveSettings then
                    local config = MODE_CONFIG[settings.mode]
                    local pos = Validate.getPosition(turretID)
                    if pos then
                        -- Calculate line width scaling based on camera distance
                        -- At height 500: scale = 1.0, at height 2000: scale = 0.5
                        local distanceScale = math.min(2.0, math.max(0.3, 800 / camHeight))
                        
                        -- Main action circle (only if action mode is active)
                        if config and settings.mode ~= PRIORITY_MODES.OFF then
                            gl.LineWidth(2.5 * distanceScale)
                            gl.Color(config.color[1], config.color[2], config.color[3], config.color[4])
                            gl.DrawGroundCircle(pos.x, pos.y, pos.z, 15, 20)  -- Reduced from 25 to 15 (40% reduction)
                        end
                        
                        -- Tier indicator (radiating lines)
                        if settings.tierFocus ~= "NONE" then
                            gl.LineWidth(3.5 * distanceScale)  -- Scaled line width
                            
                            if settings.tierFocus == "LOW" then
                                gl.Color(0.9, 0.9, 0.2, 0.9)  -- Yellow for Low Tier
                                -- 8 lines evenly spread around a circle
                                gl.BeginEnd(GL.LINES, function()
                                    for i = 0, 7 do
                                        local angle = math.rad(i * 45)  -- 8 lines = 360/8 = 45 degrees apart
                                        local dx = math.cos(angle) * 21
                                        local dz = math.sin(angle) * 21
                                        gl.Vertex(pos.x, pos.y, pos.z)
                                        gl.Vertex(pos.x + dx, pos.y, pos.z + dz)
                                    end
                                end)
                            else  -- HIGH
                                gl.Color(0.9, 0.2, 0.2, 0.9)  -- Red for High Tier
                                -- 16 lines (double lines at 8 positions)
                                gl.BeginEnd(GL.LINES, function()
                                    for i = 0, 7 do
                                        local angle = math.rad(i * 45)  -- 8 positions = 45 degrees apart
                                        -- Calculate perpendicular offset for double lines
                                        local perpAngle = angle + math.rad(90)
                                        local offsetX = math.cos(perpAngle) * 1.5
                                        local offsetZ = math.sin(perpAngle) * 1.5
                                        
                                        local dx = math.cos(angle) * 21
                                        local dz = math.sin(angle) * 21
                                        
                                        -- First line of the pair
                                        gl.Vertex(pos.x + offsetX, pos.y, pos.z + offsetZ)
                                        gl.Vertex(pos.x + offsetX + dx, pos.y, pos.z + offsetZ + dz)
                                        
                                        -- Second line of the pair
                                        gl.Vertex(pos.x - offsetX, pos.y, pos.z - offsetZ)
                                        gl.Vertex(pos.x - offsetX + dx, pos.y, pos.z - offsetZ + dz)
                                    end
                                end)
                            end
                        end
                        
                        -- Eco indicator (dashed green outer ring)
                        if settings.ecoEnabled then
                            gl.LineWidth(3.0 * distanceScale)  -- Scaled line width
                            gl.Color(0.2, 0.9, 0.2, 0.9)  -- Green
                            drawDashedCircle(pos.x, pos.y, pos.z, 20, 10, 5)  -- radius 20, 10° dash, 5° gap
                        end
                    end
            end
        end
    end
    gl.LineWidth(1.0)
end

function widget:GameFrame(n)
    -- Throttled turret updates
    updateTurrets(processTurrets)
end

function widget:KeyPress(key, mods, isRepeat)
    if key == string.byte('D') and mods.ctrl and mods.shift then
        DEBUG_MODE = not DEBUG_MODE
        Spring.Echo("V4: Debug mode " .. (DEBUG_MODE and "ON" or "OFF"))
        return true
    end
end

function widget:Shutdown()
    -- Clean up action handlers
    if widgetHandler.actionHandler and widgetHandler.actionHandler.RemoveAction then
        for name in pairs(ACTION_HANDLERS) do
            widgetHandler.actionHandler:RemoveAction(self, "smartturrets_" .. name, "p")
        end
    end
    
    -- Clear all data
    turretSettings = {}
    watchedTurrets = {}
    manualOverrides = {}
end
