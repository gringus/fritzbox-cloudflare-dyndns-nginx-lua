local ip6addr = require "/etc/nginx/lua/ip6addr"
local json = require "cjson"
local string = require "string"
local ngx = ngx
local token = ngx.var.token
local args, err = ngx.req.get_uri_args()
local required = {
    hostname   = true,
    ipv4       = false,
    ipv6       = false,
    ipv6offset = false,
}

-- Log
local function error(message)
    ngx.log(ngx.ERR, message)
    ngx.say(message)
end

-- Test for nil/empty string
local function isempty(s)
  return s == nil or s == ''
end

-- Split input string on separator and return table
function split(input, separator)
    local output={}
    if separator == nil then
        separator = "%s"
    end
    for str in string.gmatch(input, "([^"..separator.."]+)") do
        table.insert(output, str)
    end
    return output
end

-- Fetch from Cloudflare
local function cf_api(path, data)
    local api_url = "https://api.cloudflare.com/client/v4/"
    local httpc = require("resty.http").new()
    local res, err = httpc:request_uri(api_url .. path, {
        method = (data == nil) and "GET" or "PUT",
	body = data,
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. token,
        }
    })
    if not res then
        error(string.format("%s: request failed: %s", path, err))
        return nil
    end
    local data = json.decode(res.body)
    if not data.success then
	for i,v in ipairs(data.errors) do
	    error(string.format("%s: %s: %s", path, v.code, v.message))
	end
	return nil
    end

    return data.result
end

--- MAIN ---

-- Sanity checks
if not token then
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    error("No Cloudflare token provided")
    ngx.exit(ngx.HTTP_OK)
end

-- Validate input
for key, mandatory in pairs(required) do
    if mandatory and isempty(args[key]) then
        ngx.status = ngx.HTTP_BAD_REQUEST
        error(string.format("%s: missing", key))
        ngx.exit(ngx.HTTP_OK)
    end
    if type(args[key]) == "table" then
        ngx.status = ngx.HTTP_BAD_REQUEST
        error(string.format("%s: only single value allowed", key))
        ngx.exit(ngx.HTTP_OK)
    end
end

if isempty(args.ipv4) and isempty(args.ipv6) then
    ngx.status = ngx.HTTP_BAD_REQUEST
    error("missing or empty both 'ipv4' and 'ipv6' values")
    ngx.exit(ngx.HTTP_OK)
end

local ipv6 = ip6addr:new(args.ipv6)
if not isempty(args.ipv6) and not ipv6.addr then
    error(string.format("invalid 'ipv6' address: %s", args.ipv6))
end

local ipv6offset = ip6addr:new(args.ipv6offset)
if args.ipv6offset ~= nil and not ipv6offset.addr then
    error(string.format("invalid 'ipv6offset' value: %s", args.ipv6offset))
    ipv6.addr = nil
end

-- Find longest matching zone
local zones = cf_api("/zones")
if zones == nil then
    ngx.status = ngx.HTTP_NOT_FOUND
    error("no zones found")
    ngx.exit(ngx.HTTP_OK)
end

local zoneid
local zone_match
local thostname = split(args.hostname, '.')
for i, zone in ipairs(zones) do
    local name = zone.name
    if table.concat({unpack(thostname, table.getn(thostname)-table.getn(split(name, '.'))+1)}, '.') == name then
        if not zone_match or string.len(name) > string.len(zone_match) then
            zone_match = name
	    zoneid = zone.id
        end
    end
end

if zoneid == nil then
    ngx.status = ngx.HTTP_NOT_FOUND
    error(string.format("no matching zone found for '%s' hostname", args.hostname))
    ngx.exit(ngx.HTTP_OK)
end

-- Find matching records
local records = cf_api(string.format("/zones/%s/dns_records?type=A,AAAA",zoneid))
if records == nil then
    ngx.status = ngx.HTTP_NOT_FOUND
    error("no A/AAAA records found")
    ngx.exit(ngx.HTTP_OK)
end

local updates={}
for i, record in ipairs(records) do
    if record.name == args.hostname then
        table.insert(updates, {
            id      = record.id,
            name    = record.name,
            type    = record.type,
            content = record.content,
            proxied = record.proxied,
            ttl     = record.ttl,
	})
    end
end

if ipv6.addr and ipv6offset.addr then
    ipv6 = ipv6 + ipv6offset
end


local content = {
    A    = args.ipv4,
    AAAA = tostring(ipv6),
}

-- Update matched records if needed
for i, update in ipairs(updates) do
    new_content = content[update.type]
    if not isempty(new_content) and update.content ~= new_content then
        ngx.log(ngx.NOTICE, string.format("%s (%s): %s -> %s", args.hostname, update.type, update.content, new_content))
        local body = json.encode({
            name    = update.name,
            type    = update.type,
            proxied = update.proxied,
            ttl     = update.ttl,
            content = new_content,
        })
        cf_api(string.format("/zones/%s/dns_records/%s", zoneid, update.id), body)
    end
end
