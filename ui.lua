local basalt = require("basalt")
local AutoInput = require("elements/AutoInput")
require("event")

local style = {
    canvas = colors.black,
    panel = colors.gray,
    control = colors.lightGray,

    text = colors.white,
    mutedText = colors.black,
    placeholder = colors.yellow,

    accent = colors.blue,
    highlight = colors.lightBlue,
    link = colors.cyan,
    focus = colors.lightBlue,

    success = colors.green,
    error = colors.red,
    warning = colors.orange,
    info = colors.purple,

    tabControl = function(self, instance)
        instance.background = self.panel
        instance.foreground = self.text
        instance.headerBackground = self.panel
        instance.activeTabBackground = self.panel
        instance.activeTabTextColor = self.accent
        return instance
    end,

    frame = function(self, instance)
        instance.background = self.panel
        instance.foreground = self.text
        return instance
    end,

    scrollFrame = function(self, instance)
        instance.background = self.control
        instance.foreground = self.text
        instance.scrollBarColor = self.accent
        instance.scrollBarBackgroundColor = self.control
        instance.scrollBarBackgroundColor2 = self.panel
        return instance
    end,

    button = function(self, instance)
        instance.background = self.control
        instance.foreground = self.text
        instance:setBackgroundState("clicked", self.highlight)
        instance:setForegroundState("clicked", self.text)
        instance:registerState("disabled", function(element) return element.enabled end, 1000)
        instance:setBackgroundState("disabled", self.control)
        instance:setForegroundState("disabled", self.mutedText)
        instance:setEnabledState("disabled", false)
        return instance
    end,

    table = function(self, instance)
        instance.background = self.control
        instance.foreground = self.text
        instance.headerColor = self.accent
        instance.gridColor = self.highlight
        instance.scrollBarColor = self.accent
        instance.scrollBarBackgroundColor = self.panel
        instance.selectedBackground = self.highlight
        instance.selectedForeground = self.text
        return instance
    end,

    comboBox = function(self, instance)
        instance.background = self.control
        instance.foreground = self.text
        instance.scrollBarColor = self.accent
        instance.scrollBarBackgroundColor = self.panel
        instance.selectedBackground = self.accent
        instance.selectedForeground = self.text
        return instance
    end,

    input = function(self, instance)
        instance.background = self.control
        instance.foreground = self.text
        instance.placeholderColor = self.placeholder
        return instance
    end,

    switch = function(self, instance)
        instance.background = self.control
        instance.foreground = self.text
        instance.onBackground = self.accent
        instance.offBackground = self.mutedText
        return instance
    end,

    primaryText = function(self, instance)
        instance.foreground = self.text
        return instance
    end,

    secondaryText = function(self, instance)
        instance.foreground = self.mutedText
        return instance
    end,

    accentText = function(self, instance)
        instance.foreground = self.accent
        return instance
    end,
}

local openOutgoingEvt = event()
local openNewRequestEvt = event()

local function buildConsoleTab(tab, _)
    local width, height = term.getSize()

    local display = tab:addDisplay({
        width = width,
        height = height - 1
    })

    local win = display:getWindow()
    return win
end

