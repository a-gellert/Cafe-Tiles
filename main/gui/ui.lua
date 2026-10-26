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

M.WHITE = vmath.vector4(1, 1, 1, 1)
M.INK = M.hex("#4a2a1a")
M.CREAM = M.hex("#fff6e5")
M.ORANGE = M.hex("#ff8a3d")
M.GREEN = M.hex("#3fbf6a")
M.BLUE = M.hex("#3a9dff")
M.PINK = M.hex("#ff6f91")
M.PURPLE = M.hex("#9b6cff")
M.GOLD = M.hex("#ffd23f")
M.GREY = M.hex("#9a8f86")
M.DIM = vmath.vector4(0.62, 0.6, 0.66, 1)

-- generation counter: delayed callbacks from a torn-down screen are dropped
M.gen = 0
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

function M.after(delay, fn)
	local g = M.gen
	timer.delay(delay, false, function()
		if g == M.gen then fn() end
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

-- Sparkle burst at a point of `parent`
function M.burst(parent, x, y, count, color, spread, size)
	for _ = 1, count do
		local n = M.box(parent, "spark", x, y, size or 34, size or 34, color or M.GOLD)
		local a = math.random() * math.pi * 2
		local d = (spread or 80) * (0.45 + math.random() * 0.55)
		local dur = 0.35 + math.random() * 0.25
		gui.animate(n, "position", V3(x + math.cos(a) * d, y + math.sin(a) * d, 0), gui.EASING_OUTQUAD, dur)
		gui.animate(n, "color.w", 0, gui.EASING_INQUAD, dur, 0, function() gui.delete_node(n) end)
	end
end

-- Moves a node to `to` (local to its parent) along an arc, then calls done.
function M.fly(n, to, dur, delay, done, easing)
	gui.animate(n, "position", to, easing or gui.EASING_INOUTQUAD, dur, delay or 0, done and function() done() end or nil)
end

return M
