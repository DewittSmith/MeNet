function event()
    local listeners = {}

    return {
        subscribe = function(listener)
            table.insert(listeners, listener)
        end,

        unsubscribe = function(listener)
            for i, l in ipairs(listeners) do
                if l == listener then
                    table.remove(listeners, i)
                    break
                end
            end
        end,

        invoke = function(...)
            for _, listener in ipairs(listeners) do
                listener(...)
            end
        end,
    }
end

function observableProperty(initialValue)
    local value = initialValue

    local changed = event()

    return {
        changed = changed,

        get = function() 
            return value
        end,

        set = function(newValue)
            if value ~= newValue then
                local oldValue = value
                value = newValue
                changed.invoke(oldValue, newValue)
            end
        end,
    }
end

function observableTable()
    local tbl = {}

    local itemAdded = event()
    local itemRemoved = event()
    local itemChanged = event()

    return {
        itemAdded = itemAdded,
        itemRemoved = itemRemoved,
        itemChanged = itemChanged,
        table = tbl,

        get = function(key)
            return tbl[key]
        end,

        set = function(key, value)
            local oldValue = tbl[key]
            tbl[key] = value

            if oldValue == nil and value ~= nil then
                itemAdded.invoke(key, value)
            elseif oldValue ~= nil and value == nil then
                itemRemoved.invoke(key, oldValue)
            else
                itemChanged.invoke(key, oldValue, value)
            end
        end,

        remove = function(key)
            local oldValue = tbl[key]
            if oldValue ~= nil then
                tbl[key] = nil
                itemRemoved.invoke(key, oldValue)
            end
        end,

        insert = function(value, key)
            if key == nil then
                key = #tbl + 1
            end

            local oldValue = tbl[key]
            table.insert(tbl, key, value)

            if oldValue == nil and value ~= nil then
                itemAdded.invoke(key, value)
            elseif oldValue ~= nil and value == nil then
                itemRemoved.invoke(key, oldValue)
            else
                itemChanged.invoke(key, oldValue, value)
            end
        end,
    }
end