--------------------------------------------------------------------------------
-- Build Time Estimator v2 Widget for Beyond All Reason
--------------------------------------------------------------------------------
-- Copyright (C) 2024 Pyrem
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along
-- with this program; if not, write to the Free Software Foundation, Inc.,
-- 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
--------------------------------------------------------------------------------

function widget:GetInfo()
    return {
        name = "⏱️ Build Time Estimator v2",
        desc = [[
Shows realistic build time estimates for units in Beyond All Reason.
Features:
• Real-time calculation based on available builders and nano turrets
• Economy-aware predictions accounting for metal/energy constraints  
• Works in both player and spectator modes
• Press backtick (`) to toggle IDLE BUILDER MODE:
  - Shows idle builders AND turrets in range
  - Auto-commands idle units to GUARD selected builder
  - Units help build whatever the builder is constructing
  - Works with T1/T2 compatibility (guard copies commands)
  - 2-second cooldown per unit to prevent spam
  - Gray color scheme in idle mode
  - Press again to turn off
• Hover over units under construction to see completion time
• Color-coded indicators for economy status (green/yellow/red)
• Shows builder count, resource usage rates, and storage levels
• Automatically detects builders in range and selected builders
]],
        author = "Pyrem, enhanced by Waleed",
        version = "2.6.0",
        date = "2024",
        license = "GNU GPL, v2 or later",
        layer = -999,
        enabled = true
    }
end

-- 🎯 Player identification and spectator support
local myPlayerID = nil
local myTeamID = nil
local targetPlayerID = nil  -- Which player's units to track (for spectator mode)
local targetTeamID = nil
local isSpectator = false
local lastPlayerCheck = 0

-- ⚡ Performance tuning constants
local UPDATE_FREQUENCY = 15 -- Update every 15 frames (0.5s at 30 fps)
local HOVER_CHECK_FREQUENCY = 6 -- Check hover every 6 frames (0.2s at 30 fps)
local PLAYER_CHECK_FREQUENCY = 90 -- Check player status every 90 frames (3s)
local frameCounter = 0
local lastHoverUpdate = 0
local lastHoverCheck = 0

-- 🚀 Performance caching system
local unitCache = {}  -- Cache unit properties that don't change often
local lastCacheUpdate = 0
local CACHE_UPDATE_FREQUENCY = 45 -- Update cache every 45 frames (1.5s)

-- 💾 Cached calculation results
local cachedResults = {
    isActive = false,
    timeText = "",
    builderCount = 0,
    turretCount = 0,
    showingIdle = false,
    ecoStatus = nil,
    metalPerSecond = 0,
    energyPerSecond = 0,
    playerName = "" -- Track which player's units we're showing
}

-- 🔨 Cached hover results for construction info
local hoveredResults = {
    isActive = false,
    unitID = nil,
    buildProgress = 0,
    timeText = "",
    buildPowerPerSecond = 0,
    ecoStatus = nil,
    metalPerSecond = 0,
    energyPerSecond = 0
}

-- Idle builder toggle state
local showIdleOnly = false
local BACKTICK_KEY_1 = 96   -- ASCII backtick
local BACKTICK_KEY_2 = 192  -- SDL backtick/tilde key

-- Import required modules
local gl = gl
local CMD = CMD

-- Command IDs for clarity
local CMD_MOVE = CMD.MOVE
local CMD_PATROL = CMD.PATROL
local CMD_FIGHT = CMD.FIGHT
local CMD_GUARD = CMD.GUARD
local CMD_REPAIR = CMD.REPAIR
local CMD_RECLAIM = CMD.RECLAIM
local CMD_RESURRECT = CMD.RESURRECT
local CMD_WAIT = CMD.WAIT
local CMD_STOP = CMD.STOP

-- 🎯 Idle builder auto-command system
local idleBuildersCommanded = {}  -- Track cooldown per builder {[unitID] = frameExpiry}
local lastCommandFeedback = ""
local commandFeedbackTime = 0
local COMMAND_COOLDOWN = 60  -- 2 seconds at 30fps
local FEEDBACK_DURATION = 60  -- Show feedback for 2 seconds
local cachedIdleBuilders = {}  -- Cache idle builders for command system
local cachedIdleTurrets = {}  -- Cache idle turrets separately

-- BAR-style color constants
local ECO_GREEN = "\255\120\235\120"  -- Positive/affordable
local ECO_RED = "\255\240\125\125"    -- Negative/unaffordable  
local ECO_YELLOW = "\255\255\255\150" -- Warning (60-99%)
local ECO_WHITE = "\255\255\255\255"  -- Neutral
local ECO_GRAY = "\255\200\200\200"   -- Default

-- Font system
local font

-- 👤 Player identification functions
local function updatePlayerInfo()
    myPlayerID = Spring.GetMyPlayerID()
    local _, _, spec, teamID = Spring.GetPlayerInfo(myPlayerID)
    myTeamID = teamID
    isSpectator = spec
    
    -- In spectator mode, default to tracking our own player initially
    -- Later we can add UI to switch between players
    if isSpectator then
        targetPlayerID = myPlayerID
        targetTeamID = myTeamID
    else
        targetPlayerID = myPlayerID  
        targetTeamID = myTeamID
    end
    
    -- Get player name for display
    local playerName = Spring.GetPlayerInfo(targetPlayerID) or "Unknown"
    cachedResults.playerName = playerName
end

-- 🎯 Get units belonging to specific player/team
local function getPlayerUnits(forceRefresh)
    if not targetTeamID then return {} end
    
    -- For critical calculations, always get fresh data
    if forceRefresh then
        return Spring.GetTeamUnits(targetTeamID) or {}
    end
    
    -- Use cached units only for non-critical operations
    local currentFrame = Spring.GetGameFrame()
    if unitCache.units and unitCache.teamID == targetTeamID and 
       (currentFrame - lastCacheUpdate) < CACHE_UPDATE_FREQUENCY then
        return unitCache.units
    end
    
    -- Refresh unit cache
    local teamUnits = Spring.GetTeamUnits(targetTeamID) or {}
    unitCache.units = teamUnits
    unitCache.teamID = targetTeamID
    lastCacheUpdate = currentFrame
    
    return teamUnits
end

-- Helper function for 2D distance
local function getDistance2D(x1, z1, x2, z2)
    local dx, dz = x1 - x2, z1 - z2
    return math.sqrt(dx*dx + dz*dz)
end

-- Helper function to format numbers with k suffix
local function formatNumber(num)
    if num >= 1000 then
        return string.format("%.1fk", num / 1000)
    else
        return string.format("%.0f", num)
    end
end

-- Helper function to check if a MOBILE builder is idle
-- Mobile builders: Building or actively working = busy, GUARD alone = idle
local function isBuilderIdle(unitID)
    -- MOST IMPORTANT: Check if actively building something
    local buildingID = Spring.GetUnitIsBuilding(unitID)
    if buildingID then
        return false  -- Actively building = NOT idle
    end
    
    -- Check if unit is moving (velocity check - mobile builders only)
    local vx, vy, vz = Spring.GetUnitVelocity(unitID)
    if vx and (math.abs(vx) > 0.01 or math.abs(vz) > 0.01) then
        return false  -- Moving = NOT idle
    end
    
    -- No commands = definitely idle
    local commands = Spring.GetUnitCommands(unitID, 1)
    if not commands or #commands == 0 then
        return true  -- No commands = IDLE
    end
    
    -- Has commands - check if it's ONLY guard (guard alone = idle)
    if #commands == 1 and commands[1].id == CMD_GUARD then
        return true  -- Only guarding, not building = IDLE
    end
    
    -- Has other commands = busy
    return false
end

-- Helper function to check if unit is guarding any selected builder
local function isGuardingSelectedBuilder(unitID, selectedBuilders)
    if not selectedBuilders or not next(selectedBuilders) then
        return false, nil
    end
    
    local commands = Spring.GetUnitCommands(unitID, 5)
    if commands then
        for _, cmd in ipairs(commands) do
            if cmd.id == CMD_GUARD and cmd.params and cmd.params[1] then
                local targetID = cmd.params[1]
                if selectedBuilders[targetID] then
                    return true, targetID  -- Guarding a selected builder
                end
            end
        end
    end
    return false, nil
end

-- 🔨 Command idle builders and turrets to guard selected builders
local function commandIdleUnitsToGuard()
    if not showIdleOnly then return 0 end  -- Only work in idle mode
    
    local currentFrame = Spring.GetGameFrame()
    local commandedCount = 0
    local turretCount = 0
    local skippedCooldown = 0
    
    -- Get selected units that are builders (these will be doing the actual building)
    local selectedUnits = Spring.GetSelectedUnits()
    if not selectedUnits or #selectedUnits == 0 then
        -- No selected units to guard
        return 0
    end
    
    -- Find the first selected builder to guard
    local targetBuilder = nil
    for _, unitID in ipairs(selectedUnits) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        if unitDefID and UnitDefs[unitDefID].isBuilder and not UnitDefs[unitDefID].isFactory then
            targetBuilder = unitID
            break
        end
    end
    
    if not targetBuilder then
        -- No selected builder to guard
        return 0
    end
    
    -- Found target builder to guard
    
    -- Command idle mobile builders to guard (only those in range)
    if cachedIdleBuilders and #cachedIdleBuilders > 0 then
        for _, builder in ipairs(cachedIdleBuilders) do
            if builder.idle and builder.inRange then  -- Only command idle builders in range
                -- Check cooldown
                local cooldownExpiry = idleBuildersCommanded[builder.id]
                if not cooldownExpiry or currentFrame > cooldownExpiry then
                    -- Issue guard command
                    Spring.GiveOrderToUnit(builder.id, CMD_GUARD, {targetBuilder}, {})
                    
                    -- Track cooldown
                    idleBuildersCommanded[builder.id] = currentFrame + COMMAND_COOLDOWN
                    commandedCount = commandedCount + 1
                else
                    skippedCooldown = skippedCooldown + 1
                end
            end
        end
    end
    
    -- Command idle turrets to guard (only those in range)
    if cachedIdleTurrets and #cachedIdleTurrets > 0 then
        for _, turret in ipairs(cachedIdleTurrets) do
            if turret.idle and turret.inRange then  -- Turrets must be in range
                -- Check cooldown
                local cooldownExpiry = idleBuildersCommanded[turret.id]
                if not cooldownExpiry or currentFrame > cooldownExpiry then
                    -- Issue guard command
                    Spring.GiveOrderToUnit(turret.id, CMD_GUARD, {targetBuilder}, {})
                    
                    -- Track cooldown  
                    idleBuildersCommanded[turret.id] = currentFrame + COMMAND_COOLDOWN
                    turretCount = turretCount + 1
                else
                    skippedCooldown = skippedCooldown + 1
                end
            end
        end
    end
    
    -- Clean up expired cooldowns
    for unitID, expiry in pairs(idleBuildersCommanded) do
        if currentFrame > expiry then
            idleBuildersCommanded[unitID] = nil
        end
    end
    
    -- Set feedback message
    local totalCommanded = commandedCount + turretCount
    if totalCommanded > 0 then
        local parts = {}
        if commandedCount > 0 then
            table.insert(parts, commandedCount .. " builders")
        end
        if turretCount > 0 then
            table.insert(parts, turretCount .. " turrets")
        end
        lastCommandFeedback = "✓ Commanded " .. table.concat(parts, " and ") .. " to guard"
        commandFeedbackTime = currentFrame + FEEDBACK_DURATION
    elseif skippedCooldown > 0 then
        lastCommandFeedback = "⏳ " .. skippedCooldown .. " units on cooldown"
        commandFeedbackTime = currentFrame + FEEDBACK_DURATION
    end
    
    return totalCommanded
end

-- Nano turret definitions
local TURRET_NAMES = {
    "armnanotc", "armnanotcplat", "armnanotct2", "armnanotc2plat", "armrespawn",
    "cornanotc", "cornanotcplat", "cornanotct2", "cornanotc2plat", "correspawn",
    "legnanotc", "legnanotcplat", "legnanotct2", "legnanotct2plat", "legnanotcbase",
    "armnanotct3", "cornanotct3", "legnanotct3",
}

-- Convert names to UnitDefIDs for fast lookup
local TURRET_DEF_IDS = {}

-- Helper function to check if a NANO TURRET is idle
-- Turrets: Building or actively working = busy, GUARD/FIGHT alone = idle
local function isTurretIdle(unitID)
    -- MOST IMPORTANT: Check if actively building/repairing something
    local buildingID = Spring.GetUnitIsBuilding(unitID)
    if buildingID then
        return false  -- Actively building = NOT idle
    end
    
    -- Check commands but IGNORE state commands AND guard
    local commands = Spring.GetUnitCommands(unitID, 5)
    if commands and #commands > 0 then
        -- Check if turret has REAL work commands (NOT including GUARD)
        for _, cmd in ipairs(commands) do
            -- These are actual work commands for turrets
            if cmd.id == CMD_REPAIR or 
               cmd.id == CMD_RECLAIM or
               cmd.id == CMD_RESURRECT or
               cmd.id < 0 then  -- Negative = build commands
                return false  -- Has real work = NOT idle
            end
            -- GUARD, FIGHT, STOP, WAIT are NOT real work - ignore them
        end
    end
    
    -- Not building, no real work commands (guard is OK) = IDLE
    return true
end

-- Get real-time economy data
local function getEconomyInfo()
    if not targetTeamID then return {} end
    
    local metalCurrent, metalStorage, metalPull, metalIncome = Spring.GetTeamResources(targetTeamID, "metal")
    local energyCurrent, energyStorage, energyPull, energyIncome = Spring.GetTeamResources(targetTeamID, "energy")
    
    return {
        metalNet = (metalIncome or 0) - (metalPull or 0),
        energyNet = (energyIncome or 0) - (energyPull or 0),
        metalIncome = metalIncome or 0,
        energyIncome = energyIncome or 0,
        metalStored = metalCurrent or 0,
        energyStored = energyCurrent or 0,
        metalStorage = metalStorage or 0,
        energyStorage = energyStorage or 0
    }
end

-- Calculate resource gathering time
local function calculateResourceTime(metalCost, energyCost, metalPerSecond, energyPerSecond)
    local eco = getEconomyInfo()
    local metalTime = 0
    local energyTime = 0
    
    -- Calculate actual deficit after using stored resources
    local metalNeeded = math.max(0, metalCost - eco.metalStored)
    local energyNeeded = math.max(0, energyCost - eco.energyStored)
    
    -- If we have enough stored resources, no extra time needed
    if metalNeeded == 0 and energyNeeded == 0 then
        return 0
    end
    
    -- Calculate gathering time if income can't support required rate
    if metalPerSecond > 0 and eco.metalNet < metalPerSecond then
        if metalNeeded > 0 then
            if eco.metalIncome > 0 then
                metalTime = metalNeeded / eco.metalIncome
            else
                metalTime = math.huge
            end
        end
    end
    
    if energyPerSecond > 0 and eco.energyNet < energyPerSecond then
        if energyNeeded > 0 then
            if eco.energyIncome > 0 then
                energyTime = energyNeeded / eco.energyIncome
            else
                energyTime = math.huge
            end
        end
    end
    
    return math.max(metalTime, energyTime)
end

-- Check if economy can support the build
local function getEconomyStatus(metalPerSecond, energyPerSecond, metalCost, energyCost)
    local eco = getEconomyInfo()
    
    local metalAvailable = eco.metalNet
    local energyAvailable = eco.energyNet
    
    local metalProductionPercent = metalPerSecond > 0 and ((metalAvailable / metalPerSecond) * 100) or 100
    local energyProductionPercent = energyPerSecond > 0 and ((energyAvailable / energyPerSecond) * 100) or 100
    
    local hasMetalStorage = eco.metalStored >= metalCost
    local hasEnergyStorage = eco.energyStored >= energyCost
    
    local metalAffordable = metalAvailable >= metalPerSecond or hasMetalStorage
    local energyAffordable = energyAvailable >= energyPerSecond or hasEnergyStorage
    
    return {
        canAfford = metalAffordable and energyAffordable,
        metalOk = metalAffordable,
        energyOk = energyAffordable,
        metalPercent = metalProductionPercent,
        energyPercent = energyProductionPercent,
        hasMetalStorage = hasMetalStorage,
        hasEnergyStorage = hasEnergyStorage,
        metalStored = eco.metalStored,
        energyStored = eco.energyStored,
        metalDeficit = (not hasMetalStorage) and math.max(0, metalPerSecond - metalAvailable) or 0,
        energyDeficit = (not hasEnergyStorage) and math.max(0, energyPerSecond - energyAvailable) or 0
    }
end

-- Calculate construction info for a hovered unit
local function calculateConstructionInfo(unitID, buildProgress)
    local unitDefID = Spring.GetUnitDefID(unitID)
    if not unitDefID then return end
    
    local unitDef = UnitDefs[unitDefID]
    if not unitDef then return end
    
    local ux, uy, uz = Spring.GetUnitPosition(unitID)
    if not ux then return end
    
    -- Find builders working on this unit (only from our target player)
    local totalBuildPower = 0
    local playerUnits = getPlayerUnits(true)  -- Force refresh for accurate calculations
    
    for _, builderID in ipairs(playerUnits) do
        local builderDefID = Spring.GetUnitDefID(builderID)
        if builderDefID and UnitDefs[builderDefID].isBuilder then
            local targetID = Spring.GetUnitIsBuilding(builderID)
            
            if targetID == unitID then
                local buildSpeed = UnitDefs[builderDefID].buildSpeed or 100
                totalBuildPower = totalBuildPower + buildSpeed
            end
        end
    end
    
    -- Calculate resource consumption rates
    local metalCost = unitDef.metalCost or 0
    local energyCost = unitDef.energyCost or 0
    local remainingBuildTime = unitDef.buildTime * (1 - buildProgress)
    
    local constructionTime = totalBuildPower > 0 and (remainingBuildTime / totalBuildPower) or math.huge
    local metalPerSecond = constructionTime > 0 and constructionTime < math.huge and (metalCost * (1 - buildProgress) / constructionTime) or 0
    local energyPerSecond = constructionTime > 0 and constructionTime < math.huge and (energyCost * (1 - buildProgress) / constructionTime) or 0
    
    local remainingMetalCost = metalCost * (1 - buildProgress)
    local remainingEnergyCost = energyCost * (1 - buildProgress)
    
    local resourceGatherTime = calculateResourceTime(remainingMetalCost, remainingEnergyCost, metalPerSecond, energyPerSecond)
    local buildTime = math.max(constructionTime, resourceGatherTime)
    
    -- Format time text
    local timeText
    if buildTime == math.huge or totalBuildPower == 0 then
        timeText = "∞"
    elseif buildTime < 60 then
        timeText = string.format("%.0fs", buildTime)
    else
        local minutes = math.floor(buildTime / 60)
        local seconds = buildTime % 60
        timeText = string.format("%dm %.0fs", minutes, seconds)
    end
    
    -- Get economy status
    local ecoStatus = nil
    local ecoSuccess, ecoResult = pcall(getEconomyStatus, metalPerSecond, energyPerSecond, remainingMetalCost, remainingEnergyCost)
    if ecoSuccess then
        ecoStatus = ecoResult
    else
        Spring.Echo("Build Timer v2 Economy Error: " .. tostring(ecoResult))
        ecoStatus = {
            canAfford = true,
            metalPercent = 100,
            energyPercent = 100,
            hasMetalStorage = true,
            hasEnergyStorage = true,
            metalStored = 0,
            energyStored = 0,
            metalDeficit = 0,
            energyDeficit = 0
        }
    end
    
    -- Cache results
    hoveredResults.timeText = timeText
    hoveredResults.buildPowerPerSecond = totalBuildPower
    hoveredResults.ecoStatus = ecoStatus
    hoveredResults.metalPerSecond = metalPerSecond
    hoveredResults.energyPerSecond = energyPerSecond
end

-- Display hover info for construction
local function displayHoverInfo()
    local mx, my = Spring.GetMouseState()
    
    local totalHeight = 80 + 30
    local screenX, screenY = mx, my - totalHeight
    
    local ecoStatus = hoveredResults.ecoStatus
    local buildProgressPercent = math.floor((hoveredResults.buildProgress or 0) * 100)
    local timeText = hoveredResults.timeText or "?"
    
    if font then
        font:Begin()
        font:SetOutlineColor(0, 0, 0, 1)
        
        -- Timer with progress percentage
        local timerColor = ECO_WHITE
        if ecoStatus and not ecoStatus.canAfford then
            timerColor = ECO_RED
        elseif ecoStatus and (ecoStatus.metalPercent < 100 or ecoStatus.energyPercent < 100) then
            timerColor = ECO_YELLOW
        end
        
        font:Print(timerColor .. "⏱️ " .. timeText .. " (" .. buildProgressPercent .. "%)", screenX, screenY, 24, "co")
        
        -- Show player name in spectator mode
        if isSpectator and cachedResults.playerName then
            font:Print(ECO_GRAY .. "👤 " .. cachedResults.playerName, screenX, screenY - 15, 12, "co")
        end
        
        -- Build power being applied
        local buildPowerPerSecond = hoveredResults.buildPowerPerSecond or 0
        font:Print(ECO_GRAY .. "Build • " .. formatNumber(buildPowerPerSecond) .. " BP/s", screenX, screenY - 30, 14, "co")
        
        -- Usage rates
        local metalPerSecond = hoveredResults.metalPerSecond or 0
        local energyPerSecond = hoveredResults.energyPerSecond or 0
        font:Print(ECO_GRAY .. "Usage • " .. formatNumber(metalPerSecond) .. " M/s • " .. 
                  formatNumber(energyPerSecond) .. " E/s", 
                  screenX, screenY - 45, 12, "co")
        
        if ecoStatus then
            -- Show storage availability
            local metalStorageColor = ecoStatus.hasMetalStorage and ECO_GREEN or ECO_RED
            local energyStorageColor = ecoStatus.hasEnergyStorage and ECO_GREEN or ECO_RED
            local metalStored = ecoStatus.metalStored or 0
            local energyStored = ecoStatus.energyStored or 0
            
            font:Print(ECO_GRAY .. "Storage " ..
                      metalStorageColor .. "• " .. formatNumber(metalStored) .. " M " ..
                      energyStorageColor .. "• " .. formatNumber(energyStored) .. " E",
                      screenX, screenY - 60, 12, "co")
                      
            -- Show production constraints
            local metalDeficit = ecoStatus.metalDeficit or 0
            local energyDeficit = ecoStatus.energyDeficit or 0
            if metalDeficit > 0 or energyDeficit > 0 then
                local eco = getEconomyInfo()
                local metalProduction = eco.metalNet or 0
                local energyProduction = eco.energyNet or 0
                local metalRequired = hoveredResults.metalPerSecond or 0
                local energyRequired = hoveredResults.energyPerSecond or 0
                
                local productionText = ""
                local hasProduction = false
                if metalDeficit > 0 and metalRequired > 0 then
                    productionText = productionText .. string.format("• %.0f/%.0f M/s", metalProduction, metalRequired)
                    hasProduction = true
                end
                if energyDeficit > 0 and energyRequired > 0 then
                    if hasProduction then productionText = productionText .. " " end
                    productionText = productionText .. string.format("• %.0f/%.0f E/s", energyProduction, energyRequired)
                end
                font:Print(ECO_GRAY .. "Production " .. ECO_RED .. productionText, screenX, screenY - 75, 12, "co")
            end
        end
        
        font:End()
    else
        -- Fallback GL rendering
        gl.Color(1, 1, 1, 1)
        gl.Text("⏱️ " .. timeText .. " (" .. buildProgressPercent .. "%)", screenX, screenY, 24, "co")
        
        if isSpectator and cachedResults.playerName then
            gl.Color(0.8, 0.8, 0.8, 1)
            gl.Text("👤 " .. cachedResults.playerName, screenX, screenY - 15, 12, "co")
        end
        
        gl.Color(0.8, 0.8, 0.8, 1)
        local buildPowerPerSecond = hoveredResults.buildPowerPerSecond or 0
        gl.Text("Build  • " .. formatNumber(buildPowerPerSecond) .. " BP/s", screenX, screenY - 30, 14, "co")
        
        local metalPerSecond = hoveredResults.metalPerSecond or 0
        local energyPerSecond = hoveredResults.energyPerSecond or 0
        gl.Text("Usage • " .. formatNumber(metalPerSecond) .. " M/s • " .. 
                formatNumber(energyPerSecond) .. " E/s", screenX, screenY - 45, 12, "co")
        
        if ecoStatus then
            local metalStored = ecoStatus.metalStored or 0
            local energyStored = ecoStatus.energyStored or 0
            gl.Text("Storage • " .. formatNumber(metalStored) .. " M • " .. 
                    formatNumber(energyStored) .. " E", screenX, screenY - 60, 12, "co")
        end
    end
end

-- Get BAR color based on economy percentage
local function getEcoColor(percent)
    if percent >= 100 then
        return ECO_GREEN
    elseif percent >= 60 then
        return ECO_YELLOW
    else
        return ECO_RED
    end
end

-- For gl rendering fallback
local function getEcoColorGL(percent)
    if percent >= 100 then
        return {0.47, 0.92, 0.47, 1}
    elseif percent >= 60 then
        return {1.0, 1.0, 0.6, 1}
    else
        return {0.94, 0.49, 0.49, 1}
    end
end

function widget:Initialize()
    -- Initialize player info (works in both regular and spectator mode)
    updatePlayerInfo()
    
    -- Initialize UnitDefID lookup tables
    for _, name in ipairs(TURRET_NAMES) do
        local def = UnitDefNames[name]
        if def then TURRET_DEF_IDS[def.id] = true end
    end
    
    -- Use BAR font system
    if WG.fonts then
        font = WG.fonts.getFont(2)
    end
    
    local modeText = isSpectator and "spectator mode" or "player mode"
    Spring.Echo("Build Timer v2: Initialized in " .. modeText .. " tracking " .. (cachedResults.playerName or "unknown player"))
end

function widget:Shutdown()
    Spring.Echo("Build Timer v2: Shutdown")
end

-- Handle player status changes
function widget:PlayerChanged(playerID)
    -- Update our player information when players change
    updatePlayerInfo()
    
    local modeText = isSpectator and "spectator mode" or "player mode"  
    Spring.Echo("Build Timer v2: Player changed, now in " .. modeText .. " tracking " .. (cachedResults.playerName or "unknown player"))
end

-- Key handler for idle builder toggle (press to toggle on/off)
function widget:KeyPress(key, mods, isRepeat)
    if (key == BACKTICK_KEY_1 or key == BACKTICK_KEY_2) and not isRepeat then
        showIdleOnly = not showIdleOnly  -- Toggle the state
        
        -- Clear cached idle units when turning off
        if not showIdleOnly then
            cachedIdleBuilders = {}
            cachedIdleTurrets = {}
        end
        
        return false
    end
end

-- 🎯 Intercept build commands to auto-command idle builders
function widget:CommandNotify(cmdID, cmdParams, cmdOptions)
    -- Check if placing a building (negative cmdID) and idle mode is active
    if showIdleOnly and cmdID < 0 then
        local buildDefID = -cmdID  -- Convert to positive unit def ID
        local unitDef = UnitDefs[buildDefID]
        local unitName = unitDef and unitDef.name or "unknown"
        
        -- Command idle units to guard the selected builder
        local commanded = commandIdleUnitsToGuard()
        
        -- Still let the original command through for any selected builders
        return false
    end
    
    return false  -- Don't block the command
end

-- Optimized calculation loop with player-specific filtering
function widget:GameFrame()
    frameCounter = frameCounter + 1
    
    -- Periodically update player status
    if frameCounter % PLAYER_CHECK_FREQUENCY == 0 then
        updatePlayerInfo()
    end
    
    -- Only process every UPDATE_FREQUENCY frames
    if frameCounter % UPDATE_FREQUENCY ~= 0 then
        return
    end
    
    -- Reset cached results
    cachedResults.isActive = false
    
    -- Check build mode
    local _, activeCommand = Spring.GetActiveCommand()
    if not activeCommand or activeCommand >= 0 then
        return
    end
    
    -- Get mouse position and world coordinates
    local mx, my = Spring.GetMouseState()
    local _, pos = Spring.TraceScreenRay(mx, my, true)
    
    if not pos then
        return
    end
    
    local unitDef = UnitDefs[-activeCommand]
    if not unitDef or not unitDef.buildTime then
        return
    end
    
    -- Get player-specific units - ALWAYS FRESH for accurate range detection
    local playerUnits = getPlayerUnits(true)  -- Force refresh for accurate calculations
    if not playerUnits or #playerUnits == 0 then
        return
    end
    
    -- Smart build time calculation: check player's builders against their ranges
    local builders = {}
    local selectedUnits = Spring.GetSelectedUnits()
    local selectedBuilders = {}
    
    -- Mark selected builders for special handling
    for _, unitID in ipairs(selectedUnits) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        if unitDefID and UnitDefs[unitDefID].isBuilder and not UnitDefs[unitDefID].isFactory then
            selectedBuilders[unitID] = true
        end
    end
    
    -- Check player's builders against placement position
    for _, unitID in ipairs(playerUnits) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        -- Count mobile builders (not nano turrets, not factories)
        if unitDefID and UnitDefs[unitDefID].isBuilder and not UnitDefs[unitDefID].isFactory and not TURRET_DEF_IDS[unitDefID] then
            local bx, by, bz = Spring.GetUnitPosition(unitID)
            if bx then
                local buildRange = UnitDefs[unitDefID].buildDistance or 100
                local distance = getDistance2D(bx, bz, pos[1], pos[3])
                local buildSpeed = UnitDefs[unitDefID].buildSpeed or 100
                
                local isSelected = selectedBuilders[unitID] or false
                local inRange = distance <= buildRange
                
                -- Check if guarding a selected builder
                local isGuarding, guardTarget = isGuardingSelectedBuilder(unitID, selectedBuilders)
                
                -- Add builder if in range OR selected OR guarding selected
                if inRange or isSelected or isGuarding then
                    -- Check if builder is idle (includes guard without building)
                    local idle = isBuilderIdle(unitID)
                    
                    -- Only add builder if showing all OR it's idle (when showing idle only)
                    if not showIdleOnly or idle then
                        builders[#builders + 1] = {
                            id = unitID,
                            buildSpeed = buildSpeed,
                            inRange = inRange,
                            selected = isSelected,
                            distance = distance,
                            buildRange = buildRange,
                            idle = idle,
                            guarding = isGuarding,
                            guardTarget = guardTarget
                        }
                    end
                end
            end
        end
    end
    
    -- Calculate totals and count guarding units
    local builderCount = #builders
    local guardingBuilderCount = 0
    local totalBuildPower = 0
    
    for _, builder in ipairs(builders) do
        totalBuildPower = totalBuildPower + builder.buildSpeed
        if builder.guarding and not builder.selected then
            guardingBuilderCount = guardingBuilderCount + 1
        end
    end
    
    -- Check nano turrets in range from player's units
    local turrets = {}
    for _, unitID in ipairs(playerUnits) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        if unitDefID and TURRET_DEF_IDS[unitDefID] then
            local tx, ty, tz = Spring.GetUnitPosition(unitID)
            if tx then
                local buildRange = UnitDefs[unitDefID].buildDistance or 300
                local distance = getDistance2D(tx, tz, pos[1], pos[3])
                
                local inRange = distance <= buildRange
                
                -- Check if turret is guarding a selected builder
                local isGuarding, guardTarget = isGuardingSelectedBuilder(unitID, selectedBuilders)
                
                -- Include turret if in range OR guarding selected builder
                if inRange or isGuarding then
                    local idle = isTurretIdle(unitID)
                    local buildSpeed = UnitDefs[unitDefID].buildSpeed or 100
                    
                    -- Only add turret if showing all OR it's idle
                    if not showIdleOnly or idle then
                        turrets[#turrets + 1] = {
                            id = unitID,
                            buildSpeed = buildSpeed,
                            inRange = inRange,
                            idle = idle,
                            guarding = isGuarding,
                            guardTarget = guardTarget
                        }
                        totalBuildPower = totalBuildPower + buildSpeed
                    end
                end
            end
        end
    end
    
    -- 📦 Cache idle builders and turrets for command system (when in idle mode)
    if showIdleOnly then
        cachedIdleBuilders = builders  -- Store the filtered builder list
        cachedIdleTurrets = turrets  -- Store the filtered turret list
        local totalIdle = #builders + #turrets
        -- Cached idle units for command system
    else
        cachedIdleBuilders = {}  -- Clear when not in idle mode
        cachedIdleTurrets = {}  -- Clear when not in idle mode
    end
    
    local turretCount = #turrets
    local guardingTurretCount = 0
    
    -- Count guarding turrets
    for _, turret in ipairs(turrets) do
        if turret.guarding then
            guardingTurretCount = guardingTurretCount + 1
        end
    end
    
    -- Calculate resource consumption rates
    local metalCost = unitDef.metalCost or 0
    local energyCost = unitDef.energyCost or 0
    local constructionTime = totalBuildPower > 0 and (unitDef.buildTime / totalBuildPower) or 0
    local metalPerSecond = constructionTime > 0 and (metalCost / constructionTime) or 0
    local energyPerSecond = constructionTime > 0 and (energyCost / constructionTime) or 0
    
    -- Calculate resource gathering time
    local resourceGatherTime = calculateResourceTime(metalCost, energyCost, metalPerSecond, energyPerSecond)
    
    -- Realistic build time is the maximum of construction time and resource gathering time
    local buildTime = math.max(constructionTime, resourceGatherTime)
    
    if totalBuildPower > 0 then
        local timeText
        if buildTime == math.huge then
            timeText = "∞"
        elseif buildTime < 60 then
            timeText = string.format("%.0fs", buildTime)
        else
            local minutes = math.floor(buildTime / 60)
            local seconds = buildTime % 60
            timeText = string.format("%dm %.0fs", minutes, seconds)
        end
        
        -- Get economy status
        local ecoStatus = getEconomyStatus(metalPerSecond, energyPerSecond, metalCost, energyCost)
        
        -- Cache calculation results
        cachedResults.isActive = true
        cachedResults.timeText = timeText
        cachedResults.builderCount = builderCount
        cachedResults.turretCount = turretCount
        cachedResults.guardingBuilderCount = guardingBuilderCount
        cachedResults.guardingTurretCount = guardingTurretCount
        cachedResults.showingIdle = showIdleOnly
        cachedResults.ecoStatus = ecoStatus
        cachedResults.metalPerSecond = metalPerSecond
        cachedResults.energyPerSecond = energyPerSecond
    end
    
    -- 🌐 Share data with other widgets via WG table
    WG.BuildTimeEstimator = WG.BuildTimeEstimator or {}
    WG.BuildTimeEstimator.showingIdleOnly = showIdleOnly
    WG.BuildTimeEstimator.idleBuilders = cachedIdleBuilders
    WG.BuildTimeEstimator.builderCount = cachedResults.builderCount
    WG.BuildTimeEstimator.turretCount = cachedResults.turretCount
end

function widget:DrawScreen()
    -- Wrap everything in error protection
    local success, err = pcall(function()
    
    -- Always check for hover position, but throttle expensive calculations
    if not cachedResults.isActive then
        local mx, my = Spring.GetMouseState()
        local _, pos = Spring.TraceScreenRay(mx, my, true)
        
        if pos then
            -- Find units at mouse position
            local unitsAtPos = Spring.GetUnitsInCylinder(pos[1], pos[3], 50)
            local foundConstruction = false
            
            for _, unitID in ipairs(unitsAtPos or {}) do
                if unitID and Spring.ValidUnitID(unitID) then
                    local health, maxHealth, paralyze, capture, buildProgress = Spring.GetUnitHealth(unitID)
                    
                    -- Check if unit is under construction
                    if buildProgress and buildProgress < 1 then
                        foundConstruction = true
                        
                        -- Check if we should calculate/recalculate
                        local currentFrame = Spring.GetGameFrame()
                        local shouldCalculate = false
                        
                        if showIdleOnly then
                            -- Instant calculation with backtick key
                            shouldCalculate = hoveredResults.unitID ~= unitID or (currentFrame - lastHoverUpdate) >= UPDATE_FREQUENCY
                        else
                            -- Throttled calculation for default hover
                            local shouldCheckHoverDefault = (currentFrame - lastHoverCheck) >= HOVER_CHECK_FREQUENCY
                            if shouldCheckHoverDefault then
                                shouldCalculate = hoveredResults.unitID ~= unitID or (currentFrame - lastHoverUpdate) >= UPDATE_FREQUENCY
                                lastHoverCheck = currentFrame
                            end
                        end
                        
                        if shouldCalculate then
                            hoveredResults.isActive = true
                            hoveredResults.unitID = unitID
                            hoveredResults.buildProgress = buildProgress
                            lastHoverUpdate = currentFrame
                            
                            -- Initialize safe defaults
                            hoveredResults.timeText = "?"
                            hoveredResults.buildPowerPerSecond = 0
                            hoveredResults.metalPerSecond = 0
                            hoveredResults.energyPerSecond = 0
                            hoveredResults.ecoStatus = {
                                canAfford = true,
                                metalPercent = 100,
                                energyPercent = 100,
                                hasMetalStorage = true,
                                hasEnergyStorage = true,
                                metalStored = 0,
                                energyStored = 0,
                                metalDeficit = 0,
                                energyDeficit = 0
                            }
                            
                            -- Calculate construction info
                            local calcSuccess, calcErr = pcall(calculateConstructionInfo, unitID, buildProgress)
                            if not calcSuccess then
                                Spring.Echo("Build Timer v2 Calc Error: " .. tostring(calcErr))
                            end
                        else
                            -- Keep showing existing hover info
                            hoveredResults.isActive = true
                        end
                        break
                    end
                end
            end
            
            -- Clear hover if no construction found
            if not foundConstruction then
                hoveredResults.isActive = false
                hoveredResults.unitID = nil
            end
        else
            -- Clear hover if no valid position
            hoveredResults.isActive = false
            hoveredResults.unitID = nil
        end
    end
    
    -- Check for hover info first
    if hoveredResults.isActive then
        local hoverSuccess, hoverErr = pcall(displayHoverInfo)
        if not hoverSuccess then
            Spring.Echo("Build Timer v2 Hover Error: " .. tostring(hoverErr))
            gl.Color(1, 0, 0, 1)
            gl.Text("HOVER ERROR - Check console", 10, 30, 14)
        end
        return
    end
    
    -- Display build placement info if we have cached results
    if cachedResults.isActive then
        local mx, my = Spring.GetMouseState()
        local _, pos = Spring.TraceScreenRay(mx, my, true)
        
        if pos then
            local totalHeight = 65 + 30
            local screenX, screenY = mx, my - totalHeight
            
            if screenX and screenY then
                local ecoStatus = cachedResults.ecoStatus
                
                if font then
                    font:Begin()
                    font:SetOutlineColor(0, 0, 0, 1)
                    
                    -- Timer color based on economy (gray in idle mode)
                    local timerColor = ECO_WHITE
                    if cachedResults.showingIdle then
                        timerColor = ECO_GRAY  -- Always gray in idle mode
                    elseif not ecoStatus.canAfford then
                        timerColor = ECO_RED
                    elseif ecoStatus.metalPercent < 100 or ecoStatus.energyPercent < 100 then
                        timerColor = ECO_YELLOW
                    end
                    
                    -- Show idle mode indicator
                    if cachedResults.showingIdle then
                        font:Print(ECO_GRAY .. "🎯 IDLE BUILDER MODE", screenX, screenY - 25, 16, "co")
                        font:Print(timerColor .. "⏱️ " .. cachedResults.timeText, screenX, screenY, 24, "co")
                    else
                        font:Print(timerColor .. "⏱️ " .. cachedResults.timeText, screenX, screenY, 24, "co")
                    end
                    
                    -- Show player name in spectator mode
                    if isSpectator and cachedResults.playerName then
                        font:Print(ECO_GRAY .. "👤 " .. cachedResults.playerName, screenX, screenY - 15, 12, "co")
                    end
                    
                    -- Builder and turret count
                    local builderText = ""
                    
                    if cachedResults.showingIdle then
                        local idleParts = {}
                        if cachedResults.builderCount > 0 then
                            table.insert(idleParts, cachedResults.builderCount .. " builders")
                        end
                        if cachedResults.turretCount > 0 then
                            table.insert(idleParts, cachedResults.turretCount .. " turrets")
                        end
                        
                        if #idleParts > 0 then
                            builderText = "Ready: " .. table.concat(idleParts, " + ") .. " idle"
                        else
                            builderText = "No idle builders or turrets in range"
                        end
                    else
                        local parts = {}
                        if cachedResults.builderCount > 0 then
                            local builderStr = cachedResults.builderCount .. " builders"
                            if cachedResults.guardingBuilderCount and cachedResults.guardingBuilderCount > 0 then
                                builderStr = builderStr .. " [" .. cachedResults.guardingBuilderCount .. " guarding]"
                            end
                            table.insert(parts, builderStr)
                        end
                        if cachedResults.turretCount > 0 then
                            local turretStr = cachedResults.turretCount .. " turrets"
                            if cachedResults.guardingTurretCount and cachedResults.guardingTurretCount > 0 then
                                turretStr = turretStr .. " [" .. cachedResults.guardingTurretCount .. " guarding]"
                            end
                            table.insert(parts, turretStr)
                        end
                        builderText = "(" .. table.concat(parts, ", ") .. ")"
                    end
                    
                    local yOffset = cachedResults.showingIdle and -45 or (isSpectator and -35 or -20)
                    font:Print(ECO_GRAY .. builderText, screenX, screenY + yOffset, 14, "co")
                    
                    -- Usage rates
                    yOffset = cachedResults.showingIdle and -60 or (isSpectator and -50 or -35)
                    font:Print(ECO_GRAY .. "Usage • " .. formatNumber(cachedResults.metalPerSecond) .. " M/s • " .. 
                              formatNumber(cachedResults.energyPerSecond) .. " E/s", 
                              screenX, screenY + yOffset, 12, "co")
                    
                    -- Storage availability (gray in idle mode)
                    local metalStorageColor = cachedResults.showingIdle and ECO_GRAY or (ecoStatus.hasMetalStorage and ECO_GREEN or ECO_RED)
                    local energyStorageColor = cachedResults.showingIdle and ECO_GRAY or (ecoStatus.hasEnergyStorage and ECO_GREEN or ECO_RED)
                    
                    yOffset = cachedResults.showingIdle and -75 or (isSpectator and -65 or -50)
                    font:Print(ECO_GRAY .. "Storage " ..
                              metalStorageColor .. "• " .. formatNumber(ecoStatus.metalStored) .. " M " ..
                              energyStorageColor .. "• " .. formatNumber(ecoStatus.energyStored) .. " E",
                              screenX, screenY + yOffset, 12, "co")
                    
                    -- Production constraints
                    if ecoStatus.metalDeficit > 0 or ecoStatus.energyDeficit > 0 then
                        local eco = getEconomyInfo()
                        local metalProduction = eco.metalNet or 0
                        local energyProduction = eco.energyNet or 0
                        local metalRequired = cachedResults.metalPerSecond or 0
                        local energyRequired = cachedResults.energyPerSecond or 0
                        
                        local productionText = ""
                        local hasProduction = false
                        if ecoStatus.metalDeficit > 0 and metalRequired > 0 then
                            productionText = productionText .. string.format("• %.0f/%.0f M/s", metalProduction, metalRequired)
                            hasProduction = true
                        end
                        if ecoStatus.energyDeficit > 0 and energyRequired > 0 then
                            if hasProduction then productionText = productionText .. " " end
                            productionText = productionText .. string.format("• %.0f/%.0f E/s", energyProduction, energyRequired)
                        end
                        yOffset = cachedResults.showingIdle and -90 or (isSpectator and -80 or -65)
                        font:Print(ECO_GRAY .. "Production " .. (cachedResults.showingIdle and ECO_GRAY or ECO_RED) .. productionText, screenX, screenY + yOffset, 12, "co")
                    end
                    
                    -- 🎯 Command feedback
                    local currentFrame = Spring.GetGameFrame()
                    if commandFeedbackTime > currentFrame then
                        font:Print(ECO_GRAY .. lastCommandFeedback, screenX, screenY - 95, 12, "co")
                    end
                    
                    font:End()
                else
                    -- Fallback GL rendering
                    local timerColor = {1, 1, 1, 1}
                    if not ecoStatus.canAfford then
                        timerColor = getEcoColorGL(0)
                    elseif ecoStatus.metalPercent < 100 or ecoStatus.energyPercent < 100 then
                        timerColor = getEcoColorGL(75)
                    end
                    
                    gl.Color(timerColor[1], timerColor[2], timerColor[3], timerColor[4])
                    gl.Text("⏱️ " .. cachedResults.timeText, screenX, screenY, 24, "co")
                    
                    -- Show player name in spectator mode
                    if isSpectator and cachedResults.playerName then
                        gl.Color(0.8, 0.8, 0.8, 1)
                        gl.Text("👤 " .. cachedResults.playerName, screenX, screenY - 15, 12, "co")
                    end
                    
                    gl.Color(0.8, 0.8, 0.8, 1)
                    local builderText = ""
                    
                    if cachedResults.showingIdle then
                        local idleParts = {}
                        if cachedResults.builderCount > 0 then
                            table.insert(idleParts, cachedResults.builderCount .. " builders")
                        end
                        if cachedResults.turretCount > 0 then
                            table.insert(idleParts, cachedResults.turretCount .. " turrets")
                        end
                        
                        if #idleParts > 0 then
                            builderText = "Ready: " .. table.concat(idleParts, " + ") .. " idle"
                        else
                            builderText = "No idle builders or turrets in range"
                        end
                    else
                        local parts = {}
                        if cachedResults.builderCount > 0 then
                            local builderStr = cachedResults.builderCount .. " builders"
                            if cachedResults.guardingBuilderCount and cachedResults.guardingBuilderCount > 0 then
                                builderStr = builderStr .. " [" .. cachedResults.guardingBuilderCount .. " guarding]"
                            end
                            table.insert(parts, builderStr)
                        end
                        if cachedResults.turretCount > 0 then
                            local turretStr = cachedResults.turretCount .. " turrets"
                            if cachedResults.guardingTurretCount and cachedResults.guardingTurretCount > 0 then
                                turretStr = turretStr .. " [" .. cachedResults.guardingTurretCount .. " guarding]"
                            end
                            table.insert(parts, turretStr)
                        end
                        builderText = "(" .. table.concat(parts, ", ") .. ")"
                    end
                    
                    local yOffset = isSpectator and -35 or -20
                    gl.Text(builderText, screenX, screenY + yOffset, 14, "co")
                    
                    yOffset = isSpectator and -50 or -35
                    gl.Text("Usage • " .. formatNumber(cachedResults.metalPerSecond) .. " M/s • " .. 
                            formatNumber(cachedResults.energyPerSecond) .. " E/s", screenX, screenY + yOffset, 12, "co")
                    
                    -- Storage with colors
                    yOffset = isSpectator and -65 or -50
                    gl.Color(0.8, 0.8, 0.8, 1)
                    gl.Text("Storage: ", screenX, screenY + yOffset, 12, "co")
                    
                    local metalStorageColorGL = ecoStatus.hasMetalStorage and {0.47, 0.92, 0.47, 1} or {0.94, 0.49, 0.49, 1}
                    local energyStorageColorGL = ecoStatus.hasEnergyStorage and {0.47, 0.92, 0.47, 1} or {0.94, 0.49, 0.49, 1}
                    
                    gl.Color(metalStorageColorGL[1], metalStorageColorGL[2], metalStorageColorGL[3], metalStorageColorGL[4])
                    gl.Text("• " .. formatNumber(ecoStatus.metalStored) .. " M ", screenX + 45, screenY + yOffset, 12, "co")
                    
                    gl.Color(energyStorageColorGL[1], energyStorageColorGL[2], energyStorageColorGL[3], energyStorageColorGL[4])
                    gl.Text("• " .. formatNumber(ecoStatus.energyStored) .. " E", screenX + 90, screenY + yOffset, 12, "co")
                    
                    -- Production constraints
                    if ecoStatus.metalDeficit > 0 or ecoStatus.energyDeficit > 0 then
                        local eco = getEconomyInfo()
                        local metalProduction = eco.metalNet or 0
                        local energyProduction = eco.energyNet or 0
                        local metalRequired = cachedResults.metalPerSecond or 0
                        local energyRequired = cachedResults.energyPerSecond or 0
                        
                        local productionText = ""
                        local hasProduction = false
                        if ecoStatus.metalDeficit > 0 and metalRequired > 0 then
                            productionText = productionText .. string.format("• %.0f/%.0f M/s", metalProduction, metalRequired)
                            hasProduction = true
                        end
                        if ecoStatus.energyDeficit > 0 and energyRequired > 0 then
                            if hasProduction then productionText = productionText .. " " end
                            productionText = productionText .. string.format("• %.0f/%.0f E/s", energyProduction, energyRequired)
                        end
                        
                        yOffset = isSpectator and -80 or -65
                        gl.Color(0.8, 0.8, 0.8, 1)
                        gl.Text("Production ", screenX, screenY + yOffset, 12, "co")
                        gl.Color(0.94, 0.49, 0.49, 1)
                        gl.Text(productionText, screenX + 65, screenY + yOffset, 12, "co")
                    end
                end
            end
        end
    end
    end)
    
    -- Error handling
    if not success then
        Spring.Echo("Build Timer v2 Error: " .. tostring(err))
        gl.Color(1, 0, 0, 1)
        gl.Text("BUILD TIMER V2 ERROR - Check console", 10, 10, 14)
    end
end
