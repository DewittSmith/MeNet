local shared = require("shared")
local message = require("message")
local rednetAsync = require("rednetAsync")

local function setupRednet(state, openConsole)
    if not peripheral.isPresent(state.modemName) then
        local modem = peripheral.find("modem", function(_, modem)
            return modem.isWireless()
        end)

        if not modem then
            printError("No wireless modem found")

            if openConsole then
                openConsole()
            end

            return
        else
            state.modemName = peripheral.getName(modem)
            print("Wireless modem found: " .. state.modemName)
        end
    end

    if rednet.isOpen(state.modemName) then
        rednet.close(state.modemName)
    end

    rednet.open(state.modemName)
    rednet.broadcast(message.initMessage(state:formatName(), state.nameMemory), PROTOCOL)
    print("Rednet opened on modem: " .. state.modemName)

    state.settings.name.changed.subscribe(function() 
        rednet.broadcast(message.nameChangeMessage(state:formatName()), PROTOCOL) 
    end)

    local function onRequestAdded(request)
        local onlineCount = 0
        for _, node in pairs(state.knownNodes.table) do
            if node.isOnline then
                onlineCount = onlineCount + 1
            end
        end

        if onlineCount == 0 then
            print("Cannot fulfill request ID " .. request.id .. ": no available nodes")
            for _, item in ipairs(request.items) do
                item.status = STATUS.ERROR
            end
            request.error = "No available nodes"
            request.updated = state:getCurrentDate()
            state.outgoingRequests.set(request.id, request)
            return
        end

        local normalizedItems = {}
        for i, item in ipairs(request.items) do
            normalizedItems[i] = {
                name = item.name,
                count = item.count,
            }
        end

        coroutine.wrap(function()
            local responses = {}
            local allTimeout = true
            for id, node in  pairs(state.knownNodes.table) do
                if node.isOnline then
                    local result = rednetAsync.request(id, message.getAvailableMessage(request.id, normalizedItems), PROTOCOL, 1)
                    if result == "timeout" then
                        print("Node " .. node.name .. " (" .. id .. ") did not respond in time")
                    else
                        allTimeout = false
                        responses[id] = result
                    end
                end
            end

            -- Evaluate best node
            local function canFulfillAll(nodeResponse, requested)
                for _, req in ipairs(requested) do
                    local found = false
                    for _, avail in ipairs(nodeResponse) do
                        if avail.name == req.name and avail.count >= req.count then
                            found = true
                            break
                        end
                    end
                    if not found then return false end
                end
                return true
            end

            local function canFulfillWithCraft(nodeResponse, requested)
                for _, req in ipairs(requested) do
                    local avail = nil
                    for _, a in ipairs(nodeResponse) do
                        if a.name == req.name then
                            avail = a
                            break
                        end
                    end
                    if not avail or (avail.count < req.count and not avail.isCraftable) then
                        return false
                    end
                end
                return true
            end

            local function totalItems(nodeResponse)
                local sum = 0
                for _, avail in ipairs(nodeResponse) do
                    sum = sum + avail.count
                end
                return sum
            end

            local fullProviders = {}
            local craftableProviders = {}

            for id, resp in pairs(responses) do
                if canFulfillAll(resp, normalizedItems) then
                    table.insert(fullProviders, {id = id, total = totalItems(resp)})
                elseif canFulfillWithCraft(resp, normalizedItems) then
                    table.insert(craftableProviders, {id = id, total = totalItems(resp)})
                end
            end

            local bestNode = nil
            if #fullProviders > 0 then
                table.sort(fullProviders, function(a, b) return a.total > b.total end)
                bestNode = fullProviders[1].id
            elseif #craftableProviders > 0 then
                table.sort(craftableProviders, function(a, b) return a.total > b.total end)
                bestNode = craftableProviders[1].id
            end

            request.updated = state:getCurrentDate()
            if bestNode then
                local worker = state.knownNodes.get(bestNode)

                for _, item in ipairs(request.items) do
                    item.worker = worker
                    item.status = STATUS.BUSY
                end

                rednet.send(bestNode, message.executeRequestMessage(request.id, request.items), PROTOCOL)
                print("Request assigned to node " .. worker.name .. " (" .. bestNode .. ")")
            else
                for _, item in ipairs(request.items) do
                    item.status = STATUS.ERROR
                end

                if allTimeout then
                    request.error = "Request timed out"
                    print("Cannot fulfill request ID " .. request.id .. ": all nodes timed out")
                else
                    request.error = "Cannot fulfill request"
                    print("Cannot fulfill request ID " .. request.id .. ": no available nodes")
                end
            end

            state.outgoingRequests.set(request.id, request)
        end)()
    end

    state.outgoingRequests.itemAdded.subscribe(function(_, request)
        onRequestAdded(request)
    end)

    state.outgoingRequests.itemChanged.subscribe(function(_, _, request)
        for _, item in ipairs(request.items) do
            if item.status == STATUS.PENDING then
                onRequestAdded(request)
                break
            end
        end
    end)
