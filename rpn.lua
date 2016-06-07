#!/usr/bin/lua
local curses = require 'curses'
local ConfigClass = require "configuration"
require "class"
require "baselog"
LogInit("luarpn", false)

local helpstrings = {
    {txt = "Q - Quit"},
    {txt = "BACKSPACE - Drop"},
    {txt = "~ - show stats"},
    {txt = "^P - purge stack"},
    {txt = "^R - Real/Bin Tgl"},
    {txt = "^G - deg/rad Tgl"},
    {txt = "^B - Toggle Radix"},
    {txt = "w - swap"},
    {txt = "Up/Dn - copy item"},
    {txt = "DEL - delete item"},
    {txt = "n - negate"},
    {txt = "x - EEX"},
    {txt = "y - y^x"},
    {txt = "Y - x^2"},
    {txt = "q - sqrt"},
    {txt = "l - ln"},
    {txt = "L - e^x"},
    {txt = "g - Log"},
    {txt = "G - 10^x"},
    {txt = "m - Modulo"},
    {txt = "M - !"},
    {txt = "W - 1/x"},
    {txt = "s/S - sin/asin"},
    {txt = "o/O - cos/acos"},
    {txt = "t/T - tan/atan"},
    {txt = "u/U - undo/redo"},
    {txt = "p - Pi"},
    {txt = "\" - Add label"},
}

-- Initialize curses and get the initial window size
----------------------------------------------------
curses.initscr()
curses.cbreak()
curses.echo(false)  -- not noecho !
curses.nl(0)    -- not nonl !
curses.start_color()
curses.use_default_colors()

local stdscr = curses.stdscr()  -- it's a userdatum
stdscr:keypad(1)
stdscr:clear()
local window_y, window_x = stdscr:getmaxyx()
local window_x = math.min(window_x, 99)
local mvaddstr = function (...) stdscr:mvaddstr(...) end

local entry_line = ""
local nav_pointer = 1
local base = {HEX = 16, DEC = 10, BIN = 2, OCT = 8}
local help_page = 0
local statistic_page = 0
local curr_stack = 1

local Config = ConfigClass(os.getenv("HOME") .. "/.luarpn")
local settings = Config:Load()
if not settings then
    settings = {}
end
RadixModes = {"DEC", "BIN", "OCT", "HEX"}
local RadixModeIndex = 1
for i, v in pairs(RadixModes) do
    RadixModeIndex = i
    if v == settings.RadixMode then
        break
    end
end
settings.RadixMode = RadixModes[RadixModeIndex]
settings.angle_units = settings.angle_units or "RAD"
settings.stack = settings.stack or {}

local KEY_ESCAPE = 27
local CTRL_B = 2
local CTRL_D = 4
local CTRL_G = 7
local CTRL_H = 8
local CTRL_P = 16
local CTRL_R = 18
local BIN_CODES = {['0']=' 0000', ['1']=' 0001', ['2']=' 0010', ['3']=' 0011', ['4']=' 0100', ['5']=' 0101', ['6']=' 0110', ['7']=' 0111', ['8']=' 1000', ['9']=' 1001', ['a']=' 1010', ['b']=' 1011', ['c']=' 1100', ['d']=' 1101', ['e']=' 1110', ['f']=' 1111'}

-- Item Definitions
-------------------
Real = class()
function Real:__init(value)
    if type(value) == "string" then
        value = tonumber(value)
        self.value = value or 0
    elseif type(value) == "table" then
        for k, v in pairs(value) do
            self[k] = v
        end
    else
        self.value = value or 0
    end
    self.Type = "Real"
end
function Real:__tostring()
    if self.label == "" then
        return tostring(self.value)
    else
        return self.label .. ": " .. tostring(self.value)
    end
end
function Real:GetNumber()
    return tostring(self.value)
end
function Real:new(item) return Real(item or self.value) end
Real.label = ""

