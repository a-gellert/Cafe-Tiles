-- One level: board, tray (7 cells), holding shelf, customers and their orders.
-- Pure logic without Defold APIs (also runs in tools/sim.lua). Actions push events
-- into s.events; the GUI drains them and plays the animations.
--
-- Rules
--   * a free tile goes to the tray, next to tiles of the same food;
--   * three of a kind leave the tray: they serve a waiting order item of that food
--     (most impatient customer first) or, when nobody ordered it, go to the bin (waste);
--   * 7 tiles in the tray without a match = kitchen jam (second chance: 3 tiles go to the shelf);
--   * orders are only made from unreserved triples, so every order can be served;
--   * the level is won when board, tray and shelf are empty.
local config = require "main.modules.config"
local levels = require "main.modules.levels"
local board_mod = require "main.modules.board"
local rng_mod = require "main.modules.rng"

local M = {}

local function push(s, e)
	s.events[#s.events + 1] = e
end

local function round(v)
	return math.floor(v + 0.5)
end

function M.new(level, opts)
	opts = opts or {}
	local p = levels.get(level)
	local positions, cols, rows = levels.layout(p)
	local b = board_mod.new(positions)
	local deal_rng = rng_mod.new(p.seed + 1)
	local counts = levels.type_counts(p, #positions / 3, deal_rng)
	board_mod.deal(b, board_mod.board_ids(b), counts, p.types, nil, p.open, deal_rng, false)

	local s = {
		level = level,
		params = p,
		rng = rng_mod.new(p.seed * 3 + 11),
		board = b,
		cols = cols,
		rows = rows,
		slot = {},
		shelf = {},
		history = {},
		left = {},        -- unmatched tiles per food (board + tray + shelf)
		reserved = {},    -- unserved order items per food
		seats = {},
		seat_timer = {},
		events = {},
		status = "play",  -- play | jam | won
		running = false,  -- patience ticks only after the first tap
		coins = 0,
		served = 0,
		angry = 0,
		waste = 0,
		dishes = 0,
		chances = config.SECOND_CHANCES,
		paid_chances = config.PAID_CHANCES,
		vips = 0,          -- VIP guests spawned this level
		vip_served = 0,
		food_done = {},    -- served triples per food (missions)
		mult = opts.mult or 1,
		streak = opts.streak or 0,
		total = #positions,
		next_customer = 1,
	}
	for t = 1, p.types do
		s.left[t] = counts[t] or 0
		s.reserved[t] = 0
	end
	for i = 1, config.SEATS do
		s.seats[i] = false
		s.seat_timer[i] = 0.15 + (i - 1) * config.FIRST_ARRIVE_STAGGER
	end
	return s
end

function M.tile(s, id)
	return s.board.tiles[id]
end

function M.remaining(s)
	return s.board.count + #s.slot + #s.shelf
end

-- ---------------------------------------------------------------- customers

local function available(s, t)
	return math.floor(s.left[t] / 3) - s.reserved[t]
end

-- tiles of a food the player can take right now (free on board, tray, shelf)
local function reach_counts(s)
	local r = {}
	for _, t in ipairs(s.board.tiles) do
		if (t.where == "board" and t.blockers == 0) or t.where == "slot" or t.where == "shelf" then
			r[t.type] = (r[t.type] or 0) + 1
		end
	end
	return r
end

local function spawn(s, seat)
	local p = s.params
	local reach = reach_counts(s)
	local cand = {}
	for t = 1, p.types do
		local a = available(s, t)
		if a > 0 then
			local r = reach[t] or 0
			cand[#cand + 1] = { type = t, w = a + (r >= 3 and 8 or (r > 0 and 3 or 0)) }
		end
	end
	if #cand == 0 then return false end

	local vip = p.level >= config.VIP_MIN_LEVEL and s.vips < (p.level >= 15 and 2 or 1)
		and s.rng:float() < config.VIP_CHANCE
	local k = math.min(s.rng:int(p.items_min, p.items_max), #cand)
	if vip then k = math.min(math.max(k, 2), #cand) end
	local items = {}
	for _ = 1, k do
		local total = 0
		for _, c in ipairs(cand) do total = total + c.w end
		local roll = s.rng:float() * total
		local pick = #cand
		for ci, c in ipairs(cand) do
			roll = roll - c.w
			if roll < 0 then pick = ci break end
		end
		local t = table.remove(cand, pick).type
		items[#items + 1] = { type = t, done = false }
		s.reserved[t] = s.reserved[t] + 1
	end

	local used = {}
	for _, c in ipairs(s.seats) do
		if c then used[c.kind] = true end
	end
	local kind = s.rng:int(1, #config.CUSTOMERS)
	for _ = 1, #config.CUSTOMERS do
		if not used[kind] then break end
		kind = kind % #config.CUSTOMERS + 1
	end

	local patience = 0
	if p.patience_per_item > 0 then
		patience = 15 + p.patience_per_item * #items
		if vip then patience = math.floor(patience * config.VIP_PATIENCE) end
	end
	if vip then s.vips = s.vips + 1 end
	s.seats[seat] = {
		id = s.next_customer,
		kind = kind,
		vip = vip,
		items = items,
		patience = patience,
		patience_max = patience,
	}
	s.next_customer = s.next_customer + 1
	push(s, { e = "arrive", seat = seat, vip = vip })
	return true
end

local function leave(s, seat, happy)
	local c = s.seats[seat]
	local tip = 0
	if happy then
		local ratio = c.patience_max > 0 and math.max(0, c.patience / c.patience_max) or 1
		tip = math.max(1, round(config.TIP_MAX * ratio * s.mult * (c.vip and config.VIP_TIP or 1)))
		s.coins = s.coins + tip
		s.served = s.served + 1
		if c.vip then s.vip_served = s.vip_served + 1 end
	else
		for _, it in ipairs(c.items) do
			if not it.done then s.reserved[it.type] = s.reserved[it.type] - 1 end
		end
		s.angry = s.angry + 1
	end
	s.seats[seat] = false
	s.seat_timer[seat] = config.ARRIVE_DELAY
	push(s, { e = "leave", seat = seat, happy = happy, coins = tip, kind = c.kind, vip = c.vip })
end

local function serve_item(s, seat, k, ids, rush)
	local c = s.seats[seat]
	local it = c.items[k]
	it.done = true
	s.reserved[it.type] = s.reserved[it.type] - 1
	local pay = round(config.DISH_PRICE * s.mult * (c.vip and config.VIP_PAY or 1))
	s.coins = s.coins + pay
	s.dishes = s.dishes + 1
	s.food_done[it.type] = (s.food_done[it.type] or 0) + 1
	push(s, { e = "serve", ids = ids, type = it.type, seat = seat, item = k, coins = pay, rush = rush })
	for _, other in ipairs(c.items) do
		if not other.done then return end
	end
	leave(s, seat, true)
end

local function most_urgent_seat(s, food)
	local best, best_item, best_ratio
	for i, c in ipairs(s.seats) do
		if c then
			for k, it in ipairs(c.items) do
				if not it.done and (food == nil or it.type == food) then
					local ratio = c.patience_max > 0 and c.patience / c.patience_max or 1
					if not best_ratio or ratio < best_ratio then
						best, best_item, best_ratio = i, k, ratio
					end
					break
				end
			end
		end
	end
	return best, best_item
end

local function resolve_triple(s, food, ids)
	s.left[food] = s.left[food] - 3
	local seat, k = most_urgent_seat(s, food)
	if seat then
		serve_item(s, seat, k, ids, false)
	else
		s.waste = s.waste + 1
		push(s, { e = "waste", ids = ids, type = food })
	end
end

-- ---------------------------------------------------------------- tray

local function purge_history(s, ids)
	local gone = {}
	for _, id in ipairs(ids) do gone[id] = true end
	for i = #s.history, 1, -1 do
		if gone[s.history[i].id] then table.remove(s.history, i) end
	end
end

local function remove_from(list, id)
	for i, v in ipairs(list) do
		if v == id then table.remove(list, i) return i end
	end
end

local function insert_into_slot(s, id)
	local food = s.board.tiles[id].type
	local at = #s.slot + 1
	for i = #s.slot, 1, -1 do
		if s.board.tiles[s.slot[i]].type == food then at = i + 1 break end
	end
	table.insert(s.slot, at, id)
	s.board.tiles[id].where = "slot"
	return at
end

local function check_end(s)
	if s.status ~= "play" then return end
	if M.remaining(s) == 0 then
		s.status = "won"
		push(s, { e = "won" })
	elseif #s.slot >= config.SLOT_COUNT then
		s.status = "jam"
		push(s, { e = "jam" })
	end
end

local function match_tray(s, food)
	local same = {}
	for _, sid in ipairs(s.slot) do
		if s.board.tiles[sid].type == food then same[#same + 1] = sid end
	end
	if #same < 3 then return end
	for _, sid in ipairs(same) do
		remove_from(s.slot, sid)
		s.board.tiles[sid].where = "gone"
	end
	purge_history(s, same)
	resolve_triple(s, food, same)
end

function M.tap(s, id)
	if s.status ~= "play" then return false end
	local t = s.board.tiles[id]
	if not t or #s.slot >= config.SLOT_COUNT then return false end
	local from = t.where
	if from == "board" then
		if t.blockers > 0 then
			push(s, { e = "blocked", id = id })
			return false
		end
		local freed = board_mod.lift(s.board, id, "slot")
		if #freed > 0 then push(s, { e = "free", ids = freed }) end
	elseif from == "shelf" then
		remove_from(s.shelf, id)
		push(s, { e = "shelf" })
	else
		return false
	end
	s.running = true
	local at = insert_into_slot(s, id)
	push(s, { e = "to_slot", id = id, from = from, index = at })
	s.history[#s.history + 1] = { id = id, from = from }
	match_tray(s, t.type)
	push(s, { e = "slot" })
	check_end(s)
	return true
end

-- ---------------------------------------------------------------- boosters

function M.can_undo(s)
	return s.status == "play" and #s.history > 0
end

function M.undo(s)
	if not M.can_undo(s) then return false end
	local h = table.remove(s.history)
	remove_from(s.slot, h.id)
	if h.from == "board" then
		local blocked = board_mod.put_back(s.board, h.id)
		push(s, { e = "undo", id = h.id, to = "board" })
		if #blocked > 0 then push(s, { e = "block", ids = blocked }) end
	else
		s.board.tiles[h.id].where = "shelf"
		s.shelf[#s.shelf + 1] = h.id
		push(s, { e = "undo", id = h.id, to = "shelf" })
		push(s, { e = "shelf" })
	end
	push(s, { e = "slot" })
	return true
end

function M.can_shuffle(s)
	return s.status == "play" and s.board.count >= 2
end

-- Re-deals the foods of the board tiles, keeping the counts and a solvable order
-- that finishes the triples already in hand first.
function M.shuffle(s)
	if not M.can_shuffle(s) then return false end
	local ids = board_mod.board_ids(s.board)
	local counts, in_hand = {}, {}
	for t = 1, s.params.types do
		counts[t] = 0
		in_hand[t] = 0
	end
	for _, id in ipairs(ids) do
		local t = s.board.tiles[id].type
		counts[t] = counts[t] + 1
	end
	for _, list in ipairs({ s.slot, s.shelf }) do
		for _, id in ipairs(list) do
			local t = s.board.tiles[id].type
			in_hand[t] = in_hand[t] + 1
		end
	end
	local open = {}
	for t = 1, s.params.types do
		if in_hand[t] % 3 ~= 0 then open[#open + 1] = { type = t, need = 3 - in_hand[t] % 3 } end
	end
	board_mod.deal(s.board, ids, counts, s.params.types, open, math.max(3, #open), s.rng, true)
	push(s, { e = "shuffle", ids = ids })
	return true
end

function M.can_rush(s)
	return s.status == "play" and (most_urgent_seat(s, nil)) ~= nil
end

-- Takes three tiles of a food from anywhere: tray, shelf, free tiles, then the highest covered ones.
local function take_three(s, food)
	local picked = {}
	local function grab(id)
		if #picked < 3 then picked[#picked + 1] = id end
	end
	for _, id in ipairs(s.slot) do
		if s.board.tiles[id].type == food then grab(id) end
	end
	for _, id in ipairs(s.shelf) do
		if s.board.tiles[id].type == food then grab(id) end
	end
	local board_tiles = {}
	for _, t in ipairs(s.board.tiles) do
		if t.where == "board" and t.type == food then board_tiles[#board_tiles + 1] = t end
	end
	table.sort(board_tiles, function(a, b)
		if a.blockers ~= b.blockers then return a.blockers < b.blockers end
		if a.z ~= b.z then return a.z > b.z end
		return a.id < b.id
	end)
	for _, t in ipairs(board_tiles) do grab(t.id) end
	return picked
end

-- Rewarded "rush order": the most impatient customer gets the whole order at once.
function M.rush(s)
	if not M.can_rush(s) then return false end
	local seat = most_urgent_seat(s, nil)
	local c = s.seats[seat]
	local shelf_changed = false
	for k, it in ipairs(c.items) do
		if not it.done then
			local ids = take_three(s, it.type)
			for _, id in ipairs(ids) do
				local t = s.board.tiles[id]
				if t.where == "board" then
					local freed = board_mod.lift(s.board, id, "gone")
					if #freed > 0 then push(s, { e = "free", ids = freed }) end
				else
					if t.where == "shelf" then shelf_changed = true end
					remove_from(s.slot, id)
					remove_from(s.shelf, id)
				end
				t.where = "gone"
			end
			purge_history(s, ids)
			s.left[it.type] = s.left[it.type] - 3
			-- serve_item may free the seat after the last item
			local still_here = s.seats[seat] == c
			if still_here then serve_item(s, seat, k, ids, true) end
		end
	end
	if shelf_changed then push(s, { e = "shelf" }) end
	push(s, { e = "slot" })
	s.running = true
	check_end(s)
	return true
end

-- paid = continue for coins (its own counter), otherwise the rewarded chance
function M.can_second_chance(s, paid)
	local left = paid and s.paid_chances or s.chances
	return s.status == "jam" and left > 0 and #s.shelf < config.SHELF_COUNT
end

-- Moves up to 3 tray tiles to the holding shelf, the loneliest foods first.
function M.second_chance(s, paid)
	if not M.can_second_chance(s, paid) then return false end
	local count = {}
	for _, id in ipairs(s.slot) do
		local t = s.board.tiles[id].type
		count[t] = (count[t] or 0) + 1
	end
	local order = {}
	for i, id in ipairs(s.slot) do order[#order + 1] = { id = id, i = i } end
	table.sort(order, function(a, b)
		local ca, cb = count[s.board.tiles[a.id].type], count[s.board.tiles[b.id].type]
		if ca ~= cb then return ca < cb end
		return a.i > b.i
	end)
	local n = math.min(3, config.SHELF_COUNT - #s.shelf, #s.slot)
	local moved = {}
	for k = 1, n do
		local id = order[k].id
		remove_from(s.slot, id)
		s.shelf[#s.shelf + 1] = id
		s.board.tiles[id].where = "shelf"
		moved[#moved + 1] = id
	end
	purge_history(s, moved)
	if paid then s.paid_chances = s.paid_chances - 1 else s.chances = s.chances - 1 end
	s.status = "play"
	push(s, { e = "to_shelf", ids = moved })
	push(s, { e = "shelf" })
	push(s, { e = "slot" })
	return true
end

-- ---------------------------------------------------------------- time

function M.update(s, dt)
	if s.status == "won" then return end
	for i = 1, config.SEATS do
		local c = s.seats[i]
		if c then
			if s.running and s.status == "play" and c.patience_max > 0 then
				c.patience = c.patience - dt
				if c.patience <= 0 then leave(s, i, false) end
			end
		elseif s.status == "play" then
			s.seat_timer[i] = s.seat_timer[i] - dt
			if s.seat_timer[i] <= 0 and not spawn(s, i) then
				s.seat_timer[i] = 0.5
			end
		end
	end
end

-- ---------------------------------------------------------------- helpers

function M.wanted(s)
	local w = {}
	for _, c in ipairs(s.seats) do
		if c then
			for _, it in ipairs(c.items) do
				if not it.done then w[it.type] = true end
			end
		end
	end
	return w
end

-- Best next tap (hint, tutorial hand, autoplay bot).
function M.suggest(s)
	if s.status ~= "play" then return nil end
	local in_tray = {}
	for _, id in ipairs(s.slot) do
		local t = s.board.tiles[id].type
		in_tray[t] = (in_tray[t] or 0) + 1
	end
	local cand, by_type = {}, {}
	for _, t in ipairs(s.board.tiles) do
		if (t.where == "board" and t.blockers == 0) or t.where == "shelf" then
			cand[#cand + 1] = t
			by_type[t.type] = (by_type[t.type] or 0) + 1
		end
	end
	local wanted = M.wanted(s)
	local empty = config.SLOT_COUNT - #s.slot
	local best, best_score
	for _, t in ipairs(cand) do
		local have = in_tray[t.type] or 0
		local reach = have + by_type[t.type]
		local score
		local want = wanted[t.type]
		if have == 2 then
			score = want and 1200 or 800
		elseif reach >= 3 then
			score = 400 + have * 60 + (want and 350 or 0)
			if 3 - have > empty then score = score - 900 end
		else
			score = have * 40 + by_type[t.type] * 10 + (want and 150 or 0)
			if empty <= 3 then score = score - 2000 end
		end
		score = score + t.z * 3 + #t.under * 2
		if t.where == "shelf" then score = score + 5 end
		if not best or score > best_score then best, best_score = t, score end
	end
	return best and best.id
end

function M.result(s)
	-- the bin is part of the game: a few wasted triples still give 3 stars on big levels
	local triples = s.total / 3
	local mistakes = s.waste + 2 * s.angry
	local stars = 1
	if mistakes <= math.floor(triples * 0.1) then
		stars = 3
	elseif mistakes <= math.floor(triples * 0.3) + 1 then
		stars = 2
	end
	local bonus = round((config.LEVEL_BONUS_BASE + config.LEVEL_BONUS_PER_LEVEL * s.level) * stars / 3 * s.mult
		* (s.params.hard and config.HARD_BONUS or 1))
	local new_streak = (s.streak or 0) + 1
	local streak_pct = (new_streak >= 3 and (config.STREAK_BONUS[3] or 0.30))
		or (new_streak == 2 and (config.STREAK_BONUS[2] or 0.15)) or 0
	local streak_bonus = round(bonus * streak_pct)
	local total_bonus = bonus + streak_bonus
	return {
		stars = stars,
		bonus = total_bonus,
		base_bonus = bonus,
		streak = new_streak,
		streak_bonus = streak_bonus,
		earned = s.coins,
		coins = s.coins + total_bonus,
		waste = s.waste,
		angry = s.angry,
		served = s.served,
		vip_served = s.vip_served,
		food_done = s.food_done,
		hard = s.params.hard,
	}
end

return M
