-- AutoInput.lua
-- A wrapper that adds autocomplete functionality to an existing Basalt2 Input element

local AutoInput = {}

function AutoInput.new(inputElement, items)
    local self = {
        input = inputElement,
        items = items or {},
        filteredItems = {},
        selectedIndex = 0,
        caseSensitive = false,
        suggestionColor = colors.gray,
        enabled = true,
        separator = ".",
    }
    
    -- Helper: Filter items based on current input
    local function updateFilteredItems()
        self.filteredItems = {}

        if self.input.text == "" then
            self.selectedIndex = 0
            return
        end

        local searchText = self.caseSensitive and self.input.text or self.input.text:lower()

        local function addEntries(prefix, key, item)
            if type(key) == "string" then
                local fullName = prefix == "" and key or prefix .. self.separator .. key
                local compareText = self.caseSensitive and fullName or fullName:lower()
                if compareText:sub(1, #searchText) == searchText then
                    table.insert(self.filteredItems, fullName)
                end

                if type(item) == "table" then
                    for subKey, subItem in pairs(item) do
                        addEntries(fullName, subKey, subItem)
                    end
                end
            elseif type(item) == "string" then
                local fullName = prefix == "" and item or prefix .. self.separator .. item
                local compareText = self.caseSensitive and fullName or fullName:lower()
                if compareText:sub(1, #searchText) == searchText then
                    table.insert(self.filteredItems, fullName)
                end
            end
        end

        for key, item in pairs(self.items) do
            addEntries("", key, item)
        end

        self.selectedIndex = #self.filteredItems > 0 and 1 or 0
    end
    
    -- Helper: Get current suggestion
    local function getCurrentSuggestion()
        return self.filteredItems[self.selectedIndex]
    end
    
    -- Helper: Get suggestion suffix
    local function getSuggestionSuffix()
        local suggestion = getCurrentSuggestion()
        if suggestion and self.input.text ~= "" then
            return suggestion:sub(#self.input.text + 1)
        end
        return ""
    end
    
    -- Helper: Complete suggestion
    local function completeSuggestion()
        local suggestion = getCurrentSuggestion()
        if suggestion then
            self.input:setText(suggestion)
            self.input.cursorPos = #suggestion + 1
            self.filteredItems = {}
            self.selectedIndex = 0
            return true
        end
        return false
    end
    
    -- Helper: Navigate suggestions
    local function navigateSuggestion(direction)
        if #self.filteredItems == 0 then
            return false
        end
        
        if direction > 0 then
            self.selectedIndex = self.selectedIndex + 1
            if self.selectedIndex > #self.filteredItems then
                self.selectedIndex = 1
            end
        else
            self.selectedIndex = self.selectedIndex - 1
            if self.selectedIndex < 1 then
                self.selectedIndex = #self.filteredItems
            end
        end
        
        self.input:updateRender()
        return true
    end
    
    -- Store original functions
    local originalRender = self.input.render
    local originalKey = self.input.key
    local originalChar = self.input.char
    
    -- Override render to show suggestion
    function self.input:render()
        originalRender(self)
        
        if not self.autoInput or not self.autoInput.enabled then
            return
        end
        
        local suffix = getSuggestionSuffix()
        if suffix ~= "" then
            self:textFg(1 + #self.text, 1, suffix, self.autoInput.suggestionColor)
        end
    end

    -- Override char to handle text input
    function self.input:char(char)
        originalChar(self, char)

        if self.autoInput and self.autoInput.enabled then
            updateFilteredItems()
        end
    end

    -- Override key to handle key events
    function self.input:key(key, held)
        if self.autoInput and self.autoInput.enabled then
            if key == keys.down or key == keys.right then
                if navigateSuggestion(1) then
                    return
                end
            elseif key == keys.up or key == keys.left then
                if navigateSuggestion(-1) then
                    return
                end
            elseif key == keys.enter or key == keys.tab then
                if completeSuggestion() then
                    return
                end
            end
        end
        
        -- Call original key handler
        originalKey(self, key, held)

        if self.autoInput and self.autoInput.enabled then
            if key == keys.backspace or key == keys.delete then
                updateFilteredItems()
            end
        end
    end
    
    -- Store reference to wrapper in input element
    self.input.autoInput = self
    return self
end

return AutoInput