local function buildOutgoingTab(tab, state)
    local COUNT_WIDTH = 7
    local STATUS_WIDTH = 7

    local content = tab:addFrame({
        width = "{parent.width}",
        height = "{parent.height}",
        backgroundEnabled = false,
    })
    
    local requestsTable = style:table(content:addTable({
        width = "{parent.width}",
        height = "{parent.height - 7}",
        columns = {
            { name = "Item", width = "{parent.width - " .. (COUNT_WIDTH + STATUS_WIDTH) .. "}" },
            { name = "Count", width = COUNT_WIDTH },
            { name = "Status", width = STATUS_WIDTH }
        }
    }))

    local RID_IDX = #requestsTable.columns + 1
    local IID_IDX = RID_IDX + 1

    for _, request in pairs(state.outgoingRequests.table) do
        for _, item in ipairs(request.items) do
            requestsTable:addRow(item.name, item.count, item.status, request.id, item.id)
        end
    end

    local addRequestButton = style:button(content:addButton({
        width = 13,
        height = 3,
        text = "Add Request",
    })):toBottom(1):toRight()

    addRequestButton:onClick(openNewRequestEvt.invoke)

    local selectedLabel = style:primaryText(content:addLabel({
        height = 1,
        text = "Selected: ",
    })):toLeft():below(requestsTable, 1)

    local infoFrame = content:addFrame({ 
        width = "{parent.width - " .. (addRequestButton.width + 1) .. "}",
        height = 5,
        visible = false,
        backgroundEnabled = false,
    }):below(requestsTable, 2)

    local selectedValueLabel = style:accentText(content:addLabel({
        height = 1,
        text = "None",
    })):alignRight(infoFrame):below(requestsTable, 1)

    local workerLabel = style:primaryText(infoFrame:addLabel({
        height = 1,
        text = "Worker: ",
    })):toLeft()

    local workerValueLabel = style:accentText(infoFrame:addLabel({
        height = 1,
        text = "N/A",
    })):toRight()

    local createdLabel = style:primaryText(infoFrame:addLabel({
        height = 1,
        text =  "Created: ",
    })):below(workerLabel, 1):toLeft()

    local createdValueLabel = style:accentText(infoFrame:addLabel({
        height = 1,
        text = "N/A",
    })):below(workerLabel, 1):toRight()

    local updatedLabel = style:primaryText(infoFrame:addLabel({
        height = 1,
        text = "Updated: ",
    })):below(createdLabel, 1):toLeft()

    local updatedValueLabel = style:accentText(infoFrame:addLabel({
        height = 1,
        text = "N/A",
    })):below(createdLabel, 1):toRight()

    local progressLabel =  style:primaryText(infoFrame:addLabel({
        height = 1,
        text = "Progress: ",
    })):below(updatedLabel, 1):toLeft()

    local progressValueLabel = style:accentText(infoFrame:addLabel({
        height = 1,
        text = "0",
    })):below(updatedLabel, 1):toRight()

    local errorLabel = style:primaryText(infoFrame:addLabel({
        height = 1,
        text = "Error: ",
    })):below(progressLabel, 1):toLeft()

    local errorValueLabel = style:accentText(infoFrame:addLabel({
        height = 1,
        text = "None",
    })):below(progressLabel, 1):toRight()

    local selectedDelete = style:button(content:addButton({
        width = 5,
        height = 1,
        text = "DEL",
    })):below(requestsTable, 1):toRight(8):setState("disabled")

    selectedDelete:onClick(function()
        local row = requestsTable:getSelectedRow()
        if not row then
            return
        end

        local cells = row._data.cells
        local id = cells[RID_IDX]
        state.outgoingRequests.remove(id)
    end)

    local selectedUpdate = style:button(content:addButton({
        width = 5,
        height = 1,
        text = "UPD",
    })):below(requestsTable, 1):toRight():setState("disabled")

    selectedUpdate:onClick(function()
        local row = requestsTable:getSelectedRow()
        if not row then
            return
        end

        local cells = row._data.cells
        local id = cells[RID_IDX]
        local request = state.outgoingRequests.get(id)

        state:resendRequest(request)
    end)

    local function updateInfoFrame(request, item)
        selectedValueLabel:setText(item.name .. " (ID: " .. request.id .. "/" .. item.id .. ")"):alignRight(infoFrame)
        if item.worker then
            workerValueLabel:setText(item.worker.name .. " (" .. item.worker.id .. ")"):alignRight(infoFrame)
        else
            workerValueLabel:setText("N/A"):alignRight(infoFrame)
        end

        createdValueLabel:setText(request.created:tostring()):alignRight(infoFrame)
        updatedValueLabel:setText(request.updated:tostring()):alignRight(infoFrame)

        progressValueLabel:setText(item.progress .. " / " .. item.count):alignRight(infoFrame)
        errorValueLabel:setText(request.error or "None"):alignRight(infoFrame)

        selectedDelete:unsetState("disabled")
        selectedUpdate:unsetState("disabled")
    end

    state.outgoingRequests.itemAdded.subscribe(function(_, request)
        for _, item in pairs(request.items) do
            requestsTable:addRow(item.name, item.count, item.status, request.id, item.id)
        end
    end)

    state.outgoingRequests.itemRemoved.subscribe(function(_, request) 
        local rows = requestsTable:getData()
        local offset = 0
        for i, row in ipairs(rows) do
            local j = i + offset
            if row[RID_IDX] == request.id then
                if requestsTable:getSelectedIndex() == j then
                    infoFrame:setVisible(false)
                    selectedValueLabel:setText("None"):alignRight(infoFrame)
                    selectedDelete:setState("disabled")
                    selectedUpdate:setState("disabled")
                end

                requestsTable:removeRow(j)
                offset = offset - 1
            end
        end
    end)

    state.outgoingRequests.itemChanged.subscribe(function(_, _, request) 
        local items = request.items
        for _, item in ipairs(items) do
            for i, row in ipairs(requestsTable:getData()) do
                if row[RID_IDX] == request.id and row[IID_IDX] == item.id then
                    requestsTable:updateCell(i, 1, item.name)
                    requestsTable:updateCell(i, 2, item.count)
                    requestsTable:updateCell(i, 3, item.status)

                    if requestsTable:getSelectedIndex() == i then
                        updateInfoFrame(request, item)
                    end

                    break
                end
            end
        end
    end)

    requestsTable:onRowSelect(function(_, index, row)
        local cells = row._data.cells
        local id = cells[RID_IDX]
        local request = state.outgoingRequests.get(id)
        local itemId = cells[IID_IDX]

        for _, item in ipairs(request.items) do
            if item.id == itemId then
                infoFrame:setVisible(true)
                updateInfoFrame(request, item)
                break
            end
        end
    end)

    return content
