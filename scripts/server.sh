# Creates a MySQL container named 'db' (whose only database is also named 'db),
# and a Docker container named 'server' with a DOMserver.
# The DOMserver is mapped to port 80 of the host.
# Requires cgroups (TODO why?)

# Arguments
# $TIMEZONE: the server timezone
# $DISABLE_ERROR_PRIORITY: whether to disable priority of judging errors (so that all errors have the same priority)
# $DB_PASSWORD: the root password of the DB
# $ADMIN_PASSWORD: the password for the DOMjudge admin user
# $JUDGE_PASSWORD: the password for judgehosts

# HACK wait until Docker has finished initializing fully, otherwise the client can't find the socket
sleep 20

# Create a subnet so that the DOMserver can talk to the DB
# (and delete it if it already exists, just in case)
sudo docker network rm net >> /dev/null 2>&1 || true
sudo docker network create net

# Create a MySQL DB container
# (again, delete it first just in case)
sudo docker rm -f db >> /dev/null 2>&1 || true
sudo docker run --name=db \
                --network=net \
                --detach \
                --restart=always \
                -e "MYSQL_ROOT_PASSWORD=$DB_PASSWORD" \
                -e 'MYSQL_ROOT_HOST=%' \
                -e 'MYSQL_DATABASE=db' \
                -e 'MYSQL_USER=domjudge' \
                -e 'MYSQL_PASSWORD=domjudge' \
                mysql/mysql-server:5.7

# Wait until MySQL has actually started
wait_db() {
  while [ "$(sudo docker inspect --format='{{json .State.Health.Status}}' db)" != '"healthy"' ]; do
    sleep 1
  done
}

# Configure MySQL according to DOMjudge recommendations
# Wait for MySQL to finish initializing first, otherwise it can corrupt the inner state
wait_db
sudo docker exec db bash -c "echo 'max_connections=1000' >> /etc/my.cnf"
sudo docker exec db bash -c "echo 'max_allowed_packet=512M' >> /etc/my.cnf"
sudo docker restart db
wait_db

# Create a DOMserver container (with bare-install, we don't want example data)
# Expose ports 80 (HTTP) and 443 (HTTPS) - even if HTTPS isn't needed, since ports must be exposed at container creation time
sudo docker rm -f server >> /dev/null 2>&1 || true
sudo docker run --name=server \
                --network=net \
                --detach \
                -p 80:80 \
                -p 443:443 \
                --restart=always \
                --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro \
                -e "CONTAINER_TIMEZONE=$TIMEZONE" \
                -e 'MYSQL_HOST=db' \
                -e 'MYSQL_DATABASE=db' \
                -e 'MYSQL_USER=domjudge' \
                -e 'MYSQL_PASSWORD=domjudge' \
                -e "MYSQL_ROOT_PASSWORD=$DB_PASSWORD" \
                -e 'DJ_DB_INSTALL_BARE=1' \
                domjudge/domserver:5.3.2

# TODO better way to check that the domjudge container has initialized the DB...
sleep 30

# Set a DOMjudge user's password
# $1: User
# $2: Password
password_set() {
  # We need to hash the password in the same way DOMjudge does it,
  # so... we use DOMjudge to do it. Sort of.
  # The dj_password_hash function is in lib/lib.wrappers.php,
  # but it also uses constants from the etc/domserver-config.php.
  HASH="$(sudo docker exec server \
                           php -r "require_once('/opt/domjudge/domserver/etc/domserver-config.php'); \
                                   require_once('/opt/domjudge/domserver/lib/lib.wrappers.php'); \
                                   echo(dj_password_hash('$2'));")"
  # After we have the hash, we can store it in the DB
  sudo docker exec db \
                   sh -c "echo 'update user set password=\"$HASH\" where username = \"$1\";' | mysql -uroot -p$DB_PASSWORD db"
}

# Set the passwords
password_set 'admin' "$ADMIN_PASSWORD"
password_set 'judgehost' "$JUDGE_PASSWORD"

# Disable results priority if needed (via JSON in SQL...)
if [ "$DISABLE_ERROR_PRIORITY" = "true" ]; then
  sudo docker exec db \
                   sh -c "echo 'update configuration \
                                set value = \"{\\\"memory-limit\\\":99,\\\"output-limit\\\":99,\\\"run-error\\\":99,\\\"timelimit\\\":99,\\\"wrong-answer\\\":99,\\\"no-output\\\":99,\\\"correct\\\":1}\" \
                                where name = \"results_prio\";' | mysql -uroot -p$DB_PASSWORD db"
fi
