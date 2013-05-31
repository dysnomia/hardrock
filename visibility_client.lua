-- client that drives to the farthest point it can still see
local Vector = require "Vector"

-- saved width and height of board
local width, height

-- table of tiles with type {Vector pos, int dir, int turnType, String typ}
local tiles = {}

-- game board constants
local TILE_SIZE = 45
local TURN_NONE = 0
local TURN_LEFT = -1
local TURN_RIGHT = 1

-- constants for parametrisation
local PAR_LEFT  = -1
local PAR_MID   = 0
local PAR_RIGHT = 1

-- circular arc parametrisation
local function curveParam(t, which)
	which = which or PAR_MID
	local res = Vector(3.5*TILE_SIZE, 0)
	t = t * (math.pi / 2)
	res = res - (3.5 - which * 2.5)*TILE_SIZE * Vector(math.cos(t), math.sin(t))
	return res
end

-- straight line parametrisation
local function straightParam(t, which)
	which = which or PAR_MID
	return Vector(which * 2.5 * TILE_SIZE, -t * 3 * TILE_SIZE)
end

-- tile parametrisation (selects type of tile)
local function tileParam(tile, t, which)
	which = which or PAR_MID
	local res = tile.pos:clone()
	local loc
	if(tile.turnType ~= TURN_NONE) then
		loc = curveParam(t, which)
		if (tile.turnType == TURN_LEFT) then
			loc.x = -loc.x
		end
	else
		loc = straightParam(t, which)
	end
	--print("Loc: ", tile.dir, " ", loc, " ", loc:rotated(tile.dir * math.pi / 2))
	
	return res + loc:rotate(tile.dir * math.pi / 2)
end

