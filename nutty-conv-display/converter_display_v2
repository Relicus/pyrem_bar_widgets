-- Converter Energy Display Widget v2 (Minimal)
-- Shows only energy ratio with visual color coding

function widget:GetInfo()
	return {
		name = "Conversion Display v2",
		desc = "Minimal converter energy ratio display",
		author = "Pyrem",
		date = "2025",
		license = "GNU GPL, v2 or later",
		layer = -9,
		enabled = true,
	}
end

--------------------------------------------------------------------------------
-- PERFORMANCE OPTIMIZATIONS
--------------------------------------------------------------------------------

local mathmin = math.min
local mathabs = math.abs

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local UPDATE_FRAMES = 30  -- Update every 1 second

-- Texture settings
local textureSizeX = 160  -- 40% reduction from 300px
local textureSizeY = 60   -- 70% reduction from 200px

-- Position offsets (universal for all modes)
local positionOffsetX = -470  -- Left side
local positionOffsetY = -6    -- Near top

-- Visual settings
local fontSize = 13       -- 20% reduction from 16px
local padding = 6
local barHeight = 30
local cornerRadius = 6

-- Ratio thresholds (RATIO_MAX not used - bar always full width)
-- local RATIO_MAX = 1.2  -- Not needed - bar is always full width
local RATIO_BALANCED_MIN = 0.95
local RATIO_BALANCED_MAX = 1.05

