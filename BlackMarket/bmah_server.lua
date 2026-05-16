-- ────────────────────────────────────────────────────────────────────────────────
-- ────────────────────────────────────────────────────────────────────────────────
-- BLACK MARKET AUCTION HOUSE 3.3.5 BACKPORT 
-- ────────────────────────────────────────────────────────────────────────────────
-- ────────────────────────────────────────────────────────────────────────────────

-- ─── Vendor NPC Configuration ───────────────────────────────────────────────
-- List the NPC IDs that will serve as Black Market Auction House vendors.
-- Interacting with any of these IDs will open the BMAH UI for players.
-- Add or remove IDs here as your server requires.

local BMAH_VENDOR_NPCs = {
  228404, --Test Subject
  --#######, --Add More Here
}
-- ─────────────────────────────────────────────────────────────────────────────
-- ─── Fill-rarity configuration ───────────────────────────────────────────────────
-- Tweak these three values to adjust your loot rarity probabilities.
-- They represent the *cumulative* thresholds for a random roll r = math.random():
--
--   0.00 ≤ r < FillRateCommon   → pick from commonItems
--   FillRateCommon ≤ r < FillRateRare     → pick from rareItems
--   FillRateRare ≤ r ≤ FillRateUltra      → pick from ultraRareItems
--
-- Requirements:
--  1) 0.0  ≤ FillRateCommon
--  2) FillRateCommon ≤ FillRateRare
--  3) FillRateRare   ≤ FillRateUltra
--  4) FillRateUltra ≤ 1.0
--
-- Example distributions:
--   FillRateCommon = 0.70   → 70% common
--   FillRateRare   = 0.90   → 20% rare  (0.90 - 0.70)
--   FillRateUltra  = 1.00   → 10% ultra (1.00 - 0.90)
--
-- Implementation note:
--   local r = math.random()  -- returns a float 0 <= r < 1 (or ≤1 depending on build)
--   if r < FillRateCommon then
--       -- common
--   elseif r < FillRateRare then
--       -- rare
--   else
--       -- ultra
--   end
--
local FillRateCommon   = 0.85   -- e.g. 85% chance for commonItems
local FillRateRare     = 0.95   -- next 10% (95% - 85%) for rareItems
local FillRateUltra    = 1.00   -- final 5%  (100% - 95%) for ultraRareItems
-- ──────────────────────────────────────────────────────────────────────────────

-- ─── Fill-count configuration ─────────────────────────────────────────────────
-- These three thresholds (cumulative) map a random roll r = math.random() to
-- one of four possible row-counts. Adjust the numbers below to change how many
-- auctions get spawned most often.
--
--    0.00 ≤ r < FillCountThreshold1 → insert FillCount1 rows
--    FillCountThreshold1 ≤ r < FillCountThreshold2 → insert FillCount2 rows
--    FillCountThreshold2 ≤ r < FillCountThreshold3 → insert FillCount3 rows
--    FillCountThreshold3 ≤ r ≤ FillCountThreshold4 → insert FillCount4 rows
--
-- Requirements:
--  0.0 ≤ FillCountThreshold1
--  FillCountThreshold1 ≤ FillCountThreshold2
--  FillCountThreshold2 ≤ FillCountThreshold3
--  FillCountThreshold3 ≤ FillCountThreshold4 (must be 1.0)
--
local FillCountThreshold1 = 0.64   -- e.g. 64% chance to insert FillCount1 rows
local FillCountThreshold2 = 0.76   -- next 12% (76%–64%) → FillCount2
local FillCountThreshold3 = 0.88   -- next 12% (88%–76%) → FillCount3
local FillCountThreshold4 = 1.00   -- final 12% (100%–88%) → FillCount4

local FillCount1 = 3               -- rows if r < 0.64
local FillCount2 = 2               -- rows if r < 0.76
local FillCount3 = 4               -- rows if r < 0.88
local FillCount4 = 5               -- rows otherwise
-- ───────────────────────────────────────────────────────────────────────────────

