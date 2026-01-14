local basalt = require("basalt")
local shared = require("shared")
local ui = require("ui")
local node = require("node")

local STATE_FILE = "menet_state.dat"

local oPrint = print
local oPrintError = printError
local loadLines = {}

local function customPrint(...)
    local color = term.current().getTextColor()
    local args = { ... }

    for _, v in ipairs(args) do
        if type(v) ~= "string" then
            v = textutils.serialize(v)
        end

        v = v:gsub("\r\n", "\n")
        v = v:gsub("\r", "\n")

        for line in v:gmatch("([^\n]*)\n?") do
            table.insert(loadLines, { text = line, color = color })
        end
    end
end

print = customPrint
printError = customPrint

if fs.exists(STATE_FILE) then
    print("Loading existing state...")

    local file = fs.open(STATE_FILE, "r")
    local text = file.readAll()
    file.close()

    shared.state:unserialize(text)
end

shared.state.changed.subscribe(function()
    print("State changed, saving...")

    local text = shared.state:serialize()
    local file = fs.open(STATE_FILE, "w")
    file.write(text)
    file.close()
end)

local consoleWin, openConsole = ui.buildUI(shared.state)
local _, consoleHeight = consoleWin.getSize()
for y, line in ipairs(loadLines) do
    if y > consoleHeight then
        consoleWin.scroll(1)
        y = consoleHeight
    end

    consoleWin.setCursorPos(1, y)
    consoleWin.setTextColor(line.color)
    consoleWin.write(line.text)
end

consoleWin.setCursorPos(1, #loadLines + 1)

print = oPrint
printError = oPrintError

local defaultTerm = term.current()
term.redirect(consoleWin)

print("Initializing Node...")

node.setupRednet(shared.state, openConsole)

basalt.schedule(function() 
    basalt.update()
end)

shared.state.settings.name.changed.subscribe(function(_, newValue)
    os.setComputerLabel(newValue)
end)

local function listener()
    local MC_DAY_SECONDS = 20 * 60
    local REAL_DAY_SECONDS = 24 * 60 * 60
    local MC_SECOND_RATIO = MC_DAY_SECONDS / REAL_DAY_SECONDS
    local UPDATE_RATE = 60 * MC_SECOND_RATIO

    local timerId = os.startTimer(UPDATE_RATE)

    while true do
        local eventData = { os.pullEventRaw() }

        if eventData[1] == "terminate" then
            break
        end

        if eventData[1] == "timer" and eventData[2] == timerId then
            shared.state:updateDate()
            timerId = os.startTimer(UPDATE_RATE)
            basalt.update()
            goto continue
        end

        local success, err = pcall(node.update, shared.state, eventData)
        if err then
            printError(err)
        end

        success, err = pcall(basalt.update, table.unpack(eventData))
        if err then
            printError(err)
        end

        ::continue::
    end
end

local function worker()
    while true do
        os.pullEvent("menetWorker")

        local callback = shared.state.callbackQueue:pop()
        while callback ~= nil do
            local success, err = pcall(callback)
            if err then
                printError(err)
            end

            callback = shared.state.callbackQueue:pop()
        end
    end
end

parallel.waitForAny(listener, worker)

term.redirect(defaultTerm)

term.clear()
term.setCursorPos(1,1)

node.closeRednet(shared.state)