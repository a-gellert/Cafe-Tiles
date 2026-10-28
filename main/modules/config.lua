-- Gameplay and economy constants. Balance changes go here and into docs/KNOWLEDGE_BASE.md.
local M = {}

M.SLOT_COUNT = 7        -- tray cells under the board; 7 tiles without a match = kitchen jam
M.SHELF_COUNT = 7       -- holding shelf filled by "second chance"
M.SEATS = 3             -- customers at the counter at once

-- Food types in unlock order: a level with N types uses the first N.
M.FOOD = {
	"burger", "coffee", "donut", "pizza", "cupcake", "fries",
	"icecream", "hotdog", "croissant", "cookie", "juice", "cake",
	"taco", "sushi", "egg", "cheese",
}

M.CUSTOMERS = { "cat", "bear", "bunny", "panda", "fox", "frog", "pig", "penguin" }

-- Economy (coins)
M.DISH_PRICE = 4                -- per served order item (one triple)
M.TIP_MAX = 4                   -- tip at full patience, scales down with patience
M.LEVEL_BONUS_BASE = 10         -- completion bonus = (base + level * per_level) * stars / 3
M.LEVEL_BONUS_PER_LEVEL = 2
M.DECOR_BONUS = 0.05            -- +5% coins per bought decor tier

-- Session loops (Star Chest & Win Streak)
M.STAR_CHEST_GOAL = 10          -- stars needed to open the chef's star chest
M.STAR_CHEST_COINS = 80         -- coins rewarded by the star chest
M.STREAK_BONUS = { [0] = 0, [1] = 0, [2] = 0.15, [3] = 0.30 } -- bonus coins for win streak >= 2

-- Session loops 2: missions, VIP guests, hard levels, coin continue
M.MISSION_SLOTS = 3
M.VIP_MIN_LEVEL = 4
M.VIP_CHANCE = 0.06             -- per arriving guest (max 1 VIP per level, 2 from level 15)
M.VIP_PAY = 2                   -- dish price multiplier
M.VIP_TIP = 3                   -- tip multiplier
M.VIP_PATIENCE = 0.9
M.HARD_BONUS = 1.5              -- level bonus multiplier on "hard" levels (every 5th)
M.PAID_CHANCES = 2              -- "continue for coins" per level, on top of the rewarded ones
M.CONTINUE_COST_BASE = 40       -- cost = base + per_level * level
M.CONTINUE_COST_PER_LEVEL = 3

-- Phase 3: depth and juice
M.COMBO_WINDOW = 6.0            -- seconds between served triples that keep the combo going
M.COMBO_COIN_MAX = 3            -- extra coins per served dish: combo - 1, capped
M.GOLD_MIN_LEVEL = 4            -- golden tiles pay extra when they leave in a triple
M.GOLD_TILES = 3                -- per level (x2 on hard levels)
M.GOLD_COINS = 3                -- per golden tile (x decor multiplier)
M.CLOCHE_MIN_LEVEL = 6          -- some covered dishes hide under a cloche until they are free
M.CLOCHE_SHARE = 0.3            -- share of the initially covered tiles
-- Session gifts: seconds of level play (this page session) for each gift, then every GIFT_REPEAT
M.GIFT_TIMES = { 75, 200, 360, 540, 720, 900 }
M.GIFT_REPEAT = 240
M.GIFTS = {
	{ coins = 25 },
	{ coins = 20, booster = "rush" },
	{ coins = 50 },
	{ coins = 40, booster = "shuffle" },
	{ coins = 80 },
	{ coins = 60, booster = "undo" },
}
M.GIFT_LATER = { coins = 70 }

-- Rewarded / boosters
M.SECOND_CHANCES = 2            -- per level
M.START_BOOSTERS = { undo = 3, shuffle = 2, rush = 1 }
M.BOOSTER_AD_GRANT = 1          -- uses granted by one rewarded video

-- Customers
M.ARRIVE_DELAY = 1.3            -- seconds before an empty seat is taken
M.FIRST_ARRIVE_STAGGER = 0.25

return M
