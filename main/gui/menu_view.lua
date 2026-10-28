-- Main menu: the player's cafe (decor progress), Play, Decorate, More games, Settings.
local ui = require "main.gui.ui"
local cafe_view = require "main.gui.cafe_view"
local layout = require "main.modules.layout"
local i18n = require "main.modules.i18n"
local progress = require "main.modules.progress"
local decor = require "main.modules.decor"
local config = require "main.modules.config"

local M = {}

local V3 = vmath.vector3
local H = ui.hex
local PILL = H("#6b2f5c", 0.85)

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
	local ty = vh - (portrait and 262 or 130)
	-- a sticker title: plum drop shadow, pink letters with a white rim
	local tsize = portrait and 108 or 100
	local tpane = ui.pane(root, vw / 2, ty)
	local shadow = ui.text(tpane, i18n.get("TITLE"), 0, -7, tsize, H("#b4467a"), H("#b4467a"))
	local title = ui.text(tpane, i18n.get("TITLE"), 0, 0, tsize, H("#ff6fa8"), ui.WHITE)
	ui.fit(shadow, vw - 60, tsize)
	ui.fit(title, vw - 60, tsize)
	gui.animate(tpane, "position.y", ty + 8, gui.EASING_INOUTSINE, 1.4, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
	local tw = ui.text_width(title) * gui.get_scale(title).x
	for k, sx in ipairs({ -0.5, 0.5, -0.22, 0.3 }) do
		local sp = ui.glow(ui.box(tpane, "spark", tw * sx, (k % 2 == 0 and 44 or -40), 46, 46, ui.WHITE))
		gui.animate(sp, "scale", V3(0.2, 0.2, 1), gui.EASING_INOUTSINE, 0.7 + k * 0.17, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
		gui.animate(sp, "euler.z", 180, gui.EASING_LINEAR, 3, 0, nil, gui.PLAYBACK_LOOP_FORWARD)
	end
	local rating = decor.rating(progress.data.decor)
	local rp = ui.slice(root, "panel", vw / 2, ty - 92, 380, 54, PILL, 26)
	ui.box(rp, "star", -160, 2, 46, 46)
	local rt = ui.text(rp, i18n.get("RATING") .. "  " .. rating .. "/" .. decor.max_rating(), 14, 1, 28)
	ui.fit(rt, 300, 28)

	-- coins + settings
	local cp = ui.slice(root, "panel", 175, vh - 46, 190, 58, PILL, 28)
	ui.box(cp, "coin", -70, 0, 54, 54)
	ui.text(cp, tostring(progress.data.coins), 18, 1, 32)
	round_button(root, vw - 60, vh - 46, 78, ui.PURPLE, "icon_gear", nil, function() app.open_popup("settings") end)

	-- star chest widget
	local cur_chest, goal_chest = progress.star_chest_progress()
	local can_open_chest = progress.can_open_star_chest()
	local ch_x = portrait and 175 or 390
	local ch_y = portrait and (vh - 110) or (vh - 46)
	local ch_w = portrait and 190 or 200
	local chest_card = ui.slice(root, "panel", ch_x, ch_y, ch_w, 54, can_open_chest and H("#2fa57c", 0.95) or PILL, 26)
	ui.icon(chest_card, "icon_chest", -ch_w / 2 + 32, 0, 42)
	local ch_t = ui.text(chest_card, can_open_chest and i18n.get("OPEN") or (cur_chest .. "/" .. goal_chest), 18, 1, 26, can_open_chest and ui.WHITE or ui.GOLD)
	ui.fit(ch_t, ch_w - 70, 26)
	ui.button(chest_card, ch_w, 54, function()
		if can_open_chest then
			app.open_chest()
		end
	end)
	if can_open_chest then
		local badge = ui.box(chest_card, "btn_round", ch_w / 2 - 10, 22, 34, 34, H("#ff4d6d"))
		ui.text(badge, "!", 0, 2, 26)
		ui.pulse(chest_card, 1.06, 0.5)
	end

	-- chef's tasks widget (under the chest in portrait, next to it in landscape)
	local mx = portrait and ch_x or (ch_x + ch_w + 20)
	local my = portrait and (ch_y - 64) or ch_y
	local tasks = ui.slice(root, "panel", mx, my, ch_w, 54, PILL, 26)
	ui.icon(tasks, "icon_tasks", -ch_w / 2 + 32, 0, 40, ui.GOLD)
	local mt = ui.text(tasks, i18n.get("MISSIONS"), 18, 1, 24, ui.WHITE)
	ui.fit(mt, ch_w - 70, 24)
	ui.button(tasks, ch_w, 54, function() app.open_popup("missions") end)

	-- session gift: opens after minutes of play (right column in portrait)
	local gx = portrait and (vw - ch_x) or (mx + ch_w + 20)
	local gy = ch_y
	local ready = progress.gift_ready()
	local left = math.ceil((progress.gift_state()))
	local gcard = ui.slice(root, "panel", gx, gy, ch_w, 54, ready and H("#e0457b", 0.95) or PILL, 26)
	local gi = ui.icon(gcard, "gift", -ch_w / 2 + 32, 3, 46)
	local gt = ui.text(gcard, ready and i18n.get("OPEN") or string.format("%d:%02d", math.floor(left / 60), left % 60),
		18, 1, 26, ready and ui.WHITE or ui.GOLD)
	ui.fit(gt, ch_w - 70, 26)
	ui.button(gcard, ch_w, 54, function()
		if progress.gift_ready() then app.open_gift() else ui.shake(gi, 10) end
	end)
	if ready then
		ui.pulse(gcard, 1.06, 0.5)
		gui.animate(gi, "euler.z", 12, gui.EASING_INOUTSINE, 0.2, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
	end

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

	-- win streak badge
	if (progress.data.streak or 0) >= 2 then
		local st_w = 230
		local streak_badge = ui.slice(root, "panel", vw / 2, py + 86, st_w, 42, H("#ff7b5c", 0.95), 20)
		ui.icon(streak_badge, "icon_fire", -st_w / 2 + 24, 0, 32)
		local st_t = ui.text(streak_badge, i18n.get("WIN_STREAK") .. " x" .. progress.data.streak, 14, 1, 22, ui.WHITE)
		ui.fit(st_t, st_w - 55, 22)
		ui.pulse(streak_badge, 1.06, 0.6)
	end

	-- decorate + more games
	-- round buttons flank the Play button
	local dx, dy = portrait and -(vw / 2 - 74) or -340, py + 6
	local label_w = math.min(200, 2 * (vw / 2 + dx) - 12)
	local deco = round_button(root, vw / 2 + dx, dy, 112, ui.PURPLE, "icon_brush", i18n.get("DECORATE"), function()
		app.open_popup("decor")
	end, label_w)
	if progress.can_decorate() then
		local badge = ui.box(deco, "btn_round", 40, 40, 42, 42, H("#ff4d6d"))
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
