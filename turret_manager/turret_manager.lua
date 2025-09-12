--[[
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 TURRET MANAGER - Intelligent Nano Turret Automation & Control
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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
        name = "🎯 Turret Manager",
        desc = "Intelligent nano turret automation with tier control and visual feedback",
        author = "augustin, enhanced by Waleed via Claude Code",
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
local DEBUG_MODE = true

--------------------------------------------------------------------------------
-- COMMAND DEFINITIONS
--------------------------------------------------------------------------------

-- Spring Command Constants (REQUIRED!)
local CMD_STOP = CMD.STOP
local CMD_REPAIR = CMD.REPAIR
local CMD_RECLAIM = CMD.RECLAIM
local CMD_RESURRECT = CMD.RESURRECT
local CMD_GUARD = CMD.GUARD
local CMD_MOVE = CMD.MOVE
local CMD_BUILD = CMD.BUILD

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
    
    local tier = 1
    
    -- Check custom params first (try both cases)
    if unitDef.customParams then
        if unitDef.customParams.techlevel then
            tier = tonumber(unitDef.customParams.techlevel) or 1
        elseif unitDef.customParams.techLevel then  -- Check camelCase version
            tier = tonumber(unitDef.customParams.techLevel) or 1
        end
    -- Also check lowercase version
    elseif unitDef.customparams then
        if unitDef.customparams.techlevel then
            tier = tonumber(unitDef.customparams.techlevel) or 1
        elseif unitDef.customparams.techLevel then  -- Check camelCase version
            tier = tonumber(unitDef.customparams.techLevel) or 1
        end
    end
    
    -- If no techlevel found, use cost-based detection
    if tier == 1 and unitDef.metalCost then
        local cost = unitDef.metalCost
        local name = unitDef.name or ""
        
        -- Cost thresholds (approximate)
        if cost > 10000 or string.find(name, "[tT]4") or string.find(name, "exp") then
            tier = 4
        elseif cost > 2000 or string.find(name, "[tT]3") or string.find(name, "afus") then
            tier = 3  
        elseif cost > 500 or string.find(name, "[tT]2") or string.find(name, "adv") then
            tier = 2
        end
    end
    
    if DEBUG_MODE then
        Spring.Echo("V4 Tier: " .. unitDef.name .. " = T" .. tier .. " (cost: " .. (unitDef.metalCost or 0) .. ")")
    end
    
    UNIT_TIERS[unitDefID] = tier
    return tier
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

-- Generic target finder (DRY pattern)
local function findBestTargetGeneric(turretID, turretX, turretZ, buildRange, candidateGetter, priorityCalc)
    local bestTarget = nil
    local bestPriority = math.huge
    
    for _, candidate in ipairs(candidateGetter()) do
        local pos = candidate.pos or Validate.getPosition(candidate.id, candidate.isFeature)
        
        if pos then
            local dist = Distance.exact(turretX, turretZ, pos.x, pos.z)
            local radius = candidate.radius or 8
            
            if dist <= buildRange + radius + RANGE_BUFFER then
                local priority = priorityCalc(candidate, dist)
                if priority < bestPriority then
                    bestTarget = candidate.id
                    bestPriority = priority
                end
            end
        end
    end
    
    return bestTarget
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
            
            if buildProgress and buildProgress > 0.01 and buildProgress < 0.99 then
                local unitDefID = Spring.GetUnitDefID(unitID)
                if unitDefID then
                    local tier = getUnitTier(unitDefID)
                    local category = getUnitCategory(unitDefID)
                    local ux, _, uz = Spring.GetUnitPosition(unitID)
                    if ux and uz then
                        local distance = Distance.exact(tx, tz, ux, uz)
                        
                        if DEBUG_MODE then
                            local unitDef = UnitDefs[unitDefID]
                            if unitDef then
                                local catSymbol = category == "resource" and "💰" or 
                                                 category == "defense" and "🛡️" or
                                                 category == "intel" and "📡" or
                                                 category == "factory" and "🏭" or
                                                 category == "builder" and "🔧" or
                                                 category == "assist" and "🤖" or "🏗️"
                                Spring.Echo("  Found: " .. unitDef.name .. " = T" .. tier .. 
                                          " " .. catSymbol .. "(" .. category .. ") progress=" .. math.floor(buildProgress * 100) .. 
                                          "% at " .. math.floor(distance) .. " range")
                            end
                        end
                        
                        -- Store unit with distance and category for later sorting
                        table.insert(tierUnits[tier], {
                            id = unitID,
                            distance = distance,
                            progress = buildProgress,
                            category = category
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
                   " T3=" .. #tierUnits[3] .. " T4=" .. #tierUnits[4])
        if currentTarget then
            local currentDefID = Spring.GetUnitDefID(currentTarget)
            if currentDefID then
                local currentTier = getUnitTier(currentDefID)
                local currentDef = UnitDefs[currentDefID]
                if currentDef then
                    Spring.Echo("  Current target: " .. currentDef.name .. " (T" .. currentTier .. ")")
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
        
        -- Apply ECO priority if enabled
        if settings.ecoEnabled then
            -- Separate resource and non-resource units
            local resourceUnits = {}
            local otherUnits = {}
            
            for _, unit in ipairs(units) do
                if unit.category == "resource" then
                    table.insert(resourceUnits, unit)
                else
                    table.insert(otherUnits, unit)
                end
            end
            
            if DEBUG_MODE then
                local tierLabel = selectedTier == "ALL" and "all tiers" or ("T" .. selectedTier)
                Spring.Echo("  ECO PRIORITY: Found " .. #resourceUnits .. " resource units and " .. 
                           #otherUnits .. " other units in " .. tierLabel)
                -- Show what we found
                for i, unit in ipairs(resourceUnits) do
                    local unitDefID = Spring.GetUnitDefID(unit.id)
                    local unitDef = unitDefID and UnitDefs[unitDefID]
                    if unitDef then
                        Spring.Echo("    Resource[" .. i .. "]: " .. unitDef.name .. " at " .. math.floor(unit.distance))
                    end
                end
                for i, unit in ipairs(otherUnits) do
                    if i <= 3 then  -- Only show first 3 to avoid spam
                        local unitDefID = Spring.GetUnitDefID(unit.id)
                        local unitDef = unitDefID and UnitDefs[unitDefID]
                        if unitDef then
                            Spring.Echo("    Other[" .. i .. "]: " .. unitDef.name .. " at " .. math.floor(unit.distance))
                        end
                    end
                end
            end
            
            -- Prioritize resource units if any exist
            if #resourceUnits > 0 then
                sortByDistance(resourceUnits)
                if DEBUG_MODE then
                    local targetDefID = Spring.GetUnitDefID(resourceUnits[1].id)
                    local targetDef = targetDefID and UnitDefs[targetDefID]
                    Spring.Echo("  -> ECO SELECTED: " .. (targetDef and targetDef.name or "unknown"))
                end
                return resourceUnits[1].id
            else
                if DEBUG_MODE then
                    Spring.Echo("  -> No resource units, using closest other unit")
                end
                units = otherUnits
            end
        end
        
        -- Sort by distance (closest first)
        sortByDistance(units)
        
        if DEBUG_MODE then
            local ecoStatus = settings.ecoEnabled and "[ECO ON]" or "[ECO OFF]"
            local tierLabel = selectedTier == "ALL" and "unit from all tiers" or ("T" .. selectedTier .. " unit")
            Spring.Echo("Selected " .. tierLabel .. " " .. ecoStatus .. " (out of " .. 
                       #tierUnits[1] .. " T1, " .. #tierUnits[2] .. " T2, " ..
                       #tierUnits[3] .. " T3, " .. #tierUnits[4] .. " T4)")
            local targetDefID = Spring.GetUnitDefID(units[1].id)
            if targetDefID and UnitDefs[targetDefID] then
                Spring.Echo("  -> Target: " .. UnitDefs[targetDefID].name)
            end
        end
        
        return units[1].id
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
                                              " (T" .. tier .. ") " .. 
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
                            
                            table.insert(tierFeatures[tier], {
                                id = featureID,
                                isFeature = true,
                                tier = tier,
                                category = category,
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
                              " damage=" .. math.floor(candidate.damage * 100) .. "%")
                end
            end
        else
            -- Under construction - lower priority
            if DEBUG_MODE then
                local unitDef = UnitDefs[candidate.defID]
                if unitDef then
                    Spring.Echo("    Low priority (constructing): " .. unitDef.name .. 
                              " progress=" .. math.floor(candidate.buildProgress * 100) .. "%")
                end
            end
        end
        
        -- Primary: Tier (already filtered in findRepairTargets)
        -- Tier ordering is handled by the order candidates are added
        
        -- Secondary: Eco priority within same tier
        if settings.ecoEnabled and candidate.category == "resource" then
            priority = priority - 100000  -- Strong eco preference
        end
        
        -- Tertiary: Damage level (more damage = higher priority)
        priority = priority - candidate.damage * 1000
        
        -- Final: Distance as tiebreaker
        priority = priority + distance / 10
        
        return priority
    end
end

local function calculateReclaimPriority(settings)
    return function(candidate, distance)
        local priority = 0
        
        -- Primary: Tier (already ordered in findFeatureTargets)
        
        -- Secondary: Eco priority
        if settings.ecoEnabled and candidate.category == "resource" then
            priority = priority - 100000  -- Strong eco preference
        end
        
        -- Tertiary: Value
        priority = priority - candidate.value
        
        -- Final: Distance as tiebreaker
        priority = priority + distance / 10
        
        return priority
    end
end

local function calculateResurrectPriority(settings)
    return function(candidate, distance)
        local priority = 0
        
        -- Primary: Tier (already ordered in findFeatureTargets)
        
        -- Secondary: Eco priority
        if settings.ecoEnabled and candidate.category == "resource" then
            priority = priority - 100000  -- Strong eco preference
        end
        
        -- Tertiary: Unit value
        priority = priority - candidate.value
        
        -- Final: Distance as tiebreaker
        priority = priority + distance / 10
        
        return priority
    end
end

--------------------------------------------------------------------------------
-- MAIN PROCESSING
--------------------------------------------------------------------------------

local function processSingleTurret(turretID, settings, currentFrame)
    -- If ALL options are OFF/disabled, don't touch the turret at all
    if settings.mode == PRIORITY_MODES.OFF and 
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
        -- Check if we need to switch targets
        local currentCmd, currentTarget = getCurrentCommand(turretID)
        
        if DEBUG_MODE and currentTarget then
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
                                   ") -> " .. targetDef.name .. " (T" .. targetTier .. ")")
                    elseif settings.tierFocus ~= "NONE" then
                        Spring.Echo("KEEPING: " .. currentDef.name .. " (T" .. currentTier .. 
                                   ") [best option: " .. targetDef.name .. " T" .. targetTier .. "]")
                    end
                end
            end
        end
        
        -- Only issue new command if target changed
        if currentTarget ~= target then
            -- Stop current action first to ensure clean switch
            Spring.GiveOrderToUnit(turretID, CMD_STOP, {}, {})
            -- Issue new command
            Spring.GiveOrderToUnit(turretID, cmdID, {target}, {})
        end
        
        -- Show selection info when tier focus is active
        if settings.tierFocus ~= "NONE" or DEBUG_MODE then
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
        Spring.GiveOrderToUnit(turretID, CMD.STOP, {}, {})
    end
end

local function processTurrets(specificTurrets)
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
        processSingleTurret(turretID, settings, currentFrame)
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
        end
        Spring.Echo("Turret Manager: " .. MODE_CONFIG[mode].message .. " for " .. #turrets .. " turret(s)")
        processTurrets(turrets)
    end
end

ACTION_HANDLERS.toggle_eco = function()
    local turrets = filterTurrets(Spring.GetSelectedUnits())
    for _, turretID in ipairs(turrets) do
        local settings = getTurretSettings(turretID)
        settings.ecoEnabled = not settings.ecoEnabled
    end
    local state = getTurretSettings(turrets[1]).ecoEnabled
    Spring.Echo("Turret Manager: Eco " .. (state and "ON" or "OFF") .. " for " .. #turrets .. " turret(s)")
    processTurrets(turrets)
end

ACTION_HANDLERS.toggle_tier = function()
    local turrets = filterTurrets(Spring.GetSelectedUnits())
    local tierValues = {"NONE", "LOW", "HIGH"}
    
    for _, turretID in ipairs(turrets) do
        local settings = getTurretSettings(turretID)
        settings.tierFocus = cycleValue(settings.tierFocus, tierValues)
    end
    
    local newFocus = getTurretSettings(turrets[1]).tierFocus
    local message = "Tier focus: " .. (newFocus == "NONE" and "disabled" or 
                    newFocus == "LOW" and "LowTier (T1→T4)" or "HighTier (T4→T1)")
    Spring.Echo("Turret Manager: " .. message .. " for " .. #turrets .. " turret(s)")
    processTurrets(turrets)
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
    
    Spring.Echo("Turret Manager: Initialized with UNIVERSAL priority hierarchy")
    Spring.Echo("  All modes follow: Action → Tier → Eco → Distance")
    Spring.Echo("  Select turrets to see control buttons")
    Spring.Echo("  Each turret maintains its own settings")
    Spring.Echo("  Press Ctrl+Shift+D for debug mode")
    
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
end

function widget:CommandNotify(cmdID, cmdParams, cmdOptions)
    local turrets = filterTurrets(Spring.GetSelectedUnits())
    if #turrets == 0 then return false end
    
    if cmdID == CMD_SMART_MODE then
        -- Cycle mode for selected turrets
        for _, turretID in ipairs(turrets) do
            local settings = getTurretSettings(turretID)
            settings.mode = (settings.mode + 1) % 5
        end
        
        local newMode = getTurretSettings(turrets[1]).mode
        Spring.Echo("Turret Manager: " .. MODE_CONFIG[newMode].display .. " for " .. #turrets .. " turret(s)")
        processTurrets(turrets)
        return true
        
    elseif cmdID == CMD_ECO_PRIORITY then
        -- Toggle eco for selected turrets
        for _, turretID in ipairs(turrets) do
            local settings = getTurretSettings(turretID)
            settings.ecoEnabled = not settings.ecoEnabled
        end
        
        local state = getTurretSettings(turrets[1]).ecoEnabled
        Spring.Echo("Turret Manager: Eco " .. (state and "ON" or "OFF") .. " for " .. #turrets .. " turret(s)")
        processTurrets(turrets)
        return true
        
    elseif cmdID == CMD_TIER_FOCUS then
        -- Cycle tier focus for selected turrets
        local tierValues = {"NONE", "LOW", "HIGH"}
        
        for _, turretID in ipairs(turrets) do
            local settings = getTurretSettings(turretID)
            settings.tierFocus = cycleValue(settings.tierFocus, tierValues)
        end
        
        local newFocus = getTurretSettings(turrets[1]).tierFocus
        local message = newFocus == "NONE" and "disabled" or 
                       newFocus == "LOW" and "LowTier" or "HighTier"
        Spring.Echo("Turret Manager: Tier " .. message .. " (value: '" .. newFocus .. "') for " .. #turrets .. " turret(s)")
        processTurrets(turrets)
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
            -- Show for selected turrets always, or all turrets in debug mode
            if selectedTurrets[turretID] or DEBUG_MODE then
                local settings = getTurretSettings(turretID)
                local config = MODE_CONFIG[settings.mode]
                
                -- Show indicators if ANY setting is active (action, tier, or eco)
                local shouldDraw = settings.mode ~= PRIORITY_MODES.OFF or 
                                 settings.tierFocus ~= "NONE" or 
                                 settings.ecoEnabled
                
                if shouldDraw then
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
                                -- Single lines radiating from 4 sides (from center)
                                gl.BeginEnd(GL.LINES, function()
                                    -- Top line
                                    gl.Vertex(pos.x, pos.y, pos.z)
                                    gl.Vertex(pos.x, pos.y, pos.z - 21)  -- Reduced from 35 to 21
                                    -- Bottom line
                                    gl.Vertex(pos.x, pos.y, pos.z)
                                    gl.Vertex(pos.x, pos.y, pos.z + 21)  -- Reduced from 35 to 21
                                    -- Left line
                                    gl.Vertex(pos.x, pos.y, pos.z)
                                    gl.Vertex(pos.x - 21, pos.y, pos.z)  -- Reduced from 35 to 21
                                    -- Right line
                                    gl.Vertex(pos.x, pos.y, pos.z)
                                    gl.Vertex(pos.x + 21, pos.y, pos.z)  -- Reduced from 35 to 21
                                end)
                            else  -- HIGH
                                gl.Color(0.9, 0.2, 0.2, 0.9)  -- Red for High Tier
                                -- Double lines radiating from 4 sides (from center)
                                gl.BeginEnd(GL.LINES, function()
                                    -- Top double lines
                                    gl.Vertex(pos.x - 1.5, pos.y, pos.z)
                                    gl.Vertex(pos.x - 1.5, pos.y, pos.z - 21)  -- Reduced from 35 to 21
                                    gl.Vertex(pos.x + 1.5, pos.y, pos.z)
                                    gl.Vertex(pos.x + 1.5, pos.y, pos.z - 21)  -- Reduced from 35 to 21
                                    
                                    -- Bottom double lines
                                    gl.Vertex(pos.x - 1.5, pos.y, pos.z)
                                    gl.Vertex(pos.x - 1.5, pos.y, pos.z + 21)  -- Reduced from 35 to 21
                                    gl.Vertex(pos.x + 1.5, pos.y, pos.z)
                                    gl.Vertex(pos.x + 1.5, pos.y, pos.z + 21)  -- Reduced from 35 to 21
                                    
                                    -- Left double lines
                                    gl.Vertex(pos.x, pos.y, pos.z - 1.5)
                                    gl.Vertex(pos.x - 21, pos.y, pos.z - 1.5)  -- Reduced from 35 to 21
                                    gl.Vertex(pos.x, pos.y, pos.z + 1.5)
                                    gl.Vertex(pos.x - 21, pos.y, pos.z + 1.5)  -- Reduced from 35 to 21
                                    
                                    -- Right double lines
                                    gl.Vertex(pos.x, pos.y, pos.z - 1.5)
                                    gl.Vertex(pos.x + 21, pos.y, pos.z - 1.5)  -- Reduced from 35 to 21
                                    gl.Vertex(pos.x, pos.y, pos.z + 1.5)
                                    gl.Vertex(pos.x + 21, pos.y, pos.z + 1.5)  -- Reduced from 35 to 21
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
