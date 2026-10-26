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

-- Rewarded / boosters
M.SECOND_CHANCES = 2            -- per level
M.START_BOOSTERS = { undo = 3, shuffle = 2, rush = 1 }
M.BOOSTER_AD_GRANT = 1          -- uses granted by one rewarded video

-- Customers
M.ARRIVE_DELAY = 1.3            -- seconds before an empty seat is taken
M.FIRST_ARRIVE_STAGGER = 0.25

return M
