#!/bin/bash

# TARGET has to be a fqdn
TARGET=${1:?No target given}

while true; do
  ping -c 1 $TARGET >/dev/null 2>&1 && \
  ssh -o "PasswordAuthentication no" \
      -o "StrictHostKeyChecking no" \
      -q -t $TARGET watch -n 1 cat /proc/mdstat
done

