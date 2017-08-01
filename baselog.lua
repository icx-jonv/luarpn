-- Depends on the 'luasyslog' luarock
require 'logging.syslog'
local syslog = logging.syslog
local sl = nil

EMERG="logEmergency"
ALERT="logAlert"
CRITICAL="logCritical"
ERROR="logError"
NOTICE="logNotice"
INFO="logInfo"
DEBUG="logDebug"
WARN="logWarning"

--- This table consist of the logging levels that are supported
-- as well as flags to enable/disable them
-- The strval is the string literal value that the syslog library
-- expects when using it.
-- The EMERG vs LOG_EMERG is just a shortcut for less typing
local loggingLevels = {
    logEmergency = {
        enabled=true,
        strval="FATAL",
    },
    logAlert = {
        enabled=true,
        strval="FATAL",
    },
    logCritical = {
        enabled=true,
        strval="FATAL",
    },
    logError = {
        enabled=true,
        strval="ERROR",
    },
    logWarning = {
        enabled=true,
        strval="WARN",
    },
    logNotice = {
        enabled=false,
        strval="INFO",
    },
    logInfo = {
        enabled=true,
        strval="INFO",
    },
    logDebug = {
        enabled=true,
        strval="DEBUG",
    }
}

local _Logging_Parameters_ = { }

--- This initializes the logging library
-- This class is a logging object that speaks the syslog protocol
-- on the backend.  All log messages are sent to the local syslog 
-- daemon.
-- @param name -- the name of the application logging
-- @param console -- a flag to specify if console logging is enabled
function LogInit(name, console)
    _Logging_Parameters_.name = name or "baselog"
    _Logging_Parameters_.console = console or false
    _Logging_Parameters_.levels = loggingLevels

    if _Logging_Parameters_.console == true then
        -- Console needs to be fixed, currently it means nothing
        sl = syslog(_Logging_Parameters_.name)
    else
        sl = syslog(_Logging_Parameters_.name)
    end
end

--- This function allows the user to dynamically set
-- the levels that he wants to be logged in his application
-- The parameter must be in the format of a key/value table like so:
-- {
--    DEBUG = true,
--    WARN = false,
--    INFO = true,
--    etc...
-- }
-- You would just add the levels that you want to enable/disable
-- <strong>Remember, by default all levels are enabled.</strong>
--
-- @param log_levels -- a table specifying the levels to be enabled/disabled
function LogSetLevel(log_levels)
    for k,v in pairs(log_levels) do
        _Logging_Parameters_.levels[k].enabled = v
    end
end

--- This function performs the actual logging of the message
-- specified.  It also make sure that it only logs the messages
-- that are on the levels that are enabled
--
-- @param level -- the level DEBUG, WARN, etc...
-- @param msg -- The text string to log
function Log(level, msg)
    if not sl then return end
    if _Logging_Parameters_.levels[level].enabled ~= false then
        sl:log(_Logging_Parameters_.levels[level].strval, msg)
    end
end

--- This function simply closes the connection with the syslog
-- server.  If this is not called the syslog server closes the connection
-- once the application exists.  But it's good practice to call this on any exit
-- cases you may have in your application.
function LogClose()
end

