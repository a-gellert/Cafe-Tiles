-- Casual-player balance check: how often does a jam popup (the exit point) show up?
-- The bot taps a random free tile with probability `noise`, otherwise the hint (session.suggest).
-- When the tray holds config.ASSIST_TRAY tiles the game shows the hint hand (after a short
-- pause, not modelled): the bot then follows it 70% of the time.
-- Early levels get the free rescue (config.FREE_CHANCE_LEVEL).
-- usage (from the project root, LuaJIT from the Defold editor):
--   luajit-64.exe tools/sim_casual.lua [first] [last] [seconds_per_tap] [noise] [runs]
-- "popup%" = runs that reached the jam popup, "rescue%" = runs saved by the free rescue,
-- "lost%" = runs lost when the player refuses every video and coin continue.
package.path = "./?.lua;" .. package.path

local session = require "main.modules.session"
local config = require "main.modules.config"

local first = tonumber(arg[1]) or 1
local last = tonumber(arg[2]) or 20
local tap_time = tonumber(arg[3]) or 2.0
local noise = tonumber(arg[4]) or 0.4
local runs = tonumber(arg[5]) or 40
math.randomseed(7)

local function free_tiles(s)
	local c = {}
	for _, t in ipairs(s.board.tiles) do
		if (t.where == "board" and t.blockers == 0) or t.where == "shelf" then c[#c + 1] = t.id end
	end
	return c
end

print("lvl  popup%  rescue%  lost%  secs  case   ord%   stars")
local total_secs, total_popups = 0, 0
for level = first, last do
	local popups, rescues, lost, secs, shown, share, stars = 0, 0, 0, 0, 0, 0, 0
	for _ = 1, runs do
		local s = session.new(level)
		local popup, rescued, t = false, false, 0
		for _ = 1, 3000 do
			session.update(s, tap_time)
			t = t + tap_time
			if s.status == "won" then break end
			if s.status == "jam" then
				if session.can_second_chance(s, "free") then
					session.second_chance(s, "free")
					rescued = true
				else
					popup = true
					break
				end
			end
			local nz = #s.slot >= config.ASSIST_TRAY and noise * 0.3 or noise
			local id
			if math.random() < nz then
				local c = free_tiles(s)
				id = c[math.random(#c)]
			else
				id = session.suggest(s)
			end
			if id then session.tap(s, id) end
			s.events = {}
		end
		if popup then popups = popups + 1 end
		if rescued then rescues = rescues + 1 end
		if s.status ~= "won" then lost = lost + 1 end
		secs = secs + t
		shown = shown + s.showcase
		share = share + s.dishes * 300 / s.total
		if s.status == "won" then stars = stars + session.result(s).stars end
	end
	total_secs = total_secs + secs / runs
	total_popups = total_popups + popups / runs
	print(string.format("%-4d %-7d %-8d %-6d %-5d %-6.1f %-6.1f %.1f", level,
		math.floor(popups * 100 / runs), math.floor(rescues * 100 / runs), math.floor(lost * 100 / runs),
		math.floor(secs / runs), shown / runs, share / runs, stars / math.max(1, runs - lost)))
end
print(string.format("jam popups per player over levels %d-%d: %.2f, level time %.1f min",
	first, last, total_popups, total_secs / 60))
