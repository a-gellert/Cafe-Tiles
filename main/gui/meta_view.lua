-- Meta widgets shared by the menu, the decor shop and the win popup:
-- the cafe level badge, the next-decoration goal bar and the framed cafe preview.
local ui = require "main.gui.ui"
local cafe_view = require "main.gui.cafe_view"
local decor = require "main.modules.decor"
local progress = require "main.modules.progress"
local config = require "main.modules.config"
local i18n = require "main.modules.i18n"

local M = {}

local V3 = vmath.vector3
local H = ui.hex
local PILL = H("#6b2f5c", 0.9)

-- the preview cafe is built at this inner width and scaled down, so it looks like the menu cafe
local PREVIEW_W = 1280

-- "Cafe level N": a star with the level, one segment per tier towards the next level,
-- and the coin bonus of the decor. w x 72.
function M.level_badge(parent, x, y, w)
	local owned = progress.data.decor
	local lvl = decor.cafe_level(owned)
	local done, step = decor.level_progress(owned)
	local p = ui.slice(parent, "panel", x, y, w, 72, PILL, 32)
	local star = ui.box(p, "star", -w / 2 + 34, 3, 76, 76)
	ui.text(star, tostring(lvl), 0, -4, 30, ui.WHITE, ui.INK)
	local name = ui.text(p, i18n.get("CAFE_LEVEL", { n = lvl }), -w / 2 + 80, 14, 26)
	gui.set_pivot(name, gui.PIVOT_W)
	ui.fit(name, w - 200, 26)
	local bx, bw = -w / 2 + 80, w - 200
	local sw = (bw - (step - 1) * 6) / step
	for k = 1, step do
		ui.slice(p, "bar", bx + (k - 1) * (sw + 6) + sw / 2, -16, sw, 16, k <= done and ui.GOLD or H("#000000", 0.3), 6)
	end
	ui.box(p, "coin", w / 2 - 92, 1, 38, 38)
	local pct = math.floor(decor.rating(owned) * config.DECOR_BONUS * 100 + 0.5)
	local bonus = ui.text(p, "+" .. pct .. "%", w / 2 - 44, 2, 28, ui.GOLD)
	ui.fit(bonus, 64, 28)
	return p
end

-- Progress towards the cheapest next decoration, w x 76; nil when every tier is bought.
-- from: coins to fill from (the coins of a level roll in), nil = no animation.
-- on_ready: tap handler once the decoration is affordable.
function M.goal_bar(parent, x, y, w, from, on_ready)
	local goal = decor.next_goal(progress.data.decor)
	if not goal then return nil end
	local coins = progress.data.coins
	local ready = coins >= goal.price
	local row = ui.slice(parent, "panel", x, y, w, 76, PILL, 32)
	local badge = ui.box(row, "btn_round", -w / 2 + 40, 0, 68, 68, H("#ffe0ec"))
	cafe_view.swatch(badge, goal.id, goal.tier, 0, 3, 42)
	local bx, bw = -w / 2 + 84, w - 102
	ui.slice(row, "bar", bx + bw / 2, 0, bw, 38, H("#000000", 0.3), 12)
	local fill = ui.slice(row, "bar", bx + 3, 0, 20, 32, ui.GOLD, 10)
	gui.set_pivot(fill, gui.PIVOT_W)
	local label = ui.text(row, "", bx + bw / 2, 2, 24)
	local function show(c)
		gui.set_size(fill, V3(math.max(20, (bw - 6) * math.min(1, c / goal.price)), 32, 0))
		if c >= goal.price then
			gui.set_color(fill, ui.GREEN)
			ui.set_text(label, i18n.get("NEXT_DECOR"), bw - 24, 24)
		else
			ui.set_text(label, c .. " / " .. goal.price, bw - 24, 24)
		end
	end
	if from and from < coins then
		show(math.max(0, from))
		for k = 1, 12 do
			ui.after(0.3 + k * 0.045, function() show(math.floor(from + (coins - from) * k / 12 + 0.5)) end)
		end
		if ready and from < goal.price then
			ui.after(0.9, function()
				ui.burst(row, bx + bw, 0, 10, nil, 110)
				ui.pop(badge, 1.4, 1, 0.3)
			end)
		end
	else
		show(coins)
	end
	if ready and on_ready then
		ui.button(row, w, 76, on_ready)
		ui.pulse(row, 1.04, 0.6)
	end
	return row
end

-- The player's cafe in a framed window, pw x ph, with two regulars at the counter.
-- Returns the cafe_view handle (for cafe_view.reveal).
function M.preview(parent, x, y, pw, ph)
	ui.slice(parent, "panel", x, y - 8, pw + 22, ph + 22, H("#c2507e", 0.3), 30)
	ui.slice(parent, "panel", x, y, pw + 18, ph + 18, ui.WHITE, 30)
	local k = pw / PREVIEW_W
	local vh = ph / k
	local holder = ui.pane(parent, x, y, k)
	local cv = cafe_view.build(holder, PREVIEW_W, vh, -vh * 0.14,
		{ mode = "full", decor = progress.data.decor, counter_h = 64, animate = true, seat_scale = 1 })
	for i, cx in ipairs({ -0.1, 0.2 }) do
		local kind = ((progress.data.level + i * 3) % #config.CUSTOMERS) + 1
		local a = ui.box(cv.seats, "cust_" .. config.CUSTOMERS[kind], PREVIEW_W * cx, 40, 170, 170)
		gui.animate(a, "position.y", 52, gui.EASING_INOUTSINE, 0.9 + i * 0.2, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
	end
	return cv
end

return M
