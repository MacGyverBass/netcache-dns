# Network Cache Docker Container

```txt
_____   __    ______________            ______
___/ | / /______/ /__/ ____/_____ _________/ /______
__/  |/ /_/ _ \/ __/  /    _/ __ `// ___/_/ __ \/ _ \
_/ /|  / /  __/ /_ / /___  / /_/ // /__ _  / / /  __/
/_/ |_/  \___/\__/ \____/  \__,_/ \___/ /_/ /_/\___/

```

## Introduction

This docker container provides DNS entries for caching services to be used in conjunction with a HTTP caching server.

This project is based off the work of SteamCache-DNS.  For more information, please check out their [GitHub steamcache/steamcache-dns Page](https://github.com/steamcache/steamcache-dns).

This project aims to be compatible with the same environmental variables, thus being a potential drop-in replacement, but adding additional options.

The DNS is generated automatically at startup of the container, the list of supported services is available here: [github.com/uklans/cache-domains](https://github.com/uklans/cache-domains)

Addtional custom services can be added via the options noted below.

The primary use case is gaming events, such as LAN parties, which need to be able to cope with hundreds or thousands of computers receiving an unannounced patch - without spending a fortune on internet connectivity. Other uses include smaller networks, such as Internet Cafes and home networks, where the new games are regularly installed on multiple computers; or multiple independent operating systems on the same computer.

## Quick Explanation

For a LAN cache to function on your network you need two services.

* A depot cache service
* A special DNS service

The depot cache service transparently proxies your requests for content to Steam/Origin/etc, or serves the content to you if it already has it.

The special DNS service handles DNS queries normally (recursively), except when the query is for a cached service and in that case it responds that the depot cache service should be used.

## Usage

If all of the services you wish to run point to a single IP address, you should make sure you set USE_GENERIC_CACHE=true and set LANCACHE_IP to the IP address of the caching server.
In this case it is highly recommended that you use some form of load balancer or reverse proxy, as running a single caching server for multiple services will result in cache clashes and will result in incorrect or corrupt data.

Run the netcache-dns container using the following to allow UDP port 53 (DNS) through the host machine:

```sh
docker run --name netcache-dns -p 10.0.0.2:53:53/udp -e USE_GENERIC_CACHE=true -e LANCACHE_IP=10.0.0.3 bassware/netcache-dns:latest
```

The example above is binds to UDP port 53 on IP 10.0.0.2 on the host machine and specifies the single caching server is hosted on 10.0.0.3 on the host machine.

You can specify a different IP for each service hosted within the cache; for a full list of supported services have a look at the [GitHub uklans/cache-domains Page](https://github.com/uklans/cache-domains). Set the IP for a service using ${SERVICE}CACHE_IP environment:

```conf
LANCACHE_IP=10.0.0.10  (requires USE_GENERIC_CACHE to be set to true)

