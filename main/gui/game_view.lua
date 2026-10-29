-- Gameplay screen: cafe with customers, layered board, tray, shelf, boosters and HUD.
-- The view is rebuilt from the session state (also on resize); session events drive animations.
local ui = require "main.gui.ui"
local cafe_view = require "main.gui.cafe_view"
local session = require "main.modules.session"
local config = require "main.modules.config"
local layout = require "main.modules.layout"
local audio = require "main.modules.audio"
local i18n = require "main.modules.i18n"
local progress = require "main.modules.progress"
local levels = require "main.modules.levels"

local M = {}

local V3 = vmath.vector3
local H = ui.hex

-- board geometry (board units). The tile sprite is 124x144 px with its baked shadow;
-- the 104 px face sits 14 px above the sprite center.
local STEP_X, STEP_Y = 48, 52   -- per half-cell
local K = 100 / 112             -- sprite px -> board units
local TILE_W, TILE_H = 124 * K, 144 * K
local FACE = 104 * K
local FACE_DY = 14 * K
local LIFT = 9                  -- upward shift per layer
local ICON_DY = FACE_DY + 1
local ICON_SIZE = 76
-- tray / shelf / seats (their own units)
local TRAY_STEP = 94
local TRAY_SCALE = 0.86
local SHELF_STEP = 82
local SHELF_SCALE = 0.72
local SEAT_STEP = 230
local BAR_W = 120

local BG_TOP = H("#ffd3e3")
local BG_BOTTOM = H("#ffeadf")
local TRAY = H("#f59ec0")
local TRAY_WARN = H("#ffa05c")
local TRAY_DANGER = H("#ff4d6d")
local PILL = H("#6b2f5c", 0.85)
local CLOCHE_DIM = vmath.vector4(0.9, 0.86, 0.95, 1)   -- a covered cloche stays bright and shiny

local PRAISE_COLORS = { H("#ffd23f"), H("#ff8fc4"), H("#7fdcff"), H("#c9a4ff"), H("#7fe8b4") }

local V = {}

local function food_sprite(t)
	return "food_" .. config.FOOD[t]
end

-- ---------------------------------------------------------------- layout

local function regions(vw, vh, portrait)
	local R = {}
	if portrait then
		local extra = math.max(0, vh - 1280)
		local cafe_h = 236 + math.min(extra * 0.3, 90)
		R.hud_y = vh - 46
		R.cafe = { x = vw / 2, y = vh - 92 - cafe_h / 2, w = vw, h = cafe_h, mode = "strip", counter = -cafe_h / 2 + 54 }
		R.seat_scale = math.min(1, (cafe_h - 50) / 196, vw / 720)
		R.boost = { x = vw / 2, y = 88, s = math.min(1, vw / 720) }
		R.tray = { x = vw / 2, y = 216, s = math.min(1, (vw - 16) / 700) }
		R.shelf = { x = vw / 2, y = 322, s = math.min(1, (vw - 16) / 700) }
		local top = vh - 92 - cafe_h - 10
		local bot = 374
		R.board = { x = vw / 2, y = (top + bot) / 2, w = vw - 20, h = top - bot }
		R.gift = { x = vw / 2 - 58, y = -96 }
	else
		local col = math.max(600, math.min(vw * 0.42, 760))
		R.hud_y = vh - 40
		local ch = vh - 84 - 172
		R.cafe = { x = col / 2 + 10, y = 172 + ch / 2, w = col - 20, h = ch, mode = "full", counter = -ch / 2 + 170 }
		R.seat_scale = math.min(1, (col - 40) / 700)
		R.boost = { x = col / 2 + 10, y = 92, s = (col - 20) / 720 }
		local rx = col + (vw - col) / 2
		local rw = vw - col - 30
		R.tray = { x = rx, y = 82, s = math.min(1, rw / 700) }
		R.shelf = { x = rx, y = 188, s = math.min(1, rw / 700) }
		R.board = { x = rx, y = (vh - 92 + 238) / 2, w = rw, h = vh - 92 - 238 }
		R.gift = { x = vw / 2 - 160, y = 0 }
	end
	return R
end

local function tile_local(t)
	return V3((t.x + 1 - V.cx) * STEP_X - t.z * 2, -(t.y + 1 - V.cy) * STEP_Y + t.z * LIFT - V.lift_mid, 0)
end

local function tray_pos(i)
	return V3((i - 4) * TRAY_STEP, -1, 0)
end

local function shelf_pos(i)
	return V3((i - 4) * SHELF_STEP, -2, 0)
end

local function index_of(list, id)
	for i, v in ipairs(list) do
		if v == id then return i end
	end
end

-- ---------------------------------------------------------------- tiles

local function set_tile_color(tv, free, animate)
	local c = free and ui.WHITE or ui.DIM
	if animate then
		gui.animate(tv.root, "color", c, gui.EASING_OUTQUAD, 0.18)
		gui.animate(tv.icon, "color", c, gui.EASING_OUTQUAD, 0.18)
	else
		gui.set_color(tv.root, c)
		gui.set_color(tv.icon, c)
	end
	-- the cloche fades on its own when it lifts: never animate its colour
	if tv.cloche then gui.set_color(tv.cloche, free and ui.WHITE or CLOCHE_DIM) end
end

