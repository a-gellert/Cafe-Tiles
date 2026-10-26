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

-- board geometry (board units)
local STEP_X, STEP_Y = 48, 52   -- per half-cell
local TILE_W, TILE_H = 100, 111
local LIFT = 8                  -- upward shift per layer
local ICON_DY = 7
local ICON_SIZE = 74
-- tray / shelf / seats (their own units)
local TRAY_STEP = 94
local TRAY_SCALE = 0.86
local SHELF_STEP = 82
local SHELF_SCALE = 0.72
local SEAT_STEP = 230
local BAR_W = 120

local BG = H("#f3d9b8")
local TABLE = H("#e9c49a")

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
	end
	return R
end

local function tile_local(t)
	return V3((t.x + 1 - V.cx) * STEP_X - t.z * 2, -(t.y + 1 - V.cy) * STEP_Y + t.z * LIFT - V.lift_mid, 0)
end

local function tray_pos(i)
	return V3((i - 4) * TRAY_STEP, 4, 0)
end

local function shelf_pos(i)
	return V3((i - 4) * SHELF_STEP, 2, 0)
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
end

local function make_tile(parent, t, pos, scale)
	local root = ui.box(parent, "tile", pos.x, pos.y, TILE_W, TILE_H)
	gui.set_scale(root, V3(scale, scale, 1))
	local icon = ui.box(root, food_sprite(t.type), 0, ICON_DY, ICON_SIZE, ICON_SIZE)
	local tv = { root = root, icon = icon }
	V.tiles[t.id] = tv
	return tv
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

local function relayout_tray(delay)
	for i, id in ipairs(V.s.slot) do
		local tv = V.tiles[id]
		if tv then
			gui.animate(tv.root, "position", tray_pos(i), gui.EASING_OUTQUAD, 0.2, delay or 0)
			gui.animate(tv.root, "scale", V3(TRAY_SCALE, TRAY_SCALE, 1), gui.EASING_OUTQUAD, 0.2)
			set_tile_color(tv, true, false)
		end
	end
	local n = #V.s.slot
	gui.set_color(V.tray_bg, n >= config.SLOT_COUNT - 1 and H("#d9534f") or (n >= config.SLOT_COUNT - 2 and H("#e08a3c") or H("#b9784a")))
end