-- ─── Bidding rules ────────────────────────────────────────────────────────────
local MinBidIncrementG   = 10       -- how many gold above last_bid is required
-- ──────────────────────────────────────────────────────────────────────────────
-- ─── General timing & chance ──────────────────────────────────────────────────
local AutoFillChance     = 0.50        -- chance to auto-fill when table is empty
local PotentialDurations = {720, 1440} -- possible “time left” values (in minutes)
-- ───────────────────────────────────────────────────────────────────────────────
-- ─── Refund‐mail configuration ─────────────────────────────────────────────────
local RefundMailSender     = 0         
local RefundStationery     = 41     
local RefundMailSubject    = "[BMAH] Remboursement de mise"
local RefundMailBody       = "Vous avez été surenchéri sur l'Hôtel des Ventes du Marché Noir. Votre mise de %dg vous a été remboursée."
-- ────────────────────────────────────────────────────────────────────────────────

-- ─── Flush‐notify configuration ────────────────────────────────────────────────
local FlushMailSender      = 0  
local FlushMailStationery  = 62 
local FlushMailSubject     = "[BMAH] Vous avez remporté l'enchère !"
local FlushMailBody        = [[
Félicitations ! Vous avez remporté un article sur l'Hôtel des Ventes du Marché Noir.
After spending %dg, “%s” is now yours! Enjoy.

– Le Marché Noir
]]
-- ───────────────────────────────────────────────────────────────────────────────

-- ─── Item Pricing Configuration ──────────────────────────────────────────────
-- Define the gold cost for each item category and rarity tier.
--   common_*_price   → cost for common items
--   rare_*_price     → cost for rare items
--   ultraRare_*_price → cost for ultra-rare items
-- Adjust these values to fit your server’s economy.

local common_pets_price     = 100
local rare_pets_price       = 400
local ultraRare_pets_price  = 1000

local common_mount_price    = 5000
local rare_mount_price      = 10000
local ultraRare_mount_price = 20000

local common_tcg_price      = 1000
local rare_tcg_price        = 2000
local ultraRare_tcg_price   = 5000

local common_misc_price     = 500
local rare_misc_price       = 600

local battered_hilt_price   = 10000

local common_gear_price     = 500
local rare_gear_price       = 1800
local ultraRare_gear_price  = 5000

local rare_instrument_price = 25000
-- ─────────────────────────────────────────────────────────────────────────────

local commonItems = {
  { itemId = 8485,   seller = "Breanni",         cost = common_pets_price  },
  { itemId = 8490,   seller = "Breanni",         cost = common_pets_price  },
  { itemId = 8491,   seller = "Breanni",         cost = common_pets_price  },
  { itemId = 8492,   seller = "Breanni",         cost = common_pets_price  },
  { itemId = 20768,  seller = "Yuppl",           cost = common_pets_price  },
  { itemId = 20769,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 22799,  seller = "Zunji the Knife", cost = common_gear_price  },
  { itemId = 29960,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 34499,  seller = "Landro Longshot", cost = common_tcg_price   },
  { itemId = 34535,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 38309,  seller = "Landro Longshot", cost = common_tcg_price   },
  { itemId = 38310,  seller = "Landro Longshot", cost = common_tcg_price   },
  { itemId = 38313,  seller = "Landro Longshot", cost = common_tcg_price   },
  { itemId = 38578,  seller = "Landro Longshot", cost = common_tcg_price   },
  { itemId = 39883,  seller = "Yuppl",           cost = common_pets_price  },
  { itemId = 43698,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 44178,  seller = "Mei Francis",     cost = common_mount_price },
  { itemId = 44707,  seller = "Mei Francis",     cost = common_mount_price },
  { itemId = 44721,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 44751,  seller = "Yuppl",           cost = common_pets_price  },
  { itemId = 44965,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 44970,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 44971,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 44973,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 44974,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 44980,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 44982,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 45002,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 45606,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 46780,  seller = "Landro Longshot", cost = common_tcg_price   },
  { itemId = 48112,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 48114,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 48116,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 48118,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 48124,  seller = "Breanni",         cost = common_pets_price  },
  { itemId = 48126,  seller = "Breanni",         cost = common_pets_price  },
}

