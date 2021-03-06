 
--seterrorhandler(print);
function debug(message)
   --print(message);
end

ConfirmLootAwardDialg = 'LootM_ConfirmAwardLoot';

LootMFrames = { };
LootMEvents = { };
LootMItemEvaluator = { };
LootM = CreateFrame("FRAME", "LootM"), { };

LootMFrames["LootM"] = LootM;
LootM.RaidVersion = { };

LootM.Update = function()
    local resetButton = LootMFrames["LootMLootFrame"].ResetButton;
    if (LootM.IsLootMaster()) then
        resetButton:Show();
    else
        resetButton:Hide();
    end

    -- update the version table based on raid roster.
    if IsInRaid() then
        local versionTable = { }
        for i = 1, MAX_RAID_MEMBERS do
            local name = GetRaidRosterInfo(i);
            if (name ~= nil) then
                versionTable[name] = LootM.RaidVersion[name] or "LootM not found";
            end
        end
        LootM.RaidVersion = versionTable;
    else
        LootM.RaidVersion = {};
    end
end

LootM.Init = function()
    StaticPopupDialogs[ConfirmLootAwardDialg] = {
        text = "Are you sure you wish to award %s to %s",
        button1 = ACCEPT,
        button2 = CANCEL,
        OnAccept = function(self, data)
            if (type(data) == 'function') then data(); end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,-- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
    };

    LootM.Update();
end

LootM.PrintRaidAudit = function ()
    print("[LootM] addon raid audit");
    PrintTable(LootM.RaidVersion);
end

