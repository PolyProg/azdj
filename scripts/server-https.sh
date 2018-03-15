#!/bin/sh
# Enables HTTPS on a DOMjudge server Docker container (assumed to exist and be named 'server').

# Parameters:
# $DOMAIN: The domain
# $EMAIL: The e-mail address responsible for the domain

# Write down the command we'll execute within Docker.
# Note that the parameters are not expanded (thanks to the quoted EOF), but given later
cat > command.sh << 'EOF'
# Install getssl (much simpler than certbot)
# TODO reconsider certbot once they have fixed their nginx integration?
apt-get update
apt-get install -y --no-install-recommends curl dnsutils ca-certificates
curl --silent https://raw.githubusercontent.com/srvrco/getssl/master/getssl > getssl
chmod 700 getssl

# Create the getssl configuration
./getssl -c "$DOMAIN"

# Provide the proper CA (instead of the staging one), email, and ACME challenge path
#echo 'CA="https://acme-v01.api.letsencrypt.org"' >> "/root/.getssl/$DOMAIN/getssl.cfg"
echo 'ACCOUNT_EMAIL="$EMAIL"' >> "/root/.getssl/$DOMAIN/getssl.cfg"
echo 'ACL="/opt/domjudge/domserver/www/.well-known/acme-challenge"' >> "/root/.getssl/$DOMAIN/getssl.cfg"

# Remove the additional www domain, we don't need/want it
sed -i '/^SANS/d' "/root/.getssl/$DOMAIN/getssl.cfg"

# Generate the certificate
./getssl "$DOMAIN"

# Create a full-chain certificate
cat "/root/.getssl/$DOMAIN/$DOMAIN.crt" "/root/.getssl/$DOMAIN/chain.crt" >> "/root/.getssl/$DOMAIN/full.crt"

# Configure nginx to use HTTPS (by first removing existing directives and then adding some)
# the last sed uses | as a separator since it contains path that include /
sed -i '/^\s*listen/d' /etc/nginx/sites-enabled/default
sed -i '/^\s*server_name/d' /etc/nginx/sites-enabled/default
sed -i "s|^server {|server { \n\
\tlisten 443 ssl;\n\
\tserver_name $DOMAIN;\n\
\tssl_certificate /root/.getssl/$DOMAIN/full.crt;\n\
\tssl_certificate_key /root/.getssl/$DOMAIN/$DOMAIN.key;\n|" /etc/nginx/sites-enabled/default

# Configure nginx to redirect HTTP to HTTPS
echo "" >> /etc/nginx/sites-enabled/default # just in case it doesn't finish by a newline
echo "server { listen 80; return 301 https://$DOMAIN\$request_uri; }" >> /etc/nginx/sites-enabled/default

# Restart nginx
supervisorctl restart nginx
EOF

# Execute the command
sudo docker exec server bash -c "DOMAIN='$DOMAIN'; EMAIL='$EMAIL'; $(cat command.sh)"

# Remove the command file, useless now
rm command.sh