local rareItems = {
  { itemId = 8494,   seller = "Breanni",             cost = rare_pets_price     },
  { itemId = 8498,   seller = "Breanni",             cost = rare_pets_price     },
  { itemId = 8499,   seller = "Breanni",             cost = rare_pets_price     },
  { itemId = 10822,  seller = "Breanni",             cost = rare_pets_price     },
  { itemId = 13335,  seller = "Mei Francis",         cost = rare_mount_price    },
  { itemId = 14617,  seller = "Yuppl",               cost = rare_misc_price     },
  { itemId = 23705,  seller = "Landro Longshot",     cost = rare_tcg_price      },
  { itemId = 23709,  seller = "Landro Longshot",     cost = rare_tcg_price      },
  { itemId = 23713,  seller = "Landro Longshot",     cost = rare_tcg_price      },
  { itemId = 23720,  seller = "Mei Francis",         cost = rare_mount_price    },
  { itemId = 29271,  seller = "Zunji the Knife",     cost = rare_gear_price     },
  { itemId = 30380,  seller = "Caladis Brightspear", cost = battered_hilt_price },
  { itemId = 32542,  seller = "Landro Longshot",     cost = rare_tcg_price      },
  { itemId = 32566,  seller = "Landro Longshot",     cost = rare_tcg_price      },
  { itemId = 32588,  seller = "Landro Longshot",     cost = rare_tcg_price      },
  { itemId = 33219,  seller = "Landro Longshot",     cost = rare_tcg_price      },
  { itemId = 33223,  seller = "Landro Longshot",     cost = rare_tcg_price      },
  { itemId = 34492,  seller = "Landro Longshot",     cost = rare_tcg_price      },
  { itemId = 35504,  seller = "Breanni",             cost = rare_pets_price     },
  { itemId = 35513,  seller = "Mei Francis",         cost = rare_mount_price    },
  { itemId = 38050,  seller = "Landro Longshot",     cost = rare_tcg_price      },
  { itemId = 38311,  seller = "Landro Longshot",     cost = rare_tcg_price      },
  { itemId = 39769,  seller = "Bergrisst",           cost = rare_instrument_price },
  { itemId = 43952,  seller = "Mei Francis",         cost = rare_mount_price    },
  { itemId = 43953,  seller = "Mei Francis",         cost = rare_mount_price    },
  { itemId = 44151,  seller = "Mei Francis",         cost = rare_mount_price    },
  { itemId = 44924,  seller = "Bergrisst",           cost = rare_instrument_price },
  { itemId = 45037,  seller = "Yuppl",               cost = rare_misc_price     },
  { itemId = 45063,  seller = "Landro Longshot",     cost = rare_tcg_price      },
  { itemId = 50379,  seller = "Caladis Brightspear", cost = battered_hilt_price },
}

local ultraRareItems = {
  { itemId = 19872,  seller = "Mei Francis",       cost = ultraRare_mount_price },
  { itemId = 19902,  seller = "Mei Francis",       cost = ultraRare_mount_price },
  { itemId = 30480,  seller = "Mei Francis",       cost = ultraRare_mount_price },
  { itemId = 32458,  seller = "Mei Francis",       cost = ultraRare_mount_price },
  { itemId = 34493,  seller = "Landro Longshot",   cost = ultraRare_tcg_price   },
  { itemId = 35227,  seller = "Landro Longshot",   cost = ultraRare_tcg_price   },
  { itemId = 38312,  seller = "Landro Longshot",   cost = ultraRare_tcg_price   },
  { itemId = 38314,  seller = "Landro Longshot",   cost = ultraRare_tcg_price   },
  { itemId = 40491,  seller = "Zunji the Knife",   cost = ultraRare_tcg_price   },
  { itemId = 44083,  seller = "Mei Francis",       cost = ultraRare_mount_price },
  { itemId = 44175,  seller = "Mei Francis",       cost = ultraRare_mount_price },
  { itemId = 45693,  seller = "Mei Francis",       cost = ultraRare_mount_price },
  { itemId = 45802,  seller = "Mei Francis",       cost = ultraRare_mount_price },
  { itemId = 49286,  seller = "Mei Francis",       cost = ultraRare_mount_price },
  { itemId = 49287,  seller = "Breanni",           cost = ultraRare_pets_price  },
  { itemId = 49343,  seller = "Breanni",           cost = ultraRare_pets_price  },
  { itemId = 49636,  seller = "Mei Francis",       cost = ultraRare_mount_price },
  { itemId = 50046,  seller = "Zunji the Knife",   cost = ultraRare_gear_price  },
  { itemId = 50047,  seller = "Zunji the Knife",   cost = ultraRare_gear_price  },
  { itemId = 50048,  seller = "Zunji the Knife",   cost = ultraRare_gear_price  },
  { itemId = 50049,  seller = "Zunji the Knife",   cost = ultraRare_gear_price  },
  { itemId = 50050,  seller = "Zunji the Knife",   cost = ultraRare_gear_price  },
  { itemId = 50051,  seller = "Zunji the Knife",   cost = ultraRare_gear_price  },
  { itemId = 50052,  seller = "Zunji the Knife",   cost = ultraRare_gear_price  },
  { itemId = 50818,  seller = "Mei Francis",       cost = ultraRare_mount_price },
  { itemId = 54068,  seller = "Mei Francis",       cost = ultraRare_mount_price },
}
--Set the Table
CharDBExecute([[
CREATE TABLE IF NOT EXISTS `blackmarketauctionhouse` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `item_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `item_owner` VARCHAR(32) NOT NULL DEFAULT '',
  `time` INT NOT NULL DEFAULT 0,
  `last_bid` INT UNSIGNED NOT NULL DEFAULT 0,
  `start_bid` INT UNSIGNED NOT NULL DEFAULT 0,
  `buyer_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `total_bids` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]])