Bin = class()
function Bin:__init(value)
    if type(value) == "string" and string.find(entry_line, "^# ") then
        value = tonumber(string.sub(entry_line, 3), base[settings.RadixMode])
        self.value = value or 0
    elseif type(value) == "table" then
        for k, v in pairs(value) do
            self[k] = v
        end
    else
        self.value = value or 0
    end
    self.Type = "Bin"
end
function Bin:__tostring()
    local label = ""
    if self.label ~= "" then
        label = self.label .. ": "
    end
    local formattedNumber = self:GetNumber()
    if settings.RadixMode == "HEX" then
        return string.format("%s%sh", label, self:GetNumber())
    elseif settings.RadixMode == "BIN" then
        local string_num = ""
        local num = string.format("%x", math.floor(self.value))
        for i=1,#num do
            string_num = string_num .. BIN_CODES[string.sub(num, i, i)]
        end
        return string.format("#%sb", string_num)
    elseif settings.RadixMode == "DEC" then
        return string.format("%s%sd", label, self:GetNumber())
    elseif settings.RadixMode == "OCT" then
        return string.format("%s%so", label, self:GetNumber())
    end
end
function Bin:GetNumber()
    if settings.RadixMode == "HEX" then
        return string.format("# %x", math.floor(self.value))
    elseif settings.RadixMode == "BIN" then
        local string_num = ""
        local num = string.format("%x", math.floor(self.value))
        for i=1,#num do
            string_num = string_num .. string.sub(BIN_CODES[string.sub(num, i, i)], 2)
        end
        return string.format("# %s", string_num)
    elseif settings.RadixMode == "DEC" then
        return string.format("# %d", math.floor(self.value))
    elseif settings.RadixMode == "OCT" then
        return string.format("# %o", math.floor(self.value))
    end
end
function Bin:new(item) return Bin(item or self.value) end
Bin.label = ""

-- Stack Class definition
-------------------------
StackClass = class()
function StackClass:__init(args)
    self.stack = {}
    self.status = ""
    if args then
        if args.stack then
            for k, v in ipairs(args.stack) do
                if v.Type == "Real" then
                    table.insert(self.stack, Real(v))
                elseif v.Type == "Bin" then
                    table.insert(self.stack, Bin(v))
                end
            end
        end
        self.status = args.status or ""
    end
end

function StackClass:redraw(starting_line)
    local stack_length = #self.stack
    local stack_starting_line = stack_length - (window_y - 2)

    local active_width = window_x - 4 -- 4 comes from the stack_item size, plus the :
    local format = "%3s:%"..tostring(active_width).."s"
    for i=starting_line, window_y - 2 do
        local stack_pointer = i + stack_starting_line
        local stack_item = window_y - 1 - i
        if stack_pointer < 1 then
            --There is no stack, this is a clear line
            mvaddstr(i, 0, string.format(format, stack_item, " "))
        else
            --Add item from the stack
            num_string = tostring(self.stack[stack_pointer])
            if nav_pointer == stack_pointer then
                stdscr:attron(curses.A_REVERSE)
                mvaddstr(i, 0, string.format(format, '*'..tostring(stack_item), num_string))
                stdscr:attroff(curses.A_REVERSE)
            else
                mvaddstr(i, 0, string.format(format, '*'..tostring(stack_item), num_string))
            end
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
        table.insert(self.stack, Real(item))
    end
end

function StackClass:DropItem(item)
    if item and item < #self.stack then
        local last_item = #self.stack - 1
        for i = item, last_item do
            self.stack[i] = self.stack[i+1]
        end
    end
    table.remove(self.stack)
end

function StackClass:DropStack()
    self.stack = {}
end

function StackClass:Addition()
    if #self.stack < 2 then return end
    local a = table.remove(self.stack)
    local b = table.remove(self.stack)
    table.insert(self.stack, b:new{value=a.value + b.value, label = b.label})
end

