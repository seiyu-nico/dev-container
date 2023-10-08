#!/bin/sh

cat << EOF > /etc/dnsmasq.conf
address=/.local.challtech.dev/$HOST_IP

server=8.8.8.8
server=8.8.4.4
EOF

/bin/dnsmasq --no-daemon --log-queries --keep-in-foreground
