-- Layered tile board: coverage graph, free tiles and solvable type dealing.
-- A tile is covered by every tile on a higher layer whose footprint overlaps it.
local M = {}

function M.new(positions)
	local b = { tiles = {}, count = 0 }
	for i, p in ipairs(positions) do
		b.tiles[i] = { id = i, x = p.x, y = p.y, z = p.z, type = 0, where = "board", over = {}, under = {}, blockers = 0 }
	end
	for i, a in ipairs(b.tiles) do
		for j, c in ipairs(b.tiles) do
			if c.z > a.z and math.abs(c.x - a.x) < 2 and math.abs(c.y - a.y) < 2 then
				a.over[#a.over + 1] = j
				c.under[#c.under + 1] = i
			end
		end
	end
	for _, a in ipairs(b.tiles) do a.blockers = #a.over end
	b.count = #b.tiles
	return b
end

function M.is_free(b, id)
	local t = b.tiles[id]
	return t.where == "board" and t.blockers == 0
end

-- Takes a tile off the board. Returns the ids of tiles that became free.
function M.lift(b, id, where)
	local t = b.tiles[id]
	t.where = where
	b.count = b.count - 1
	local freed = {}
	for _, u in ipairs(t.under) do
		local ut = b.tiles[u]
		ut.blockers = ut.blockers - 1
		if ut.blockers == 0 and ut.where == "board" then freed[#freed + 1] = u end
	end
	return freed
end

-- Puts a tile back (undo). Returns the ids of tiles that became blocked.
function M.put_back(b, id)
	local t = b.tiles[id]
	t.where = "board"
	b.count = b.count + 1
	local blocked = {}
	for _, u in ipairs(t.under) do
		local ut = b.tiles[u]
		ut.blockers = ut.blockers + 1
		if ut.blockers == 1 and ut.where == "board" then blocked[#blocked + 1] = u end
	end
	return blocked
end

function M.board_ids(b)
	local ids = {}
	for _, t in ipairs(b.tiles) do
		if t.where == "board" then ids[#ids + 1] = t.id end
	end
	return ids
end

function M.free_ids(b)
	local ids = {}
	for _, t in ipairs(b.tiles) do
		if t.where == "board" and t.blockers == 0 then ids[#ids + 1] = t.id end
	end
	return ids
end

-- Deals food types onto the board tiles `ids` by simulating a forward play:
-- free tiles are taken one by one and assigned to at most `max_open` unfinished
-- triples. That play keeps at most 2 * max_open tiles in the tray, so the deal is
-- always solvable when max_open <= 3.
--   counts[type]  tiles of each type to place (indexed 1..n_types)
--   open          unfinished triples already in hand: { {type=, need=} }
--   greedy        finish the nearest-to-complete triple first (used by shuffle)
function M.deal(b, ids, counts, n_types, open, max_open, rng, greedy)
	local present, blockers, free = {}, {}, {}
	for _, id in ipairs(ids) do present[id] = true end
	for _, id in ipairs(ids) do
		local n = 0
		for _, o in ipairs(b.tiles[id].over) do
			if present[o] then n = n + 1 end
		end
		blockers[id] = n
		if n == 0 then free[#free + 1] = id end
	end

	local groups = {}
	local remaining = {}
	for t = 1, n_types do remaining[t] = counts[t] or 0 end
	for _, g in ipairs(open or {}) do
		groups[#groups + 1] = { type = g.type, need = g.need }
		remaining[g.type] = remaining[g.type] - g.need
	end
	local pool = {}
	for t = 1, n_types do
		for _ = 1, math.floor(remaining[t] / 3) do pool[#pool + 1] = t end
	end
	rng:shuffle(pool)

	local left = #ids
	while left > 0 and #free > 0 do
		local fi = rng:int(1, #free)
		local id = free[fi]
		free[fi] = free[#free]
		free[#free] = nil

		local g
		if #pool > 0 and (#groups == 0 or (#groups < max_open and rng:float() < 0.5)) then
			g = { type = table.remove(pool), need = 3 }
			groups[#groups + 1] = g
		elseif #groups > 0 then
			if greedy then
				g = groups[1]
				for _, cand in ipairs(groups) do
					if cand.need < g.need then g = cand end
				end
			else
				g = groups[rng:int(1, #groups)]
			end
		else
			g = { type = 1, need = 3 } -- inconsistent counts: never expected
			groups[#groups + 1] = g
		end

		b.tiles[id].type = g.type
		g.need = g.need - 1
		if g.need == 0 then
			for k, cand in ipairs(groups) do
				if cand == g then table.remove(groups, k) break end
			end
		end
		left = left - 1
		for _, u in ipairs(b.tiles[id].under) do
			if present[u] then
				blockers[u] = blockers[u] - 1
				if blockers[u] == 0 then free[#free + 1] = u end
			end
		end
	end
end

return M