function StackClass:Subtract()
    if #self.stack < 2 then return end
    local a = table.remove(self.stack)
    local b = table.remove(self.stack)
    table.insert(self.stack, b:new{value=b.value - a.value, label = b.label})
end

function StackClass:Multiply()
    if #self.stack < 2 then return end
    local a = table.remove(self.stack)
    local b = table.remove(self.stack)
    table.insert(self.stack, b:new{value=a.value * b.value, label = b.label})
end

function StackClass:Divide()
    if #self.stack < 2 then return end
    local divisor = table.remove(self.stack)
    local numerator = table.remove(self.stack)
    if divisor.value ~=0 then
        table.insert(self.stack, numerator:new{value=numerator.value/divisor.value, label = numerator.label})
    else
        self.status = "Divide by zero error"
        table.insert(self.stack, numerator)
        table.insert(self.stack, divisor)
    end
end

function StackClass:Power()
    if #self.stack < 2 then return end
    local x = table.remove(self.stack)
    local y = table.remove(self.stack)
    table.insert(self.stack, y:new{value=y.value^x.value, label = y.label})
end

function StackClass:Sqrt()
    if #self.stack < 1 then return end
    local x = table.remove(self.stack)
    if x.value > 0 then
        table.insert(self.stack, x:new{value=math.sqrt(x.value), label = x.label})
    else
        self.status = "Invalid operand"
        table.insert(self.stack, x)
    end
end

function StackClass:Square()
    if #self.stack < 1 then return end
    local x = table.remove(self.stack)
    table.insert(self.stack, x:new{value=x.value^2, label = x.label})
end

function StackClass:NatLog()
    if #self.stack < 1 then return end
    local x = table.remove(self.stack)
    if x.value < 0 then
        self.status = "Invalid operand"
        table.insert(self.stack, x)
    else
        table.insert(self.stack, x:new{value=math.log(x.value), label = x.label})
    end
end

function StackClass:Exp()
    if #self.stack < 1 then return end
    local x = table.remove(self.stack)
    table.insert(self.stack, x:new{value=math.exp(x.value), label = x.label})
end

function StackClass:Log10()
    if #self.stack < 1 then return end
    local x = table.remove(self.stack)
    table.insert(self.stack, x:new{value=math.log10(x.value), label = x.label})
end

function StackClass:Pow10()
    if #self.stack < 1 then return end
    local x = table.remove(self.stack)
    table.insert(self.stack, x:new{value=10^x.value, label = x.label})
end

function StackClass:Mod()
    if #self.stack < 2 then return end
    local x = table.remove(self.stack)
    local y = table.remove(self.stack)
    table.insert(self.stack, x:new{value=math.fmod(y.value, x.value), label = x.label})
end

function StackClass:Factorial()
    if #self.stack < 1 then return end
    local x = table.remove(self.stack)
    real, frac = math.modf(x.value)
    if frac == 0 and real > 0 then
        for i=real-1,2,-1 do
            real = real * i
        end
    else
        table.insert(self.stack, x)
        self.status = "Bad argument type"
        return false
    end
    table.insert(self.stack, x:new{value=real, label = x.label})
    return true
end

function StackClass:Reciprocal()
    if #self.stack < 1 then return end
    local a = table.remove(self.stack)
    table.insert(self.stack, a:new{value=1/a.value, label = a.label})
end

function StackClass:Negate()
    if #self.stack < 1 then return end
    local a = table.remove(self.stack)
    table.insert(self.stack, a:new{value=-a.value, label = a.label})
end

function StackClass:Sin()
    if #self.stack < 1 then return end
    local a = table.remove(self.stack)
    local x = 0
    if settings.angle_units == "RAD" then
        x = math.sin(a.value)
    elseif settings.angle_units == "DEG" then
        x = math.sin(a.value * math.pi / 180)
    end
    table.insert(self.stack, a:new{value=x, label = a.label})
end

