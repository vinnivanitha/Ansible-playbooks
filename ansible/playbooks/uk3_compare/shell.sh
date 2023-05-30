#!/bin/bash
CURRENT=$(df | tail --lines=+2 | sed s/%//g | awk '{ if($5 > 0) print $0;}' | awk '{ print $5 }')
THRESHOLD=40

if [ "$CURRENT" -gt "$THRESHOLD" ] ; then
    mail -s 'Disk Space Alert' vinnivanitha99@gmail.com << EOF
Your root partition remaining free space is critically low. Used: $CURRENT%
EOF
fi
