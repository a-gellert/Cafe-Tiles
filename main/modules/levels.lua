-- Level parameters and procedural board layouts.
-- Board positions are in half-cell units: a tile at (x, y) covers [x, x+2) x [y, y+2),
-- y grows downward, z = 0 is the bottom layer. Upper layers are shifted by half a tile,
-- like mahjong stacks.
local config = require "main.modules.config"
local rng_mod = require "main.modules.rng"

local M = {}

M.MAX_COLS = 7
M.MAX_ROWS = 6
M.MAX_TRIPLES = 36
M.MAX_TYPES = 12

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- Hand-tuned openers, then a sawtooth curve: every block of 5 levels climbs,
-- the 5th level is "hard", the next one is a breather.
local OPENERS = {
	{ types = 3, triples = 6, layers = 2, open = 1, items = { 1, 1 }, patience = 0 },
	{ types = 4, triples = 9, layers = 2, open = 1, items = { 1, 1 }, patience = 0 },
	{ types = 5, triples = 12, layers = 3, open = 2, items = { 1, 2 }, patience = 0 },
}

function M.get(n)
	local p
	local o = OPENERS[n]
	if o then
		p = {
			types = o.types, triples = o.triples, layers = o.layers, open = o.open,
			items_min = o.items[1], items_max = o.items[2], patience_per_item = o.patience,
		}
	else
		local step = (n - 1) % 5
		local hard = step == 4
		local triples = 10 + math.floor((n - 1) * 0.9)
		if hard then triples = triples + 4 end
		if step == 0 then triples = triples - 3 end
		p = {
			-- a new dish every 5 levels, 3 open triples on hard levels from 10 and everywhere from 25:
			-- casual players (tools/sim_casual.lua) no longer hit a wall around level 13
			types = clamp(5 + math.floor((n - 1) / 5), 5, math.min(M.MAX_TYPES, #config.FOOD)),
			triples = clamp(triples, 10, M.MAX_TRIPLES),
			layers = clamp(2 + math.floor((n + 2) / 4), 3, 7),
			open = (hard and n >= 10 or n >= 25) and 3 or 2,
			items_min = 1,
			items_max = n < 10 and 2 or 3,
			-- the tip meter: guests never leave, a slow player only gets smaller tips
			patience_per_item = n < config.TIP_METER_LEVEL and 0 or math.max(34, 56 - n * 0.4),
			hard = hard,
		}
	end
	p.level = n
	p.seed = 7919 * n + 104729
	p.types = math.min(p.types, p.triples)
	return p
end

-- Food index that appears for the first time on this level (or nil)
function M.new_food(n)
	if n <= 1 then return nil end
	local now, before = M.get(n).types, M.get(n - 1).types
	if now > before then return now end
	return nil
end

-- ---------------------------------------------------------------- layout

-- Mask styles are mirror-symmetric around the vertical axis.
local function mask_fn(style, c, r, rng)
	local ci, cj = (c - 1) / 2, (r - 1) / 2
	if style == "full" then
		return function() return true end
	elseif style == "oval" then
		return function(i, j)
			local dx, dy = (i - ci) / (c / 2), (j - cj) / (r / 2)
			return dx * dx + dy * dy <= 1.2
		end
	elseif style == "diamond" then
		return function(i, j) return math.abs(i - ci) / (c / 2) + math.abs(j - cj) / (r / 2) <= 1.15 end
	elseif style == "frame" then
		return function(i, j) return i == 0 or j == 0 or i == c - 1 or j == r - 1 end
	elseif style == "columns" then
		return function(i) return math.min(i, c - 1 - i) % 2 == 0 end
	elseif style == "rows" then
		return function(_, j) return math.min(j, r - 1 - j) % 2 == 0 end
	elseif style == "checker" then
		return function(i, j) return (math.min(i, c - 1 - i) + j) % 2 == 0 end
	elseif style == "cross" then
		return function(i, j) return math.abs(i - ci) <= c * 0.2 or math.abs(j - cj) <= r * 0.2 end
	end
	local cells = {}
	for j = 0, r - 1 do
		for i = 0, math.floor((c - 1) / 2) do
			cells[j * 16 + i] = rng:float() < 0.72
		end
	end
	return function(i, j) return cells[j * 16 + math.min(i, c - 1 - i)] end
end

local BASE_STYLES = { "full", "full", "oval", "diamond", "random", "columns", "cross" }
local TOP_STYLES = { "full", "oval", "diamond", "frame", "columns", "rows", "checker", "cross", "random" }

local function build_layers(layers, rng, cols, rows)
	local pos = {}
	local c, r, ox, oy = cols, rows, 0, 0
	for z = 0, layers - 1 do
		local style = rng:pick(z == 0 and BASE_STYLES or TOP_STYLES)
		local mask = mask_fn(style, c, r, rng)
		for j = 0, r - 1 do
			for i = 0, c - 1 do
				if mask(i, j) then
					pos[#pos + 1] = { x = ox + 2 * i, y = oy + 2 * j, z = z }
				end
			end
		end
		-- geometry of the next layer: pyramid, slide or tower
		local mode = rng:int(1, 10)
		if mode <= 5 and c > 2 and r > 2 then
			c, r, ox, oy = c - 1, r - 1, ox + 1, oy + 1
		elseif mode <= 8 and c > 2 then
			c, ox = c - 1, ox + 1
		elseif mode == 9 and r > 2 then
			r, oy = r - 1, oy + 1
		end
	end
	return pos
end

-- Remove tiles from the top down, in mirrored pairs where possible.
local function trim(pos, excess, cols, rng)
	local axis = 2 * (cols - 1)
	while excess > 0 do
		local top = -1
		for _, p in ipairs(pos) do top = math.max(top, p.z) end
		local layer = {}
		for i, p in ipairs(pos) do
			if p.z == top then layer[#layer + 1] = i end
		end
		local pairs_, singles = {}, {}
		local by_key = {}
		for _, i in ipairs(layer) do by_key[pos[i].x .. ":" .. pos[i].y] = i end
		for _, i in ipairs(layer) do
			local p = pos[i]
			local mx = axis - p.x
			if mx == p.x then
				singles[#singles + 1] = { i }
			elseif p.x < mx then
				local m = by_key[mx .. ":" .. p.y]
				if m then pairs_[#pairs_ + 1] = { i, m } else singles[#singles + 1] = { i } end
			elseif not by_key[mx .. ":" .. p.y] then
				singles[#singles + 1] = { i }
			end
		end
		local victim
		if excess >= 2 and #pairs_ > 0 then
			victim = rng:pick(pairs_)
		elseif #singles > 0 then
			victim = rng:pick(singles)
		else
			victim = { rng:pick(pairs_)[1] }
		end
		table.sort(victim, function(a, b) return a > b end)
		for _, i in ipairs(victim) do table.remove(pos, i) end
		excess = excess - #victim
	end
end

local function count_free(pos)
	local n = 0
	for _, a in ipairs(pos) do
		local free = true
		for _, c in ipairs(pos) do
			if c.z > a.z and math.abs(c.x - a.x) < 2 and math.abs(c.y - a.y) < 2 then
				free = false
				break
			end
		end
		if free then n = n + 1 end
	end
	return n
end

-- Returns positions (exactly triples * 3 of them when the layout allows) and the base grid size.
-- Layouts with too few open tiles at the start feel unfair, so they are re-rolled.
function M.layout(p)
	local rng = rng_mod.new(p.seed)
	local target = p.triples * 3
	local min_free = math.max(6, math.ceil(target * 0.14))
	local area = target / math.max(1.5, p.layers * 0.55)
	local cols = clamp(math.floor(math.sqrt(area * 1.15) + 0.5), 3, M.MAX_COLS)
	local rows = clamp(math.ceil(area / cols), 3, M.MAX_ROWS)
	local best, best_cols, best_rows = nil, cols, rows
	local fit, fit_cols, fit_rows, fit_free = nil, cols, rows, -1
	for attempt = 1, 60 do
		local pos = build_layers(p.layers, rng, cols, rows)
		if #pos >= target then
			trim(pos, #pos - target, cols, rng)
			local free = count_free(pos)
			if free >= min_free then return pos, cols, rows end
			if free > fit_free then fit, fit_cols, fit_rows, fit_free = pos, cols, rows, free end
		elseif not best or #pos > #best then
			best, best_cols, best_rows = pos, cols, rows
		end
		if attempt % 4 == 0 then
			if cols <= rows and cols < M.MAX_COLS then cols = cols + 1
			elseif rows < M.MAX_ROWS then rows = rows + 1
			elseif cols < M.MAX_COLS then cols = cols + 1 end
		end
	end
	if fit then return fit, fit_cols, fit_rows end
	-- Could not reach the target: keep the biggest layout, rounded down to whole triples.
	trim(best, #best % 3, best_cols, rng)
	return best, best_cols, best_rows
end

-- Number of tiles of each food index (1..types) for `triples` triples.
function M.type_counts(p, triples, rng)
	local counts = {}
	local base = math.floor(triples / p.types)
	local extra = triples - base * p.types
	local order = {}
	for t = 1, p.types do
		counts[t] = base * 3
		order[t] = t
	end
	rng:shuffle(order)
	for k = 1, extra do counts[order[k]] = counts[order[k]] + 3 end
	return counts
end

return M
