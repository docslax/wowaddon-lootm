-- fortunatly the communication requirements for this are fairly straight forward, so the formatting is rutamentry

LootMComms =( function()

    local raidMessageType = "OFFICER";
    -- changed for testing
    -- local raidMessageType = "RAID";
    local newLootPrefix = 'LootMNew';
    local rollPrefix = 'LootMRoll';
    local awardPrefix = 'LootMAward';
    local newLootMessageSpool = {};
    local pendingMessages = { };

    local function processNewLootMessage(itemCount)
        -- deturmins if the new loot spool has all the items expected then calls out for the items to be loaded
        if (not newLootMessageSpool) then
            newLootMessageSpool = {};
            return;
        end

        local i =0;
        for i in pairs(newLootMessageSpool) do
            i = i + 1;
        end
        if (i ~= itemCount) then
            return;
        end

        LootMItemEntries.Hide();
        for k,itemLink in pairs(newLootMessageSpool) do
            LootMItemEntries.ShowItem(itemLink);    
        end    
        LootMItemEntries.Show();
        print('[LootM] Staring new loot session. Take a gandar');
    end

    
    -- a dictionary of message prefixes (used as message type) and funtions to handle/parse the message
    -- see below for the format of each message type
    local chatMessageHandlers = {
        [newLootPrefix] = function(message, sender)
            local parsedMessage = {};
            for i in string.gmatch("([^;]+)") do
                table.insert(parsedMessage, i);
            end
            local messageCount, messageIndex, itemLink = unpack(parsedMessage);
            if (newLootMessageSpool[messageIndex]) then
                -- this shoudnt happen
                newLootMessageSpool = {};
            end

            -- if the item is not loaded, pend the message untill the server can get us info about the item
            if (not GetItemInfo(itemLink)) then
                table.insert(pendingMessages,
                {
                    MessageType = newLootPrefix,
                    Message = message,
                    Sender = sender,
                });
                return;
            end

            newLootMessageSpool[messageIndex] = itemLink;
            processNewLootMessage(messsageCount);
        end,
        [rollPrefix] = function(message, sender)
            local parsedMessage = {};
            for i in string.gmatch("([^;]+)") do
                table.insert(parsedMessage, i);
            end
            local rollId, itemLink, improvementRating, playerItems = (function(a, b, c, ...)
                return a,b,c,{...};
            end)(unpack(parsedMessage));

            -- We are not short-circuting this logic because we want to make sure all
            -- items are being requested from the server.
            local requiresItemLoad = (not GetItemInfo(itemLink));
            for k,item in pairs(playerItems) do
                if (not GetItemInfo(item)) then
                    requiresItemLoad = true;
                end
            end

            if (requiresItemLoad) then
                table.insert(pendingMessages,
                {
                    MessageType = rollPrefix,
                    Message = message,
                    Sender = sender,
                });
                return;
            end

            LootMItemEntries.SetPlayerRoll(itemLink, sender, rollId, playerItems, improvementRating);
        end,
        [awardPrefix] = function(message, sender) return; end,
    };

    -- main event handler which dispatches the message to a handler based on prefix
    local chatMessageEvent = function(prefix, message, distType, sender)
        local f = chatMessageHandlers[prefix];
        if (f) then f(message, sender); end;
    end;

    local itemsLoaded = function()
        -- swap out the table so we can process the messages
        local messages, pendingMessages = pendingMessages, {};
        -- re call into each handler, if the item is still not loaded it will reque the message.
        for k,v in pairs(messages) do
            local f = chatMessageHandlers[v.MessageType];
            if (f) then 
                f(v.Message, v.Sender); 
            end
        end
    end

    for k,v in pairs(chatMessageHandlers) do
        RegisterAddonMessagePrefix(k);
    end

    return {
        -- signals to raid members new lootable items are available from the loot master
        NewLoot = function(lootTable)
            local lootCount = #lootTable;
            for i, v in ipairs(lootTable) do
                -- [total messages];[this message index];[item link]
                SendAddonMessage(
                    newLootPrefix, 
                    table.concat({lootCount, i, v}, ";"),
                    raidMessageType);
            end
        end,

        -- singles a player's roll selection on a item being looted
        Roll = function(rollId, itemLink, playerItems, improvementRating)

            local message = { rollId, itemLink, improvementRating };
            if (playerItems) then
                for k,v in pairs(playerItems) do
                    table.insert(message, v);
                end
            end
            -- [rollid];[item being rolled on];[improvementrating];[table...of player equipped items]
            SendAddonMessage(rollPrefix, table.concat(message, ';'), raidMessageType);
        end,
        -- TODO: Implement award
        Award = function(itemLink, awardee) return; end,
        MessageRecieved = chatMessageEvent,-- proxy to publically expose the handler
        ItemsLoaded = ItemsLoaded, -- proxy for even when item data is received from server
    };

end )();