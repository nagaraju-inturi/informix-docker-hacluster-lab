docker stop cm1
docker stop cm2
docker stop sds
docker stop rss
docker stop hdr
docker stop primary
docker rm cm1
docker rm cm2
docker rm sds
docker rm rss
docker rm hdr
docker rm primary
cd ./context
docker build -t nagaraju/informix .
cd ../context_cm
docker build -t nagaraju/cm .
docker network rm informix_nw
