# Creates a DOMjudge judge daemon Docker container,
# connecting to the given server
# Requires cgroups

# Arguments
# $TIMEZONE: the server timezone
# $SERVER: the host/IP of the DOMjudge server
# $SERVER_PASSWORD: the password of the 'judgehost' user on the server

# HACK wait until Docker has finished initializing fully, otherwise the client can't find the socket
sleep 20

# Delete the container first, just in case
sudo docker rm -f judge >> /dev/null 2>&1 || true
sudo docker run --name=judge \
                --detach \
                --restart=always \
                --privileged \
                --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro \
                -e "CONTAINER_TIMEZONE=$TIMEZONE" \
                -e "DOMSERVER_BASEURL=http://$SERVER/" \
                -e 'JUDGEDAEMON_USERNAME=judgehost' \
                -e "JUDGEDAEMON_PASSWORD=$SERVER_PASSWORD" \
                -e 'DAEMON_ID=0' \
                domjudge/judgehost:5.3.2
