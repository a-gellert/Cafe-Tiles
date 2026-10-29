-- Modal popups. Built from app.popup = { kind = ..., data = ... } so they survive rebuilds.
local ui = require "main.gui.ui"
local i18n = require "main.modules.i18n"
local progress = require "main.modules.progress"
local decor = require "main.modules.decor"
local session = require "main.modules.session"
local audio = require "main.modules.audio"
local poki = require "main.modules.poki"
local missions = require "main.modules.missions"
local config = require "main.modules.config"
local layout = require "main.modules.layout"
local cafe_view = require "main.gui.cafe_view"
local meta_view = require "main.gui.meta_view"

local M = {}

local V3 = vmath.vector3
local H = ui.hex

local function frame(app, w, h, title, backdrop)
	local root = ui.pane(app.popup_layer, 0, 0)
	local dim = ui.box(root, "square", app.vw / 2, app.vh / 2, app.vw, app.vh, vmath.vector4(0.24, 0.07, 0.2, 0.55))
	ui.fade(dim, 0, 0.55, 0.2)
	if backdrop then backdrop(root) end
	local s = math.min(1, (app.vw - 30) / w, (app.vh - 80) / (h + 60))
	local panel = ui.pane(root, app.vw / 2, app.vh / 2 - 20 * s, s)
	ui.slice(panel, "frame", 0, 0, w, h, ui.CREAM, 34)
	if title then
		local rib = ui.slice(panel, "btn", 0, h / 2, math.min(w * 0.82, 470), 86, ui.PINK, 34)
		local t = ui.text(rib, title, 0, 6, 42)
		ui.fit(t, math.min(w * 0.82, 470) - 50, 42)
	end
	ui.pop(panel, s * 0.6, s, 0.3)
	return root, panel
end

local function button(parent, x, y, w, h, color, label, icon, fn)
	local b = ui.slice(parent, "btn", x, y, w, h, color, 34)
	local tx = 0
	if icon then
		ui.icon(b, icon, -w / 2 + 48, 5, 50)
		tx = 26
	end
	if label then
		local t = ui.text(b, label, tx, 6, 36)
		ui.fit(t, w - (icon and 110 or 40), 36)
	end
	ui.button(b, w, h, fn)
	return b
end

local function round(parent, x, y, size, color, icon, fn)
	local b = ui.box(parent, "btn_round", x, y, size, size, color)
	ui.icon(b, icon, 0, 4, size * 0.5)
	ui.button(b, size, size, fn)
	return b
end

local function close_button(app, panel, w, h)
	round(panel, w / 2 - 18, h / 2 - 10, 76, H("#ff4d6d"), "icon_close", function() app.dismiss() end)
end

local function audio_toggles(app, panel, y)
	local d = progress.data
	round(panel, -90, y, 110, d.sound and ui.BLUE or ui.GREY, d.sound and "icon_sound" or "icon_sound_off", function()
		app.set_audio(not d.sound, d.music)
	end)
	round(panel, 90, y, 110, d.music and ui.BLUE or ui.GREY, d.music and "icon_music" or "icon_music_off", function()
		app.set_audio(d.sound, not d.music)
	end)
end

-- ---------------------------------------------------------------- kinds

local builders = {}

builders.pause = function(app)
	local w, h = 520, 520
	local root, panel = frame(app, w, h, i18n.get("PAUSED"))
	audio_toggles(app, panel, 120)
	button(panel, 0, -20, 380, 104, ui.GREEN, i18n.get("RESUME"), "icon_play", function() app.resume() end)
	button(panel, -100, -150, 220, 96, ui.BLUE, i18n.get("RESTART"), "icon_undo", function() app.restart() end)
	round(panel, 70, -150, 96, ui.GOLD, "icon_tasks", function() app.open_child("missions") end)
	round(panel, 180, -150, 96, ui.PURPLE, "icon_home", function() app.show_menu() end)
	return root
end

