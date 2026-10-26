-- Headless balance check: plays levels with the hint bot (session.suggest).
-- usage (from the project root, LuaJIT from the Defold editor):
--   luajit-64.exe tools/sim.lua [first_level] [last_level] [seconds_per_tap]
package.path = "./?.lua;" .. package.path

local session = require "main.modules.session"
local levels = require "main.modules.levels"
local config = require "main.modules.config"

local first = tonumber(arg[1]) or 1
local last = tonumber(arg[2]) or 60
local tap_time = tonumber(arg[3]) or 0.9

local totals = { won = 0, lost = 0, chances = 0, coins = 0, stars = 0 }
print(string.format("%-4s %-5s %-3s %-5s %-4s %-5s %-5s %-4s %-5s %-5s %-5s %-5s %-6s",
	"lvl", "tiles", "lay", "grid", "typ", "free0", "res", "2nd", "waste", "angry", "stars", "coins", "taps"))
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
			if session.can_second_chance(s) then
				session.second_chance(s)
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
	if outcome == "won" then totals.won = totals.won + 1 else totals.lost = totals.lost + 1 end
	totals.chances = totals.chances + used
	totals.coins = totals.coins + r.coins
	totals.stars = totals.stars + r.stars
	print(string.format("%-4d %-5d %-3d %-5s %-4d %-5d %-5s %-4d %-5d %-5d %-5d %-5d %-6d",
		level, s.total, max_z + 1, s.cols .. "x" .. s.rows, p.types, free0, outcome, used,
		r.waste, r.angry, r.stars, r.coins, taps))
	-- sanity: the deal must keep every food a multiple of 3
	local count = {}
	for _, t in ipairs(s.board.tiles) do count[t.type] = (count[t.type] or 0) + 1 end
	for t, c in pairs(count) do
		if c % 3 ~= 0 then print("  !! food " .. t .. " has " .. c .. " tiles") end
	end
	if s.total ~= p.triples * 3 then print("  !! layout gave " .. s.total .. " tiles, wanted " .. p.triples * 3) end
end
print(string.format("won %d, lost %d, second chances %d, coins %d, avg stars %.2f",
	totals.won, totals.lost, totals.chances, totals.coins, totals.stars / (last - first + 1)))
