# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Install Docker
curl -fsSL get.docker.com -o get-docker.sh
sudo sh get-docker.sh
rm get-docker.sh

# Allow IP forwarding, so we can access docker containers from outside
# needs to be allowed at the kernel level
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-ip-forward.conf
sudo sysctl -p
# and via iptables
sudo iptables -P FORWARD ACCEPT
echo 'iptables-persistent iptables-persistent/autosave_v4 boolean true' | sudo debconf-set-selections
echo 'iptables-persistent iptables-persistent/autosave_v6 boolean true' | sudo debconf-set-selections
sudo apt-get -y install iptables-persistent

# Enable cgroups (not needed by judgehost, but simpler to put more stuff in init)
sudo sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1/' /etc/default/grub
sudo update-grub
sudo reboot