builders.win = function(app, data)
	local r = data
	-- first levels: stars, coins and Continue only; tasks, chest and the x2 video come later
	local level = app.session and app.session.level or progress.data.level
	local reveal = level >= config.REVEAL_LEVEL
	local has_streak = r.streak and r.streak >= 2
	local offer_x2 = reveal and not r.doubled
	-- rows top-down (distance of each row centre from the panel top)
	local y_coins = 320 + (has_streak and 50 or 0)
	local y_stats = y_coins + 92
	local y_chest = y_stats + 88
	local y_cont = reveal and y_chest + 100 or y_stats + 110
	local y_x2 = y_cont + 106
	local w, h = 560, (offer_x2 and y_x2 or y_cont) + 72
	local top = h / 2
	local root, panel = frame(app, w, h, i18n.get("LEVEL_DONE"), function(r)
		local rays = ui.glow(ui.box(r, "rays", app.vw / 2, app.vh / 2 + 100, 1000, 1000, H("#ffb3d1", 0.5)))
		gui.animate(rays, "euler.z", -360, gui.EASING_LINEAR, 24, 0, nil, gui.PLAYBACK_LOOP_FORWARD)
		if not data.shown then ui.confetti(r, app.vw, app.vh, 60) end
	end)
	-- confetti and the count-up play once, not again after a resize or a child popup
	local first = not data.shown
	data.shown = true

	for i = 1, 3 do
		local x, y, size = (i - 2) * 140, top - 145 + (i == 2 and 22 or 0), i == 2 and 150 or 120
		local st = ui.box(panel, "star", x, y, size, size, i <= r.stars and ui.WHITE or H("#8a6b80", 0.4))
		if i <= r.stars then
			gui.set_scale(st, V3(0.01, 0.01, 1))
			ui.after(0.25 + i * 0.3, function()
				ui.pop(st, 0.01, 1, 0.35)
				audio.play("star", 1, 0.9 + i * 0.12)
				ui.burst(panel, x, y, 9, nil, 120)
				ui.ring(panel, x, y, size * 2, ui.WHITE, 0.35)
			end)
		end
	end

	if has_streak then
		local st_pct = math.floor((r.streak >= 3 and 30 or 15))
		local st_p = ui.slice(panel, "panel", 0, top - 250, 380, 48, H("#ff7b5c", 0.95), 24)
		ui.icon(st_p, "icon_fire", -150, 0, 36)
		local st_txt = ui.text(st_p, i18n.get("WIN_STREAK") .. " x" .. r.streak .. " (+" .. st_pct .. "%)", 12, 1, 24, ui.WHITE)
		ui.fit(st_txt, 280, 24)
		ui.pulse(st_p, 1.05, 0.6)
	end

	local total = r.doubled and r.coins * 2 or r.coins
	local cp = ui.slice(panel, "panel", 0, top - y_coins, 300, 78, H("#6b2f5c", 0.85), 32)
	ui.box(cp, "coin", -100, 0, 62, 62)
	local ct = ui.text(cp, "+" .. (first and 0 or total), 30, 2, 46, ui.GOLD)
	ui.pop(cp, 0.5, 1, 0.3, 0.2)
	if first then
		for k = 1, 12 do
			ui.after(0.3 + k * 0.045, function() gui.set_text(ct, "+" .. math.floor(total * k / 12 + 0.5)) end)
		end
		ui.after(0.9, function() ui.pop(ct, 1.3, 1, 0.25) end)
	end

	-- the meta goal after every level: this level's coins fill the bar to the next decoration
	local before = first and progress.data.coins - total - (r.missions and r.missions.coins or 0) or nil
	local goal = meta_view.goal_bar(panel, 0, top - y_stats, 460, before, function() app.open_child("decor") end)
	if not goal then
		local stats = { { "heart", r.served }, { "bin", r.waste }, { "angry", r.angry } }
		for i, st in ipairs(stats) do
			local x = (i - 2) * 150
			ui.icon(panel, st[1], x - 30, top - y_stats, 48)
			ui.text(panel, tostring(st[2]), x + 22, top - y_stats + 2, 34, ui.WHITE)
		end
	end

	-- star chest progress
	if reveal then
		local cur_chest, goal_chest = progress.star_chest_progress()
		local can_open = progress.can_open_star_chest()
		local chest_y = top - y_chest
		local chest_p = ui.slice(panel, "panel", can_open and -65 or 0, chest_y, can_open and 320 or 440, 56, H("#6b2f5c", 0.9), 24)
		ui.icon(chest_p, "icon_chest", can_open and -120 or -180, 0, 40)
		local chest_txt = ui.text(chest_p, i18n.get("STAR_CHEST") .. "  " .. cur_chest .. "/" .. goal_chest, 10, 1, 24, ui.GOLD)
		ui.fit(chest_txt, can_open and 220 or 320, 24)
		if can_open then
			local ob = button(panel, 160, chest_y, 130, 56, ui.GREEN, i18n.get("OPEN"), nil, function()
				app.open_chest()
			end)
			ui.pulse(ob, 1.08, 0.5)
		end
	end

	-- Poki: the plain Continue is the primary button, above and bigger than the video one,
	-- and video buttons are never green
	local cont_y = top - y_cont
	-- a decor item is affordable: offer it right here, the decor popup returns to this one
	if progress.can_decorate() then
		local d = round(panel, -190, cont_y, 92, ui.PURPLE, "icon_brush", function() app.open_child("decor") end)
		local badge = ui.box(d, "btn_round", 32, 32, 36, 36, H("#ff4d6d"))
		ui.text(badge, "!", 0, 2, 26)
		ui.pulse(d, 1.1, 0.5)
	else
		round(panel, -190, cont_y, 92, ui.PURPLE, "icon_home", function() app.show_menu() end)
	end
	local cont = button(panel, 50, cont_y, 330, 100, ui.ORANGE, i18n.get("CONTINUE"), "icon_play", function() app.next_level() end)
	ui.pulse(cont, 1.05, 0.6)
	if offer_x2 then
		poki.measure("rewarded", "double-coins", "visible")
		button(panel, 50, top - y_x2, 330, 84, ui.PURPLE, "x2", "icon_ad", function() app.double_coins() end)
	end
	return root
