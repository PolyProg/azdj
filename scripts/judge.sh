# Creates a DOMjudge judge daemon Docker container,
# connecting to the given server
# Requires cgroups

# Arguments
# $NAME: the judge name
# $TIMEZONE: the server timezone
# $SERVER: the protocol + host/IP of the DOMjudge server
# $SERVER_PASSWORD: the password of the 'judgehost' user on the server
# $LANGUAGES: the languages to install in the judge

# HACK wait until Docker has finished initializing fully, otherwise the client can't find the socket
sleep 20

# Delete the container first, just in case
sudo docker rm -f judge >> /dev/null 2>&1 || true
# Note that --hostname is what DOMjudge will report as the judge name
sudo docker run --name=judge \
                --hostname="$NAME" \
                --detach \
                --restart=always \
                --privileged \
                --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro \
                -e "CONTAINER_TIMEZONE=$TIMEZONE" \
                -e "DOMSERVER_BASEURL=$SERVER/" \
                -e 'JUDGEDAEMON_USERNAME=judgehost' \
                -e "JUDGEDAEMON_PASSWORD=$SERVER_PASSWORD" \
                -e 'DAEMON_ID=0' \
                domjudge/judgehost:5.3.3


# HACK wait until the judge has initialized (how do we do that properly?)
sleep 20

# Write down the command we'll execute within Docker.
# Note that the parameters are not expanded (thanks to the quoted EOF), but given later
cat > command.sh << 'EOF'
# Mount stuff so that packages can be installed properly
mount -t proc proc '/chroot/domjudge/proc'
mount -t sysfs sysfs '/chroot/domjudge/sys'
mount --bind /dev/pts '/chroot/domjudge/dev/pts'

# Execute a command in chroot
# $1: The command
chroot_exec() {
  chroot '/chroot/domjudge' /bin/sh -c "$1"
}

# Better Apt config: only required packages, and retry on failure
# note: we're within an EOF-delimited script here, use something else
cat > '/etc/apt/apt.conf.d/99custom' << 'XXX'
APT::Install-Suggests "false";
APT::Install-Recommends "false";
Acquire::Retries "5";
XXX
# And in the chroot as well
chroot_exec "echo '$(cat /etc/apt/apt.conf.d/99custom)' > '/etc/apt/apt.conf.d/99custom'"

# Always install the 'testing' repo, doesn't hurt if not needed
echo 'deb http://deb.debian.org/debian testing main' >> '/etc/apt/sources.list'
apt-get update
chroot_exec "echo 'deb http://deb.debian.org/debian testing main' >> '/etc/apt/sources.list'"
chroot_exec "apt-get update"

for lang in $LANGUAGES; do
  outside='false'
  install=''
  alias=''

  case $lang in
    c11)
      install='-t testing gcc-8'
      alias='/usr/bin/gcc-8 /usr/bin/gcc'
      ;;
    cpp17)
      install='-t testing g++-8'
      alias='/usr/bin/g++-8 /usr/bin/g++'
      ;;
    java11)
      install='-t testing openjdk-11-jdk'
      ;;
    python27)
      install='python2.7'
      alias='/usr/bin/python2.7 /usr/bin/python2'
      outside='true'
      ;;
    python37)
      install='python3.7'
      alias='/usr/bin/python3.7 /usr/bin/python3'
      outside='true'
      ;;
  esac

  if [ ! -z "$install" ]; then
    chroot_exec "apt-get install -y $install"

    if [ "$outside" = 'true' ]; then
      apt-get install -y $install
    fi
  fi
  if [ ! -z "$alias" ]; then
    chroot_exec "ln -fs $alias"

    if [ "$outside" = 'true' ]; then
      ln -fs $alias
    fi
  fi
done

# Unmount the stuff we did at the beginning
umount '/chroot/domjudge/proc'
umount '/chroot/domjudge/sys'
umount '/chroot/domjudge/dev/pts'
EOF

# Execute the command
sudo docker exec judge bash -c "LANGUAGES='$LANGUAGES'; $(cat command.sh)"

# Remove the command file, useless now
rm command.sh
