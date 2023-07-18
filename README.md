# fritzbox-cloudflare-dyndns-nginx-lua
Simple [FRITZ!Box](https://en.avm.de/products/fritzbox/) self-hosted proxy for updating [Cloudflare](https://www.cloudflare.com/) DNS records which runs exclusively in [nginx](https://nginx.org/) with [LuaJIT](https://luajit.org/) support.

## Requirements
* [FRITZ!Box](https://en.avm.de/products/fritzbox/) with [DynDNS](https://en.avm.de/service/knowledge-base/dok/FRITZ-Box-7590/30_Setting-up-dynamic-DNS-in-the-FRITZ-Box/) enabled and configured
* [Cloudflare API Token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/) with [Zone Edit](https://developers.cloudflare.com/fundamentals/api/reference/permissions/) permission
* [nginx](https://nginx.org/) with [LuaJIT](https://luajit.org/) support
  * [lua-resty-core](https://github.com/openresty/lua-resty-core) (required by LuaJIT)
  * [lua-resty-lrucache](https://github.com/openresty/lua-resty-lrucache) (required by LuaJIT)
  * [lua-resty-http](https://github.com/ledgetech/lua-resty-http)
  * [lua-cjson](https://github.com/openresty/lua-cjson)

## Setup

### Cloudflare API Token

[Create Cloudflare API Token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/) with Zone Edit permissions (`Zone.DNS.Edit`) for the specific zone. Write down the token.

### nginx

* Clone repository
```
$ git clone git@github.com:gringus/fritzbox-cloudflare-dyndns-nginx-lua.git
```
* Copy `lua`,`dyndns.conf` and `cf-token.conf` to nginx configuration directory
```
# cp -r lua dyndns.conf cf-token.conf /etc/nginx
```
* Update `cf-token.conf`

Edit `cf-token.conf` file by updating the token value obtained in `Cloudflare API Token` step. Make sure file is protected:
```
# chmod 0400 /etc/nginx/cf-token.conf
```

* Create authentication file

Select username and password (`some_username` and `some_password` in the example) for endpoint authentication.
```
# echo -n "some_username:$(openssl passwd -1 'some_password')" > /etc/nginx/dyndns.auth
```
Make sure file is protected and readable at runtime:
```
# chmod 0440 /etc/nginx/dyndns.auth
# chgrp nginx /etc/nginx/dyndns.auth
```

* Add endpoint configuration

Either copy and paste snippet from `dyndns.conf` file or include it in `nginx.conf` eg.
```
include dyndns.conf;
```

### FRITZ!Box

Enable `DynDNS` (`Internet` -> `Permit Access` -> `DynDNS` -> `Use DynDNS`) and configure:
* `Update URL`

URL to self hosted instance including endpoint path (`/dyndns` by default) eg. `https://example.com/dyndns?hostname=<domain>&ipv4=<ipaddr>&ipv6=<ip6lanprefix>&ipv6offset=::1` Supported endpoint parameters:
| Parameter | Example | Description |
| --- | --- | --- |
| hostname | `<domain>` | [FQDN](https://en.wikipedia.org/wiki/Fully_qualified_domain_name) of existing DNS record to update. No new records get created. |
| ipv4 | `<ipaddr>` | The value of `A` record |
| ipv6 | `<ip6addr>` or `<ip6lanprefix>` | The value of `AAAA` record |
| ipv6offset | `::1` | Optional `ipv6` offset (eg. when `<ip6lanprefix>` used as value) in IPv6 address notation. The final value of `AAAA` record will be a sum of `ipv6` and `ipv6pffset` parameters eg. `2001:1234::` and `::ff0` will give `2001:1234::ff0` |

* `Domand name`

[FQDN](https://en.wikipedia.org/wiki/Fully_qualified_domain_name) which FRITZ!Box will use to watch for DNS changes. It seems FRITZ!Box will query `Update URL` only when `Domain name` `A` record value is different than IPv4 address obtained from ISP.

* `Username`

Username used when querying `Update URL`. This should match username in nginx authentication file created in `nginx` step.

* `Password`

Password used when querying `Update URL`. This should match password in nginx authentication file created in `nginx` step.