end

-- star chest, a session gift (data.gift) or a cafe level reward (data.cafe_level)
builders.chest = function(app, data)
	local w, h = 540, 580
	local gift = data and data.gift
	local cafe_level = data and data.cafe_level
	local title = cafe_level and "CAFE_LEVEL_UP" or (gift and "GIFT" or "STAR_CHEST")
	local root, panel = frame(app, w, h, i18n.get(title), function(r)
		local rays = ui.glow(ui.box(r, "rays", app.vw / 2, app.vh / 2 + 70, 950, 950, H("#ffd6e8", 0.55)))
		gui.animate(rays, "euler.z", -360, gui.EASING_LINEAR, 20, 0, nil, gui.PLAYBACK_LOOP_FORWARD)
		if data and not data.shown then ui.confetti(r, app.vw, app.vh, 40) end
	end)
	if data then data.shown = true end

	local ch = ui.box(panel, cafe_level and "star" or (gift and "gift" or "chest"), 0, 95, 140, 140)
	if cafe_level then ui.text(ch, tostring(cafe_level), 0, -6, 54, ui.WHITE, ui.INK) end
	ui.pop(ch, 0.2, 1, 0.35)
	gui.animate(ch, "position.y", 105, gui.EASING_INOUTSINE, 0.8, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)

	local reward = data
	if reward then
		-- Reward 1: Coins
		local r1 = ui.slice(panel, "panel", -105, -45, 185, 78, H("#6b2f5c", 0.9), 28)
		ui.box(r1, "coin", -52, 0, 56, 56)
		ui.text(r1, "+" .. reward.coins, 25, 2, 38, ui.GOLD)
		ui.pop(r1, 0.2, 1, 0.35, 0.15)

		-- Reward 2: Booster (a gift may be coins only)
		if reward.booster then
			local icon_name = (reward.booster == "undo" and "icon_undo")
				or (reward.booster == "shuffle" and "icon_shuffle")
				or "icon_bolt"
			local r2 = ui.slice(panel, "panel", 105, -45, 185, 78, H("#6b2f5c", 0.9), 28)
			ui.icon(r2, icon_name, -50, 0, 50)
			ui.text(r2, "+1", 25, 2, 38, ui.WHITE)
			ui.pop(r2, 0.2, 1, 0.35, 0.3)
		else
			gui.set_position(r1, V3(0, -45, 0))
		end

		ui.after(0.25, function()
			audio.play(gift and "gift" or "win")
			ui.burst(panel, 0, 95, 16, nil, 170)
			ui.ring(panel, 0, 95, 320, ui.WHITE, 0.45)
		end)
	end

	button(panel, 0, -h / 2 + 66, 360, 96, ui.GREEN, i18n.get("CLAIM"), "icon_check", function()
		audio.play("coin")
		app.dismiss()
	end)
	return root
