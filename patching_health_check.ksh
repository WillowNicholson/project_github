#!/usr/bin/ksh
#
#  Name        : patching_health_check.ksh
#  Author      : Willow Nicholson
#  Version     :
#  Date        :
#  Description : Some server checks to run before patching.  Writes to a logfile if there are any issues that require
#                investigating
#
#
#

log_function()
{
COMMAND="$*"

echo "Output of ${COMMAND} at $(date):"
${COMMAND} 2>&1

}

check_function()
{
typeset -i STATUS=0
typeset -i NO_LINES=0
typeset -i CAPACITY=0
typeset -i NODE_OFFLINE=0


# Check for any faults in the fault management system
NO_LINES=$(fmadm faulty|grep -i event | wc -l)
if [[ ${NO_LINES} -ne 0 ]]
then
        log_function fmadm faulty
        STATUS=${STATUS}+1
fi

# Check status of zpools
zpool status -vx |/usr/xpg4/bin/grep -q "all pools are healthy" ; POOLSTATUS=$?
if [[ ${POOLSTATUS} -ne 0 ]]
then
        zpool status -vx
        STATUS=${STATUS}+1
fi

# Check for offline SMF services
NO_LINES=$(svcs -vx | wc -l)
if [[ ${NO_LINES} -ne 0 ]]
then
        svcs -vx
        STATUS=${STATUS}+1
fi

# Capacity check on /var/sadm
CAPACITY=$(df -h /var/sadm |grep % | awk '{ print $5 }' |tr -d "%")
if [[ ${CAPACITY} -ge 95 ]]
then
        df -h /var/sadm
        STATUS=${STATUS}+1
fi

# Check that all zones are running
NO_LINES=$(zoneadm list -cv |awk 'NR>1' |awk '$0 !~ /running/' |wc -l)
if [[ ${NO_LINES} -ne 0 ]]
then
        zoneadm list -cv
        STATUS=${STATUS}+1
fi

# Check cluster nodes are online.  Ignore if not part of a SUN cluster
cluster status 2>&1 | /usr/xpg4/bin/grep -q "not found" ; NON_CLUSTER=$?
if [[ ${NON_CLUSTER} -ne 0 ]]
then
        NODE_OFFLINE=$(clnode status |grep -v "^$" |sed -n -e '/Node Name/,$p' |awk 'NR>2'| sed '/Online/d'|wc -l)
        if [[ ${NODE_OFFLINE} -ne 0 ]]
        then
                clnode status
                STATUS=${STATUS}+1
        fi
fi

# Make a copy of currently mounted filesystems
#mount > /var/tmp/mounts_`date +%Y%m%d%H%M%s`

return ${STATUS}
}

# Main script

export PATH=/usr/sbin:$PATH

LOGFILE=/tmp/patching_health_check.log

check_function >> ${LOGFILE} ; SUCCESS=$?

if [[ ${SUCCESS} -ne 0 ]]
then
        echo "There are " ${SUCCESS} "issues to address"
        echo "Please check " ${LOGFILE} "for details"
else
        echo "All checks were successful"
fi
