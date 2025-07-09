#!/usr/bin/env bash

# saner programming env: these switches turn some bugs into errors
set -o errexit -o pipefail -o noclobber -o nounset

# Script to generate deny rules for a specific ASN, e.g. Alibaba (AS45102).

ASN="${1?you must specify the ASN}"
if ! [ -f "$ASN.txt" ]; then
  whois -h whois.radb.net -- "-i origin $ASN" > "$ASN.txt"
fi
# Generate nginx deny block.
sed -nE 's/route:\s*([0-9]{1,3}(\.[0-9]{1,3}){3}\/[0-9]+).*/deny \1;/p' "$ASN.txt" | sort -u >| "$ASN.conf"
# Generate ipset list.
echo "# Apply with: ipset-update.sh -n badactors_net -f $ASN.ipset [-d]" >| "$ASN.ipset"
sed -nE "s/route:\s*([0-9]{1,3}(\.[0-9]{1,3}){3}\/[0-9]+).*/\1 # $ASN/p" "$ASN.txt" | sort -u >> "$ASN.ipset"
# awk '!seen[$0]++' "$ASN.ipset" >| "${ASN}_nodups.ipset"
