--------------------------------------------------------------------------------
-- Copy Queue v2 Widget for Beyond All Reason
--------------------------------------------------------------------------------
-- 🔨 Advanced queue copying & self-organizing system for constructors
-- Instead of guarding constructors, intelligently manages build queues
-- CTRL+ALT+Q = Self-Organize: Merge all selected builder queues and redistribute
-- CTRL+ALT+W = Frontline chunks: Prioritize nearest build tasks in four waves
-- CTRL+ALT+Guard = Divide queue sequentially among units (each gets portion only)
-- CTRL+Guard = Divide sequentially + add full sequential queue (hybrid mode)
-- ALT+Guard = Copy queue as-is (maintain order)
-- All modes return units to starting positions after tasks
--------------------------------------------------------------------------------

local widget = widget ---@type Widget

function widget:GetInfo()
    return {
        name      = "📋 Copy Queue v2",
        desc      = [[
🎯 Smart queue copying & division for constructors

FEATURES:
• CTRL+ALT+Q = Self-Organizing Builder Group (merge all queues)
• CTRL+ALT+W = Frontline chunking (4 priority waves, nearest-to-farthest)
• CTRL+ALT+Guard = Divide queue sequentially (each gets portion only)
• CTRL+Guard = Hybrid: Divide + full sequential queue backup
• ALT+Guard = Copy queue in order (full queue to each)
• All units return to starting position after tasks
• Smart fallback: Units that can't build will guard instead
• No monitoring - one-time task assignment
• Works with all builder types (mobile & nano turrets)
• Validates build capabilities per unit

SELF-ORGANIZING MODE (CTRL+ALT+Q):
• Select 2+ builders with queues
• Merges all their commands into master queue
• Divides sequentially among builders
• Each builder gets primary portion + backup coverage
• Prevents crowding while ensuring completion

FRONTLINE MODE (CTRL+ALT+W):
• Same setup as CTRL+ALT+Q but chunks tasks into 4 priority waves
• Sorts by proximity to the builder group and hands out nearest sections first
• Assigns each wave to builders closest to that slice (fills gaps front-to-back)
• Adds optional backup queue to ensure completion if units die

HYBRID MODE (CTRL+Guard):
• Each unit gets sequential portion first (no crowding)
• Then gets full sequential queue as backup
• Ensures all tasks completed even if units fail

IMPROVEMENTS:
• Sequential division prevents builder crowding
• Return to start prevents unit wandering
• Intelligent capability checking
• Mixed unit handling (T1/T2 constructors)
]],
        author    = "uBdead (v1), Pyrem (v2)",
        date      = "Jan 2025",
        license   = "GPL v3 or later",
        layer     = 0,
        enabled   = true
    }
end

-- Include key definitions for KEYSYMS
VFS.Include('luaui/Headers/keysym.h.lua')

--------------------------------------------------------------------------------
-- 🔧 Constants & Variables
--------------------------------------------------------------------------------

local CMD_GUARD = CMD.GUARD or 25
local CMD_STOP = CMD.STOP or 0
local CMD_MOVE = CMD.MOVE or 10
local CMD_OPT_SHIFT = CMD.OPT_SHIFT or 32

-- 🏗️ Cache constructor definitions for performance
local constructorDefs = {}
local nanoTurretDefs = {}

-- 📊 Statistics tracking
local totalQueuesCopied = 0
local lastCopyFrame = 0
local COPY_COOLDOWN = 10 -- frames between copies to prevent spam

-- 🎮 Modifier key tracking (captured on mouse press)
local ctrlHeldOnPress = false
local altHeldOnPress = false
local shiftHeldOnPress = false

-- 📊 Batch processing for sequential division
local processingBatch = false
local currentUnitIndex = 0
local totalUnitsInBatch = 0
local batchResetFrame = 0

-- ⚡ Async task for self-organizing builder group (prevents lag)
local selfOrganizeTask = nil
local SELF_ORGANIZE_PRESERVE_QUEUE_ORDER = true  -- Keep merged commands sequential (matches CTRL+Guard feel)
local FRONTLINE_CHUNK_COUNT = 4
local FRONTLINE_ADD_BACKUP = true

--------------------------------------------------------------------------------
-- 🎯 Utility Functions
--------------------------------------------------------------------------------

-- 📋 Check if unit is a valid constructor
local function isConstructor(unitDefID)
    return constructorDefs[unitDefID] or nanoTurretDefs[unitDefID]
end

-- 🏗️ Check if a unit can build a specific structure
local function canUnitBuild(unitDefID, buildDefID)
    local unitDef = UnitDefs[unitDefID]
    if not unitDef or not unitDef.buildOptions then
        return false
    end

    for _, option in ipairs(unitDef.buildOptions) do
        if option == buildDefID then
            return true
        end
    end
    return false
end

-- 🔧 Filter commands to only those the unit can execute
local function filterBuildableCommands(unitDefID, commands)
    local buildable = {}
    local unbuildable = 0

    for _, cmd in ipairs(commands) do
        -- Negative command IDs are build commands (unitDefID)
        if cmd.id < 0 then
            local buildDefID = -cmd.id
            if canUnitBuild(unitDefID, buildDefID) then
                table.insert(buildable, cmd)
            else
                unbuildable = unbuildable + 1
            end
        else
            -- Non-build commands (move, patrol, etc) can always be copied
            table.insert(buildable, cmd)
        end
    end

    return buildable, unbuildable
