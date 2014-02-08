local curses = require 'curses'
require "class"

-- Initialize curses and get the initial window size
----------------------------------------------------
curses.initscr()
curses.cbreak()
curses.echo(false)  -- not noecho !
curses.nl(0)    -- not nonl !
local stdscr = curses.stdscr()  -- it's a userdatum
stdscr:keypad(1)
stdscr:clear()
local window_y, window_x = stdscr:getmaxyx()
local window_x = math.min(window_x, 99)
local mvaddstr = function (...) stdscr:mvaddstr(...) end

local entry_line = ""
local RadixMode = "Hex"
local base = {Hex = 16, Dec = 10, Bin = 10}

-- Item Definitions
-------------------
Dec = class()
function Dec:__init(value)
    if type(value) == "string" then value = tonumber(value) end
    self.value = value or 0
end
Dec.Description = "Decimal"
function Dec:__tostring()
    return tostring(self.value)
end
function Dec:new(item) return Dec(item or self.value) end

Bin = class()
function Bin:__init(value)
    if type(value) == "string" and string.find(entry_line, "^# ") then
        value = tonumber(string.sub(entry_line, 3), base[RadixMode])
    end
    self.value = value or 0
end
Bin.Description = "Bin"
function Bin:__tostring()
    if RadixMode == "Hex" then
        return string.format("# %xh", math.floor(self.value))
    elseif RadixMode == "Bin" then
        return string.format("# %bb", math.floor(self.value))
    elseif RadixMode == "Dec" then
        return string.format("# %dd", math.floor(self.value))
    end
end
function Bin:new(item) return Bin(item or self.value) end

-- Stack Class definition
-------------------------
StackClass = class()
function StackClass:__init(args)
    self.stack = {}
    self.status = ""
    if args then
        self.stack = args.stack or {}
        self.status = args.status or ""
    end
end

function StackClass:redraw()
    local stack_length = #self.stack
    local stack_starting_line = stack_length - (window_y - 2)
    mvaddstr(0, 0, string.format("%"..window_x.."s", self.status))

    local active_width = window_x - 4 -- 4 comes from the stack_item size, plus the :
    local format = "%3s:%"..tostring(active_width).."s"
    for i=1, window_y - 2 do
        local stack_pointer = i + stack_starting_line
        local stack_item = window_y - 1 - i
        if stack_pointer < 1 then
            --There is no stack, this is a clear line
            mvaddstr(i, 0, string.format(format, stack_item, " "))
        else
            --Add item from the stack
            num_string = tostring(self.stack[stack_pointer])
            mvaddstr(i, 0, string.format(format, '*'..tostring(stack_item), num_string))
        end
    end
end

function StackClass:AddItem(item)
    if item == "# " then
        item = ""
    elseif string.find(item, "e$") then
        item = item .. "0"
    end

    if item == "" then
        self:Duplicate()
    elseif string.find(item, "^# .") then
        table.insert(self.stack, Bin(item))
    else
        table.insert(self.stack, Dec(item))
    end
end

function StackClass:DropItem()
    table.remove(self.stack)
end

function StackClass:Addition()
    if #self.stack < 2 then return end
    local a = table.remove(self.stack)
    local b = table.remove(self.stack)
    table.insert(self.stack, a:new(a.value + b.value))
end

function StackClass:Subtract()
    if #self.stack < 2 then return end
    local a = table.remove(self.stack)
    local b = table.remove(self.stack)
    table.insert(self.stack, a:new(b.value - a.value))
end

function StackClass:Multiply()
    if #self.stack < 2 then return end
    local a = table.remove(self.stack)
    local b = table.remove(self.stack)
    table.insert(self.stack, a:new(a.value * b.value))
end

function StackClass:Divide()
    if #self.stack < 2 then return end
    local divisor = table.remove(self.stack)
    local numerator = table.remove(self.stack)
    table.insert(self.stack, divisor:new(numerator.value/divisor.value))
end

function StackClass:Reciprocal()
    if #self.stack < 1 then return end
    local a = table.remove(self.stack)
    table.insert(self.stack, a:new(1/a.value))
end

function StackClass:Negate()
    if #self.stack < 1 then return end
    local a = table.remove(self.stack)
    table.insert(self.stack, a:new(-a.value))
end

function StackClass:Swap()
    if #self.stack < 2 then return end
    local a = table.remove(self.stack)
    local b = table.remove(self.stack)
    table.insert(self.stack, a)
    table.insert(self.stack, b)
