#!/bin/sh 

export INFORMIXDIR=/opt/ibm/informix
export PATH=":${INFORMIXDIR}/bin:.:${PATH}"
#export INFORMIXSERVER=informix
export INFORMIXSQLHOSTS="${INFORMIXDIR}/etc/sqlhosts"
export ONCONFIG=onconfig
export LD_LIBRARY_PATH="${INFORMIXDIR}/lib:${INFORMIXDIR}/lib/esql:${LD_LIBRARY_PATH}"
export DATA_ROOT="${DATA_ROOT:-/opt/ibm/data/}"

SLEEP_TIME=1  # Seconds
MAX_SLEEP=240 # Seconds

echoThis()
{
  timestamp=`date --rfc-3339=seconds`
  echo "[$timestamp] $@"
  echo "[$timestamp] $@" >> /tmp/informix.log
}

function clean_up {

    # Perform program exit housekeeping
    echo "${sn} stop: Shutting down informix Instance ..."
    su informix -c "${INFORMIXDIR}/bin/onmode -kuy"
    echo "${sn} stop: done"
    
    exit 0
}

trap clean_up SIGHUP SIGINT SIGTERM


if [ -f /etc/profile.d/informix.sh ]; then
    . /etc/profile.d/informix.sh
fi
local_ip=`ifconfig eth0 |awk '{if(NR==2)print $2}'`

preStart()
{
setStr="
#!/bin/bash

export INFORMIXDIR=/opt/ibm/informix
export PATH="${INFORMIXDIR}/bin:\${PATH}"
export INFORMIXSERVER=\"${HA_ALIAS}\"
export HA_ALIAS=\"${HA_ALIAS}\"
export INFORMIXSQLHOSTS=\"${INFORMIXSQLHOSTS}\"
export ONCONFIG=\"onconfig\"
export LD_LIBRARY_PATH="${INFORMIXDIR}/lib:${INFORMIXDIR}/lib/esql:${LD_LIBRARY_PATH}"
"
   echo "${setStr}" > /etc/profile.d/informix.sh
   . /etc/profile.d/informix.sh
   chown informix:informix /etc/profile.d/informix.sh
   chmod 644 /etc/profile.d/informix.sh
   #echo "informix onsoctcp $local_ip 60000" >${INFORMIXDIR}/etc/sqlhosts
   echo "$HA_ALIAS onsoctcp $local_ip 60000" >${INFORMIXDIR}/etc/sqlhosts
   chown informix:informix ${INFORMIXDIR}/etc/sqlhosts
   touch ${INFORMIXDIR}/etc/authfile.$HA_ALIAS
   #echo "$local_ip" >${INFORMIXDIR}/etc/authfile.$HA_ALIAS
   chown root:informix ${INFORMIXDIR}/etc/authfile.$HA_ALIAS
   chmod 660 ${INFORMIXDIR}/etc/authfile.$HA_ALIAS
   sed -i "s/DBSERVERNAME.*/DBSERVERNAME $HA_ALIAS /g" ${INFORMIXDIR}/etc/$ONCONFIG
   sed -i "s/HA_ALIAS.*/HA_ALIAS $HA_ALIAS/g " ${INFORMIXDIR}/etc/$ONCONFIG
   sed -i "s/REMOTE_SERVER_CFG.*/REMOTE_SERVER_CFG authfile.$HA_ALIAS/g " ${INFORMIXDIR}/etc/$ONCONFIG
   sed -i "s/ROOTPATH.*/ROOTPATH \/opt\/ibm\/data\/dbspaces\/rootdbs /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/MSGPATH.*/MSGPATH \/opt\/ibm\/data\/log\/$HA_ALIAS.log /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/FULL_DISK_INIT.*/FULL_DISK_INIT 1 /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/LOG_INDEX_BUILDS.*/LOG_INDEX_BUILDS 1 /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/TEMPTAB_NOLOG.*/TEMPTAB_NOLOG 1 /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/ENABLE_SNAPSHOT_COPY.*/ENABLE_SNAPSHOT_COPY 1 /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/CDR_AUTO_DISCOVER.*/CDR_AUTO_DISCOVER 1 /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/LTAPEDEV.*/LTAPEDEV \/dev\/null /g" /opt/ibm/informix//etc/onconfig
   #sed -i "s/VPCLASS cpu/VPCLASS cpu=2/g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/SDS_PAGING.*/SDS_PAGING \/opt\/ibm\/data\/ifx_sds_paging1_$HA_ALIAS,\/opt\/ibm\/data\/ifx_sds_paging2_$HA_ALIAS /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/SDS_TEMPDBS.*/SDS_TEMPDBS ifx_sds_tmpdbs_$HA_ALIAS,\/opt\/ibm\/data\/ifx_sds_tmpdbs_$HA_ALIAS,4,0,50M /g" ${INFORMIXDIR}/etc/onconfig

   chown informix:informix ${INFORMIXDIR}/etc/onconfig
   mkdir -p ${DATA_ROOT}/dbspaces
   touch ${DATA_ROOT}/dbspaces/rootdbs
   chown -R informix:informix ${DATA_ROOT}
   chmod 660 ${DATA_ROOT}/dbspaces/rootdbs
   su informix -c "mkdir -p ${DATA_ROOT}/log"
   su informix -c "touch ${DATA_ROOT}/log/$HA_ALIAS.log"
}

