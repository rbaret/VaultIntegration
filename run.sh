#!/bin/bash
# Create a random root token for Vault
export VAULT_DEV_ROOT_TOKEN_ID=$(openssl rand -base64 15)

# Create a random password for the root user of the database
export MYSQL_ROOT_PASSWORD=$(openssl rand -base64 15)

# Create a random password for the Vault user of the database
export MYSQL_VAULT_PASSWORD=$(openssl rand -base64 15)

export VAULT_ADDR='localhost:8200'

# Run the docker-compose file to depdoy Vault, mysql and the app
docker-compose up -d
sleep 5 # Wait for the containers to start
echo "Enable mysqli extension for the app container"

docker exec -it app sh -c " docker-php-ext-install mysqli && apachectl restart" &>/dev/null
docker restart app
echo "Inserting data into the database"
docker exec -i database mysql -uroot -p${MYSQL_ROOT_PASSWORD} app < dump.sql

echo "Creating a Vault user for the database"
# Connect to the mysql container and create a role with read-only access to the app database
docker exec -i database mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "CREATE ROLE 'appreadonly'; GRANT SELECT ON app.* TO 'appreadonly';"

# Connect to the mysql container and create a role with read-write access to the app database
docker exec -i database mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "CREATE ROLE 'appreadwrite'; GRANT SELECT, INSERT, UPDATE, DELETE ON app.* TO 'appreadwrite';"

echo "Granting Vault user permissions to create other users and assign roles"
# Connect to the mysql container and grant vault user permissions to create other users
docker exec -i database mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "GRANT ALL PRIVILEGES ON *.* TO 'vault'@'%';FLUSH PRIVILEGES;"

# Save the root token in a file
echo ${VAULT_DEV_ROOT_TOKEN_ID} > ~/root_token.txt
chmod 600 ~/root_token.txt

# API calls to perform the initial configuration of Vault

# Enable the database secrets engine
echo "Enabling the database secrets engine"
curl \
    --header "X-Vault-Token: ${VAULT_DEV_ROOT_TOKEN_ID}" \
    --request POST \
    --data '{"type": "database"}' \
    http://${VAULT_ADDR}/v1/sys/mounts/database


echo "Configuring the database secrets engine"
# Configure Vault to connect to the database
tee payload.json &>/dev/null <<EOF
{
  "plugin_name": "mysql-database-plugin",
  "connection_url": "{{username}}:{{password}}@tcp(database:3306)/",
    "allowed_roles": ["appreadonly", "appreadwrite"],
    "username": "vault",
    "password": "${MYSQL_VAULT_PASSWORD}"
}
EOF

curl \
    --header "X-Vault-Token: ${VAULT_DEV_ROOT_TOKEN_ID}" \
    --request POST \
    --data @payload.json \
    http://${VAULT_ADDR}/v1/database/config/mysql

echo "Creating a Vault role called appreadonly which matches the appreadonly role in MySQL"

tee payload.json &>/dev/null <<EOF
{
  "db_name": "mysql",
  "creation_statements": ["CREATE USER '{{name}}' IDENTIFIED BY '{{password}}';",
                          "GRANT 'appreadonly' TO '{{name}}';",
                          "SET DEFAULT ROLE ALL TO '{{name}}'@'%';"],
  "default_ttl": "1m",
  "max_ttl": "10m"
}
EOF

curl \
    --header "X-Vault-Token: ${VAULT_DEV_ROOT_TOKEN_ID}" \
    --request POST \
    --data @payload.json \
    http://${VAULT_ADDR}/v1/database/roles/appreadonly

echo "Creating a policy for the appreadonly role"
tee payload.json &>/dev/null <<EOF
{
  "policy": "path \"database/creds/appreadonly\" {\n  capabilities = [\"read\"]\n}"
}
EOF

curl \
    --header "X-Vault-Token: ${VAULT_DEV_ROOT_TOKEN_ID}" \
    --request POST \
    --data @payload.json \
    http://${VAULT_ADDR}/v1/sys/policy/appreadonly

echo "Creating an appreadwrite role in Vault which matches the appreadwrite role in MySQL"
tee payload.json &>/dev/null <<EOF
{
  "db_name": "mysql",
  "creation_statements": ["CREATE USER '{{name}}' IDENTIFIED BY '{{password}}';",
                          "GRANT 'appreadwrite' TO '{{name}}';",
                          "SET DEFAULT ROLE ALL TO '{{name}}'@'%';"],
  "default_ttl": "1m",
  "max_ttl": "10m"
}
EOF

curl \
    --header "X-Vault-Token: ${VAULT_DEV_ROOT_TOKEN_ID}" \
    --request POST \
    --data @payload.json \
    http://${VAULT_ADDR}/v1/database/roles/appreadwrite

echo "Creating a policy for the appreadwrite role"
tee payload.json &>/dev/null <<EOF
{
  "policy": "path \"database/creds/appreadwrite\" {\n  capabilities = [\"read\"]\n}"
}
EOF

curl \
    --header "X-Vault-Token: ${VAULT_DEV_ROOT_TOKEN_ID}" \
    --request POST \
    --data @payload.json \
    http://${VAULT_ADDR}/v1/sys/policy/appreadwrite


rm payload.json

echo "Creating a token for the app"
export VAULT_TOKEN=$(curl \
    --header "X-Vault-Token: ${VAULT_DEV_ROOT_TOKEN_ID}" \
    --request POST \
    --data '{"policies": ["appreadonly","appreadwrite"]}' \
    http://${VAULT_ADDR}/v1/auth/token/create | jq -r '.auth.client_token')



echo "Injecting the token in the app container"
docker exec -it app sh -c "echo 'export VAULT_TOKEN=${VAULT_TOKEN}' >> /etc/apache2/envvars && apachectl restart"

echo "Restarting the app container"
docker restart app

clear
echo "#### DEBUG Information for the app ####"
echo "The app is now running on http://$HOSTNAME:80"
echo "The root token is stored in ~/root_token.txt"
# echo "The root password for the database is ${MYSQL_ROOT_PASSWORD}"
# echo "The password for the Vault user of the database is ${MYSQL_VAULT_PASSWORD}"
# echo "The Vault token for the app is ${VAULT_TOKEN}"
echo "As the credentials for the database are generated randomly, remove the volume to reset the database when re-running this script"