end

local function closeRednet(state)
    if rednet.isOpen(state.modemName) then
        rednet.broadcast(message.shutdownMessage(), PROTOCOL)
        rednet.close(state.modemName)
        print("Rednet closed on modem: " .. state.modemName)
    end
end

local function executeRequest(target, exportOut, redstoneOut, msg, state)
    local DELAY = 1
    local MAX_ITERATIONS = 4

    local ignoreList = { 
        ["gtceu:programmed_circuit"] = true,
     }

    local exportPeripheral = peripheral.wrap(exportOut.target)

    local function isExportEmpty()
        local contents = exportPeripheral.list()
        while contents == nil do
            contents = exportPeripheral.list()
            sleep(DELAY)
        end

        for _, item in pairs(contents) do
            if item and not ignoreList[item.name] and item.count > 0 then
                return false
            end
        end
        
        return true
    end

    local function launchItems()
        local relay = peripheral.wrap(redstoneOut.source)
        if redstoneOut.source == "computer" then
            relay = redstone
        end

        relay.setOutput(redstoneOut.direction, false)
        while isExportEmpty() do sleep(DELAY) end
        local exported = exportPeripheral.list()
        relay.setOutput(redstoneOut.direction, true)
        while not isExportEmpty() do sleep(DELAY) end
        relay.setOutput(redstoneOut.direction, false)

        for _, item in pairs(exported) do
            if item and not ignoreList[item.name] and item.count > 0 then
                rednet.send(target, message.updateItemMessage(msg.id, item.name, item.count), PROTOCOL)
            end
        end
    end

    local function exportItem(me, name, count)
        if count == 0 then
            return 0
        end

        while true do
            local storedItem = me.getItem({ name = name })
            if storedItem == nil or storedItem.amount == 0 then
                return 0, false
            end

            local extractCount = math.min(storedItem.amount, count)
            local exported = me.exportItemToPeripheral({ name = name, count = extractCount }, exportOut.target)
            return exported, (storedItem.amount - exported) > 0
        end
    end

    local function craftItem(me, name, count, onYield)
        local BATCH_SIZE = 16

        local iTable = { name = name }
        local item = me.getItem(iTable)
        if item == nil or not item.isCraftable then
            return
        end

        local toCraft = count

        repeat
            while me.isItemCrafting(iTable) do
                sleep(DELAY)
            end

            item = me.getItem(iTable)

            if item.amount > 0 then
                local toYield = math.min(item.amount, toCraft)
                toCraft = toCraft - toYield
                onYield(toYield)
            else
                local batchToCraft = math.min(BATCH_SIZE, toCraft)
                while not me.isItemCrafting(iTable) do
                    me.craftItem({ name = name, count = batchToCraft })
                    sleep(DELAY)
                end
            end
        until toCraft == 0
    end

    for _, item in pairs(msg.items) do
        local name = item.name
        local toExport = item.count

        for _, me in ipairs(state.meBridges.table) do
            if toExport <= 0 then
                break
            end

            while toExport > 0 do
                print("Attempting to export " .. toExport .. " of item")
                print("  " .. name)

                local exported, hasMore = exportItem(me, name, toExport)

                if exported > 0 then
                    print("Exported " .. exported .. "/" .. toExport .. " of item")
                    print("  " .. name)
                    toExport = toExport - exported
                else
                    if isExportEmpty() then
                        break
                    elseif hasMore then
                        launchItems()
                    else
                        break
                    end
                end
            end

            if toExport > 0 then
                print("Crafting " .. toExport .. " of item")
                print("  " .. name)

                craftItem(me, name, toExport, function(yielded)
                    while yielded > 0 do
                        local exported = exportItem(me, name, yielded)
                        yielded = yielded - exported
                        toExport = toExport - exported

                        if exported == 0 and yielded > 0 then
                            launchItems()
                        end
                    end
                end)

                print("Finished crafting item")
                print("  " .. name)
            end
        end

        if toExport > 0 then
            print("Could not fully fulfill item " .. name .. ", remaining: " .. toExport)
        end
    end

    if not isExportEmpty() then
        launchItems()
    end

    print("Request execution completed")