function StackClass:ArcSin()
    if #self.stack < 1 then return end
    local a = table.remove(self.stack)
    local x = 0
    if a.value < -1 or a.value > 1 then
        table.insert(self.stack, a)
        return
    end
    if settings.angle_units == "RAD" then
        x = math.asin(a.value)
    elseif settings.angle_units == "DEG" then
        x = math.asin(a.value) * 180 / math.pi
    end
    table.insert(self.stack, a:new{value=x, label = a.label})
end

function StackClass:Cos()
    if #self.stack < 1 then return end
    local a = table.remove(self.stack)
    local x = 0
    if settings.angle_units == "RAD" then
        x = math.cos(a.value)
    elseif settings.angle_units == "DEG" then
        x = math.cos(a.value * math.pi / 180)
    end
    table.insert(self.stack, a:new{value=x, label = a.label})
end

function StackClass:ArcCos()
    if #self.stack < 1 then return end
    local a = table.remove(self.stack)
    local x = 0
    if a.value < -1 or a.value > 1 then
        table.insert(self.stack, a)
        return
    end
    if settings.angle_units == "RAD" then
        x = math.acos(a.value)
    elseif settings.angle_units == "DEG" then
        x = math.acos(a.value) / math.pi * 180
    end
    table.insert(self.stack, a:new{value=x, label = a.label})
end

function StackClass:Tan()
    if #self.stack < 1 then return end
    local a = table.remove(self.stack)
    if settings.angle_units == "RAD" then
        x = math.tan(a.value)
    elseif settings.angle_units == "DEG" then
        x = math.tan(a.value * math.pi / 180)
    end
    table.insert(self.stack, a:new{value=x, label = a.label})
end

function StackClass:ArcTan()
    if #self.stack < 1 then return end
    local a = table.remove(self.stack)
    if settings.angle_units == "RAD" then
        x = math.atan(a.value)
    elseif settings.angle_units == "DEG" then
        x = math.atan(a.value) / math.pi * 180
    end
    table.insert(self.stack, a:new{value=x, label = a.label})
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

function StackClass:ToggleRealBinary()
    if #self.stack > 0 then
        local a = table.remove(self.stack)
        if a.Type == "Bin" then
            table.insert(self.stack, Real{value=a.value, label = a.label})
        else
            table.insert(self.stack, Bin{value=a.value, label = a.label})
        end
    end
end

function StackClass:AddLabel(label)
    if #self.stack > 0 then
        local a = table.remove(self.stack)
        a.label = label
        table.insert(self.stack, a)
    end
end

-- keymaps
----------
local keymap = {}
local affect_stack = {}
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
keymap['a'] = function(stack) if settings.RadixMode == "HEX" then keymap['#'](stack) catNumber('a') end end
keymap['b'] = function(stack) if settings.RadixMode == "HEX" then keymap['#'](stack) catNumber('b') end end
keymap['c'] = function(stack) if settings.RadixMode == "HEX" then keymap['#'](stack) catNumber('c') end end
keymap['d'] = function(stack) if settings.RadixMode == "HEX" then keymap['#'](stack) catNumber('d') end end
keymap['e'] = function(stack) if settings.RadixMode == "HEX" then keymap['#'](stack) catNumber('e') end end
keymap['f'] = function(stack) if settings.RadixMode == "HEX" then keymap['#'](stack) catNumber('f') end end
keymap['A'] = keymap['a']
keymap['B'] = keymap['b']
keymap['C'] = keymap['c']
keymap['D'] = keymap['d']
keymap['E'] = keymap['e']
keymap['F'] = keymap['f']
affect_stack['0'] = false
affect_stack['1'] = false
affect_stack['2'] = false
affect_stack['3'] = false
affect_stack['4'] = false
affect_stack['5'] = false
affect_stack['6'] = false
affect_stack['7'] = false
affect_stack['8'] = false
affect_stack['9'] = false
affect_stack['a'] = false
affect_stack['b'] = false
affect_stack['c'] = false
affect_stack['d'] = false
affect_stack['e'] = false
affect_stack['f'] = false
affect_stack['A'] = false
affect_stack['B'] = false
affect_stack['C'] = false
affect_stack['D'] = false
affect_stack['E'] = false
affect_stack['F'] = false

