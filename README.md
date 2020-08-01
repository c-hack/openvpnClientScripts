# openvpnClientScripts
Some scripts to enhance the openvpn client. Especially when using tap interaces.

## Using
Usage: 
`startVpn.sh [options] <serverName>`

### Options
```
-h --help           print this help
-n --not            invert next option. Only works for options below
-d --default-route  add default route through vpn
-t --tmux           use tmux
```

### Server Name
The name of a server configuration

### Config file
You can configure some of the options in the file startVpn.conf
The following options are supported: 
 * default-route
 * tmux

To overwrite these options using the command line option use the `--not` option.

### Why do I need sudo?
Many network operations need root privileges under most systems.
Examples are creating a tap device or manually triggering dhclient.


## Configuring a server
To configure a server create a folder in servers. The folder name will be used as the name for selecting the server.
In this folder there needs to be the follwoing files:
  * `client.ovpn` The openvpn client configuration
  * `startup.sh` A script run when the connection is established. Use this to trigger dhclient and set routes.
  * `shutdown.sh` A script run after the vpn goes down. Use this to clean up the routes.

### Working directory
The working directory is changed to the folder of the server before executing openvpn, 
so any relative paths inside the config should be relative to it.

### Startup and Shutdown scripts.
The scripts are run with root privileges and are given `true` or `false` as the first and only parameter stating whether it should create a default route.

#### Exmamples
##### startup.sh

```
#!/usr/bin/env bash
dhclient <tap device from config>
ip route add <some addintional network> via <some gateway> dev <tap device from config>

if [ "$1" == "true" ] ;then
  vpn_ip="`host <vpn server address> | grep "has address" | sed 's/.* has address//g'`"
  route_to_vpn="`ip r get $vpn_ip | grep "via" | sed 's/uid.*//g'`"
  ip route add $route_to_vpn
  ip route add default via <some gateway> dev <tap device from config> metric 100
fi

resolvconf -u
```

##### shutdown.sh

```
#Any routes containing the tap device are deleted when the device goes down.

if [ "$1" == "true" ] ;then
  vpn_ip="`host <vpn server address> | grep "has address" | sed 's/.* has address//g'`"
  route_to_vpn="`ip r get $vpn_ip | grep "via" | sed 's/uid.*//g'`"
  ip route del $route_to_vpn
fi

resolvconf -u
```