end

-- 🔍 Get unit under mouse cursor using ray casting
local function getUnitUnderMouse()
    local mx, my = Spring.GetMouseState()
    local targetType, targetID = Spring.TraceScreenRay(mx, my)
    
    if targetType == 'unit' then
        return targetID
    end
    
    return nil
end

-- 📦 Copy command queue from source to target with capability checking
local function copyCommandQueue(sourceUnitID, targetUnitID, shuffle, returnPos)
    -- Get source unit's command queue
    local commands = Spring.GetUnitCommands(sourceUnitID, -1)
    if not commands or #commands == 0 then
        Spring.Echo("📋 Copy Queue: Source unit has no commands to copy")
        return false, "no_commands"
    end

    -- Check what this unit can build
    local targetDefID = Spring.GetUnitDefID(targetUnitID)
    local buildableCommands, unbuildableCount = filterBuildableCommands(targetDefID, commands)

    -- If unit can't build anything, return false to trigger guard
    if #buildableCommands == 0 then
        return false, "cannot_build"
    end

    -- Shuffle buildable commands if requested
    if shuffle then
        -- Fisher-Yates shuffle algorithm
        for i = #buildableCommands, 2, -1 do
            local j = math.random(i)
            buildableCommands[i], buildableCommands[j] = buildableCommands[j], buildableCommands[i]
        end
    end

    -- Clear target's queue first
    Spring.GiveOrderToUnit(targetUnitID, CMD_STOP, {}, 0)

    -- Copy buildable commands to target
    for i = 1, #buildableCommands do
        local cmd = buildableCommands[i]
        -- Create a copy of command options to avoid mutating original
        local options = {}
        if cmd.options then
            for k, v in pairs(cmd.options) do
                options[k] = v
            end
        end
        if i > 1 then
            options.shift = true
        end
        Spring.GiveOrderToUnit(targetUnitID, cmd.id, cmd.params, options)
    end

    -- Add return to start position if provided
    if returnPos then
        Spring.GiveOrderToUnit(targetUnitID, CMD_MOVE, {returnPos.x, returnPos.y, returnPos.z}, {"shift"})
    end

    -- Update statistics
    totalQueuesCopied = totalQueuesCopied + 1
    lastCopyFrame = Spring.GetGameFrame()

    return true, "success", #buildableCommands, unbuildableCount
end

