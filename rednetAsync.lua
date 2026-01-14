local awaitedMessages = {}
local RESPONSE = "response"

local function request(targetId, message, protocol, timeout)
    if not message.id then
        error("Message must have an 'id' field for request")
    end

    local co = coroutine.running()
    if co == nil then
        error("request must be called from within a coroutine")
    end

    local handle = { coroutine = co }

    if timeout then
        local timer = os.startTimer(timeout)
        handle.timer = timer
    end

    awaitedMessages[message.id] = handle
    rednet.send(targetId, message, protocol)
    return coroutine.yield()
end

local function response(targetId, request, data, protocol)
    rednet.send(targetId, { type = RESPONSE, id = request.id, data = data }, protocol)
end

local function feedEvent(eventData)
    if eventData[1] ~= "timer" then
        return false
    end

    local timer = eventData[2]
    for messageId, handle in pairs(awaitedMessages) do
        if handle.timer == timer then
            awaitedMessages[messageId] = nil
            coroutine.resume(handle.coroutine, "timeout")
            return true
        end
    end

    return false
end

local function feedResponse(message)
    if message.type ~= RESPONSE then
        return false
    end

    local handle = awaitedMessages[message.id]
    if handle then
        os.cancelTimer(handle.timer)
        awaitedMessages[message.id] = nil
        coroutine.resume(handle.coroutine, message.data)
    end

    return true
end

return {
    RESPONSE = RESPONSE,
    request = request,
    response = response,
    feedResponse = feedResponse,
    feedEvent = feedEvent,
}