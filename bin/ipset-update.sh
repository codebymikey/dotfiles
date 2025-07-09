#!/usr/bin/env bash

# saner programming env: these switches turn some bugs into errors
set -o errexit -o pipefail -o noclobber -o nounset

# https://gist.github.com/toke/0474b80308de68e13d8c6b21156b5fec

# Parse arguments
PURGE=false
CREATE_SET=false
DRY_RUN=false
IPSET_NAME=""
IP_LIST_FILE=""

TMP_FILES_TO_CLEANUP=()
function cleanup() {
  rm -rf "${TMP_FILES_TO_CLEANUP[@]}"
}
trap cleanup 0

# Usage function
usage() {
    echo >&2 "Usage: $0 -n IPSET_NAME -f IP_LIST_FILE [-c] [-p] [-d]"
    echo >&2 "  -n IPSET_NAME      Name of the ipset to manage"
    echo >&2 "  -f IP_LIST_FILE    Path to the file containing a list of IPs to add"
    echo >&2 "  -c                 Create the ipset if it doesn't already exist"
    echo >&2 "  -p                 Purge the ipset before adding new IPs"
    echo >&2 "  -d                 Dry run"
    exit 1
}

run_command() {
  if $DRY_RUN; then
    echo >&2 "> $*"
  else
    "$@"
  fi
}

while getopts "n:f:c:p:d" opt; do
    case "$opt" in
        n) IPSET_NAME="$OPTARG" ;;
        f) IP_LIST_FILE="$OPTARG" ;;
        c) CREATE_SET=true ;;
        p) PURGE=true ;;
        d) DRY_RUN=true ;;
        *) usage ;;
    esac
done

# Validate arguments
if [[ -z "$IPSET_NAME" || -z "$IP_LIST_FILE" ]]; then
    usage
fi

if [[ ! -f "$IP_LIST_FILE" ]]; then
    echo >&2 "Error: File '$IP_LIST_FILE' not found."
    exit 1
fi

# Check if ipset exists by checking ipset save output
if $CREATE_SET && ! ipset list -name -terse | grep -Fxq "$IPSET_NAME"; then
    echo >&2 "Creating ipset '$IPSET_NAME'..."
    run_command ipset create "$IPSET_NAME" hash:net
fi

# Purge ipset if requested
if $PURGE; then
    echo >&2 "Purging ipset '$IPSET_NAME'..."
    run_command ipset flush "$IPSET_NAME"
fi

# Add IPs to ipset
echo >&2 "Adding IPs to ipset '$IPSET_NAME' from file '$IP_LIST_FILE'..."

TMP_IPLIST=$(mktemp)

TMP_FILES_TO_CLEANUP+=( "$TMP_IPLIST" )

# Generate ipset rules.
# https://ipset.netfilter.org/ipset.man.html
awk -F '[ #]+' "
# Match IPv4 addresses and CIDRs
/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?/ ||
# Match IPv6 addresses and CIDRs
/^[0-9a-fA-F:]+(\/[0-9]+)?( |\$)/ {
  printf \"add $IPSET_NAME \" \$1 \" -exist\"
  if (\$2) {
    printf \" comment \042\"
    { for (i = 2; i <= NF-1; i++) { printf \"%s \", \$i }; printf \$NF }
    printf \"\042\"
  }
  printf \"\n\"
}" "$IP_LIST_FILE" >| "$TMP_IPLIST"

if $DRY_RUN; then
  # Print the commands.
  echo >&2 "> ipset restore -file $TMP_IPLIST"
  >&2 cat "$TMP_IPLIST"
else
  # Add the IPs to the list. Existing elements are not erased.
  run_command ipset restore -file "$TMP_IPLIST"
fi
