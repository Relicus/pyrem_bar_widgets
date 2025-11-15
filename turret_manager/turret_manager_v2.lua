--[[
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TURRET MANAGER V2 - 3-Mode Nano Turret Automation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

MODES:
• ECO (Default): Balance converter/energy ratio with hysteresis
• REPAIR: Prioritize damaged allied units
• RECLAIM: Prioritize features/wreckage

UI: Custom command buttons to switch modes

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--]]

function widget:GetInfo()
	return {
		name = "Turret Manager V2 - Pyrem",
		desc = "3-mode nano turret automation (ECO/REPAIR/RECLAIM)",
		author = "Pyrem",
		date = "2025",
		version = "2.2",
		layer = 10,
		enabled = true,
		handler = true,
	}
end

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CMD_REPAIR = CMD.REPAIR or 40
local CMD_RECLAIM = CMD.RECLAIM or 90
local CMD_STOP = CMD.STOP or 0
local CMD_WAIT = CMD.WAIT
local CMD_GUARD = CMD.GUARD or 25
local CMD_INSERT = CMD.INSERT or 150

local CMD_ECO_MODE = 28370
local CMD_REPAIR_MODE = 28371
local CMD_RECLAIM_MODE = 28372

local CMDTYPE = CMDTYPE or {}
CMDTYPE.ICON_MODE = 5

local CMD_MODE_DESC = {
	id = CMD_ECO_MODE,
	type = CMDTYPE.ICON_MODE,
	name = "Turret Mode",
	action = "turretmode",
	tooltip = "ECO: Converter priority | REPAIR: Fix damage | RECLAIM: Clean wreckage",
	params = {0, "ECO", "REPAIR", "RECLAIM"},
	texture = "LuaUI/Images/commands/Bold/dgun.png"
}

local RESOURCE_IMBALANCE_RATIO = 3
local PRIORITY_CRITICAL_BUILDER = -500000
local PRIORITY_HIGHEST = 0
local PRIORITY_MEDIUM = 50000
local PRIORITY_LOW = 100000
local PRIORITY_LOWEST = 1000000
local PRIORITY_SWITCH_THRESHOLD = 100
local HP_SWITCH_THRESHOLD = 30
local PRIORITY_CONSTRUCTION_PENALTY = 100000
local METAL_VALUE_MULTIPLIER = 2
local PRIORITY_COST_DIVISOR = 10
-- Reduced from 1.20 to 1.05: Allows switching to converters/metal with just 5% energy surplus
-- Previous 20% surplus requirement was too high, causing widget to stay stuck building energy
local RATIO_THRESHOLD_BASE = 1.05
local RATIO_THRESHOLD_BUFFER = 0.10
local RATIO_PRIORITY_BOOST = -250000
local RATIO_MIN_EPULL = 1.0
local MAX_TRACKED_TURRETS = 400

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local myTeamID
local lastRatioPriorityState = nil

local turretDefIDs = {}
local watchedTurrets = {}
local unitDefCache = {}
local categoryCache = {}
local unitMetadataCache = {}
local turretStates = {}
local widgetIssuedCommands = {}
local userOverriddenTurrets = {}

local resourceCache = {
	frame = -1,
	mCurrent = 0, mStorage = 0, mPull = 0, mIncome = 0,
	eCurrent = 0, eStorage = 0, ePull = 0, eIncome = 0,
	converterCapacity = 0,
	converterUsePerc = 0
}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function distance3D(x1, y1, z1, x2, y2, z2)
	local dx = x1 - x2
	local dy = (y1 or 0) - (y2 or 0)
	local dz = z1 - z2
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function getTurretMode(turretID)
	return (turretStates[turretID] and turretStates[turretID].mode) or "ECO"
end

local function setTurretMode(turretID, newMode)
	if not turretStates[turretID] then
		turretStates[turretID] = {}
	end
	turretStates[turretID].mode = newMode
end

local function updateResourceCache(frame)
	if resourceCache.frame ~= frame then
		resourceCache.mCurrent, resourceCache.mStorage, resourceCache.mPull, resourceCache.mIncome = Spring.GetTeamResources(myTeamID, "metal")
		resourceCache.eCurrent, resourceCache.eStorage, resourceCache.ePull, resourceCache.eIncome = Spring.GetTeamResources(myTeamID, "energy")
		resourceCache.converterCapacity = Spring.GetTeamRulesParam(myTeamID, "mmCapacity") or 0
		resourceCache.converterUse = Spring.GetTeamRulesParam(myTeamID, "mmUse") or 0
		resourceCache.frame = frame
	end