end

builders.jam = function(app)
	local s = app.session
	local cost = app.continue_cost()
	local coins_ok = session.can_second_chance(s, true) and progress.data.coins >= cost
	local ad_ok = session.can_second_chance(s)
	-- rows top-down: a plain way on first (coins, else retry), the video chance under it
	local y_main = 350
	local y_ad = y_main + 112
	local y_bottom = (ad_ok and y_ad or y_main) + 116
	local w, h = 540, y_bottom + 70
	local top = h / 2
	local root, panel = frame(app, w, h, i18n.get("JAM"))
	local face = ui.box(panel, "angry", 0, top - 160, 120, 120)
	ui.shake(face, 15)
	local t = ui.text(panel, i18n.get("JAM_DESC"), 0, top - 254, 36, ui.INK, ui.CREAM)
	ui.fit(t, w - 80, 36)
	local main
	if coins_ok then
		main = button(panel, 0, top - y_main, 420, 104, ui.ORANGE, i18n.get("CHANCE") .. " · " .. cost, "coin", function() app.continue_coins() end)
	else
		main = button(panel, 0, top - y_main, 420, 104, ui.ORANGE, i18n.get("RETRY"), "icon_undo", function() app.retry() end)
	end
	ui.pulse(main, 1.05, 0.6)
	if ad_ok then
		poki.measure("rewarded", "second-chance", "visible")
		button(panel, 0, top - y_ad, 420, 96, ui.PURPLE, i18n.get("CHANCE"), "icon_ad", function() app.second_chance() end)
	end
	if coins_ok then
		round(panel, -170, top - y_bottom, 92, ui.PURPLE, "icon_home", function() app.show_menu() end)
		button(panel, 50, top - y_bottom, 320, 96, ui.BLUE, i18n.get("RETRY"), "icon_undo", function() app.retry() end)
	else
		round(panel, 0, top - y_bottom, 92, ui.PURPLE, "icon_home", function() app.show_menu() end)
	end
	return root
end

builders.settings = function(app)
	local w, h = 520, 520
	local root, panel = frame(app, w, h, i18n.get("SETTINGS"))
	close_button(app, panel, w, h)
	audio_toggles(app, panel, 100)
	local lang = button(panel, 0, -60, 380, 100, ui.PURPLE, i18n.NAMES[i18n.get_language()], "icon_globe", function()
		app.next_language()
	end)
	local lt = ui.text(panel, i18n.get("LANGUAGE"), 0, -140, 28, ui.INK, ui.CREAM)
	ui.fit(lt, 300, 28)
	return root
end

-- soft badge colors behind the item samples
local DECOR_BADGE = {
	wall = H("#ffd9e6"), counter = H("#ffe7cf"), flowers = H("#ffe0f0"), lights = H("#fff1c4"),
	plants = H("#d8f5e6"), floor = H("#f3e3d6"), kitchen = H("#e9ddff"),
}

