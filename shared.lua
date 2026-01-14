require("event")

PROTOCOL = "menet"

STATUS = {
    PENDING = "Pending",
    DONE = "Done",
    BUSY = "Busy",
    ERROR = "Error",
    SENT = "Sent",
}

MESSAGE_TYPE = {
    INIT = "init",
    SHUTDOWN = "shutdown",
    HANDSHAKE = "handshake",
    NAME_CHANGE = "name_change",
    GET_AVAILABLE = "get_available",
    EXECUTE_REQUEST = "execute_request",
    UPDATE_ITEM = "update_item",
}

local state = {
    changed = event(),
    dateUpdated = event(),
    outgoingRequests = observableTable(),
    incomingRequests = observableTable(),
    knownNodes = observableTable(),
    modemName = "",

    _id = 1,

    settings = {
        name = observableProperty(os.getComputerLabel()),
        importer = observableProperty(),
        allowImport = observableProperty(true),
        allowExport = observableProperty(true),
        allowCrafting = observableProperty(true),
    },

    meBridges = observableTable(),
    redstoneOuts = observableTable(),
    exportOuts = observableTable(),
    callbackQueue = {
        push = function(self, callback)
            table.insert(self, callback)
        end,

        pop = function(self)
            return #self == 0 and nil or table.remove(self, 1)
        end,
    },

    _memoryHashmap = {},
    nameMemory = {},
    memory = {},

    updateDate = function(self)
        local date = self:getCurrentDate()
        self.dateUpdated.invoke(date)
    end,

    rememberItem = function(self, itemName)
        if self._memoryHashmap[itemName] then
            return
        end

        self._memoryHashmap[itemName] = true
        local namespace = string.match(itemName, "(.-):")

        local memory = self.memory[namespace]
        if not memory then
            memory = {}
            self.memory[namespace] = memory
        end

        table.insert(memory, itemName:sub((namespace and #namespace + 2) or 1 ))
        table.insert(self.nameMemory, itemName)
    end,

    getDate = function(self, day, time)
        local hours = math.floor(time)
        local minutes = math.floor((time - hours) * 60)
        local seconds = math.floor(((time - hours) * 60 - minutes) * 60)

        return { 
            time = time,
            day = day, 
            hours = hours, 
            minutes = minutes, 
            seconds = seconds,
            totalSeconds = day * 24 * 60 * 60 + time * 60 * 60,
            tostring = function(self, format)
                return string.format(format or "%02d %02d:%02d:%02d", self.day, self.hours, self.minutes, self.seconds)
            end,
        }
    end,

    getCurrentDate = function(self) 
        return self:getDate(os.day(), os.time()) 
    end,

    addOutgoingRequest = function(self, items)
        local request = {
            id = self._id,
            created = self:getCurrentDate(),
            updated = self:getCurrentDate(),
            items = {},
        }

        for i, item in ipairs(items) do
            request.items[i] = {
                name = item.name,
                count = item.count,
                status = STATUS.PENDING,
                progress = 0,
                id = i,
            }
        end

        table.sort(request.items, function(a, b) return a.name < b.name end)
        
        self._id = self._id + 1
        self.outgoingRequests.set(request.id, request)
    end,

    resendRequest = function(self, request)
        request.created = self:getCurrentDate()
        request.updated = self:getCurrentDate()
        request.error = nil

        for _, item in ipairs(request.items) do
            item.status = STATUS.PENDING
            item.progress = 0
            item.worker = nil
        end

        self.outgoingRequests.set(request.id, request)
    end,

    removeOutgoingRequest = function(self, id)
        local request = self.outgoingRequests.get(id)
        if request then
            self.outgoingRequests.set(id, nil)
        end
    end,

    formatName = function(self, name, id)
        if name == nil then
            name = self.settings.name.get()
        end

        local validName = string.gsub(name or "", "^%s*(.-)%s*$", "%1")
        if validName == nil or validName == "" then
            return "Computer " .. (id or os.getComputerID())
        end

        return validName
    end,

    unserialize = function(self, text)
        local data = textutils.unserialize(text)

        if data then
            for id, request in pairs(data.outgoingRequests or {}) do
                for i, item in ipairs(request.items) do
                    item.id = i
                end

                local parsed = {
                    id = id,
                    created = self:getDate(request.created.day, request.created.time),
                    updated = self:getDate(request.updated.day, request.updated.time),
                    items = request.items,
                }

                if request.error then
                    parsed.error = request.error
                end

                self.outgoingRequests.set(id, parsed)
            end

            for id, request in pairs(data.incomingRequests or {}) do
                for i, item in ipairs(request.items) do
                    item.id = i
                end

                local parsed = {
                    id = id,
                    created = self:getDate(request.created.day, request.created.time),
                    updated = self:getDate(request.updated.day, request.updated.time),
                    items = request.items,
                }

                if request.error then
                    parsed.error = request.error
                end

                self.incomingRequests.set(id, parsed)
            end

            for id, node in pairs(data.knownNodes or {}) do
                self.knownNodes.set(id, {
                    id = id,
                    name = node.name,
                    redstoneOut = { text = node.redstoneOut },
                    exportOut = { text = node.exportOut },
                })
            end

            if data.settings then
                self.settings.importer.set(data.settings.importer)
                self.settings.allowImport.set(data.settings.allowImport)
                self.settings.allowExport.set(data.settings.allowExport)
                self.settings.allowCrafting.set(data.settings.allowCrafting)
            end

            if data.id then
                self._id = data.id
            end
        end
    end,

    serialize = function(self)
        local outgoing = {}
        local incoming = {}
        local nodes = {}

        for id, request in pairs(self.outgoingRequests.table) do
            local items = {}
            for i, item in ipairs(request.items) do
                items[i] = {
                    name = item.name,
                    count = item.count,
                    status = item.status,
                    progress = item.progress,
                }

                if item.worker then
                    items[i].worker = { name = item.worker.name, id = item.worker.id }
                end
            end

            outgoing[id] = { 
                created = { time = request.created.time, day = request.created.day },
                updated = { time = request.updated.time, day = request.updated.day },
                items = items,  
            }

            if request.error then
                outgoing[id].error = request.error
            end
        end

        for id, request in pairs(self.incomingRequests.table) do
            local items = {}
            for i, item in ipairs(request.items) do
                items[i] = {
                    name = item.name,
                    count = item.count,
                    status = item.status,
                    progress = item.progress,
                }

                if item.worker then
                    items[i].worker = { name = item.worker.name, id = item.worker.id }
                end
            end

            incoming[id] = { 
                created = { time = request.created.time, day = request.created.day },
                updated = { time = request.updated.time, day = request.updated.day },
                items = items,  
            }

            if request.error then
                incoming[id].error = request.error
            end
        end

        for id, node in pairs(self.knownNodes.table) do
            nodes[id] = {
                name = node.name,
                redstoneOut = (node.redstoneOut or {}).text,
                exportOut = (node.exportOut or {}).text,
            }
        end

        return textutils.serialize({
            outgoingRequests = outgoing,
            incomingRequests = incoming,
            knownNodes = nodes,
            settings = {
                importer = self.settings.importer.get(),
                allowImport = self.settings.allowImport.get(),
                allowExport = self.settings.allowExport.get(),
                allowCrafting = self.settings.allowCrafting.get(),
            },
            id = self._id,
        })
    end,
}

state.outgoingRequests.itemAdded.subscribe(state.changed.invoke)
state.outgoingRequests.itemRemoved.subscribe(state.changed.invoke)
state.outgoingRequests.itemChanged.subscribe(state.changed.invoke)

state.incomingRequests.itemAdded.subscribe(state.changed.invoke)
state.incomingRequests.itemRemoved.subscribe(state.changed.invoke)
state.incomingRequests.itemChanged.subscribe(state.changed.invoke)

state.knownNodes.itemAdded.subscribe(state.changed.invoke)
state.knownNodes.itemRemoved.subscribe(state.changed.invoke)
state.knownNodes.itemChanged.subscribe(state.changed.invoke)

state.settings.importer.changed.subscribe(state.changed.invoke)
state.settings.allowImport.changed.subscribe(state.changed.invoke)
state.settings.allowExport.changed.subscribe(state.changed.invoke)
state.settings.allowCrafting.changed.subscribe(state.changed.invoke)

state.meBridges.itemAdded.subscribe(function(_, bridge)
    for _, item in pairs(bridge.listItems() or {}) do        
        state:rememberItem(item.name)
    end

    for _, item in pairs(bridge.listCraftableItems() or {}) do        
        state:rememberItem(item.name)
    end
end)

local validName = string.gsub(state.settings.name.get() or "", "^%s*(.-)%s*$", "%1")
if validName == nil or validName == "" then
    state.settings.name.set(nil)
    os.setComputerLabel(nil)
end

local sides = { "right", "left", "front", "back", "top", "bottom" }

for _, dir in ipairs(sides) do
    state.redstoneOuts.insert({ source = "computer", direction = dir, text = dir })
end

for _, relay in ipairs({ peripheral.find("redstone_relay") }) do
    local name = peripheral.getName(relay)
    for _, dir in ipairs(sides) do
        state.redstoneOuts.insert({ source = name, direction = dir, text = name .. ":" .. dir })
    end
end

for _, bridge in ipairs({ peripheral.find("meBridge") }) do
    state.meBridges.insert(bridge)
end

for _, inventory in ipairs({ peripheral.find("inventory") }) do
    local name = peripheral.getName(inventory)
    state.exportOuts.insert({ target = name, text = name })
end

return {
    state = state,
    sides = sides,
}