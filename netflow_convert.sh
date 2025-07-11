#!/bin/bash

SRC_DIR="/var/log/netflow"
DEST_DIR="/var/log/netflow/parsed"

if [ ! -d "$DEST_DIR" ]; then
    mkdir -p "$DEST_DIR"
fi

chmod 755 "$SRC_DIR"
chmod 755 "$DEST_DIR"

for file in "$SRC_DIR"/nfcapd.*; do
    filename=$(basename "$file")

    if [[ "$filename" == nfcapd.current* ]]; then
        continue
    fi

    json_file="$DEST_DIR/${filename}.json"

    if [ ! -f "$json_file" ]; then
        /usr/bin/nfdump -r "$file" -o json > "$json_file"
        if [ $? -eq 0 ]; then
            rm -f "$file"
        fi
    fi
done