local function decor_card(app, panel, it, x, y, cw, ch, highlight)
	local owned = progress.data.decor
	local tier = decor.tier(owned, it.id)
	local price = decor.next_price(owned, it.id)
	local afford = price ~= nil and progress.data.coins >= price
	ui.slice(panel, "panel", x, y - 6, cw, ch, H("#d77fa3", 0.35), 30)
	local card = ui.slice(panel, "panel", x, y, cw, ch, (not price and H("#fff4d6")) or (afford and ui.WHITE) or H("#fbeef3"), 30)
	local badge = ui.box(card, "btn_round", -cw / 2 + 60, 4, 96, 96, DECOR_BADGE[it.id] or ui.ROSE)
	-- the sample shows what the next tier brings (the last one when maxed)
	cafe_view.swatch(badge, it.id, math.min(tier + 1, decor.MAX_TIER), 0, 4, 62)
	local name = ui.text(card, i18n.get("DECOR_" .. it.id), -cw / 2 + 118, 36, 26, ui.INK, ui.CREAM)
	gui.set_pivot(name, gui.PIVOT_W)
	ui.fit(name, cw - 130, 26)
	for p = 1, decor.MAX_TIER do
		ui.box(card, "star", -cw / 2 + 134 + (p - 1) * 32, 0, 30, 30, p <= tier and ui.WHITE or H("#8a6b80", 0.3))
	end
	if price then
		local b = ui.slice(card, "btn", cw / 2 - 78, -ch / 2 + 32, 136, 52, afford and ui.GREEN or ui.GREY, 24)
		ui.box(b, "coin", -40, 4, 36, 36)
		local pt = ui.text(b, tostring(price), 16, 5, 28)
		ui.fit(pt, 76, 28)
		if afford then ui.pulse(b, 1.06, 0.6) end
	else
		ui.text(card, i18n.get("MAX"), cw / 2 - 78, -ch / 2 + 32, 32, ui.GOLD)
	end
	ui.button(card, cw, ch, function()
		if not afford then ui.shake(card, 8) end
		app.buy_decor(it.id)
	end, { silent = true })
	if highlight then
		ui.pop(card, 1.12, 1, 0.35)
		ui.burst(panel, x, y, 12, nil, 150)
	end
	return card
end

-- data.just = item bought a moment ago (revealed once), data.levelup = its cafe level reward
builders.decor = function(app, data)
	local portrait = app.orient == layout.PORTRAIT
	local just = data and data.just
	local levelup = data and data.levelup
	if data then data.just, data.levelup = nil, nil end
	local n = #decor.ITEMS
	local CW, CH, GAP = 290, 140, 14
	local grid_w = 2 * CW + GAP
	local grid_h = math.ceil(n / 2) * (CH + GAP) - GAP
	local w, h, pw, ph
	if portrait then
		pw, ph = grid_w, 320
		w, h = grid_w + 50, 70 + ph + 26 + 76 + 22 + grid_h + 104
	else
		pw, ph = 560, 420
		w, h = pw + grid_w + 90, 70 + 76 + 22 + grid_h + 40
	end
	local root, panel = frame(app, w, h, i18n.get("DECORATE"))
	close_button(app, panel, w, h)
	local top = h / 2
	local px, py, gx, info_y, coins_x, coins_y
	if portrait then
		px, py = 0, top - 70 - ph / 2
		gx = 0
		info_y = py - ph / 2 - 26 - 38
		coins_x, coins_y = 0, -h / 2 + 52
	else
		px, py = -w / 2 + 30 + pw / 2, top - 70 - ph / 2
		gx = w / 2 - 30 - grid_w / 2
		info_y = top - 70 - 38
		coins_x, coins_y = px, py - ph / 2 - 70
	end
	local cv = meta_view.preview(panel, px, py, pw, ph)
	meta_view.level_badge(panel, gx, info_y, grid_w)
	local cp = ui.slice(panel, "panel", coins_x, coins_y, 220, 58, H("#6b2f5c", 0.85), 28)
	ui.box(cp, "coin", -72, 0, 50, 50)
	local ct = ui.text(cp, tostring(progress.data.coins), 18, 1, 32)
	ui.fit(ct, 120, 32)

	local grid_top = info_y - 38 - 22
	for k, it in ipairs(decor.ITEMS) do
		local col, row = (k - 1) % 2, math.floor((k - 1) / 2)
		local x = gx + (col == 0 and -1 or 1) * (CW + GAP) / 2
		-- an odd last card sits in the middle
		if k == n and n % 2 == 1 then x = gx end
		local y = grid_top - CH / 2 - row * (CH + GAP)
		decor_card(app, panel, it, x, y, CW, CH, it.id == just)
	end

	if just then
		-- the purchase comes alive in the preview
		local t = cafe_view.reveal(cv, just)
		ui.confetti(root, app.vw, app.vh, 36)
		ui.after(0.2, function()
			ui.float_text(panel, i18n.get("NEW_LOOK"), px, py + ph / 2 - 60, 56, H("#ff6fa8"), ui.WHITE, 90)
		end)
		if levelup then
			ui.after(t + 0.5, function()
				audio.play("win")
				app.open_child("chest", levelup)
			end)
		end
	end
	return root