local function OnBMAHVendorGossip(event, player, creature)
    -- prefix “BMAHUI” / message “OPEN” is arbitrary but must match client
    player:SendAddonMessage("BMAHUI", "OPEN", 0, player)
    player:GossipComplete()    -- close the gossip window
end

for _, entry in ipairs(BMAH_VENDOR_NPCs) do
    RegisterCreatureGossipEvent(entry, 1, OnBMAHVendorGossip)
end

local REQ  = "BMAH_REQ"
local DATA = "BMAH_DATA"
local DONE = "BMAH_DONE"
local COPPER_PER_SILVER = 100
local SILVER_PER_GOLD   = 100
math.randomseed(os.time())

local SUBCLASS = {
    ["0_0"]="Consommable",["0_1"]="Potion",["0_2"]="Élixir",["0_3"]="Fiole",["0_4"]="Parchemin",["0_5"]="Nourriture & Boisson",["0_6"]="Amélioration d'objet",["0_7"]="Bandage",["0_8"]="Autre",
    ["1_0"]="Sac",["1_1"]="Sac d'âmes",["1_2"]="Sac d'herbes",["1_3"]="Sac d'enchantement",["1_4"]="Sac d'ingénierie",["1_5"]="Sac de gemmes",["1_6"]="Sac de mineur",["1_7"]="Sac de travail du cuir",["1_8"]="Sac d'calligraphie",
    ["2_0"]="Hache à une main",["2_1"]="Hache à deux mains",["2_2"]="Arc",["2_3"]="Arme à feu",["2_4"]="Masse à une main",["2_5"]="Masse à deux mains",["2_6"]="Arme d'hast",["2_7"]="Épée à une main",["2_8"]="Épée à deux mains",["2_9"]="Obsolète",["2_10"]="Bâton",["2_11"]="Exotique",["2_12"]="Exotique",["2_13"]="Arme de poing",["2_14"]="Divers",["2_15"]="Dague",["2_16"]="Arme de jet",["2_17"]="Lance",["2_18"]="Arbalète",["2_19"]="Baguette",["2_20"]="Canne à pêche",
    ["3_0"]="Rouge",["3_1"]="Bleu",["3_2"]="Jaune",["3_3"]="Violet",["3_4"]="Vert",["3_5"]="Orange",["3_6"]="Méta",["3_7"]="Simple",["3_8"]="Prismatique",
    ["4_0"]="Divers",["4_1"]="Tissu",["4_2"]="Cuir",["4_3"]="Mailles",["4_4"]="Plaques",["4_5"]="Rondache",["4_6"]="Bouclier",["4_7"]="Libram",["4_8"]="Idole",["4_9"]="Totem",["4_10"]="Signe",
    ["5_0"]="Réactif",
    ["6_0"]="Baguette",["6_1"]="Carreau",["6_2"]="Flèche",["6_3"]="Balle",["6_4"]="Arme de jet",
    ["7_0"]="Articles commerciaux",["7_1"]="Pièces",["7_2"]="Explosifs",["7_3"]="Dispositifs",["7_4"]="Joaillerie",["7_5"]="Tissu",["7_6"]="Cuir",["7_7"]="Métal & Pierre",["7_8"]="Viande",["7_9"]="Herbe",["7_10"]="Élémentaire",["7_11"]="Autre",["7_12"]="Enchantement",["7_13"]="Matériaux",["7_14"]="Enchantement d'armure",["7_15"]="Enchantement d'arme",
    ["8_0"]="Générique",
    ["9_0"]="Livre",["9_1"]="Travail du cuir",["9_2"]="Couture",["9_3"]="Ingénierie",["9_4"]="Forge",["9_5"]="Cuisine",["9_6"]="Alchimie",["9_7"]="Premiers secours",["9_8"]="Enchantement",["9_9"]="Pêche",["9_10"]="Joaillerie",
    ["10_0"]="Argent",
    ["11_0"]="Carquois",["11_1"]="Carquois",["11_2"]="Carquois",["11_3"]="Sacoche à munitions",
    ["12_0"]="Quête",
    ["13_0"]="Clé",["13_1"]="Crochet",
    ["14_0"]="Permanent",
    ["15_0"]="Bric-à-brac",["15_1"]="Réactif",["15_2"]="Mascotte",["15_3"]="Fête",["15_4"]="Autre",["15_5"]="Monture",
    ["16_1"]="Guerrier",["16_2"]="Paladin",["16_3"]="Chasseur",["16_4"]="Voleur",["16_5"]="Prêtre",["16_6"]="Chevalier de la Mort",["16_7"]="Chaman",["16_8"]="Mage",["16_9"]="Démoniste",["16_11"]="Druide",
}

