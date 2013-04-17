#Netifd version by CyrusFox alias lcb01
SO=$1
SN=$2
interface=$3
[ -n $interface ] 

. /lib/netifd/netifd-proto.sh

gwiptbl=/var/p2ptbl/$interface/gwip
DHCPLeaseTime=$((12 * 3600))
NodeId="$(cat /etc/nodeid)"

we_own_our_ip () {
	local CurrentOct3=$(current_oct3)
    [ "$(p2ptbl get $gwiptbl $CurrentOct3 | cut -sf2)" == "$NodeId" ]
}

current_oct3 () {
	local iface=$(uci get network.$interface.ifname)
	local type=$(uci get network.$interface.type)
	[ "bridge" = "$type" ] && iface="br-$interface"
	local CurrentOct3=$(ifconfig $iface | egrep -o 'inet addr:[0-9.]*'|cut -f3 -d.)
	echo $CurrentOct3
}

get_iface () {
	local iface=$(uci get network.$interface.ifname)
	local type=$(uci get network.$interface.type)
	[ "bridge" = "$type" ] && iface="br-$interface"
	echo $iface
}

cloud_is_online () {
    # look for mac addrs in batman gateway list
	batctl -m $(uci get network.$interface.batman_iface) gwl | tail -n-1 | egrep -q '([0-9a-f]{2}:){5}[0-9a-f]{2}'
}

mesh_add_defaults() {
	proto_init_update "*" 1
	proto_set_keep 1
	#IP6 ULA
	# Set IP6 stateless ULA now according to RFC using a modified EUI-64 ;) 
	#MacAddr without ":"
	MacAddr=$(ifconfig eth0 | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}' | tr ':' ' ')
	# split the address in two, add the IPv6 ":" notation and add FF:FE in between e.g. 0123:56FF:FE78:9ABC
	# then XOR the 6th byte with 0x02 according to RFC to create a modified EUI64 based IPv6 address
	# e.g. -> 0323:56FF:FE78:9ABC (notice the difference to the MAC address at the start)
	# Afterwards add the Network from the cloud configuration file and put a "/64" as netmask at the end
	ByteSix=$(echo $MacAddr | awk '{print $1}')
	XORByteSix=$(let "RESULT=0x$ByteSix ^ 0x02" ; printf '%x\n' $RESULT)
	net_ip6ula=$(uci get network.$interface.net_ip6ula)
	IP6NetworkAddr=$(echo $net_ip6ula | egrep -o 'f[c-d][:0-9a-f]*' | sed -e 's/:$//')
	IP6HostAddr="$XORByteSix""$(echo $MacAddr | awk '{print $2":"$3}')""FF:FE""$(echo $MacAddr | awk '{print $4":"$5$6}')"
	IP6Addr="$IP6NetworkAddr$IP6HostAddr"
	IP6Netmask="64"
	proto_add_ipv6_address $IP6Addr $Netmask
	logger -t fsm "Interface: $interface, Action: Set IPv6-ULA $IP6Addr/$IP6Netmask"
	proto_send_update "$interface"
}
mesh_reset_interface() {
	logger -t fsm "Interface: $interface, Action: Reset"
	proto_init_update "*" 0
	proto_set_keep 0
	proto_send_update "$interface"
	sleep 2
	mesh_add_defaults
}

## add/remove IPv4/IPv6 address from mesh iface
# manual update to avoid full ifdown+ifup, but update uci state for
# other users (e.g. dnsmasq)

mesh_add_ipv4 () {
	logger -t fsm "Interface: $interface, Action: Set IPv4 $1/$2"
	proto_init_update "*" 1
	proto_set_keep 1
	proto_add_ipv4_address $1 $2 
	proto_send_update "$interface"
}

#Todo: currently uses reset instead
mesh_del_ipv4 () {
	logger -t fsm "Interface: $interface, Action: Remove IPv4"
	mesh_reset_interface
}

mesh_add_ipv6 () {
	logger -t fsm "Interface: $interface, Action: Add IPv6 $1/$2"
	proto_init_update "*" 1
	proto_set_keep 1
	proto_add_ipv6_address $1 $2 
	proto_send_update "$interface"
}

#Todo: currently uses reset instead
mesh_del_ipv6() {
	logger -t fsm "Interface: $interface, Action: Remove IPv6"
	mesh_reset_interface
}
