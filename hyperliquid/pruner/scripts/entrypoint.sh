#!/bin/bash
set -e

# Create cron.d file: env var + daily prune at 03:00 UTC
# cron.d format: minute hour day month weekday user command
RETENTION="${PRUNE_RETENTION_HOURS:-48}"
cat > /etc/cron.d/prune << EOF
PRUNE_RETENTION_HOURS=${RETENTION}
0 3 * * * root /bin/bash -c '/home/hluser/scripts/prune.sh > /proc/1/fd/1 2>&1'
EOF

exec /usr/sbin/cron -f -L 15