end

local function buildNewRequestWindow(tab, state)
    local content = tab:addFrame({
        width = "{parent.width}",
        height = "{parent.height}",
        backgroundEnabled = false,
    })

    local backButton = style:button(content:addButton({
        width = 13,
        height = 3,
        text = "Back",
    })):toBottom(1):toRight()

    backButton:onClick(function()
        openOutgoingEvt.invoke()
    end)

    local itemInput = style:input(content:addInput({
        width = "{parent.width - 10}",
        height = 1,
        placeholder = "minecraft:diamond"
    }))

    local itemAutoInput = AutoInput.new(itemInput, state.memory)
    itemAutoInput.suggestionColor = style.placeholder
    itemAutoInput.separator = ":"
    itemAutoInput.caseSensitive = false

    local xLabel = style:primaryText(content:addLabel({
        height = 1,
        text = " x ",
    })):rightOf(itemInput, 1)

    local countInput = style:input(content:addInput({
        width = 5,
        height = 1,
        placeholder = "64"
    })):rightOf(xLabel, 1)

    local requestTable = style:table(content:addTable({
        width = "{parent.width}",
        height = "{parent.height - 8}",
        columns = {
            { name = "Item", width = "{parent.width - 7}" },
            { name = "Count", width = 7 },
        }
    })):below(itemInput, 3)

    local addButton = style:button(content:addButton({
        width = 5,
        height = 1,
        text = "Add",
    })):above(requestTable, 1)

    addButton:onClick(function()
        local itemName = itemInput:getText()
        local countText = countInput:getText()
        local count = tonumber(countText) or 64

        if itemName ~= "" then
            requestTable:addRow(itemName, count)
            itemInput:setText("")
            countInput:setText("")
        end
    end)

    local removeButton = style:button(content:addButton({
        width = 8,
        height = 1,
        text = "Remove",
    })):rightOf(addButton, 2):above(requestTable, 1)

    removeButton:onClick(function()
        local selectedIndex = requestTable:getSelectedIndex()
        if selectedIndex then
            requestTable:removeRow(selectedIndex)
        end
    end)

    local submitButton = style:button(content:addButton({
        width = 13,
        height = 3,
        text = "Submit",
    })):toBottom(1)

    submitButton:onClick(function()
        local items = {}
        for _, item in ipairs(requestTable:getData()) do
            local noSpace = string.gsub(item[1] or "", "%s+", "")
            table.insert(items, {
                name = noSpace,
                count = tonumber(item[2]) or 64,
            })
        end

        if #items > 0 then
            state:addOutgoingRequest(items)
            requestTable:clearData()
            openOutgoingEvt.invoke()
        end
    end)

    local clearButton = style:button(content:addButton({
        width = 13,
        height = 3,
        text = "Clear",
    })):toBottom(1):rightOf(submitButton, 2)

    clearButton:onClick(function()
        requestTable:clearData()
    end)

    return content
end

local function buildIncomingTab(tab, state)
    local content = tab:addFrame({
        width = "{parent.width}",
        height = "{parent.height}",
        backgroundEnabled = false,
    })

    local infoLabel = style:primaryText(content:addLabel({
        text = "TODO",
    }))

    return content
end

