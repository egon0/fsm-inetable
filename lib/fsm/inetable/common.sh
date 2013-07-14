#Netifd version by CyrusFox alias lcb01
SO=$1
SN=$2
interface=$3
[ -n $interface ] 

gwiptbl=/var/p2ptbl/$interface/gwip
DHCPLeaseTime="1h"
NodeId="$(cat /etc/nodeid)"

we_own_our_ip () {
	local CurrentOct3=$(current_oct3)
    [ "$(p2ptbl get $gwiptbl $CurrentOct3 | cut -sf2)" == "$NodeId" ]
}

current_oct3 () {
	local CurrentOct3=$(ifconfig $(get_iface) | egrep -o 'inet addr:[0-9.]*'|cut -f3 -d.)
	echo $CurrentOct3
}

get_iface () {
	local iface=$(uci get network.$interface.ifname)
	local type=$(uci -q get network.$interface.type)
	[ "bridge" = "$type" ] && iface="br-$interface"
	echo $iface
}

cloud_is_online () {
    # look for mac addrs in batman gateway list
	batctl -m $(uci get network.$interface.batman_iface) gwl | tail -n-1 | egrep -q '([0-9a-f]{2}:){5}[0-9a-f]{2}'
}

generate_ip6addr() {
	#If there is no cached ip6 addr yet, we will do so
	if [ ! -s /tmp/$interface-cached-ip6addr ]; then
		local MacAddr=$(ifconfig eth0 | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}' | tr ':' ' ')
		# split the address in two, add the IPv6 ":" notation and add FF:FE in between e.g. 0123:56FF:FE78:9ABC
		# then XOR the 6th byte with 0x02 according to RFC 2373 to create a EUI64 based IPv6 address
		# e.g. -> 0323:56FF:FE78:9ABC (notice the difference to the MAC address at the start)
		# Afterwards add the Network from the cloud configuration file and put a "/64" as netmask at the end
		local ByteSix=$(echo $MacAddr | awk '{print $1}')
		local XORByteSix=$(let "RESULT=0x$ByteSix ^ 0x02" ; printf '%x\n' $RESULT)
		local net_ip6ula=$(uci get network.$interface.net_ip6ula)
		local IP6NetworkAddr=$(echo $net_ip6ula | egrep -o 'f[c-d][:0-9a-f]*' | sed -e 's/:$//')
		local IP6HostAddr="$XORByteSix""$(echo $MacAddr | awk '{print $2":"$3}')""FF:FE""$(echo $MacAddr | awk '{print $4":"$5$6}')"
		local IP6Addr="$IP6NetworkAddr$IP6HostAddr"
		echo $IP6Addr > /tmp/$interface-cached-ip6addr
	fi
	echo $(cat /tmp/$interface-cached-ip6addr)
}

mesh_add_ipv4 () {
	local ip6addr=$(generate_ip6addr)
	local ip6netmask="64"
	local ipaddr=$1
	local netmask=$2
	logger -t fsm "Interface: $interface, Action: Set IPv4 $ipaddr/$netmask"
	call_changescript configure $ip6addr $ip6netmask $ipaddr $netmask
}

mesh_del_ipv4 () {
	#Just calling mesh_add_ipv6 here ;)
	mesh_add_ipv6
}

mesh_add_ipv6 () {
	#Function will always take its IP from the generated functions rather that as function parameters!
	local ip6addr=$(generate_ip6addr)
	local ip6netmask="64"
	logger -t fsm "Interface: $interface, Action: Set IPv6 $ip6addr/$ip6netmask"
	call_changescript configure $ip6addr $ip6netmask
}
call_changescript () { 
	local ip6addr=$2
	local ip6netmask=$3
	local ipaddr=$4
	local netmask=$5
    echo "/lib/netifd/fsm.script" | (
		exec 2>/tmp/fsm.script.log-"$interface"
		set -x
		logger -t debug "$ip6addr $ip6netmask $ipaddr $netmask $INTERFACE"
		while read cmd; do
			if [ -x "$cmd" ]; then
				$cmd $1 $interface $ip6addr $ip6netmask $ipaddr $netmask  666<&-
				exit $?
			fi
		done
	)
}

mesh_set_dhcp() {
	local start_ip=$1
	local end_ip=$2
	local netmask=$3
	# Remove old DHCP settings
	sed \
    -e "/$interface settings/d" \
    -i "/tmp/dnsmasq.conf"
	# Write new settings
	echo "dhcp-range=$(get_iface),$start_ip,$end_ip,$netmask,$DHCPLeaseTime # $interface settings" \
		>> "/tmp/dnsmasq.conf"
}

mesh_set_dhcp_fake() {
	local start_ip=$1
	local end_ip=$2
	local netmask=$3
	local fakeip=$4
	# Remove old DHCP settings
	sed \
    -e "/$interface settings/d" \
    -i "/tmp/dnsmasq.conf"
	# Write new settings
	echo "dhcp-range=$(get_iface),$start_ip,$end_ip,$netmask,$DHCPLeaseTime # $interface settings" \
		>> "/tmp/dnsmasq.conf"
	echo "address=/#/$fakeip # $interface settings" \
		>> "/tmp/dnsmasq.conf"
}


mesh_remove_dhcp() {
	# Remove old DHCP settings
	sed \
    -e "/$interface settings/d" \
    -i "/tmp/dnsmasq.conf"
}