local function make_tile(parent, t, pos, scale)
	local root = ui.box(parent, t.gold and "tile_gold" or "tile", pos.x, pos.y, TILE_W, TILE_H)
	gui.set_scale(root, V3(scale, scale, 1))
	local icon = ui.box(root, food_sprite(t.type), 0, ICON_DY, ICON_SIZE, ICON_SIZE)
	local tv = { root = root, icon = icon }
	if t.hidden then tv.cloche = ui.box(root, "cloche", 0, FACE_DY + 3, 96, 89) end
	if t.gold then
		local tw = ui.glow(ui.box(root, "spark", 30, FACE_DY + 30, 30, 30, ui.WHITE))
		gui.animate(tw, "scale", V3(1.6, 1.6, 1), gui.EASING_INOUTSINE, 0.45 + math.random() * 0.3, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
		gui.animate(tw, "euler.z", 90, gui.EASING_LINEAR, 1.6, 0, nil, gui.PLAYBACK_LOOP_FORWARD)
	end
	V.tiles[t.id] = tv
	return tv
end

-- a tile became free: a soft white flash and a little pop
local function flash(tv)
	local f = ui.glow(ui.box(tv.root, "tile_flash", 0, FACE_DY, FACE, FACE, vmath.vector4(1, 1, 1, 0.7)))
	gui.animate(f, "color.w", 0, gui.EASING_OUTQUAD, 0.4, 0, function() gui.delete_node(f) end)
	local s = gui.get_scale(tv.root).x
	gui.animate(tv.root, "scale", V3(s * 1.07, s * 1.07, 1), gui.EASING_OUTSINE, 0.1, 0, nil, gui.PLAYBACK_ONCE_PINGPONG)
end

-- keeps the board draw order (lower layers first, back rows first) after undo
local function restore_order(id)
	local t = V.s.board.tiles[id]
	local key = t.z * 10000 + t.y * 100 + t.x
	local best, best_key
	for _, o in ipairs(V.s.board.tiles) do
		if o.id ~= id and o.where == "board" and V.tiles[o.id] then
			local k = o.z * 10000 + o.y * 100 + o.x
			if k > key and (not best_key or k < best_key) then best, best_key = o.id, k end
		end
	end
	if best then gui.move_below(V.tiles[id].root, V.tiles[best].root) end
end

local function tray_color()
	local n = #V.s.slot
	return n >= config.SLOT_COUNT - 1 and TRAY_DANGER or (n >= config.SLOT_COUNT - 2 and TRAY_WARN or TRAY)
end

local function relayout_tray(delay)
	for i, id in ipairs(V.s.slot) do
		local tv = V.tiles[id]
		-- a tile still flying in finds its cell when it lands
		if tv and not V.arriving[id] then
			gui.animate(tv.root, "position", tray_pos(i), gui.EASING_OUTQUAD, 0.2, delay or 0)
			gui.animate(tv.root, "scale", V3(TRAY_SCALE, TRAY_SCALE, 1), gui.EASING_OUTQUAD, 0.2)
			set_tile_color(tv, true, false)
		end
	end
	gui.set_color(V.tray_bg, tray_color())
end

local function relayout_shelf()
	for i, id in ipairs(V.s.shelf) do
		local tv = V.tiles[id]
		if tv then
			gui.cancel_animations(tv.root)
			gui.animate(tv.root, "position", shelf_pos(i), gui.EASING_OUTQUAD, 0.25)
			gui.animate(tv.root, "scale", V3(SHELF_SCALE, SHELF_SCALE, 1), gui.EASING_OUTQUAD, 0.25)
			set_tile_color(tv, true, false)
		end
	end
	gui.set_enabled(V.shelf_bg, #V.s.shelf > 0)
end

-- ---------------------------------------------------------------- customers

local function seat_x(i)
	return (i - (config.SEATS + 1) / 2) * SEAT_STEP
end

local function build_seat(i, c, appear)
	local root = ui.pane(V.seats_pane, seat_x(i), 0)
	local sv = { root = root, customer = c, items = {} }
	if c.vip then
		local g = ui.glow(ui.box(root, "glow", 0, 40, 230, 230, H("#ffd23f", 0.55)))
		ui.pulse(g, 1.12, 0.8)
	end
	sv.avatar = ui.box(root, "cust_" .. config.CUSTOMERS[c.kind], 0, 30, 140, 140)
	-- idle breathing
	gui.animate(sv.avatar, "scale.y", 1.035, gui.EASING_INOUTSINE, 0.9 + math.random() * 0.4, math.random() * 0.5, nil, gui.PLAYBACK_LOOP_PINGPONG)
	if c.vip then
		local crown = ui.box(sv.avatar, "crown", 0, 74, 70, 52)
		gui.set_euler(crown, V3(0, 0, -8))
		ui.pulse(crown, 1.08, 0.5)
	end
	local n = #c.items
	local bw = 28 + n * 60
	sv.bubble = ui.pane(root, 0, 152)
	ui.box(sv.bubble, "bubble_tail", 0, -40, 30, 22)
	ui.slice(sv.bubble, "frame", 0, 0, bw, 80, c.vip and H("#ffe08a") or ui.WHITE, 30)
	for k, it in ipairs(c.items) do
		local x = (k - (n + 1) / 2) * 60
		local icon = ui.box(sv.bubble, food_sprite(it.type), x, 6, 52, 52)
		local check = ui.box(sv.bubble, "icon_check", x + 12, -6, 34, 34, ui.GREEN)
		gui.set_enabled(check, it.done)
		if it.done then gui.set_color(icon, vmath.vector4(1, 1, 1, 0.45)) end
		sv.items[k] = { icon = icon, check = check }
	end
	if c.patience_max > 0 then
		local bar_w = math.min(BAR_W, bw - 30)
		sv.bar_w = bar_w
		ui.slice(sv.bubble, "bar", 0, -27, bar_w + 6, 14, H("#6b2f5c", 0.22), 6)
		sv.bar = ui.slice(sv.bubble, "bar", -bar_w / 2, -27, bar_w, 9, ui.GREEN, 4)
		gui.set_pivot(sv.bar, gui.PIVOT_W)
	end
	if appear then
		gui.set_position(root, V3(seat_x(i), -170, 0))
		gui.animate(root, "position", V3(seat_x(i), 0, 0), gui.EASING_OUTBACK, 0.45)
		ui.pop(sv.bubble, 0.01, 1, 0.3, 0.35)
	end
	V.seats[i] = sv
	return sv
end

local function update_patience()
	for _, sv in pairs(V.seats) do
		local c = sv.customer
		if sv.bar and c.patience_max > 0 then
			local f = math.max(0, c.patience / c.patience_max)
			gui.set_size(sv.bar, V3(math.max(8, sv.bar_w * f), 9, 0))
			gui.set_color(sv.bar, f > 0.5 and ui.GREEN or (f > 0.25 and ui.GOLD or H("#ff4d6d")))
			if f < 0.25 and not sv.worried then
				sv.worried = true
				gui.animate(sv.avatar, "position.x", 4, gui.EASING_INOUTSINE, 0.12, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
			end
		end
	end
end

-- a happy little hop
local function hop(sv)
	gui.cancel_animations(sv.avatar, "position.y")
	gui.animate(sv.avatar, "position.y", 52, gui.EASING_OUTQUAD, 0.13, 0, function()
		gui.animate(sv.avatar, "position.y", 30, gui.EASING_OUTBOUNCE, 0.35)
	end)
end

local function leave_seat(seat, happy)
	local sv = V.seats[seat]
	if not sv then return end
	V.seats[seat] = nil
	local function go()
		gui.cancel_animations(sv.avatar, "position.x")
		local mood = ui.box(sv.root, happy and "heart" or "angry", 50, 110, 64, 64)
		ui.pop(mood, 0.1, 1, 0.3)
		gui.animate(mood, "position.y", 150, gui.EASING_OUTQUAD, 0.8)
		gui.set_enabled(sv.bubble, false)
		if happy then ui.hearts(sv.root, 0, 100, 4, 50) end
		local p = gui.get_position(sv.root)
		gui.animate(sv.root, "position", V3(p.x, -180, 0), gui.EASING_INBACK, 0.4, 0.35, function()
			sv.deleted = true
			gui.delete_node(sv.root)
		end)
		if not happy then
			audio.play("angry")
			ui.shake(sv.avatar, 12)
		end
	end
	-- a happy guest waits for the last dish to land
	if happy then ui.after(0.95, go) else go() end
end

-- ---------------------------------------------------------------- HUD / toasts

local function coins_text()
	gui.set_text(V.coins_label, tostring(V.coins_shown))
end

-- rolls the HUD counter up to the new value
local function add_coins_shown(amount)
	local from = V.coins_shown
	V.coins_shown = V.coins_shown + amount
	local steps = math.min(8, math.max(1, amount))
	for k = 1, steps do
		ui.after(k * 0.035, function()
			gui.set_text(V.coins_label, tostring(math.floor(from + amount * k / steps + 0.5)))
		end)
	end
end

local function update_progress()
	local s = V.s
	local f = 1 - session.remaining(s) / s.total
	gui.set_size(V.progress_fill, V3(math.max(10, 210 * f), 12, 0))
end

local function update_boosters()
	for kind, b in pairs(V.boosters) do
		local count = progress.data.boosters[kind] or 0
		gui.set_enabled(b.badge, count > 0)
		gui.set_enabled(b.ad, count <= 0)
		gui.set_text(b.count, tostring(count))
	end
end

function M.toast(text, icon, dur)
	if V.toast then gui.delete_node(V.toast.node) end
	local p = ui.pane(V.fx, V.R.board.x, V.R.board.y + V.R.board.h / 2 - 40)
	-- compare tokens, not nodes: comparing a deleted node raises an error
	local token = { node = p }
	V.toast = token
	local label = ui.text(p, text, icon and 24 or 0, 0, 30)
	ui.fit(label, V.R.board.w - 140, 30)
	local w = ui.text_width(label) * gui.get_scale(label).x + (icon and 110 or 60)
	local bg = ui.slice(p, "panel", 0, 0, w, 64, PILL, 28)
	gui.move_below(bg, label)
	if icon then ui.icon(p, icon, -w / 2 + 40, 0, 50) end
	ui.pop(p, 0.6, 1, 0.25)
	ui.after(dur or 2.2, function()
		if V.toast == token then
			V.toast = nil
			gui.animate(p, "scale", V3(0.01, 0.01, 1), gui.EASING_INBACK, 0.2, 0, function() gui.delete_node(p) end)
		end
	end)
end

local function tip_once(key, text, icon)
	if progress.tip_seen(key) then return end
	progress.mark_tip(key)
	M.toast(text, icon, 2.6)
end

-- big ribbon in the middle of the board (level start)
local function banner(text, color)
	local p = ui.pane(V.fx, V.R.board.x, V.R.board.y + 30)
	local label = ui.text(p, text, 0, 6, 56)
	ui.fit(label, V.R.board.w - 120, 56)
	local w = math.min(V.R.board.w - 40, ui.text_width(label) * gui.get_scale(label).x + 120)
	local rib = ui.slice(p, "btn", 0, 0, w, 112, color or ui.PINK, 34)
	gui.move_below(rib, label)
	ui.burst(p, -w / 2, 0, 5, nil, 60)
	ui.burst(p, w / 2, 0, 5, nil, 60)
	ui.pop(p, 0.3, 1, 0.35)
	ui.after(1.15, function()
		gui.animate(p, "position.y", V.R.board.y + 110, gui.EASING_INQUAD, 0.3)
		gui.animate(p, "scale", V3(0.6, 0.6, 1), gui.EASING_INQUAD, 0.3, 0, function() gui.delete_node(p) end)
	end)
end

-- seconds without a tap before the hint hand shows: almost at once when the tray fills up
-- (casual players jam far less when they see the safe tile, see tools/sim_casual.lua)
local function hint_delay()
	local s = V.s
	if #s.slot >= config.ASSIST_TRAY then
		return s.level <= config.ASSIST_LEVEL and config.ASSIST_DELAY or config.ASSIST_DELAY_LATE
	end
	return s.level <= 5 and config.HINT_IDLE_EARLY or config.HINT_IDLE
end

local function update_hand()
	if not V.hand then return end
	local id = (V.tutorial or V.idle >= hint_delay()) and V.s.status == "play" and session.suggest(V.s)
	if not id then
		gui.set_enabled(V.hand, false)
		return
	end
	local tv = V.tiles[id]
	local p = ui.world(tv.root)
	local lp = ui.to_local(V.fx, p)
	gui.set_enabled(V.hand, true)
	gui.set_position(V.hand, lp + V3(12, -50, 0))
end

-- ---------------------------------------------------------------- combo meter

local function update_combo()
	local s = V.s
	local left = session.combo_left(s)
	local show = s.combo >= 2 and left > 0 and s.status == "play"
	if show ~= V.combo_shown then
		V.combo_shown = show
		gui.set_enabled(V.combo_pill, show)
		if show then ui.pop(V.combo_pill, 0.5, 1, 0.25) end
	end
	if show then
		if V.combo_value ~= s.combo then
			V.combo_value = s.combo
			gui.set_text(V.combo_text, "x" .. s.combo)
			ui.pop(V.combo_text, 1.5, 1, 0.25)
		end
		gui.set_size(V.combo_fill, V3(math.max(8, 96 * left / config.COMBO_WINDOW), 10, 0))
	end
end

-- ---------------------------------------------------------------- session gifts

local function update_gift(force)
	if not V.gift then return end
	local left, f = progress.gift_state()
	local ready = left <= 0
	gui.set_fill_angle(V.gift.pie, -360 * f)
	if ready ~= V.gift.ready or force then
		V.gift.ready = ready
		gui.set_enabled(V.gift.badge, ready)
		gui.set_enabled(V.gift.rays, ready)
		gui.cancel_animations(V.gift.icon, "scale")
		gui.set_scale(V.gift.icon, V3(1, 1, 1))
		if ready then
			gui.animate(V.gift.icon, "scale", V3(1.18, 1.18, 1), gui.EASING_INOUTSINE, 0.35, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
			if not force then
				audio.play("star")
				M.toast(i18n.get("GIFT_READY"), "gift", 2.4)
			end
		end
	end
end

local function build_gift(parent, x, y)
	local g = { root = ui.pane(parent, x, y) }
	g.rays = ui.glow(ui.box(g.root, "rays", 0, 0, 170, 170, H("#ffe08a", 0.7)))
	gui.animate(g.rays, "euler.z", -360, gui.EASING_LINEAR, 8, 0, nil, gui.PLAYBACK_LOOP_FORWARD)
	local base = ui.box(g.root, "btn_round", 0, 0, 84, 84, ui.PLUM)
	g.pie = gui.new_pie_node(V3(0, 4, 0), V3(76, 76, 0))
	gui.set_parent(g.pie, g.root)
	gui.set_inner_radius(g.pie, 30)
	gui.set_outer_bounds(g.pie, gui.PIEBOUNDS_ELLIPSE)
	gui.set_perimeter_vertices(g.pie, 48)
	gui.set_euler(g.pie, V3(0, 0, 90))
	gui.set_color(g.pie, ui.GOLD)
	g.icon = ui.box(g.root, "gift", 0, 6, 58, 58)
	g.badge = ui.box(g.root, "btn_round", 30, 30, 34, 34, H("#ff4d6d"))
	ui.text(g.badge, "!", 0, 2, 26)
	ui.button(base, 96, 96, function()
		if progress.gift_ready() then
			V.app.open_gift()
		else
			local left = math.ceil(progress.gift_state())
			ui.shake(g.icon, 10)
			M.toast(i18n.get("NEXT_GIFT", { t = string.format("%d:%02d", math.floor(left / 60), left % 60) }), "gift", 1.6)
		end
	end)
	V.gift = g
	update_gift(true)
end

-- ---------------------------------------------------------------- flights

-- world position of a node expressed in the fx layer
local function fx_pos(node)
	return ui.to_local(V.fx, (ui.world(node)))
end

local function fly_coins(from, amount)
	local to = fx_pos(V.coin_icon)
	local n = math.min(6, math.max(2, math.floor(amount / 2)))
	for k = 1, n do
		local c = ui.box(V.fx, "coin", from.x + math.random(-24, 24), from.y + math.random(-12, 12), 42, 42)
		ui.pop(c, 0.3, 1, 0.2)
		local last = k == n
		ui.fly(c, to, 0.5, 0.06 * k, function()
			gui.delete_node(c)
			audio.play("coin", 0.55, 0.95 + k * 0.03)
			if last then
				add_coins_shown(amount)
				ui.pop(V.coin_icon, 1.35, 1, 0.22)
				ui.burst(V.coin_hud, -66, 0, 3, ui.GOLD, 40, 26)
			end
		end)
	end
end

-- three matched tiles merge, then a dish flies to `target_node`
local function merge_and_fly(ids, food, delay, target_node, on_arrive, combo, gold)
	local nodes = {}
	for _, id in ipairs(ids) do
		local tv = V.tiles[id]
		V.tiles[id] = nil
		V.arriving[id] = nil
		if tv then nodes[#nodes + 1] = tv.root end
	end
	if #nodes == 0 then return end
	ui.after(delay, function()
		for _, n in ipairs(nodes) do
			gui.cancel_animations(n)
			gui.set_parent(n, V.fx, true)
		end
		local mid = gui.get_position(nodes[math.min(2, #nodes)])
		for _, n in ipairs(nodes) do
			gui.animate(n, "position", mid, gui.EASING_INBACK, 0.16)
			gui.animate(n, "scale", V3(0.35, 0.35, 1), gui.EASING_INBACK, 0.2, 0.03, function() gui.delete_node(n) end)
		end
		ui.after(0.18, function()
			local c = mid + V3(0, 12, 0)
			local pitch = math.min(1.4, 1.0 + math.max(0, (combo or 1) - 1) * 0.07)
			audio.play("match", 1.0, pitch)
			ui.ring(V.fx, c.x, c.y, 230, ui.WHITE, 0.42)
			ui.burst(V.fx, c.x, c.y, 10, nil, 120)
			if combo and combo >= 2 then
				local k = math.min(5, combo - 1)
				local word = ui.float_text(V.fx, i18n.get("PRAISE_" .. k), c.x, c.y + 105, 46 + k * 4, PRAISE_COLORS[k], ui.INK, 80)
				gui.set_euler(word, V3(0, 0, math.random(-6, 6)))
				ui.hearts(V.fx, c.x, c.y + 20, math.min(5, combo), 60)
			end
			if gold and gold > 0 then
				audio.play("sparkle")
				ui.burst(V.fx, c.x, c.y, 12, ui.GOLD, 150, 40)
				ui.float_text(V.fx, "+" .. gold, c.x + 60, c.y - 10, 40, ui.GOLD, ui.INK, 60)
				fly_coins(c, gold)
			end
			local dish = ui.box(V.fx, food_sprite(food), c.x, c.y, 88, 88)
			gui.set_scale(dish, V3(0.4, 0.4, 1))
			gui.animate(dish, "scale", V3(1.3, 1.3, 1), gui.EASING_OUTBACK, 0.16, 0, function()
				gui.animate(dish, "scale", V3(0.62, 0.62, 1), gui.EASING_INQUAD, 0.4)
			end)
			ui.fly(dish, fx_pos(target_node), 0.42, 0.14, function()
				gui.delete_node(dish)
				on_arrive()
			end, ui.GOLD)
		end)
	end)
end

-- ---------------------------------------------------------------- events

local handlers = {}

handlers.to_slot = function(e)
	local tv = V.tiles[e.id]
	if not tv then return end
	gui.cancel_animations(tv.root)
	gui.set_parent(tv.root, V.tray, true)
	set_tile_color(tv, true, false)
	local id, root = e.id, tv.root
	local s = gui.get_scale(root).x
	-- lift, fly along a curve, land with a squash
	gui.animate(root, "scale", V3(s * 1.15, s * 1.15, 1), gui.EASING_OUTQUAD, 0.07, 0, function()
		gui.animate(root, "scale", V3(TRAY_SCALE, TRAY_SCALE, 1), gui.EASING_INOUTQUAD, 0.2)
	end)
	V.arriving[id] = true
	ui.fly(root, tray_pos(e.index), 0.26, 0.03, function()
		V.arriving[id] = nil
		local i = index_of(V.s.slot, id)
		if i and i ~= e.index then gui.animate(root, "position", tray_pos(i), gui.EASING_OUTQUAD, 0.12) end
		gui.animate(root, "scale", V3(TRAY_SCALE * 1.1, TRAY_SCALE * 0.88, 1), gui.EASING_OUTQUAD, 0.06, 0, function()
			gui.animate(root, "scale", V3(TRAY_SCALE, TRAY_SCALE, 1), gui.EASING_OUTBACK, 0.2)
		end)
	end)
	audio.play("tap", 0.9, 0.94 + #V.s.slot * 0.035)
end

handlers.free = function(e)
	for _, id in ipairs(e.ids) do
		local tv = V.tiles[id]
		if tv then
			set_tile_color(tv, true, true)
			flash(tv)
		end
	end
end

handlers.reveal = function(e)
	for _, id in ipairs(e.ids) do
		local tv = V.tiles[id]
		if tv and tv.cloche then
			local c = tv.cloche
			tv.cloche = nil
			gui.animate(c, "position.y", FACE_DY + 80, gui.EASING_OUTQUAD, 0.45)
			gui.animate(c, "euler.z", math.random() < 0.5 and -20 or 20, gui.EASING_OUTQUAD, 0.45)
			gui.animate(c, "color.w", 0, gui.EASING_INQUAD, 0.45, 0, function() gui.delete_node(c) end)
			local p = gui.get_position(tv.root)
			ui.burst(V.board, p.x, p.y + FACE_DY, 7, nil, 70, 30)
			ui.pop(tv.icon, 0.5, 1, 0.3)
		end
	end
	audio.play("reveal", 0.8)
	tip_once("cloche", i18n.get("TIP_CLOCHE"), "cloche")
end

handlers.block = function(e)
	for _, id in ipairs(e.ids) do
		if V.tiles[id] then set_tile_color(V.tiles[id], false, true) end
	end
end

handlers.slot = function()
	relayout_tray(V.matched and 0.32 or 0)
	update_progress()
	local n = #V.s.slot
	-- the tray pulses while it is nearly full
	local pulsing = n >= 5 and V.s.status == "play"
	if pulsing ~= V.tray_pulsing then
		V.tray_pulsing = pulsing
		gui.cancel_animations(V.tray, "scale")
		gui.set_scale(V.tray, V3(V.R.tray.s, V.R.tray.s, 1))
		if pulsing then ui.pulse(V.tray, 1.035, 0.25) end
	end
	if n >= 6 and V.s.status == "play" then
		ui.shake(V.tray, 8)
		gui.animate(V.tray_bg, "color", TRAY_DANGER, gui.EASING_OUTQUAD, 0.15)
	elseif n == 5 and V.s.status == "play" then
		gui.animate(V.tray_bg, "color", TRAY_WARN, gui.EASING_OUTQUAD, 0.15)
	else
		gui.animate(V.tray_bg, "color", TRAY, gui.EASING_OUTQUAD, 0.2)
		if V.last_slot_count and V.last_slot_count >= 5 and n <= 4 then
			ui.burst(V.tray, 0, 0, 10, nil, 160)
		end
	end
	V.last_slot_count = n
	if n >= config.SLOT_COUNT - 2 and V.s.status == "play" then
		tip_once("full", i18n.get("TIP_FULL"))
	end
end

handlers.shelf = function()
	relayout_shelf()
	update_progress()
end

handlers.serve = function(e)
	V.matched = true
	local sv = V.seats[e.seat]
	if not sv then return end
	local item = sv.items[e.item]
	local delay = e.rush and 0.05 or 0.2
	merge_and_fly(e.ids, e.type, delay, item.icon, function()
		-- the guest may have walked away (out of patience) while the dish was flying
		if sv.deleted then return end
		gui.set_enabled(item.check, true)
		ui.pop(item.check, 0.2, 1, 0.3)
		gui.set_color(item.icon, vmath.vector4(1, 1, 1, 0.45))
		audio.play("serve")
		local p = fx_pos(item.icon)
		ui.burst(V.fx, p.x, p.y, 8, nil, 80)
		local a = fx_pos(sv.avatar)
		ui.hearts(V.fx, a.x, a.y + 30, 2, 36)
		hop(sv)
		fly_coins(p, e.coins)
		V.app.mission_check()
	end, e.combo, e.gold)
	if (e.combo or 0) >= 2 then tip_once("combo", i18n.get("TIP_COMBO"), "icon_fire") end
	if V.tutorial and not V.tutorial_served then
		V.tutorial_served = true
		ui.after(1.0, function()
			V.tutorial = false
			update_hand()
			progress.mark_tip("tutorial")
			M.toast(i18n.get("TUT_2"), nil, 3)
		end)
	end
end

handlers.waste = function(e)
	V.matched = true
	merge_and_fly(e.ids, e.type, 0.2, V.bin_icon, function()
		audio.play("waste")
		ui.shake(V.bin_icon, 14)
		gui.set_text(V.bin_count, tostring(V.s.waste))
		ui.pop(V.bin_count, 1.6, 1, 0.3)
	end, nil, e.gold)
	tip_once("waste", i18n.get("TIP_WASTE"))
end

handlers.arrive = function(e)
	if V.seats[e.seat] then leave_seat(e.seat, true) end
	local sv = build_seat(e.seat, V.s.seats[e.seat], true)
	audio.play("arrive", 0.6)
	if e.vip then
		audio.play("star")
		ui.after(0.45, function() ui.burst(sv.root, 0, 110, 12, ui.GOLD, 120) end)
		tip_once("vip", i18n.get("VIP_TIP"), "crown")
	end
end

handlers.leave = function(e)
	local sv = V.seats[e.seat]
	if e.happy and sv and e.coins > 0 then
		local avatar = sv.avatar
		ui.after(0.9, function() fly_coins(fx_pos(avatar), e.coins) end)
	end
	if not e.happy then tip_once("angry", i18n.get("TIP_ANGRY")) end
	leave_seat(e.seat, e.happy)
	if e.happy then V.app.mission_check() end
end

handlers.blocked = function(e)
	local tv = V.tiles[e.id]
	if tv then ui.shake(tv.root, 8) end
	audio.play("blocked")
	V.blocked_taps = (V.blocked_taps or 0) + 1
	if V.blocked_taps >= 2 then tip_once("blocked", i18n.get("TIP_BLOCKED")) end
end

handlers.undo = function(e)
	local tv = V.tiles[e.id]
	if not tv then return end
	V.arriving[e.id] = nil
	gui.cancel_animations(tv.root)
	local t = V.s.board.tiles[e.id]
	if e.to == "board" then
		gui.set_parent(tv.root, V.board, true)
		restore_order(e.id)
		ui.fly(tv.root, tile_local(t), 0.28)
		gui.animate(tv.root, "scale", V3(1, 1, 1), gui.EASING_OUTBACK, 0.28)
		set_tile_color(tv, t.blockers == 0, false)
	else
		gui.set_parent(tv.root, V.shelf, true)
	end
	audio.play("place")
end

handlers.shuffle = function(e)
	audio.play("shuffle")
	for k, id in ipairs(e.ids) do
		local tv = V.tiles[id]
		if tv then
			local t = V.s.board.tiles[id]
			local d = (k % 7) * 0.02
			gui.animate(tv.root, "scale.x", 0.01, gui.EASING_INQUAD, 0.15, d, function()
				gui.play_flipbook(tv.icon, food_sprite(t.type))
				gui.animate(tv.root, "scale.x", 1, gui.EASING_OUTBACK, 0.2)
			end)
		end
	end
	local bp = V.R.board
	ui.burst(V.fx, bp.x, bp.y, 14, nil, math.min(bp.w, bp.h) * 0.45, 40)
end

handlers.to_shelf = function(e)
	for _, id in ipairs(e.ids) do
		local tv = V.tiles[id]
		if tv then
			gui.set_parent(tv.root, V.shelf, true)
			local p = gui.get_position(tv.root)
			ui.burst(V.shelf, p.x, p.y, 4, nil, 50)
		end
	end
	audio.play("booster")
end

handlers.won = function()
	M.celebrate()
	V.app.on_won_soon()
end

handlers.jam = function()
	-- the free rescue follows at once on early levels: no losing sound there
	audio.play(session.can_second_chance(V.s, "free") and "blocked" or "lose")
	V.app.on_jam_soon()
end

function M.process()
	local events = V.s.events
	V.s.events = {}
	V.matched = false
	for _, e in ipairs(events) do
		if e.e == "serve" or e.e == "waste" then V.matched = true end
	end
	for _, e in ipairs(events) do
		local h = handlers[e.e]
		if h then h(e) end
	end
	update_hand()
end

-- ---------------------------------------------------------------- build

local function build_background(vw, vh)
	ui.box(V.root, "square", vw / 2, vh / 2, vw, vh, BG_BOTTOM)
	ui.box(V.root, "grad", vw / 2, vh * 0.62, vw, vh * 0.76, BG_TOP)
	local cell = 168
	local pat = H("#ffffff", 0.32)
	for y = cell / 2, vh + cell / 2, cell do
		for x = cell / 2, vw + cell / 2, cell do ui.box(V.root, "pat_hearts", x, y, cell, cell, pat) end
	end
	ui.ambient(ui.pane(V.root, 0, 0), vw, vh, 12)
end

local function build_board(R)
	local s = V.s
	local minx, maxx, miny, maxy, maxz = math.huge, -math.huge, math.huge, -math.huge, 0
	for _, t in ipairs(s.board.tiles) do
		minx, maxx = math.min(minx, t.x), math.max(maxx, t.x)
		miny, maxy = math.min(miny, t.y), math.max(maxy, t.y)
		maxz = math.max(maxz, t.z)
	end
	V.cx, V.cy = (minx + maxx) / 2 + 1, (miny + maxy) / 2 + 1
	V.lift_mid = maxz * LIFT / 2
	local bw = (maxx - minx) * STEP_X + TILE_W + maxz * 2
	local bh = (maxy - miny) * STEP_Y + TILE_H + maxz * LIFT
	-- small early boards get big, easy-to-hit tiles
	local scale = math.min(R.board.w / bw, R.board.h / bh, 1.6)
	V.board_scale = scale

	-- tablecloth with a soft shadow under the board
	local cw, ch = math.min(R.board.w + 10, bw * scale + 56), math.min(R.board.h + 10, bh * scale + 46)
	ui.slice(V.root, "panel", R.board.x, R.board.y - 10, cw + 6, ch, H("#c2507e", 0.16), 30)
	ui.slice(V.root, "cloth", R.board.x, R.board.y, cw, ch, ui.WHITE, 36)
	V.board = ui.pane(V.root, R.board.x, R.board.y, scale)

	local order = {}
	for _, t in ipairs(s.board.tiles) do order[#order + 1] = t end
	table.sort(order, function(a, b)
		if a.z ~= b.z then return a.z < b.z end
		if a.y ~= b.y then return a.y < b.y end
		return a.x < b.x
	end)
	for _, t in ipairs(order) do
		if t.where == "board" then
			local tv = make_tile(V.board, t, tile_local(t), 1)
			set_tile_color(tv, t.blockers == 0, false)
		end
	end
	-- top-most first for hit testing
	V.hit_order = {}
	for i = #order, 1, -1 do V.hit_order[#V.hit_order + 1] = order[i] end
end

local function booster_button(parent, kind, x, color, icon_name, label)
	local b = ui.box(parent, "btn_round", x, 8, 104, 104, color)
	ui.icon(b, icon_name, 0, 4, 54)
	local txt = ui.text(parent, i18n.get(label), x, -62, 22)
	ui.fit(txt, 140, 22)
	local badge = ui.box(b, "btn_round", 38, 38, 40, 40, H("#ff4d6d"))
	local count = ui.text(badge, "0", 0, 2, 26)
	local ad = ui.box(b, "btn_round", 38, 38, 44, 44, ui.GOLD)   -- Poki: rewarded buttons are never green
	ui.icon(ad, "icon_ad", 0, 2, 28)
	V.boosters[kind] = { node = b, badge = badge, count = count, ad = ad }
	ui.button(b, 110, 110, function() V.app.use_booster(kind) end, { silent = true })
end

function M.build(app, parent)
	V = { app = app, s = app.session, tiles = {}, seats = {}, boosters = {}, arriving = {} }
	local s = V.s
	local vw, vh = app.vw, app.vh
	local portrait = app.orient == layout.PORTRAIT
	local R = regions(vw, vh, portrait)
	V.R = R
	V.root = ui.pane(parent, 0, 0)

	build_background(vw, vh)

	-- cafe + customers
	local cafe = ui.pane(V.root, R.cafe.x, R.cafe.y)
	local cv = cafe_view.build(cafe, R.cafe.w, R.cafe.h, R.cafe.counter,
		{ mode = R.cafe.mode, decor = progress.data.decor, counter_h = 66, seat_scale = R.seat_scale, animate = true })
	V.seats_pane = cv.seats
	gui.set_scale(V.seats_pane, V3(R.seat_scale, R.seat_scale, 1))
	for i = 1, config.SEATS do
		if s.seats[i] then build_seat(i, s.seats[i], false) end
	end

	build_board(R)

	-- shelf
	V.shelf = ui.pane(V.root, R.shelf.x, R.shelf.y, R.shelf.s)
	V.shelf_bg = ui.slice(V.shelf, "panel", 0, 0, 7 * SHELF_STEP + 20, 96, H("#c2507e", 0.18), 30)
	for i, id in ipairs(s.shelf) do make_tile(V.shelf, s.board.tiles[id], shelf_pos(i), SHELF_SCALE) end
	gui.set_enabled(V.shelf_bg, #s.shelf > 0)

	-- tray: a pink 3D slab with inset cells
	V.tray = ui.pane(V.root, R.tray.x, R.tray.y, R.tray.s)
	V.tray_bg = ui.slice(V.tray, "btn", 0, 0, config.SLOT_COUNT * TRAY_STEP + 30, 132, TRAY, 34)
	for i = 1, config.SLOT_COUNT do
		ui.slice(V.tray, "cell", (i - 4) * TRAY_STEP, 4, 86, 100, H("#fff1f5"), 20)
	end
	for i, id in ipairs(s.slot) do make_tile(V.tray, s.board.tiles[id], tray_pos(i), TRAY_SCALE) end
	relayout_tray(0)
	-- combo meter on the tray corner
	V.combo_pill = ui.pane(V.tray, -(config.SLOT_COUNT * TRAY_STEP) / 2 + 74, 78)
	ui.slice(V.combo_pill, "panel", 0, 0, 150, 52, PILL, 24)
	ui.icon(V.combo_pill, "icon_fire", -50, 2, 34, ui.PEACH)
	V.combo_text = ui.text(V.combo_pill, "x2", 6, 9, 28, ui.GOLD)
	ui.slice(V.combo_pill, "bar", 18, -12, 100, 12, H("#000000", 0.3), 5)
	V.combo_fill = ui.slice(V.combo_pill, "bar", -30, -12, 96, 10, ui.PINK, 5)
	gui.set_pivot(V.combo_fill, gui.PIVOT_W)
	gui.set_enabled(V.combo_pill, false)
	V.combo_shown = false

	-- boosters + bin
	local boost = ui.pane(V.root, R.boost.x, R.boost.y, R.boost.s)
	V.bin_icon = ui.box(boost, "bin", -262, 12, 92, 92)
	local pill = ui.slice(boost, "panel", -262, -50, 76, 38, PILL, 18)
	V.bin_count = ui.text(pill, tostring(s.waste), 0, 1, 28)
	-- boosters come in on level 2: the first level only teaches tap -> tray -> order
	if s.level >= config.BOOSTERS_MIN_LEVEL then
		booster_button(boost, "undo", -88, ui.BLUE, "icon_undo", "UNDO")
		booster_button(boost, "shuffle", 72, ui.PURPLE, "icon_shuffle", "SHUFFLE")
		booster_button(boost, "rush", 232, ui.PEACH, "icon_bolt", "RUSH")
		update_boosters()
	end

	-- HUD
	local hud = ui.pane(V.root, vw / 2, R.hud_y)
	local half = vw / 2
	-- coins left (clear of the Poki pill), level between coins and pause
	local cp = ui.slice(hud, "panel", -half + 140, 0, 180, 58, PILL, 28)
	V.coin_hud = cp
	V.coin_icon = ui.box(cp, "coin", -66, 0, 54, 54)
	V.coins_shown = progress.data.coins + s.coins
	V.coins_label = ui.text(cp, "", 18, 1, 32)
	coins_text()
	local lx = portrait and ((-half + 230) + (half - 100)) / 2 or 0
	local lp = ui.slice(hud, "panel", lx, 0, 250, 66, s.params.hard and H("#c2304f", 0.92) or PILL, 30)
	local lt = ui.text(lp, i18n.get("LEVEL", { n = s.level }), 0, 10, 30)
	ui.fit(lt, 230, 30)
	ui.slice(lp, "bar", 0, -18, 216, 16, H("#000000", 0.3), 6)
	V.progress_fill = ui.slice(lp, "bar", -105, -18, 10, 12, ui.PINK, 5)
	gui.set_pivot(V.progress_fill, gui.PIVOT_W)
	update_progress()
	if (progress.data.streak or 0) >= 2 then
		local st_badge = ui.box(lp, "btn_round", 116, 22, 38, 38, H("#ff7b5c"))
		ui.icon(st_badge, "icon_fire", 0, 1, 24)
		ui.pulse(st_badge, 1.1, 0.6)
	end
	local pause = ui.box(hud, "btn_round", half - 60, 0, 78, 78, ui.PURPLE)
	ui.icon(pause, "icon_pause", 0, 3, 40)
	ui.button(pause, 90, 90, function() V.app.pause() end)
	build_gift(hud, R.gift.x, R.gift.y)

	-- fx layer on top
	V.fx = ui.pane(V.root, 0, 0)
	-- pointing hand: tutorial on level 1, idle hint afterwards
	V.tutorial = s.level == 1 and not progress.tip_seen("tutorial")
	V.idle = 0
	V.gift_t = 0
	V.hand = ui.box(V.fx, "hand", 0, 0, 96, 96)
	ui.pulse(V.hand, 1.12, 0.5)
	if V.tutorial and not s.running then M.toast(i18n.get("TUT_1"), nil, 4) end
	update_hand()
end

function M.intro()
	local s = V.s
	if not V.tutorial then banner(i18n.get("LEVEL", { n = s.level }), s.params.hard and H("#ff5d73") or ui.PINK) end
	local food = levels.new_food(s.level)
	local delay = 1.5
	if food and not V.tutorial then
		ui.after(delay, function() M.toast(i18n.get("NEW_DISH"), food_sprite(food), 2.4) end)
		delay = delay + 2.6
	end
	if s.params.hard then
		ui.after(delay, function() M.toast(i18n.get("HARD_LEVEL"), "icon_fire", 2.6) end)
		delay = delay + 2.8
	end
	-- first golden tiles: explain once
	if s.level >= config.GOLD_MIN_LEVEL and not progress.tip_seen("gold") then
		ui.after(delay, function() tip_once("gold", i18n.get("TIP_GOLD"), "coin") end)
	elseif s.level >= config.BOOSTERS_MIN_LEVEL and not progress.tip_seen("boosters") then
		ui.after(delay, function()
			for _, b in pairs(V.boosters) do ui.pop(b.node, 0.3, 1, 0.4) end
			tip_once("boosters", i18n.get("TIP_BOOSTERS"), "icon_bolt")
		end)
	end
end

-- level cleared: confetti and sparkles over the table
function M.celebrate()
	local R = V.R
	ui.confetti(V.fx, V.app.vw, V.app.vh, 46)
	for k = 1, 4 do
		ui.after(0.12 * k, function()
			ui.burst(V.fx, R.board.x + math.random(-1, 1) * R.board.w * 0.3, R.board.y + math.random(-1, 1) * R.board.h * 0.25, 10, nil, 140, 40)
		end)
	end
	ui.ring(V.fx, R.board.x, R.board.y, math.min(R.board.w, R.board.h), ui.WHITE, 0.6)
end

-- coins paid from the HUD total (continue for coins)
function M.spend_coins(n)
	V.coins_shown = V.coins_shown - n
	coins_text()
	ui.shake(V.coin_icon, 10)
end

-- a gift was claimed while the level is on screen
function M.refresh_gift()
	V.coins_shown = progress.data.coins + V.s.coins
	coins_text()
	update_boosters()
	update_gift(true)
end

function M.update(dt)
	if not V.s then return end
	update_patience()
	update_combo()
	V.gift_t = V.gift_t + dt
	if V.gift_t > 0.25 then
		V.gift_t = 0
		update_gift(false)
	end
	if V.s.status == "play" and not V.tutorial then
		local before = V.idle
		V.idle = V.idle + dt
		local need = hint_delay()
		if before < need and V.idle >= need then update_hand() end
	end
end

function M.refresh_boosters()
	update_boosters()
end

function M.booster_node(kind)
	return V.boosters[kind] and V.boosters[kind].node
end

-- ---------------------------------------------------------------- input

-- returns the tile id under a scene point (top-most), and whether it is takeable
function M.tile_at(x, y)
	local s = V.s
	for _, id in ipairs(s.shelf) do
		local tv = V.tiles[id]
		if tv then
			local p, sc = ui.world(tv.root)
			if math.abs(x - p.x) <= TILE_W * sc / 2 and math.abs(y - p.y - FACE_DY * sc) <= FACE * sc / 2 + 6 then
				return id
			end
		end
	end
	local bp, bs = ui.world(V.board)
	for _, t in ipairs(V.hit_order) do
		if t.where == "board" then
			local l = tile_local(t)
			local cx, cy = bp.x + l.x * bs, bp.y + (l.y + FACE_DY) * bs
			if math.abs(x - cx) <= STEP_X * bs and math.abs(y - cy) <= STEP_Y * bs then
				return t.id
			end
		end
	end
end

function M.tap_tile(id)
	V.idle = 0
	local ok = session.tap(V.s, id)
	M.process()
	return ok
end

function M.tap(x, y)
	local id = M.tile_at(x, y)
	if not id then return false end
	return M.tap_tile(id)
end

return M