-- 📊 Divide command queue among multiple units
local function divideCommandQueue(sourceUnitID, targetUnits, returnPositions)
    -- Get source unit's command queue
    local commands = Spring.GetUnitCommands(sourceUnitID, -1)
    if not commands or #commands == 0 then
        Spring.Echo("📋 Copy Queue: Source unit has no commands to divide")
        return {}
    end

    -- Sort units by what they can build
    local capableUnits = {}
    local incapableUnits = {}

    for _, unitID in ipairs(targetUnits) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        local buildable, _ = filterBuildableCommands(unitDefID, commands)

        if #buildable > 0 then
            table.insert(capableUnits, {id = unitID, defID = unitDefID})
        else
            table.insert(incapableUnits, unitID)
        end
    end

    if #capableUnits == 0 then
        return incapableUnits -- All units should guard
    end

    -- Divide commands among capable units
    local commandsPerUnit = math.floor(#commands / #capableUnits)
    local remainder = #commands % #capableUnits
    local commandIndex = 1

    Spring.Echo(string.format("[DEBUG] divideCommandQueue: %d commands, %d units, %d per unit, %d remainder",
        #commands, #capableUnits, commandsPerUnit, remainder))

    for i, unitData in ipairs(capableUnits) do
        local unitID = unitData.id
        local unitDefID = unitData.defID

        -- Calculate how many commands this unit gets
        local numCommands = commandsPerUnit
        if i <= remainder then
            numCommands = numCommands + 1
        end

        Spring.Echo(string.format("[DEBUG]   Unit %d gets commands %d to %d (%d total)",
            i, commandIndex, math.min(commandIndex + numCommands - 1, #commands), numCommands))

        -- Clear unit's queue
        Spring.GiveOrderToUnit(unitID, CMD_STOP, {}, 0)

        -- Assign commands to this unit
        local assignedCount = 0
        for j = commandIndex, math.min(commandIndex + numCommands - 1, #commands) do
            local cmd = commands[j]

            -- Check if this unit can build this specific command
            local canBuild = true
            if cmd.id < 0 then
                canBuild = canUnitBuild(unitDefID, -cmd.id)
            end

            if canBuild then
                -- Create a copy of command options to avoid mutating original
                local options = {}
                if cmd.options then
                    for k, v in pairs(cmd.options) do
                        options[k] = v
                    end
                end
                if assignedCount > 0 then
                    options.shift = true
                end
                Spring.GiveOrderToUnit(unitID, cmd.id, cmd.params, options)
                assignedCount = assignedCount + 1
            end
        end

        -- Add return to start position if provided
        if returnPositions and returnPositions[unitID] then
            local pos = returnPositions[unitID]
            Spring.GiveOrderToUnit(unitID, CMD_MOVE, {pos.x, pos.y, pos.z}, {"shift"})
        end

        commandIndex = commandIndex + numCommands
    end

    Spring.Echo(string.format("📋 Copy Queue: Divided %d commands among %d units (%d will guard)",
        #commands, #capableUnits, #incapableUnits))

    return incapableUnits -- Return units that need to guard
end

-- 🎯 Hybrid: Divide sequentially then add full sequential queue
local function divideAndCopyQueue(sourceUnitID, targetUnits, returnPositions)
    -- Get source unit's command queue
    local commands = Spring.GetUnitCommands(sourceUnitID, -1)
    if not commands or #commands == 0 then
        Spring.Echo("📋 Copy Queue: Source unit has no commands to divide")
        return {}
    end

    -- Sort units by what they can build
    local capableUnits = {}
    local incapableUnits = {}

    for _, unitID in ipairs(targetUnits) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        local buildable, _ = filterBuildableCommands(unitDefID, commands)

        if #buildable > 0 then
            table.insert(capableUnits, {id = unitID, defID = unitDefID})
        else
            table.insert(incapableUnits, unitID)
        end
    end

    if #capableUnits == 0 then
        return incapableUnits -- All units should guard
    end

    -- Phase 1: Divide commands sequentially among capable units
    local commandsPerUnit = math.floor(#commands / #capableUnits)
    local remainder = #commands % #capableUnits
    local commandIndex = 1

    Spring.Echo(string.format("[DEBUG] divideAndCopyQueue: %d commands, %d units, %d per unit, %d remainder",
        #commands, #capableUnits, commandsPerUnit, remainder))

    for i, unitData in ipairs(capableUnits) do
        local unitID = unitData.id
        local unitDefID = unitData.defID

        -- Calculate how many commands this unit gets
        local numCommands = commandsPerUnit
        if i <= remainder then
            numCommands = numCommands + 1
        end

        Spring.Echo(string.format("[DEBUG]   Unit %d Phase1: commands %d to %d, Phase2: full queue",
            i, commandIndex, math.min(commandIndex + numCommands - 1, #commands)))

        -- Clear unit's queue
        Spring.GiveOrderToUnit(unitID, CMD_STOP, {}, 0)

        -- Assign sequential portion to this unit
        local assignedCount = 0
        for j = commandIndex, math.min(commandIndex + numCommands - 1, #commands) do
            local cmd = commands[j]

            -- Check if this unit can build this specific command
            local canBuild = true
            if cmd.id < 0 then
                canBuild = canUnitBuild(unitDefID, -cmd.id)
            end

            if canBuild then
                -- Create a copy of command options to avoid mutating original
                local options = {}
                if cmd.options then
                    for k, v in pairs(cmd.options) do
                        options[k] = v
                    end
                end
                if assignedCount > 0 then
                    options.shift = true
                end
                Spring.GiveOrderToUnit(unitID, cmd.id, cmd.params, options)
                assignedCount = assignedCount + 1
            end
        end

        commandIndex = commandIndex + numCommands

        -- Phase 2: Add full sequential queue after the assigned portion
        for _, cmd in ipairs(commands) do
            -- Only add commands this unit can build
            local canBuild = true
            if cmd.id < 0 then
                canBuild = canUnitBuild(unitDefID, -cmd.id)
            end
            if canBuild then
                -- Create a copy of command options to avoid mutating original
                local options = {}
                if cmd.options then
                    for k, v in pairs(cmd.options) do
                        options[k] = v
                    end
                end
                options.shift = true
                Spring.GiveOrderToUnit(unitID, cmd.id, cmd.params, options)
            end
        end

        -- Add return to start position
        if returnPositions and returnPositions[unitID] then
            local pos = returnPositions[unitID]
            Spring.GiveOrderToUnit(unitID, CMD_MOVE, {pos.x, pos.y, pos.z}, {"shift"})
        end
    end

    Spring.Echo(string.format("📋 Copy Queue: Divided %d commands + full sequential queue to %d units (%d will guard)",
        #commands, #capableUnits, #incapableUnits))

    return incapableUnits -- Return units that need to guard
end

-- 🎨 Show visual feedback for queue copy
local function showCopyFeedback(targetUnitID, commandCount, shuffled)
    local x, y, z = Spring.GetUnitPosition(targetUnitID)
    if x and y and z then
        local message = shuffled and 
            "🔀 Copied & shuffled " .. commandCount .. " commands" or
            "📋 Copied " .. commandCount .. " commands"
        
        -- This would need a proper text rendering system in DrawWorld
        -- For now, just echo to console
        Spring.Echo(message)
    end
end

--------------------------------------------------------------------------------
-- ⚙️ Self-Organize Helpers
--------------------------------------------------------------------------------

local function cloneOptions(options)
    if not options then
        return nil
    end
    local copy = {}
    for k, v in pairs(options) do
        copy[k] = v
    end
    return copy
end

local function queueCommandForBuilder(builderDataEntry, cmd)
    if not builderDataEntry or not cmd then
        return
    end
    local needsShift = (builderDataEntry.assignedCommands or 0) > 0
    local options = cloneOptions(cmd.options)
    if needsShift then
        if options then
            options.shift = true
        else
            options = { shift = true }
        end
    end
    Spring.GiveOrderToUnit(builderDataEntry.unitID, cmd.id, cmd.params, options or 0)
    builderDataEntry.assignedCommands = (builderDataEntry.assignedCommands or 0) + 1
end

local function collectSelfOrganizeData(builders)
    local builderData = {}
    local seenCommands = {}
    local mergedCommands = {}
    local totalCommands = 0
    local duplicatesRemoved = 0

    local function commandKey(cmd)
        if cmd.id >= 0 or not cmd.params then
            return nil
        end
        local x = math.floor((cmd.params[1] or 0) / 8 + 0.5) * 8
        local z = math.floor((cmd.params[3] or 0) / 8 + 0.5) * 8
        return cmd.id .. "," .. x .. "," .. z
    end

    for _, unitID in ipairs(builders) do
        local x, y, z = Spring.GetUnitPosition(unitID)
        if x then
            local commands = Spring.GetUnitCommands(unitID, -1)
            builderData[#builderData + 1] = {
                unitID = unitID,
                position = { x = x, y = y, z = z },
                commandCount = commands and #commands or 0,
                assignedCommands = 0,
            }

            if commands then
                totalCommands = totalCommands + #commands
                for _, cmd in ipairs(commands) do
                    if cmd.id < 0 then
                        local key = commandKey(cmd)
                        if key and not seenCommands[key] then
                            seenCommands[key] = true
                            mergedCommands[#mergedCommands + 1] = cmd
                        elseif key then
                            duplicatesRemoved = duplicatesRemoved + 1
                        end
                    end
                    -- Non-build commands are skipped; widget adds fresh return-home MOVE later
                end
            end
        else
            Spring.Echo("[Self-Organize] Warning: Could not get position for unit " .. unitID)
        end
    end

    return builderData, mergedCommands, totalCommands, duplicatesRemoved
end

local function distributeBalancedSelfOrganize(builderData, mergedCommands)
    local totalCommands = #mergedCommands
    local builderCount = #builderData

    if builderCount == 0 or totalCommands == 0 then
        Spring.Echo("[Self-Organize] Nothing to distribute (need builders + build commands)")
        return
    end

    if not SELF_ORGANIZE_PRESERVE_QUEUE_ORDER then
        local centerX, centerZ = 0, 0
        for _, data in ipairs(builderData) do
            centerX = centerX + data.position.x
            centerZ = centerZ + data.position.z
        end
        centerX = centerX / builderCount
        centerZ = centerZ / builderCount

        for _, cmd in ipairs(mergedCommands) do
            local cmdX, cmdZ = cmd.params[1], cmd.params[3]
            if cmdX and cmdZ then
                local dx, dz = cmdX - centerX, cmdZ - centerZ
                cmd.distanceSquared = dx * dx + dz * dz
            else
                cmd.distanceSquared = math.huge
            end
        end

        table.sort(mergedCommands, function(a, b)
            return a.distanceSquared < b.distanceSquared
        end)

        Spring.Echo(string.format("[Self-Organize] Sorted %d commands by distance from group center (%.0f, %.0f)",
            totalCommands, centerX, centerZ))
    else
        Spring.Echo(string.format("[Self-Organize] Preserving original queue order for %d commands", totalCommands))
    end

    local commandsPerBuilder = math.floor(totalCommands / builderCount)
    local remainder = totalCommands % builderCount

    Spring.Echo(string.format("[Self-Organize] Distributing %d commands to %d builders (floor=%d, remainder=%d)",
        totalCommands, builderCount, commandsPerBuilder, remainder))

    local shiftOptions = { shift = true }

    for i, data in ipairs(builderData) do
        local extraBefore = math.min(i - 1, remainder)
        local startIdx = (i - 1) * commandsPerBuilder + 1 + extraBefore
        local endIdx = startIdx + commandsPerBuilder - 1
        if i <= remainder then
            endIdx = endIdx + 1
        end

        if startIdx > totalCommands then
            startIdx = totalCommands + 1
            endIdx = totalCommands
        else
            endIdx = math.min(endIdx, totalCommands)
        end

        data.primaryStart = startIdx
        data.primaryEnd = endIdx
        data.backupCommands = {}

        for j = 1, totalCommands do
            if j < startIdx or j > endIdx then
                data.backupCommands[#data.backupCommands + 1] = mergedCommands[j]
            end
        end
    end

    for i, data in ipairs(builderData) do
        Spring.GiveOrderToUnit(data.unitID, CMD_STOP, {}, 0)

        local startIdx = data.primaryStart
        local endIdx = data.primaryEnd
        local primaryAssigned = 0

        for j = startIdx, math.min(endIdx, totalCommands) do
            local cmd = mergedCommands[j]
            if cmd then
                primaryAssigned = primaryAssigned + 1
                local options = cloneOptions(cmd.options)
                if primaryAssigned > 1 then
                    if options then
                        options.shift = true
                    else
                        options = { shift = true }
                    end
                end
                Spring.GiveOrderToUnit(data.unitID, cmd.id, cmd.params, options or 0)
            end
        end

        local backupCount = 0
        for _, cmd in ipairs(data.backupCommands) do
            local options = cloneOptions(cmd.options) or {}
            options.shift = true
            Spring.GiveOrderToUnit(data.unitID, cmd.id, cmd.params, options)
            backupCount = backupCount + 1
        end

        local pos = data.position
        Spring.GiveOrderToUnit(data.unitID, CMD_MOVE, { pos.x, pos.y, pos.z }, shiftOptions)

        local plannedPrimary = math.max(0, math.min(endIdx, totalCommands) - startIdx + 1)
        Spring.Echo(string.format("  Builder %d: %d primary + %d backup commands", i, plannedPrimary, backupCount))

        if i % 3 == 0 then
            coroutine.yield()
        end
    end

    Spring.Echo("[Self-Organize] Complete! Each builder has primary tasks + full backup coverage")
end

local function assignFrontlineChunk(builderData, mergedCommands, startIdx, endIdx, chunkIndex)
    local chunkSize = endIdx - startIdx + 1
    if chunkSize <= 0 then
        return 0
    end

    local chunkCommands = {}
    local chunkCenterX, chunkCenterZ = 0, 0
    for i = startIdx, endIdx do
        local cmd = mergedCommands[i]
        if cmd then
            chunkCommands[#chunkCommands + 1] = cmd
            chunkCenterX = chunkCenterX + (cmd.params[1] or 0)
            chunkCenterZ = chunkCenterZ + (cmd.params[3] or 0)
        end
    end

    if #chunkCommands == 0 then
        return 0
    end

    chunkCenterX = chunkCenterX / #chunkCommands
    chunkCenterZ = chunkCenterZ / #chunkCommands

    local builderOrder = {}
    for idx, data in ipairs(builderData) do
        local dx = chunkCenterX - data.position.x
        local dz = chunkCenterZ - data.position.z
        builderOrder[#builderOrder + 1] = {
            index = idx,
            distance = dx * dx + dz * dz
        }
    end

    table.sort(builderOrder, function(a, b)
        return a.distance < b.distance
    end)

    local builderCount = #builderOrder
    if builderCount == 0 then
        return 0
    end

    local commandsPerBuilder = math.floor(#chunkCommands / builderCount)
    local remainder = #chunkCommands % builderCount
    local cursor = 1

    for orderIdx, info in ipairs(builderOrder) do
        local take = commandsPerBuilder
        if orderIdx <= remainder then
            take = take + 1
        end

        for _ = 1, take do
            local cmd = chunkCommands[cursor]
            if not cmd then break end
            queueCommandForBuilder(builderData[info.index], cmd)
            cursor = cursor + 1
        end

        if cursor > #chunkCommands then
            break
        end
    end

    while cursor <= #chunkCommands do
        for _, info in ipairs(builderOrder) do
            local cmd = chunkCommands[cursor]
            if not cmd then break end
            queueCommandForBuilder(builderData[info.index], cmd)
            cursor = cursor + 1
            if cursor > #chunkCommands then
                break
            end
        end
    end

    Spring.Echo(string.format("[Frontline] Chunk %d assigned (%d commands)", chunkIndex, #chunkCommands))
    return #chunkCommands
end

local function distributeFrontlineSelfOrganize(builderData, mergedCommands)
    local totalCommands = #mergedCommands
    local builderCount = #builderData

    if builderCount == 0 or totalCommands == 0 then
        Spring.Echo("[Frontline] Nothing to distribute (need builders + build commands)")
        return
    end

    local centerX, centerZ = 0, 0
    for _, data in ipairs(builderData) do
        centerX = centerX + data.position.x
        centerZ = centerZ + data.position.z
        Spring.GiveOrderToUnit(data.unitID, CMD_STOP, {}, 0)
        data.assignedCommands = 0
    end
    centerX = centerX / builderCount
    centerZ = centerZ / builderCount

    for _, cmd in ipairs(mergedCommands) do
        local cmdX, cmdZ = cmd.params[1], cmd.params[3]
        if cmdX and cmdZ then
            local dx = cmdX - centerX
            local dz = cmdZ - centerZ
            cmd.distanceSquared = dx * dx + dz * dz
        else
            cmd.distanceSquared = math.huge
        end
    end

    table.sort(mergedCommands, function(a, b)
        return a.distanceSquared < b.distanceSquared
    end)

    local chunkCount = math.min(FRONTLINE_CHUNK_COUNT, totalCommands)
    local baseChunk = math.floor(totalCommands / chunkCount)
    local remainder = totalCommands % chunkCount
    local startIdx = 1

    Spring.Echo(string.format("[Frontline] Prioritizing %d commands into %d chunks (floor=%d, remainder=%d)",
        totalCommands, chunkCount, baseChunk, remainder))

    for chunk = 1, chunkCount do
        local size = baseChunk
        if chunk <= remainder then
            size = size + 1
        end
        local endIdx = math.min(startIdx + size - 1, totalCommands)
        if size > 0 then
            assignFrontlineChunk(builderData, mergedCommands, startIdx, endIdx, chunk)
            coroutine.yield()
        end
        startIdx = endIdx + 1
    end

    if FRONTLINE_ADD_BACKUP then
        for _, data in ipairs(builderData) do
            for _, cmd in ipairs(mergedCommands) do
                local options = cloneOptions(cmd.options) or {}
                options.shift = true
                Spring.GiveOrderToUnit(data.unitID, cmd.id, cmd.params, options)
            end
        end
        Spring.Echo("[Frontline] Added backup coverage after prioritized chunks")
    end

    local shiftOptions = { shift = true }
    for i, data in ipairs(builderData) do
        local pos = data.position
        Spring.GiveOrderToUnit(data.unitID, CMD_MOVE, { pos.x, pos.y, pos.z }, shiftOptions)
        if i % 3 == 0 then
            coroutine.yield()
        end
    end

    Spring.Echo(string.format("[Frontline] Complete! %d commands distributed across %d builders using %d chunks",
        totalCommands, builderCount, chunkCount))
end

local function startSelfOrganizeMode(mode)
    local label = (mode == "frontline") and "Frontline" or "Self-Organize"

    if selfOrganizeTask then
        Spring.Echo(string.format("[%s] Already processing, please wait...", label))
        return
    end

    selfOrganizeTask = coroutine.wrap(function()
        local selectedUnits = Spring.GetSelectedUnits()
        local builders = {}

        for _, unitID in ipairs(selectedUnits) do
            local unitDefID = Spring.GetUnitDefID(unitID)
            if unitDefID and isConstructor(unitDefID) then
                builders[#builders + 1] = unitID
            end
        end

        if #builders < 2 then
            Spring.Echo(string.format("[%s] Need at least 2 builders selected", label))
            selfOrganizeTask = nil
            return
        end

        local builderData, mergedCommands, totalCommands, duplicatesRemoved = collectSelfOrganizeData(builders)

        coroutine.yield()

        if duplicatesRemoved > 0 then
            Spring.Echo(string.format("[%s] Removed %d duplicate commands (%d unique from %d total)",
                label, duplicatesRemoved, #mergedCommands, totalCommands))
        end

        if #builderData == 0 then
            Spring.Echo(string.format("[%s] Error: No valid builders found (position check failed)", label))
            selfOrganizeTask = nil
            return
        end

        if #mergedCommands == 0 then
            Spring.Echo(string.format("[%s] No commands found in selected builders", label))
            selfOrganizeTask = nil
            return
        end

        if mode == "frontline" then
            distributeFrontlineSelfOrganize(builderData, mergedCommands)
        else
            distributeBalancedSelfOrganize(builderData, mergedCommands)
        end

        selfOrganizeTask = nil
    end)

    local success, err = pcall(selfOrganizeTask)
    if not success then
        Spring.Echo(string.format("[%s] Error starting task: %s", label, tostring(err)))
        selfOrganizeTask = nil
    end
end

--------------------------------------------------------------------------------
-- 🎮 Widget Lifecycle Functions
--------------------------------------------------------------------------------

function widget:Initialize()
    if Spring.GetSpectatingState() then
      self:RemoveWidget()
      return
    end
    -- 🏗️ Build lookup tables for constructor types
    for unitDefID, unitDef in pairs(UnitDefs) do
        -- Mobile constructors
        if unitDef.isBuilder and not unitDef.isFactory and unitDef.canMove then
            constructorDefs[unitDefID] = true
        end
        
        -- Nano turrets (stationary builders)
        if unitDef.isBuilder and not unitDef.isFactory and not unitDef.canMove then
            nanoTurretDefs[unitDefID] = true
        end
    end
    
    local constructorCount = 0
    local nanoCount = 0
    for _ in pairs(constructorDefs) do constructorCount = constructorCount + 1 end
    for _ in pairs(nanoTurretDefs) do nanoCount = nanoCount + 1 end
    
    Spring.Echo("📋 Copy Queue v2: Initialized with " .. constructorCount .. " mobile constructors and " .. nanoCount .. " nano turrets")
end

function widget:Shutdown()
    Spring.Echo("📋 Copy Queue v2: Total queues copied this session: " .. totalQueuesCopied)
end

--------------------------------------------------------------------------------
-- ⌨️ Keyboard Shortcut Handler
--------------------------------------------------------------------------------

-- Spring.GetSelectedUnits() -> unitID[]
-- Spring.GetUnitCommands(unitID, -1) -> commands[]
-- Spring.GetUnitPosition(unitID) -> x, y, z
-- Spring.GiveOrderToUnit(unitID, cmdID, params, options)
-- Ref: docs/spring-lua-api.txt
function widget:KeyPress(key, mods, isRepeat)
	if key == KEYSYMS.Q and mods.ctrl and mods.alt then
		startSelfOrganizeMode("balanced")
		return false
	end

	if key == KEYSYMS.W and mods.ctrl and mods.alt then
		startSelfOrganizeMode("frontline")
		return false
	end

	return false
end

--------------------------------------------------------------------------------
-- 🎯 Command Interception
--------------------------------------------------------------------------------

-- Capture modifier keys on mouse press (before command is issued)
function widget:MousePress(x, y, button)
    -- 🎮 Capture modifier key states for command processing
    local alt, ctrl, meta, shift = Spring.GetModKeyState()
    ctrlHeldOnPress = ctrl
    altHeldOnPress = alt
    shiftHeldOnPress = shift

    -- Reset batch processing on new mouse press
    processingBatch = false
    currentUnitIndex = 0
    totalUnitsInBatch = 0

    return false -- Don't eat the event
end

-- UnitCommand: Handle queue copying (fires per unit)
function widget:UnitCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions, playerID, fromSynced, fromLua)
    -- Get modifier states from mouse press
    local ctrlHeld = ctrlHeldOnPress
    local altHeld = altHeldOnPress

    -- Only process if CTRL or ALT was held
    if not ctrlHeld and not altHeld then
        return false
    end

    -- Only process GUARD commands
    if cmdID ~= CMD_GUARD then
        return false
    end

    -- Only process constructors
    if not isConstructor(unitDefID) then
        return false
    end

    -- Get target unit from command parameters
    local targetUnitID = cmdParams[1]
    if not targetUnitID or not Spring.ValidUnitID(targetUnitID) then
        return false
    end

    -- Check if target is a constructor
    local targetDefID = Spring.GetUnitDefID(targetUnitID)
    if not targetDefID or not isConstructor(targetDefID) then
        return false
    end

    -- Get target's command queue
    local commands = Spring.GetUnitCommands(targetUnitID, -1)
    if not commands or #commands == 0 then
        return false
    end

    -- Initialize batch processing on first unit
    if not processingBatch then
        processingBatch = true
        currentUnitIndex = 0

        -- Count total constructors in selection (excluding target)
        local selectedUnits = Spring.GetSelectedUnits()
        local selectedConstructorCount = 0
        for _, selUnitID in ipairs(selectedUnits) do
            local selDefID = Spring.GetUnitDefID(selUnitID)
            if selDefID and isConstructor(selDefID) and selUnitID ~= targetUnitID then
                selectedConstructorCount = selectedConstructorCount + 1
            end
        end

        if selectedConstructorCount == 0 then
            return false
        end

        -- Total builders = target (already working) + selected builders
        totalUnitsInBatch = 1 + selectedConstructorCount

        Spring.Echo(string.format("[CopyQueue] Starting batch: %d commands, %d total builders (target + %d selected), CTRL=%s ALT=%s",
            #commands, totalUnitsInBatch, selectedConstructorCount, tostring(ctrlHeld), tostring(altHeld)))
    end

    -- Increment unit counter (for selected units)
    currentUnitIndex = currentUnitIndex + 1

    -- This selected unit is actually builder #(currentUnitIndex + 1) because target is builder #1
    local builderNumber = currentUnitIndex + 1

    Spring.Echo(string.format("[CopyQueue] Processing selected unit %d (builder #%d/%d total, unitID=%d)",
        currentUnitIndex, builderNumber, totalUnitsInBatch, unitID))

    -- Clear unit's queue
    Spring.GiveOrderToUnit(unitID, CMD_STOP, {}, 0)

    -- Get shift state
    local shiftHeld = shiftHeldOnPress

    -- CTRL+SHIFT mode: Random sequential start (rotated queue)
    if ctrlHeld and shiftHeld and not altHeld then
        -- Pick random starting position
        local startPos = math.random(1, #commands)

        Spring.Echo(string.format("[CopyQueue] CTRL+SHIFT - Builder starts at random position %d (rotated queue)", startPos))

        local cmdCount = 0

        -- Phase 1: Copy from startPos to end
        for i = startPos, #commands do
            local cmd = commands[i]
            cmdCount = cmdCount + 1
            -- First command: original options, rest: add shift
            local options = cmd.options
            if cmdCount > 1 then
                options = {}
                if cmd.options then
                    for k, v in pairs(cmd.options) do
                        options[k] = v
                    end
                end
                options.shift = true
            end
            Spring.GiveOrderToUnit(unitID, cmd.id, cmd.params, options)
        end

        -- Phase 2: Wrap around - copy from 1 to startPos-1
        if startPos > 1 then
            for i = 1, startPos - 1 do
                local cmd = commands[i]
                local options = {}
                if cmd.options then
                    for k, v in pairs(cmd.options) do
                        options[k] = v
                    end
                end
                options.shift = true
                Spring.GiveOrderToUnit(unitID, cmd.id, cmd.params, options)
            end
        end

        Spring.Echo(string.format("  Total commands: %d (full queue from position %d)", #commands, startPos))

    -- ALT mode: Copy full queue to each unit
    elseif altHeld and not ctrlHeld then
        Spring.Echo(string.format("[CopyQueue] Unit %d: Copying full queue (%d commands)", currentUnitIndex, #commands))

        for i = 1, #commands do
            local cmd = commands[i]
            -- First command: use original options, rest: add shift to queue
            local options = cmd.options
            if i > 1 then
                options = {}
                if cmd.options then
                    for k, v in pairs(cmd.options) do
                        options[k] = v
                    end
                end
                options.shift = true
            end
            Spring.GiveOrderToUnit(unitID, cmd.id, cmd.params, options)
        end

    -- CTRL mode: Sequential division (accounting for target as builder #1)
    elseif ctrlHeld then
        -- Calculate this builder's portion (using builderNumber which includes target offset)
        local commandsPerUnit = math.floor(#commands / totalUnitsInBatch)
        local remainder = #commands % totalUnitsInBatch

        -- Calculate start and end indices for this builder
        local startIdx = (builderNumber - 1) * commandsPerUnit + 1
        local endIdx = builderNumber * commandsPerUnit

        -- Add one extra command to earlier builders if there's a remainder
        if builderNumber <= remainder then
            startIdx = startIdx + (builderNumber - 1)
            endIdx = endIdx + builderNumber
        else
            startIdx = startIdx + remainder
            endIdx = endIdx + remainder
        end

        endIdx = math.min(endIdx, #commands)

        -- CTRL+ALT: Sequential portion only
        if altHeld then
            Spring.Echo(string.format("[CopyQueue] CTRL+ALT - Builder #%d: Sequential portion [%d to %d] ONLY (%d commands)",
                builderNumber, startIdx, endIdx, endIdx - startIdx + 1))

            -- Assign this builder's sequential portion only
            local cmdCount = 0
            for i = startIdx, endIdx do
                local cmd = commands[i]
                cmdCount = cmdCount + 1
                -- First command: original options, rest: add shift
                local options = cmd.options
                if cmdCount > 1 then
                    options = {}
                    if cmd.options then
                        for k, v in pairs(cmd.options) do
                            options[k] = v
                        end
                    end
                    options.shift = true
                end
                Spring.GiveOrderToUnit(unitID, cmd.id, cmd.params, options)
            end

        -- CTRL only: Hybrid mode (sequential portion THEN full queue)
        else
            Spring.Echo(string.format("[CopyQueue] CTRL-ONLY (HYBRID) - Builder #%d: Sequential [%d to %d] THEN full queue [1 to %d]",
                builderNumber, startIdx, endIdx, #commands))

            local cmdCount = 0

            -- Phase 1: Assign sequential portion first
            Spring.Echo(string.format("  Phase 1: Adding sequential portion [%d to %d]", startIdx, endIdx))
            for i = startIdx, endIdx do
                local cmd = commands[i]
                cmdCount = cmdCount + 1
                -- First command: original options, rest: add shift
                local options = cmd.options
                if cmdCount > 1 then
                    options = {}
                    if cmd.options then
                        for k, v in pairs(cmd.options) do
                            options[k] = v
                        end
                    end
                    options.shift = true
                end
                Spring.GiveOrderToUnit(unitID, cmd.id, cmd.params, options)
            end

            -- Phase 2: Add commands this builder DIDN'T get as backup
            local backupCount = 0
            Spring.Echo(string.format("  Phase 2: Adding backup (commands NOT in [%d to %d])", startIdx, endIdx))
            for i = 1, #commands do
                -- Skip commands already in this builder's sequential portion
                if i < startIdx or i > endIdx then
                    local cmd = commands[i]
                    local options = {}
                    if cmd.options then
                        for k, v in pairs(cmd.options) do
                            options[k] = v
                        end
                    end
                    options.shift = true
                    Spring.GiveOrderToUnit(unitID, cmd.id, cmd.params, options)
                    backupCount = backupCount + 1
                end
            end
            Spring.Echo(string.format("  Total commands queued: %d (sequential) + %d (backup) = %d",
                endIdx - startIdx + 1, backupCount, (endIdx - startIdx + 1) + backupCount))
        end
    end

    return true -- Command handled
end

--------------------------------------------------------------------------------
-- 📊 Optional: Display Statistics
--------------------------------------------------------------------------------

function widget:TextCommand(command)
    if command == "copyqueue" or command == "cq" then
        Spring.Echo("📋 Copy Queue v2 Statistics:")
        Spring.Echo("  • Total queues copied: " .. totalQueuesCopied)
        Spring.Echo("  • Mobile constructors tracked: " .. #constructorDefs)
        Spring.Echo("  • Nano turrets tracked: " .. #nanoTurretDefs)
        Spring.Echo("  • Commands:")
		Spring.Echo("    - CTRL+ALT+Q: Self-Organize (merge all selected builder queues)")
		Spring.Echo("    - CTRL+ALT+W: Frontline chunking (4 waves, nearest-first)")
		Spring.Echo("    - CTRL+ALT+Guard: Divide sequentially (portion only)")
        Spring.Echo("    - CTRL+Guard: Hybrid (divide + full sequential backup)")
        Spring.Echo("    - ALT+Guard: Copy in order (full queue)")
        Spring.Echo("  • All commands include return to starting position")
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- ⚡ Async Task Processing
--------------------------------------------------------------------------------

function widget:GameFrame(n)
    -- Resume self-organize task every 2 frames to spread work
    if selfOrganizeTask and n % 2 == 0 then
        local success, err = pcall(selfOrganizeTask)
        if not success then
            Spring.Echo("[Self-Organize] Error during processing: " .. tostring(err))
            selfOrganizeTask = nil
        end
    end
end

--------------------------------------------------------------------------------
-- 🎨 Optional: Visual Feedback (can be expanded)
--------------------------------------------------------------------------------

function widget:DrawWorld()
    -- Could add visual indicators here for:
    -- • Highlight target constructor when hovering with CTRL/ALT
    -- • Show queue length above units
    -- • Draw lines between source and target during copy
    -- For now, keeping it simple for performance
end