-- Color themes (based on energy ratio)
-- LOW: eIncome < converter needs (yellow) → BUILD ENERGY
-- BALANCED: eIncome ≈ converter needs (green) → BALANCED
-- HIGH: eIncome > converter needs (light gray) → BUILD METAL
local colorThemes = {
	low = {  -- ratio < 0.95 (need more energy)
		barGradientStart = {1, 1, 0, 0.9},    -- Bright yellow
		barGradientEnd = {1, 0.6, 0, 0.9},    -- Orange-yellow
		border = {1, 1, 0, 0.8},              -- Yellow border
		text = {1, 1, 0.3, 1},                -- Yellow text
		label = "Build Energy"
	},
	balanced = {  -- 0.95 <= ratio <= 1.05 (optimal)
		barGradientStart = {0.5, 1, 0, 0.9},  -- Light green
		barGradientEnd = {0, 0.8, 0, 0.9},    -- Green
		border = {0, 1, 0, 0.7},
		text = {0.5, 1, 0.5, 1},
		label = "Balanced"
	},
	high = {  -- ratio > 1.05 (excess energy, build metal)
		barGradientStart = {0.9, 0.9, 0.9, 0.9},  -- Light gray
		barGradientEnd = {0.6, 0.6, 0.6, 0.9},    -- Medium gray
		border = {0.7, 0.7, 0.7, 0.8},            -- Gray border
		text = {0.9, 0.9, 0.9, 1},                -- Light gray text
		label = "Build Metal"
	}
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local font
local displayTexture = nil
local textureNeedsUpdate = true

local vsx, vsy = Spring.GetViewGeometry()
local viewSizeX, viewSizeY = 0, 0
local x1, y1 = 0, 0

-- Spectator mode support
local myPlayerID = nil
local myTeamID = nil
local targetTeamID = nil  -- Which team to track (for spectator mode)
local isSpectator = false

-- Converter data (minimal - only need ratio!)
local converterData = {
	eRatio = 1.0
}

local currentTheme = colorThemes.balanced

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

-- Interpolate between two colors
-- Returns: {r, g, b, a}
-- Ref: gui_converter_energy_display.lua:116-123
local function lerpColor(colorA, colorB, t)
	return {
		colorA[1] + (colorB[1] - colorA[1]) * t,
		colorA[2] + (colorB[2] - colorA[2]) * t,
		colorA[3] + (colorB[3] - colorA[3]) * t,
		colorA[4] + (colorB[4] - colorA[4]) * t,
	}
end

-- Draw rounded rectangle approximation
-- Uses simple rectangles with corner segments
-- Ref: gui_converter_energy_display.lua:127-139
local function drawRoundedRect(x, y, width, height, radius, color)
	gl.Color(color)

	-- Main body (center rectangle)
	gl.Rect(x + radius, y, x + width - radius, y + height)
	gl.Rect(x, y + radius, x + width, y + height - radius)

	-- Corner approximations (small rectangles)
	gl.Rect(x, y, x + radius, y + radius)
	gl.Rect(x + width - radius, y, x + width, y + radius)
	gl.Rect(x, y + height - radius, x + radius, y + height)
	gl.Rect(x + width - radius, y + height - radius, x + width, y + height)
end

-- Draw gradient progress bar (simplified for v2)
-- Ref: gui_converter_energy_display.lua:143-174
local function drawGradientBar(x, y, width, height, gradStartColor, gradEndColor)
	-- Draw gradient as segments
	local segments = 20
	for i = 0, segments - 1 do
		local segX = x + (width / segments) * i
		local segWidth = width / segments
		local t = i / segments
		local segColor = lerpColor(gradStartColor, gradEndColor, t)

		gl.Color(segColor)
		gl.Rect(segX, y, segX + segWidth, y + height)
	end
end

-- NOTE: Bar fill calculation removed - bar is always full width
-- Only color changes based on ratio thresholds:
-- - ratio < 0.95: Yellow (Build Energy)
-- - ratio 0.95-1.05: Green (Balanced)
-- - ratio > 1.05: Gray (Build Metal)
-- (getBarFillPercentage function removed - no longer needed)

-- Get theme based on ratio thresholds
-- LOW (<0.95): Need energy → Yellow → "Build Energy"
-- BALANCED (0.95-1.05): Optimal → Green → "Balanced"
-- HIGH (>1.05): Excess energy → Light Gray → "Build Metal"
local function getThemeForRatio(ratio)
	if ratio < RATIO_BALANCED_MIN then
		return colorThemes.low
	elseif ratio <= RATIO_BALANCED_MAX then
		return colorThemes.balanced
	else
		return colorThemes.high
	end
end

--------------------------------------------------------------------------------
-- TEXTURE SYSTEM
--------------------------------------------------------------------------------

-- Draw all UI elements to texture
-- Coordinate system: (0, 0) to (textureSizeX, textureSizeY) after transformation
-- Ref: gui_converter_energy_display.lua:194-320
local function drawToTexture()
	-- Clear texture background
	gl.Blending(GL.ONE, GL.ZERO)
	gl.Color(0, 0, 0, 0.0)  -- BLACK transparent (fixed from white)
	gl.Rect(-textureSizeX, -textureSizeY, textureSizeX, textureSizeY)

	-- Apply coordinate transformation for texture space
	-- Ref: gui_converter_energy_display.lua:197-199
	gl.PushMatrix()
	gl.Translate(-1, -1, 0)
	gl.Scale(2 / textureSizeX, 2 / textureSizeY, 0)

	-- Now drawing in local pixel coordinates (0,0) to (textureSizeX, textureSizeY)

	local theme = currentTheme

	-- Calculate positions
	local bgX = 0  -- Changed from padding
	local bgY = 0  -- Changed from padding
	local bgWidth = textureSizeX  -- Changed from textureSizeX - (2 * padding)
	local bgHeight = textureSizeY  -- Changed from textureSizeY - (2 * padding)

	local barX = padding * 3  -- Changed from padding * 2
	local barY = (textureSizeY - barHeight) / 2
	local barWidth = textureSizeX - (6 * padding) - 30  -- Changed from (4 * padding)

	local textX = barX + barWidth + 8
	local textY = textureSizeY / 2

	-- 1. Draw background (hardcoded transparent black)
	local hardcodedBackground = {0, 0, 0, 0.75}  -- Black with 75% opacity
	drawRoundedRect(bgX, bgY, bgWidth, bgHeight, cornerRadius, hardcodedBackground)

	-- 2. Draw border
	gl.Color(theme.border)
	gl.LineWidth(2)
	gl.Shape(GL.LINE_LOOP, {
		{v = {bgX, bgY}},
		{v = {bgX + bgWidth, bgY}},
		{v = {bgX + bgWidth, bgY + bgHeight}},
		{v = {bgX, bgY + bgHeight}}
	})

	-- 3. Draw progress bar background (dark unfilled area)
	gl.Color(0.15, 0.15, 0.15, 0.8)
	gl.Rect(barX, barY, barX + barWidth, barY + barHeight)

	-- 4. Draw progress bar (always full width, color changes based on ratio)
	drawGradientBar(barX, barY, barWidth, barHeight, theme.barGradientStart, theme.barGradientEnd)

	-- 5. Draw label text INSIDE the bar (always centered in full bar)
	font:Begin()
		font:SetTextColor({0, 0, 0, 0.9})  -- Dark text for contrast
		font:Print(
			theme.label,  -- "Build Energy" / "Balanced" / "Build Metal"
			barX + (barWidth / 2),  -- Center of full bar
			barY + (barHeight / 2),  -- Vertical center
			fontSize - 1,  -- Slightly smaller font
			'cv'  -- center horizontal, vertical center
		)
	font:End()

	-- 6. Draw ratio text (right side)
	font:Begin()
	font:SetTextColor(theme.text)
	font:Print(
		string.format("%.2f", converterData.eRatio),
		textX,
		textY,
		fontSize,
		'lv'  -- left-aligned, vertical center
	)
	font:End()

	gl.PopMatrix()
end

-- Update texture if dirty flag is set
-- Ref: gui_converter_energy_display.lua:324-329
local function updateTexture()
	if displayTexture and textureNeedsUpdate then
		gl.RenderToTexture(displayTexture, drawToTexture)
		textureNeedsUpdate = false
	end
end

-- Create texture for rendering
-- Ref: gui_converter_energy_display.lua:333-347
local function createTexture()
	if displayTexture then
		gl.DeleteTexture(displayTexture)
	end

	-- Create texture with FBO for rendering
	-- Spring API: gl.CreateTexture(width, height, {options}) -> textureID
	displayTexture = gl.CreateTexture(textureSizeX, textureSizeY, {
		target = GL.TEXTURE_2D,
		format = GL.RGBA,
		fbo = true  -- CRITICAL: Required for gl.RenderToTexture
	})

	textureNeedsUpdate = true
end

-- Cleanup texture
-- Ref: gui_converter_energy_display.lua:350-355
local function deleteTexture()
	if displayTexture then
		gl.DeleteTexture(displayTexture)
		displayTexture = nil
	end
end

--------------------------------------------------------------------------------
-- DATA PROCESSING
--------------------------------------------------------------------------------

-- Detect which team spectator should track based on selected units
-- Based on pattern from build_time_estimator_v2.lua
-- MUST BE DEFINED BEFORE updatePlayerInfo() which calls it
local function detectSpectatorTargetTeam()
	if not isSpectator then
		return myTeamID
	end

	-- Check if spectator has full view
	local spec, fullView, fullSelect = Spring.GetSpectatingState()
	if not fullView then
		return myTeamID  -- Limited spectator, use own team
	end

	-- PRIORITY 1: Check selected units to determine which team to track
	local selectedUnits = Spring.GetSelectedUnits()
	if selectedUnits and #selectedUnits > 0 then
		-- Use the team of the first selected unit
		local unitTeam = Spring.GetUnitTeam(selectedUnits[1])
		if unitTeam then
			return unitTeam
		end
	end

	-- PRIORITY 2: No units selected, try to find first valid team with units
	local teamList = Spring.GetTeamList()
	if teamList then
		for _, teamID in ipairs(teamList) do
			local teamUnits = Spring.GetTeamUnits(teamID)
			if teamUnits and #teamUnits > 0 then
				-- Check if this is a real player team (not Gaia)
				local _, leader = Spring.GetTeamInfo(teamID)
				if leader and leader >= 0 then
					return teamID
				end
			end
		end
	end

	-- Fallback to own team
	return myTeamID
end

-- Update player and spectator information
local function updatePlayerInfo()
	myPlayerID = Spring.GetMyPlayerID()
	local _, _, spec, teamID = Spring.GetPlayerInfo(myPlayerID)
	myTeamID = teamID
	isSpectator = spec

	-- Detect which team to track
	targetTeamID = detectSpectatorTargetTeam()
end

-- Update converter data from Spring API
-- Ref: gui_converter_energy_display.lua:363-400
local function UpdateConverterData()
	-- Use targetTeamID for spectator support (falls back to myTeamID for players)
	local teamToCheck = targetTeamID or Spring.GetMyTeamID()

	-- Spring API: Spring.GetTeamRulesParam(teamID, "mmCapacity") -> max converter capacity (E/sec)
	local mmCapacity = Spring.GetTeamRulesParam(teamToCheck, "mmCapacity")

	-- Spring API: Spring.GetTeamResources(teamID, "energy") -> current, storage, pull, income
	local _, _, ePull, eIncome = Spring.GetTeamResources(teamToCheck, "energy")

	-- Energy ratio calculation:
	-- newRatio = eIncome / (mmCapacity / 0.85)
	-- - mmCapacity = max theoretical converter capacity (E/sec)
	-- - 0.85 = 85% efficiency factor (converters are 85% efficient)
	-- - eIncome = current energy production
	--
	-- This formula measures "can I support my converters at 85% efficiency"
	-- It ignores temporary construction/weapon drains, focusing on base economy structure
	-- HIGH ratio (>1.05): Energy income exceeds converter needs → BUILD METAL
	-- LOW ratio (<0.95): Energy income below converter needs → BUILD ENERGY
	-- BALANCED (0.95-1.05): Energy income matches converter needs → BALANCED
	local newRatio = 1.0
	if mmCapacity and mmCapacity > 0 and eIncome and eIncome > 0 then
		newRatio = eIncome / (mmCapacity / 0.85)
	end

	-- Update theme if state changed
	local newTheme = getThemeForRatio(newRatio)
	if newTheme ~= currentTheme then
		currentTheme = newTheme
		textureNeedsUpdate = true
	end

	-- Update ratio if changed significantly (0.01 threshold to avoid micro-updates)
	if mathabs(newRatio - converterData.eRatio) > 0.01 then
		converterData.eRatio = newRatio
		textureNeedsUpdate = true
	end
end

--------------------------------------------------------------------------------
-- WIDGET CALLBACKS
--------------------------------------------------------------------------------

function widget:Initialize()
	-- Initialize player info (works in both player and spectator modes)
	updatePlayerInfo()

	-- Get font from BAR font system
	font = WG['fonts'].getFont(nil, nil, 0.4, 1.76)

	widget:ViewResize()
	createTexture()
	UpdateConverterData()

	local modeText = isSpectator and "spectator mode" or "player mode"
	Spring.Echo("Converter Display v2: Initialized in " .. modeText)
end

function widget:Shutdown()
	deleteTexture()
end

-- Check and update texture before drawing
-- Ref: gui_converter_energy_display.lua:440-442
function widget:DrawGenesis()
	if textureNeedsUpdate and displayTexture then
		updateTexture()
	end
end

-- Draw texture to screen
-- Ref: gui_converter_energy_display.lua:446-463
function widget:DrawScreen()
	-- Skip if no converters for the tracked team
	local teamToCheck = targetTeamID or Spring.GetMyTeamID()
	local mmCapacity = Spring.GetTeamRulesParam(teamToCheck, "mmCapacity")
	if not mmCapacity or mmCapacity == 0 then
		return  -- No converters for this team
	end

	if not displayTexture then
		return
	end

	-- Draw texture at screen position
	gl.Color(1, 1, 1, 1)
	gl.Texture(displayTexture)
	-- Spring API: gl.TexRect(x1, y1, x2, y2, flipX, flipY)
	-- flipX=false, flipY=true provides correct texture orientation (Y-axis inverted in OpenGL)
	gl.TexRect(x1, y1, x1 + textureSizeX, y1 + textureSizeY, false, true)
	gl.Texture(false)
end

function widget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateConverterData()
	end
end

function widget:ViewResize()
	vsx, vsy = Spring.GetViewGeometry()
	viewSizeX, viewSizeY = vsx, vsy

	local offsetX = positionOffsetX
	local offsetY = positionOffsetY

	local x0 = (viewSizeX / 2) - (textureSizeX / 2) + offsetX
	local y0 = viewSizeY - textureSizeY - offsetY

	x1 = x0
	y1 = y0

	textureNeedsUpdate = true
end

-- Handle unit selection changes (for spectator team switching)
function widget:SelectionChanged(selectedUnits)
	if not isSpectator then
		return  -- Only relevant for spectators
	end

	-- Check if we have a new team selected
	local oldTargetTeam = targetTeamID
	targetTeamID = detectSpectatorTargetTeam()

	-- If team changed, update data immediately
	if oldTargetTeam ~= targetTeamID then
		UpdateConverterData()
		textureNeedsUpdate = true  -- Force texture redraw on team switch
		Spring.Echo("Converter Display v2: Switched to team " .. targetTeamID)
	end
end

-- Handle player changes (spectator switching, etc.)
function widget:PlayerChanged(playerID)
	-- Update our player information when players change
	updatePlayerInfo()
	textureNeedsUpdate = true  -- Force texture redraw on player change
	widget:ViewResize()  -- Update position when switching modes

	local modeText = isSpectator and "spectator mode" or "player mode"
	Spring.Echo("Converter Display v2: Player changed, now in " .. modeText)
end
