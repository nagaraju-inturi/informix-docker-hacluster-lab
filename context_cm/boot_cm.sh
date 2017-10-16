#!/bin/sh 

export INFORMIXDIR=/opt/ibm/informix
export PATH=":${INFORMIXDIR}/bin:.:${PATH}"
export INFORMIXSQLHOSTS="${INFORMIXDIR}/etc/sqlhosts"
export LD_LIBRARY_PATH="${INFORMIXDIR}/lib:${INFORMIXDIR}/lib/esql:${LD_LIBRARY_PATH}"

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
    echo "${sn} stop: Shutting down CM Instance ..."
    su informix -c "${INFORMIXDIR}/bin/oncmsm -k $CM_NAME"
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
export INFORMIXSERVER=\"${PRIMARY}\"
export INFORMIXSQLHOSTS=\"${INFORMIXSQLHOSTS}\"
export LD_LIBRARY_PATH="${INFORMIXDIR}/lib:${INFORMIXDIR}/lib/esql:${LD_LIBRARY_PATH}"
export CM_NAME=\"${CM_NAME}\"
"
   echo "${setStr}" > /etc/profile.d/informix.sh
   . /etc/profile.d/informix.sh
   chown informix:informix /etc/profile.d/informix.sh
   chmod 644 /etc/profile.d/informix.sh
   #echo "oltp onsoctcp $local_ip 60000" >${INFORMIXDIR}/etc/sqlhosts
   #echo "report onsoctcp $local_ip 60001" >>${INFORMIXDIR}/etc/sqlhosts
   echo "$PRIMARY onsoctcp $PRIMARY_IP 60000" >>${INFORMIXDIR}/etc/sqlhosts
   chown informix:informix ${INFORMIXDIR}/etc/sqlhosts

   su informix -c "${INFORMIXDIR}/bin/dbaccess sysmaster - <<EOF
   unload to ${INFORMIXDIR}/etc/sqlhosts DELIMITER ' ' select dbsvrnm, nettype, hostname, svcname from syssqlhosts where nettype=\"onsoctcp\";
EOF"
   SERVERVS=`awk '{ print $1 }' ORS=',' ${INFORMIXDIR}/etc/sqlhosts`
   SERVERVS_2=${SERVERVS::-1}
   echo "oltp onsoctcp $local_ip 60000" >>${INFORMIXDIR}/etc/sqlhosts
   echo "report onsoctcp $local_ip 60001" >>${INFORMIXDIR}/etc/sqlhosts

   sed -i "s/NAME.*/NAME  $CM_NAME/g" ${INFORMIXDIR}/etc/cmsm.cfg
   sed -i "s/.*INFORMIXSERVER.*/  INFORMIXSERVER  $SERVERVS_2/g" ${INFORMIXDIR}/etc/cmsm.cfg
   sed -i "s/.*FOC.*/  FOC ORDER=SDS,HDR,RSS PRIORITY=$PRIORITY/g" ${INFORMIXDIR}/etc/cmsm.cfg

}

echo $1
case "$1" in
    '--start')
        su informix -c "${INFORMIXDIR}/bin/oncmsm -c ${INFORMIXDIR}/etc/cmsm.cfg" 
        sleep 5
        echo "${sn} start: done"
        /bin/bash
        ;;
    '--initIP')
	if [ -e /etc/profile.d/informix.sh ]; then
            su informix -c "${INFORMIXDIR}/bin/oncmsm -c ${INFORMIXDIR}/etc/cmsm.cfg"  && tail -f /dev/null
	     exit 0
	else
            echo "${sn} Local container ip address=$local_ip" && tail -f  /dev/null
	fi
        ;;
    '--getInfo')
        echo "${sn} Local container ip address=$local_ip"
        ;;
    '--initCM')
	    if [ -e /etc/profile.d/informix.sh ]; then
                su informix -c "${INFORMIXDIR}/bin/oncmsm -c ${INFORMIXDIR}/etc/cmsm.cfg"  && tail -f /dev/null
                exit 0
            fi
            PRIMARY=$2
            PRIMARY_IP=$3
            CM_NAME=$4
            PRIORITY=$5
            if [ "a$CM_NAME" = "a" ]; then
                CM_NAME="cm1"
             fi
            if [ "a$PRIORITY" = "a" ]; then
                PRIORITY="1"
             fi
            if [ "a$PRIMARY" = "a" ]; then
               echo "Usage: ${sn} --initCM <primary name> <primary ip> [<cm name>] [<priority>]}"
               exit 1
            fi
            if [ "a$PRIMARY_IP" = "a" ]; then
               echo "Usage: ${sn} --initCM <primary name> <primary ip> [<cm name>] [<priority>]}"
               exit 1
            fi
            preStart
            echo "${sn} Local container ip address=$local_ip"  
            su informix -c "${INFORMIXDIR}/bin/oncmsm -c ${INFORMIXDIR}/etc/cmsm.cfg"  && tail -f /dev/null
        exit 0
        ;;
    '--stop')
            echo "${sn} stop: Shutting down CM ..."
            su informix -c "${INFORMIXDIR}/bin/oncmsm -k $CM_NAME"
            echo "${sn} stop: done"
        ;;

    '--status')
        s="down"
        ps -ef|grep oncmsm|grep -v grep
        if [ $? -eq 0 ]; then
           s="up"
        fi
        echo "${sn} status: CM $CM_NAME Instance is ${s}"
        ;;

    '--addHost')
         host2add=$2
         serv2add=$3
         if [[ "a$host2add" != "a" && "a$serv2add" != "a" ]]; then
             echo "$serv2add onsoctcp $host2add 60000" >>${INFORMIXDIR}/etc/sqlhosts
         fi
        ;;
    '--shell')
        /bin/bash -c "$2 $3 $4 $5 $6"
        ;;
    *)
        echo "Usage: ${sn} {--start|--stop|--status|--addHost <server ip><server name>|--getInfo|--initCM <primary name> <primary ip addr> [<cm name>]}"
        ;;
esac

exit 0
