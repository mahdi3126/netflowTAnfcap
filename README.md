# NetFlow to Splunk Enterprise Security (ES) Pipeline

This guide describes how to collect, convert, and ingest NetFlow logs from a network device (e.g., FortiGate, MikroTik) into Splunk Enterprise Security, using a Linux-based NetFlow collector and a Splunk Heavy Forwarder. All steps are production-ready, tested, and work in a resource-efficient and CIM-compliant manner.

## Architecture Overview

```
[Network Device: MikroTik / FortiGate]
          │ (NetFlow v9 via UDP/2055)
          ▼
 [Linux Collector with nfcapd + nfdump]
          ▼
     [/var/log/netflow/parsed/*.json]
          ▼
 [Universal Forwarder] ➝ [Heavy Forwarder] ➝ [Indexer Cluster] ➝ [Splunk ES]
```

---

## 1. NetFlow Export Configuration (Example for FortiGate)

```bash
config system netflow
    set collector-ip <Linux-Collector-IP>
    set collector-port 2055
    set source-ip <local-interface-IP>
    set active-flow-timeout 1
    set inactive-flow-timeout 15
end
```

## 2. NetFlow Collector Setup (on Linux)

### Install nfdump:
```bash
sudo apt install nfdump
```

### Create a cronjob to persist nfcapd across reboots:

```cron
@reboot sudo /usr/bin/nfcapd -D -w /var/log/netflow -p 2055 -e -t 300
```

- Listens on UDP 2055
- Rotates flow files every 5 minutes
- Writes them as binary files into `/var/log/netflow/`

### File Permissions:
```bash
sudo chmod 755 /var/log/netflow
sudo chmod 755 /var/log/netflow/parsed
```

## 3. Conversion Script (nfdump ➝ JSON)

**Path:** `/usr/local/bin/netflow_convert.sh`

```bash
#!/bin/bash

SRC_DIR="/var/log/netflow"
DEST_DIR="/var/log/netflow/parsed"

# Create destination dir if not exists
[ ! -d "$DEST_DIR" ] && mkdir -p "$DEST_DIR"
chmod 755 "$SRC_DIR"
chmod 755 "$DEST_DIR"

for file in "$SRC_DIR"/nfcapd.*; do
    filename=$(basename "$file")
    [[ "$filename" == nfcapd.current* ]] && continue

    json_file="$DEST_DIR/${filename}.json"

    if [ ! -f "$json_file" ]; then
        /usr/bin/nfdump -r "$file" -o json > "$json_file"
        [ $? -eq 0 ] && rm -f "$file"
    fi
done
```

### Cron Job (run every 5 minutes):
```cron
*/5 * * * * /usr/local/bin/netflow_convert.sh >> /var/log/netflow/convert.log 2>&1
```

---

## 4. Cleanup Script (for parsed/ JSON files)

**Path:** `/usr/local/bin/cleanup_parsed_netflow.sh`
```bash
#!/bin/bash
find /var/log/netflow/parsed -type f -name "*.json" -mmin +30 -delete
```

### Cron Job:
```cron
*/10 * * * * /usr/local/bin/cleanup_parsed_netflow.sh >> /var/log/netflow/cleanup.log 2>&1
```

---

## 5. Splunk Forwarding (Universal Forwarder)

### `inputs.conf`:
```ini
[monitor:///var/log/netflow/parsed]
index = netflow
sourcetype = netflow_json
```

### `outputs.conf` (forward to HF):
```ini
[tcpout]
defaultGroup = hfs
[tcpout:hfs]
server = <HF-IP>:9997
```

---

## 6. Splunk Add-on (TA) for NetFlow Logs

Create a custom Splunk TA with the following structure:

```
SplunkNetflow-nfcap-TA/
├── default/
│   ├── props.conf
│   ├── transforms.conf
│   ├── eventtypes.conf
│   └── tags.conf
└── metadata/
    └── default.meta
```

### `props.conf`
```ini
[netflow_json]
KV_MODE = json
SHOULD_LINEMERGE = false
INDEXED_EXTRACTIONS = json
NO_BINARY_CHECK = true
TRUNCATE = 999999
TIME_PREFIX = "t_first":"
TIME_FORMAT = %Y-%m-%dT%H:%M:%S
TRANSFORMS-add_tags = add_netflow_tags
EVAL-tag = "netflow,flow,network"

# CIM field mappings
FIELDALIAS-src_ip = src4_addr AS src
FIELDALIAS-dest_ip = dst4_addr AS dest
FIELDALIAS-bytes_in = in_bytes AS bytes_in
FIELDALIAS-packets_in = in_packets AS packets_in
EVAL-protocol = case(proto=6, "tcp", proto=17, "udp", proto=1, "icmp", true(), "other")

```

### `transforms.conf`
```ini
[add_netflow_tags]
REGEX = .
FORMAT = tag::network=netflow tag::communication=flow tag::direction=unknown
DEST_KEY = MetaData:Tag
```

### `eventtypes.conf`
```ini
[netflow_event]
search = sourcetype=netflow_json
tags = netflow communication flow
```

### `tags.conf`
```ini
[eventtype=netflow_event]
netflow = enabled
communication = enabled
flow = enabled
```

### `metadata/default.meta`
```ini
[]
access = read : [ * ], write : [ admin ]
export = system
```

### Install TA on:
- ✅ Heavy Forwarder
- ✅ Search Head (e.g., Splunk ES)

Restart Splunk after deployment.

---

## 7. Verifying Ingestion & Tags

### Confirm events:
```spl
index=netflow sourcetype=netflow_json | head 5
```

### Confirm tags:
```spl
index=netflow sourcetype=netflow_json | stats count by tag
```

### Confirm eventtype:
```spl
eventtype=netflow_event | stats count by tag
```

---

## ✅ Result
You now have a complete, tag-compliant, efficient NetFlow pipeline into Splunk Enterprise Security. All data is CIM-ready, tagged, rotated, and managed properly on disk.
