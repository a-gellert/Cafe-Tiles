-- Persistent player data (sys.save; IndexedDB on HTML5).
local config = require "main.modules.config"
local decor = require "main.modules.decor"

local M = {}

local VERSION = 1

local function defaults()
	return {
		version = VERSION,
		level = 1,
		coins = 0,
		decor = {},
		boosters = {
			undo = config.START_BOOSTERS.undo,
			shuffle = config.START_BOOSTERS.shuffle,
			rush = config.START_BOOSTERS.rush,
		},
		sound = true,
		music = true,
		lang = "",
		stars = {},
		tips = {},
		missions = { list = {}, done = 0, serial = 0 },
		star_chest = 0,
		streak = 0,
	}
end

M.data = defaults()

local function save_path()
	return sys.get_save_file("cafe_tiles", "save.dat")
end

local function merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" then
			merge(dst[k], v)
		elseif dst[k] == nil or type(dst[k]) == type(v) then
			dst[k] = v
		end
	end
end

function M.load(fresh)
	local d = defaults()
	if not fresh then
		local ok, saved = pcall(sys.load, save_path())
		if ok and type(saved) == "table" and saved.version then merge(d, saved) end
	end
	M.data = d
end

function M.save()
	pcall(sys.save, save_path(), M.data)
end

function M.coin_mult()
	return decor.coin_mult(M.data.decor)
end

function M.add_coins(n)
	M.data.coins = M.data.coins + n
end

function M.buy_decor(id)
	local price = decor.next_price(M.data.decor, id)
	if not price or M.data.coins < price then return false end
	M.data.coins = M.data.coins - price
	M.data.decor[id] = decor.tier(M.data.decor, id) + 1
	M.save()
	return true
end

function M.can_decorate()
	local p = decor.cheapest(M.data.decor)
	return p ~= nil and M.data.coins >= p
end

function M.streak_mult()
	local s = M.data.streak or 0
	if s >= 3 then
		return 1 + (config.STREAK_BONUS[3] or 0.30)
	elseif s == 2 then
		return 1 + (config.STREAK_BONUS[2] or 0.15)
	end
	return 1
end

function M.reset_streak()
	if (M.data.streak or 0) > 0 then
		M.data.streak = 0
		M.save()
	end
end

function M.star_chest_progress()
	return M.data.star_chest or 0, config.STAR_CHEST_GOAL
end

function M.can_open_star_chest()
	return (M.data.star_chest or 0) >= config.STAR_CHEST_GOAL
end

function M.open_star_chest()
	if not M.can_open_star_chest() then return nil end
	M.data.star_chest = math.max(0, (M.data.star_chest or 0) - config.STAR_CHEST_GOAL)
	M.add_coins(config.STAR_CHEST_COINS)
	local booster_pool = { "undo", "shuffle", "rush" }
	local b = booster_pool[math.random(#booster_pool)]
	M.data.boosters[b] = (M.data.boosters[b] or 0) + 1
	M.save()
	return {
		coins = config.STAR_CHEST_COINS,
		booster = b,
		star_chest = M.data.star_chest,
	}
end

function M.finish_level(level, stars, coins)
	local best = M.data.stars[level] or 0
	if stars > best then M.data.stars[level] = stars end
	M.add_coins(coins)
	if level >= M.data.level then M.data.level = level + 1 end
	M.data.star_chest = (M.data.star_chest or 0) + stars
	M.data.streak = (M.data.streak or 0) + 1
	M.save()
end

-- one-time tips
function M.tip_seen(key)
	return M.data.tips[key] == true
end

function M.mark_tip(key)
	M.data.tips[key] = true
	M.save()
end

return M