function LootMEvents:LOOT_READY(...)
    debug("trying to loot...");
    if (not LootM.IsEnabled() or not LootM.IsLootMaster()) then return; end;
    local lootTable = LootM.GetLootItems();
    if (lootTable == nil or #lootTable == 0) then return; end
    if (LootMItemEntries.IsNewLoot(lootTable)) then
        LootMComms.NewLoot(lootTable);
    else
        LootMItemEntries.Show();
    end
end

function LootMEvents:LOOT_CLOSED(...)

end
function LootMEvents:GROUP_ROSTER_UPDATE(...)
    LootM.Update();
    if IsInRaid() then
        LootMComms.VersionCheck();
    end
end
function LootMEvents:PARTY_LOOT_METHOD_CHANGED(...)
    LootM.Update();
end
function LootMEvents:RAID_INSTANCE_WELCOME(...)
    LootM.Update();
    if IsInRaid() then
        LootMComms.VersionCheck();
    end
end
function LootMEvents:GET_ITEM_INFO_RECEIVED(...)
    if (lootIsntReadyFlag) then
        lootIsntReadyFlag = false;
        LootMEvents.LOOT_READY(...);
    else
        LootMComms.ItemsLoaded(...);
    end
end
function LootMEvents:CHAT_MSG_ADDON(...)
    LootMComms.MessageRecieved(...);
end

function LootMEvents:ADDON_LOADED(...)
    LootM.Init();
end
function LootMEvents:PLAYER_LOOT_SPEC_UPDATED(...)
    LootM.UpdateConfig();
end

LootM:SetScript("OnEvent", function(self, event, ...)
    LootMEvents[event](self, ...);
end );
LootM:SetScript("OnLoad", LootM.Update);

for k, v in pairs(LootMEvents) do
    LootM:RegisterEvent(k);
end

LootM.IsEnabled = function()
    return(IsInRaid() and 'master' == GetLootMethod())
end

LootM.IsLootMaster = function()
    local masterLooterId = select(3, GetLootMethod());
    if masterLooterId then
        return GetRaidRosterInfo(masterLooterId) == GetUnitName("player");
    end
    return false;
end


LootM.GetLootItems = function()
    local lootTable = { };
    for i = 1, GetNumLootItems() do
        local itemLink = GetLootSlotLink(i);
        if (itemLink) then
            _, _, itemRarity = GetItemInfo(itemLink);
            if (itemRarity >= GetLootThreshold()) then
                table.insert(lootTable, itemLink);
            end
        end
    end
    return lootTable;
end

LootM.ResetLoot = function()
    if (not LootM.IsEnabled() or not LootM.IsLootMaster()) then return; end;
    local lootTable = LootM.GetLootItems();
    if (not lootTable) then return; end
    LootMComms.NewLoot(lootTable);
end

LootM.AwardLoot = function(playerName, itemLink)
    local playerWithOutServer = string.gmatch(playerName, "([^-]+)")();
    -- strip the servername off player name
    if (not LootM.IsLootMaster()) then return; end
    local awardLoot = function()
        debug('award loot ' .. itemLink .. ' to player ' .. playerName);
        local lootIndex = 0;
        for i = 1, GetNumLootItems() do
            if (itemLink == GetLootSlotLink(i)) then
                lootIndex = i;
                break;
            end
        end
        if (lootIndex == 0) then
            print('[LootM] Unable to find loot item! (are you looting boss?)');
        end

        for i = 1, 40 do
            local candidate = GetMasterLootCandidate(lootIndex, i);
            if (candidate == nil) then
                print('[LootM] Unable to find player to award loot!');
                break;
            end
            if (candidate == playerWithOutServer) then
                GiveMasterLoot(lootIndex, i);
                LootMComms.Award(itemLink, playerName);
                return;
            end
        end
    end;

    local dialog = StaticPopup_Show(ConfirmLootAwardDialg, itemLink, playerName)
    if (dialog) then
        dialog.data = awardLoot;
    end
end

LootM.GetLootSpecId = function()
    local specId = GetLootSpecialization();
    if (specId == 0) then
        specId = GetSpecializationInfo(GetSpecialization());
    end
    return specId;
end

local lootText = {
    'Take a gander',
    'Ooooh! shiiiny!',
    'May the odds ever be in your favor',
    'Feast your eyes!'
};

LootM.RandomLootText = function()
    return lootText[math.random(#lootText)];
end;

function RegisterFrame(frame)
    if (frame == nil or not frame:GetName()) then return; end
    local frameName = frame:GetName();
    LootMFrames[frameName] = frame;

    if (LootMEvents[frameName .. '_OnLoad']) then
        LootMEvents[frameName .. '_OnLoad'](self, frame);
    end
end

LootMItemEvaluator =( function()

    local inventoryMap = {
        ["INVTYPE_AMMO"] = 0,
        ["INVTYPE_HEAD"] = 1,
        ["INVTYPE_NECK"] = 2,
        ["INVTYPE_SHOULDER"] = 3,
        ["INVTYPE_BODY"] = 4,
        ["INVTYPE_CHEST"] = 5,
        ["INVTYPE_ROBE"] = 5,
        ["INVTYPE_WAIST"] = 6,
        ["INVTYPE_LEGS"] = 7,
        ["INVTYPE_FEET"] = 8,
        ["INVTYPE_WRIST"] = 9,
        ["INVTYPE_HAND"] = 10,
        ["INVTYPE_FINGER"] = { 11, 12 },
        ["INVTYPE_TRINKET"] = { 13, 14 },
        ["INVTYPE_CLOAK"] = 15,
        ["INVTYPE_THROWN"] = 18,
        ["INVTYPE_RELIC"] = 18,
        ["INVTYPE_TABARD"] = 19,
    };

    local tokenIcons = {
        ["interface\\icons\\inv_chest_chain_10.blp"] = 5,
        ["interface\\icons\\inv_gauntlets_29.blp"] = 10,
        ["interface\\icons\\inv_helmet_24.blp"] = 1,
        ["interface\\icons\\inv_misc_desecrated_platepants.blp"] = 7,
        ["interface\\icons\\inv_shoulder_22.blp"] = 3,
    };

    local offHandItemType, twoHandItemType, oneHandItemType = "offhand", "twohand", "onehand";
    local offHandItems = {
        ["INVTYPE_SHIELD"] = 17,
        ["INVTYPE_WEAPONOFFHAND"] = 17,
        ["INVTYPE_HOLDABLE"] = 17,-- off hand
    };

    local twoHandItems = {
        ["INVTYPE_2HWEAPON"] = { 16, 17 },
        ["INVTYPE_RANGED"] = { 16, 17 },-- bows (2h)
    };

    local oneHandItems = {
        ["INVTYPE_WEAPON"] = { 16, 17 },
        ["INVTYPE_WEAPONMAINHAND"] = 16,
        ["INVTYPE_RANGEDRIGHT"] = 16,-- main wands
    };

    local function getPlayerInventoryItem(slotId)
        return GetInventoryItemLink('player', slotId);
    end
    -- the premis on thsi one is that a token is misc/junk with specific textures for each slot
    -- as long as the game keeps that, we can assume these will be tokens
    local function getItemTokenSlot(itemType, itemSubType, itemTexture)
        if (itemType ~= 'Miscellaneous' or itemSubType ~= 'Junk') then return nil; end
        return tokenIcons[string.lower(itemTexture)];
    end

    local function getPlayerWeaponRelatedItems(itemLink, itemEquipLocation)
        -- this is rather complicated. The gloal here is readability, so have some repetitive code
        local playerItems = { };
        local lootItemType, playerItemType;
        local mainHandSlot, offHandSlot = 16, 17;

        if (offHandItems[itemEquipLocation]) then
            -- is the looted item an offhand?
            lootItemType = offHandItemType;
            local offHandItem = getPlayerInventoryItem(offHandSlot);

            if (not offHandItem) then
                -- loot item is an offhand, but equipped 2 hander
                playerItemType = twoHandItemType;
                playerItems[1] = getPlayerInventoryItem(mainHandSlot);
            else
                -- loot item is offhand and has equipped offhand/one hander
                playerItemType = offHandItemType;
                playerItems[1] = offHandItem;
            end
        elseif (oneHandItems[itemEquipLocation]) then
            -- is the looted item a one hander?
            lootItemType = oneHandItemType;
            local offHandItem = getPlayerInventoryItem(offHandSlot);

            if (not offHandItem) then
                -- looted item is 1h but have equipped a 2h
                playerItemType = twoHandItemType;
                playerItems[1] = getPlayerInventoryItem(mainHandSlot);
            else
                -- item loot is 1 hand and have equipped 1handers
                playerItemType = oneHandItemType;
                playerItems[1] = getPlayerInventoryItem(mainHandSlot);
                playerItems[2] = offHandItem;
            end
        elseif (twoHandItems[itemEquipLocation]) then
            -- is the looted item a two hander?
            lootItemType = twoHandItemType;
            local offHandItem = getPlayerInventoryItem(offHandSlot);

            if (not offHandItem) then
                -- loot item is 2h and has equipped a 2h
                playerItemType = twoHandItemType;
                playerItems[1] = getPlayerInventoryItem(mainHandSlot);
            else
                -- loot item is 2h and has equpped 1hx2 or mh,oh
                playerItemType = oneHandItemType;
                playerItems[1] = getPlayerInventoryItem(mainHandSlot);
                playerItems[2] = offHandItem;
            end
        else
            return nil;
        end
        return playerItems, lootItemType, playerItemType;
    end

    local function getPlayerRelatedItems(itemLink)
        local _, _, _, _, _, itemType, itemSubType, _, itemEquipLocation, itemTexture = GetItemInfo(itemLink);

        -- check to see if the item is a token, then assing the appropreate inventory slot for said token
        local playerSlot = getItemTokenSlot(itemType, itemSubType, itemTexture);

        if (not playerSlot) then
            -- weapons are handled differently
            local a, b, c = getPlayerWeaponRelatedItems(itemLink, itemEquipLocation);
            if (a) then
                return a, b, c;
            else
                playerSlot = inventoryMap[itemEquipLocation];
            end
        end

        local dataType = type(playerSlot);
        local playerItems = { };

        if (dataType == 'number') then
            local equippedItemLink = getPlayerInventoryItem(playerSlot);
            if (equippedItemLink) then
                table.insert(playerItems, equippedItemLink);
            end
        elseif (dataType == 'table') then
            for k, v in pairs(playerSlot) do
                local equippedItemLink = getPlayerInventoryItem(v);
                if (equippedItemLink) then
                    table.insert(playerItems, equippedItemLink);
                end
            end
        end
        -- returns item links for the equpped item and a bool if the item is a weapon
        return playerItems, nil, nil;
    end;

    local function getItemValue(itemLink, weightTable)
        local itemStats = GetItemStats(itemLink);
        local itemValue = 0;
        for k, v in pairs(itemStats) do
            local weight = weightTable[k];
            if (weight and weight > 0) then
                itemValue = itemValue +(v * weight);
            end
        end
        return itemValue;
    end;

    local function getItemImprovementRating(equippedValue, newValue)
        local value = 0;
        if (equippedValue > 0 and newValue > 0) then
            value =(newValue - equippedValue) / equippedValue;
            value = math.max(0, value);
            value = math.floor(value * 100);
        end
        return value;
    end

    local function calculateImprovementRating(itemLink, playerItems, statWeights, lootItemType, playerItemType)
        local improvementRating = 0;
        local new = getItemValue(itemLink, statWeights);
        -- if the items are not weapons, or the weapons are the same
        -- the comparison is straight forward
        -- lootItemType is set in function (getPlayerWeaponRelatedItems)
        if (not lootItemType or(lootItemType == playerItemType)) then
            for k, v in pairs(playerItems) do
                local old = getItemValue(v, statWeights);
                improvementRating = math.max(getItemImprovementRating(old, new), improvementRating);
            end
        elseif (lootItemType == twoHandItemType) then
            -- not the same, so player type is 1 or offhand
            local equippedValue =
            getItemValue(playerItems[1], statWeights) +
            getItemValue(playerItems[2], statWeights);
            -- add the value of both equipped weapons to compare against 2h
            improvementRating = getItemImprovementRating(equippedValue, new);
        elseif (lootItemType == oneHandItemtype or lootItemType == offHandItemType) then
            -- player should have a 2h
            local equippedValue = getItemValue(playerItems[1], statWeights);
            improvementRating = getItemImprovementRating(equippedValue,(new * 2));
        end
        return math.min(99, math.max(0, improvementRating));
        -- capped between 0 and 99
    end

    return {
        GetPlayerItemDetails = function(itemLink)
            -- find out which items we are interested in comparing against the looted item.
            local playerItems, lootItemType, playerItemType = getPlayerRelatedItems(itemLink);
            -- calculate an improvement rating agaist the player equipped items
            local improvementRating =
            calculateImprovementRating(itemLink, playerItems, LootM.GetPlayerStatWeights(), lootItemType, playerItemType);
            return { PlayerItems = playerItems, ImprovementRaiting = improvementRating };
        end,
        GetItemValue = function(itemLink, weightTable)
            return getItemValue(itemLink, weightTable);
        end,
        GetTokenType = function(itemLink)
            local _, _, _, _, _, itemType, itemSubType, _, itemEquipLocation, itemTexture = GetItemInfo(itemLink);
            local slotIndex = getItemTokenSlot(itemType, itemSubType, itemTexture);
            if (not slotIndex) then return; end
            for k, v in pairs(inventoryMap) do
                if (v == slotIndex) then
                    return _G[k];
                end
            end
        end,
    };

end )();

-- LootM_Show
-- /lootm
SLASH_LOOTM1 = '/lootm';
SlashCmdList["LOOTM"] = function(message)
    local rollType, name;
    if (string.sub(message, 1, 6) == 'config') then
        LootM.ShowConfig();
    elseif (string.sub(message, 1, 1) == 'v' or
        string.sub(message, 1, 7) == 'version') then
        print("[LootM] " .. GetAddOnMetadata("LootM", "Version"));
    elseif (string.sub(message, 1, 5) == "audit") then
        LootM.PrintRaidAudit();
    else
        LootMItemEntries.Show();
    end

    -- ** used for internal testing ** --
--        if (string.sub(message, 1, 4) == 'test') then
--            LootMComms.NewLoot( { string.sub(message, 5) });
--        elseif (string.sub(message, 1, 4) == 'need') then
--            name = string.sub(message, 6);
--            rollType = '1';
--        elseif (string.sub(message, 1, 4) == 'gree') then
--            name = string.sub(message, 7);
--            rollType = '2';
--        elseif (string.sub(message, 1, 5) == 'award') then
--            LootMComms.Award(LootMItemEntries.GetItems()[1], 'TheNewGuy');

--        end
--        if (rollType) then
--            local x = LootMItemEntries.GetItems();
--            local playerDetails = LootMItemEvaluator.GetPlayerItemDetails(x[1]);
--            LootMItemEntries.SetPlayerRoll(x[1],
--            name or 'TheNewGuy',
--            'DAMAGER', rollType,
--            playerDetails.PlayerItems,
--            playerDetails.ImprovementRaiting);
--        end
end;

-- table sort iterator
-- http://stackoverflow.com/a/15706820
function spairs(t, order)
    -- collect the keys
    local keys = { }
    for k in pairs(t) do table.insert(keys, k) end

    -- if order function given, sort by it by passing the table and keys a, b,
    -- otherwise just sort the keys
    if order then
        table.sort(keys, function(a, b) return order(t, a, b) end)
    else
        table.sort(keys)
    end

    -- return the iterator function
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
end


 function PrintTable(t)
    for k, v in pairs(t) do
        print(k .. ": " .. v);
    end
 end

-- Recieve rolls via tell
-- Broadcast loot via tells to non-addon clients
-- prevent need on non-usable items (Encounter Journal)
-- spirit only to healers, bonus armor only to tanks (Encounter journal)
-- Improvement ratings on trinkets?


-- known issues:
-- duplicate items don't show rolls for that item
