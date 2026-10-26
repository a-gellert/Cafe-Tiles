-- Cafe decoration: the meta progression. Every bought tier changes the cafe look
-- and raises the cafe rating (+config.DECOR_BONUS coins per tier).
local config = require "main.modules.config"

local M = {}

M.MAX_TIER = 3

M.ITEMS = {
	{ id = "wall", icon = "icon_brush", prices = { 40, 150, 400 } },
	{ id = "counter", icon = "coffee_machine", prices = { 60, 180, 450 } },
	{ id = "lights", icon = "lamp", prices = { 80, 220, 500 } },
	{ id = "plants", icon = "plant_small", prices = { 100, 260, 560 } },
	{ id = "floor", icon = "table", prices = { 120, 300, 620 } },
	{ id = "kitchen", icon = "cake_display", prices = { 150, 350, 700 } },
}

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

function M.cheapest(owned)
	local best
	for _, it in ipairs(M.ITEMS) do
		local p = M.next_price(owned, it.id)
		if p and (not best or p < best) then best = p end
	end
	return best
end

function M.max_rating()
	return #M.ITEMS * M.MAX_TIER
end

return M
