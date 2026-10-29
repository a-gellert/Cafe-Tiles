-- GUI helpers: node factories, buttons with hit testing, tweens and particles.
-- All nodes are created from code in virtual units (see main/modules/layout.lua).
local audio = require "main.modules.audio"
local sizes = require "main.gui.sprite_sizes"

local M = {}

local V3 = vmath.vector3

M.TEX = "game"
M.FONT = "main"
M.FONT_SIZE = 44

function M.hex(s, a)
	local v = tonumber(string.sub(s, 2), 16)
	return vmath.vector4(math.floor(v / 65536) / 255, math.floor(v / 256) % 256 / 255, v % 256 / 255, a or 1)
end

-- warm coffee-house palette for everyone: cream, caramel wood, teal, terracotta, espresso
M.WHITE = vmath.vector4(1, 1, 1, 1)
M.INK = M.hex("#3d2b22")       -- espresso: text outlines and dark text
M.COCOA = M.hex("#47362c")     -- HUD pills (with alpha)
M.CREAM = M.hex("#fff8ee")
M.ORANGE = M.hex("#ff8c42")    -- main call to action
M.PEACH = M.hex("#ffb15c")
M.GREEN = M.hex("#35c493")
M.BLUE = M.hex("#4da3f0")
M.TEAL = M.hex("#2fb0a3")      -- ribbons, banners, calm accents
M.CORAL = M.hex("#ef6f5e")     -- hard levels, alerts
M.PURPLE = M.hex("#8270ee")
M.MINT = M.hex("#7fe3c4")
M.GOLD = M.hex("#ffd23f")
M.GREY = M.hex("#b5a99d")
M.DIM = vmath.vector4(0.74, 0.69, 0.64, 1)
-- sparkle colours for bursts: warm light with a few cool glints
M.CANDY = { M.hex("#ffd23f"), M.hex("#ffb36b"), M.hex("#ffffff"), M.hex("#9fe8ff"), M.hex("#a8f0c8"), M.hex("#ffe9b0") }

-- generation counter: delayed callbacks from a torn-down screen are dropped
M.gen = 0
M.popup_gen = 0     -- bumped when a popup closes (app.close_popup)
M.buttons = {}
M.layer = "screen"

-- ---------------------------------------------------------------- nodes

function M.pane(parent, x, y, s)
	local n = gui.new_box_node(V3(x or 0, y or 0, 0), V3(1, 1, 0))
	gui.set_visible(n, false)
	if s then gui.set_scale(n, V3(s, s, 1)) end
	if parent then gui.set_parent(n, parent) end
	return n
end

function M.box(parent, sprite, x, y, w, h, color)
	local n = gui.new_box_node(V3(x, y, 0), V3(w, h, 0))
	if sprite then
		gui.set_texture(n, M.TEX)
		gui.play_flipbook(n, sprite)
	end
	gui.set_color(n, color or M.WHITE)
	gui.set_inherit_alpha(n, true)
	if parent then gui.set_parent(n, parent) end
	return n
end

function M.slice(parent, sprite, x, y, w, h, color, border)
	local n = M.box(parent, sprite, x, y, w, h, color)
	gui.set_slice9(n, vmath.vector4(border, border, border, border))
	return n
end

function M.text(parent, str, x, y, size, color, outline)
	local n = gui.new_text_node(V3(x, y, 0), str)
	gui.set_font(n, M.FONT)
	gui.set_line_break(n, true)
	gui.set_size(n, V3(3000, 200, 0))
	local s = size / M.FONT_SIZE
	gui.set_scale(n, V3(s, s, 1))
	gui.set_color(n, color or M.WHITE)
	gui.set_outline(n, outline or M.INK)
	gui.set_shadow(n, vmath.vector4(0, 0, 0, 0))
	gui.set_inherit_alpha(n, true)
	if parent then gui.set_parent(n, parent) end
	return n
end