local function buildSettingsTab(tab, state)
    local content = tab:addFrame({
        width = "{parent.width}",
        height = "{parent.height}",
        backgroundEnabled = false,
    })

    local nameLabel = style:primaryText(content:addLabel({
        height = 1,
        text = "Name: ",
    }))

    local nameInput = style:input(content:addInput({
        width = "{parent.width - " .. (nameLabel.width + 1) .. "}",
        height = 1,
        text = state.settings.name.get() or "",
        placeholder = "Enter name..."
    })):rightOf(nameLabel, 1)

    nameInput:onChange("text", function(_, text)
        state.settings.name.set(text)
    end)

    local importLabel = style:primaryText(content:addLabel({
        height = 1,
        text = "Importer: ",
    })):below(nameLabel, 2)

    local importComboBox = style:comboBox(content:addComboBox({
        width = "{parent.width - " .. (importLabel.width + 1) .. "}",
        height = 1,
        items = state.exportOuts.table,
        selectedText = "none",
        autoComplete = true,
        dropdownHeight = 6,
    })):rightOf(importLabel, 1):below(nameLabel, 2)

    for i, imp in ipairs(importComboBox.items) do
        if imp.text == state.settings.importer.get() then
            importComboBox:selectItem(i)
            importComboBox:setText(imp.text)
            break
        end
    end

    importComboBox:onChange("text", function(_, text)
        local noSpace = string.gsub(value or "", "%s+", "")

        if noSpace == "" then
            state.settings.importer.set(nil)
        else
            for _, out in pairs(state.exportOuts.table) do
                if out.text == noSpace then
                    state.settings.importer.set(out.target)
                    break
                end
            end
        end
    end)

    importComboBox:onSelect(function(_, _, value) 
        state.settings.importer.set(value.target)
    end)

    local allowImportSwitch = style:switch(content:addSwitch({
        height = 1,
        text = "Allow Import",
        checked = state.settings.allowImport.get()
    })):below(importLabel, 2)

    allowImportSwitch:onChange("checked", function(_, checked)
        state.settings.allowImport.set(checked)
    end)

    local allowExportSwitch = style:switch(content:addSwitch({
        height = 1,
        text = "Allow Export",
        checked = state.settings.allowExport.get()
    })):below(allowImportSwitch, 1)

    allowExportSwitch:onChange("checked", function(_, checked)
        state.settings.allowExport.set(checked)
    end)

    local allowCraftingSwitch = style:switch(content:addSwitch({
        height = 1,
        text = "Allow Crafting",
        checked = state.settings.allowCrafting.get()
    })):below(allowExportSwitch, 1) 

    allowCraftingSwitch:onChange("checked", function(_, checked)
        state.settings.allowCrafting.set(checked)
    end)

    local nodeListHeader = content:addFrame({
        width = "{parent.width}",
        height = 1,
        background = style.control,
    }):below(allowCraftingSwitch, 2)

    local COMBO_WIDTH = 16
    nodeListHeader:addLabel({
        height = 1,
        text = "Name (ID)",
        foreground = style.accent,
    })

    nodeListHeader:addLabel({
        width = COMBO_WIDTH,
        height = 1,
        text = "Redstone Out",
        foreground = style.accent,
    }):toRight(COMBO_WIDTH + 1)

    nodeListHeader:addLabel({
        width = COMBO_WIDTH,
        height = 1,
        text = "Export Out",
        foreground = style.accent,
    }):toRight()

    local nodeControls = {}
    local nodeListFrame = style:scrollFrame(content:addScrollFrame({
        width = "{parent.width}",
        height = "{parent.height - 10}",
    })):below(nodeListHeader, 1)

    local function reorder()
        local y = 1
        for _, control in pairs(nodeControls) do
            control.frame:setVisible(control.visible)
            if control.visible then
                control.frame.y = y
                y = y + 1
            end
        end
    end

    local function addNodeControl(id, node)
        local FRAME_HEIGHT = 7
        local frame = nodeListFrame:addFrame({
            height = 1,
            width = "{parent.width}",
            backgroundEnabled = false,
        })

        local frameZ = frame.z

        local label = style:primaryText(frame:addLabel({
            height = 1,
            text = node.name .. " (" .. id .. ")",
            width = "{parent.width - " .. (COMBO_WIDTH * 2 + 2) .. "}",
        }))

        local redstoneOutCombo = style:comboBox(frame:addComboBox({
            width = COMBO_WIDTH,
            selectedText = "none",
            items = state.redstoneOuts.table,
            autoComplete = true,
            dropdownHeight = 6,
        })):setBackground(style.focus):toRight(COMBO_WIDTH + 1)

        for i, out in ipairs(redstoneOutCombo.items) do
            if node.redstoneOut and out.text == node.redstoneOut.text then
                redstoneOutCombo:selectItem(i)
                redstoneOutCombo:setText(out.text)
                node.redstoneOut = out
                break
            end
        end

        redstoneOutCombo:onChange("text", function(_, value)
            local noSpace = string.gsub(value or "", "%s+", "")

            if noSpace == "" then
                node.redstoneOut = nil
                state.knownNodes.set(id, node)
            else
                for _, out in pairs(state.redstoneOuts.table) do
                    if out.text == noSpace then
                        node.redstoneOut = out
                        state.knownNodes.set(id, node)
                        break
                    end
                end
            end
        end)

        redstoneOutCombo:onSelect(function(_, _, value) 
            node.redstoneOut = value
            state.knownNodes.set(id, node)
        end)

        redstoneOutCombo:onChange("height", function(_, value)
            if redstoneOutCombo:hasState("opened") then
                for _, control in pairs(nodeControls) do
                    control.frame.enabled = false
                end

                frame.enabled = true
                frame.height = FRAME_HEIGHT
                frame.z = frameZ + 1
            else
                for _, control in pairs(nodeControls) do
                    control.frame.enabled = true
                end

                frame.height = 1
                frame.z = frameZ
            end
        end)

        local exportOutCombo = style:comboBox(frame:addComboBox({
            width = COMBO_WIDTH,
            selectedText = "none",
            items = state.exportOuts.table,
            autoComplete = true,
            dropdownHeight = 6,
        })):setBackground(style.focus):toRight()

        for i, out in ipairs(exportOutCombo.items) do
            if node.exportOut and out.text == node.exportOut.text then
                exportOutCombo:selectItem(i)
                exportOutCombo:setText(out.text)
                node.exportOut = out
                break
            end
        end

        exportOutCombo:onChange("text", function(_, value)
            local noSpace = string.gsub(value or "", "%s+", "")

            if noSpace == "" then
                node.exportOut = nil
                node.state.knownNodes.set(id, node)
            else
                for _, out in pairs(state.exportOuts.table) do
                    if out.text == noSpace then
                        node.exportOut = out
                        state.knownNodes.set(id, node)
                        break
                    end
                end
            end
        end)

        exportOutCombo:onSelect(function(_, _, value) 
            node.exportOut = value
            state.knownNodes.set(id, node)
        end)

        exportOutCombo:onChange("height", function(_, value)
            if exportOutCombo:hasState("opened") then
                for _, control in pairs(nodeControls) do
                    control.frame.enabled = false
                end

                frame.enabled = true
                frame.height = FRAME_HEIGHT
                frame.z = frameZ + 1
            else
                for _, control in pairs(nodeControls) do
                    control.frame.enabled = true
                end

                frame.height = 1
                frame.z = frameZ
            end
        end)

        nodeControls[id] = {
            frame = frame,
            label = label,
            redstoneOutCombo = redstoneOutCombo,
            exportOutCombo = exportOutCombo,
            visible = node.isOnline,
        }

        reorder()
    end

    state.knownNodes.itemAdded.subscribe(addNodeControl)

    state.knownNodes.itemChanged.subscribe(function(id, _, node)
        local control = nodeControls[id]
        if not control then
            addNodeControl(id, node)
            control = nodeControls[id]
        end

        if control then
            control.label:setText(node.name .. " (" .. id .. ")")
            control.visible = node.isOnline
            reorder()
        end
    end)
