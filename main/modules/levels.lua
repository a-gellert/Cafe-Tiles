-- Level parameters and board layouts.
-- Board positions are in half-cell units: a tile at (x, y) covers [x, x+2) x [y, y+2),
-- y grows downward, z = 0 is the bottom layer. Upper layers are shifted by half a tile,
-- like mahjong stacks.
--
-- Levels 1..51 are based on Brain Storm level0.json (Ids 0..50).
-- Levels 52..151 are +100 similar handcrafted/procedural thematic levels (Ids 51..150).
local config = require "main.modules.config"
local rng_mod = require "main.modules.rng"
local level_data = require "main.modules.level_data"

local M = {}

M.MAX_COLS = 8
M.MAX_ROWS = 8
M.MAX_TRIPLES = 72
M.MAX_TYPES = 12
M.TOTAL_LEVELS = level_data.COUNT

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- Hand-tuned openers for onboarding
local OPENERS = {
	[1] = { types = 3, open = 1, items = { 1, 1 }, patience = 0 },
	[2] = { types = 4, open = 1, items = { 1, 1 }, patience = 0 },
	[3] = { types = 5, open = 2, items = { 1, 2 }, patience = 0 },
	[4] = { types = 5, open = 2, items = { 1, 2 }, patience = 0 },
	[5] = { types = 5, open = 2, items = { 1, 2 }, patience = 0 },
}

function M.get(n)
	local idx = ((n - 1) % level_data.COUNT) + 1
	local def = level_data.LEVELS[idx]
	local triples = def.triples

	local p
	local o = OPENERS[n]
	if o then
		p = {
			types = math.min(o.types, triples),
			triples = triples,
			layers = def.layers,
			open = o.open,
			items_min = o.items[1],
			items_max = o.items[2],
			patience_per_item = o.patience,
		}
	else
		local step = (n - 1) % 5
		local hard = step == 4
		local types = clamp(5 + math.floor((n - 1) / 5), 5, math.min(M.MAX_TYPES, #config.FOOD))
		p = {
			types = math.min(types, triples),
			triples = triples,
			layers = def.layers,
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
	return p
end

-- Food index that appears for the first time on this level (or nil)
function M.new_food(n)
	if n <= 1 then return nil end
	local now, before = M.get(n).types, M.get(n - 1).types
	if now > before then return now end
	return nil
end

-- Returns precomputed positions and grid size for the level.
function M.layout(p)
	local idx = ((p.level - 1) % level_data.COUNT) + 1
	local def = level_data.LEVELS[idx]
	return def.positions, def.cols, def.rows
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
