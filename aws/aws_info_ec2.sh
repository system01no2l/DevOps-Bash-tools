#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2024-11-22 14:20:14 +0400 (Fri, 22 Nov 2024)
#
#  https///github.com/HariSekhon/DevOps-Bash-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/HariSekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090,SC1091
. "$srcdir/lib/aws.sh"

# shellcheck disable=SC2034,SC2154
usage_description="
Lists AWS EC2 Instances resources deployed in the current AWS account

Written to be combined with aws_foreach_project.sh
"

# used by usage() in lib/utils.sh
# shellcheck disable=SC2034
usage_args="[<aws_profile>]"

help_usage "$@"

max_args 1 "$@"

check_bin aws

if [ $# -gt 0 ]; then
    project_id="$1"
    shift || :
    export CLOUDSDK_CORE_PROJECT="$project_id"
fi

# AWS Virtual Machines
cat <<EOF
# ============================================================================ #
#                   E C 2   V i r t u a l   M a c h i n e s
# ============================================================================ #

EOF

declare -A ami_map

timestamp "Getting all unique AMI IDs in use"
ami_ids="$(
    aws ec2 describe-instances \
        --query 'Reservations[*].Instances[*].ImageId' \
        --output text |
    sort -u
)"

while read -r ami_id; do
    [[ -z "$ami_id" ]] && continue

    timestamp "Resolving AMI ID: $ami_id"
    ami_name="$(
        aws ec2 describe-images \
            --image-ids "$ami_id" \
            --query 'Images[0].Name' \
            --output text
    )"
    if [[ "$ami_name" == "None" || -z "$ami_name" ]]; then
        timestamp "WARNING: AMI ID '$ami_id' failed to resolve to AMI Name"
    else
        timestamp "AMI ID '$ami_id' => '$ami_name'"
        ami_map["$ami_id"]="$ami_name"
    fi
done <<< "$ami_ids"

sed_script=''
for ami_id in "${!ami_map[@]}"; do
    ami_name="${ami_map[$ami_id]}"
    sed_script+="
    s/\"$ami_id\"/\"$ami_name\"/g;"
done

timestamp "Getting list of EC2 instances"
# shellcheck disable=SC2016
json="$(
    aws ec2 describe-instances \
        --query 'Reservations[*].Instances[*].{
                    "Name": Tags[?Key==`Name`].Value | [0],
                    "ID": InstanceId,
                    "State": State.Name,
                    "InstanceType": InstanceType,
                    "AMI": ImageId,
                    "Architecture": "Architecture",
                    "PublicDNS": publicDnsName,
                    "PrivateDNS": PrivateDnsName
                }' \
        --output json |
    jq_debug_pipe_dump
)"

timestamp "Generating CSV output with AMI images IDs resolved to names"
jq -r '
    .[][] |
    [ .ID, .Name, .State, .InstanceType, .AMI, .Architecture, .PrivateDNS, .PublicDNS ] |
    @csv
' <<< "$json" |
sed "$sed_script"