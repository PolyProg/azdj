#!/bin/bash -x
# azdj, the Azure DOMjudge utility

# TODO:
# - Redirect all output to a log file (EXCEPT azure login!)
# - TLS via letsencrypt
# - Custom languages in judgehosts

### Parse arguments

print_help() {
  echo 'Usage:'
  echo "$0 init"
  echo "$0 add-judge"
  exit 1
}

if [ $# -eq 0 ]; then
  print_help
fi
if [ "$1" != 'init' ] && [ "$1" != 'add-judge' ]; then
  print_help
fi


### Sanity checks

# Make sure we're in the proper directory
if [ ! -d 'scripts' ]; then
  echo "Please run $0 from the folder it is located in."
  exit 1
fi

# Make sure config exists
if [ ! -f 'config.sh' ]; then
  echo 'Please copy the config template to "config.sh" after having modified it according to your needs.'
  exit 1
fi


### Setup

# Load config
. ./config.sh

# State directory, to store other stuff
STATE_DIR='.state'

# Check if it's the first run, install deps if so
if [ ! -d "$STATE_DIR" ]; then
  sudo apt-get update
  sudo apt-get install -y bc openssl openssh-client

  mkdir "$STATE_DIR"
fi

# Install Azure CLI
if ! command -v az >> /dev/null; then
  # from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-apt
  sudo apt-get install -y dirmngr # from their "known issues" - just in case
  echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
  sudo apt-key adv --keyserver packages.microsoft.com --recv-keys 52E16F86FEE04B979B07E28DB02C46DF417A0893
  sudo apt-get install -y apt-transport-https
  sudo apt-get update
  sudo apt-get install -y azure-cli
fi

# Log into Azure (user interaction!)
if ! az account show >> /dev/null 2>&1; then
  echo 'Please log into Azure:'
  az login
fi

# Create an SSH key
SSH_KEY_FILE="$STATE_DIR/ssh_key"
if [ ! -f "$SSH_KEY_FILE" ]; then
  ssh-keygen -t rsa -b 4096 -C "$CONTEST_EMAIL" -f "$SSH_KEY_FILE" -P ""
fi

# SSH to a VM
# $1: VM IP
# $2: Command to run
vm_ssh() {
  ssh \
    -i "$SSH_KEY_FILE" `# use the key we generated` \
    -o "StrictHostKeyChecking no" `# don't prompt to accept unknown hosts` \
    -o "ConnectTimeout 5" -o "ConnectionAttempts 100" `# retry a lot, in case server is rebooting` \
    "$SSH_USERNAME@$1" `# use the user we generated` \
    "$2"
}

# Get, or create if needed, passwords
# $1: File in which it should be stored
# Prints the password on stdout
password_get() {
  password_file="$STATE_DIR/$1"
  if [ ! -f "$password_file" ]; then
    echo "$(openssl rand -base64 32)" > "$password_file"
  fi
  cat "$password_file"
}

# DB root password
DB_ROOT_PASSWORD_FILE='db_root_password'
DB_ROOT_PASSWORD="$(password_get $DB_ROOT_PASSWORD_FILE)"

# Server 'admin' password
SERVER_ADMIN_PASSWORD_FILE='admin_password'
SERVER_ADMIN_PASSWORD="$(password_get $SERVER_ADMIN_PASSWORD_FILE)"

# Server 'judgehost' password (for judge daemons)
SERVER_JUDGE_PASSWORD_FILE='judge_password'
SERVER_JUDGE_PASSWORD="$(password_get $SERVER_JUDGE_PASSWORD_FILE)"

# Create an Azure resource group
if [ "$(az group exists --name "$AZURE_GROUP_NAME")" = "false" ]; then
  az group create --name "$AZURE_GROUP_NAME" \
                  --location "$AZURE_LOCATION"
fi

# Create an Azure NSG
if [ -z "$(az network nsg show --resource-group "$AZURE_GROUP_NAME" \
                               --name "$AZURE_NSG_NAME")" ]; then
  az network nsg create --resource-group "$AZURE_GROUP_NAME" \
                        --name "$AZURE_NSG_NAME" \
                        --location "$AZURE_LOCATION"
fi

# Allow an IP range to access the VMs
# $1: The IP range
nsg_range_index=100 # min priority
nsg_allow_range() {
  # 22: SSH
  # 80: HTTP
  for port in '22' '80'; do
    # note: using the range in the rule name is not possible because of the slash
    rule_name="$port-$nsg_range_index"
    nsg_range_index="$(echo "$nsg_range_index + 1" | bc)"

    if [ -z "$(az network nsg rule show --resource-group "$AZURE_GROUP_NAME" \
                                        --nsg-name "$AZURE_NSG_NAME" \
                                        --name "$rule_name")" ]; then
      az network nsg rule create --resource-group "$AZURE_GROUP_NAME" \
                                 --nsg-name "$AZURE_NSG_NAME" \
                                 --name "$rule_name" \
                                 --access Allow \
                                 --protocol Tcp \
                                 --direction Inbound \
                                 --priority "$nsg_range_index" \
                                 --source-address-prefix "$1" \
                                 --source-port-range '*' \
                                 --destination-address-prefix '*' \
                                 --destination-port-range "$port"
    fi
  done
}

# Configure the NSG inbound rules from config
for range in "$CONTEST_ALLOWED_IP_RANGES"; do
  nsg_allow_range "$range"
done

# Get the NSG's ID to create VMs
AZURE_NSG_ID="$(az network nsg show --resource-group "$AZURE_GROUP_NAME" \
                                    --name "$AZURE_NSG_NAME" \
                                    --query id -o tsv)"

# Create a VM
# $1: VM name
# Returns via stdout: The IP, or an empty string if the VM doesn't exist
vm_create() {
  # Create the VM
  az vm create --resource-group "$AZURE_GROUP_NAME" \
               --name "$1" \
               --nsg "$AZURE_NSG_ID" \
               --size "$AZURE_VM_SIZE" \
               --admin-username "$SSH_USERNAME" \
               --ssh-key-value "$SSH_KEY_FILE.pub" \
               --image UbuntuLTS >> /dev/null 2>&1

  # Wait for creation to finish
  az vm wait --resource-group "$AZURE_GROUP_NAME" \
             --name "$1" \
             --created >> /dev/null 2>&1

  # Get its IP
  az vm show --resource-group "$AZURE_GROUP_NAME" \
             --name "$1" \
             --show-details \
             --output tsv `# don't print quotes` \
             --query publicIps
}


### Get or create the contest server

SERVER_IP_FILE="$STATE_DIR/server_ip"
if [ ! -f "$SERVER_IP_FILE" ]; then
  if [ "$1" != 'init' ]; then
    echo 'Contest server does not exists. Please use the "init" command.'
    exit 1
  fi

  # Create the VM
  SERVER_IP="$(vm_create "$AZURE_VM_SERVER_NAME")"

  # Initialize it
  vm_ssh "$SERVER_IP" "$(cat scripts/init.sh)"

  # Install the DOMjudge server
  vm_ssh "$SERVER_IP" "TIMEZONE='$CONTEST_TIMEZONE'; \
                       DISABLE_ERROR_PRIORITY='$CONTEST_DISABLE_ERROR_PRIORITY'; \
                       DB_PASSWORD='$DB_ROOT_PASSWORD'; \
                       ADMIN_PASSWORD='$SERVER_ADMIN_PASSWORD'; \
                       JUDGE_PASSWORD='$SERVER_JUDGE_PASSWORD'; \
                       $(cat scripts/server.sh)"

  # Write down the IP
  echo "$SERVER_IP" > "$SERVER_IP_FILE"

  # Explain what happened
  echo 'Contest server created'
  echo "Its IP is '$SERVER_IP', written down in $SERVER_IP_FILE"
  echo "Its admin password is '$SERVER_ADMIN_PASSWORD', written down in $SERVER_ADMIN_PASSWORD_FILE"
  echo "Its judgehost password is '$SERVER_JUDGE_PASSWORD', written down in $SERVER_JUDGE_PASSWORD_FILE"
  echo "Its root DB password is '$DB_ROOT_PASSWORD', written down in $DB_ROOT_PASSWORD_FILE"
  echo "Use $0 add-judge to add judges"
fi

SERVER_IP="$(cat "$SERVER_IP_FILE")"



### Add a judge if needed

if [ "$1" = 'add-judge' ]; then
  # Store each judge as a single file containing its IP
  JUDGES_DIR="$STATE_DIR/judges"
  mkdir -p "$JUDGES_DIR"

  # Get the first unused index
  JUDGE_INDEX=0
  while [ -f "$JUDGES_DIR/$JUDGE_INDEX" ]; do
    JUDGE_INDEX="$(echo "$JUDGE_INDEX + 1" | bc)"
  done

  # Make up the name for the VM
  JUDGE_NAME="$AZURE_VM_JUDGE_NAME-$JUDGE_INDEX"

  # Create the VM
  JUDGE_IP="$(vm_create "$JUDGE_NAME")"

  # Allow its IP to access the others (since it communicates with the server via http)
  nsg_allow_range "$JUDGE_IP/32"

  # Initialize it
  vm_ssh "$JUDGE_IP" "$(cat scripts/init.sh)"

  # Install the DOMjudge judge
  vm_ssh "$JUDGE_IP" "TIMEZONE='$CONTEST_TIMEZONE'; \
                      SERVER='$SERVER_IP'; \
                      SERVER_PASSWORD='$SERVER_JUDGE_PASSWORD'; \
                      $(cat scripts/judge.sh)"

  # Write down its IP
  echo "$JUDGE_IP" > "$JUDGES_DIR/$JUDGE_INDEX"

  # Explain what happened
  echo 'Done!'
  echo "The judge's IP is '$JUDGE_IP', written down in $JUDGES_DIR/$JUDGE_INDEX"
  echo "There are now $(echo "$JUDGE_INDEX + 1" | bc) judges"
fi