affect_stack['#'] = false
keymap['#'] = function(stack)
    if entry_line == "" then
        entry_line = "# "
    elseif not string.find(entry_line, "^# ") then
        entry_line = "# " .. entry_line
    end
end

affect_stack['.'] = false
keymap['.'] = function(stack)
    if not string.find(entry_line, '%.') and not string.find(entry_line, "^# ") then
        catNumber('.')
    end
end

affect_stack['x'] = false
keymap['x'] = function (stack)
    if entry_line == "" then
        entry_line = "1e"
    elseif not string.find(entry_line, 'e') and not string.find(entry_line, "^# ") then
        catNumber('e')
    end
end

affect_stack[curses.KEY_BACKSPACE] = true
keymap[curses.KEY_BACKSPACE] = function(stack)
    if entry_line == "" then
        stack:DropItem()
    elseif entry_line == "# " then
        entry_line = ""
    else
        entry_line = string.sub(entry_line, 1, -2)
    end
end
-- some terminals issue a 127 for the backspace key ??
affect_stack[127] = true
keymap[127] = keymap[curses.KEY_BACKSPACE]

affect_stack[curses.KEY_DC] = true
keymap[curses.KEY_DC] = function(stack)
    if nav_pointer ~= #stack.stack + 1 then
        stack:DropItem(nav_pointer)
    end
end

affect_stack[CTRL_P] = true
keymap[CTRL_P] = function(stack)
    stack:DropStack()
end

