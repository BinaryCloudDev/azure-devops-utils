#!/bin/bash

function print_usage() {
  cat <<EOF
Command
  $0
Arguments
  --storage_account_name|-san [Required] : Storage Account name used for Spinnaker's persistent storage
  --storage_account_key|-sak  [Required] : Storage Account key used for Spinnaker's persistent storage
  --front50_port|-fp                     : Port to use for front50, if different than the default
  --artifacts_location|-al               : Url used to reference other scripts/artifacts.
  --sas_token|-st                        : A sas token needed if the artifacts location is private.
EOF
}

function throw_if_empty() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "Parameter '$name' cannot be empty." 1>&2
    print_usage
    exit -1
  fi
}

function run_util_script() {
  local script_path="$1"
  shift
  curl --silent "${artifacts_location}${script_path}${artifacts_location_sas_token}" | sudo bash -s -- "$@"
  local return_value=$?
  if [ $return_value -ne 0 ]; then
    >&2 echo "Failed while executing script '$script_path'."
    exit $return_value
  fi
}

#Set defaults
artifacts_location="https://raw.githubusercontent.com/Azure/azure-devops-utils/master/"
front50_port=""

while [[ $# > 0 ]]
do
  key="$1"
  shift
  case $key in
    --storage_account_name|-san)
      storage_account_name="$1"
      shift
      ;;
    --storage_account_key|-sak)
      storage_account_key="$1"
      shift
      ;;
    --front50_port|-fp)
      front50_port="$1"
      shift
      ;;
    --artifacts_location|-al)
      artifacts_location="$1"
      shift
      ;;
    --sas_token|-st)
      artifacts_location_sas_token="$1"
      shift
      ;;
    --help|-help|-h)
      print_usage
      exit 13
      ;;
    *)
      echo "ERROR: Unknown argument '$key' to script '$0'" 1>&2
      exit -1
  esac
done

throw_if_empty --storage_account_name $storage_account_name
throw_if_empty --storage_account_key $storage_account_key

curl --silent -O https://raw.githubusercontent.com/spinnaker/halyard/master/install/stable/InstallHalyard.sh
sudo bash InstallHalyard.sh -y
rm InstallHalyard.sh

# Set Halyard to use the latest released/validated version of Spinnaker
hal config version edit --version $(hal version latest -q)

hal config storage azs edit --storage-account-name $storage_account_name --storage-account-key $storage_account_key
hal config storage edit --type azs

sudo hal deploy apply

if [ -n "$front50_port" ] && [ "$front50_port" != "8080" ]; then
  echo "Reconfiguring front50 to use port '${front50_port}'..."
  spinnaker_local_config="/opt/spinnaker/config/spinnaker-local.yml"
  front50_port=8081
  sudo touch "$spinnaker_local_config"
  sudo cat <<EOF >"$spinnaker_local_config"
services:
  front50:
    port: $front50_port
EOF
  sudo service spinnaker restart # We have to restart all services so that they know how to communicate to front50
fi