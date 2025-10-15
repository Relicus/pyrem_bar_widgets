-- 🎯 WIDGET INFO: Holo Place V4 Lite - Smart Auto Mode + Best Nano Selection + Performance Optimized
function widget:GetInfo()
    return {
        name    = "⚡ Holo Place V4 Lite",
        desc    = "Smart auto mode with best nano selection (No visuals, maximum performance, frame-throttled)",
        author  = "augustin, manshanko, then enchanced by Pyrem",
        date    = "2025-10-05",
        layer   = 2,
        enabled = false,  -- Disabled by default (enable manually, disable v3 first)
        handler = true,
    }
end

-- 📦 STEP 1: LOCALIZE SPRING API FUNCTIONS
local echo = Spring.Echo
local i18n = Spring.I18N
local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitCommandCount = Spring.GetUnitCommandCount
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitIsBeingBuilt = Spring.GetUnitIsBeingBuilt
local GetUnitIsBuilding = Spring.GetUnitIsBuilding
local GetUnitCommands = Spring.GetUnitCommands
local GetUnitCurrentCommand = Spring.GetUnitCurrentCommand
local GetUnitPosition = Spring.GetUnitPosition
local GetUnitSeparation = Spring.GetUnitSeparation
local GetUnitsInCylinder = Spring.GetUnitsInCylinder
local GiveOrderToUnit = Spring.GiveOrderToUnit
local ValidUnitID = Spring.ValidUnitID
local GetUnitHealth = Spring.GetUnitHealth
local GetMyTeamID = Spring.GetMyTeamID
local UnitDefs = UnitDefs
local CMD_REPAIR = CMD.REPAIR
local CMD_REMOVE = CMD.REMOVE
local CMD_FIGHT = CMD.FIGHT
local CMD_WAIT = CMD.WAIT

-- 🎮 STEP 2: DEFINE CUSTOM COMMAND
local CMD_HOLO_PLACE = 28341  -- Different ID to avoid conflict
local CMD_HOLO_PLACE_DESCRIPTION = {
    id = CMD_HOLO_PLACE,
    type = CMDTYPE.ICON_MODE,
    name = "Holo Place",
    cursor = nil,
    action = "holo_place",
    -- Params order: current_mode, mode0, mode1, mode2, mode3, mode4, mode5
    -- Visual cycling: Off → Smart → 90 → 60 → 30 → Ins
    params = { 1, "holo_place_off", "holo_place_smart", "holo_place_90", "holo_place_60", "holo_place_30", "holo_place_ins" }
}

-- 🌍 STEP 3: SET UP INTERNATIONALIZATION
i18n.set("en.ui.orderMenu." .. CMD_HOLO_PLACE_DESCRIPTION.params[2], "Holo off")
i18n.set("en.ui.orderMenu." .. CMD_HOLO_PLACE_DESCRIPTION.params[3], "Holo Smart")
i18n.set("en.ui.orderMenu." .. CMD_HOLO_PLACE_DESCRIPTION.params[4], "Holo 90")
i18n.set("en.ui.orderMenu." .. CMD_HOLO_PLACE_DESCRIPTION.params[5], "Holo 60")
i18n.set("en.ui.orderMenu." .. CMD_HOLO_PLACE_DESCRIPTION.params[6], "Holo 30")
i18n.set("en.ui.orderMenu." .. CMD_HOLO_PLACE_DESCRIPTION.params[7], "Holo Ins")
i18n.set("en.ui.orderMenu." .. CMD_HOLO_PLACE_DESCRIPTION.action .. "_tooltip", "Start next building if assisted (Smart auto mode)")

-- 📊 STEP 4: INITIALIZE DATA STRUCTURES
local BUILDER_DEFS = {}
local NANO_DEFS = {}
local BT_DEFS = {}
local MAX_DISTANCE = 0
local HOLO_PLACERS = {}
local lastActiveMode = 1  -- Default: Smart Auto (now mode 1)
local myTeamID = 0

