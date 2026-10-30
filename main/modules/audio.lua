-- Sound effects and music (components live on main:/sounds).
local M = {}

local URL = "main:/sounds#"
local sound_on = true
local music_on = true
local music_playing = false
local music_loaded = false
local last_played = {}
local clock = 0

function M.update(dt)
	clock = clock + dt
end

function M.play(name, gain, speed)
	if not sound_on then return end
	-- the same sound twice in one frame only adds volume and clipping
	if last_played[name] and clock - last_played[name] < 0.04 then return end
	last_played[name] = clock
	sound.play(URL .. name, { gain = gain or 1, speed = speed or 1 })
end

local function update_music()
	if not music_loaded then return end
	if music_on and not music_playing then
		sound.play(URL .. "music", { gain = 0.32 })
		music_playing = true
	elseif not music_on and music_playing then
		sound.stop(URL .. "music")
		music_playing = false
	end
end

function M.load_music()
	if music_loaded then return end
	music_loaded = true
	update_music()
end

function M.set(sound_enabled, music_enabled)
	sound_on = sound_enabled
	music_on = music_enabled
	update_music()
end

return M
