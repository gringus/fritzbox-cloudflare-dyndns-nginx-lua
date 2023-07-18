local bit = require "bit"
local ffi = require "ffi"
local string = require "string"
local ngx = ngx
local C = ffi.C
local bswap = bit.bswap

ffi.cdef[[
    typedef uint32_t socklen_t;
    int inet_pton(int af, const char *src, void *dst);
    const char *inet_ntop(int af, const void *src, char *dst, socklen_t size);
    static const int AF_INET6=10;
]]

-- IPv6 address class
ip6addr = {
    __tostring = function(ip6)
        if ip6.addr == nil then
            return nil
        end

        local output = ffi.new('char[64]')
        C.inet_ntop(C.AF_INET6, ip6.addr, output, 64);

        return ffi.string(output)
    end;

    __add = function(left, right)
        local ip6 = ip6addr:new()
        ip6.addr = ffi.new('uint64_t[2]')
        if left.addr == nil or right.addr == nil then
            return ip6
        end

        local overflow = 0
        for i=1,0,-1 do
            lswap = bswap(left.addr[i])
            rswap = bswap(right.addr[i])
            ip6.addr[i] = bswap(lswap + rswap + overflow)
            overflow = bswap(ip6.addr[i]) < lswap and 1 or 0
        end

        return ip6
    end;
}

-- Create IPv6 address object
function ip6addr:new(ip)
    local ip6 = { addr = nil }
    setmetatable(ip6, ip6addr)
    if not ip then
        return ip6
    end

    local pos = string.find(ip, "/", 0, true)
    if pos then
        ip = string.sub(ip, 1, pos-1)
    end

    local addr = ffi.new('uint64_t[2]')
    local res = C.inet_pton(C.AF_INET6, tostring(ip), addr)
    if res == 1 then
        ip6.addr = addr
    end

    return ip6
end

return ip6addr
