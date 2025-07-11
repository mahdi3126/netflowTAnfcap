#!/bin/bash

# This script deletes JSON files in the parsed NetFlow directory older than 30 minutes
# to prevent disk space issues after Splunk ingests the data.

PARSED_DIR="/var/log/netflow/parsed"

# Delete JSON files older than 30 minutes
find "$PARSED_DIR" -type f -name "*.json" -mmin +30 -delete