-- helper: bucket minutes into a word
local function ClassifyTime(mins)
    if mins < 30 then
        return "Court"
    elseif mins < 120 then
        return "Moyen"
    elseif mins < 720 then
        return "Long"
    else
        return "Très long"
    end
end

RegisterPlayerEvent(19, function(_, player, msg, _, _, receiver)
    if msg ~= REQ then
        return
    end
    local target = receiver or player

    -- ◼ 0) find row with the most total_bids
    local maxQ = CharDBQuery([[
        SELECT id
        FROM blackmarketauctionhouse
        ORDER BY total_bids DESC
        LIMIT 1
    ]])
    local maxRowId = maxQ and maxQ:GetUInt32(0) or 0

    -- 1) Fetch all blackmarket rows from CharDB
    local rowsQ = CharDBQuery([[
        SELECT id, item_id, time, item_owner, last_bid
        FROM blackmarketauctionhouse
        ORDER BY id ASC
    ]])
    if not rowsQ then
        player:SendAddonMessage(DONE, "0", 0, target)
        return
    end

    local sent = 0
    repeat
        -- pull from CharDB
        local itemId   = rowsQ:GetUInt32(1)
        local minsLeft = rowsQ:GetUInt32(2)
        local owner    = rowsQ:GetString(3)
        local lastBid  = rowsQ:GetUInt32(4)

        -- lookup name (frFR en priorité), level, class, subclass in WorldDB
        local tplQ = WorldDBQuery(string.format([[
            SELECT COALESCE(NULLIF(loc.Name, ''), it.name) AS name,
                   it.RequiredLevel,
                   it.class,
                   it.subclass
            FROM item_template it
            LEFT JOIN item_template_locale loc
                   ON loc.ID = it.entry AND loc.locale = 'frFR'
            WHERE it.entry = %d
        ]], itemId))

        local itemName, reqLevel, classId, subClassId
        if tplQ then
            itemName   = tplQ:GetString(0)
            reqLevel   = tplQ:GetUInt32(1)
            classId    = tplQ:GetUInt32(2)
            subClassId = tplQ:GetUInt32(3)
        else
            itemName   = "Item#" .. itemId
            reqLevel   = 0
            classId    = 0
            subClassId = 0
        end

        -- map class_subclass → text via your SUBCLASS table
        local key      = classId .."_".. subClassId
        local itemType = SUBCLASS[key] or ""

        -- bucket minutes into Short/Medium/Long/Very Long
        local timeWord = ClassifyTime(minsLeft)

        -- L'icône est résolue côté client via GetItemInfo(itemId) dans l'addon
        local iconName = ""

        -- build exactly 9 fields: name;level;type;time;owner;bid;icon;maxRowId;itemId
        local payload = string.format(
            "%s;%d;%s;%s;%s;%d;%s;%d;%d",
            itemName:gsub(";", ""),
            reqLevel,
            itemType,
            timeWord,
            owner:gsub(";", ""),
            lastBid,
            iconName,
            maxRowId,
            itemId
        )

        player:SendAddonMessage(DATA, payload, 0, target)
        sent = sent + 1
    until not rowsQ:NextRow()

    player:SendAddonMessage(DONE, tostring(sent), 0, target)