-- Unscaled width of the widest line of a text node.
function M.text_width(n)
	M.font_res = M.font_res or gui.get_font_resource(M.FONT)
	local w = 0
	for line in string.gmatch(gui.get_text(n) .. "\n", "([^\n]*)\n") do
		if line ~= "" then w = math.max(w, resource.get_text_metrics(M.font_res, line).width) end
	end
	return w
end

-- Scales a text node down so it fits max_w (parent units).
function M.fit(n, max_w, size)
	local s = size / M.FONT_SIZE
	local w = M.text_width(n)
	if w * s > max_w and w > 0 then s = max_w / w end
	gui.set_scale(n, V3(s, s, 1))
end

function M.set_text(n, str, max_w, size)
	gui.set_text(n, str)
	if max_w then M.fit(n, max_w, size) end
end

-- Fits a sprite of the atlas into a w x h box keeping its aspect.
function M.icon(parent, sprite, x, y, size, color)
	local wh = sizes[sprite] or { 1, 1 }
	local k = size / math.max(wh[1], wh[2])
	return M.box(parent, sprite, x, y, wh[1] * k, wh[2] * k, color)
end

function M.delete(n)
	if n then gui.delete_node(n) end
end

-- ---------------------------------------------------------------- transforms

-- Scene position and uniform scale of a node (rotation ignored).
function M.world(n)
	local p = gui.get_position(n)
	local s = gui.get_scale(n).x
	local parent = gui.get_parent(n)
	while parent do
		local ps = gui.get_scale(parent).x
		p = gui.get_position(parent) + p * ps
		s = s * ps
		parent = gui.get_parent(parent)
	end
	return p, s
end

-- Scene point -> local point of `parent`
function M.to_local(parent, p)
	local pp, ps = M.world(parent)
	return (p - pp) * (1 / ps)
end

-- ---------------------------------------------------------------- buttons