getSQLHostFromPrimary()
{
   su informix -c "${INFORMIXDIR}/bin/dbaccess sysmaster@$1 - <<EOF
   unload to ${INFORMIXDIR}/etc/sqlhosts DELIMITER ' ' select dbsvrnm, nettype, hostname, svcname from syssqlhosts where nettype=\"onsoctcp\";
EOF"

 awk --re-interval '/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/{print $3}'  ${INFORMIXDIR}/etc/sqlhosts |xargs -iip echo ip >> ${INFORMIXDIR}/etc/authfile.$HA_ALIAS
 awk '{print $1}'  ${INFORMIXDIR}/etc/sqlhosts |xargs -iip echo ip >> ${INFORMIXDIR}/etc/authfile.$HA_ALIAS
 awk '{print $1}'  ${INFORMIXDIR}/etc/sqlhosts |xargs -iip echo ip.informix_nw >> ${INFORMIXDIR}/etc/authfile.$HA_ALIAS

}

# Wait for local server to be On-Line.
wait4online()
{
retry=0
wait4online_status=0
while [ 1 ]
    do
    sleep 10
    onstat -
    server_state=$?

    #Offline mode
    if [ $server_state -eq 255 ]
    then
        wait4online_status=1
        printf "ERROR: wait4online() Server is in Offline mode\n" 
        break
    fi

    # Quiescent mode check.
    # Note: at secondary server, exit code 2 used for Quiscent mode as well.
    if [ $server_state -eq 1 ] || [ $server_state -eq 2 ]
    then
        su -p informix -c 'onmode -m; exit $?'
        onmode_rc=$?
        printf "CMD: onmode -m, exit code $onmode_rc \n" 
        if [  $server_state -ne 2 ]
        then
            printf "INFO: wait4online() Server state changed from Quiescent to On-Line mode\n" 
        fi
    fi
    #Check if sqlexec connectivity is enabled or not.
    onstat -g ntd|grep sqlexec|grep yes
    exit_status=$?
    if [ $exit_status -eq 0 ]
    then
        su informix -c "${INFORMIXDIR}/bin/dbaccess sysadmin - <<EOF
EOF"
        rc=$?
        if [ $? -eq 0 ]
        then
           wait4online_status=0
           break
        fi
    fi
    retry=$(expr $retry + 1)
    if [ $retry -eq 120 ]
    then
       wait4online_status=1
       printf "ERROR: wait4online() Timed-out waiting for server to allow client connections\n" 
       break
    fi
done
}