end)

RegisterPlayerEvent(19, function(_, player, msg, _, _, _)
    if msg:lower() ~= "bmah_flush" then
        return
    end

    if not player:IsGM() then
        player:SendBroadcastMessage("|cffff0000[BMAH]|r Vous n'avez pas la permission de vider la table BlackMarketAH.")
        return false
    end

    -- 1) query every sold row
    local q = CharDBQuery([[
        SELECT id, item_id, buyer_id, last_bid
        FROM blackmarketauctionhouse
        WHERE buyer_id <> 0
    ]])

    if q then
        repeat
            local rowId       = q:GetUInt32(0)
            local itemEntry   = q:GetUInt32(1)
            local receiver    = q:GetUInt32(2)
            local bidCopper   = q:GetUInt32(3)
            -- fetch item name from world DB (frFR en priorité)
            local wq = WorldDBQuery(string.format(
                "SELECT COALESCE(NULLIF(loc.Name,''), it.name) FROM item_template it LEFT JOIN item_template_locale loc ON loc.ID = it.entry AND loc.locale = 'frFR' WHERE it.entry = %d", itemEntry
            ))
            local itemName = wq and wq:GetString(0) or ("Item#"..itemEntry)
            -- compute gold spent
            local bidGold = math.floor(bidCopper / (COPPER_PER_SILVER * SILVER_PER_GOLD))

            -- format the body
            local body = string.format(FlushMailBody, bidGold, itemName)

            -- send the mail: no money, no COD, attach exactly one of the item
            SendMail(
                FlushMailSubject,
                body,
                receiver,
                FlushMailSender,
                FlushMailStationery,
                0,        -- immediate delivery
                0,        -- money attached
                0,        -- COD
                itemEntry,
                1         -- quantity
            )
        until not q:NextRow()
    end

    -- 2) now wipe the auction table
    CharDBExecute([[TRUNCATE TABLE blackmarketauctionhouse]])

    -- 3) feedback
    player:SendBroadcastMessage("|cff69ccf0[BMAH]|r La table BlackMarketAH a été vidée. Tous les articles remportés ont été envoyés par courrier !")
    return false
end)

