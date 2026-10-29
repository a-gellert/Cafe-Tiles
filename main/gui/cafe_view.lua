-- The cafe interior drawn from the bought decor tiers.
-- mode "strip": wall + counter only (portrait gameplay, customers in front of the wall)
-- mode "full":  wall, counter and floor with furniture (menu, decor shop, landscape gameplay)
-- build() also records which nodes belong to which decor item, so a purchase can be
-- revealed with an animation (M.reveal).
local ui = require "main.gui.ui"
local decor = require "main.modules.decor"

local M = {}

local V3 = vmath.vector3
local H = ui.hex

-- [tier] = wall color, pattern sprite, pattern color, awning color
local WALL = {
	[0] = { "#fde7e3", "pat_stripes", "#f8d7d3", "#f58aa6" },
	[1] = { "#d9f3e7", "pat_stripes", "#c4ead8", "#43b892" },
	[2] = { "#ffdfea", "pat_dots", "#ffc8da", "#ef6f9a" },
	[3] = { "#ebe0fe", "pat_diamond", "#d9c8ff", "#9a7cf0" },
}
-- [tier] = front color, top plank color, panel line color
local COUNTER = {
	[0] = { "#e2a68a", "#a7664c", "#d1937a" },
	[1] = { "#fbf5ef", "#c9b4a5", "#ece0d6" },
	[2] = { "#a4e3cf", "#fbf5ef", "#86d0b9" },
	[3] = { "#ffb0c4", "#ffd36b", "#f293ad" },
}
-- [tier] = floor color, pattern sprite, pattern color
local FLOOR = {
	[0] = { "#ecc9b6", nil, nil },
	[1] = { "#f3ebe4", "pat_checker", "#ffffff" },
	[2] = { "#e2b190", "pat_planks", "#f0c9a8" },
	[3] = { "#fbd9e2", "pat_checker", "#ffffff" },
}

