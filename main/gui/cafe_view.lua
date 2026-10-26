-- The cafe interior drawn from the bought decor tiers.
-- mode "strip": wall + counter only (portrait gameplay, customers in front of the wall)
-- mode "full":  wall, counter and floor with furniture (menu, landscape gameplay)
local ui = require "main.gui.ui"
local decor = require "main.modules.decor"

local M = {}

local V3 = vmath.vector3
local H = ui.hex

-- [tier] = wall color, pattern sprite, pattern color, awning color
local WALL = {
	[0] = { "#f6e3c9", "pat_stripes", "#f0d6b4", "#e07a5f" },
	[1] = { "#cdeccf", "pat_stripes", "#b6e2ba", "#3fa38a" },
	[2] = { "#ffdde3", "pat_dots", "#ffc3cf", "#ef6f8e" },
	[3] = { "#e6dbff", "pat_diamond", "#d2c2ff", "#8c6cf0" },
}
-- [tier] = front color, top plank color, panel line color
local COUNTER = {
	[0] = { "#c98a52", "#8a5228", "#ad6f3c" },
	[1] = { "#f4efe6", "#b8a690", "#ded5c6" },
	[2] = { "#8fd6c1", "#f6f1e7", "#73bfa9" },
	[3] = { "#ff9fb5", "#ffd36b", "#f0839c" },
}
-- [tier] = floor color, pattern sprite, pattern color
local FLOOR = {
	[0] = { "#d9b48a", nil, nil },
	[1] = { "#e9e2d6", "pat_checker", "#ffffff" },
	[2] = { "#d8a46e", "pat_planks", "#ecc08e" },
	[3] = { "#f6d3da", "pat_checker", "#ffffff" },
}

local function tiled(parent, sprite, cx, cy, w, h, cell, color)
	local nx, ny = math.ceil(w / cell), math.ceil(h / cell)
	local x0 = cx - nx * cell / 2 + cell / 2
	local y0 = cy + ny * cell / 2 - cell / 2
	for j = 0, ny - 1 do
		for i = 0, nx - 1 do
			ui.box(parent, sprite, x0 + i * cell, y0 - j * cell, cell + 1, cell + 1, color)
		end
	end
end

