--[[
custom_terrain_rivers.script.lua - Natural river network generator for the "Custom Terrain (Experimental)"
TF3 map generator. Replaces the vanilla script node gui/node_editor/river_points.node
(implemented in base gui.zip gui/node_editor/layer_nodes.script.tl + climates/gen/*.tl).

WHY (problems with the vanilla generator; vanilla source: base gui.zip
gui/node_editor/layer_nodes.script.tl and climates/gen/mapgenutil.tl + rivermapgenutil.tl):
  * Vanilla meanders flip the bend direction at EVERY evenly spaced control point with an almost
    constant angle -> a fixed-period zig-zag / sine look.
  * Vanilla half-width = 12*(5 - order/1.5) + rand*22 per point: constant along a river, set only by
    branching order; the computed drainage volume is never used. No mouths, deltas or bends.

WHAT THIS DOES
  1. Network: same idea as vanilla (rivers start inside water and grow inland in coarse segments,
     greedy on a weight map, collision-checked, recursive tributaries), ported to plain Lua.
     Optional GREAT RIVER: grown first, from the coast side (lowest coastT, preferably in water)
     straight across the map toward the far side.
  2. Discharge Q along every river (upstream length + tributary inflow) -> width ~ sqrt(Q):
     narrow streams at the headwaters, widening downstream and at each confluence, widest at the
     mouth. The width slider scales big rivers; small streams stay natural.
  3. Meanders: dense Catmull-Rom base path, then a Kinoshita-type sine-generated curve
        phi(s) = theta0(s)*sin(PHI) + theta0^3*(Js*cos(3PHI) - Jf*sin(3PHI))
     whose wavelength (10-16 x channel width) and amplitude vary smoothly and randomly along the
     river (non-periodic), damped in steep terrain (flatness map) and near junctions/mouths.
     Each reach between anchors (mouth, junctions, source) is similarity-transformed so anchors stay
     exactly in place -> tributaries stay connected.
  4. Width details: estuary flare at mouths in water, slight bulge at confluences, outer-bank
     widening in bends, optional deltas (2-4 distributaries) for large rivers at the coast.
  5. Output format identical to vanilla (pointy tip at each river's last point, rivers
     concatenated with a duplicated separator point) so the native river_map node consumes it.

Plain Lua (5.1/5.3/5.4/LuaJIT compatible), no requires. Engine APIs used: api.type.Vec2f.new,
map:get / map:isEmpty, log.verbose (optional).
]]

function data()

local PI = math.pi
local atan2 = math.atan2 or math.atan
local sqrt, abs, floor, cos, sin, exp = math.sqrt, math.abs, math.floor, math.cos, math.sin, math.exp

local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function lerp(a, b, t) return a + (b - a) * t end
local function randf(a, b) return a + math.random() * (b - a) end
local function smoothstep(t) t = clamp(t, 0, 1) return t * t * (3 - 2 * t) end
local function logv(msg) if log and log.verbose then log.verbose(msg) end end

local function numIn(inp, default)
	if inp ~= nil and inp.value ~= nil then return inp.value end
	return default
end

local function mapGet(inp, x, y, default)
	if inp == nil or inp.map == nil or inp.map:isEmpty() then return default end
	return inp.map:get(api.type.Vec2f.new(x, y))
end

-- 1D smooth value noise along a river (knots every `spacing` metres, values in [0,1])
local function makeNoise1(spacing)
	local knots = {}
	return function(s)
		local f = s / spacing
		local i = floor(f)
		local t = f - i
		local a = knots[i]; if a == nil then a = math.random(); knots[i] = a end
		local b = knots[i + 1]; if b == nil then b = math.random(); knots[i + 1] = b end
		return lerp(a, b, smoothstep(t))
	end
end

---------------------------------------------------------------------------------------------
-- 1. Network growth (port of vanilla map_gen_util.makeRivers with collision hashing)
---------------------------------------------------------------------------------------------
local BLOCK = 800
local DIST_CHECK = 1400   -- max spacing (trunks); streams use less, see SPACING
-- minimum distance kept from OTHER rivers, by branching order of the river being grown.
-- Vanilla uses 1400 m for every river, which rejects most tributaries (they cannot get 1400 m
-- away from their parent within their second segment); small streams may run closer.
local SPACING = {1400, 1000, 750, 600, 600, 600, 600, 600, 600, 600, 600}
local OUTSIDE = 5000
local MAX_IMPASSABLE = 1.2
local RIVER_PROB = {0.6, 0.4, 0.1, 0.05, 0.05}
local CHILD_COUNT = {12, 4, 4, 4, 4}

local function newGrid() return { cells = {} } end
local function cellKey(cx, cy) return cx * 1000003 + cy end

local function gridInsert(grid, x, y, id, log2)
	local k = cellKey(floor(x / BLOCK), floor(y / BLOCK))
	local c = grid.cells[k]
	if c == nil then c = {}; grid.cells[k] = c end
	c[#c + 1] = { id = id, x = x, y = y }
	log2[#log2 + 1] = k
end

local function gridRemoveId(grid, keys, id)
	for _, k in ipairs(keys) do
		local c = grid.cells[k]
		if c then
			for i = #c, 1, -1 do if c[i].id == id then table.remove(c, i) end end
		end
	end
end

local function gridHit(grid, x, y, selfId, ignoreId, bounds, dist)
	if x < bounds.min.x - OUTSIDE or x > bounds.max.x + OUTSIDE or
	   y < bounds.min.y - OUTSIDE or y > bounds.max.y + OUTSIDE then return false end
	local cx0, cy0 = floor((x - dist) / BLOCK), floor((y - dist) / BLOCK)
	local cx1, cy1 = floor((x + dist) / BLOCK), floor((y + dist) / BLOCK)
	for cx = cx0, cx1 do
		for cy = cy0, cy1 do
			local c = grid.cells[cellKey(cx, cy)]
			if c then
				for _, e in ipairs(c) do
					if e.id ~= selfId and e.id ~= ignoreId then
						local dx, dy = e.x - x, e.y - y
						if dx * dx + dy * dy < dist * dist then return true end
					end
				end
			end
		end
	end
	return false
end

local function segmentHits(grid, x0, y0, x1, y1, selfId, ignoreId, bounds, dist)
	local d = sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
	local n = math.max(1, math.ceil(d / dist) * 10)
	for j = 1, n do
		local f = j / n
		if gridHit(grid, x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, selfId, ignoreId, bounds, dist) then
			return true
		end
	end
	return false
end

-- grow one river (and recursively its tributaries). Returns river id or nil.
local function grow(ctx, startX, startY, startDir, length, order, parentId, parentIdx, mode)
	local cfg = ctx.cfg
	ctx.nextId = ctx.nextId + 1
	local id = ctx.nextId
	local river = { id = id, order = order, parent = parentId, parentIdx = parentIdx,
		pts = {}, dirs = {}, children = {}, great = (mode == "great") }
	local keys = {}
	local x, y, dir = startX, startY, startDir
	local oldDir = startDir
	local px, py = x, y
	local interrupted = false
	local maxSeg = (mode == "great") and 200 or 60

	for seg = 1, maxSeg do
		river.pts[#river.pts + 1] = { x = x, y = y }
		river.dirs[#river.dirs + 1] = dir
		local step = cfg.segmentLength
		local nx, ny = x + step * cos(dir), y + step * sin(dir)
		-- register the new segment for collision tests (vanilla: 4 samples per 1400 m)
		local nseg = math.ceil(step / DIST_CHECK) * 4
		for j = 1, nseg do
			local f = j / nseg
			gridInsert(ctx.grid, px + (nx - px) * f, py + (ny - py) * f, id, keys)
		end
		px, py = x, y
		x, y = nx, ny
		length = length - step
		if length < 0 then break end
		local b = cfg.bounds
		if x > b.max.x + OUTSIDE or y > b.max.y + OUTSIDE or x < b.min.x - OUTSIDE or y < b.min.y - OUTSIDE then
			break
		end

		-- vanilla rule: a step is valid only if 0 <= weight < 1.2 (negative = water, >= 1.2 =
		-- impassable deep water) and it does not come within 1400 m of another river.
		-- Normal rivers take the highest weight (they climb away from water); the great river
		-- takes the largest progress across the map (coastT gain).
		local bestScore, bestDir = -1e30, nil
		oldDir = dir
		for _ = 0, 10 do
			local ad = oldDir + randf(-cfg.curvature * 15, cfg.curvature * 15)
			local ax, ay = x + step * cos(ad), y + step * sin(ad)
			-- the parent is ignored for the first two segments (a branch needs room to diverge)
			local ignore = (seg <= 2) and parentId or -1
			local spacing = SPACING[clamp(order + 1, 1, #SPACING)]
			if not segmentHits(ctx.grid, x, y, ax, ay, id, ignore, b, spacing) then
				local w = cfg.weight(ax, ay)
				if w >= 0 and w < MAX_IMPASSABLE then
					local score = w
					if mode == "great" then
						score = 10 * (cfg.coastT(ax, ay) - cfg.coastT(x, y)) + 0.1 * w
					end
					if score >= bestScore then bestScore, bestDir = score, ad end
				end
			end
		end
		if bestDir == nil then interrupted = true; break end
		dir = bestDir
	end

	if mode ~= "great" then
		local tooShort = cfg.minLength and cfg.segmentLength * (#river.pts - 1) < cfg.minLength
		if interrupted or tooShort or #river.pts < 2 then
			gridRemoveId(ctx.grid, keys, id)
			return nil
		end
	elseif #river.pts < 4 then
		gridRemoveId(ctx.grid, keys, id)
		return nil
	end

	ctx.rivers[#ctx.rivers + 1] = river
	ctx.byId[id] = river

	-- tributaries (vanilla probabilities; baseProbability scales them)
	if order < cfg.maxOrder + 1 then
		local oi = clamp(order + 1, 1, 5)
		local count, lastFeeder = 0, -100
		for i = 2, #river.pts - 1 do
			if math.random() < RIVER_PROB[oi] * cfg.baseProbability and count <= CHILD_COUNT[oi]
				and i - lastFeeder > cfg.minDist then
				local side = (math.random() < 0.5) and 1 or -1
				local nd = river.dirs[i] + side * PI * randf(0.18, 0.4)
				local remaining = cfg.segmentLength * (#river.pts - i) + randf(0, 4000)
				local childId = grow(ctx, river.pts[i].x, river.pts[i].y, nd,
					randf(2 / 3, 1) * remaining + 3000, order + 1, id, i, "normal")
				if childId then
					river.children[#river.children + 1] = { idx = i, id = childId }
					count = count + 1
					lastFeeder = i
				end
			end
		end
	end
	return id
end

---------------------------------------------------------------------------------------------
-- 2. Geometry helpers
---------------------------------------------------------------------------------------------
-- Catmull-Rom densification of coarse points; returns arrays of {x,y,s,c} (c = coarse index float)
local function densify(pts, ds)
	local out = {}
	local n = #pts
	local function P(i) return pts[clamp(i, 1, n)] end
	local s = 0
	for i = 1, n - 1 do
		local p0, p1, p2, p3 = P(i - 1), P(i), P(i + 1), P(i + 2)
		local segLen = sqrt((p2.x - p1.x) ^ 2 + (p2.y - p1.y) ^ 2)
		local m = math.max(1, math.ceil(segLen / ds))
		for j = 0, m - 1 do
			local t = j / m
			local t2, t3 = t * t, t * t * t
			local x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
			local y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
			if #out > 0 then
				local q = out[#out]
				s = s + sqrt((x - q.x) ^ 2 + (y - q.y) ^ 2)
			end
			out[#out + 1] = { x = x, y = y, s = s, c = i + t }
		end
	end
	local q = out[#out]
	local last = pts[n]
	s = s + sqrt((last.x - q.x) ^ 2 + (last.y - q.y) ^ 2)
	out[#out + 1] = { x = last.x, y = last.y, s = s, c = n }
	return out
end

-- sample a dense polyline at arc length s (linear); returns x, y, dirAngle, coarse index float
local function sampleAt(base, s, hint)
	local i = hint or 1
	local n = #base
	while i < n - 1 and base[i + 1].s < s do i = i + 1 end
	while i > 1 and base[i].s > s do i = i - 1 end
	local a, b = base[i], base[i + 1]
	local L = b.s - a.s
	local t = (L > 0) and clamp((s - a.s) / L, 0, 1) or 0
	return a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, atan2(b.y - a.y, b.x - a.x), a.c + (b.c - a.c) * t, i
end

---------------------------------------------------------------------------------------------
-- 3. Meandering (Kinoshita curve per reach, anchors preserved)
---------------------------------------------------------------------------------------------
local function meanderReach(base, s0, s1, ctx, river, halfWidthAt, flatAt)
	local cfg = ctx.cfg
	local L = s1 - s0
	local x0, y0 = sampleAt(base, s0)
	local x1, y1 = sampleAt(base, s1)
	local pts = {}
	if L < 60 or cfg.meander <= 0.001 then
		-- copy base points
		local hint = 1
		local s = s0
		while s < s1 - 20 do
			local x, y, _, c, h = sampleAt(base, s, hint); hint = h
			pts[#pts + 1] = { x = x, y = y, s = s }
			s = s + 40
		end
		pts[#pts + 1] = { x = x1, y = y1, s = s1 }
		return pts
	end
	local nAmp = river.noiseAmp
	local nLam = river.noiseLam
	local h = 15          -- integration step along the meandering path (m)
	local s = s0
	local phase = river.phase
	local x, y = x0, y0
	local hint = 1
	pts[1] = { x = x, y = y, s = s }
	local guard = 0
	local lastOut = 0
	while s < s1 and guard < 200000 do
		guard = guard + 1
		local bx, by, bdir, c, hh = sampleAt(base, s, hint); hint = hh
		local w = halfWidthAt(c)
		local lam = math.max(250, (10 + 6 * nLam(s)) * 2 * w)
		-- amplitude: slider x terrain flatness x along-river noise x taper near anchors
		local taper = smoothstep(math.min(s - s0, s1 - s) / (0.6 * lam))
		local th = cfg.meander * 1.45 * (0.2 + 0.8 * flatAt(bx, by)) * (0.3 + 0.7 * nAmp(s)) * taper
		-- keep meander belt amplitude (~0.25*lam*theta) under ~550 m to respect river spacing
		th = math.min(th, 1.8, 550 / (0.25 * lam))
		local phi = th * sin(phase) + th * th * th * (river.Js * cos(3 * phase) - river.Jf * sin(3 * phase))
		local d = bdir + phi
		x = x + h * cos(d)
		y = y + h * sin(d)
		local adv = h * math.max(0.15, cos(phi))
		s = s + adv
		phase = phase + 2 * PI * adv / lam
		lastOut = lastOut + h
		-- adaptive output spacing: ~9 points per meander wavelength, 35..110 m
		if lastOut >= clamp(lam / 9, 35, 110) then
			pts[#pts + 1] = { x = x, y = y, s = math.min(s, s1) }
			lastOut = 0
		end
	end
	river.phase = phase
	-- final point: replace the last emitted point if it is (almost) at the same place,
	-- otherwise append (avoids zero-length segments at junctions and tips)
	local last = pts[#pts]
	if #pts > 1 and (x - last.x) ^ 2 + (y - last.y) ^ 2 < (0.5 * clamp(lastOut, 1, 35)) ^ 2 + 100 then
		pts[#pts] = { x = x, y = y, s = s1 }
	else
		pts[#pts + 1] = { x = x, y = y, s = s1 }
	end
	-- similarity transform: map integrated end points onto the true anchors
	local qx0, qy0 = pts[1].x, pts[1].y
	local qx1, qy1 = pts[#pts].x, pts[#pts].y
	local vx, vy = qx1 - qx0, qy1 - qy0
	local ux, uy = x1 - x0, y1 - y0
	local vv = vx * vx + vy * vy
	if vv < 1 then return pts end
	-- complex division (ux+iuy)/(vx+ivy) = rotation+scale
	local a = (ux * vx + uy * vy) / vv
	local b = (uy * vx - ux * vy) / vv
	for _, p in ipairs(pts) do
		local dx, dy = p.x - qx0, p.y - qy0
		p.x = x0 + a * dx - b * dy
		p.y = y0 + b * dx + a * dy
	end
	return pts
end

---------------------------------------------------------------------------------------------
-- 4. Main
---------------------------------------------------------------------------------------------
local function applyFn(params, inputs, captureParams)
	local seed = numIn(inputs.seed, nil)
	if seed ~= nil then
		math.randomseed(floor(abs(seed) % 2147483646) + 7919)
	else
		math.randomseed(math.random(1, 100000000))
	end

	local bounds = {
		min = { x = inputs.boundsMin.point.x, y = inputs.boundsMin.point.y },
		max = { x = inputs.boundsMax.point.x, y = inputs.boundsMax.point.y },
	}
	local W = bounds.max.x - bounds.min.x
	local H = bounds.max.y - bounds.min.y

	local cfg = {
		bounds = bounds,
		segmentLength = params.segmentLength or 1000,
		maxOrder = floor(params.maxOrder or 6),
		minDist = params.minDist or 2,
		curvature = numIn(inputs.baseCurvature, 0.03),
		baseProbability = numIn(inputs.baseProbability, 1),
		minLength = numIn(inputs.minLength, 2000),
		amount = numIn(inputs.riverAmountFactor, 0.5),
		trunkWidth = numIn(inputs.trunkWidth, 1),
		meander = numIn(inputs.meander, 0.75),
		greatRiver = numIn(inputs.greatRiver, 0) > 0.5,
		deltaChance = numIn(inputs.deltas, 0.5),
		outSpacing = 45,
	}
	cfg.weight = function(x, y) return mapGet(inputs.riverWeight, x, y, 1) end
	cfg.startWeight = function(x, y) return mapGet(inputs.riverWeight, x, y, -1) end
	cfg.coastT = function(x, y)
		local fx = clamp(x, bounds.min.x, bounds.max.x)
		local fy = clamp(y, bounds.min.y, bounds.max.y)
		return mapGet(inputs.coastT, fx, fy, (x - bounds.min.x) / W)
	end
	local function water(x, y)
		if x < bounds.min.x or x > bounds.max.x or y < bounds.min.y or y > bounds.max.y then return 0 end
		return mapGet(inputs.water, x, y, 0)
	end
	local function flat(x, y)
		local fx = clamp(x, bounds.min.x, bounds.max.x)
		local fy = clamp(y, bounds.min.y, bounds.max.y)
		return clamp(mapGet(inputs.flatness, fx, fy, 1), 0, 1)
	end
	local function widthMul(x, y)
		local fx = clamp(x, bounds.min.x, bounds.max.x)
		local fy = clamp(y, bounds.min.y, bounds.max.y)
		return mapGet(inputs.riverWidth, fx, fy, 1)
	end

	local ctx = { cfg = cfg, grid = newGrid(), rivers = {}, byId = {}, nextId = 0 }

	-- 4a. great river: start at the coast side (prefer inside water), head across the map
	if cfg.greatRiver then
		for attempt = 1, 6 do
			local bestT, bx, by = 1e9, nil, nil
			for _ = 1, 600 do
				local x = randf(bounds.min.x, bounds.max.x)
				local y = randf(bounds.min.y, bounds.max.y)
				local t = cfg.coastT(x, y)
				local inWater = water(x, y) > 0.5
				local score = t + (inWater and 0 or 0.25)
				-- avoid map corners so the river runs through the middle part of the map
				local cx = abs((x - bounds.min.x) / W - 0.5)
				local cy = abs((y - bounds.min.y) / H - 0.5)
				score = score + 0.15 * math.max(cx, cy)
				if score < bestT then bestT, bx, by = score, x, y end
			end
			if bx then
				-- direction of increasing coastT (finite differences, 300 m)
				local gx = cfg.coastT(bx + 300, by) - cfg.coastT(bx - 300, by)
				local gy = cfg.coastT(bx, by + 300) - cfg.coastT(bx, by - 300)
				local dir = atan2(gy, gx)
				local n0 = #ctx.rivers
				local id = grow(ctx, bx, by, dir, 300000, 0, -1, 0, "great")
				if id then
					local r = ctx.byId[id]
					local endT = cfg.coastT(r.pts[#r.pts].x, r.pts[#r.pts].y)
					if endT > 0.75 then break end
					logv("great river attempt " .. attempt .. " ended early at t=" .. tostring(endT))
					if attempt < 6 then
						-- keep it anyway if it is the best we get; otherwise retry
						if endT < 0.5 then
							-- roll back the great river AND its tributaries (appended after it)
							for k = #ctx.rivers, n0 + 1, -1 do
								ctx.byId[ctx.rivers[k].id] = nil
								table.remove(ctx.rivers, k)
							end
							-- (their grid entries stay; harmless: they only repel later rivers)
						else
							break
						end
					end
				end
			end
		end
	end

	-- 4b. normal rivers (vanilla start logic)
	local area = sqrt(W * H)
	local numRivers = (area / 30000) * 10 * cfg.amount
	local attempts = floor(numRivers * 300 * cfg.amount + 0.5)
	local starts = {}
	for _ = 1, attempts do
		local x = randf(bounds.min.x, bounds.max.x)
		local y = randf(bounds.min.y, bounds.max.y)
		if cfg.startWeight(x, y) < 0 then
			local best, bestA = -1e30, 0
			for k = 0, 7 do
				local a = k / 8 * 2 * PI
				local w = cfg.startWeight(x + 200 * cos(a), y + 200 * sin(a))
				if w > best then best, bestA = w, a end
			end
			starts[#starts + 1] = { x = x, y = y, a = bestA }
		end
	end
	local num = 0
	for _, st in ipairs(starts) do
		if num >= numRivers then break end
		if grow(ctx, st.x, st.y, st.a, 120000, 0, -1, 0, "normal") then num = num + 1 end
	end
	if num < numRivers then
		for _ = 1, floor(numRivers - num) do
			-- vanilla fallback: start at a random map edge pointing inward
			local side = math.random(1, 4)
			local x, y, a
			if side == 1 then x, y, a = randf(bounds.min.x, bounds.max.x), bounds.max.y, -PI / 2
			elseif side == 2 then x, y, a = bounds.max.x, randf(bounds.min.y, bounds.max.y), PI
			elseif side == 3 then x, y, a = randf(bounds.min.x, bounds.max.x), bounds.min.y, PI / 2
			else x, y, a = bounds.min.x, randf(bounds.min.y, bounds.max.y), 0 end
			if grow(ctx, x, y, a, 120000, 0, -1, 0, "normal") then num = num + 1 end
		end
	end
	logv(string.format("custom_terrain_rivers: %d rivers (+great=%s), %d segments total", num,
		tostring(cfg.greatRiver), #ctx.rivers))

	-- 4c. discharge along each river (children were created after parents -> reverse order)
	for k = #ctx.rivers, 1, -1 do
		local r = ctx.rivers[k]
		local inflow = {}
		for _, ch in ipairs(r.children) do
			local c = ctx.byId[ch.id]
			inflow[ch.idx] = (inflow[ch.idx] or 0) + (c and c.Q and c.Q[1] or 0)
		end
		r.Q = {}
		local q = r.great and 40 or 0
		for i = #r.pts, 1, -1 do
			q = q + 1 + (inflow[i] or 0)
			r.Q[i] = q
		end
	end

	-- 4d. geometry per river
	local outRivers = {}
	local function emit(points, widthsL, widthsR, depths)
		outRivers[#outRivers + 1] = { points = points, wl = widthsL, wr = widthsR, d = depths }
	end

	for _, r in ipairs(ctx.rivers) do
		local n = #r.pts
		r.noiseAmp = makeNoise1(randf(1500, 3000))
		r.noiseLam = makeNoise1(randf(1200, 2500))
		r.phase = randf(0, 2 * PI)
		r.Js = randf(0.0, 0.04)
		r.Jf = randf(0.0, 0.03)
		local bankNoise = makeNoise1(300)

		-- half-width (m) per coarse index (float), before bend/mouth effects
		local function halfWidthAt(c)
			local i = clamp(floor(c), 1, n)
			local j = clamp(i + 1, 1, n)
			local q = lerp(r.Q[i], r.Q[j], c - floor(c))
			local base = 5 + 10 * sqrt(q)
			local scale = 1 + (cfg.trunkWidth - 1) * smoothstep(q / 30)
			return base * scale
		end
		local function depthAt(c)
			local i = clamp(floor(c + 0.5), 1, n)
			return clamp(2.0 + 1.1 * sqrt(r.Q[i]) * math.max(0.8, cfg.trunkWidth ^ 0.5), 3, 12)
		end

		local base = densify(r.pts, 40)
		local total = base[#base].s
		-- anchors: mouth, junction points, source (coarse index -> arc length)
		local anchorC = { 1 }
		for _, ch in ipairs(r.children) do anchorC[#anchorC + 1] = ch.idx end
		anchorC[#anchorC + 1] = n
		table.sort(anchorC)
		local anchorS = {}
		for _, c in ipairs(anchorC) do
			for _, p in ipairs(base) do
				if p.c >= c - 1e-6 then anchorS[#anchorS + 1] = p.s; break end
			end
		end
		local path = {}
		for a = 1, #anchorS - 1 do
			if anchorS[a + 1] - anchorS[a] > 1 then
				local seg = meanderReach(base, anchorS[a], anchorS[a + 1], ctx, r, halfWidthAt, flat)
				for k = (#path == 0) and 1 or 2, #seg do
					local q = path[#path]
					-- drop near-duplicates (< 5 m) so no segment has zero length
					if q == nil or (seg[k].x - q.x) ^ 2 + (seg[k].y - q.y) ^ 2 > 25 then
						path[#path + 1] = seg[k]
					elseif k == #seg then
						path[#path] = seg[k]   -- keep exact anchor position
					end
				end
			end
		end
		if #path >= 2 then
			-- attributes along the path
			local mouthInWater = water(r.pts[1].x, r.pts[1].y) > 0.5 and r.parent == -1
			local flareF = r.great and randf(1.8, 2.6) or randf(1.3, 2.0)
			local wl, wr, dep, pts = {}, {}, {}, {}
			local hint = 1
			local parentDepth = nil
			if r.parent ~= -1 then
				local p = ctx.byId[r.parent]
				if p and p.depthAtJunction then parentDepth = p.depthAtJunction[r.parentIdx] end
			end
			for k, p in ipairs(path) do
				local _, _, _, c, hh = sampleAt(base, clamp(p.s, 0, total), hint); hint = hh
				local w = halfWidthAt(c) * widthMul(p.x, p.y) * (0.92 + 0.16 * bankNoise(p.s))
				-- estuary flare at mouths in water
				if mouthInWater then
					local Lf = clamp(6 * w, 600, 3000)
					local u = clamp(p.s / Lf, 0, 1)
					w = w * (1 + (flareF - 1) * (1 - u) * (1 - u))
				end
				-- bulge at confluences
				for _, ch in ipairs(r.children) do
					local dc = abs(c - ch.idx)
					if dc < 0.3 then w = w * (1 + 0.18 * (1 - dc / 0.3)) end
				end
				local d = depthAt(c)
				if parentDepth and p.s < 600 then d = lerp(parentDepth, d, p.s / 600) end
				pts[k] = { p.x, p.y }
				wl[k], wr[k], dep[k] = w, w, d
			end
			-- bends: widen the outer bank (curvature from the final path)
			for k = 2, #pts - 1 do
				local a1 = atan2(pts[k][2] - pts[k - 1][2], pts[k][1] - pts[k - 1][1])
				local a2 = atan2(pts[k + 1][2] - pts[k][2], pts[k + 1][1] - pts[k][1])
				local da = a2 - a1
				while da > PI do da = da - 2 * PI end
				while da < -PI do da = da + 2 * PI end
				local ds = sqrt((pts[k + 1][1] - pts[k - 1][1]) ^ 2 + (pts[k + 1][2] - pts[k - 1][2]) ^ 2) * 0.5
				local kappa = (ds > 0) and da / ds or 0
				local f = math.min(0.45, 0.6 * abs(kappa) * (wl[k] + wr[k]))
				if kappa > 0 then wr[k] = wr[k] * (1 + f) else wl[k] = wl[k] * (1 + f) end
			end
			-- remember depth at junction indices for children
			r.depthAtJunction = {}
			for _, ch in ipairs(r.children) do r.depthAtJunction[ch.idx] = depthAt(ch.idx) end
			emit(pts, wl, wr, dep)

			-- deltas: distributaries from a trunk point a few km inland back to the water.
			-- Each arm is a cubic Bezier leaving the trunk tangentially, with a small irregular
			-- wiggle; arms may bifurcate once more half way (successive splitting, as in real deltas).
			if mouthInWater and r.order == 0 and r.Q[1] >= 15 and math.random() < cfg.deltaChance then
				local Dd = randf(1800, 3800)
				local kD = 1
				local acc = 0
				for k = 2, #pts do
					acc = acc + sqrt((pts[k][1] - pts[k - 1][1]) ^ 2 + (pts[k][2] - pts[k - 1][2]) ^ 2)
					if acc >= Dd then kD = k; break end
				end
				if kD > 2 then
					local function makeArm(hx, hy, hdir, wHead, dHead, depthEnd, spread, level)
						local ang = hdir + spread
						local Lm = randf(0.9, 1.4) * Dd * (level == 1 and 1 or 0.6)
						local ex, ey = hx + Lm * cos(ang), hy + Lm * sin(ang)
						local ok = false
						for _ = 1, 4 do
							if water(ex, ey) > 0.5 then ok = true; break end
							Lm = Lm * 1.2
							ex, ey = hx + Lm * cos(ang), hy + Lm * sin(ang)
						end
						if not ok then return end
						-- Bezier control points: leave the head along hdir, arrive along ang
						local c1x, c1y = hx + 0.35 * Lm * cos(hdir), hy + 0.35 * Lm * sin(hdir)
						local c2x, c2y = ex - 0.35 * Lm * cos(ang), ey - 0.35 * Lm * sin(ang)
						local steps = math.max(6, floor(Lm / 45))
						local wig = makeNoise1(randf(250, 500))
						local wigAmp = randf(0.02, 0.05) * Lm
						local curve = {}
						for s = 0, steps do
							local t = s / steps
							local u = 1 - t
							local bx = u*u*u*hx + 3*u*u*t*c1x + 3*u*t*t*c2x + t*t*t*ex
							local by = u*u*u*hy + 3*u*u*t*c1y + 3*u*t*t*c2y + t*t*t*ey
							curve[#curve + 1] = { bx, by, t }
						end
						-- lateral wiggle (zero at both ends)
						for k2 = 2, #curve - 1 do
							local p0, p2 = curve[k2 - 1], curve[k2 + 1]
							local tx, ty = p2[1] - p0[1], p2[2] - p0[2]
							local tl = sqrt(tx * tx + ty * ty)
							if tl > 0 then
								local t = curve[k2][3]
								local off = (wig(t * Lm) - 0.5) * 2 * wigAmp * sin(PI * t)
								curve[k2][1] = curve[k2][1] - ty / tl * off
								curve[k2][2] = curve[k2][2] + tx / tl * off
							end
						end
						-- emit from the water end (mouth, widest) up to the head (pointy tip)
						local armPts, awl, awr, adep = {}, {}, {}, {}
						for k2 = #curve, 1, -1 do
							local t = curve[k2][3]
							armPts[#armPts + 1] = { curve[k2][1], curve[k2][2] }
							local w = wHead * lerp(0.55, 0.65, t) * (1 + 0.6 * t ^ 3)
							awl[#awl + 1], awr[#awr + 1] = w, w
							adep[#adep + 1] = lerp(depthEnd, dHead, t) * 0.85
						end
						emit(armPts, awl, awr, adep)
						-- secondary bifurcation half way
						if level == 1 and math.random() < 0.5 then
							local mid = curve[floor(#curve / 2)]
							local nxt = curve[floor(#curve / 2) + 1]
							local mdir = atan2(nxt[2] - mid[2], nxt[1] - mid[1])
							local side2 = (math.random() < 0.5) and 1 or -1
							makeArm(mid[1], mid[2], mdir, wHead * 0.5, dHead * 0.85, depthEnd,
								side2 * randf(0.3, 0.7), 2)
						end
					end
					local hx, hy = pts[kD][1], pts[kD][2]
					-- downstream direction at the head (toward the mouth = decreasing index)
					local hdir = atan2(pts[kD - 2][2] - hy, pts[kD - 2][1] - hx)
					local nArms = math.random(2, 3)
					for arm = 1, nArms do
						local side = (arm % 2 == 0) and 1 or -1
						makeArm(hx, hy, hdir, wl[kD], dep[kD], dep[1], side * randf(0.35, 0.9), 1)
					end
				end
			end
		end
	end

	-- 4e. assemble vanilla output format
	local P, Wd, D, DT, T, WT = {}, {}, {}, {}, {}, {}
	local function appendRiver(r)
		local m = #r.points
		if m < 2 then return end
		if #P > 0 then
			-- vanilla separator: repeat the last element of every stream before the next river
			P[#P + 1] = P[#P]; Wd[#Wd + 1] = Wd[#Wd]; D[#D + 1] = D[#D]
			T[#T + 1] = T[#T]; WT[#WT + 1] = WT[#WT]
		end
		for k = 1, m do
			local a = r.points[math.max(1, k - 1)]
			local b = r.points[math.min(m, k + 1)]
			local tx, ty = b[1] - a[1], b[2] - a[2]
			local tl = sqrt(tx * tx + ty * ty)
			local segLen = tl / ((k == 1 or k == m) and 1 or 2)
			if tl > 0 then tx, ty = tx / tl * segLen, ty / tl * segLen end
			P[#P + 1] = { r.points[k][1], r.points[k][2] }
			T[#T + 1] = { tx, ty }
			if k == m then
				-- pointy tip (vanilla): zero width, strong negative shore tangent
				Wd[#Wd + 1] = { 0, 0 }
				WT[#WT + 1] = { -1000, -1000 }
			else
				Wd[#Wd + 1] = { r.wl[k], r.wr[k] }
				WT[#WT + 1] = { 0, 0 }
			end
			D[#D + 1] = { r.d[k], 0 }
		end
	end
	for _, r in ipairs(outRivers) do appendRiver(r) end
	logv(string.format("custom_terrain_rivers: %d polylines, %d points", #outRivers, #P))
	-- machine-readable summary for the project's log analyzer (log.verbose is not written to
	-- stdout.txt for generator scripts, so use message/warning; never fail on logging)
	pcall(function()
		local trunks, total, maxW, greatEnd = 0, 0, 0, -1
		for _, r in ipairs(ctx.rivers) do if r.order == 0 then trunks = trunks + 1 end end
		for _, r in ipairs(outRivers) do
			for k = 2, #r.points do
				total = total + sqrt((r.points[k][1] - r.points[k - 1][1]) ^ 2 + (r.points[k][2] - r.points[k - 1][2]) ^ 2)
			end
			for k = 1, #r.wl do maxW = math.max(maxW, r.wl[k] + r.wr[k]) end
		end
		for _, r in ipairs(ctx.rivers) do
			if r.great then greatEnd = cfg.coastT(r.pts[#r.pts].x, r.pts[#r.pts].y) end
		end
		local line = string.format('CT_RIVERS {"rivers":%d,"trunks":%d,"polylines":%d,"points":%d,'
			.. '"total_km":%.2f,"max_width_m":%.1f,"great_end_t":%.3f,"amount":%.3f,"meander":%.3f,'
			.. '"trunk_width":%.3f,"tributary_p":%.3f,"deltas":%.3f,"clock":%.3f}',
			#ctx.rivers, trunks, #outRivers, #P, total / 1000, maxW, greatEnd, cfg.amount, cfg.meander,
			cfg.trunkWidth, cfg.baseProbability, cfg.deltaChance, (os and os.clock) and os.clock() or -1)
		if log and log.message then pcall(log.message, line) end
		if log and log.warning then pcall(log.warning, line) end
		if print then pcall(print, line) end
	end)

	return {
		{ 3, P },
		{ 3, Wd },
		{ 3, D },
		{ 3, T },
		{ 3, WT },
	}
end

return {
	riverPoints = {
		applyFn = applyFn,
	},
}
end