end

local function getUnitCategory(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	local name = unitDef.name or ""
	local translatedHumanName = unitDef.translatedHumanName or ""
	if not unitDef then return "other" end
	if unitDef.extractsMetal > 0 then
		return "mex"
	end
	if unitDef.energyMake > 0 then
		return "energy"
	end
	local energyConvCapacity = unitDef.customParams.energyconv_capacity
	if (energyConvCapacity and tonumber(energyConvCapacity) > 0) or string.find(name, "mmkr") or string.find(name, "metalmaker") then
		return "converter"
	end
	if (unitDef.energyStorage > 0) or
	   (unitDef.metalStorage > 0) then
		return "storage"
	end
	if  ((unitDef.isBuilder and unitDef.showNanoSpray) or string.find(string.lower(translatedHumanName), "turret") 
		 or string.find(name, "nano") or (unitDef.isBuilder and unitDef.isStaticBuilder and
		 unitDef.buildDistance and unitDef.buildDistance > 0)) and not unitDef.canMove then
		return "builder"
	end
	if unitDef.weapons and #unitDef.weapons > 0 and not unitDef.canMove then
		return "defense"
	end
	return "other"
end

local function getCachedCategory(unitDefID)
	if not categoryCache[unitDefID] then
		categoryCache[unitDefID] = getUnitCategory(unitDefID)
	end
	return categoryCache[unitDefID]
end

local function getCachedDefID(unitID)
	if not unitDefCache[unitID] then
		unitDefCache[unitID] = Spring.GetUnitDefID(unitID)
	end
	return unitDefCache[unitID]
end

local function updateUnitCache(unitID)
	if not unitID then return end
	local defID = getCachedDefID(unitID)
	if not defID then return end
	local health, maxHealth, paralyzeDamage, captureProgress, buildProgress = Spring.GetUnitHealth(unitID)
	if not health then return end
	local x, y, z = Spring.GetUnitPosition(unitID)
	if not x then return end
	local category = getCachedCategory(defID)
	local unitDef = UnitDefs[defID]
	local metalCost = unitDef and unitDef.metalCost or 0
	local energyCost = unitDef and unitDef.energyCost or 0
	local remainingCost = 0
	if buildProgress < 1 then
		local remainingMetal = metalCost * (1 - buildProgress)
		local remainingEnergy = energyCost * (1 - buildProgress)
		remainingCost = remainingMetal * 2 + remainingEnergy
	else
		local healthFraction = health / maxHealth
		local repairMetal = metalCost * (1 - healthFraction)
		local repairEnergy = energyCost * (1 - healthFraction)
		remainingCost = repairMetal * 2 + repairEnergy
	end
	unitMetadataCache[unitID] = {
		defID = defID,
		category = category,
		health = health,
		maxHealth = maxHealth,
		buildProgress = buildProgress,
		metalCost = metalCost,
		energyCost = energyCost,
		remainingCost = remainingCost,
		position = {x = x, y = y, z = z},
		lastUpdated = Spring.GetGameFrame()
	}
end

local function cleanupUnitCache()
	local currentFrame = Spring.GetGameFrame()
	local MAX_CACHE_AGE = 600
	for unitID, cached in pairs(unitMetadataCache) do
		if not Spring.ValidUnitID(unitID) then
			unitMetadataCache[unitID] = nil
		elseif currentFrame - cached.lastUpdated > MAX_CACHE_AGE then
			unitMetadataCache[unitID] = nil
		end
	end
end

local function countWatchedTurrets()
	local count = 0
	for _ in pairs(watchedTurrets) do
		count = count + 1
	end
	return count
end

local function addWatchedTurret(unitID, unitDefID)
	if not turretDefIDs[unitDefID] then return end
	local count = countWatchedTurrets()
	if count < MAX_TRACKED_TURRETS then
		local turretData = turretDefIDs[unitDefID]
		watchedTurrets[unitID] = {
			defID = unitDefID,
			buildDistance = turretData and turretData.buildDistance or 128
		}
		setTurretMode(unitID, "ECO")
	end
end

local function removeWatchedTurret(unitID)
	watchedTurrets[unitID] = nil
	turretStates[unitID] = nil
	unitMetadataCache[unitID] = nil
	widgetIssuedCommands[unitID] = nil
	userOverriddenTurrets[unitID] = nil
end

--------------------------------------------------------------------------------
-- ECO MODE
--------------------------------------------------------------------------------

local function calculateEcoPriority(unitID, unitDefID, turretX, turretZ)
	local cached = unitMetadataCache[unitID]
	if not cached then return PRIORITY_LOWEST end
	local category = cached.category
	local remainingCost = cached.remainingCost
	local costMod = (remainingCost / PRIORITY_COST_DIVISOR)
	
	if category == "builder" then
		return PRIORITY_CRITICAL_BUILDER + costMod
	end
	
	if lastRatioPriorityState == "ENERGY" then
		if category == "energy" then
			return RATIO_PRIORITY_BOOST + costMod
		elseif category == "mex" or category == "converter" then
			return PRIORITY_LOW + costMod
		else
			return PRIORITY_MEDIUM + costMod
		end
	elseif lastRatioPriorityState == "METAL" then
		if category == "mex" or category == "converter" then
			return RATIO_PRIORITY_BOOST + costMod
		elseif category == "energy" then
			return PRIORITY_LOW + costMod
		else
			return PRIORITY_MEDIUM + costMod
		end
	else
		if category == "energy" or category == "mex" or category == "converter" then
			return PRIORITY_HIGHEST + costMod
		else
			return PRIORITY_MEDIUM + costMod
		end
	end
end

local function isCurrentTargetImbalanced(unitID, unitDefID)
	local unitDef = UnitDefs[unitDefID]
	if not unitDef then return false end
	local cached = unitMetadataCache[unitID]
	if not cached then return false end
	local buildProgress = cached.buildProgress
	if not buildProgress or buildProgress >= 1.0 then return false end
	if not resourceCache.mIncome or not resourceCache.mPull or not resourceCache.eIncome or not resourceCache.ePull then return false end
	local mRatio = resourceCache.mPull > 0 and (resourceCache.mIncome / resourceCache.mPull) or 1
	local eRatio = resourceCache.ePull > 0 and (resourceCache.eIncome / resourceCache.ePull) or 1
	local totalMetal = unitDef.metalCost or 0
	local totalEnergy = unitDef.energyCost or 0
	local remainingMetal = totalMetal * (1 - buildProgress)
	local remainingEnergy = totalEnergy * (1 - buildProgress)
	if remainingEnergy > remainingMetal * RESOURCE_IMBALANCE_RATIO and eRatio < 0.3 then
		return true
	end
	if remainingMetal > remainingEnergy * RESOURCE_IMBALANCE_RATIO and mRatio < 0.3 then
		return true
	end
	return false
end

local function shouldSwitchRepairTarget(currentTargetID, bestCandidateID)
	if not currentTargetID or not bestCandidateID then return true end
	if not Spring.ValidUnitID(currentTargetID) then return true end
	if currentTargetID == bestCandidateID then return false end
	local currentCached = unitMetadataCache[currentTargetID]
	local bestCached = unitMetadataCache[bestCandidateID]
	if not currentCached or not bestCached then
		return true
	end
	local currentHealth = currentCached.health
	local currentMaxHealth = currentCached.maxHealth
	local bestHealth = bestCached.health
	local bestMaxHealth = bestCached.maxHealth
	if not currentHealth or not currentMaxHealth or not bestHealth or not bestMaxHealth then
		return true
	end
	if currentHealth >= currentMaxHealth then return true end
	local currentHPPercent = (currentHealth / currentMaxHealth) * 100
	local bestHPPercent = (bestHealth / bestMaxHealth) * 100
	local hpDifference = math.abs(currentHPPercent - bestHPPercent)
	if hpDifference > HP_SWITCH_THRESHOLD then
		if bestHPPercent < currentHPPercent then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- COLLECTION & CLASSIFICATION
--------------------------------------------------------------------------------

local function collectUnitCandidates(turretX, turretY, turretZ, range, teamID, mode)
	local units = Spring.GetUnitsInCylinder(turretX, turretZ, range)
	if not units then return {} end

	local candidates = {}
	for _, unitID in ipairs(units) do
		if Spring.ValidUnitID(unitID) then
			if not unitMetadataCache[unitID] then
				if Spring.GetUnitTeam(unitID) == teamID then
					updateUnitCache(unitID)
				end
			end

			local cached = unitMetadataCache[unitID]
			if cached then
				local ux, uy, uz = Spring.GetUnitPosition(unitID)
				if ux then 
					local distance = distance3D(ux, uy, uz, turretX, turretY, turretZ)
					if distance <= range then
						if mode == "ECO" then
							if cached.buildProgress < 1 then
								table.insert(candidates, {id = unitID, type = "unit", distance = distance})
							end
						elseif mode == "REPAIR" then
							if cached.health < cached.maxHealth and cached.health > 0 then
								table.insert(candidates, {id = unitID, type = "unit", distance = distance})
							end
						end
					end
				end
			end
		end
	end
	return candidates
end

local function collectFeatureCandidates(turretX, turretY, turretZ, range)
	local x1, z1 = turretX - range, turretZ - range
	local x2, z2 = turretX + range, turretZ + range
	local features = Spring.GetFeaturesInRectangle(x1, z1, x2, z2)
	if not features then return {} end
	local candidates = {}
	for _, featureID in ipairs(features) do
		if Spring.ValidFeatureID(featureID) then
			local fx, fy, fz = Spring.GetFeaturePosition(featureID)
			if fx then
				local distance = distance3D(fx, fy, fz, turretX, turretY, turretZ)
				if distance <= range then
					local metalValue = Spring.GetFeatureResources(featureID)
					if metalValue and metalValue > 0 then
						table.insert(candidates, {id = featureID, type = "feature", distance = distance})
					end
				end
			end
		end
	end
	return candidates
end

local function classifyTargets(candidates, mode, turretX, turretZ)
	local classified = {}
	for _, candidate in ipairs(candidates) do
		local enriched = {
			id = candidate.id,
			type = candidate.type,
			distance = candidate.distance,
			priority = 0,
			isFeature = (candidate.type == "feature")
		}
		if mode == "ECO" then
			local cached = unitMetadataCache[candidate.id]
			if cached then
				local defID = cached.defID
				local priority = calculateEcoPriority(candidate.id, defID, turretX, turretZ)
				enriched.priority = priority
				enriched.unitID = candidate.id
				enriched.unitDefID = defID
			end
		elseif mode == "REPAIR" then
			local cached = unitMetadataCache[candidate.id]
			if cached then
				local health = cached.health
				local maxHealth = cached.maxHealth
				local buildProgress = cached.buildProgress
				local damageAmount = maxHealth - health
				local isBuilt = (buildProgress and buildProgress >= 1.0) or (not buildProgress)
				local priority = isBuilt and damageAmount or (damageAmount - PRIORITY_CONSTRUCTION_PENALTY)
				enriched.priority = -priority
				enriched.unitID = candidate.id
				enriched.damageAmount = damageAmount
			end
		elseif mode == "RECLAIM" then
			local metalValue, _, energyValue, _, reclaimLeft, reclaimTime = Spring.GetFeatureResources(candidate.id)
			if metalValue then
				energyValue = energyValue or 0
				local reclaimValue = (metalValue * METAL_VALUE_MULTIPLIER) + energyValue
				enriched.priority = reclaimLeft * reclaimTime
				enriched.featureID = candidate.id
				enriched.reclaimValue = reclaimValue
				enriched.metal = metalValue
				enriched.energy = energyValue
			end
		end
		table.insert(classified, enriched)
	end
	return classified
end

--------------------------------------------------------------------------------
-- RATIO & MODE HANDLERS
--------------------------------------------------------------------------------

-- Calculate energy ratio using converter capacity formula
-- MATCHES: gui_converter_energy_display_v2.lua:362-374
-- Formula: eIncome / (mmCapacity / 0.85)
-- - mmCapacity = max theoretical converter capacity (E/sec)
-- - 0.85 = 85% efficiency factor (converters are 85% efficient)
-- - eIncome = current energy production
-- This measures "can I support my converters at 85% efficiency"
-- It ignores temporary construction/weapon drains, focusing on base economy structure
local function calculateEnergyRatio()
	local eIncome = resourceCache.eIncome
	local mmCapacity = resourceCache.converterCapacity

	-- Fallback to safe ratio if no converters or no energy
	if not mmCapacity or mmCapacity <= 0 or not eIncome or eIncome <= 0 then
		return 2.0  -- Safe default (high ratio = build metal/other)
	end

	-- Use converter capacity formula (consistent with converter display widget)
	return eIncome / (mmCapacity / 0.85)
end

local function determineRatioPriority(currentRatio)
	local switchToMetal = RATIO_THRESHOLD_BASE + RATIO_THRESHOLD_BUFFER
	local switchToEnergy = RATIO_THRESHOLD_BASE - RATIO_THRESHOLD_BUFFER
	if lastRatioPriorityState == nil then
		if currentRatio > RATIO_THRESHOLD_BASE then
			lastRatioPriorityState = "METAL"
		else
			lastRatioPriorityState = "ENERGY"
		end
		return lastRatioPriorityState
	end
	if lastRatioPriorityState == "METAL" then
		if currentRatio < switchToEnergy then
			lastRatioPriorityState = "ENERGY"
		end
	else
		if currentRatio > switchToMetal then
			lastRatioPriorityState = "METAL"
		end
	end
	return lastRatioPriorityState
end

local function processEcoMode(turretID, tx, ty, tz, buildRange, commands, turretState)
	local rawCandidates = collectUnitCandidates(tx, ty, tz, buildRange, myTeamID, "ECO")
	local candidates = classifyTargets(rawCandidates, "ECO", tx, tz)
	table.sort(candidates, function(a, b)
		if math.abs(a.priority - b.priority) < 0.1 then return a.distance < b.distance end
		return a.priority < b.priority
	end)
	if #candidates == 0 then
		return nil, false
	end
	local best = candidates[1]
	local currentCmd = commands and commands[1]
	local currentTarget = currentCmd and currentCmd.params and currentCmd.params[1]
	local shouldSwitch = true
	if currentCmd and currentTarget and currentCmd.id == CMD_REPAIR then
		if Spring.ValidUnitID(currentTarget) then
			local cached = unitMetadataCache[currentTarget]
			if not cached then
				shouldSwitch = true
			else
				local ux, uy, uz = cached.position.x, cached.position.y, cached.position.z
				local dist = distance3D(tx, ty, tz, ux, uy, uz)
				if dist > buildRange then
					shouldSwitch = true
				else
					if cached.buildProgress and cached.buildProgress >= 0.95 then
						shouldSwitch = false
					else
						local targetDefID = getCachedDefID(currentTarget)
						if targetDefID and isCurrentTargetImbalanced(currentTarget, targetDefID) then
							shouldSwitch = true
						else
							local currentPriority = calculateEcoPriority(currentTarget, targetDefID, tx, tz)
							local priorityDiff = currentPriority - best.priority
							if priorityDiff > PRIORITY_SWITCH_THRESHOLD then
								shouldSwitch = true
							else
								shouldSwitch = false
							end
						end
					end
				end
			end
		end
	end
	return best, shouldSwitch
end

local function processRepairMode(tx, ty, tz, buildRange, commands, turretState)
	local rawCandidates = collectUnitCandidates(tx, ty, tz, buildRange, myTeamID, "REPAIR")
	local candidates = classifyTargets(rawCandidates, "REPAIR", tx, tz)
	table.sort(candidates, function(a, b)
		if math.abs(a.priority - b.priority) < 0.1 then return a.distance < b.distance end
		return a.priority < b.priority
	end)
	if #candidates == 0 then return nil, false end
	local best = candidates[1]
	local currentCmd = commands and commands[1]
	local currentTarget = currentCmd and currentCmd.params and currentCmd.params[1]
	local shouldSwitch = true
	if currentCmd and currentTarget and currentCmd.id == CMD_REPAIR then
		if Spring.ValidUnitID(currentTarget) then
			local cached = unitMetadataCache[currentTarget]
			if not cached then
				shouldSwitch = true
			else
				local ux, uy, uz = cached.position.x, cached.position.y, cached.position.z
				if ux and uz then
					local dist = distance3D(tx, ty, tz, ux, uy, uz)
					if dist <= buildRange then
						shouldSwitch = shouldSwitchRepairTarget(currentTarget, best.unitID)
					end
				end
			end
		end
	end
	return best, shouldSwitch
end

local function processReclaimMode(tx, ty, tz, buildRange, commands, turretState)
	local rawCandidates = collectFeatureCandidates(tx, ty, tz, buildRange)
	local candidates = classifyTargets(rawCandidates, "RECLAIM", tx, tz)
	table.sort(candidates, function(a, b)
		if math.abs(a.priority - b.priority) < 0.1 then return a.distance < b.distance end
		return a.priority < b.priority
	end)
	if #candidates == 0 then return nil, false end
	local best = candidates[1]
	local currentCmd = commands and commands[1]
	local currentTarget = currentCmd and currentCmd.params and currentCmd.params[1]
	local shouldSwitch = true
	if currentCmd and currentTarget and currentCmd.id == CMD_RECLAIM then
		if currentTarget and Spring.GetFeatureDefID(currentTarget) then
			local fx, fy, fz = Spring.GetFeaturePosition(currentTarget)
			if fx and fz then
				local dist = distance3D(tx, ty, tz, fx, fy, fz)
				if dist <= buildRange then
					shouldSwitch = false
				end
			end
		end
	end
	return best, shouldSwitch
end

--------------------------------------------------------------------------------
-- MAIN LOGIC
--------------------------------------------------------------------------------

local function refreshWatchedTurrets()
	local allUnits = Spring.GetTeamUnits(myTeamID)
	for turretID in pairs(watchedTurrets) do
		if not Spring.ValidUnitID(turretID) then
			watchedTurrets[turretID] = nil
			turretStates[turretID] = nil
		end
	end
	local currentCount = countWatchedTurrets()
	if currentCount < MAX_TRACKED_TURRETS then
		for _, unitID in ipairs(allUnits) do
			if not watchedTurrets[unitID] then
				local unitDefID = Spring.GetUnitDefID(unitID)
				if unitDefID and turretDefIDs[unitDefID] then
					local _, _, _, _, buildProgress = Spring.GetUnitHealth(unitID)
					if buildProgress and buildProgress >= 1.0 then
						local turretData = turretDefIDs[unitDefID]
						watchedTurrets[unitID] = {
							defID = unitDefID,
							buildDistance = turretData and turretData.buildDistance or 128
						}
						setTurretMode(unitID, "ECO")
						currentCount = currentCount + 1
						if currentCount >= MAX_TRACKED_TURRETS then
							break
						end
					end
				end
			end
		end
	end
end

local function processNanoTurretTargets()
	local currentFrame = Spring.GetGameFrame()
	updateResourceCache(currentFrame)
	local energyRatio = calculateEnergyRatio()
	local ratioPriority = determineRatioPriority(energyRatio)
	
	for turretID, turretData in pairs(watchedTurrets) do
		if Spring.ValidUnitID(turretID) then
			local turretDefID = turretData.defID
			if turretDefID then
				local tx, ty, tz = Spring.GetUnitPosition(turretID)
				if tx then
					local buildRange = turretData.buildDistance
					local commands = Spring.GetUnitCommands(turretID, 1)
					local shouldSkip = false
					if userOverriddenTurrets[turretID] then
						if not commands or #commands == 0 then
							userOverriddenTurrets[turretID] = nil
							widgetIssuedCommands[turretID] = nil
						else
							shouldSkip = true
						end
					end
					if commands and commands[1] and commands[1].id == CMD_GUARD then
						local guardTarget = commands[1].params and commands[1].params[1]
						if guardTarget and Spring.ValidUnitID(guardTarget) then
							local guardCommands = Spring.GetUnitCommands(guardTarget, 1)
							if guardCommands and #guardCommands > 0 then
								shouldSkip = true
							end
						end
					end
					if WG.ForceReclaim and WG.ForceReclaim.isManaged then
						local isForceReclaim, targetID = WG.ForceReclaim.isManaged(turretID)
						if isForceReclaim then
							shouldSkip = true
						end
					end
					if not shouldSkip then
						local state = turretStates[turretID]
						local best, shouldSwitch
						local turretMode = getTurretMode(turretID)
						if turretMode == "ECO" then
							best, shouldSwitch = processEcoMode(turretID, tx, ty, tz, buildRange, commands, state)
						elseif turretMode == "REPAIR" then
							best, shouldSwitch = processRepairMode(tx, ty, tz, buildRange, commands, state)
						elseif turretMode == "RECLAIM" then
							best, shouldSwitch = processReclaimMode(tx, ty, tz, buildRange, commands, state)
						end
						if best and shouldSwitch then
							local currentCmd = commands and commands[1]
							local currentTarget = currentCmd and currentCmd.params and currentCmd.params[1]
							local targetID = best.unitID or best.featureID
							local cmdID = best.isFeature and CMD_RECLAIM or CMD_REPAIR
							if currentTarget ~= targetID or (currentCmd and currentCmd.id ~= cmdID) then
								local targetX, targetY, targetZ
								if best.isFeature then
									targetX, targetY, targetZ = Spring.GetFeaturePosition(targetID)
								else
									targetX, targetY, targetZ = Spring.GetUnitPosition(targetID)
								end
								if targetX then
									local finalDist = distance3D(tx, ty, tz, targetX, targetY, targetZ)
									if finalDist <= buildRange then
										local fullQueue = Spring.GetUnitCommands(turretID, -1)
										if fullQueue and #fullQueue >= 3 then
											for i = 1, #fullQueue - 2 do
												Spring.GiveOrderToUnit(turretID, CMD.REMOVE, {fullQueue[i].tag}, {})
											end
										end
										if not commands or #commands == 0 then
											Spring.GiveOrderToUnit(turretID, cmdID, {targetID}, {})
										else
											Spring.GiveOrderToUnit(turretID, CMD_INSERT, {0, cmdID, 0, targetID}, {"alt"})
										end
										widgetIssuedCommands[turretID] = {
											cmdID = cmdID,
											targetID = targetID,
											frame = Spring.GetGameFrame()
										}
										local existingMode = turretStates[turretID] and turretStates[turretID].mode or "ECO"
										turretStates[turretID] = {
											mode = existingMode,
											lastTarget = targetID,
											lastCommand = cmdID,
											lastEcoState = (turretMode == "ECO") and lastRatioPriorityState or nil
										}
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- WIDGET EVENTS
--------------------------------------------------------------------------------

function widget:Initialize()
	if Spring.GetSpectatingState() then
		self:RemoveWidget()
		return
	end
	myTeamID = Spring.GetMyTeamID()
	for unitDefID, unitDef in pairs(UnitDefs) do
		if unitDef.isBuilder and
		   not unitDef.isFactory and
		   not unitDef.canMove then
			turretDefIDs[unitDefID] = {
				category = getUnitCategory(unitDefID),
				buildDistance = unitDef.buildDistance,
				name = unitDef.name
			}
		end
	end
	local allUnits = Spring.GetTeamUnits(myTeamID)
	local trackedCount = 0
	for _, unitID in ipairs(allUnits) do
		local unitDefID = Spring.GetUnitDefID(unitID)
		if unitDefID then
			local matches = turretDefIDs[unitDefID] ~= nil
			if matches then
				trackedCount = trackedCount + 1
				if trackedCount <= MAX_TRACKED_TURRETS then
					local turretData = turretDefIDs[unitDefID]
					watchedTurrets[unitID] = {
						defID = unitDefID,
						buildDistance = turretData and turretData.buildDistance or 128
					}
					setTurretMode(unitID, "ECO")
				end
			end
		end
	end

	widgetHandler.actionHandler:AddAction(
		self,
		"turretmode",
		function()
			local selectedUnits = Spring.GetSelectedUnits()
			if not selectedUnits or #selectedUnits == 0 then return end
			local selectedTurrets = {}
			for _, unitID in ipairs(selectedUnits) do
				if watchedTurrets[unitID] then
					table.insert(selectedTurrets, unitID)
				end
			end
			if #selectedTurrets == 0 then return end
			local currentTurretMode = getTurretMode(selectedTurrets[1])
			local newMode
			if currentTurretMode == "ECO" then
				newMode = "REPAIR"
			elseif currentTurretMode == "REPAIR" then
				newMode = "RECLAIM"
			else
				newMode = "ECO"
			end
			for _, turretID in ipairs(selectedTurrets) do
				setTurretMode(turretID, newMode)
			end
		end,
		nil,
		nil
	)
end

function widget:Shutdown()
	watchedTurrets = {}
	widgetHandler.actionHandler:RemoveAction(self, "turretmode")
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
	if unitTeam ~= myTeamID then return end
	addWatchedTurret(unitID, unitDefID)
	if unitTeam == myTeamID then
		updateUnitCache(unitID)
	end
end

function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer)
	if unitTeam ~= myTeamID then return end
	if unitMetadataCache[unitID] then
		local health, maxHealth, paralyzeDamage, captureProgress, buildProgress = Spring.GetUnitHealth(unitID)
		if health then
			unitMetadataCache[unitID].health = health
			unitMetadataCache[unitID].buildProgress = buildProgress
			unitMetadataCache[unitID].lastUpdated = Spring.GetGameFrame()
			
			local metalCost = unitMetadataCache[unitID].metalCost
			local energyCost = unitMetadataCache[unitID].energyCost
			local remainingCost = 0
			if buildProgress < 1 then
				local remainingMetal = metalCost * (1 - buildProgress)
				local remainingEnergy = energyCost * (1 - buildProgress)
				remainingCost = remainingMetal * 2 + remainingEnergy
			else
				local healthFraction = health / maxHealth
				local repairMetal = metalCost * (1 - healthFraction)
				local repairEnergy = energyCost * (1 - healthFraction)
				remainingCost = repairMetal * 2 + repairEnergy
			end
			unitMetadataCache[unitID].remainingCost = remainingCost
		end
	end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
	removeWatchedTurret(unitID)