end

-- Chef's tasks. data = report from missions.apply (after a win, animated, Continue goes on)
-- or nil (from menu / pause: current state, close button).
local KIND_ICON = { serve = "heart", levels = "icon_play", stars3 = "star", vip = "crown", clean = "bin", gold = "tile_gold" }

builders.missions = function(app, data)
	local after_win = data ~= nil
	local rows = after_win and data.rows or missions.rows(progress.data.missions)
	local w, h = 600, (after_win and 250 or 150) + #rows * 120
	local root, panel = frame(app, w, h, i18n.get("MISSIONS"))
	if not after_win then close_button(app, panel, w, h) end
	for i, r in ipairs(rows) do
		local y = h / 2 - 110 - (i - 1) * 120
		ui.slice(panel, "panel", 0, y, w - 50, 106, r.done and H("#d6f5e6") or H("#ffe6ee"), 30)
		local icon = r.kind == "food" and ("food_" .. config.FOOD[r.food]) or KIND_ICON[r.kind]
		ui.icon(panel, icon, -w / 2 + 72, y, 64, r.kind == "levels" and ui.ORANGE or nil)
		local name = ui.text(panel, i18n.get("MISSION_" .. r.kind, { n = r.goal }), -w / 2 + 116, y + 22, 26, ui.INK, ui.CREAM)
		gui.set_pivot(name, gui.PIVOT_W)
		ui.fit(name, 290, 26)
		-- progress bar
		local bw = 250
		ui.slice(panel, "bar", -w / 2 + 116 + bw / 2, y - 18, bw, 24, H("#6b2f5c", 0.22), 10)
		local fill = ui.slice(panel, "bar", -w / 2 + 116, y - 18, math.max(16, bw * r.from / r.goal), 20, r.done and ui.GREEN or ui.GOLD, 9)
		gui.set_pivot(fill, gui.PIVOT_W)
		local label = ui.text(panel, r.from .. "/" .. r.goal, -w / 2 + 116 + bw / 2, y - 17, 20, ui.WHITE)
		if r.to ~= r.from then
			gui.animate(fill, "size.x", math.max(16, bw * r.to / r.goal), gui.EASING_OUTQUAD, 0.6, 0.3 + i * 0.2, function()
				gui.set_text(label, r.to .. "/" .. r.goal)
			end)
		end
		-- reward
		local rx = w / 2 - 95
		if r.done then
			local ok = ui.box(panel, "icon_check", rx, y + 16, 54, 54, ui.GREEN)
			gui.set_scale(ok, V3(0.01, 0.01, 1))
			ui.after(0.9 + i * 0.2, function()
				ui.pop(ok, 0.01, 1, 0.35)
				audio.play("coin")
				ui.burst(panel, rx, y, 8, ui.GOLD, 90)
			end)
			ui.text(panel, "+" .. r.coins, rx + 8, y - 26, 28, ui.GOLD)
			ui.box(panel, "coin", rx - 46, y - 26, 32, 32)
		else
			ui.box(panel, "coin", rx - 30, y + 10, 40, 40)
			ui.text(panel, tostring(r.coins), rx + 22, y + 11, 28, ui.GOLD)
			if r.booster then
				local bi = r.booster == "undo" and "icon_undo" or (r.booster == "shuffle" and "icon_shuffle" or "icon_bolt")
				ui.icon(panel, bi, rx - 30, y - 30, 34, ui.BLUE)
				ui.text(panel, "+1", rx + 18, y - 29, 24, ui.WHITE)
			end
		end
	end
	if after_win then
		button(panel, 0, -h / 2 + 66, 360, 100, ui.ORANGE, i18n.get("CONTINUE"), "icon_play", function() app.next_level() end)
	end
	return root
end

function M.build(app, popup)
	local b = builders[popup.kind]
	app.popup_root = b(app, popup.data)
end

return M
