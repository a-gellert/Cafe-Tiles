-- Modal popups. Built from app.popup = { kind = ..., data = ... } so they survive rebuilds.
local ui = require "main.gui.ui"
local i18n = require "main.modules.i18n"
local progress = require "main.modules.progress"
local decor = require "main.modules.decor"
local session = require "main.modules.session"
local audio = require "main.modules.audio"
local poki = require "main.modules.poki"

local M = {}

local V3 = vmath.vector3
local H = ui.hex

local function frame(app, w, h, title, backdrop)
	local root = ui.pane(app.popup_layer, 0, 0)
	local dim = ui.box(root, "square", app.vw / 2, app.vh / 2, app.vw, app.vh, vmath.vector4(0.1, 0.05, 0.02, 0.6))
	ui.fade(dim, 0, 0.6, 0.2)
	if backdrop then backdrop(root) end
	local s = math.min(1, (app.vw - 30) / w, (app.vh - 80) / (h + 60))
	local panel = ui.pane(root, app.vw / 2, app.vh / 2 - 20 * s, s)
	ui.slice(panel, "frame", 0, 0, w, h, ui.CREAM, 34)
	if title then
		local rib = ui.slice(panel, "btn", 0, h / 2, math.min(w * 0.82, 470), 86, ui.ORANGE, 34)
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
	round(panel, w / 2 - 18, h / 2 - 10, 76, H("#e63946"), "icon_close", function() app.close_popup() end)
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
	button(panel, -70, -150, 240, 96, ui.BLUE, i18n.get("RESTART"), "icon_undo", function() app.restart() end)
	round(panel, 130, -150, 96, ui.PURPLE, "icon_home", function() app.show_menu() end)
	return root
end

builders.win = function(app, data)
	local r = data
	local w, h = 560, 660
	local root, panel = frame(app, w, h, i18n.get("LEVEL_DONE"), function(r)
		local rays = ui.box(r, "rays", app.vw / 2, app.vh / 2 + 100, 1000, 1000, H("#ffe08a", 0.55))
		gui.animate(rays, "euler.z", -360, gui.EASING_LINEAR, 24, 0, nil, gui.PLAYBACK_LOOP_FORWARD)
	end)

	for i = 1, 3 do
		local x, y, size = (i - 2) * 140, h / 2 - 150 + (i == 2 and 22 or 0), i == 2 and 150 or 120
		local st = ui.box(panel, "star", x, y, size, size, i <= r.stars and ui.WHITE or H("#6b5b52", 0.45))
		if i <= r.stars then
			gui.set_scale(st, V3(0.01, 0.01, 1))
			ui.after(0.25 + i * 0.3, function()
				ui.pop(st, 0.01, 1, 0.35)
				audio.play("star")
				ui.burst(panel, x, y, 6, ui.GOLD, 110)
			end)
		end
	end

	local total = r.doubled and r.coins * 2 or r.coins
	local cp = ui.slice(panel, "panel", 0, 10, 300, 84, H("#4a2a1a", 0.85), 34)
	ui.box(cp, "coin", -100, 0, 66, 66)
	local ct = ui.text(cp, "+" .. total, 30, 2, 48, ui.GOLD)
	ui.pop(cp, 0.5, 1, 0.3, 0.2)

	local stats = { { "heart", r.served }, { "bin", r.waste }, { "angry", r.angry } }
	for i, st in ipairs(stats) do
		local x = (i - 2) * 150
		ui.icon(panel, st[1], x - 30, -72, 50)
		ui.text(panel, tostring(st[2]), x + 22, -70, 36, ui.WHITE)
	end

	if not r.doubled then
		poki.measure("rewarded", "double-coins", "visible")
		button(panel, 0, -170, 400, 100, ui.GREEN, "x2", "icon_ad", function() app.double_coins() end)
	end
	round(panel, -190, -h / 2 + 64, 92, ui.PURPLE, "icon_home", function() app.show_menu() end)
	button(panel, 50, -h / 2 + 64, 330, 104, ui.ORANGE, i18n.get("CONTINUE"), "icon_play", function() app.next_level() end)
	return root
