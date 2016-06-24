#!/bin/bash

set -e

echo "
################################################################################
#                                                                              #
# Warning: This script is for Arch-Linux only, use carefully, it overwrites    #
# several config-files without any queries!                                    #
#                                                                              #
# If you're unsure what you're doing exit now by pressing ctrl+c!              #
#                                                                              #
################################################################################
"
sleep 5

#check enviroment
if [ ! -f '/etc/arch-release' ]; then
	echo 'this linux seems not to be an ArchLinux, so we exit now.'
	exit 1
fi

if [ "$(whoami)" == 'root' ]; then
	echo 'Do not run as root. Use an account with sudo-rights.'
	exit 1
fi

#settings
install_folder='basic-config'
packagelist='iproute2 base-devel net-tools bird bird6 dhcp radvd bind openvpn haveged bridge-utils tinc fastd batctl batman-adv'

echo "updating system..."

yaourt -Syu --noconfirm >/dev/null 2>&1
yaourt -Syua --noconfirm >/dev/null 2>&1

echo "install packages..."
yaourt -S $packagelist --needed --noconfirm >/dev/null 2>&1
unset packagelist

echo "preparing system..."
sudo useradd --system --no-create-home --shell /bin/false fastd >/dev/null 2>&1 | true
sudo useradd --system --no-create-home --shell /bin/false openvpn >/dev/null 2>&1 | true

echo "generating config-files..."
[ -z "$install_folder" ] && exit 1

sudo mkdir -p /etc/dhcp.d-freifunk/

declare -a fns
fns+=('/etc/iptables/iptables.rules')
fns+=('/etc/openvpn/tun-01.conf')
fns+=('/etc/openvpn/tun-01_pass.txt')
fns+=('/etc/openvpn/tun-01_up.sh')
fns+=('/etc/sysctl.d/99-sysctl.conf')
fns+=('/etc/dhcpd.conf')
fns+=('/etc/named.conf')
fns+=('/etc/radvd.conf')
fns+=('/etc/bird.conf')
fns+=('/usr/local/bin/tun-01_check.sh')

#now copy default content to config files, if they doesn't exit, but the folders
#touch them before filling them, else exit
for fn in "${fns[@]}"; do
	[ "$fn" == '' ] && exit 1
	if [ ! -f "${install_folder}${fn}" ]; then
		echo "file $fn which is marked for installation could not be found"
		exit 1
	fi
	if [ ! -f "$fn" ] || [ "$(head -n 1 basic-config/etc/bird.conf)" == "#File is generated by gluon-server-scripts" ]; then
		sudo cp "${install_folder}${fn}" "${fn}"
		if [ "$?" -ne "0" ]; then
			echo "file $fn could not be copied"
			exit 1
		fi
	else
		echo "file $fn does exist, we do NOT overwrite, skipping file!"
	fi
done

unset fn fns

#fixing rp-filter
sudo touch /etc/sysctl.d/50-default.conf

#fixing rights
sudo chmod +x /etc/openvpn/tun-01_up.sh
sudo chmod +x /usr/local/bin/tun-01_check.sh

#enabling services
sudo systemctl enable bird radvd named iptables openvpn@tun-01 # bird6

#set routerid
sudo sed -i -e "s/ROUTERID/$(/sbin/ifconfig eth0 | grep 'inet ' | cut -d: -f2 | awk '{ print $2}')/g" /etc/bird.conf

#starting services
sudo systemctl start bird radvd named iptables #bird6

echo "please start openvpn@tun-01 when config is completed."

if [ ! -f '/etc/sudoers.installed_by_gluon-server-scripts' ]; then
	echo "installing fastd-sudo rights..."
	echo "
	fastd ALL=(ALL)NOPASSWD:/usr/bin/batctl
	fastd ALL=(ALL)NOPASSWD:/usr/bin/brctl
	fastd ALL=(ALL)NOPASSWD:/usr/bin/ifconfig
	fastd ALL=(ALL)NOPASSWD:/usr/bin/ip" | sudo tee -a /etc/sudoers

	sudo touch /etc/sudoers.installed_by_gluon-server-scripts
fi