affect_stack['p'] = true
keymap['p'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:AddItem(math.pi)
    entry_line = ""
end

affect_stack['+'] = true
keymap['+'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Addition()
    entry_line = ""
end

affect_stack['-'] = true
keymap['-'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Subtract()
    entry_line = ""
end

affect_stack['*'] = true
keymap['*'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Multiply()
    entry_line = ""
end

affect_stack['/'] = true
keymap['/'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Divide()
    entry_line = ""
end

affect_stack['y'] = true
keymap['y'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Power()
    entry_line = ""
end

affect_stack['q'] = true
keymap['q'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Sqrt()
    entry_line = ""
end

affect_stack['l'] = true
keymap['l'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:NatLog()
    entry_line = ""
end

affect_stack['L'] = true
keymap['L'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Exp()
    entry_line = ""
end

affect_stack['g'] = true
keymap['g'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Log10()
    entry_line = ""
end

affect_stack['G'] = true
keymap['G'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Pow10()
    entry_line = ""
end

affect_stack['m'] = true
keymap['m'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Mod()
    entry_line = ""
end

affect_stack['M'] = true
keymap['M'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Factorial()
    entry_line = ""
end

affect_stack['!'] = true
keymap['!'] = keymap['M']

affect_stack['Y'] = true
keymap['Y'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Square()
    entry_line = ""
end

affect_stack['W'] = true
keymap['W'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Reciprocal()
    entry_line = ""
end

affect_stack['s'] = true
keymap['s'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Cos()
    entry_line = ""
end

affect_stack['S'] = true
keymap['S'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:ArcCos()
    entry_line = ""
end

affect_stack['o'] = true
keymap['o'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Sin()
    entry_line = ""
end

affect_stack['O'] = true
keymap['O'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:ArcSin()
    entry_line = ""
end

affect_stack['t'] = true
keymap['t'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Tan()
    entry_line = ""
end

affect_stack['T'] = true
keymap['T'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:ArcTan()
    entry_line = ""
end

affect_stack['\n'] = true
keymap['\n'] = function(stack)
    stack:AddItem(entry_line)
    entry_line=""
end

affect_stack[' '] = true
keymap[' '] = keymap['\n']

affect_stack[0xd] = true
keymap[0xd] = keymap['\n']

affect_stack[0xa] = true
keymap[0xa] = keymap['\n']

affect_stack['w'] = true
keymap['w'] = function(stack)
    if entry_line ~= "" then stack:AddItem(entry_line) end
    stack:Swap()
    entry_line = ""
end

affect_stack['n'] = true
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

affect_stack[CTRL_B] = false
keymap[CTRL_B] = function(stack)
    RadixModeIndex = math.mod(RadixModeIndex, #RadixModes) + 1
    settings.RadixMode = RadixModes[RadixModeIndex]
end

affect_stack[CTRL_R] = true
keymap[CTRL_R] = function(stack)
    if entry_line == "" then
        stack:ToggleRealBinary()
    end
end

affect_stack[CTRL_G] = false
keymap[CTRL_G] = function(stack)
    if settings.angle_units == "RAD" then
        settings.angle_units = "DEG"
    elseif settings.angle_units == "DEG" then
        settings.angle_units = "RAD"
    end
end

affect_stack[curses.KEY_UP] = false
keymap[curses.KEY_UP] = function(stack)
    if nav_pointer > 1 then
        nav_pointer = nav_pointer-1
    end
    entry_line = stack.stack[nav_pointer]:GetNumber()
end

affect_stack[curses.KEY_DOWN] = false
keymap[curses.KEY_DOWN] = function(stack)
    if nav_pointer < #stack.stack then
        nav_pointer = nav_pointer+1
        entry_line = stack.stack[nav_pointer]:GetNumber()
    else
        entry_line = ""
        nav_pointer = #stack.stack + 1
    end
end

affect_stack['?'] = false
keymap['?'] = function(stack)
    help_page = help_page + 1
end

affect_stack['~'] = false
keymap['~'] = function(stack)
    statistic_page = statistic_page + 1
end

affect_stack[curses.KEY_RESIZE] = false
keymap[curses.KEY_RESIZE] = function(stack)
    stdscr:clear()
    window_y, window_x = stdscr:getmaxyx()
    window_x = math.min(window_x, 99)
end

affect_stack['"'] = false
keymap['"'] = function(stack)
    if entry_line == "" then
        entry_line = '"'
    end
end

-- Main application code
------------------------
local stack = {}
stack[curr_stack] = StackClass{stack = settings.stack, status = "? for keymap help"}
local stack_start_line = 1

function catNumber(number)
    if number then
        entry_line = entry_line .. number
    end
end

function draw_entry_line()
    mvaddstr(window_y-1, 0, string.format("%"..tostring(window_x-1).."s",entry_line))
end

function draw_info_window(strings, page)
    local max_length = 0
    local max_lines = #strings
    for k,v in ipairs(strings) do
        if #v.txt > max_length then max_length = #v.txt end
    end
    -- figure out how many columns we can have (up to 3)
    local columns = math.min(3, math.floor(window_x / (max_length + 2)))
    -- figure out how many lines we will have
    local lines = math.max(1, math.floor(window_y / 4))
    local lines = math.min(lines, math.ceil(max_lines/columns))
    -- figure out the column spacing
    local spacing = math.floor(window_x / columns)
    -- figure out how many items per page
    local itemspp = columns * lines
    -- figure out how many pages we have
    local pages = math.ceil(max_lines / itemspp)
    page = math.fmod(page, pages + 1)
    if page == 0 then return 1, 0 end
    --figure out the start and end of the help array for this page
    local start_item = (page - 1) * itemspp + 1
    local last_item = math.min(page * itemspp, max_lines)
    if page == pages then
        local lines_left = last_item - start_item + 1
        lines = math.ceil(lines_left/columns)
    end
    for i = start_item, last_item do
        local x, y = math.modf((i-start_item)/lines)
        y = math.floor(y * lines + 1 + 0.5)
        x = x * spacing
        local line_width = window_x - x
        --mvaddstr(y, x, string.format("%-"..line_width.."s", tostring(x)..","..tostring(y)..": "..strings[i].txt))
        mvaddstr(y, x, string.format("%-"..line_width.."s", strings[i].txt))
    end
    stdscr:mvhline(lines+1, 0, curses.ACS_HLINE, window_x)
    stdscr:refresh()
    return lines + 2, page
end

function draw_statistics_window(stack)
    local sum, count, stack_copy, stats = 0, 0, {}, {}

    for k, v in ipairs(stack.stack) do
        sum = sum + v.value
        count = count + 1
        stack_copy[k] = v
    end
    table.insert(stats, {txt = "Count: " .. count})
    if count > 0 then
        table.insert(stats, {txt = "Sum: " .. sum})
        table.insert(stats, {txt = "Mean: " .. sum/count})
        if count > 1 then
            table.sort(stack_copy, function (a, b) return a.value < b.value end)
            local a = stack_copy[math.floor(count/2+0.5)].value
            local b = stack_copy[math.ceil(count/2+0.5)].value
            table.insert(stats, {txt = "Median: " .. (a+b)/2})
        end
    end
    stack_start_line, statistic_page = draw_info_window(stats, statistic_page)
    return stack_start_line, statistic_page
end

function draw_status_line(stack)
    local status_len = window_x - 7
    stdscr:attron(curses.A_STANDOUT)
    mvaddstr(0, 0, string.format("%s %s%"..status_len.."s", settings.angle_units, settings.RadixMode, stack.status))
    stdscr:attroff(curses.A_STANDOUT)
end

function push_stack(stack, stack_pointer)
    local new_stack_pointer = stack_pointer + 1
    if stack[new_stack_pointer] then
        local i = 0
        while stack[new_stack_pointer + i] do
            stack[new_stack_pointer + i] = nil
            i = i + 1
        end
    end
    stack[new_stack_pointer] = StackClass(stack[stack_pointer])
    return new_stack_pointer
end

while string.sub(entry_line, 1, 1) =='"' or input_char ~= 'Q' do -- not a curses reference
    if input_char ~= curses.KEY_UP and input_char ~= curses.KEY_DOWN then
        nav_pointer = #stack[curr_stack].stack + 1
    end
    stack_start_line = 1
    if help_page ~=0 then
        stack_start_line, help_page = draw_info_window(helpstrings, help_page)
    end
    if statistic_page ~=0 and help_page == 0 then
        stack_start_line = draw_statistics_window(stack[curr_stack])
    end
    draw_status_line(stack[curr_stack])
    stack[curr_stack]:redraw(stack_start_line)
    draw_entry_line()
    local key = stdscr:getch()
    if key then
        if key < 127 and key > 31 then
            input_char = string.char(key)
        else
            input_char = key
        end
        stack[curr_stack].status = ""
        if string.sub(entry_line, 1, 1) == '"' then
            if key < 127 and key > 31 then
                entry_line = entry_line .. input_char
            elseif key == 0xd or key == 0xa then
                stack[curr_stack]:AddLabel(string.sub(entry_line, 2))
                entry_line = ""
            elseif key == curses.KEY_BACKSPACE or key == 127 then
                entry_line = string.sub(entry_line, 1, -2)
            end
        elseif input_char == 'u' then
            if stack[curr_stack - 1] then
                curr_stack = curr_stack - 1
            end
        elseif input_char == 'U' then
            if stack[curr_stack + 1] then
                curr_stack = curr_stack + 1
            end
        elseif keymap[input_char] then
            if affect_stack[input_char] then
                curr_stack = push_stack(stack, curr_stack)
            end
            keymap[input_char](stack[curr_stack])
        --else stack:AddItem(tostring(input_char))
        end
    end
end

curses.endwin()
settings.stack = stack[curr_stack].stack
Config:Save(settings)
if #stack[curr_stack].stack > 0 then
    print("Last Result: "..tostring(stack[curr_stack].stack[#stack[curr_stack].stack]))
end
