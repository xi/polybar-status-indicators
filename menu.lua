#!/bin/env lua

-- local cjson = require('cjson')
-- local inspect = require('pl.import_into')().pretty.write
local lgi = require('lgi')
local Gio = lgi.require("Gio")
-- local Gtk = lgi.require("Gtk")
local GLib = lgi.require("GLib")
local strip = require("dbus_proxy").variant.strip

local Bus = setmetatable({}, {
    __call = function(self, conn, name, path)
        self.conn = conn
        self.name = name
        self.path = path

        self.call_sync = function(interface, method, params, params_type,
                                  return_type)
            -- return ("oi")
            return self.conn:call_sync(self.name, self.path, interface, method,
                                       GLib.Variant(params_type, params),
                                       GLib.VariantType(return_type),
                                       Gio.DBusCallFlags.NONE, -1, nil)
        end

        self.get_menu_layout = function(...)
            return self.call_sync('com.canonical.dbusmenu', 'GetLayout', {...},
                                  '(iias)', '(u(ia{sv}av))')
            --
        end

        self.menu_event = function(...)
            self.call_sync('com.canonical.dbusmenu', 'Event', {...}, '(isvu)',
                           '()')
        end

        return self
    end
})

local format = function(menu)
    local csv = ""
    for _, j in pairs(menu) do
        if j["cmd"] ~= nil then
            csv = csv .. (j["label"] .. "," .. j["cmd"]) .. '\n'
        else
            csv = csv .. (j["label"]) .. '\n'
        end
    end
    return csv
end

local jgmenu = function(csv)
    local cmd =
        ("printf '%s' '$foo' | jgmenu --simple --no-spawn --config-file='./scripts/jgmenurc'"):gsub(
            '$foo', csv)
    local f = assert(io.popen(cmd, 'r'))
    local id = assert(f:read('*a'))
    f:close()

    id = string.gsub(id, '^%s+', '')
    id = string.gsub(id, '%s+$', '')
    id = string.gsub(id, '[\n\r]+', ' ')

    return id
end

local show_menu = function(conn, name, path)
    local bus = Bus(conn, name, path)
    local item = strip(bus.get_menu_layout(0, -1, {}))
    local menu = {}

    for i = 1, #item do
        if type(item[i]) == "table" and item[2][2]["children-display"] ==
            "submenu" then
            for _, k in ipairs(item[2][3]) do
                local entry = {}

                if k[2]["children-display"] ~= "submenu" then
                    if k[2].type == "separator" then
                        entry = {label = "^sep()"}
                        --
                    elseif k[2].enabled ~= nil and not k[2].enabled and
                        string.len(k[2].label) > 0 then
                        entry = {label = "^sep(" .. k[2].label .. ")"}
                        --
                    elseif string.len(k[2].label) > 0 then
                        entry = {cmd = tostring(k[1]), label = k[2].label}
                        --
                    end
                else
                    entry = {label = "^tag(" .. k[2].label .. ")"}
                end

                table.insert(menu, entry)
            end
        end
    end

    local csv = format(menu)
    print(csv)

    local id = jgmenu(csv)

    if string.len(id) > 0 then
        print("id: " .. id)
        bus.menu_event(id, 'clicked', GLib.Variant('s', ''), os.time())
    end
    --
end

local conn = Gio.bus_get_sync(Gio.BusType.SESSION)
show_menu(conn, arg[1], arg[2])
