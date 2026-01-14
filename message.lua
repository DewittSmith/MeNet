require("shared")

local function initMessage(name, memory)
    return { type = MESSAGE_TYPE.INIT, name = name, memory = memory }
end

local function handshakeMessage(name, memory)
    return { type = MESSAGE_TYPE.HANDSHAKE, name = name, memory = memory }
end

local function nameChangeMessage(name)
    return { type = MESSAGE_TYPE.NAME_CHANGE, name = name }
end

local function shutdownMessage()
    return { type = MESSAGE_TYPE.SHUTDOWN }
end

local function getAvailableMessage(id, requestedItems)
    return { type = MESSAGE_TYPE.GET_AVAILABLE, id = id, items = requestedItems }
end

local function response(id, data)
    return { type = MESSAGE_TYPE.RESPONSE, id = id, data = data }
end

local function executeRequestMessage(id, requestedItems)
    return { type = MESSAGE_TYPE.EXECUTE_REQUEST, id = id, items = requestedItems }
end

local function updateItemMessage(id, item, count)
    return { type = MESSAGE_TYPE.UPDATE_ITEM, id = id, item = item, count = count }
end

return {
    initMessage = initMessage,
    handshakeMessage = handshakeMessage,
    nameChangeMessage = nameChangeMessage,
    shutdownMessage = shutdownMessage,
    getAvailableMessage = getAvailableMessage,
    response = response,
    executeRequestMessage = executeRequestMessage,
    updateItemMessage = updateItemMessage,
}