-- parametrisation of the lines bounding a track as curves
-- t = parameter
-- which =
--   PAR_LEFT: left border of track
--   PAR_MID:  middle line through track
--   PAR_RIGHT: right border of track
local function trackParam(t, which)
	which = which or PAR_MID
	return tileParam(tiles[math.floor(t) % #tiles + 1], t % 1, which)
end

-- map of external tile representation to internal one
local dir_to_shift = {
	LEFT  = Vector(3*TILE_SIZE, 2.5*TILE_SIZE),
	RIGHT = Vector(          0, 2.5*TILE_SIZE),
	UP    = Vector(2.5*TILE_SIZE, 3*TILE_SIZE),
	DOWN  = Vector(2.5*TILE_SIZE,           0),
}
local turn_to_turn = {
	straight  = TURN_NONE,
	turnleft  = TURN_LEFT,
	turnright = TURN_RIGHT,
	finish    = TURN_NONE
}
local str_to_dir = {
	UP = 0,
	RIGHT = 1,
	DOWN = 2,
	LEFT = 3,
}

-- return the player strategy
return {
	-- gamestart = build representation of tiles
	-- gets message with .track = {width, height, tiles}
	gamestart = function(req)
		log("Starting game...\n")
		
		-- read track
		local track = req.track
		width = track.width
		height = track.height
		printf("Got gameboard of size %dx%d and tiled = %s\n", width, height, tostring(track.tiled))
		
		-- tile[1] = {straight, turnleft, turnright, finish}, tile[2,3] = {x, y}
		local direction = str_to_dir[track.startdir]
		local currentPos = Vector(track.tiles[1][2], track.tiles[1][3]) + dir_to_shift[track.startdir]
		local start = currentPos:clone()
		
		-- build parametrisation
		for idx, tile in ipairs(track.tiles) do
			--print("Pos = ", start, currentPos)
			tiles[idx] = {
				pos = currentPos,
				dir = direction,
				turnType = turn_to_turn[tile[1]],
				typ = tile[1]
			}
			
			currentPos = tileParam(tiles[idx], 1)
			direction = (direction + tiles[idx].turnType) % 4
		end
		
		--print("Pos = ", start, currentPos)
	end,
	
	-- update on gamestate -> answer with action
	gamestate = function(req)
		-- find myself
		local car
		for _, other_car in ipairs(req.cars) do
			if other_car.driver == player then
				car = other_car
				break
			end
		end
		-- do nothing if we are dead
		if car == nil then
			return
		end
		
		-- parameters for the algorithm
		local RESOLUTION = 0.1
		local MIN_OFFSET = 1
		local OFFSET = 1.5
		local MINDALPHA  = 0.2
		local MINSPEED   = 300
		local NORMAL_SPEED = 100
		local MIN_ANGLE  = 0.4
		local MINE_PROB = 0.01   -- probability of laying of mine
		local MISSILE_ANGLE = 0.2 -- angle another player has to be in to fire missile
		local MISSILE_DIST  = 300  -- distance another player has to be in to fire missile
		
		local minDist = math.huge
		local mint = nil
		local pos = Vector(car.locationX, car.locationY)
		local dir = Vector(car.speedX, car.speedY) -- current driving direction
		local speed = dir:len()
		
		-- where are we on the parametrisation?
		for t = 0, #tiles, RESOLUTION do
			local dist = (trackParam(t) - pos):lenSq()
			--print("PARAM: ", t, trackParam(t))
			if (dist < minDist) then
				minDist = dist
				mint    = t
			end
		end
		
		-- look for the nearest visible point to drive to
		local t = mint + 0.2
		local rightMostToLeft = trackParam(t, PAR_LEFT) - pos
		local leftMostToRight = trackParam(t, PAR_RIGHT) - pos
		while (rightMostToLeft:angleTo(leftMostToRight) > MIN_ANGLE) do
			t = t + RESOLUTION
			local nextLeft  = trackParam(t, PAR_LEFT ) - pos
			local nextRight = trackParam(t, PAR_RIGHT) - pos
			
			--print(trackParam(t, PAR_LEFT ), trackParam(t, PAR_RIGHT ))
			
			if(rightMostToLeft:angleTo(nextLeft) > 0) then
				rightMostToLeft = nextLeft
			end
			
			if(leftMostToRight:angleTo(nextRight) < 0) then
				leftMostToRight = nextRight
			end
		end
		--print("t - mint: ", t - mint)
		
		-- drive towards targetPos
		t = math.max(t, mint + MIN_OFFSET)
		local targetPos = 1.0 * trackParam(t) + 0 * trackParam(mint + math.max(speed / NORMAL_SPEED, MIN_OFFSET))
		--local targetPos = trackParam(mint + math.max(speed / NORMAL_SPEED, MIN_OFFSET))
		local diff      = targetPos - pos
		--print("speed = ", speed)
		
		-- turn if we are far from the target direction
		diff:normalize()
		dir:normalize()
		local cp = diff:cross(dir)
		local turning = false
		if (cp < -MINDALPHA) then
			action("turnright")
			turning = true
		elseif (cp > MINDALPHA) then
			action("turnleft")
			turning = true
		else
			action("stopturning")
		end
		
		-- accelerate if we are slow or not turning
		if (not turning or speed < MINSPEED) then
			action("accelerate")
			action("boost")
		else 
			action("stopaccelerate")
		end			
		
		-- Randomly drop mines
		if math.random() < MINE_PROB then
			action("mine")
		end
		
		-- Fire missile if other player before me
		for _, other_car in ipairs(req.cars) do
			if other_car.driver ~= player then
				local pos_other = Vector(other_car.locationX, other_car.locationY)
				local dir_other = (pos_other - pos):normalized()
				local angle_other = math.abs(dir_other:cross(dir))
				print("Distance, angle to other: ", Vector.distance(pos_other, pos), angle_other)
				if Vector.distance(pos_other, pos) < MISSILE_DIST and 0 < angle_other and angle_other < MISSILE_ANGLE then
					action("missile")
				end
			end
		end
	end,
	
	raceover = function(req)
		log("Race over.\n")
	end
}
