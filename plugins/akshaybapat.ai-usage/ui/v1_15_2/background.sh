#!/bin/sh
# Runs its arguments as one command on the efficiency cores, at idle priority.
# A short job on a performance core of a hybrid CPU can spike turbo thermals; E-cores keep it silent.
# The move is best effort: where the cores cannot be changed, the command still runs, at idle priority.
read -r cores 2>/dev/null </sys/devices/cpu_atom/cpus && taskset -pc "$cores" $$ >/dev/null 2>&1
exec nice -n 19 "$@"
