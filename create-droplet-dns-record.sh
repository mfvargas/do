#!/bin/bash

# Check if doctl is installed
if ! command -v doctl &> /dev/null; then
    echo "doctl is not installed. Exiting script..."
    exit 1
fi

# Check if all parameters are passed
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || \
   [ -z "$6" ] || [ -z "$7" ] || [ -z "$8" ] || [ -z "$9" ]; then
  echo -e "\nError: Required parameters not provided."
  echo "Usage: $0 DROPLET_NAME REGION IMAGE SIZE SSH_KEYS TAG_NAMES SSH_KEY_PATH DNS_RECORD_NAME DOMAIN"
  exit 1
fi

# Assign parameters to variables
DROPLET_NAME="$1"
REGION="$2"
IMAGE="$3"
SIZE="$4"
SSH_KEYS="$5"
TAG_NAMES="$6"
SSH_KEY_PATH="$7"
DNS_RECORD_NAME="$8"
DOMAIN="$9"

# Check if a droplet with the same name already exists
EXISTING_DROPLET_ID=$(doctl compute droplet list --format ID,Name --no-header | awk -v name=$DROPLET_NAME '$2 == name {print $1}')

# If a droplet with the same name exists, ask the user if they want to delete it
if [ ! -z "$EXISTING_DROPLET_ID" ]; then
  echo -e "\n"
  read -p "A droplet with the same name already exists. Do you want to delete it? [y/N]: " REPLY
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    echo "Deleting existing droplet with the same name..."
    doctl compute droplet delete -f $EXISTING_DROPLET_ID
  else
    echo "Exiting script..."
    exit 1
  fi
fi

# Create droplet
echo -e "\nCreating droplet..."
DROPLET_ID=$(doctl compute droplet create $DROPLET_NAME \
  --region $REGION \
  --image $IMAGE \
  --size $SIZE \
  --ssh-keys $SSH_KEYS \
  --tag-names $TAG_NAMES \
  --format ID \
  --no-header 2>&1)
CREATE_DROPLET_EXIT_CODE=$?

# Check for errors
if [ $CREATE_DROPLET_EXIT_CODE -ne 0 ]; then
    echo "Error creating droplet." >&2
    exit 1
fi

echo "Droplet created with ID: $DROPLET_ID"

# Wait for droplet to be "active"
STATUS=""
while [ "$STATUS" != "active" ]; do
  STATUS=$(doctl compute droplet get $DROPLET_ID --format Status --no-header)
  echo "Waiting for droplet to be active. Current status: $STATUS"
  sleep 10
done

# Get droplet IP address
DROPLET_IP=$(doctl compute droplet get $DROPLET_ID --format PublicIPv4 --no-header)

# Check if DNS record with the same name already exists
EXISTING_DNS_ID=$(doctl compute domain records list $DOMAIN --format ID,Name --no-header | awk -v name=$DNS_RECORD_NAME '$2 == name {print $1}')

# If DNS record with the same name exists, ask user if they want to delete it
if [ ! -z "$EXISTING_DNS_ID" ]; then
  echo -e "\n"
  read -p "A DNS record with the same name already exists. Do you want to delete it? [y/N]: " REPLY
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    echo "Deleting existing DNS record with the same name..."
    doctl compute domain records delete $DOMAIN $EXISTING_DNS_ID --force
  else
    echo "Exiting script..."
    exit 1
  fi
fi

# Create DNS record
echo -e "\nCreating DNS record..."
CREATE_DNS_RECORD_OUTPUT=$(doctl compute domain records create $DOMAIN \
  --record-type A \
  --record-name $DNS_RECORD_NAME \
  --record-data $DROPLET_IP \
  --record-ttl 1800 2>&1)
CREATE_DNS_RECORD_EXIT_CODE=$?

# Check for errors
if [ $CREATE_DNS_RECORD_EXIT_CODE -ne 0 ]; then
    echo "Error creating DNS record." >&2
    echo "doctl output: $CREATE_DNS_RECORD_OUTPUT" >&2
    exit 1
fi

echo "DNS record created with IP address: $DROPLET_IP"

# Setup commands to be run on the remote server
REMOTE_COMMANDS_UPDATE="sudo apt-get update -y -qq"
REMOTE_COMMANDS_UPGRADE="sudo apt-get upgrade -y -qq"
REMOTE_COMMANDS_USER_CREATE="adduser ubuntu --disabled-password --gecos \"\""
REMOTE_COMMANDS_USER_MOD="usermod -aG sudo ubuntu"
REMOTE_COMMANDS_USER_PASSWORDLESS="echo \"ubuntu ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/90-cloud-init-users"
REMOTE_COMMANDS_USER_RSYNC_KEYS="rsync --archive --chown=ubuntu:ubuntu ~/.ssh /home/ubuntu"

# Execute the commands on the remote server
echo -e "\nConfiguring droplet..."

echo -e "\nUpdating packages..."
until ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$DROPLET_IP "$REMOTE_COMMANDS_UPDATE"; do
    sleep 5
    echo "Retrying SSH connection for updating packages..."
done
echo "Update command executed successfully."

echo -e "\nUpgrading packages..."
until ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$DROPLET_IP "$REMOTE_COMMANDS_UPGRADE"; do
    sleep 5
    echo "Retrying SSH connection for upgrading packages..."
done
echo "Upgrade command executed successfully."

echo -e "\nCreating user 'ubuntu'..."
until ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$DROPLET_IP "$REMOTE_COMMANDS_USER_CREATE"; do
    sleep 5
    echo "Retrying SSH connection for creating user 'ubuntu'..."
done
echo "User 'ubuntu' created successfully."

echo -e "\nAdding user 'ubuntu' to group 'sudo'..."
until ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$DROPLET_IP "$REMOTE_COMMANDS_USER_MOD"; do
    sleep 5
    echo "Retrying SSH connection for adding user 'ubuntu' to group 'sudo'..."
done
echo "User 'ubuntu' added to group 'sudo' successfully."

echo -e "\nGranting user 'ubuntu' passwordless sudo privileges..."
until ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$DROPLET_IP "$REMOTE_COMMANDS_USER_PASSWORDLESS"; do
    sleep 5
    echo "Retrying SSH connection for granting user 'ubuntu' passwordless sudo privileges..."
done
echo "Passwordless sudo privileges granted to user 'ubuntu' successfully."

echo -e "\nRsyncing ssh keys to user 'ubuntu'..."
until ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$DROPLET_IP "$REMOTE_COMMANDS_USER_RSYNC_KEYS"; do
    sleep 5
    echo "Retrying SSH connection for rsyncing ssh keys to user 'ubuntu'..."
done
echo "SSH keys rsynced to user 'ubuntu' successfully."

echo -e "\nDroplet configuration completed."

# Print out the final message and the ssh command
echo -e "\n\nScript finished successfully!"

echo -e "\nYou can connect to the new droplet with the following command:"
echo "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no ubuntu@$DNS_RECORD_NAME.$DOMAIN"
echo -e "\nIf you can not connect using the host name, you can query name mapping (it should point to $DROPLET_IP) with:"
echo "nslookup $DNS_RECORD_NAME.$DOMAIN"
echo -e "\nYou can also restart network name resolution service in your local computer with:"
echo "sudo systemctl restart systemd-resolved"
echo -e "\nOr you can connect using the IP address:"
echo "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no ubuntu@$DROPLET_IP"