-- Builds the cafe into `parent` for a w x h region centered at the parent origin.
-- counter_y: local y of the counter top. Returns { seats = pane for customers }.
function M.build(parent, w, h, counter_y, opts)
	local owned = opts.decor or {}
	local t_wall = decor.tier(owned, "wall")
	local t_counter = decor.tier(owned, "counter")
	local t_lights = decor.tier(owned, "lights")
	local t_plants = decor.tier(owned, "plants")
	local t_floor = decor.tier(owned, "floor")
	local t_kitchen = decor.tier(owned, "kitchen")
	local full = opts.mode == "full"
	local top, bottom = h / 2, -h / 2
	local counter_h = opts.counter_h or 70

	-- clip everything to the region
	local root = ui.box(parent, nil, 0, 0, w, h, vmath.vector4(1, 1, 1, 1))
	gui.set_clipping_mode(root, gui.CLIPPING_MODE_STENCIL)
	gui.set_clipping_visible(root, false)

	-- wall
	local wall = WALL[t_wall]
	local wall_bottom = counter_y - 10
	local wall_h = top - wall_bottom
	ui.box(root, "square", 0, wall_bottom + wall_h / 2, w, wall_h, H(wall[1]))
	tiled(root, wall[2], 0, wall_bottom + wall_h / 2, w, wall_h, 72, H(wall[3]))
	ui.box(root, "square", 0, wall_bottom + 30, w, 60, H(wall[3], 0.6))
	ui.box(root, "square", 0, wall_bottom + 62, w, 6, H("#ffffff", 0.7))

	-- windows and wall decor
	local wy = math.min(counter_y + (full and 175 or 150), top - 120)
	if full then
		ui.icon(root, "window", -w * 0.28, wy, 220)
		ui.icon(root, "window", w * 0.06, wy, 220)
		if t_kitchen >= 1 then ui.icon(root, "menu_board", w * 0.32, wy + 10, 170) end
	else
		ui.icon(root, "window", -w * 0.16, wy + 10, 170)
		ui.icon(root, "window", w * 0.16, wy + 10, 170)
		if t_kitchen >= 1 then ui.icon(root, "menu_board", w * 0.5 - 70, wy + 20, 110) end
	end
	if t_plants >= 3 then
		ui.icon(root, "plant_hang", -w / 2 + 70, top - 120, 130)
		ui.icon(root, "plant_hang", w / 2 - 70, top - 120, 130)
	end

	-- lights
	if t_lights >= 1 then
		local xs = t_lights >= 2 and { -w * 0.3, 0, w * 0.3 } or { -w * 0.17, w * 0.17 }
		for _, x in ipairs(xs) do
			local glow = ui.box(root, "glow", x, top - (full and 190 or 150), 220, 220, H("#ffe9a8", 0.45))
			ui.icon(root, "lamp", x, top - (full and 110 or 70), full and 130 or 105)
			if opts.animate then ui.pulse(glow, 1.06, 1.4) end
		end
	end
	-- awning
	local seg = 96
	local n = math.ceil(w / seg) + 1
	for i = 0, n - 1 do
		ui.box(root, "awning", -n * seg / 2 + seg / 2 + i * seg, top - 26, seg + 1, 64, H(wall[4]))
	end
	if t_lights >= 3 then
		local gn = math.ceil(w / 256) + 1
		for i = 0, gn - 1 do
			ui.box(root, "garland", -gn * 128 + 128 + i * 256, top - 80, 256, 64)
		end
	end

	-- customers stand behind the counter
	local seats = ui.pane(root, 0, counter_y)

	-- floor (full mode)
	local floor_top = counter_y - counter_h
	if full and floor_top > bottom then
		local fl = FLOOR[t_floor]
		local fh = floor_top - bottom
		ui.box(root, "square", 0, bottom + fh / 2, w, fh, H(fl[1]))
		if fl[2] then tiled(root, fl[2], 0, bottom + fh / 2, w, fh, 64, H(fl[3], 0.55)) end
		ui.box(root, "square", 0, floor_top - 4, w, 8, H("#000000", 0.12))
		local fy = floor_top - math.min(fh * 0.45, 150)
		local tsize = math.min(190, fh * 1.1)
		ui.icon(root, "table", -w * 0.28, fy, tsize)
		if t_floor >= 2 then ui.icon(root, "table", w * 0.08, fy - 6, tsize) end
		if t_plants >= 2 then ui.icon(root, "plant_big", w / 2 - 80, floor_top - 90, 220) end
	end

	-- counter
	local cc = COUNTER[t_counter]
	local front_bottom = full and (counter_y - counter_h) or bottom
	local fh = counter_y - front_bottom
	ui.box(root, "square", 0, front_bottom + fh / 2, w, fh, H(cc[1]))
	local step = 150
	local k = math.ceil(w / step)
	for i = 0, k do
		local x = -k * step / 2 + i * step
		ui.box(root, "square", x, front_bottom + fh / 2 - 6, 6, fh - 30, H(cc[3]))
	end
	ui.box(root, "square", 0, counter_y - 3, w, 22, H(cc[2]))
	ui.box(root, "square", 0, counter_y - 16, w, 5, H("#000000", 0.15))

	-- things on the counter (in front of the customers)
	local ty = counter_y + 6
	if t_counter >= 1 then
		local m = ui.icon(root, "coffee_machine", full and -w * 0.36 or -w / 2 + 52, ty + 44, full and 120 or 92)
		gui.set_pivot(m, gui.PIVOT_CENTER)
	end
	if t_kitchen >= 2 then ui.icon(root, "cake_display", full and w * 0.36 or w / 2 - 62, ty + 40, full and 150 or 112) end
	if t_kitchen >= 3 and full then ui.icon(root, "cake_display", w * 0.18, ty + 40, 130) end
	-- strip mode: plants go into the gaps between the customers
	if t_plants >= 1 then
		ui.icon(root, "plant_small", full and -w * 0.2 or -105 * opts.seat_scale, ty + 30, full and 90 or 64)
	end
	if t_plants >= 2 and not full then ui.icon(root, "plant_small", 105 * opts.seat_scale, ty + 30, 64) end

	return { root = root, seats = seats }
end

return M
