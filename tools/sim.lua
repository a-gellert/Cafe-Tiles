-- Headless balance check: plays levels with the hint bot (session.suggest).
-- usage (from the project root, LuaJIT from the Defold editor):
--   luajit-64.exe tools/sim.lua [first_level] [last_level] [seconds_per_tap]
-- "min" = estimated session minutes (taps * seconds_per_tap + LEVEL_OVERHEAD per level),
-- "tasks" = chef's tasks finished on that level, "2nd" = free rescues + ad chances + coin continues,
-- "case" = triples to the display case, "ord%" = triples served to guests (stars),
-- "cmb" = best combo, "cc" = combo coins, "gold" = golden tiles found, "gifts" = session gifts so far.
package.path = "./?.lua;" .. package.path

local session = require "main.modules.session"
local levels = require "main.modules.levels"
local config = require "main.modules.config"
local missions = require "main.modules.missions"

local LEVEL_OVERHEAD = 9 -- seconds: result popup, tasks screen, level intro
math.randomseed(1)
local mstate = { list = {}, done = 0, serial = 0 }
local wallet, minutes, tasks_total, vips_total = 0, 0, 0, 0
local combo_coins_total, gold_total = 0, 0
local progress_gifts = 0
local function gifts_at(seconds)
	local n = 0
	while true do
		local i = n + 1
		local at = i <= #config.GIFT_TIMES and config.GIFT_TIMES[i]
			or config.GIFT_TIMES[#config.GIFT_TIMES] + (i - #config.GIFT_TIMES) * config.GIFT_REPEAT
		if at > seconds then return n end
		n = n + 1
	end
end

local first = tonumber(arg[1]) or 1
local last = tonumber(arg[2]) or 60
local tap_time = tonumber(arg[3]) or 0.9

local totals = { won = 0, lost = 0, chances = 0, coins = 0, stars = 0 }
print(string.format("%-4s %-5s %-3s %-5s %-4s %-5s %-5s %-4s %-5s %-5s %-5s %-5s %-6s",
	"lvl", "tiles", "lay", "grid", "typ", "free0", "res", "2nd", "case", "ord%", "stars", "coins", "taps") .. " vip tasks cmb cc  gold gifts min")
for level = first, last do
	local s = session.new(level)
	local p = s.params
	local free0 = 0
	for _, t in ipairs(s.board.tiles) do
		if t.blockers == 0 then free0 = free0 + 1 end
	end
	local max_z = 0
	for _, t in ipairs(s.board.tiles) do max_z = math.max(max_z, t.z) end

	local taps, used = 0, 0
	local outcome = "?"
	for _ = 1, 2000 do
		session.update(s, tap_time)
		if s.status == "won" then outcome = "won" break end
		if s.status == "jam" then
			local cost = config.CONTINUE_COST_BASE + config.CONTINUE_COST_PER_LEVEL * level
			if session.can_second_chance(s, "free") then
				session.second_chance(s, "free")
				used = used + 1
			elseif session.can_second_chance(s) then
				session.second_chance(s)
				used = used + 1
			elseif session.can_second_chance(s, true) and wallet >= cost then
				wallet = wallet - cost
				session.second_chance(s, true)
				used = used + 1
			else
				outcome = "LOST"
				break
			end
		end
		local id = session.suggest(s)
		if id then
			session.tap(s, id)
			taps = taps + 1
		end
		s.events = {}
	end
	local r = session.result(s)
	local finished = 0
	if outcome == "won" then
		wallet = wallet + r.coins
	end
	-- tasks count from config.REVEAL_LEVEL, as in the game
	if outcome == "won" and level >= config.REVEAL_LEVEL then
		missions.ensure(mstate, level)
		local rep = missions.apply(mstate, level, r)
		wallet = wallet + rep.coins
		for _, row in ipairs(rep.rows) do
			if row.done then finished = finished + 1 end
		end
	end
	tasks_total = tasks_total + finished
	vips_total = vips_total + s.vips
	minutes = minutes + (taps * tap_time + LEVEL_OVERHEAD) / 60
	combo_coins_total = combo_coins_total + s.combo_coins
	gold_total = gold_total + s.gold_found
	-- play time = time inside the level (popups do not count)
	progress_gifts = progress_gifts + taps * tap_time
	if outcome == "won" then totals.won = totals.won + 1 else totals.lost = totals.lost + 1 end
	totals.chances = totals.chances + used
	totals.coins = totals.coins + r.coins
	totals.stars = totals.stars + r.stars
	print(string.format("%-4d %-5d %-3d %-5s %-4d %-5d %-5s %-4d %-5d %-5d %-5d %-5d %-6d",
		level, s.total, max_z + 1, s.cols .. "x" .. s.rows, p.types, free0, outcome, used,
		r.showcase, math.floor(r.dishes * 300 / s.total), r.stars, r.coins, taps) .. string.format(" %-3d %-5d %-3d %-3d %-4d %-5d %.1f",
		s.vips, finished, s.best_combo, s.combo_coins, s.gold_found, gifts_at(progress_gifts), minutes))
	-- sanity: the deal must keep every food a multiple of 3
	local count = {}
	for _, t in ipairs(s.board.tiles) do count[t.type] = (count[t.type] or 0) + 1 end
	for t, c in pairs(count) do
		if c % 3 ~= 0 then print("  !! food " .. t .. " has " .. c .. " tiles") end
	end
	if s.total ~= p.triples * 3 then print("  !! layout gave " .. s.total .. " tiles, wanted " .. p.triples * 3) end
end
print(string.format("won %d, lost %d, second chances %d, coins %d, avg stars %.2f, vip %d, tasks %d, %.1f min",
	totals.won, totals.lost, totals.chances, totals.coins, totals.stars / (last - first + 1), vips_total, tasks_total, minutes))
print(string.format("combo coins %d, golden tiles %d, session gifts %d", combo_coins_total, gold_total, gifts_at(progress_gifts)))
