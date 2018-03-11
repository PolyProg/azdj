## Basic properties

# Host name of the contest server (which you will configure on your DNS provider once the server is created)
CONTEST_HOSTNAME='contest.example.org'

# E-mail of the contest organizers
CONTEST_EMAIL='admin@example.org'

# Time zone of the contest
CONTEST_TIMEZONE='Europe/Zurich'

# IP ranges allowed to connect to the contest (space-separated)
CONTEST_ALLOWED_IP_RANGES="0.0.0.0/0"

# Set all judging errors to have the same priority (faster judging, less accurate errors)
CONTEST_DISABLE_ERROR_PRIORITY='true'

# Location of the contest in Azure
AZURE_LOCATION='westeurope'

# Size of the Azure VMs to use (B1ms is a reasonable and cheap default)
AZURE_VM_SIZE='Standard_B1ms'


## Advanced properties - do not touch unless you know what you are doing!

# Username for SSH
SSH_USERNAME='ssh-user'

# Name of the group in Azure
AZURE_GROUP_NAME='azdj'

# Name of the network security group in Azure
AZURE_NSG_NAME='net-sec-group'

# Name of the VM for the server in Azure
AZURE_VM_SERVER_NAME='server'

# Template of the VM names for judges in Azure (will be suffixed with a dash and a number)
AZURE_VM_JUDGE_NAME='judge'