local function tiled(parent, sprite, cx, cy, w, h, cell, color, list)
	local nx, ny = math.ceil(w / cell), math.ceil(h / cell)
	local x0 = cx - nx * cell / 2 + cell / 2
	local y0 = cy + ny * cell / 2 - cell / 2
	for j = 0, ny - 1 do
		for i = 0, nx - 1 do
			local n = ui.box(parent, sprite, x0 + i * cell, y0 - j * cell, cell + 1, cell + 1, color)
			if list then list[#list + 1] = n end
		end
	end
end

-- Builds the cafe into `parent` for a w x h region centered at the parent origin.
-- counter_y: local y of the counter top.
-- Returns { root, seats = pane for customers, items = { [id] = { paint = {}, pop = {} } } }:
-- "paint" nodes are surfaces (wall, floor, counter), "pop" nodes are objects.
function M.build(parent, w, h, counter_y, opts)
	local owned = opts.decor or {}
	local t_wall = decor.tier(owned, "wall")
	local t_counter = decor.tier(owned, "counter")
	local t_lights = decor.tier(owned, "lights")
	local t_plants = decor.tier(owned, "plants")
	local t_floor = decor.tier(owned, "floor")
	local t_kitchen = decor.tier(owned, "kitchen")
	local t_flowers = decor.tier(owned, "flowers")
	local full = opts.mode == "full"
	local top, bottom = h / 2, -h / 2
	local counter_h = opts.counter_h or 70

	local items = {}
	for _, it in ipairs(decor.ITEMS) do items[it.id] = { paint = {}, pop = {} } end
	local function pop(id, n)
		local l = items[id].pop
		l[#l + 1] = n
		return n
	end
	local function paint(id, n)
		local l = items[id].paint
		l[#l + 1] = n
		return n
	end

	-- clip everything to the region
	local root = ui.box(parent, nil, 0, 0, w, h, vmath.vector4(1, 1, 1, 1))
	gui.set_clipping_mode(root, gui.CLIPPING_MODE_STENCIL)
	gui.set_clipping_visible(root, false)

	-- wall
	local wall = WALL[t_wall]
	local wall_bottom = counter_y - 10
	local wall_h = top - wall_bottom
	paint("wall", ui.box(root, "square", 0, wall_bottom + wall_h / 2, w, wall_h, H(wall[1])))
	tiled(root, wall[2], 0, wall_bottom + wall_h / 2, w, wall_h, 72, H(wall[3]), items.wall.paint)
	ui.box(root, "square", 0, wall_bottom + 30, w, 60, H(wall[3], 0.6))
	ui.box(root, "square", 0, wall_bottom + 62, w, 6, H("#ffffff", 0.7))

	-- windows and wall decor
	local wy = math.min(counter_y + (full and 175 or 150), top - 120)
	local windows = full and { { -w * 0.28, wy, 220 }, { w * 0.06, wy, 220 } }
		or { { -w * 0.16, wy + 10, 170 }, { w * 0.16, wy + 10, 170 } }
	for _, wnd in ipairs(windows) do
		ui.icon(root, "window", wnd[1], wnd[2], wnd[3])
		-- flower boxes under the windows
		if t_flowers >= 2 then pop("flowers", ui.icon(root, "flower_box", wnd[1], wnd[2] - wnd[3] * 0.47, wnd[3] * 0.92)) end
	end
	if t_kitchen >= 1 then
		if full then
			pop("kitchen", ui.icon(root, "menu_board", w * 0.32, wy + 10, 170))
		else
			pop("kitchen", ui.icon(root, "menu_board", w * 0.5 - 70, wy + 20, 110))
		end
	end
	if t_plants >= 3 then
		pop("plants", ui.icon(root, "plant_hang", -w / 2 + 70, top - 120, 130))
		pop("plants", ui.icon(root, "plant_hang", w / 2 - 70, top - 120, 130))
	end

	-- lights
	if t_lights >= 1 then
		local xs = t_lights >= 2 and { -w * 0.3, 0, w * 0.3 } or { -w * 0.17, w * 0.17 }
		for _, x in ipairs(xs) do
			-- the glow keeps its own pulse: not in the reveal list
			local glow = ui.box(root, "glow", x, top - (full and 190 or 150), 220, 220, H("#ffe9a8", 0.45))
			pop("lights", ui.icon(root, "lamp", x, top - (full and 110 or 70), full and 130 or 105))
			if opts.animate then ui.pulse(glow, 1.06, 1.4) end
		end
	end
	-- awning
	local seg = 96
	local n = math.ceil(w / seg) + 1
	for i = 0, n - 1 do
		paint("wall", ui.box(root, "awning", -n * seg / 2 + seg / 2 + i * seg, top - 26, seg + 1, 64, H(wall[4])))
	end
	local gn = math.ceil(w / 256) + 1
	if t_flowers >= 3 then
		for i = 0, gn - 1 do pop("flowers", ui.box(root, "flower_garland", -gn * 128 + 128 + i * 256, top - 66, 256, 64)) end
	end
	if t_lights >= 3 then
		local gy = t_flowers >= 3 and top - 98 or top - 80
		for i = 0, gn - 1 do
			local g = pop("lights", ui.box(root, "garland", -gn * 128 + 128 + i * 256, gy, 256, 64))
			if opts.animate then
				gui.animate(g, "color.w", 0.75, gui.EASING_INOUTSINE, 0.8 + i * 0.13, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
			end
		end
	end

	-- customers stand behind the counter
	local seats = ui.pane(root, 0, counter_y)

	-- floor (full mode)
	local floor_top = counter_y - counter_h
	if full and floor_top > bottom then
		local fl = FLOOR[t_floor]
		local fh = floor_top - bottom
		paint("floor", ui.box(root, "square", 0, bottom + fh / 2, w, fh, H(fl[1])))
		if fl[2] then tiled(root, fl[2], 0, bottom + fh / 2, w, fh, 64, H(fl[3], 0.55), items.floor.paint) end
		ui.box(root, "square", 0, floor_top - 4, w, 8, H("#000000", 0.12))
		local fy = floor_top - math.min(fh * 0.45, 150)
		local tsize = math.min(190, fh * 1.1)
		pop("floor", ui.icon(root, "table", -w * 0.28, fy, tsize))
		if t_floor >= 2 then pop("floor", ui.icon(root, "table", w * 0.08, fy - 6, tsize)) end
		if t_plants >= 2 then pop("plants", ui.icon(root, "plant_big", w / 2 - 80, floor_top - 90, 220)) end
	end

	-- counter
	local cc = COUNTER[t_counter]
	local front_bottom = full and (counter_y - counter_h) or bottom
	local fh = counter_y - front_bottom
	paint("counter", ui.box(root, "square", 0, front_bottom + fh / 2, w, fh, H(cc[1])))
	local step = 150
	local k = math.ceil(w / step)
	for i = 0, k do
		local x = -k * step / 2 + i * step
		paint("counter", ui.box(root, "square", x, front_bottom + fh / 2 - 6, 6, fh - 30, H(cc[3])))
	end
	paint("counter", ui.box(root, "square", 0, counter_y - 3, w, 22, H(cc[2])))
	ui.box(root, "square", 0, counter_y - 16, w, 5, H("#000000", 0.15))

	-- things on the counter (in front of the customers)
	local ty = counter_y + 6
	if t_counter >= 1 then
		local m = pop("counter", ui.icon(root, "coffee_machine", full and -w * 0.36 or -w / 2 + 52, ty + 44, full and 120 or 92))
		gui.set_pivot(m, gui.PIVOT_CENTER)
	end
	if t_kitchen >= 2 then pop("kitchen", ui.icon(root, "cake_display", full and w * 0.36 or w / 2 - 62, ty + 40, full and 150 or 112)) end
	if t_kitchen >= 3 and full then pop("kitchen", ui.icon(root, "cake_display", w * 0.18, ty + 40, 130)) end
	-- strip mode: plants and flowers go into the gaps between the customers
	if t_plants >= 1 then
		pop("plants", ui.icon(root, "plant_small", full and -w * 0.2 or -105 * opts.seat_scale, ty + 30, full and 90 or 64))
	end
	if t_flowers >= 1 then
		pop("flowers", ui.icon(root, "vase", full and w * 0.1 or 105 * opts.seat_scale, ty + (full and 40 or 32), full and 104 or 74))
	elseif t_plants >= 2 and not full then
		pop("plants", ui.icon(root, "plant_small", 105 * opts.seat_scale, ty + 30, 64))
	end

	return { root = root, seats = seats, items = items }
end

-- A just-bought tier appears: surfaces repaint in a wave from the middle (big ones flash
-- white), objects pop in one by one with sparkles. Returns the time it takes.
function M.reveal(cv, id)
	local it = cv.items[id]
	if not it then return 0 end
	local last = 0
	for _, n in ipairs(it.paint) do
		local size = gui.get_size(n)
		if size.x > 200 or size.y > 200 then
			local c = gui.get_color(n)
			gui.set_color(n, vmath.vector4(1, 1, 1, c.w))
			gui.animate(n, "color", c, gui.EASING_OUTQUAD, 0.7, 0.1)
		else
			local p = gui.get_position(n)
			local delay = math.sqrt(p.x * p.x + p.y * p.y) * 0.0011
			local s = gui.get_scale(n)
			gui.set_scale(n, V3(0.01, 0.01, 1))
			gui.animate(n, "scale", s, gui.EASING_OUTBACK, 0.35, delay)
			last = math.max(last, delay + 0.35)
		end
	end
	for k, n in ipairs(it.pop) do
		local s = gui.get_scale(n)
		local delay = 0.15 + (k - 1) * 0.12
		gui.set_scale(n, V3(0.01, 0.01, 1))
		gui.animate(n, "scale", s, gui.EASING_OUTBACK, 0.45, delay)
		local p = gui.get_position(n)
		ui.after(delay + 0.12, function()
			ui.burst(cv.root, p.x, p.y, 10, nil, 120)
			ui.ring(cv.root, p.x, p.y, 220, ui.WHITE, 0.4)
		end)
		last = math.max(last, delay + 0.45)
	end
	return last
end

-- Small sample of a decor tier for shop cards and goals: a paint chip for the wallpaper,
-- the counter and the floor, the item sprite for the rest.
function M.swatch(parent, id, tier, x, y, size)
	local chip
	if id == "wall" or id == "counter" or id == "floor" then
		chip = ui.box(parent, "square", x, y, size, size, ui.WHITE)
		local s = size - 8
		if id == "wall" then
			local c = WALL[tier]
			ui.box(chip, "square", 0, 0, s, s, H(c[1]))
			tiled(chip, c[2], 0, 0, s, s, s / 2, H(c[3]))
			ui.box(chip, "awning", 0, s / 2 - s * 0.12, s, s * 0.24, H(c[4]))
		elseif id == "counter" then
			local c = COUNTER[tier]
			ui.box(chip, "square", 0, 0, s, s, H(c[1]))
			ui.box(chip, "square", -s / 4, -s * 0.08, 4, s * 0.6, H(c[3]))
			ui.box(chip, "square", s / 4, -s * 0.08, 4, s * 0.6, H(c[3]))
			ui.box(chip, "square", 0, s / 2 - s * 0.1, s, s * 0.2, H(c[2]))
		else
			local c = FLOOR[tier]
			ui.box(chip, "square", 0, 0, s, s, H(c[1]))
			if c[2] then tiled(chip, c[2], 0, 0, s, s, s / 2, H(c[3], 0.55)) end
		end
		return chip
	end
	return ui.icon(parent, decor.item(id).icon, x, y, size)
end

return M
