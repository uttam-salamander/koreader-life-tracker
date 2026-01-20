-- Luacheck configuration for KOReader Life Tracker plugin
-- Run: luacheck .

-- Use Lua 5.1 (LuaJIT) standards
std = "luajit"

-- Maximum line length (disable for readability in UI code)
max_line_length = false

-- Allow unused self parameter (common in OOP patterns)
self = false

-- Ignore unused loop variables starting with _
unused_args = false
unused_secondaries = false

-- Global variables read by the plugin (KOReader environment)
read_globals = {
    -- Lua standard library extensions in LuaJIT
    "jit",
    "bit",
    "ffi",

    -- KOReader global utilities (if any are used directly)
    "G_reader_settings",
    "G_defaults",
}

-- Files/patterns to exclude
exclude_files = {
    ".luacheckrc",
    "**/*.rockspec",
}

-- Per-file overrides
files = {
    -- Test files may have different patterns
    ["**/spec/**/*.lua"] = {
        std = "+busted",
    },
}

-- Ignore specific warnings
ignore = {
    "212",  -- Unused argument (common with callbacks)
    "213",  -- Unused loop variable (for _ patterns)
}