echo $1
case "$1" in
    '--start')
        if [ `${INFORMIXDIR}/bin/onstat 2>&- | grep -c On-Line` -ne 1 ]; then
            if [ ! -f ${DATA_ROOT}/dbspaces/rootdbs ]; then
               HA_ALIAS=$2
               if [ "a$HA_ALIAS" = "a" ]; then
                   HA_ALIAS="informix"
               fi
               #HA_ALIAS=ha_`date +"%s"`
               preStart
               echo "$local_ip" >${INFORMIXDIR}/etc/authfile.$HA_ALIAS
               echo "$HA_ALIAS" >>${INFORMIXDIR}/etc/authfile.$HA_ALIAS
               echo "$HA_ALIAS.informix_nw" >>${INFORMIXDIR}/etc/authfile.$HA_ALIAS
               su informix -c "oninit -ivy" && tail -f  ${DATA_ROOT}/log/$HA_ALIAS.log
            else
                echo "${sn} start: Starting informix Instance ..."
                su informix -c "${INFORMIXDIR}/bin/oninit -vy" && tail -f  ${DATA_ROOT}/log/$HA_ALIAS.log
            fi
            echo "${sn} start: done"
            /bin/bash
        fi
        ;;
    '--getInfo')
        HA_ALIAS=`grep $local_ip $INFORMIXSQLHOSTS|awk '{print $1}'`
        echo "${sn} Local container ip address=$local_ip, server name=$HA_ALIAS"
        ;;
    '--setSDSPrim')
        if [ `${INFORMIXDIR}/bin/onstat 2>&- | grep -c On-Line` -ne 1 ]; then
            echo "Error: Server isn't On-Line"
            exit 1
        fi
        HA_ALIAS=`grep $local_ip $INFORMIXSQLHOSTS|awk '{print $1}'`
        su informix -c "${INFORMIXDIR}/bin/onmode -d set SDS primary $HA_ALIAS" 
        ;;
    '--initSec')
        if [ `${INFORMIXDIR}/bin/onstat 2>&- | grep -c On-Line` -ne 1 ]; then
	    if [ -e /etc/profile.d/informix.sh ]; then
                echo "${sn} start: Starting informix in fast recovery mode ..."
                su informix -c "${INFORMIXDIR}/bin/oninit -vy" && tail -f  ${DATA_ROOT}/log/$HA_ALIAS.log
		exit 0
	    fi
            HA_ALIAS=$2
            if [ "a$HA_ALIAS" = "a" ]; then
               echo "Usage: ${sn} --initSec <secondary name>}"
               exit 1
            fi
            preStart
            HA_ALIAS=`grep $local_ip $INFORMIXSQLHOSTS|awk '{print $1}'`
            echo "${sn} Local container ip address=$local_ip, server name=$HA_ALIAS" && tail -f  /dev/null
        fi
        exit 1
        ;;
    '--initHDR')
        primary_db=$2
        primary_ip=$3
        HA_ALIAS=`grep $local_ip $INFORMIXSQLHOSTS|awk '{print $1}'`
        if [ "a$HA_ALIAS" = "a" ]; then
            echo "Error: --initSec was not called"
            exit 1
        fi
        if [[ "a$HA_ALIAS" = "a" || "a$primary_ip" = "a" || "a$primary_db" = "a" ]]; then
            echo "Usage: ${sn} --initHDR <primary name><ip addr>}"
            exit 1
        fi
        if [ `${INFORMIXDIR}/bin/onstat 2>&- | grep -c On-Line` -ne 1 ]; then
            echo "$primary_db onsoctcp $primary_ip 60000" >>${INFORMIXDIR}/etc/sqlhosts
            #echo "$primary_db" >>${INFORMIXDIR}/etc/authfile.$HA_ALIAS
            getSQLHostFromPrimary $primary_db
            #su informix -c "ifxclone -S $primary_db -I $primary_ip -P 60000 -t $HA_ALIAS -i $local_ip -p 60000 -L -T -d HDR --autoconf"
            su informix -c "ifxclone -S $primary_db -I $primary_ip -P 60000 -t $HA_ALIAS -i $local_ip -p 60000 -L -T -d HDR "
            sleep  5
            wait4online
            su informix -c "${INFORMIXDIR}/bin/dbaccess sysadmin@$primary_db - <<EOF
             EXECUTE FUNCTION task(\"ha rss delete\",\"$HA_ALIAS\");
EOF"
            onstat -m
            echo "${sn} start: done"
            /bin/bash
        fi
        ;;
    '--initRSS')
        primary_db=$2
        primary_ip=$3
        HA_ALIAS=`grep $local_ip $INFORMIXSQLHOSTS|awk '{print $1}'`
        if [ "a$HA_ALIAS" = "a" ]; then
            echo "Error: --initSec was not called"
            exit 1
        fi
        if [[ "a$HA_ALIAS" = "a" || "a$primary_ip" = "a" || "a$primary_db" = "a" ]]; then
            echo "Usage: ${sn} --initRSS <primary name><ip addr>}"
            exit 1
        fi
        if [ `${INFORMIXDIR}/bin/onstat 2>&- | grep -c On-Line` -ne 1 ]; then
            echo "$primary_db onsoctcp $primary_ip 60000" >>${INFORMIXDIR}/etc/sqlhosts
            #echo "$primary_db" >>${INFORMIXDIR}/etc/authfile.$HA_ALIAS
            getSQLHostFromPrimary $primary_db
            #su informix -c "ifxclone -S $primary_db -I $primary_ip -P 60000 -t $HA_ALIAS -i $local_ip -p 60000 -L -T -d RSS --autoconf"
            su informix -c "ifxclone -S $primary_db -I $primary_ip -P 60000 -t $HA_ALIAS -i $local_ip -p 60000 -L -T -d RSS "
            sleep  5
            wait4online
            onstat -m
            echo "${sn} start: done"
            /bin/bash
        fi
        ;;
    '--initSDS')
        primary_db=$2
        primary_ip=$3
        HA_ALIAS=`grep $local_ip $INFORMIXSQLHOSTS|awk '{print $1}'`
        if [ "a$HA_ALIAS" = "a" ]; then
            echo "Error: --initSec was not called"
            exit 1
        fi
        if [[ "a$HA_ALIAS" = "a" || "a$primary_ip" = "a" || "a$primary_db" = "a" ]]; then
            echo "Usage: ${sn} --initSDS <primary name><ip addr>}"
            exit 1
        fi
        if [ `${INFORMIXDIR}/bin/onstat 2>&- | grep -c On-Line` -ne 1 ]; then
            sed -i "s/SDS_ENABLE.*/SDS_ENABLE 1 /g" ${INFORMIXDIR}/etc/onconfig
            echo "$primary_db onsoctcp $primary_ip 60000" >>${INFORMIXDIR}/etc/sqlhosts
            #echo "$primary_db" >>${INFORMIXDIR}/etc/authfile.$HA_ALIAS
            getSQLHostFromPrimary $primary_db
            #su informix -c "ifxclone -S $primary_db -I $primary_ip -P 60000 -t $HA_ALIAS -i $local_ip -p 60000 -L -T -d SDS --autoconf"
            su informix -c "ifxclone -S $primary_db -I $primary_ip -P 60000 -t $HA_ALIAS -i $local_ip -p 60000 -L -T -d SDS "
            sleep  5
            wait4online
            onstat -m
            echo "${sn} start: done"
            /bin/bash
        fi
        ;;
    '--stop')
        if [ `$INFORMIXDIR/bin/onstat 2>&- | grep -c On-Line` -eq 1 ]; then
            echo "${sn} stop: Shutting down informix Instance ..."
            su informix -c "${INFORMIXDIR}/bin/onmode -kuy"
            echo "${sn} stop: done"
        fi
        ;;

    '--status')
        s="down"
        if [ `${INFORMIXDIR}/bin/onstat 2>&- | grep -c On-Line` -eq 1 ]; then
            s="up"
        fi
        echo "${sn} status: informix Instance is ${s}"
        ;;

    '--addHost')
         host2add=$2
         secondary=$3
         if [ "a$host2add" != "a" ]; then
             onstat -
             server_state=$?
             if [ $server_state -eq 255 ]; then
                echo "${sn} status: informix Instance isn't online"
                exit 1
             fi

             retry=0
             while [ 1 ]
             do
	       if ! [[ "$host2add" =~ ^[0-9].* ]]; then
                   su informix -c "${INFORMIXDIR}/bin/dbaccess sysadmin - <<EOF
                   EXECUTE FUNCTION task(\"cdr add trustedhost\",\"$host2add.informix_nw\");
EOF"
               fi
               su informix -c "${INFORMIXDIR}/bin/dbaccess sysadmin - <<EOF
               EXECUTE FUNCTION task(\"cdr add trustedhost\",\"$host2add\");
EOF"
               if [ $? -eq 0 ]
               then
                  break
               fi
               retry=$(expr $retry + 1)
               if [ $retry -eq 10 ]
               then
                  break
               fi
               sleep 5
             done
         fi
         if [[ "a$host2add" != "a" && "a$secondary" != "a" ]]; then
             su informix -c "${INFORMIXDIR}/bin/dbaccess sysadmin - <<EOF
             EXECUTE FUNCTION task(\"cdr add trustedhost\",\"$secondary\");
             EXECUTE FUNCTION task(\"cdr add trustedhost\",\"$secondary.informix_nw\");
EOF"
             grep "^$secondary" ${INFORMIXDIR}/etc/sqlhosts
             if [ $? -eq 1 ]; then
                 echo "$secondary onsoctcp $host2add 60000" >>${INFORMIXDIR}/etc/sqlhosts
             fi
         fi
        ;;
    '--shell')
        /bin/bash -c "$2 $3 $4 $5 $6"
        ;;
    *)
        echo "Usage: ${sn} {--start|--stop|--status|--addHost <secondary serv> <ip addr>|--getInfo|--initHDR <primary name> <primary ip addr>[<secondary name>]}"
        ;;
esac

exit 0