end

function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
	if newTeam == myTeamID then
		addWatchedTurret(unitID, unitDefID)
	end
end

function widget:UnitTaken(unitID, unitDefID, oldTeam, newTeam)
	if oldTeam == myTeamID then
		removeWatchedTurret(unitID)
	end
end

function widget:UnitCaptured(unitID, unitDefID, oldTeam, newTeam)
	if newTeam == myTeamID then
		addWatchedTurret(unitID, unitDefID)
	elseif oldTeam == myTeamID then
		removeWatchedTurret(unitID)
	end
end

function widget:GameFrame(n)
	if n % 300 == 0 then
		refreshWatchedTurrets()
		cleanupUnitCache()
	end
	if n % 30 == 0 then
		processNanoTurretTargets()
	end
end

function widget:CommandNotify(cmdID, cmdParams, cmdOptions)
	local selectedUnits = Spring.GetSelectedUnits()
	if selectedUnits then
		for _, unitID in ipairs(selectedUnits) do
			if watchedTurrets[unitID] then
				if cmdID ~= CMD_STOP and cmdID ~= CMD_ECO_MODE and cmdID ~= CMD_REPAIR_MODE and cmdID ~= CMD_RECLAIM_MODE then
					local widgetCmd = widgetIssuedCommands[unitID]
					local isWidgetCommand = widgetCmd and
											  widgetCmd.cmdID == cmdID and
											  widgetCmd.targetID == (cmdParams[1] or nil) and
											  Spring.GetGameFrame() - widgetCmd.frame < 2
					if not isWidgetCommand then
						userOverriddenTurrets[unitID] = true
						widgetIssuedCommands[unitID] = nil
					end
				end
			end
		end
	end
	
	if cmdID == CMD_ECO_MODE then
		if not selectedUnits or #selectedUnits == 0 then return false end
		local selectedTurrets = {}
		for _, unitID in ipairs(selectedUnits) do
			if watchedTurrets[unitID] then
				table.insert(selectedTurrets, unitID)
			end
		end
		if #selectedTurrets == 0 then return false end
		local currentTurretMode = getTurretMode(selectedTurrets[1])
		local newMode
		if currentTurretMode == "ECO" then
			newMode = "REPAIR"
		elseif currentTurretMode == "REPAIR" then
			newMode = "RECLAIM"
		else
			newMode = "ECO"
		end
		for _, turretID in ipairs(selectedTurrets) do
			setTurretMode(turretID, newMode)
		end
		return true
	elseif cmdID == CMD_REPAIR_MODE then
		for _, unitID in ipairs(selectedUnits or {}) do
			if watchedTurrets[unitID] then
				setTurretMode(unitID, "REPAIR")
			end
		end
		return true
	elseif cmdID == CMD_RECLAIM_MODE then
		for _, unitID in ipairs(selectedUnits or {}) do
			if watchedTurrets[unitID] then
				setTurretMode(unitID, "RECLAIM")
			end
		end
		return true
	end
	return false
end

function widget:GetConfigData()
	return {}
end

function widget:SetConfigData(data)
end

function widget:CommandsChanged()
	local selected = Spring.GetSelectedUnits()
	if not selected or #selected == 0 then return end
	local turrets = {}
	for _, unitID in ipairs(selected) do
		if watchedTurrets[unitID] then
			table.insert(turrets, unitID)
		end
	end
	if #turrets == 0 then return end
	local displayMode = getTurretMode(turrets[1])
	if displayMode == "ECO" then
		CMD_MODE_DESC.params[1] = 0
	elseif displayMode == "REPAIR" then
		CMD_MODE_DESC.params[1] = 1
	elseif displayMode == "RECLAIM" then
		CMD_MODE_DESC.params[1] = 2
	end
	local cmds = widgetHandler.customCommands
	cmds[#cmds + 1] = CMD_MODE_DESC
end
