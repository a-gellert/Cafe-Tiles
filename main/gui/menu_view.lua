-- Main menu: the player's cafe (decor progress), Play, Decorate, More games, Settings,
-- the cafe level, the next-decoration goal and the side buttons (gift, star chest, tasks).
local ui = require "main.gui.ui"
local cafe_view = require "main.gui.cafe_view"
local meta_view = require "main.gui.meta_view"
local layout = require "main.modules.layout"
local i18n = require "main.modules.i18n"
local progress = require "main.modules.progress"
local config = require "main.modules.config"

local M = {}

local V3 = vmath.vector3
local H = ui.hex
local PILL = H("#6b2f5c", 0.85)
local ALERT = H("#ff4d6d")

local function round_button(parent, x, y, size, color, icon, label, fn, max_label)
	local b = ui.box(parent, "btn_round", x, y, size, size, color)
	ui.icon(b, icon, 0, 4, size * 0.5)
	if label then
		local t = ui.text(parent, label, x, y - size / 2 - 20, 26)
		ui.fit(t, max_label or size * 1.8, 26)
	end
	ui.button(b, size, size, fn)
	return b
end

-- A round side button with a big sprite and a caption pill; `alert` adds a "!" badge,
-- a pulse and a wiggle (something is ready to open). fn(icon) runs on tap.
local function side_button(parent, x, y, color, sprite, caption, alert, fn)
	local b = ui.box(parent, "btn_round", x, y, 108, 108, color)
	local ic = ui.icon(b, sprite, 0, 6, 70)
	local cap = ui.slice(parent, "panel", x, y - 70, 128, 40, alert and ALERT or PILL, 18)
	local t = ui.text(cap, caption, 0, 1, 24, alert and ui.WHITE or ui.GOLD)
	ui.fit(t, 114, 24)
	ui.button(b, 112, 112, function() fn(ic) end)
	if alert then
		local badge = ui.box(b, "btn_round", 40, 40, 38, 38, ALERT)
		ui.text(badge, "!", 0, 2, 28)
		ui.pulse(b, 1.07, 0.5)
		gui.animate(ic, "euler.z", 10, gui.EASING_INOUTSINE, 0.22, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
	end
	return b
end

function M.build(app, parent)
	local vw, vh = app.vw, app.vh
	local portrait = app.orient == layout.PORTRAIT
	local root = ui.pane(parent, 0, 0)

	-- the cafe fills the screen
	local cafe = ui.pane(root, vw / 2, vh / 2)
	local counter_y = portrait and -vh * 0.04 or -vh * 0.16
	local cv = cafe_view.build(cafe, vw, vh, counter_y, { mode = "full", decor = progress.data.decor, counter_h = 92, animate = true, seat_scale = 1 })
	local k = portrait and 1.05 or 0.95
	gui.set_scale(cv.seats, V3(k, k, 1))
	local kinds = { (progress.data.level % #config.CUSTOMERS) + 1, ((progress.data.level + 3) % #config.CUSTOMERS) + 1 }
	for i, x in ipairs({ -0.12, 0.17 }) do
		local a = ui.box(cv.seats, "cust_" .. config.CUSTOMERS[kinds[i]], vw * x / k, 34, 150, 150)
		gui.animate(a, "position.y", 44, gui.EASING_INOUTSINE, 0.9 + i * 0.2, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
	end
	ui.ambient(ui.pane(root, 0, 0), vw, vh, 14)

	-- title
	local ty = vh - (portrait and 250 or 130)
	-- a sticker title: plum drop shadow, pink letters with a white rim
	local tsize = portrait and 108 or 100
	local tpane = ui.pane(root, vw / 2, ty)
	local shadow = ui.text(tpane, i18n.get("TITLE"), 0, -7, tsize, H("#b4467a"), H("#b4467a"))
	local title = ui.text(tpane, i18n.get("TITLE"), 0, 0, tsize, H("#ff6fa8"), ui.WHITE)
	ui.fit(shadow, vw - 60, tsize)
	ui.fit(title, vw - 60, tsize)
	gui.animate(tpane, "position.y", ty + 8, gui.EASING_INOUTSINE, 1.4, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
	local tw = ui.text_width(title) * gui.get_scale(title).x
	for i, sx in ipairs({ -0.5, 0.5, -0.22, 0.3 }) do
		local sp = ui.glow(ui.box(tpane, "spark", tw * sx, (i % 2 == 0 and 44 or -40), 46, 46, ui.WHITE))
		gui.animate(sp, "scale", V3(0.2, 0.2, 1), gui.EASING_INOUTSINE, 0.7 + i * 0.17, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
		gui.animate(sp, "euler.z", 180, gui.EASING_LINEAR, 3, 0, nil, gui.PLAYBACK_LOOP_FORWARD)
	end
	-- cafe level: the long-term goal under the title
	meta_view.level_badge(root, vw / 2, ty - 100, math.min(460, vw - 40))

	-- coins + settings
	local cp = ui.slice(root, "panel", 175, vh - 46, 190, 58, PILL, 28)
	ui.box(cp, "coin", -70, 0, 54, 54)
	ui.text(cp, tostring(progress.data.coins), 18, 1, 32)
	round_button(root, vw - 60, vh - 46, 78, ui.PURPLE, "icon_gear", nil, function() app.open_popup("settings") end)

	-- side buttons over the wall: gift on the right, star chest and tasks on the left
	local sy = portrait and ty - 250 or vh * 0.56
	local lx, rx = portrait and 80 or 100, portrait and vw - 80 or vw - 100
	local ready = progress.gift_ready()
	local left = math.ceil((progress.gift_state()))
	side_button(root, rx, sy, ui.PINK, "gift",
		ready and i18n.get("OPEN") or string.format("%d:%02d", math.floor(left / 60), left % 60), ready, function(ic)
			if progress.gift_ready() then app.open_gift() else ui.shake(ic, 10) end
		end)
	local cur_chest, goal_chest = progress.star_chest_progress()
	local chest_ready = progress.can_open_star_chest()
	side_button(root, lx, sy, H("#ffb347"), "chest", chest_ready and i18n.get("OPEN") or (cur_chest .. "/" .. goal_chest),
		chest_ready, function(ic)
			if progress.can_open_star_chest() then app.open_chest() else ui.shake(ic, 10) end
		end)
	side_button(root, lx, sy - 160, ui.PURPLE, "icon_tasks", i18n.get("MISSIONS"), false, function()
		app.open_popup("missions")
	end)

	-- play
	local py = portrait and 190 or 140
	local pw = portrait and 360 or 400
	local play = ui.slice(root, "btn", vw / 2, py, pw, 136, ui.ORANGE, 34)
	local pt = ui.text(play, i18n.get("PLAY"), 0, 18, 58)
	ui.fit(pt, pw - 60, 58)
	local lt = ui.text(play, i18n.get("LEVEL", { n = progress.data.level }), 0, -32, 30)
	ui.fit(lt, pw - 60, 30)
	ui.button(play, pw, 136, function() app.play() end)
	ui.pulse(play, 1.04, 0.7)

	-- the next decoration right above Play: coins earned in levels fill it
	local goal_y = py + (portrait and 150 or 130)
	meta_view.goal_bar(root, vw / 2, goal_y, math.min(460, vw - 40), nil, function() app.open_popup("decor") end)

	-- win streak badge
	if (progress.data.streak or 0) >= 2 then
		local st_w = 230
		local streak_badge = ui.slice(root, "panel", vw / 2, goal_y + 66, st_w, 42, H("#ff7b5c", 0.95), 20)
		ui.icon(streak_badge, "icon_fire", -st_w / 2 + 24, 0, 32)
		local st_t = ui.text(streak_badge, i18n.get("WIN_STREAK") .. " x" .. progress.data.streak, 14, 1, 22, ui.WHITE)
		ui.fit(st_t, st_w - 55, 22)
		ui.pulse(streak_badge, 1.06, 0.6)
	end

	-- decorate + more games flank the Play button
	local dx, dy = portrait and -(vw / 2 - 74) or -340, py + 6
	local label_w = math.min(200, 2 * (vw / 2 + dx) - 12)
	local deco = round_button(root, vw / 2 + dx, dy, 112, ui.PURPLE, "icon_brush", i18n.get("DECORATE"), function()
		app.open_popup("decor")
	end, label_w)
	if progress.can_decorate() then
		local badge = ui.box(deco, "btn_round", 40, 40, 42, 42, ALERT)
		ui.text(badge, "!", 0, 2, 30)
		ui.pulse(badge, 1.15, 0.5)
	end
	local url = sys.get_config_string("cafe.more_games_url", "")
	if url ~= "" then
		round_button(root, vw / 2 - dx, dy, 112, ui.BLUE, "icon_gamepad", i18n.get("MORE_GAMES"), function()
			app.more_games(url)
		end, label_w)
	end
end

return M
