#!/usr/bin/env bash
# infra is a naive helper script to start k3d clusters and Rancher Management Server
# Based on the work from https://github.com/ozbillwang/rancher-in-kind/
# and https://github.com/iwilltry42/k3d-demo

# example config file
# cat <<'_EOF_' >clusters.json
# [
#   { "name": "demo1", "labels": { "ansible_managed": "true","cloud_provider": "azure", "environment_stage": "staging"}},
#   { "name": "demo2", "labels": { "ansible_managed": "true","cloud_provider": "aws", "environment_stage": "staging"}},
#   { "name": "demo3", "labels": { "ansible_managed": "true","cloud_provider": "aws", "environment_stage": "production"}}
# ]
# _EOF_

set -u
set -o pipefail

RANCHER_CONTAINER_NAME="rancher-for-k3d"
: "${KIND_CLUSTER_NAME:="k3d-for-rancher"}"

CONFIG_FILENAME="clusters.json"

# dockerize all the things!!
CURL_IMAGE="appropriate/curl"
JQ_IMAGE="stedolan/jq"
RANCHER_IMAGE="rancher/rancher:latest"

case $(uname -s) in
  Darwin)
    localip="$(ipconfig getifaddr en0)"
  ;;
  Linux)
    localip="$(hostname -i)"
  ;;
  *)
    echo >&2 "Unsupported OS, exiting.."
    exit 1
  ;;
esac


function info() {
  if [[ ${QUIET:-0} -eq 0 ]] || [[ ${DEBUG:-0} -eq 1 ]]; then
    echo >&2 -e "\e[92mINFO:\e[0m $*"
  fi
}

function warn() {
  if [[ ${QUIET:-0} -eq 0 ]] || [[ ${DEBUG:-0} -eq 1 ]]; then
    echo >&2 -e "\e[33mWARNING:\e[0m $*"
  fi
}

function debug(){
  if [[ ${DEBUG:-0} -eq 1 ]]; then
    echo >&2 -e "\e[95mDEBUG:\e[0m $*"
  fi
}

function error(){
  local msg="$1"
  local exit_code="${2:-1}"
  echo >&2 -e "\e[91mERROR:\e[0m ${msg}"
  if [[ "${exit_code}" != "-" ]]; then
    exit "${exit_code}"
  fi
}

function usage() {
cat <<EOF
Usage: $0 [FLAGS] [ACTIONS]
  FLAGS:
    -h | --help | --usage   displays usage
    -q | --quiet            enabled quiet mode, no output except errors
    --debug                 enables debug mode, ignores quiet mode
  ACTIONS:
    prep                  Pull images, check for requirements
    create                create new Rancher & Kind cluster
    destroy               destroy Rancher & Kind cluster created by this script
  Examples:
    \$ $0 prep
    \$ $0 create
    \$ $0 destroy

EOF
}