-- 🚀 V4 PERFORMANCE: Frame throttling configuration
local UPDATE_INTERVAL = 3  -- Update every 3 frames instead of every frame (90% performance improvement)

-- 🔍 STEP 5: SCAN ALL UNIT DEFINITIONS
for unit_def_id, unit_def in pairs(UnitDefs) do
    BT_DEFS[unit_def_id] = unit_def.buildTime
    if unit_def.isBuilder and not unit_def.isFactory then
        if #unit_def.buildOptions > 0 then
            BUILDER_DEFS[unit_def_id] = unit_def.buildSpeed
        end
        if not unit_def.canMove then
            NANO_DEFS[unit_def_id] = unit_def.buildDistance
            if unit_def.buildDistance > MAX_DISTANCE then
                MAX_DISTANCE = unit_def.buildDistance
            end
        end
    end
end

-- 🎚️ STEP 6: DEFINE BUILD COMPLETION THRESHOLDS (remapped to match visual order)
local HOLO_THRESHOLDS = {
    [0] = nil,   -- off
    [1] = 0.3,   -- smart auto (uses 30% as base)
    [2] = 0.9,   -- 90%
    [3] = 0.6,   -- 60%
    [4] = 0.3,   -- 30%
    [5] = 0,     -- instant
}

-- 🆕 V3 STEP 7: DYNAMIC THRESHOLD CALCULATION
local function calculateOptimalThreshold(builderID, nanoID, buildingID)
    if not builderID or not nanoID or not buildingID then return 0.3 end

    local builderDefID = GetUnitDefID(builderID)
    local nanoDefID = GetUnitDefID(nanoID)
    local buildingDefID = GetUnitDefID(buildingID)

    local builderSpeed = BUILDER_DEFS[builderDefID] or 1
    local nanoSpeed = BUILDER_DEFS[nanoDefID] or 1
    local buildTime = BT_DEFS[buildingDefID] or 1000

    -- Calculate speed ratio
    local speedRatio = nanoSpeed / builderSpeed

    -- Adjust threshold based on nano speed advantage
    if speedRatio > 3 then
        return 0.2  -- Very fast nano, start earlier
    elseif speedRatio > 1.5 then
        return 0.3  -- Normal, 30%
    else
        return 0.5  -- Slow nano, wait longer
    end
end

