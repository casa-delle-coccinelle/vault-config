#!/bin/sh

source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
echo "## Dynamodb conf"

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-central-1}"
export AWS_DYNAMODB_TABLE

function dynamodb_enable_pitr() {
    aws dynamodb update-continuous-backups --table-name "${AWS_DYNAMODB_TABLE}" --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true
}

function main() {
    if [ "${AWS_DYNAMODB_TABLE}" != "" ]; then
        echo "Enabling point-in-time restore for dynamodb table ${AWS_DYNAMODB_TABLE}"
        dynamodb_enable_pitr
    else
        echo "No DynamoDB found"
    fi
}

main