if [  $# -lt 1 ] 
then 
  usage
  exit 1
fi 


function pull_images() {
  for image in $CURL_IMAGE $JQ_IMAGE; do
    until docker inspect $image > /dev/null 2>&1; do
      docker pull $image
      sleep 2
    done
  done

  until docker inspect "${RANCHER_IMAGE}" > /dev/null 2>&1; do
    docker pull "${RANCHER_IMAGE}"
    sleep 2
  done
}

function check_binaries() {
  # check docker binary availability
  if ! which docker >/dev/null; then
    error "Docker binary cannot be found in PATH" -
    error "Install Docker or check your PATH, exiting.."
  fi

  # check k3d binary availability
  if ! which k3d >/dev/null; then
    error 'k3d binary is missing' -
    error 'Install it with "brew install k3d" (MacOS/Linux Homebrew users)' -
    error 'For more details see:' -
    error ' - https://k3d.io/#installation' -
    error 'exiting..'
  fi
}

function check_directories() {
  if [ ! -d ".config" ]; then
    mkdir -p .config
  fi
}

function prep() {
  pull_images
  check_binaries
  check_directories
}


# if [[ "${MODE:-}" == "destroy" ]]; then
function destroy() {
  info 'Destroying Rancher container..'
  if ! docker rm -f ${RANCHER_CONTAINER_NAME}; then
    error "failed to remove Rancher container \"${RANCHER_CONTAINER_NAME}\".." -
  fi
  # info 'Destroying Kind cluster..'
  # if ! kind delete cluster --name ${KIND_CLUSTER_NAME}; then
  #   error "failed to delete Kind cluster \"${KIND_CLUSTER_NAME}\".." -
  # fi
  for cluster_name in $(jq -r '.[] | .name' "${CONFIG_FILENAME}") ; do
    info "Destroying k3d cluster $cluster_name .."    
    if ! k3d cluster delete "${cluster_name}"; then
      error "failed to delete Kind cluster \"${KIND_CLUSTER_NAME}\".." -
    fi
  done
  rm -fr .config/*
  exit 0
}


function launch_rancher_server() {
  RANCHER_HTTP_HOST_PORT=$(($((RANDOM%9000))+30000))
  RANCHER_HTTPS_HOST_PORT=$(($((RANDOM%9000))+30000))
  URL="${localip}:${RANCHER_HTTPS_HOST_PORT}"
  # Launch Rancher server
  if [[ $(docker ps -f name=${RANCHER_CONTAINER_NAME} -q | wc -l) -ne 0 ]]; then
    info "Rancher container already present"
  else
    info 'Launching Rancher container'
    if docker run -d --restart=unless-stopped \
                  --name ${RANCHER_CONTAINER_NAME}  \
                  -p ${RANCHER_HTTP_HOST_PORT}:80   \
                  -p ${RANCHER_HTTPS_HOST_PORT}:443 \
                  --privileged \
                  rancher/rancher; then
      info "Rancher UI will be available at https://${localip}:${RANCHER_HTTPS_HOST_PORT}"
      info "It might take few up to 60 seconds for Rancher UI to become available.."
    fi
    printf "Waiting for rancher server to be ready ..."
    until docker run --rm --net=host "${CURL_IMAGE}" -slk --connect-timeout 5 --max-time 5 "https://${URL}/ping" &> /dev/null ; do
      printf "."
      sleep 3
    done
    printf "%s" "${URL}" > .config/rancher_url
    echo
  fi

}


function setup_rancher_server() {
  URL=$(cat .config/rancher_url)
  # first get token using default creds
  while true; do
      LOGINRESPONSE=$(docker run \
          --rm \
          --net=host \
          "${CURL_IMAGE}" \
          -s "https://${URL}/v3-public/localProviders/local?action=login" -H 'content-type: application/json' --data-binary '{"username":"admin","password":"admin"}' --insecure)
      LOGINTOKEN=$(echo "${LOGINRESPONSE}" | docker run --rm -i "${JQ_IMAGE}" -r .token)
      printf "%s" "${LOGINTOKEN}" > .config/logintoken
      if [ "${LOGINTOKEN}" != "null" ]; then
          break
      else
          sleep 5
      fi
  done
  # Create password
  RANCHER_PASSWORD=$(openssl rand -base64 12)
  printf "%s" "${RANCHER_PASSWORD}" > .config/rancher_password
  info "Rancher UI ready, admin password was changed, new value available in the .config/rancher_password file"

  # change admin user's default password 
  # using api
  docker run --rm --net=host "${CURL_IMAGE}" -s "https://${URL}/v3/users?action=changepassword" -H 'content-type: application/json' -H "Authorization: Bearer ${LOGINTOKEN}" --data-binary '{"currentPassword":"admin","newPassword":"'"${RANCHER_PASSWORD}"'"}' --insecure
  # using docker exec
  # https://rancher.com/docs/rancher/v2.x/en/faq/technical/#how-can-i-reset-the-admin-password
  # RANCHER_PASSWORD=$(docker exec -ti ${RANCHER_CONTAINER_NAME} reset-password | tail -n1)

  # Create API key
  APIRESPONSE=$(curl --insecure -s "https://${URL}/v3/token" -H 'content-type: application/json' -H "Authorization: Bearer $LOGINTOKEN" --data-binary '{"type":"token","description":"automation"}')
  # Extract and store token
  APITOKEN=$(echo "${APIRESPONSE}" | jq -r .token)
  printf "%s" "${APITOKEN}" > .config/apitoken
  # example: token-55xfm:pvhlfhdr5hm5tbksfddlmwjccf2g8rf9rqd4d7zl7t2lt4m47cnc62

  # Configure server-url
  docker run --rm --net=host "${CURL_IMAGE}" --silent --insecure "https://${URL}/v3/settings/server-url" -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" -X PUT --data-binary '{"name":"server-URL","value":"https://'"${URL}"'"}'
}


function create_cluster(){
  unset KUBECONFIG
  cluster_name=$1
  id=$2
  api_port="655${id}"
  # 1 server/node cluster, no workers/agents/nodes
  cluster_port="808${id}"
  # k3d cluster create "${cluster_name}" --api-port "${api_port}" --servers 1 --port "${cluster_port}:80@loadbalancer" --k3s-server-arg "--no-deploy=traefik" --wait
  k3d cluster create "${cluster_name}" --api-port "${localip}:${api_port}" --servers 1 --port "${cluster_port}:80@loadbalancer" --wait
  k3d kubeconfig get "$cluster_name" | tee ".config/kubeconfig-${cluster_name}"
  # print info
  kubectl cluster-info --kubeconfig ".config/kubeconfig-${cluster_name}"
}

function launch_k3d_clusters() {
  index_count=0
  for cluster_name in $(jq -r '.[] | .name' "${CONFIG_FILENAME}") ; do
    if [[ $(k3d cluster list "${cluster_name}") ]]; then
      info "k3d cluster already present: ${cluster_name}"
    else
      info "Launching k3d cluster $cluster_name .."
      create_cluster "${cluster_name}" "${index_count}"
    fi
    index_count=$(( index_count+1))
  done
}

function import_cluster(){
  sleep 5
  cluster_name=$1
  api_token=$(cat .config/apitoken)
  CLUSTERRESPONSE=$(docker run --rm --net=host "${CURL_IMAGE}" --silent --insecure "https://${URL}/v3/cluster" -H 'content-type: application/json' -H "Authorization: Bearer ${api_token}" --data-binary '{"type":"cluster","name":"'"${cluster_name}"'","import":true, "labels":'"$(jq -cr '.[] | select(.name=="'"${cluster_name}"'") | .labels' clusters.json)"'}')
  # echo "${CLUSTERRESPONSE}"
  # TODO: use container image for jq command
  CLUSTERID=$(echo "${CLUSTERRESPONSE}" | jq -r .id)
  # echo ${CLUSTERID}
  # Generate token (clusterRegistrationToken) and extract nodeCommand
  DEFAULTAGENTCOMMAND=$(docker run --rm --net=host "${CURL_IMAGE}" --silent --insecure "https://${URL}/v3/clusters/${CLUSTERID}/clusterregistrationtoken" -H 'content-type: application/json' -H "Authorization: Bearer ${api_token}" --data-binary '{"type":"clusterRegistrationToken","clusterId":"'"${CLUSTERID}"'"}' | jq -r .insecureCommand)
  # Show the command
  # echo "${DEFAULTAGENTCOMMAND}"
  # Add cluster's kubeconfig file to kubectl
  AGENTCOMMAND="$(echo "${DEFAULTAGENTCOMMAND}" | cut -f1 -d\|) | kubectl apply --kubeconfig ".config/kubeconfig-${cluster_name}" -f -"
  # Show the command
  echo "${AGENTCOMMAND}" 
  eval "${AGENTCOMMAND}"
}

function import_k3d_clusters(){
  for cluster_name in $(jq -r '.[] | .name' "${CONFIG_FILENAME}") ; do
    import_cluster "${cluster_name}"
  done
}

function create() {
  launch_rancher_server
  sleep 30
  setup_rancher_server
  sleep 30
  launch_k3d_clusters
  sleep 30
  import_k3d_clusters
}

function test() {
  index_count=0
  for cluster_name in $(jq -r '.[] | .name' "${CONFIG_FILENAME}") ; do
    cluster_port="808${index_count}"
    echo " -- cluster: ${cluster_name} --$cluster_port"
    curl --silent "localhost:${cluster_port}" | jq -r '[.message,.version]| @csv'
    index_count=$(( index_count+1))
  done
}

## Get CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help|--usage)
      usage
      exit 0
    ;;

    -d|--debug)
      DEBUG=1
      shift 1
    ;;

    -q|--quiet)
      QUIET=1
      shift 1
    ;;

    create|init)
      # MODE="create"
      create
      shift 1
    ;;

    prep)
      prep
      shift 1
    ;;

    destroy|cleanup)
      # MODE="destroy"
      destroy
      shift 1
    ;;

    test)
      test
      shift 1
    ;;

    *)
      error "Unexpected option \"$1\"" -
      usage
      exit 1
    ;;
  esac
done