end

function StackClass:Duplicate()
    if #self.stack > 0 then
        local a = table.remove(self.stack)
        table.insert(self.stack, a)
        table.insert(self.stack, a:new())
    end
end

-- keymaps
----------
local keymap = {}
keymap['0'] = function(stack) catNumber('0') end
keymap['1'] = function(stack) catNumber('1') end
keymap['2'] = function(stack) catNumber('2') end
keymap['3'] = function(stack) catNumber('3') end
keymap['4'] = function(stack) catNumber('4') end
keymap['5'] = function(stack) catNumber('5') end
keymap['6'] = function(stack) catNumber('6') end
keymap['7'] = function(stack) catNumber('7') end
keymap['8'] = function(stack) catNumber('8') end
keymap['9'] = function(stack) catNumber('9') end
keymap['a'] = function(stack) if RadixMode == "Hex" then keymap['#'](stack) catNumber('a') end end
keymap['b'] = function(stack) if RadixMode == "Hex" then keymap['#'](stack) catNumber('b') end end
keymap['c'] = function(stack) if RadixMode == "Hex" then keymap['#'](stack) catNumber('c') end end
keymap['d'] = function(stack) if RadixMode == "Hex" then keymap['#'](stack) catNumber('d') end end
keymap['e'] = function(stack) if RadixMode == "Hex" then keymap['#'](stack) catNumber('e') end end
keymap['f'] = function(stack) if RadixMode == "Hex" then keymap['#'](stack) catNumber('f') end end
keymap['A'] = keymap['a']
keymap['B'] = keymap['b']
keymap['C'] = keymap['c']
keymap['D'] = keymap['d']
keymap['E'] = keymap['e']
keymap['F'] = keymap['f']

keymap['#'] = function(stack)
    if entry_line == "" then
        entry_line = "# "
    elseif not string.find(entry_line, "^# ") then
        entry_line = "# " .. entry_line
    end
end

keymap['.'] = function(stack)
    if not string.find(entry_line, '%.') and not string.find(entry_line, "^# ") then
        catNumber('.')
    end
end

keymap['x'] = function (stack)
    if entry_line == "" then
        entry_line = "1e"
    elseif not string.find(entry_line, 'e') and not string.find(entry_line, "^# ") then
        catNumber('e')
    end
end

keymap[curses.KEY_BACKSPACE] = function(stack)
    if entry_line == "" then
        stack:DropItem()
    elseif entry_line == "# " then
        entry_line = ""
    else
        entry_line = string.sub(entry_line, 1, -2)
    end
end

keymap['+'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Addition()
    entry_line = ""
end

keymap['-'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Subtract()
    entry_line = ""
end

keymap['*'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Multiply()
    entry_line = ""
end

keymap['/'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Divide()
    entry_line = ""
end

keymap['W'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Reciprocal()
    entry_line = ""
end

keymap['\n'] = function(stack)
    stack:AddItem(entry_line)
    entry_line=""
end
keymap[' '] = keymap['\n']
keymap[0xd] = keymap['\n']
keymap[0xa] = keymap['\n']

keymap['w'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Swap()
    entry_line = ""
end

keymap['n'] = function(stack)
    if string.find(entry_line, "^# ") then
        return
    elseif entry_line == "" then
        stack:Negate()
    elseif string.find(entry_line, 'e%-') then
        local exp, exp_end = string.find(entry_line, 'e%-')
        entry_line = string.sub(entry_line, 1, exp-1) .. 'e' .. string.sub(entry_line, exp_end+1)
    elseif string.find(entry_line, 'e') then
        local exp = string.find(entry_line, 'e')
        entry_line = string.sub(entry_line, 1, exp) .. '-' .. string.sub(entry_line, exp+1)
    elseif string.find(entry_line, '^%-') then
        entry_line = string.sub(entry_line, 2)
    else
        entry_line = '-' .. entry_line
    end
end

-- Main application code
------------------------
local stack = StackClass()

function catNumber(number)
    if number then
        entry_line = entry_line .. number
    end
end

function draw_entry_line()
    mvaddstr(window_y-1, 0, string.format("%"..tostring(window_x-1).."s",entry_line))
end

while input_char ~= 'Q' do
    stack:redraw()
    draw_entry_line()
    local key = stdscr:getch()
    if key < 256 then
        input_char = string.char(key)
    else
        input_char = key
    end
    if keymap[input_char] then keymap[input_char](stack) end
end

curses.endwin()
