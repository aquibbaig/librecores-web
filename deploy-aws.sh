#!/bin/bash
#
# Deploy the librecores site to AWS
#

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Install dependencies required to run this script
function install_deps
{
  echo Installing Python dependencies
  pip3 install --user -r $SCRIPT_DIR/ansible/requirements.txt
}

function usage
{
  cat << EOF
Usage: $0 ENVIRONMENT ACTION

Executes the deployment action ACTION in the environment ENVIRONMENT on
Amazon Web Services (AWS).

Available ENVIRONMENTs:
  staging
    Staging setup: stage.librecores.org

  production
    Production setup: librecores.org

Available ACTIONs:
  provision
    Run the initial setup of the AWS account to create all necessary
    instances and firewall settings.

  deploy
    Deploy current code

  resetdata
    DANGEROUS: Resets all data in the database.

  initdata
    Initialize the site with the data fixtures from Git.

Environment variables:
  ANSIBLE_VAULT_PASSWORD_FILE
    Path to a password file used to decrypt the Ansible Vault.
EOF
}

# Check if all required AWS credentials are set in the environment
function ensure_aws_creds
{
  test -f aws-secrets.include && . aws-secrets.include
  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo Error: No AWS secrets were found in the environment. >&2
    echo >&2
    echo Fix option 1: >&2
    echo cp aws-secrets.include.dist aws-secrets.include >&2
    echo and update the file with your credentials. >&2
    echo >&2
    echo Fix option 2:>&2
    echo Manually set the environment variables AWS_ACCESS_KEY_ID and >&2
    echo AWS_SECRET_ACCESS_KEY. >&2
    echo >&2
    echo Then run this script again. >&2
    exit 1
  fi
}

# Check if the SSH keys for the environment $argv[1] are available
function ensure_ssh_keys
{
  environment=$1

  if [ ! -f $HOME/.ssh/librecores-$environment ] ||
     [ ! -f $HOME/.ssh/librecores-$environment.pub ]; then

     echo "Installing SSH keys for $environment. You may be asked for the "
     echo "$environment vault password."
     echo
     ansible-playbook $ANSIBLE_EXTRA_ARGS \
      ansible/$environment-aws-configure-local-ssh.yml
  fi


  if [ ! -f $HOME/.ssh/librecores-$environment ] ||
     [ ! -f $HOME/.ssh/librecores-$environment.pub ]; then

     echo Unable to install SSH keys for $environment environment. >&2
     exit 1
  fi
}

# check (and possibly install) dependencies
ansible_missing=$(which ansible >/dev/null 2>&1; echo $?)
boto_missing=$(python -c "import boto" >/dev/null 2>&1; echo $?)

if [ $ansible_missing -eq 1 ] || [ $boto_missing -eq 1 ]; then
  install_deps
fi


if [ -z "$ANSIBLE_VAULT_PASSWORD_FILE" ]; then
  ANSIBLE_EXTRA_ARGS="--ask-vault-pass $ANSIBLE_EXTRA_ARGS"
else
  ANSIBLE_EXTRA_ARGS="--vault-password-file=$ANSIBLE_VAULT_PASSWORD_FILE $ANSIBLE_EXTRA_ARGS"
fi

# Disable host key checking in Ansible's SSH
export ANSIBLE_HOST_KEY_CHECKING=False

export ANSIBLE_CFG=$SCRIPT_DIR/ansible/ansible.cfg

environment=$1
action=$2

case $environment in
  staging|production)
    echo Running steps in $environment environment.
    ;;
  *)
    echo ERROR: Unknown environment '$environment'. >&2
    echo
    usage
    exit 1
esac

case $action in
  show-inventory)
    ensure_aws_creds
    ansible-inventory \
      -i $SCRIPT_DIR/ansible/aws_ec2.yml \
      --playbook-dir $SCRIPT_DIR/ansible \
      --list
    ;;
  provision)
    ensure_aws_creds
    ensure_ssh_keys $environment
    ansible-playbook \
      --private-key $HOME/.ssh/librecores-$environment \
      -i $SCRIPT_DIR/ansible/aws_ec2.yml \
      $ANSIBLE_EXTRA_ARGS \
      ansible/$environment-aws-provision.yml
    ;;
  deploy|resetdata|initdata)
    ensure_ssh_keys $environment
    ansible-playbook \
      --private-key $HOME/.ssh/librecores-$environment \
      -i $SCRIPT_DIR/aws-static-inventory \
      $ANSIBLE_EXTRA_ARGS \
      ansible/$environment-aws-$action.yml
    ;;
  "")
    echo ERROR: No action given. >&2
    echo
    usage
    exit 1
    ;;
  *)
    echo "ERROR: Unknown action '$action'." >&2
    echo
    usage
    exit 1
esac