-- Registers a tappable node. `w`, `h` are the hit size in the node's own units.
function M.button(node, w, h, fn, opts)
	local b = { node = node, w = w, h = h, fn = fn, layer = M.layer, silent = opts and opts.silent }
	M.buttons[#M.buttons + 1] = b
	return b
end

function M.remove_buttons(layer)
	for i = #M.buttons, 1, -1 do
		if M.buttons[i].layer == layer then table.remove(M.buttons, i) end
	end
end

local function hit(b, x, y)
	if b.disabled or not gui.is_enabled(b.node, true) then return false end
	local p, s = M.world(b.node)
	return math.abs(x - p.x) <= b.w * s / 2 and math.abs(y - p.y) <= b.h * s / 2
end

function M.find_button(x, y, layer)
	for i = #M.buttons, 1, -1 do
		local b = M.buttons[i]
		if b.layer == layer and hit(b, x, y) then return b end
	end
end

function M.press(b)
	b.base_scale = b.base_scale or gui.get_scale(b.node).x
	local s = b.base_scale * 0.9
	gui.animate(b.node, "scale", V3(s, s, 1), gui.EASING_OUTQUAD, 0.06)
end

function M.release(b, fire)
	if b.base_scale then
		local s = b.base_scale
		gui.animate(b.node, "scale", V3(s, s, 1), gui.EASING_OUTBACK, 0.18)
	end
	if fire then
		if not b.silent then audio.play("button") end
		b.fn(b)
	end
end

-- ---------------------------------------------------------------- tweens & fx

-- Runs fn later unless the screen was rebuilt meanwhile. Callbacks made while a popup is
-- built die with that popup too: a popup closes without a rebuild (Continue -> tasks,
-- x2, a child popup), and its nodes are gone (Poki error reports: "Deleted node" in pop).
function M.after(delay, fn)
	local g = M.gen
	local pg = M.layer == "popup" and M.popup_gen
	timer.delay(delay, false, function()
		if g == M.gen and (not pg or pg == M.popup_gen) then fn() end
	end)
end

function M.pop(n, from, to, dur, delay)
	gui.set_scale(n, V3(from, from, 1))
	gui.animate(n, "scale", V3(to, to, 1), gui.EASING_OUTBACK, dur or 0.3, delay or 0)
end

function M.fade(n, from, to, dur, delay, done)
	local c = gui.get_color(n)
	c.w = from
	gui.set_color(n, c)
	gui.animate(n, "color.w", to, gui.EASING_OUTQUAD, dur, delay or 0, done and function() done() end or nil)
end

function M.pulse(n, k, period)
	local s = gui.get_scale(n).x
	gui.animate(n, "scale", V3(s * k, s * k, 1), gui.EASING_INOUTSINE, period or 0.6, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
end

function M.shake(n, amount)
	gui.cancel_animations(n, "euler.z")
	gui.set_euler(n, V3(0, 0, amount))
	gui.animate(n, "euler.z", 0, gui.EASING_OUTELASTIC, 0.5)
end

-- additive blending: glows and sparkles light up what is under them
function M.glow(n)
	gui.set_blend_mode(n, gui.BLEND_ADD)
	return n
end

local function candy()
	return M.CANDY[math.random(#M.CANDY)]
end

-- Sparkle burst at a point of `parent`. color = nil: mixed candy colours.
function M.burst(parent, x, y, count, color, spread, size)
	for _ = 1, count do
		local s = (size or 34) * (0.7 + math.random() * 0.6)
		local n = M.glow(M.box(parent, "spark", x, y, s, s, color or candy()))
		local a = math.random() * math.pi * 2
		local d = (spread or 80) * (0.45 + math.random() * 0.55)
		local dur = 0.35 + math.random() * 0.3
		gui.set_euler(n, V3(0, 0, math.random(0, 90)))
		gui.animate(n, "position", V3(x + math.cos(a) * d, y + math.sin(a) * d, 0), gui.EASING_OUTCUBIC, dur)
		gui.animate(n, "euler.z", math.random(-120, 120), gui.EASING_OUTQUAD, dur)
		gui.animate(n, "color.w", 0, gui.EASING_INQUAD, dur, 0, function() gui.delete_node(n) end)
	end
end

-- Expanding soft ring (shockwave)
function M.ring(parent, x, y, size, color, dur)
	local n = M.glow(M.box(parent, "ring", x, y, size * 0.3, size * 0.3, color or M.WHITE))
	gui.animate(n, "size", V3(size, size, 0), gui.EASING_OUTCUBIC, dur or 0.4)
	gui.animate(n, "color.w", 0, gui.EASING_INQUAD, dur or 0.4, 0, function() gui.delete_node(n) end)
end

-- A soft additive flash of light that swells and fades
function M.flash_light(parent, x, y, size, color, dur)
	local n = M.glow(M.box(parent, "glow", x, y, size * 0.4, size * 0.4, color or M.hex("#fff1c4", 0.9)))
	gui.animate(n, "size", V3(size, size, 0), gui.EASING_OUTCUBIC, dur or 0.45)
	gui.animate(n, "color.w", 0, gui.EASING_INQUAD, dur or 0.45, 0, function() gui.delete_node(n) end)
	return n
end

-- Little hearts floating up and fading
function M.hearts(parent, x, y, count, spread)
	for k = 1, count do
		local s = 26 + math.random() * 18
		local n = M.box(parent, "heart_w", x + math.random(-spread, spread), y, s, s,
			k % 2 == 0 and M.hex("#ff8a6b") or M.hex("#ff5f5f"))
		local dur = 0.8 + math.random() * 0.4
		local d = 0.05 * k
		gui.set_scale(n, V3(0.2, 0.2, 1))
		gui.animate(n, "scale", V3(1, 1, 1), gui.EASING_OUTBACK, 0.25, d)
		gui.animate(n, "position.y", y + 90 + math.random() * 50, gui.EASING_OUTQUAD, dur, d)
		gui.animate(n, "position.x", x + math.random(-spread, spread) * 1.4, gui.EASING_INOUTSINE, dur, d)
		gui.animate(n, "color.w", 0, gui.EASING_INQUAD, dur * 0.6, d + dur * 0.4, function() gui.delete_node(n) end)
	end
end

-- Text that pops, rises and fades (praise words, +coins)
function M.float_text(parent, str, x, y, size, color, outline, rise)
	local n = M.text(parent, str, x, y, size, color, outline)
	M.pop(n, 0.3, 1, 0.3)
	gui.animate(n, "position.y", y + (rise or 70), gui.EASING_OUTQUAD, 0.9, 0.15)
	gui.animate(n, "color.w", 0, gui.EASING_INQUAD, 0.35, 0.7, function() gui.delete_node(n) end)
	return n
end

-- Confetti falling over a w x h area of `parent` (origin at the bottom left)
function M.confetti(parent, w, h, count)
	for _ = 1, count do
		local x = math.random() * w
		local round = math.random() < 0.3
		local cw, ch = 12 + math.random() * 8, 18 + math.random() * 10
		if round then ch = cw end
		local n = M.box(parent, round and "btn_round" or "bar", x, h + 30 + math.random() * 120, cw, ch, candy())
		local dur = 1.6 + math.random() * 1.2
		gui.set_euler(n, V3(0, 0, math.random(0, 360)))
		gui.animate(n, "position.y", -40, gui.EASING_INSINE, dur, math.random() * 0.4)
		gui.animate(n, "position.x", x + math.random(-120, 120), gui.EASING_INOUTSINE, dur)
		gui.animate(n, "euler.z", math.random(-720, 720), gui.EASING_LINEAR, dur, 0, function() gui.delete_node(n) end)
	end
end

-- Moves a node to `to` (local to its parent) along a curve: x and y use different easings.
-- trail: sparkle colour left along the way (nil = none).
function M.fly(n, to, dur, delay, done, trail)
	delay = delay or 0
	gui.animate(n, "position.x", to.x, gui.EASING_INOUTSINE, dur, delay)
	gui.animate(n, "position.y", to.y, gui.EASING_OUTQUAD, dur, delay, done and function() done() end or nil)
	if trail then
		local parent = gui.get_parent(n)
		for k = 1, 4 do
			M.after(delay + dur * k / 5, function()
				local p = gui.get_position(n)
				M.burst(parent, p.x, p.y, 1, trail, 14, 26)
			end)
		end
	end
end

-- Slow ambient particles (warm bokeh and twinkling motes drifting up) over a w x h area; loops forever.
function M.ambient(parent, w, h, count)
	for k = 1, count do
		local mote = k % 3 == 0
		local s = mote and (16 + math.random() * 14) or (30 + math.random() * 60)
		local x = math.random() * w
		local n = M.box(parent, mote and "spark" or "puff", x, -s, s, s,
			mote and M.hex("#fff3d6", 0.8) or M.hex(k % 2 == 0 and "#ffffff" or "#ffe6c2", 0.35))
		if mote then
			M.glow(n)
			gui.animate(n, "color.w", 0.2, gui.EASING_INOUTSINE, 0.8 + math.random() * 0.8, math.random(), nil, gui.PLAYBACK_LOOP_PINGPONG)
		end
		local dur = 9 + math.random() * 8
		-- the first rise starts part-way up, so the screen is never empty
		local f = math.random()
		gui.set_position(n, V3(x, -s + (h + 2 * s) * f, 0))
		gui.animate(n, "position.y", h + s, gui.EASING_LINEAR, dur * (1 - f), 0, function()
			gui.set_position(n, V3(x, -s, 0))
			gui.animate(n, "position.y", h + s, gui.EASING_LINEAR, dur, 0, nil, gui.PLAYBACK_LOOP_FORWARD)
		end)
		gui.animate(n, "position.x", x + math.random(-40, 40), gui.EASING_INOUTSINE, 2.5 + math.random() * 2, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
	end
end

return M