end

local function update(state, eventData)
    local function processRednetMessage(sender, msg, protocol)
        if protocol ~= PROTOCOL then
            return
        end

        if rednetAsync.feedResponse(msg) then
            return
        end

        if msg.type == MESSAGE_TYPE.INIT then
            local existingNode = state.knownNodes.get(sender) or {}
            existingNode.id = sender
            existingNode.name = msg.name
            existingNode.isOnline = true
            state.knownNodes.set(sender, existingNode)
            print(existingNode.name .. " (" .. sender .. ") joined the network")

            for _, itemName in pairs(msg.memory) do
                state:rememberItem(itemName)
            end

            rednet.send(sender, message.handshakeMessage(state:formatName(), state.nameMemory), protocol)
        elseif msg.type == MESSAGE_TYPE.HANDSHAKE then
            local existingNode = state.knownNodes.get(sender) or {}
            existingNode.id = sender
            existingNode.name = msg.name
            existingNode.isOnline = true
            state.knownNodes.set(sender, existingNode)
            print("Received handshake from " .. existingNode.name .. " (" .. sender .. ")")

            for _, itemName in pairs(msg.memory) do
                state:rememberItem(itemName)
            end
        elseif msg.type == MESSAGE_TYPE.NAME_CHANGE then
            if not state.knownNodes.get(sender) then
                print("Received NAME_CHANGE from unknown node " .. sender)
                return
            end

            local node = state.knownNodes.get(sender)
            local oldName = node.name
            node.name = msg.name
            state.knownNodes.set(sender, node)

            print("Node " .. sender .. " changed name from " .. oldName .. " to " .. state.knownNodes.get(sender).name)
        elseif msg.type == MESSAGE_TYPE.SHUTDOWN then
            if not state.knownNodes.get(sender) then
                print("Received SHUTDOWN from unknown node " .. sender)
                return
            end

            local node = state.knownNodes.get(sender)
            node.isOnline = false
            state.knownNodes.set(sender, node)

            print(node.name .. " (" .. sender .. ") left the network")
        elseif msg.type == MESSAGE_TYPE.GET_AVAILABLE then
            local node = state.knownNodes.get(sender)
            local availableItems = {}

            if (node.redstoneOut.source == "computer" or peripheral.isPresent(node.redstoneOut.source or "")) and peripheral.isPresent(node.exportOut.target or "") then
                for i, item in ipairs(msg.items) do
                    local iTable = { name = item.name }
                    local foundItem = { name = item.name, count = 0, isCraftable = false }
                    for _, me in pairs(state.meBridges.table) do
                        local storedItem = me.getItem(iTable)
                        if storedItem then
                            foundItem.count = foundItem.count + storedItem.amount
                            foundItem.isCraftable = foundItem.isCraftable or storedItem.isCraftable
                        end
                    end

                    if foundItem.count > 0 or foundItem.isCraftable then
                        availableItems[i] = foundItem
                    end
                end
            end

            rednetAsync.response(sender, msg, availableItems, protocol)
        elseif msg.type == MESSAGE_TYPE.EXECUTE_REQUEST then
            local node = state.knownNodes.get(sender)
            if not node then
                print("Received EXECUTE_REQUEST from unknown node " .. sender)
                return
            end

            print("Received request from " .. node.name .. " (" .. sender .. ")")

            state.callbackQueue:push(function() executeRequest(sender, node.exportOut, node.redstoneOut, msg, state) end)
            os.queueEvent("menetWorker")
        elseif msg.type == MESSAGE_TYPE.UPDATE_ITEM then
            local request = state.outgoingRequests.get(msg.id)
            if not request then
                print("Received UPDATE_ITEM for unknown request ID " .. msg.id)
                return
            end

            local allSent = true
            local toDistribute = msg.count
            for _, item in ipairs(request.items) do
                if toDistribute > 0 and item.name == msg.item and item.status == STATUS.BUSY then
                    local toAdd = math.min(toDistribute, item.count - (item.progress or 0))
                    toDistribute = toDistribute - toAdd
                    item.progress = (item.progress or 0) + toAdd
                    if item.progress >= item.count then
                        item.status = STATUS.SENT
                    end
                end

                if item.status ~= STATUS.SENT then
                    allSent = false
                end
            end

            if allSent then
                local target = state.settings.importer.get()
                for _, item in ipairs(request.items) do
                    item.status = STATUS.DONE

                    local totalImported = 0
                    for _, me in pairs(state.meBridges.table) do
                        local imported = 0

                        repeat
                            imported = me.importItemFromPeripheral(item, target)
                            totalImported = totalImported + imported
                            if imported > 0 then
                                print("Imported " .. imported .. " of item " .. item.name .. " from request ID " .. request.id)
                            end
                        until imported == 0

                        if totalImported >= item.count then
                            break
                        end
                    end
                end
            end

            request.updated = state:getCurrentDate()
            state.outgoingRequests.set(msg.id, request)
        else
            print("Unknown message type from " .. sender)
        end
    end

    if rednetAsync.feedEvent(eventData) then
        return
    end

    local eventType = eventData[1]
    if eventType == "rednet_message" then
        processRednetMessage(eventData[2], eventData[3], eventData[4])
    elseif eventType == "peripheral" then
        local name = eventData[2]

        local addedRedstone, addedExport, addedBridge, addedModem = false, false, false, false
        if peripheral.hasType(name, "redstone_relay") then
            for _, dir in ipairs(shared.sides) do
                state.redstoneOuts.insert({ source = name, direction = dir, text = name .. ":" .. dir })
                addedRedstone = true
            end
        end

        if peripheral.hasType(name, "meBridge") then
            local bridge = peripheral.wrap(name)
            state.meBridges.insert(bridge)
            addedBridge = true
        end

        if peripheral.hasType(name, "inventory") then
            state.exportOuts.insert({ target = name, text = name })
            addedExport = true
        end

        if peripheral.hasType(name, "modem") and state.modemName == "" then
            local modem = peripheral.wrap(name)
            if modem.isWireless() then
                state.modemName = name
                addedModem = true
                setupRednet(state)
            end
        end

        if addedRedstone then
            print("Redstone output '" .. name .. "' added")
        end

        -- if addedExport then
        --     print("Export output '" .. name .. "' added")
        -- end

        if addedBridge then
            print("ME Bridge '" .. name .. "' added")
        end

        if addedModem then
            print("Modem '" .. name .. "' added")
        end
    elseif eventType == "peripheral_detach" then
        local name = eventData[2]
        
        local removedRedstone, removedExport, removedBridge, removedModem = false, false, false, false
        for key, redstoneOut in pairs(state.redstoneOuts.table) do
            if redstoneOut.source == name then
                state.redstoneOuts.remove(key)
                removedRedstone = true
            end
        end

        for key, exportOut in pairs(state.exportOuts.table) do
            if exportOut.target == name then
                state.exportOuts.remove(key)
                removedExport = true
            end
        end

        for key, bridge in pairs(state.meBridges.table) do
            if peripheral.getName(bridge) == name then
                state.meBridges.remove(key)
                removedBridge = true
            end
        end

        if state.modemName == name then
            closeRednet(state)
            removedModem = true
            state.modemName = ""
        end

        if removedRedstone then
            print("Redstone output '" .. name .. "' removed")
        end

        -- if removedExport then
        --     print("Export output '" .. name .. "' removed")
        -- end

        if removedBridge then
            print("ME Bridge '" .. name .. "' removed")
        end

        if removedModem then
            print("Modem '" .. name .. "' removed")
        end
    end
end

return {
    setupRednet = setupRednet,
    closeRednet = closeRednet,
    update = update,
}