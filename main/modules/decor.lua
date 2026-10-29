-- Cafe decoration: the meta progression. Every bought tier changes the cafe look
-- and raises the cafe rating (+config.DECOR_BONUS coins per tier).
local config = require "main.modules.config"

local M = {}

M.MAX_TIER = 3

M.ITEMS = {
	{ id = "wall", icon = "icon_brush", prices = { 40, 150, 400 } },
	{ id = "counter", icon = "coffee_machine", prices = { 60, 180, 450 } },
	{ id = "flowers", icon = "vase", prices = { 90, 240, 520 } },
	{ id = "lights", icon = "lamp", prices = { 80, 220, 500 } },
	{ id = "plants", icon = "plant_small", prices = { 100, 260, 560 } },
	{ id = "floor", icon = "table", prices = { 120, 300, 620 } },
	{ id = "kitchen", icon = "cake_display", prices = { 150, 350, 700 } },
}

-- Cafe level: one level per LEVEL_STEP bought tiers, each new level pays a reward once
M.LEVEL_STEP = 3
local LEVEL_BOOSTERS = { "undo", "shuffle", "rush" }

function M.item(id)
	for _, it in ipairs(M.ITEMS) do
		if it.id == id then return it end
	end
end

function M.tier(owned, id)
	return (owned and owned[id]) or 0
end

-- price of the next tier or nil when maxed
function M.next_price(owned, id)
	for _, it in ipairs(M.ITEMS) do
		if it.id == id then return it.prices[M.tier(owned, id) + 1] end
	end
end

function M.rating(owned)
	local r = 0
	for _, it in ipairs(M.ITEMS) do r = r + M.tier(owned, it.id) end
	return r
end

function M.coin_mult(owned)
	return 1 + M.rating(owned) * config.DECOR_BONUS
end

-- the cheapest next tier: the goal shown after every level ({ id, price, tier }), nil when all is bought
function M.next_goal(owned)
	local best
	for _, it in ipairs(M.ITEMS) do
		local p = M.next_price(owned, it.id)
		if p and (not best or p < best.price) then best = { id = it.id, price = p, tier = M.tier(owned, it.id) + 1 } end
	end
	return best
end

function M.cheapest(owned)
	local g = M.next_goal(owned)
	return g and g.price
end

function M.max_rating()
	return #M.ITEMS * M.MAX_TIER
end

function M.cafe_level(owned)
	return math.floor(M.rating(owned) / M.LEVEL_STEP) + 1
end

function M.max_level()
	return math.floor(M.max_rating() / M.LEVEL_STEP) + 1
end

-- tiers bought towards the next cafe level, out of LEVEL_STEP (all of them at the top level)
function M.level_progress(owned)
	if M.cafe_level(owned) >= M.max_level() then return M.LEVEL_STEP, M.LEVEL_STEP end
	return M.rating(owned) % M.LEVEL_STEP, M.LEVEL_STEP
end

-- reward for reaching cafe level n (2..max_level)
function M.level_reward(n)
	return { coins = 30 + 30 * n, booster = LEVEL_BOOSTERS[(n - 2) % #LEVEL_BOOSTERS + 1] }
end

return M