BLIZZARDCACHE_IP=10.0.0.11
FRONTIERCACHE_IP=10.0.0.12
ORIGINCACHE_IP=10.0.0.13
RIOTCACHE_IP=10.0.0.14
STEAMCACHE_IP=10.0.0.15
UPLAYCACHE_IP=10.0.0.16
```

You can also disable any of the cache dns resolvers by setting the environment variable of DISABLE_${SERVICE}=true

```conf
DISABLE_BLIZZARD=true
DISABLE_RIOT=true
DISABLE_UPLAY=true
```

### Options Added for Custom Services

Custom services may be added using the variable CUSTOMCACHE and hosts may be specified using just the service name as a variable.

```sh
docker run --name netcache-dns -p 10.0.0.2:53:53/udp -e USE_GENERIC_CACHE=true -e LANCACHE_IP=10.0.0.3 -e CUSTOMCACHE=MyCDN -e MYCDNCACHE=cdn.example.com bassware/netcache-dns:latest
```

This may also be used for ${SERVICE}CACHE_IP (mentioned previously) to specify different IP addresses for each service hosted.

```conf
CUSTOMCACHE=MyCDN
MYCDNCACHE=cdn.example.com
MYCDNCACHE_IP=10.0.0.21
```

Multiple custom services may also be added by adding unique prefixes the CUSTOMCACHE.

```conf
CUSTOMCACHE=MyCDN MyGameCDN MyBackupCDN
MYCDNCACHE=cdn.example.com
MYCDNCACHE_IP=10.0.0.21
MYGAMECDNCACHE=gamecdn.example.com
MYGAMECDNCACHE_IP=10.0.0.22
MYBACKUPCDNCACHE=backupcdn.example.com
MYBACKUPCDNCACHE_IP=10.0.0.23
```

Custom service lists may also be specified using a local file.

```sh
docker run --name netcache-dns -p 10.0.0.2:53:53/udp -e USE_GENERIC_CACHE=true -e LANCACHE_IP=10.0.0.3 -e CUSTOMCACHE=MyCDN -e MYCDNCACHE=`cat MyCDN.txt` bassware/netcache-dns:latest
```

Example MyCDN.txt file:

```txt
cdn0.example.com
cdn1.example.com
cdn2.example.com
cdn3.example.com
```

### Option for Running Only Specific Services

The ONLYCACHE variable was added to quickly specify specific services to use from the uklans/cache-domains list.

```conf
ONLYCACHE=hirez steam windowsupdates
```

The above example would cache the hirez, steam, and windowsupdates services from the uklans/cache-domains list.

This option was primarily added for debugging purposes, so one or more space-delimited services could be tested at a time without needing to heavily rewrite the docker command/script.  However this option may be useful to others testing their setups or for smaller setups.

Note that specifying a service in ONLYCACHE will thus ignore the matching DISABLE_${Service}=true entry.

For example, both DISABLE_ORIGIN=true and ONLYCACHE=origin are specified, but it will still setup caching for Origin:

```conf
DISABLE_ORIGIN=true
ONLYCACHE=origin
```

## Custom Upstream DNS

To use a custom upstream DNS server (or servers), use the `UPSTREAM_DNS` variable:

```sh
docker run --name netcache-dns -p 10.0.0.2:53:53/udp -e STEAMCACHE_IP=10.0.0.3 -e UPSTREAM_DNS=8.8.8.8 bassware/netcache-dns:latest
```

This will add a forwarder for all queries not served by netcache-dns to be sent to the upstream DNS server, in this case Google's DNS.  If
you have a DNS server on 1.2.3.4, the command argument would be `-e UPSTREAM_DNS=1.2.3.4`.

### Additional Upstream DNS Servers

Additional upstream DNS servers can now be added using the `UPSTREAM_DNS` variable:

```sh
docker run --name netcache-dns -p 10.0.0.2:53:53/udp -e STEAMCACHE_IP=10.0.0.3 -e UPSTREAM_DNS=8.8.8.8,8.8.4.4 bassware/netcache-dns:latest
```

In this example, it will add two available forwarders to the Upstream DNS, if the query is not matched by the netcache-dns.

Upstream DNS lists may also be specified using a local file.

```sh
docker run --name netcache-dns -p 10.0.0.2:53:53/udp -e STEAMCACHE_IP=10.0.0.3 -e UPSTREAM_DNS=`cat MyPreferredDNS.txt` bassware/netcache-dns:latest
```

Example MyPreferredDNS.txt file:

```txt
1.1.1.1
1.0.0.1
8.8.8.8
8.8.4.4
208.67.222.222
208.67.220.220
```

## Running on Startup

Follow the instructions in the Docker documentation to run the container at startup.
[Documentation](https://docs.docker.com/config/containers/start-containers-automatically/)

## Further information

More information can be found at the [SteamCache Homepage](http://steamcache.net) and the [GitHub steamcache/steamcache-dns Page](https://github.com/steamcache/steamcache-dns)

## License

[The MIT License (MIT)](LICENSE)
