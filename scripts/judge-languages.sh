#!/bin/sh
# Adds languages to a DOMjudge judgehost, in a Docker container (assumed to exist and be named 'judge')

# Parameters:
# $LANGUAGES: The space-separated list of languages.

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

# Fix the chroot's resolv.conf by using the host's, otherwise it won't be able to download anything
chroot_exec "echo '$(cat /etc/resolv.conf)' > /etc/resolv.conf"

# Always install the 'testing' repo, doesn't hurt if not needed
chroot_exec "echo 'deb http://deb.debian.org/debian testing main' >> /etc/apt/sources.list && \
             echo apt-get update"

for lang in $LANGUAGES; do
  install=''
  alias=''

  case $lang in
    c11)
      install='-t testing gcc-7'
      alias='/usr/bin/gcc-7 /usr/bin/gcc'
      ;;
    cpp17)
      install='-t testing g++-7'
      alias='/usr/bin/g++-7 /usr/bin/g++'
      ;;
    java8)
      install='openjdk-8-jdk'
      ;;
    python27)
      install='python2.7'
      alias='/usr/bin/python2.7 /usr/bin/python2'
      ;;
    python35)
      install='python3.5'
      alias='/usr/bin/python3.5 /usr/bin/python3'
      ;;
  esac

  if [ ! -z "$install" ]; then
    chroot_exec "apt-get install $install"
  fi
  if [ ! -z "$alias" ]; then
    chroot_exec "ln -s $alias"
  fi
done

# Unmount the stuff we did at the beginning
umount '/chroot/domjudge/proc'
umount '/chroot/domjudge/sys'
umount '/chroot/domjudge/dev/pts'
EOF

# Execute the command
sudo docker exec server bash -c "LANGUAGES='$LANGUAGES'; $(cat command.sh)"

# Remove the command file, useless now
rm command.sh
