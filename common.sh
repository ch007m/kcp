#!/usr/bin/env bash

set -e

shopt -s expand_aliases
alias k='kubectl'

# Defining some colors for output
NC='\033[0m' # No Color
COLOR_RESET="\033[0m" # Reset color
BLACK="\033[0;30m"
BLUE='\033[0;34m'
BROWN="\033[0;33m"
GREEN='\033[0;32m'
GREY="\033[0;90m"
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
RED='\033[0;31m'
PURPLE="\033[0;35m"
WHITE='\033[0;37m'
YELLOW='\033[0;33m'

shopt -s expand_aliases
alias k='kubectl'

####################################
## Section to declare the functions
####################################
repeat_char(){
  COLOR=${1}
	for i in {1..70}; do echo -ne "${!COLOR}$2${NC}"; done
}

msg() {
  COLOR=${1}
  MSG="${@:2}"
  echo -e "\n${!COLOR}## ${MSG}${NC}"
}

succeeded() {
  echo -e "${GREEN}NOTE:${NC} $1"
}

note() {
  echo -e "${BLUE}NOTE:${NC} $1"
}

warn() {
  echo -e "${YELLOW}WARN:${NC} $1"
}

error() {
  echo -e "${RED}ERROR:${NC} $1"
}

log() {
  MSG="${@:2}"
  echo; repeat_char ${1} '#'; msg ${1} ${MSG}; repeat_char ${1} '#'; echo
}

print_help() {
cat << EOF
Usage:
  $0 [args]

Arguments:
    -h            Display the help
    -t            Temporary folder where kcp is running. Default: _tmp
    -w            Workspace to be used for the demo. Default: my-org
    -i            hostname or ip address of the physical cluster to be used to access ingress routes
    -v            Version of kcp to be installed

Use $0 -h for more information about a given scenario.

EOF
}

############################################################################
## Get the arguments passed to the command
############################################################################
while getopts ":ht:w:i:v:" arg; do
   # note "Arg: ${arg}."
   case ${arg} in
      h) # display Help
         print_help
         exit
         ;;
      t) # Temporary directory where kcp is running
         TEMP_DIR=${OPTARG}
         ;;
      w) # Workspace to sync resources between kcp and target cluster
         KCP_WORKSPACE=${OPTARG}
         ;;
      i) #
         HOSTNAME_IP=${OPTARG}
         ;;
      v) # Version of kcp to be installed
         KCP_VERSION=${OPTARG}
         ;;
      ?) # Invalid arg
         error "Invalid arg was specified -$OPTARG"
         echo
         print_help
         exit
         ;;
   esac
done

#######################################################
## Set default values when no optional flags are passed
#######################################################
: ${TEMP_DIR:="_tmp"}
: ${KCP_CFG_PATH:=.kcp/admin.kubeconfig}
: ${KCP_WORKSPACE:=my-org}
: ${KCP_VERSION:=0.9.0}
: ${KUBE_CFG:=$HOME/.kube/config}
: ${HOSTNAME_IP:="1.1.1.1"}