RegisterPlayerEvent(19, function(_, player, msg, _, _, _)
    if msg:lower() ~= "bmah_fill" then
        return
    end

    if not player:IsGM() then
        player:SendBroadcastMessage("|cffff0000[BMAH]|r Vous n'avez pas la permission de remplir la table BlackMarketAH.")
        return false
    end

    -- ── do not fill if any auctions still exist ───────────
    local countQ = CharDBQuery("SELECT COUNT(*) FROM blackmarketauctionhouse")
    local count  = countQ and countQ:GetUInt32(0) or 0
    if count > 0 then
        player:SendBroadcastMessage("|cffff0000[BMAH]|r Le Marché Noir contient déjà des enchères actives. Veuillez d'abord le vider.")
        return false
    end

    -- now safe to truncate & refill
    CharDBExecute([[TRUNCATE TABLE blackmarketauctionhouse]])

    -- roll how many rows to insert
    local r = math.random()
    local count
    if r < FillCountThreshold1 then
        count = FillCount1
    elseif r < FillCountThreshold2 then
        count = FillCount2
    elseif r < FillCountThreshold3 then
        count = FillCount3
    else
        count = FillCount4
    end

    -- helper to pick a random entry from a table
    local function pick(t)
        return t[ math.random(1, #t) ]
    end

    -- now loop and insert
    for i = 1, count do
        -- roll rarity
        local r = math.random()
        local entry
        if r < FillRateCommon then
            entry = pick(commonItems)
        elseif r < FillRateRare then
            entry = pick(rareItems)
        else
            entry = pick(ultraRareItems)
        end

        -- sanitize owner name
        local owner = entry.seller:gsub("'", "''")
        -- cost is multiplied by 10000
        local bid = entry.cost * 10000
        -- timeLeft (in minutes) — adjust as you like
        local durations = PotentialDurations
        local timeLeft  = durations[ math.random(#durations) ]

        -- insert into DB
        CharDBExecute(string.format([[
            INSERT INTO blackmarketauctionhouse
              (item_id, time, item_owner, start_bid, last_bid)
            VALUES
              (%d, %d, '%s', %d, %d)
        ]],
            entry.itemId,
            timeLeft,
            owner,
            bid,
            bid
        ))
    end

    player:SendBroadcastMessage(
        string.format(
            "|cff69ccf0[BMAH]|r Le Marché Noir a été rempli avec %d articles.",
            count
        )
    )
    return false
end)

-- client will whisper: "BMAH_BID;<itemId>;<goldAmount>"
local BID_REQ    = "BMAH_BID"
-- same for hot-item if you want a different command
local HOTBID_REQ = "BMAH_HOTBID"

RegisterPlayerEvent(19, function(_, player, msg, _, _, _)
    -- only handle our bid commands
    local cmd, payload = msg:match("^([A-Z_]+);(.+)$")
    if cmd ~= BID_REQ and cmd ~= HOTBID_REQ then
        return
    end

    -- parse params
    local idStr, bidG = payload:match("^(%d+);(%d+)$")
    local id     = tonumber(idStr)
    local bidAmt = tonumber(bidG)
    if not id or not bidAmt then
        player:SendBroadcastMessage("|cffff0000[BMAH]|r Format de mise invalide.")
        return false
    end

    -- look up the auction row (now also fetch buyer_id)
    local q = CharDBQuery(string.format(
        "SELECT id, last_bid, buyer_id FROM blackmarketauctionhouse WHERE %s = %d",
        (cmd == HOTBID_REQ) and "id" or "item_id",
        id
    ))
    if not q then
        player:SendBroadcastMessage("|cffff0000[BMAH]|r Enchère introuvable.")
        return false
    end

    local rowId          = q:GetUInt32(0)
    local lastBid        = q:GetUInt32(1)
    local currentBidder  = q:GetUInt32(2)
    -- convert to copper
    local bidCopper      = bidAmt * COPPER_PER_SILVER * SILVER_PER_GOLD
    local minRequired    = lastBid + (MinBidIncrementG * COPPER_PER_SILVER * SILVER_PER_GOLD)
    local playerCopper   = player:GetCoinage()

    -- 0) If they’re already the highest bidder, bail out
    if currentBidder == player:GetGUIDLow() then
        player:SendBroadcastMessage(
            "|cffff0000[BMAH]|r Vous détenez déjà la mise la plus haute sur cette enchère."
        )
        return false
    end

    if playerCopper < bidCopper then
        player:SendBroadcastMessage("|cffff0000[BMAH]|r Vous n'avez pas assez d'or pour cette mise.")
    elseif bidCopper < minRequired then
        local requiredG = minRequired / (COPPER_PER_SILVER * SILVER_PER_GOLD)
        player:SendBroadcastMessage(
            ("|cffff0000[BMAH]|r Votre mise doit être d'au moins %dg."):format(requiredG)
        )
    else
        -- deduct
        player:ModifyMoney(-bidCopper)
        -- refund setup (as before)
        local refundCopper = lastBid
        local refundGold   = math.floor(refundCopper / (COPPER_PER_SILVER * SILVER_PER_GOLD))
        if currentBidder ~= 0 then
            -- escape strings
            local subj = RefundMailSubject:gsub("'", "''")
            local body = string.format(RefundMailBody, refundGold):gsub("'", "''")

            SendMail(
                RefundMailSubject,
                body,
                currentBidder,
                RefundMailSender,
                RefundStationery,
                0,               -- no delay
                refundCopper     -- refund amount in copper
            )
        end
        -- update DB
        CharDBExecute(string.format([[
            UPDATE blackmarketauctionhouse
               SET last_bid   = %d,
                   buyer_id   = %d,
                   total_bids = total_bids + 1
             WHERE id = %d
        ]], bidCopper, player:GetGUIDLow(), rowId))
        player:SendBroadcastMessage(
            ("|cff69ccf0[BMAH]|r Votre mise de %dg a été acceptée !"):format(bidAmt)
        )
    end

    return false    -- swallow the whisper so it doesn’t spam the client
end)

-- 1) Define two helper functions using your existing code

local function BMAH_FlushLogic()
    -- 1) grab every expired auction
    local q = CharDBQuery([[
        SELECT id, item_id, buyer_id, last_bid
        FROM blackmarketauctionhouse
        WHERE time <= 0
    ]])
    if q then
        local expiredIds = {}
        repeat
            local rowId     = q:GetUInt32(0)
            local itemEntry = q:GetUInt32(1)
            local buyerId   = q:GetUInt32(2)
            local bidCopper = q:GetUInt32(3)

            -- mail only if someone actually bid
            if buyerId ~= 0 then
                local wq = WorldDBQuery(string.format(
                    "SELECT COALESCE(NULLIF(loc.Name,''), it.name) FROM item_template it LEFT JOIN item_template_locale loc ON loc.ID = it.entry AND loc.locale = 'frFR' WHERE it.entry = %d",
                    itemEntry
                ))
                local itemName = wq and wq:GetString(0) or ("Item#"..itemEntry)
                local bidGold  = math.floor(bidCopper / (COPPER_PER_SILVER * SILVER_PER_GOLD))
                local body     = string.format(FlushMailBody, bidGold, itemName)

                SendMail(
                    FlushMailSubject,
                    body,
                    buyerId,
                    FlushMailSender,
                    FlushMailStationery,
                    0, 0, 0,
                    itemEntry,
                    1
                )
            end

            table.insert(expiredIds, rowId)
        until not q:NextRow()

        -- 2) delete only those expired rows
        CharDBExecute(( "DELETE FROM blackmarketauctionhouse WHERE id IN (%s)" )
            :format(table.concat(expiredIds, ",")))
    end

