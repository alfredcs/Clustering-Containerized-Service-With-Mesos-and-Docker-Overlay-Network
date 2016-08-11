##Architecture design and tools development.
![alt tag] (https://github.com/alfredcs/Clustering-Containerized-Service-With-Mesos-and-Docker-Overlay-Network/blob/master/dcos-mesos-docker.png)


##Installation:
####Create a bootstrap node with centos 3.10.1 or newer kernel 
#####Install Docker on the boot strap node
        curl –fsSL https://test.docker.com/ | sh
####Download and run the DCOS installer
        cd ~/dcos;curl ~/dcos;https://downloads.dcos.io/dcos/EarlyAccess/dcos_generate_config.sh | bash
#####Start nginx on the bootstrap node:
        docker run -d -p 8088:80 -v $PWD/genconf/serve:/usr/share/nginx/html:ro nginx
#####Modify config.yml in /root/dcos/genconf
        bootstrap_url: http:///<bootstrap_public_ip>:8088
        cluster_name: '<cluster-name>'
        ip_detect_filename: /root/dcos/genconf/ip-detect
        master_discovery: static
        master_list:
        - 10.10.1.40 #1st mesos master IP
        - 10.10.1.41 #2nd mesos master IP 
        - 10.10.1.42 #3rd mesos master IP
        resolvers:
        - 10.10.1.4 # DNS IP
        ssh_port: 22
        ssh_user: centos #user account for remote ssh access
####Modify ip-detect in /root/dcos/genconf
        #!/usr/bin/env bash
        set -o nounset -o errexit
        export PATH=/usr/sbin:/usr/bin:$PATH
        echo $(ip addr show eth0 | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
####Create ssh_key, ip-detect and config.yml files
        dcos
        ├── dcos-genconf.14509fe1e7899f4395-3a2b7e03c45cd615da.tar
        ├── dcos_generate_config.sh
        ├── genconf
            ├── cluster_packages.json
            ├── config.yaml
            ├── ip-detect
            ├── serve
            │   ├── bootstrap
            │   │   ├── 3a2b7e03c45cd615da8dfb1b103943894652cd71.active.json
            │   │   └── 3a2b7e03c45cd615da8dfb1b103943894652cd71.bootstrap.tar.xz
            │   ├── bootstrap.latest
            │   ├── cluster-package-info.json
            │   ├── dcos_install.sh
            │   ├── dcos_install.sh.orig
            │   ├── fetch_packages.sh
            │   └── packages
            │       ├── dcos-config
            │       │   └── dcos-config--setup_e841d0b6a20d67d54a5ce10be7ba75a7ee747f99.tar.xz
            │       └── dcos-metadata
            │           └── dcos-metadata--setup_e841d0b6a20d67d54a5ce10be7ba75a7ee747f99.tar.xz
            ├── ssh_key
            └── state

#####Publish DCOS installation tool on the bootstrap node
        Download dcos_install.sh from  https://guthub.build.ge.com/212464633/Container-Orchestration-Using-Mesos-/dcos_install.sh and place in the bootstrap node as ~/dcos/genconf/serve/dcos_install.sh
        Restart docker : docker restart `docker ps | grep nginx|grep 8088| awk '{print $1}'`

####Login to the dcos bootstrap node and run the following cmd to stand up Meoss master cluster
      fab --hosts=dcos1,dcos2,dcos3 -u centos -i /root/keys/s_admin.pem exe:"curl http://<bootstrap-ip>:8088/dcos_install.sh |bash -s master
      where:
         dcos[1-3] are the master nodes defined on the config.yml.
####From the dcos bttostrap node run following cli to standup meoss agents
      fab --hosts=dcosa01,dcosa02,dcos03 -u centos -i /root/keys/s_admin.pem exe:"curl http://<bootstrap-ip>:8088/dcos_install.sh | sudo bash –s slave
      where:
          dcosa0[1-n] are the mesos slave nodes
####Fropm the same dcos bootstrap node run this cli to stand up the edge nodes (i.e. Customer  facing load balancer)
      fab --hosts=dcosp01,dcosp02,dcosp03 -u centos -i /root/keys/s_admin.pem exe:"curl http://<bootstrap-ip>:8088/dcos_install.sh | bash –s slave_public
      where: 
          dcosp0[1-n] are the mesos public slave nodes to be used for marathon-LB

####From the dcos bttostrap node. enable Docker registry
      docker run -d -p 5000:5000 --restart=always --name dtr -v /opt/nfs1:/auth -e "REGISTRY_AUTH=htpasswd"  -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd   -e REGISTRY_HTTP_TLS_CERTIFICATE=/auth/dtr.domain.crt.pem -e REGISTRY_HTTP_TLS_KEY=/auth/dtr.key.pem -v /var/lib/registry:/tmp/registry registry
      where:
	  dtr.domain.crt.pem is the combination of signed server certificate and the signing certificate normally an intermnmediate CA 
          /auth/htpasswd contains the htpasswd hash used for registry authentication

      Upload docker image to the registry including mlb, marathon load balancer.

#### Deploy edge LB using Marathon using the suggest mlb.json 
       curl -X POST http://10.138.64.90:8080/v2/apps -d @mlb.json -H "Content-type:application/json"
