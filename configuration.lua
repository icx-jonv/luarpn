--- configuration.lua
-- This file contains config file management functions
--
require("class")

local strdump = string.dump
local gsub = string.gsub
local ioopen = io.open
local ConfigFile = class()

local objects = {}
setmetatable(objects, {__index={["subset"]=function(object, proxies)
    for _,o in ipairs(proxies) do
        if object == o then return true end
    end
end}})

--- __init 
-- This is the constructor for the ConfigFile class
-- @param <code>name</code> - optional, it defaults to 'settings.conf'
-- @return none
function ConfigFile:__init(name)
    self.__configName = name or "settings"
    self.__configName = self.__configName .. ".conf"
end

--- Serialize
-- This function serializes a config object
-- prior to writing it out to a .conf file.
-- 
-- @param <code>object</code> 
-- @param <code>seen</code> 
-- @param <code>indent</code> 
-- @return - 
function ConfigFile:Serialize(object, seen, indent)
    --if not seen then seen = {} end
    if not indent then indent = "" end

    local serialize_key = function(key)
        if type(key) == "string" then
            return "[\""..key.."\"]"
        elseif type(key) == "table" then
            return "["..self:Serialize(key):gsub("\n"," ").."]"
        else
            return "["..key.."]"
        end
        return key
    end

    local escape = function(o)
        return o:gsub("\\","\\\\"):gsub("'","\\'"):gsub('"','\\"')
    end

    --Switch Object type:
    if type(object) == "table" then
        local serialize = "{\n"
        for key, value in pairs(object) do
            serialize = serialize .. indent.."\t" .. serialize_key(key) .. " = " ..
            tostring(self:Serialize(value, seen, indent.."\t")) .. ",\n"
        end
        serialize = serialize .. indent .. "}"

        return serialize
    elseif type(object) == "string" then
        return '"' .. escape(object) .. '"'
    elseif type(object) == "function" then
        return "loadstring([[" .. strdump(object) .. "]])"
    elseif objects.subset(object, {"userdata"}) then
        return nil
    end
    return tostring(object)
end

--- LoadString
-- This function loads a table object from a string of data.
-- Used when reading the config files from disk.
-- @param <code>str</code>  - the string to load into a table
-- @return - the table that was loaded, nil on error
function ConfigFile:LoadString(str)
    if str ~= nil then
        local fn = loadstring(str)
        if fn then
            return fn()
        end
    end

    return nil
end


--- Save
-- This function writes out a config object to a file.
-- 
-- @param <code>object</code> 
-- @param <code>fname</code> 
-- @return - the serialized object or nil on error
function ConfigFile:Save(object, fname)
    filename = fname or self.__configName
    local dump = self:Serialize(object)
    local _file = ioopen(filename, "wb")
    if _file then
        _file:write(dump)
        _file:flush()
        _file:close()
        return dump
    end

    return nil
end

--- Load
-- This function reads in a config object from a file.
-- 
-- @return - the table that was loaded, nil on error
function ConfigFile:Load()
    local _file = ioopen(self.__configName, "rb")
    if _file then
        local dump = _file:read("*all")
        local object = self:LoadString("return"..dump)
        if object ~= nil then
            _file:close()
            return object
        end
    end

    return nil
end

--- Modify
-- This function alters a single setting in a file.
-- @param <code>value</code> is the new value to set
-- @return - nil always
function ConfigFile:Modify(value)
    local lobj = self:Load()    -- Get the local settings
    if lobj ~= nil then
        -- find the setting string in the settings
        self:ChangeSetting( lobj, value)
    end
    self:Save(lobj, nil)        -- Re-write the values back to the file
    return nil
end

--- Delete
-- This function removes a single setting from a file.
-- @param <code>value</code> is the new value to kill
-- @return - nil always
function ConfigFile:Delete(value)
    local lobj = self:Load()    -- Get the local settings
    if lobj ~= nil then
        -- find the setting string in the settings
        self:RemoveSetting( lobj, value)
    end
    self:Save(lobj, nil)        -- Re-write the values back to the file
    return nil
end

--- ChangeSetting
-- This function parses through object table recursively until the
-- correct setting is found and changes it.
-- @param <code>lobj</code> is the table or sub-table to examine
-- @param <code>mod_value</code> is a table of what to change it to
-- @return - nothing
function ConfigFile:ChangeSetting(lobj, mod_value)
    for j,k in pairs(mod_value) do
        if type(k) == "table" then
            if not lobj[j] or type(lobj[j]) ~= "table" then lobj[j]={} end
            self:ChangeSetting(lobj[j], k)
        else
            lobj[j] = k 
        end
    end
end

--- RemoveSetting
-- This function parses through object table recursively until the
-- correct setting is found and removes it.
-- @param <code>lobj</code> is the table or sub-table to examine
-- @param <code>del_value</code> is a table of what to change it to
-- @return - nothing
function ConfigFile:RemoveSetting(lobj, del_value)
    if type(del_value) == "table" then
        for k,v in pairs(del_value) do
            if type(v) == "table" then
                self:RemoveSetting(lobj[k], v)
            else
                lobj[v] = nil
            end
        end
    else
        lobj[del_value] = nil
    end

--    for j,k in pairs(del_value) do
--        if type(k) == "table" then
--            if not lobj[j] or type(lobj[j]) ~= "table" then lobj[j]={} end
--            self:RemoveSetting(lobj[j], k)
--        else
--            lobj[j] = nil 
--        end
--    end
end

return ConfigFile