end

local function BMAH_FillLogic()
    -- copy exactly the body of your fill handler, minus the GM‐check and player:SendBroadcastMessage
    CharDBExecute("TRUNCATE TABLE blackmarketauctionhouse")

    local r = math.random()
    local count
    if r < FillCountThreshold1 then
        count = FillCount1
    elseif r < FillCountThreshold2 then
        count = FillCount2
    elseif r < FillCountThreshold3 then
        count = FillCount3
    else
        count = FillCount4
    end

    local function pick(t) return t[ math.random(1, #t) ] end
    for i = 1, count do
        local r = math.random()
        local entry
        if r < 0.85 then entry = pick(commonItems)
        elseif r < 0.95 then entry = pick(rareItems)
        else entry = pick(ultraRareItems) end

        local owner    = entry.seller:gsub("'", "''")
        local bid      = entry.cost * 10000
        local durations = {720, 1440}
        local timeLeft = durations[ math.random(#durations) ]

        CharDBExecute(string.format([[
            INSERT INTO blackmarketauctionhouse
              (item_id, time, item_owner, start_bid, last_bid)
            VALUES (%d, %d, '%s', %d, %d)
        ]],
            entry.itemId,
            timeLeft,
            owner,
            bid,
            bid
        ))
    end

end

-- track seconds since last 5-minute tick
local tick_position = 0

-- Every 5 minutes: age, flush expired, maybe fill
CreateLuaEvent(function()
    -- 1) count how many auctions we have right now
    local totalQ = CharDBQuery("SELECT COUNT(*) FROM blackmarketauctionhouse")
    local total  = totalQ and totalQ:GetUInt32(0) or 0

    if total ~= 0 then
        -- 2) decrement time on all rows
        CharDBExecute("UPDATE blackmarketauctionhouse SET time = time - 5")

        -- 3) check for expired only if we had rows
        local expQ = CharDBQuery("SELECT COUNT(*) FROM blackmarketauctionhouse WHERE time <= 0")
        if expQ and expQ:GetUInt32(0) > 0 then
            BMAH_FlushLogic()
        end
    end

    -- 4) after potential flush, see if the table is now empty
    local remQ = CharDBQuery("SELECT COUNT(*) FROM blackmarketauctionhouse")
    local rem  = remQ and remQ:GetUInt32(0) or 0
    if rem == 0 then
        if math.random() < AutoFillChance then
            BMAH_FillLogic()
        end
    end
end, 300000, 0)
