-- Chef's tasks: MISSION_SLOTS active missions with coin (and every 3rd a booster) rewards.
-- State lives in progress.data.missions = { list = {...}, done = n, serial = n }.
-- Pure Lua: no Defold API (math.random is fine here, missions are not part of level determinism).
local config = require "main.modules.config"
local levels = require "main.modules.levels"

local M = {}

M.KINDS = { "serve", "food", "levels", "stars3", "vip", "showcase", "gold" }
local BOOSTERS = { "undo", "shuffle", "rush" }

-- goals grow with the number of finished missions (tier = done / 3)
local function goal_for(kind, tier)
	if kind == "serve" then return math.min(30, 6 + 3 * tier) end
	if kind == "food" then return math.min(8, 3 + tier) end
	if kind == "levels" then return math.min(5, 2 + math.floor(tier / 2)) end
	if kind == "stars3" then return math.min(3, 1 + math.floor(tier / 3)) end
	if kind == "vip" then return math.min(3, 1 + math.floor(tier / 3)) end
	if kind == "gold" then return math.min(12, 3 + tier) end
	return math.min(12, 3 + tier) -- showcase: dishes nobody ordered, to the display case
end

local function new_mission(state, level)
	local used = {}
	for _, m in ipairs(state.list) do used[m.kind] = true end
	local cand = {}
	for _, k in ipairs(M.KINDS) do
		if not used[k] and (k ~= "vip" or level >= config.VIP_MIN_LEVEL)
			and (k ~= "gold" or level >= config.GOLD_MIN_LEVEL) then
			cand[#cand + 1] = k
		end
	end
	local kind = cand[math.random(#cand)]
	local tier = math.floor(state.done / 3)
	local m = { kind = kind, goal = goal_for(kind, tier), progress = 0, coins = 30 + 10 * math.min(tier, 12) }
	if kind == "food" then m.food = math.random(levels.get(level).types) end
	state.serial = state.serial + 1
	if state.serial % 3 == 0 then m.booster = BOOSTERS[math.random(#BOOSTERS)] end
	return m
end

function M.ensure(state, level)
	state.list = state.list or {}
	state.done = state.done or 0
	state.serial = state.serial or 0
	-- "levels without waste" left with the bin: old saves get a new task instead
	for i = #state.list, 1, -1 do
		if state.list[i].kind == "clean" then table.remove(state.list, i) end
	end
	while #state.list < config.MISSION_SLOTS do
		state.list[#state.list + 1] = new_mission(state, level)
	end
end

-- progress a mission gets from level stats r; live = during the level (win-only kinds give 0)
local function gain(m, r, live)
	if m.kind == "serve" then return r.served or 0 end
	if m.kind == "food" then return (r.food_done and r.food_done[m.food]) or 0 end
	if m.kind == "vip" then return r.vip_served or 0 end
	if m.kind == "gold" then return r.gold_found or 0 end
	if m.kind == "showcase" then return r.showcase or 0 end
	if live then return 0 end
	if m.kind == "levels" then return 1 end
	if m.kind == "stars3" then return r.stars == 3 and 1 or 0 end
	return 0
end

-- Applies a won level (r = session.result). Finished missions are replaced by new ones.
-- Returns the popup report (a snapshot) and the rewards for the caller to credit:
-- { rows = { {kind, food, goal, from, to, done, coins, booster} }, coins = n, boosters = { kind = n }, changed = bool }
function M.apply(state, level, r)
	M.ensure(state, level)
	local rep = { rows = {}, coins = 0, boosters = {}, changed = false }
	for i, m in ipairs(state.list) do
		local from = m.progress
		m.progress = math.min(m.goal, m.progress + gain(m, r, false))
		local done = m.progress >= m.goal
		if m.progress ~= from then rep.changed = true end
		rep.rows[i] = {
			kind = m.kind, food = m.food, goal = m.goal, from = from, to = m.progress,
			done = done, coins = m.coins, booster = m.booster,
		}
		if done then
			rep.coins = rep.coins + m.coins
			if m.booster then rep.boosters[m.booster] = (rep.boosters[m.booster] or 0) + 1 end
			state.done = state.done + 1
		end
	end
	for i = #state.list, 1, -1 do
		if state.list[i].progress >= state.list[i].goal then table.remove(state.list, i) end
	end
	M.ensure(state, level + 1)
	return rep
end

-- Indices of missions the running level already finishes (for the in-game toast).
function M.live_done(state, stats)
	local out = {}
	for i, m in ipairs(state.list or {}) do
		if m.progress < m.goal and m.progress + gain(m, stats, true) >= m.goal then out[#out + 1] = i end
	end
	return out
end

-- Rows for the popup from the current state (opened from the menu / pause).
function M.rows(state)
	local rows = {}
	for i, m in ipairs(state.list or {}) do
		rows[i] = {
			kind = m.kind, food = m.food, goal = m.goal, from = m.progress, to = m.progress,
			done = false, coins = m.coins, booster = m.booster,
		}
	end
	return rows
end

return M