end

local function buildUI(state)
    local main = basalt.getMainFrame()

    local tabControl = style:tabControl(main:addTabControl({
        width = "{parent.width}",
        height = "{parent.height}",
    }))

    local DATE_FORMAT = "%02d %02d:%02d"
    local currentDateLabel = style:accentText(main:addLabel({
        height = 1,
        text = "00 00:00",
        z = tabControl.z + 1,
    })):toRight()

    basalt.schedule(function()
        sleep()
        currentDateLabel:setText(state:getCurrentDate():tostring(DATE_FORMAT)):toRight()
    end)

    state.dateUpdated.subscribe(function(date)
        currentDateLabel:setText(date:tostring(DATE_FORMAT)):toRight()
    end)

    local outgoingTab = tabControl:newTab("Outgoing")
    local outgoing = buildOutgoingTab(outgoingTab, state)
    local newRequest = buildNewRequestWindow(outgoingTab, state)
    newRequest.visible = false

    openOutgoingEvt.subscribe(function()
        outgoing:setVisible(true)
        newRequest:setVisible(false)
    end)

    openNewRequestEvt.subscribe(function()
        outgoing:setVisible(false)
        newRequest:setVisible(true)
    end)

    local incomingTab = tabControl:newTab("Incoming")
    buildIncomingTab(incomingTab, state)

    local settingsTab = tabControl:newTab("Settings")
    buildSettingsTab(settingsTab, state)

    local consoleTab = tabControl:newTab("Console")
    local consoleWin = buildConsoleTab(consoleTab, state)
    local consoleTabIdx = #tabControl.tabs

    local openConsole = function()
        tabControl:setActiveTab(consoleTabIdx)
    end

    return consoleWin, openConsole
end

return {
    buildUI = buildUI
}