local function relayout_shelf()
	for i, id in ipairs(V.s.shelf) do
		local tv = V.tiles[id]
		if tv then
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
	sv.avatar = ui.box(root, "cust_" .. config.CUSTOMERS[c.kind], 0, 30, 140, 140)
	local n = #c.items
	local bw = 28 + n * 60
	sv.bubble = ui.pane(root, 0, 152)
	ui.box(sv.bubble, "bubble_tail", 0, -40, 30, 22)
	ui.slice(sv.bubble, "frame", 0, 0, bw, 80, ui.WHITE, 30)
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
		ui.slice(sv.bubble, "bar", 0, -27, bar_w + 6, 14, H("#4a2a1a", 0.25), 6)
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
			gui.set_color(sv.bar, f > 0.5 and ui.GREEN or (f > 0.25 and ui.GOLD or H("#e63946")))
			if f < 0.25 and not sv.worried then
				sv.worried = true
				gui.animate(sv.avatar, "position.x", 4, gui.EASING_INOUTSINE, 0.12, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
			end
		end
	end
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
		local p = gui.get_position(sv.root)
		gui.animate(sv.root, "position", V3(p.x, -180, 0), gui.EASING_INBACK, 0.45, 0.5, function()
			gui.delete_node(sv.root)
		end)
		if not happy then
			audio.play("angry")
			ui.shake(sv.avatar, 12)
		end
	end
	if happy then ui.after(0.55, go) else go() end
end

-- ---------------------------------------------------------------- HUD / toasts

local function coins_text()
	gui.set_text(V.coins_label, tostring(V.coins_shown))
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
	local bg = ui.slice(p, "panel", 0, 0, w, 64, H("#4a2a1a", 0.88), 28)
	gui.move_below(bg, label)
	if icon then ui.box(p, icon, -w / 2 + 40, 0, 50, 50) end
	ui.pop(p, 0.6, 1, 0.25)
	ui.after(dur or 2.2, function()
		if V.toast == token then
			V.toast = nil
			gui.animate(p, "scale", V3(0.01, 0.01, 1), gui.EASING_INBACK, 0.2, 0, function() gui.delete_node(p) end)
		end
	end)
end

local function tip_once(key, text)
	if progress.tip_seen(key) then return end
	progress.mark_tip(key)
	M.toast(text)
end

local HINT_IDLE = 12

local function update_hand()
	if not V.hand then return end
	local id = (V.tutorial or V.idle >= HINT_IDLE) and V.s.status == "play" and session.suggest(V.s)
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

-- ---------------------------------------------------------------- flights

-- world position of a node expressed in the fx layer
local function fx_pos(node)
	return ui.to_local(V.fx, (ui.world(node)))
end

local function fly_coins(from_node, amount)
	local from = fx_pos(from_node)
	local to = fx_pos(V.coin_icon)
	local n = math.min(6, math.max(2, math.floor(amount / 2)))
	for k = 1, n do
		local c = ui.box(V.fx, "coin", from.x + math.random(-20, 20), from.y + math.random(-10, 10), 40, 40)
		local last = k == n
		gui.animate(c, "position", to, gui.EASING_INQUAD, 0.45, 0.05 * k, function()
			gui.delete_node(c)
			audio.play("coin", 0.6)
			if last then
				V.coins_shown = V.coins_shown + amount
				coins_text()
				ui.pop(V.coin_icon, 1.3, 1, 0.2)
			end
		end)
	end
end

-- three matched tiles merge, then a dish flies to `target_fn()` (fx-local point)
local function merge_and_fly(ids, food, delay, target_node, on_arrive)
	local nodes = {}
	for _, id in ipairs(ids) do
		local tv = V.tiles[id]
		V.tiles[id] = nil
		if tv then nodes[#nodes + 1] = tv.root end
	end
	if #nodes == 0 then return end
	ui.after(delay, function()
		for _, n in ipairs(nodes) do
			gui.cancel_animations(n, "position")
			gui.cancel_animations(n, "scale")
			gui.set_parent(n, V.fx, true)
		end
		local mid = gui.get_position(nodes[math.min(2, #nodes)])
		for _, n in ipairs(nodes) do
			gui.animate(n, "position", mid, gui.EASING_INQUAD, 0.14)
			gui.animate(n, "scale", V3(0.5, 0.5, 1), gui.EASING_INBACK, 0.2, 0.06, function() gui.delete_node(n) end)
		end
		ui.after(0.18, function()
			audio.play("match")
			ui.burst(V.fx, mid.x, mid.y, 7, ui.GOLD, 90)
			local dish = ui.box(V.fx, food_sprite(food), mid.x, mid.y, 84, 84)
			ui.pop(dish, 0.4, 1.25, 0.15)
			local to = fx_pos(target_node)
			gui.animate(dish, "position", to, gui.EASING_INOUTQUAD, 0.42, 0.12)
			gui.animate(dish, "scale", V3(0.6, 0.6, 1), gui.EASING_INQUAD, 0.42, 0.12, function()
				gui.delete_node(dish)
				on_arrive()
			end)
		end)
	end)
end

-- ---------------------------------------------------------------- events

local handlers = {}

handlers.to_slot = function(e)
	local tv = V.tiles[e.id]
	if not tv then return end
	gui.set_parent(tv.root, V.tray, true)
	set_tile_color(tv, true, false)
	gui.animate(tv.root, "position", tray_pos(e.index), gui.EASING_OUTQUAD, 0.2)
	gui.animate(tv.root, "scale", V3(TRAY_SCALE, TRAY_SCALE, 1), gui.EASING_OUTQUAD, 0.2)
	audio.play("tap")
end

handlers.free = function(e)
	for _, id in ipairs(e.ids) do
		if V.tiles[id] then set_tile_color(V.tiles[id], true, true) end
	end
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
		gui.set_enabled(item.check, true)
		ui.pop(item.check, 0.2, 1, 0.3)
		gui.set_color(item.icon, vmath.vector4(1, 1, 1, 0.45))
		audio.play("serve")
		fly_coins(item.icon, e.coins)
	end)
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
	end)
	tip_once("waste", i18n.get("TIP_WASTE"))
end

handlers.arrive = function(e)
	if V.seats[e.seat] then leave_seat(e.seat, true) end
	build_seat(e.seat, V.s.seats[e.seat], true)
	audio.play("arrive", 0.7)
end

handlers.leave = function(e)
	local sv = V.seats[e.seat]
	if e.happy and sv and e.coins > 0 then
		ui.after(0.5, function() fly_coins(sv.avatar, e.coins) end)
	end
	if not e.happy then tip_once("angry", i18n.get("TIP_ANGRY")) end
	leave_seat(e.seat, e.happy)
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
	local t = V.s.board.tiles[e.id]
	if e.to == "board" then
		gui.set_parent(tv.root, V.board, true)
		restore_order(e.id)
		gui.animate(tv.root, "position", tile_local(t), gui.EASING_OUTQUAD, 0.25)
		gui.animate(tv.root, "scale", V3(1, 1, 1), gui.EASING_OUTQUAD, 0.25)
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
				gui.animate(tv.root, "scale.x", 1, gui.EASING_OUTQUAD, 0.15)
			end)
		end
	end
end

handlers.to_shelf = function(e)
	for _, id in ipairs(e.ids) do
		local tv = V.tiles[id]
		if tv then gui.set_parent(tv.root, V.shelf, true) end
	end
	audio.play("booster")
end

handlers.won = function()
	V.app.on_won_soon()
end

handlers.jam = function()
	audio.play("lose")
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
	local scale = math.min(R.board.w / bw, R.board.h / bh, 1.3)
	V.board_scale = scale

	-- table cloth under the board
	ui.slice(V.root, "panel", R.board.x, R.board.y, math.min(R.board.w + 10, bw * scale + 50), math.min(R.board.h + 10, bh * scale + 40), TABLE, 30)
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
	local badge = ui.box(b, "btn_round", 38, 38, 40, 40, H("#e63946"))
	local count = ui.text(badge, "0", 0, 2, 26)
	local ad = ui.box(b, "btn_round", 38, 38, 44, 44, ui.GREEN)
	ui.icon(ad, "icon_ad", 0, 2, 28)
	V.boosters[kind] = { node = b, badge = badge, count = count, ad = ad }
	ui.button(b, 110, 110, function() V.app.use_booster(kind) end, { silent = true })
end

function M.build(app, parent)
	V = { app = app, s = app.session, tiles = {}, seats = {}, boosters = {} }
	local s = V.s
	local vw, vh = app.vw, app.vh
	local portrait = app.orient == layout.PORTRAIT
	local R = regions(vw, vh, portrait)
	V.R = R
	V.root = ui.pane(parent, 0, 0)

	ui.box(V.root, "square", vw / 2, vh / 2, vw, vh, BG)

	-- cafe + customers
	local cafe = ui.pane(V.root, R.cafe.x, R.cafe.y)
	local cv = cafe_view.build(cafe, R.cafe.w, R.cafe.h, R.cafe.counter,
		{ mode = R.cafe.mode, decor = progress.data.decor, counter_h = 66, seat_scale = R.seat_scale })
	V.seats_pane = cv.seats
	gui.set_scale(V.seats_pane, V3(R.seat_scale, R.seat_scale, 1))
	for i = 1, config.SEATS do
		if s.seats[i] then build_seat(i, s.seats[i], false) end
	end

	build_board(R)

	-- shelf
	V.shelf = ui.pane(V.root, R.shelf.x, R.shelf.y, R.shelf.s)
	V.shelf_bg = ui.slice(V.shelf, "panel", 0, 0, 7 * SHELF_STEP + 20, 92, H("#4a2a1a", 0.16), 30)
	for i, id in ipairs(s.shelf) do make_tile(V.shelf, s.board.tiles[id], shelf_pos(i), SHELF_SCALE) end
	gui.set_enabled(V.shelf_bg, #s.shelf > 0)

	-- tray
	V.tray = ui.pane(V.root, R.tray.x, R.tray.y, R.tray.s)
	V.tray_bg = ui.slice(V.tray, "frame", 0, 0, config.SLOT_COUNT * TRAY_STEP + 26, 124, H("#b9784a"), 30)
	for i = 1, config.SLOT_COUNT do
		ui.slice(V.tray, "cell", (i - 4) * TRAY_STEP, 0, 86, 100, H("#f6e2c6"), 20)
	end
	for i, id in ipairs(s.slot) do make_tile(V.tray, s.board.tiles[id], tray_pos(i), TRAY_SCALE) end
	relayout_tray(0)

	-- boosters + bin
	local boost = ui.pane(V.root, R.boost.x, R.boost.y, R.boost.s)
	V.bin_icon = ui.box(boost, "bin", -262, 12, 92, 92)
	local pill = ui.slice(boost, "panel", -262, -50, 76, 38, H("#4a2a1a", 0.8), 18)
	V.bin_count = ui.text(pill, tostring(s.waste), 0, 1, 28)
	booster_button(boost, "undo", -88, ui.BLUE, "icon_undo", "UNDO")
	booster_button(boost, "shuffle", 72, ui.PURPLE, "icon_shuffle", "SHUFFLE")
	booster_button(boost, "rush", 232, ui.ORANGE, "icon_bolt", "RUSH")
	update_boosters()

	-- HUD
	local hud = ui.pane(V.root, vw / 2, R.hud_y)
	local half = vw / 2
	-- coins left (clear of the Poki pill), level between coins and pause
	local cp = ui.slice(hud, "panel", -half + 140, 0, 180, 58, H("#4a2a1a", 0.82), 28)
	V.coin_icon = ui.box(cp, "coin", -66, 0, 54, 54)
	V.coins_shown = progress.data.coins + s.coins
	V.coins_label = ui.text(cp, "", 18, 1, 32)
	coins_text()
	local lx = portrait and ((-half + 230) + (half - 100)) / 2 or 0
	local lp = ui.slice(hud, "panel", lx, 0, 250, 66, H("#4a2a1a", 0.82), 30)
	local lt = ui.text(lp, i18n.get("LEVEL", { n = s.level }), 0, 10, 30)
	ui.fit(lt, 230, 30)
	ui.slice(lp, "bar", 0, -18, 216, 16, H("#000000", 0.35), 6)
	V.progress_fill = ui.slice(lp, "bar", -105, -18, 10, 12, ui.GOLD, 5)
	gui.set_pivot(V.progress_fill, gui.PIVOT_W)
	update_progress()
	local pause = ui.box(hud, "btn_round", half - 60, 0, 78, 78, ui.ORANGE)
	ui.icon(pause, "icon_pause", 0, 3, 40)
	ui.button(pause, 90, 90, function() V.app.pause() end)

	-- fx layer on top
	V.fx = ui.pane(V.root, 0, 0)
	-- pointing hand: tutorial on level 1, idle hint afterwards
	V.tutorial = s.level == 1 and not progress.tip_seen("tutorial")
	V.idle = 0
	V.hand = ui.box(V.fx, "hand", 0, 0, 96, 96)
	ui.pulse(V.hand, 1.12, 0.5)
	if V.tutorial and not s.running then M.toast(i18n.get("TUT_1"), nil, 4) end
	update_hand()
end

function M.intro()
	local food = levels.new_food(V.s.level)
	if food and not V.tutorial then
		M.toast(i18n.get("NEW_DISH"), food_sprite(food), 2.4)
	end
end

function M.update(dt)
	if not V.s then return end
	update_patience()
	if V.s.status == "play" and not V.tutorial then
		local before = V.idle
		V.idle = V.idle + dt
		if before < HINT_IDLE and V.idle >= HINT_IDLE then update_hand() end
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
	for i, id in ipairs(s.shelf) do
		local tv = V.tiles[id]
		if tv then
			local p, sc = ui.world(tv.root)
			if math.abs(x - p.x) <= TILE_W * sc / 2 and math.abs(y - p.y) <= TILE_H * sc / 2 then
				return id
			end
		end
	end
	local bp, bs = ui.world(V.board)
	for _, t in ipairs(V.hit_order) do
		if t.where == "board" then
			local l = tile_local(t)
			local cx, cy = bp.x + l.x * bs, bp.y + (l.y + ICON_DY) * bs
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