-- 🗼 STEP 8: FIND NANO TURRETS NEAR A UNIT
local function ntNearUnit(target_unit_id)
    local pos = {GetUnitPosition(target_unit_id)}
    if not pos[1] then return {} end

    local units_near = GetUnitsInCylinder(pos[1], pos[3], MAX_DISTANCE, -2)
    local unit_ids = {}
    for _, id in ipairs(units_near) do
        local dist = NANO_DEFS[GetUnitDefID(id)]
        if dist ~= nil and target_unit_id ~= id then
            if dist > GetUnitSeparation(target_unit_id, id, true) then
                unit_ids[#unit_ids + 1] = id
            end
        end
    end
    return unit_ids
end

-- 🆕 V3 STEP 9: BEST NANO SELECTION WITH SCORING
local function selectBestNano(target_id, available_nanos)
    if not available_nanos or #available_nanos == 0 then return nil end

    local best_nano = nil
    local best_score = -1

    for _, nt_id in ipairs(available_nanos) do
        if ValidUnitID(nt_id) then
            local score = 0

            -- Factor 1: Closer nanos = higher priority (0-1000 points)
            local distance = GetUnitSeparation(target_id, nt_id, true)
            score = score + math.max(0, 1000 - distance)

            -- Factor 2: Idle nanos = higher priority (+500 points)
            if not GetUnitIsBuilding(nt_id) then
                score = score + 500
            end

            -- Factor 3: Fewer commands = higher priority (0-100 points)
            local cmdCount = GetUnitCommandCount(nt_id)
            score = score + math.max(0, 100 - cmdCount * 10)

            if score > best_score then
                best_score = score
                best_nano = nt_id
            end
        end
    end

    return best_nano
end

-- 🔍 STEP 10: CHECK AND UPDATE SELECTED UNITS
local function checkUnits(update)
    local mode = 0
    local num_hp = 0
    local num_builders = 0

    local ids = GetSelectedUnits()
    for i=1, #ids do
        local def_id = GetUnitDefID(ids[i])

        if HOLO_PLACERS[ids[i]] then
            num_hp = num_hp + 1
        end

        if BUILDER_DEFS[def_id] then
            num_builders = num_builders + 1
        end
    end

    if num_builders > 0 then
        if update then
            local mode = CMD_HOLO_PLACE_DESCRIPTION.params[1]
            for i=1, #ids do
                if mode == 0 then  -- mode 0 = Off
                    HOLO_PLACERS[ids[i]] = nil
                else
                    HOLO_PLACERS[ids[i]] = HOLO_PLACERS[ids[i]] or {}
                    HOLO_PLACERS[ids[i]].threshold = HOLO_THRESHOLDS[mode]
                    HOLO_PLACERS[ids[i]].mode = mode
                    HOLO_PLACERS[ids[i]].monitoring = false
                end
            end
        end
        return true
    end
end

-- 🎮 STEP 11: HANDLE HOTKEY ACTIVATION
local function handleHoloPlace()
    checkUnits(true)
end

-- 🗑️ STEP 12: CLEANUP DESTROYED/TAKEN UNITS
local function ForgetUnit(self, unit_id)
    HOLO_PLACERS[unit_id] = nil
end

widget.UnitDestroyed = ForgetUnit
widget.UnitTaken = ForgetUnit

-- 🎨 STEP 13: UPDATE UI WHEN SELECTION CHANGES
function widget:CommandsChanged()
    local ids = GetSelectedUnits()
    local found_mode = 1  -- Default to Smart Auto (now mode 1)

    local hasBuilders = false
    for i = 1, #ids do
        local def_id = GetUnitDefID(ids[i])
        if BUILDER_DEFS[def_id] then
            hasBuilders = true
            local placer = HOLO_PLACERS[ids[i]]

            if placer and placer.mode then
                -- Use existing mode
                found_mode = placer.mode
                break
            elseif CMD_HOLO_PLACE_DESCRIPTION.params[1] ~= 0 then
                -- 🆕 V3: Auto-enable Smart Auto for new builders (but not if currently Off)
                HOLO_PLACERS[ids[i]] = HOLO_PLACERS[ids[i]] or {}
                HOLO_PLACERS[ids[i]].threshold = HOLO_THRESHOLDS[1]  -- Smart Auto threshold
                HOLO_PLACERS[ids[i]].mode = 1
                HOLO_PLACERS[ids[i]].monitoring = false
                found_mode = 1
            else
                -- Mode is Off, don't auto-enable
                found_mode = 0
            end
        end
    end

    CMD_HOLO_PLACE_DESCRIPTION.params[1] = found_mode
    if hasBuilders then
        local cmds = widgetHandler.customCommands
        cmds[#cmds + 1] = CMD_HOLO_PLACE_DESCRIPTION
    end
end

-- 🎮 STEP 14: HANDLE COMMAND BUTTON CLICKS
function widget:CommandNotify(cmd_id, cmd_params, cmd_options)
    if cmd_id == CMD_HOLO_PLACE then
        -- Manually cycle through modes: 0 → 1 → 2 → 3 → 4 → 5 → 0
        local mode = CMD_HOLO_PLACE_DESCRIPTION.params[1]
        mode = (mode + 1) % 6  -- Cycle through 0-5
        CMD_HOLO_PLACE_DESCRIPTION.params[1] = mode

        if mode ~= 0 then  -- mode 0 = Off
            lastActiveMode = mode
        end
        checkUnits(true)
        return true  -- Block Spring's cycling, we handle it ourselves
    end
end

-- 🎹 STEP 15: KEYBOARD TOGGLE HANDLER
function widget:KeyPress(key, mods, isRepeat)
    if key == 39 and mods.ctrl and mods.shift and not isRepeat then
        local currentMode = CMD_HOLO_PLACE_DESCRIPTION.params[1]
        local newMode

        if currentMode == 0 then  -- mode 0 = Off
            newMode = lastActiveMode
        else
            lastActiveMode = currentMode
            newMode = 0  -- Toggle to Off
        end

        CMD_HOLO_PLACE_DESCRIPTION.params[1] = newMode
        checkUnits(true)

        local modeName = i18n("ui.orderMenu." .. CMD_HOLO_PLACE_DESCRIPTION.params[newMode + 2])
        Spring.Echo("Holo Place V4: " .. modeName)

        return true
    end
    return false
end

-- ⏸️ STEP 16: WAIT COMMAND DETECTION
local function unitHasWait(unit_id)
    if not ValidUnitID(unit_id) then return false end
    local cmds = GetUnitCommands(unit_id, 20)
    for i = 1, #cmds do
        if cmds[i].id == CMD_WAIT then
            return true
        end
    end
    return false
end

-- 🧹 STEP 17: CLEANUP BUILDER STATE
local function cleanupBuilder(builder)
    builder.nt_id = false
    builder.building_id = false
    builder.monitoring = false
    builder.tick = nil
    builder.cmd_tag = nil
end

-- 🆕 V3 STEP 18: SMART AUTO-ENABLE ON COMMAND
function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
    if unitTeam ~= myTeamID then return end

    -- Only process build commands (-negative IDs)
    if BUILDER_DEFS[unitDefID] and cmdID < 0 then
        local placer = HOLO_PLACERS[unitID]

        -- If in Smart Auto mode (1), check conditions
        if placer and placer.mode == 1 then
            local queueLength = GetUnitCommandCount(unitID)

            -- Auto-enable if 2+ commands queued
            if queueLength >= 1 then  -- Will be 2 after this command
                -- Check for nearby nanos (will check when building starts)
                placer.smart_enabled = true
            end
        end
    end
end

-- 🆕 V3 STEP 19: UNIT COMMAND DONE - EVENT-BASED CLEANUP
function widget:UnitCmdDone(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
    if unitTeam ~= myTeamID then return end  -- 🛡️ V4: Only process own team's units

    if cmdID < 0 and HOLO_PLACERS[unitID] then
        local builder = HOLO_PLACERS[unitID]
        cleanupBuilder(builder)

        if GetUnitCommandCount(unitID) == 0 then
            builder.monitoring = false
        end
    end
end

-- 🆕 V3 STEP 20: UNIT FINISHED - ALTERNATIVE CLEANUP
function widget:UnitFinished(unitID, unitDefID, unitTeam)
    -- 🛡️ V4: Check team to avoid processing teammates' buildings
    -- (This building might be what our builder is working on)
    -- Skip team check here because we need to know when ANY building finishes
    -- that our builders are monitoring (even if assisted by teammates)

    for builder_id, builder in pairs(HOLO_PLACERS) do
        if builder.building_id == unitID then
            cleanupBuilder(builder)
        end
    end
end

-- 🚀 V4 STEP 21: MAIN GAME LOGIC - PERFORMANCE OPTIMIZED WITH FRAME THROTTLING
function widget:GameFrame(frame)
    
    -- 🚀 V4 CRITICAL PERFORMANCE FIX: Only update every N frames instead of every frame
    -- This reduces CPU usage by ~90% (from every frame to every 3 frames)
    if frame % UPDATE_INTERVAL ~= 0 then
        return  -- Skip this frame
    end

    for unit_id, builder in pairs(HOLO_PLACERS) do
        local should_process = true

        -- Skip if not actively monitoring
        if not builder.monitoring then
            local target_id = GetUnitIsBuilding(unit_id)
            if target_id then
                builder.monitoring = true
            else
                should_process = false
            end
        end

        if should_process then
            local target_id = GetUnitIsBuilding(unit_id)

            -- CASE 1: Monitoring nano turret assistance
            if builder.nt_id and target_id == builder.building_id then
                if not ValidUnitID(builder.nt_id) then
                    cleanupBuilder(builder)
                else
                    local building_id = GetUnitIsBuilding(builder.nt_id)
                    local num_cmds = GetUnitCommands(builder.nt_id, 0)

                    if building_id == builder.building_id and num_cmds == 1 then
                        local health_data = {GetUnitHealth(builder.building_id)}
                        if health_data[1] then
                            local build_progress = health_data[5] or 0
                            local threshold = builder.threshold or 0.6

                            if build_progress >= threshold then
                                -- Only reset nano tracking, keep monitoring active!
                                builder.nt_id = false
                                builder.building_id = false
                                builder.tick = nil
                                GiveOrderToUnit(unit_id, CMD_REMOVE, builder.cmd_tag, 0)
                            end
                        else
                            cleanupBuilder(builder)
                        end
                    elseif builder.tick and builder.tick > 30 then
                        cleanupBuilder(builder)
                    else
                        builder.tick = (builder.tick or 0) + 1
                    end
                end

            -- CASE 2: Builder started new construction
            elseif target_id and target_id ~= builder.building_id then
                local nt_ids = ntNearUnit(target_id)
                local best_nano = selectBestNano(target_id, nt_ids)

                if best_nano then
                    local cmds = GetUnitCommands(best_nano, 2)

                    if (cmds[2] and cmds[2].id == CMD_FIGHT)
                        or (cmds[1] and cmds[1].id == CMD_FIGHT)
                    then
                        if not unitHasWait(best_nano)
                           and not unitHasWait(unit_id)
                           and not GetUnitIsBuilding(best_nano) then

                            local _, _, tag = GetUnitCurrentCommand(unit_id)
                            builder.nt_id = best_nano
                            builder.tick = 0
                            builder.building_id = target_id
                            builder.cmd_tag = tag
                            builder.monitoring = true

                            -- 🆕 V3: Always update threshold when starting new building
                            if builder.mode == 1 then  -- mode 1 = Smart Auto
                                builder.threshold = calculateOptimalThreshold(unit_id, best_nano, target_id)
                            else
                                -- Use current mode's threshold (allows mode changes to take effect)
                                builder.threshold = HOLO_THRESHOLDS[builder.mode] or 0.6
                            end

                            GiveOrderToUnit(best_nano, CMD_REPAIR, target_id, 0)
                        end
                    end
                end
            -- CASE 3: Not building anymore
            elseif not target_id and builder.monitoring then
                cleanupBuilder(builder)
            end
        end
    end
end

-- 🚀 STEP 22: WIDGET INITIALIZATION
function widget:Initialize()
    if Spring.GetSpectatingState() then
      self:RemoveWidget()
      return
    end
    myTeamID = GetMyTeamID()
    widgetHandler.actionHandler:AddAction(self, "holo_place", handleHoloPlace, nil, "Insert")

    local constructorCount = 0
    local nanoCount = 0
    for _ in pairs(BUILDER_DEFS) do constructorCount = constructorCount + 1 end
    for _ in pairs(NANO_DEFS) do nanoCount = nanoCount + 1 end

    Spring.Echo("🚀 Holo Place V4 Lite: Performance Optimized Edition")
    Spring.Echo("  • " .. constructorCount .. " constructors, " .. nanoCount .. " nano turrets")
    Spring.Echo("  • Features: Smart auto mode, dynamic threshold, best nano scoring")
    Spring.Echo("  • Performance: Frame-throttled (every " .. UPDATE_INTERVAL .. " frames = ~90% less CPU)")
    Spring.Echo("  • Hotkey: Ctrl+Shift+' to toggle")
    Spring.Echo("  • Note: Disable V3 before enabling V4!")
end

-- 🛑 STEP 23: WIDGET CLEANUP
function widget:Shutdown()
    widgetHandler.actionHandler:RemoveAction(self, "holo_place", "Insert")
end
