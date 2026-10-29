-- Poki SDK wrapper: gameplay events, commercial breaks, rewarded breaks and
-- analytics. Works as a no-op outside the HTML5 build (poki_sdk is not registered).
local M = {}

local gameplay = false
local ad_active = false

-- No commercial break before this level: the first minutes teach the game ad-free.
-- Frequency after that is Poki's call (requirements: no internal ad timers).
M.FIRST_BREAK_LEVEL = 5

local function sdk()
	return rawget(_G, "poki_sdk")
end

function M.available()
	return sdk() ~= nil
end

function M.is_ad_active()
	return ad_active
end

function M.gameplay_start()
	if gameplay or ad_active then return end
	gameplay = true
	local s = sdk()
	if s and s.gameplay_start then s.gameplay_start() end
end

function M.gameplay_stop()
	if not gameplay then return end
	gameplay = false
	local s = sdk()
	if s and s.gameplay_stop then s.gameplay_stop() end
end

function M.measure(category, what, action)
	local s = sdk()
	if s and s.measure then pcall(s.measure, category, tostring(what), action) end
end

-- Natural break before the next gameplay (level start / retry). Skipped on the
-- first levels; Poki throttles the rest itself.
function M.commercial_break(level, on_done)
	local s = sdk()
	if not (s and s.commercial_break) or level < M.FIRST_BREAK_LEVEL then
		if on_done then on_done() end
		return
	end
	M.gameplay_stop()
	ad_active = true
	local done = false
	s.commercial_break(function(_, status)
		if status == s.COMMERCIAL_BREAK_START then
			ad_active = true
		elseif not done then
			done = true
			ad_active = false
			if on_done then on_done() end
		end
	end)
end

-- Rewarded video. on_done(success). Outside Poki the reward is granted at once
-- (desktop builds and local testing).
function M.rewarded(size, on_done)
	local s = sdk()
	if not (s and s.rewarded_break) then
		if on_done then on_done(true) end
		return
	end
	M.gameplay_stop()
	ad_active = true
	local done = false
	s.rewarded_break(size or "small", function(_, status)
		if status == s.REWARDED_BREAK_START then
			ad_active = true
		elseif not done then
			done = true
			ad_active = false
			if on_done then on_done(status == s.REWARDED_BREAK_SUCCESS) end
		end
	end)
end

function M.open_link(url)
	local s = sdk()
	if s and s.open_external_link then
		s.open_external_link(url)
	elseif sys.open_url then
		sys.open_url(url)
	end
end

return M