end

builders.jam = function(app)
	local w, h = 540, 560
	local root, panel = frame(app, w, h, i18n.get("JAM"))
	local face = ui.box(panel, "angry", 0, 110, 130, 130)
	ui.shake(face, 15)
	local t = ui.text(panel, i18n.get("JAM_DESC"), 0, 10, 36, H("#4a2a1a"), H("#fff6e5"))
	ui.fit(t, w - 80, 36)
	if session.can_second_chance(app.session) then
		poki.measure("rewarded", "second-chance", "visible")
		local b = button(panel, 0, -95, 420, 108, ui.GREEN, i18n.get("CHANCE"), "icon_ad", function() app.second_chance() end)
		ui.pulse(b, 1.05, 0.6)
	end
	round(panel, -170, -h / 2 + 70, 92, ui.PURPLE, "icon_home", function() app.show_menu() end)
	button(panel, 50, -h / 2 + 70, 320, 100, ui.ORANGE, i18n.get("RETRY"), "icon_undo", function() app.retry() end)
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
	local lt = ui.text(panel, i18n.get("LANGUAGE"), 0, -140, 28, H("#4a2a1a"), H("#fff6e5"))
	ui.fit(lt, 300, 28)
	return root
end

builders.decor = function(app)
	local rows = #decor.ITEMS
	local w, h = 620, 230 + rows * 104
	local root, panel = frame(app, w, h, i18n.get("DECORATE"))
	close_button(app, panel, w, h)
	local owned = progress.data.decor
	local rating = decor.rating(owned)
	local info = ui.text(panel, i18n.get("RATING") .. " " .. rating .. "/" .. decor.max_rating() .. "   " ..
		i18n.get("BONUS", { p = math.floor(rating * 5 + 0.5) }), 0, h / 2 - 82, 28, H("#4a2a1a"), H("#fff6e5"))
	ui.fit(info, w - 80, 28)
	local cp = ui.slice(panel, "panel", 0, -h / 2 + 52, 200, 54, H("#4a2a1a", 0.85), 26)
	ui.box(cp, "coin", -66, 0, 48, 48)
	ui.text(cp, tostring(progress.data.coins), 16, 1, 30)

	for k, it in ipairs(decor.ITEMS) do
		local y = h / 2 - 160 - (k - 1) * 104
		local tier = decor.tier(owned, it.id)
		local price = decor.next_price(owned, it.id)
		ui.slice(panel, "panel", 0, y, w - 50, 92, H("#f2dcc0"), 30)
		ui.icon(panel, it.icon, -w / 2 + 75, y, 72, it.icon == "icon_brush" and ui.PURPLE or nil)
		local name = ui.text(panel, i18n.get("DECOR_" .. it.id), -w / 2 + 128, y + 14, 30, H("#4a2a1a"), H("#fff6e5"))
		gui.set_pivot(name, gui.PIVOT_W)
		ui.fit(name, 230, 30)
		for p = 1, decor.MAX_TIER do
			ui.box(panel, "star", -w / 2 + 140 + (p - 1) * 38, y - 22, 32, 32, p <= tier and ui.WHITE or H("#6b5b52", 0.35))
		end
		if price then
			local afford = progress.data.coins >= price
			local b = ui.slice(panel, "btn", w / 2 - 110, y, 170, 76, afford and ui.GREEN or ui.GREY, 30)
			ui.box(b, "coin", -50, 4, 44, 44)
			ui.text(b, tostring(price), 18, 6, 32)
			ui.button(b, 170, 76, function() app.buy_decor(it.id) end)
		else
			ui.text(panel, i18n.get("MAX"), w / 2 - 110, y, 34, ui.GOLD)
		end
	end
	return root
end

function M.build(app, popup)
	local b = builders[popup.kind]
	app.popup_root = b(app, popup.data)
end

return M
