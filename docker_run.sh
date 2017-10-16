docker network create --subnet=172.18.0.0/16 informix_nw
docker run --net=informix_nw --ip=172.18.0.10 -d -h primary --name primary nagaraju/informix 
sleep 10
docker exec -it primary ./boot.sh --getInfo
docker exec -it primary /opt/ibm/boot.sh --shell onstat -

docker run --net=informix_nw --ip=172.18.0.11 -d -h hdr --name hdr nagaraju/informix --initSec hdr 
docker logs hdr
docker exec primary /opt/ibm/boot.sh --addHost 172.18.0.11 hdr
docker exec hdr /opt/ibm/boot.sh --initHDR primary 172.18.0.10
sleep 10
docker exec -it hdr /opt/ibm/boot.sh --shell onstat -

docker run --net informix_nw --ip 172.18.0.12 -d -h rss --name rss nagaraju/informix --initSec rss 
docker logs rss
docker exec primary /opt/ibm/boot.sh --addHost 172.18.0.12 rss
docker exec hdr /opt/ibm/boot.sh --addHost 172.18.0.12 rss
docker exec rss /opt/ibm/boot.sh --initRSS primary 172.18.0.10
sleep 10
docker exec -it rss /opt/ibm/boot.sh --shell onstat -

docker exec primary /opt/ibm/boot.sh --setSDSPrim
docker run --net informix_nw --ip 172.18.0.13  -d --volumes-from primary -h sds --name sds nagaraju/informix --initSec sds 
docker logs sds
docker exec primary /opt/ibm/boot.sh --addHost 172.18.0.13 sds
docker exec hdr /opt/ibm/boot.sh --addHost 172.18.0.13 sds
docker exec rss /opt/ibm/boot.sh --addHost 172.18.0.13 sds
docker exec sds /opt/ibm/boot.sh --initSDS primary 172.18.0.10
sleep 10
docker exec -it sds /opt/ibm/boot.sh --shell onstat -


docker run --net informix_nw --ip 172.18.0.14 -d -h cm1 --name cm1 nagaraju/cm  --initCM primary 172.18.0.10 cm1 1
docker logs cm1 #Get ip address
#add cm ip address to primary server as a trusted host
docker exec primary /opt/ibm/boot.sh --addHost 172.18.0.14
docker exec primary /opt/ibm/boot.sh --addHost cm1
#docker exec -it  cm1 ./boot_cm.sh --initCM primary 172.18.0.10 cm1 1
docker exec -it cm1 ./boot_cm.sh --status

docker run --net informix_nw --ip 172.18.0.15 -d -h cm2 --name cm2 nagaraju/cm  primary 172.18.0.10 cm2 2
docker logs cm2 #Get ip address
#add cm ip address to primary server as a trusted host
docker exec primary /opt/ibm/boot.sh --addHost 172.18.0.15
docker exec primary /opt/ibm/boot.sh --addHost cm2
docker exec -it  cm2 ./boot_cm.sh --initCM primary 172.18.0.10 cm2 2
docker exec -it cm2 ./boot_cm.sh --status
sleep 2
docker exec -it primary /opt/ibm/boot.sh --shell onstat -g cluster
docker exec -it primary /opt/ibm/boot.sh --shell onstat -g cmsm
