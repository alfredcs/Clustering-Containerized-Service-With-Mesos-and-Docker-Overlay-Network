#!/bin/bash
#
# BASH script to install DC/OS on a node
#
# Usage:
#
#   dcos_install.sh <role>...
#
#
# Metadata:
#   dcos image commit: 14509fe1e7899f439527fb39867194c7a425c771
#   generation date: 2016-06-30 23:16:15.826970
#
# TODO(cmaloney): Copyright + License string here

set -o errexit -o nounset -o pipefail

declare -i OVERALL_RC=0
declare -i PREFLIGHT_ONLY=0
declare -i DISABLE_PREFLIGHT=0
declare -i SYSTEMCTL_NO_BLOCK=0

declare ROLES=""
declare RED=""
declare BOLD=""
declare NORMAL=""

# Check if this is a terminal, and if colors are supported, set some basic
# colors for outputs
if [ -t 1 ]; then
    colors_supported=$(tput colors)
    if [[ $colors_supported -ge 8 ]]; then
        RED='\e[1;31m'
        BOLD='\e[1m'
        NORMAL='\e[0m'
    fi
fi

# Setup getopt argument parser
ARGS=$(getopt -o dph --long "disable-preflight,preflight-only,help,no-block-dcos-setup" -n "$(basename "$0")" -- "$@")

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

function setup_directories() {
    echo -e "Creating directories under /etc/mesosphere"
    mkdir -p /etc/mesosphere/roles
    mkdir -p /etc/mesosphere/setup-flags
}

function setup_dcos_roles() {
    # Set DC/OS roles
    for role in $ROLES
    do
        echo "Creating role file for ${role}"
        touch "/etc/mesosphere/roles/$role"
    done
}

# Set DC/OS machine configuration
function configure_dcos() {
echo -e 'Configuring DC/OS'
mkdir -p `dirname /etc/mesosphere/setup-flags/repository-url`
cat <<'EOF' > "/etc/mesosphere/setup-flags/repository-url"
http://10.10.1.50:8088

EOF
chmod 0644 /etc/mesosphere/setup-flags/repository-url

mkdir -p `dirname /etc/mesosphere/setup-flags/bootstrap-id`
cat <<'EOF' > "/etc/mesosphere/setup-flags/bootstrap-id"
BOOTSTRAP_ID=3a2b7e03c45cd615da8dfb1b103943894652cd71

EOF
chmod 0644 /etc/mesosphere/setup-flags/bootstrap-id

mkdir -p `dirname /etc/mesosphere/setup-flags/cluster-packages.json`
cat <<'EOF' > "/etc/mesosphere/setup-flags/cluster-packages.json"
["dcos-config--setup_e841d0b6a20d67d54a5ce10be7ba75a7ee747f99", "dcos-metadata--setup_e841d0b6a20d67d54a5ce10be7ba75a7ee747f99"]

EOF
chmod 0644 /etc/mesosphere/setup-flags/cluster-packages.json

mkdir -p `dirname /etc/systemd/journald.conf.d/dcos.conf`
cat <<'EOF' > "/etc/systemd/journald.conf.d/dcos.conf"
[Journal]
MaxLevelConsole=warning

EOF
chmod 0644 /etc/systemd/journald.conf.d/dcos.conf


}

# Install the DC/OS services, start DC/OS
function setup_and_start_services() {

echo -e 'Setting and starting DC/OS'
mkdir -p `dirname /etc/systemd/system/dcos-link-env.service`
cat <<'EOF' > "/etc/systemd/system/dcos-link-env.service"
[Unit]
Before=dcos.target
[Service]
Type=oneshot
StandardOutput=journal+console
StandardError=journal+console
ExecStartPre=/usr/bin/mkdir -p /etc/profile.d
ExecStart=/usr/bin/ln -sf /opt/mesosphere/environment.export /etc/profile.d/dcos.sh

EOF
chmod 0644 /etc/systemd/system/dcos-link-env.service

mkdir -p `dirname /etc/systemd/system/dcos-download.service`
cat <<'EOF' > "/etc/systemd/system/dcos-download.service"
[Unit]
Description=Pkgpanda: Download DC/OS to this host.
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/opt/mesosphere/
[Service]
EnvironmentFile=/etc/mesosphere/setup-flags/bootstrap-id
Type=oneshot
StandardOutput=journal+console
StandardError=journal+console
ExecStartPre=/usr/bin/curl -fLsSv --retry 20 -Y 100000 -y 60 -o /tmp/bootstrap.tar.xz http://10.10.1.50:8088/bootstrap/${BOOTSTRAP_ID}.bootstrap.tar.xz
ExecStartPre=/usr/bin/mkdir -p /opt/mesosphere
ExecStart=/usr/bin/tar -axf /tmp/bootstrap.tar.xz -C /opt/mesosphere
ExecStartPost=-/usr/bin/rm -f /tmp/bootstrap.tar.xz

EOF
chmod 0644 /etc/systemd/system/dcos-download.service

mkdir -p `dirname /etc/systemd/system/dcos-setup.service`
cat <<'EOF' > "/etc/systemd/system/dcos-setup.service"
[Unit]
Description=Pkgpanda: Specialize DC/OS for this host.
Requires=dcos-download.service
After=dcos-download.service
[Service]
Type=oneshot
StandardOutput=journal+console
StandardError=journal+console
EnvironmentFile=/opt/mesosphere/environment
ExecStart=/opt/mesosphere/bin/pkgpanda setup --no-block-systemd
[Install]
WantedBy=multi-user.target

EOF
chmod 0644 /etc/systemd/system/dcos-setup.service


systemctl restart systemd-journald
systemctl restart docker
systemctl start dcos-link-env
systemctl enable dcos-setup

#for dcos_service in dcos-spartan dcos-mesos-${role} dcos-minuteman dcos-epmd dcos-ddt
#do
#	systemctl status ${dcos_service}
#
#done

if (( $SYSTEMCTL_NO_BLOCK == 1 )); then
    systemctl start dcos-setup --no-block
else
    systemctl start dcos-setup
fi

###
# Restart docker with overlay network
###
[[ -z `dig +short leader.mesos` ]] && { echo "Waiting to talk with Mesos DNS ..."; sleep 7; }
THIS_IP=$(ip addr show `find /etc/sysconfig/network-scripts/ -type f -name "ifcfg*" -printf '%f\n' | grep -v ifcfg-lo|sed 's/ifcfg-//'| sort -u | head -1` |grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
cat > /etc/systemd/system/docker.service.d/override.conf  <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/docker daemon --storage-driver=overlay --storage-opt dm.no_warn_on_loop_devices=true -H fd:// -H tcp://0.0.0.0:4243  --insecure-registry dcos-bootstrap.vms.crd.ge.com:5000 --cluster-store=zk://$(dig +short master.mesos|grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'|paste -sd:| sed 's/:/:2181\,/g'):2181 --cluster-advertise=${THIS_IP}:2376
EOF

systemctl daemon-reload
# Docker needs to stop first before the socket can be restarted
systemctl stop docker
systemctl restart docker.socket
systemctl start docker
}

set +e

declare -i DISABLE_VERSION_CHECK=0

# check if sort -V works
function check_sort_capability() {
    $( echo '1' | sort -V >/dev/null 2>&1 || exit 1 )
    RC=$?
    if [[ "$RC" -eq "2" ]]; then
        echo -e "${RED}Disabling version checking as sort -V is not available${NORMAL}"
        DISABLE_VERSION_CHECK=1
    fi
}

function version_gt() {
    # sort -V does version-aware sort
    HIGHEST_VERSION="$(echo "$@" | tr " " "
" | sort -V | tail -n 1)"
    test $HIGHEST_VERSION == "$1"
}

function print_status() {
    CODE_TO_TEST=$1
    EXTRA_TEXT=${2:-}
    if [[ $CODE_TO_TEST == 0 ]]; then
        echo -e "${BOLD}PASS $EXTRA_TEXT${NORMAL}"
    else
        echo -e "${RED}FAIL $EXTRA_TEXT${NORMAL}"
    fi
}

function check_command_exists() {
    COMMAND=$1
    DISPLAY_NAME=${2:-$COMMAND}

    echo -e -n "Checking if $DISPLAY_NAME is installed and in PATH: "
    $( command -v $COMMAND >/dev/null 2>&1 || exit 1 )
    RC=$?
    print_status $RC
    (( OVERALL_RC += $RC ))
    return $RC
}

# Pre-requsites
function pre_requisite() {
    yum -y update; yum -y upgrade
    setenforce 0
    [[ `grep ^nogroup /etc/group|wc -l` -lt 1 ]] && groupadd -g 1001 nogroup
    if ! check_command_exists unzip || ! check_command_exists ipset; then
	  yum -y install unzip ipset
    fi
    if ! check_command_exists docker; then
    	[[ -f /etc/resolv.conf.preinstall ]] && cp -p /etc/resolv.conf.preinstall /etc/resolv.conf
    	curl -fsSL https://test.docker.com/ | sh
    	[[ ! -d /etc/systemd/system/docker.service.d ]] && mkdir -p /etc/systemd/system/docker.service.d
    fi
    if ! check_command_exists dig; then
	yum -y install bind-utils
    fi
  
    cat > /etc/systemd/system/docker.service.d/override.conf  <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/docker daemon --storage-driver=overlay --storage-opt dm.no_warn_on_loop_devices=true -H fd:// -H tcp://0.0.0.0:4243  --insecure-registry dcos-bootstrap.vms.crd.ge.com:5000
EOF

    if [[ ! -f /usr/lib/systemd/system/docker.socket ]]; then
  	tee /usr/lib/systemd/system/docker.socket <<-'EOF'
[Unit]
Description=Docker Socket for the API
PartOf=docker.service

[Socket]
ListenStream=/var/run/docker.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
EOF
    fi

    systemctl daemon-reload
    systemctl stop docker
    systemctl restart docker.socket
    systemctl start docker

   # Add nfs
   [[ `grep '/opt/nfs1' /etc/fstab | grep -v ^#|wc -l` -lt 1 ]] && echo "10.138.64.10:/opt/nfs1	/opt/nfs1			  nfs rsize=8192,wsize=8192,timeo=14,intr" >> /etc/fstab
   [[ `grep '/opt/nfs2' /etc/fstab | grep -v ^#|wc -l` -lt 1 ]] && echo  "10.138.64.10:/opt/nfs2	/var/lib/registry		  nfs rsize=8192,wsize=8192,timeo=14,intr" >> /etc/fstab
   [[ ! -d /opt/nfs1 ]] &&  { mkdir -p /opt/nfs1; mount /opt/nfs1; }
   [[ ! -d /var/lib/registry ]] &&  { mkdir -p /var/lib/registry; mount /var/lib/registry; }

}

function check_version() {
    COMMAND_NAME=$1
    VERSION_ATLEAST=$2
    COMMAND_VERSION=$3
    DISPLAY_NAME=${4:-$COMMAND}

    echo -e -n "Checking $DISPLAY_NAME version requirement (>= $VERSION_ATLEAST): "
    version_gt $COMMAND_VERSION $VERSION_ATLEAST
    RC=$?
    print_status $RC "${NORMAL}($COMMAND_VERSION)"
    (( OVERALL_RC += $RC ))
    return $RC
}

function check_selinux() {
  ENABLED=$(getenforce)

  if [[ $ENABLED != 'Enforcing' ]]; then
    RC=0
  else
    RC=1
  fi

  print_status $RC "Is SELinux disabled?"
  return $RC
}

function check() {
    # Wrapper to invoke both check_commmand and version check in one go
    if [[ $# -eq 4 ]]; then
       DISPLAY_NAME=$4
    elif [[ $# -eq 2 ]]; then
       DISPLAY_NAME=$2
    else
       DISPLAY_NAME=$1
    fi
    check_command_exists $1 $DISPLAY_NAME
    # check_version takes {3,4} arguments
    if [[ "$?" -eq 0 && "$#" -ge 3 && $DISABLE_VERSION_CHECK -eq 0 ]]; then
        check_version $*
    fi
}

function check_service() {
  PORT=$1
  NAME=$2
  echo -e -n "Checking if port $PORT (required by $NAME) is in use: "
  RC=0
  cat /proc/net/{udp*,tcp*} | cut -d: -f3 | cut -d' ' -f1 | grep -q $(printf "%04x" $PORT) && RC=1
  print_status $RC
  (( OVERALL_RC += $RC ))
}

function check_preexisting_dcos() {
    echo -e -n 'Checking if DC/OS is already installed: '
    if [[ ( -d /etc/systemd/system/dcos.target ) ||        ( -d /etc/systemd/system/dcos.target.wants ) ||        ( -d /opt/mesosphere ) ]]; then
        # this will print: Checking if DC/OS is already installed: FAIL (Currently installed)
        print_status 1 "${NORMAL}(Currently installed. Execute dcos_uninstall.sh to clean up first!!!)"
    else
        print_status 0 "${NORMAL}(Not installed)"
    fi
}


function check_docker_device_mapper_loopback() {
    echo -e -n 'Checking Docker is configured with a production storage driver: '

  storage_driver="$(docker info | grep 'Storage Driver' | cut -d ':' -f 2  | tr -d '[[:space:]]')"

  if [ "$storage_driver" != "devicemapper" ]; then
      print_status 0 "${NORMAL}(${storage_driver})"
      return
  fi

  data_file="$(docker info | grep 'Data file' | cut -d ':' -f 2  | tr -d '[[:space:]]')"

  if [[ "${data_file}" == /dev/loop* ]]; then
    print_status 1 "${NORMAL}(${storage_driver}, ${data_file})"
    echo
    cat <<EOM
Docker is configured to use the devicemapper storage driver with a loopback
device behind it. This is highly recommended against by Docker and the
community at large for production use[0][1]. See the docker documentation on
selecting an alternate storage driver, or use alternate storage than loopback
for the devicemapper driver.

[0] https://docs.docker.com/engine/userguide/storagedriver/device-mapper-driver/
[1] http://www.projectatomic.io/blog/2015/06/notes-on-fedora-centos-and-docker-storage-drivers/
EOM
        echo
	exit 1
    else
        print_status 0 "${NORMAL}(${storage_driver} ${data_file})"
    fi
}

function check_all() {
    # Disable errexit because we want the preflight checks to run all the way
    # through and not bail in the middle, which will happen as it relies on
    # error exit codes
    set +e
    echo -e "${BOLD}Running preflight checks${NORMAL}"

    #check_preexisting_dcos
    check_selinux
    check_sort_capability

    local docker_version=$(command -v docker >/dev/null 2>&1 && docker version 2>/dev/null | awk '
        BEGIN {
            version = 0
            client_version = 0
            server_version = 0
        }
        {
            if($1 == "Server:") {
                server = 1
                client = 0
            } else if($1 == "Client:") {
                server = 0
                client = 1
            } else if ($1 == "Server" && $2 == "version:") {
                server_version = $3
            } else if ($1 == "Client" && $2 == "version:") {
                client_version = $3
            }
            if(server && $1 == "Version:") {
                server_version = $2
            } else if(client && $1 == "Version:") {
                client_version = $2
            }
        }
        END {
            if(client_version == server_version) {
                version = client_version
            } else {
                split(client_version, cv, ".")
                split(server_version, sv, ".")

                y = length(cv) > length(sv) ? length(cv) : length(sv)

                for(i = 1; i <= y; i++) {
                    if(cv[i] < sv[i]) {
                        version = client_version
                        break
                    } else if(sv[i] < cv[i]) {
                        version = server_version
                        break
                    }
                }
            }
            print version
        }
    ')
    # CoreOS stable as of Aug 2015 has 1.6.2
    check docker 1.12 "$docker_version"
    check_preexisting_dcos

    check curl
    check bash
    check ping
    check tar
    check xz
    check unzip
    check ipset
    check systemd-notify
    check dig

    # $ systemctl --version ->
    # systemd nnn
    # compiler option string
    # Pick up just the first line of output and get the version from it
    check systemctl 200 $(systemctl --version | head -1 | cut -f2 -d' ') systemd

    echo -e -n "Checking if group 'nogroup' exists: "
    getent group nogroup > /dev/null
    RC=$?
    print_status $RC
    (( OVERALL_RC += $RC ))
    #for service in       "80 mesos-ui"       "53 mesos-dns"       "15055 dcos-history"       "5050 mesos-master"       "2181 zookeeper"       "8080 marathon"       "3888 zookeeper"       "8181 exhibitor"       "8123 mesos-dns"
    ##for service in       "80 mesos-ui"       "15055 dcos-history"       "5050 mesos-master"       "2181 zookeeper"       "8080 marathon"       "3888 zookeeper"       "8181 exhibitor"       "8123 mesos-dns"
    ##do
     ## check_service $service
    ##done

    # Check we're not in docker on devicemapper loopback as storage driver.
    if [[ `grep 'net.bridge.bridge-nf-call-iptables = 1' /etc/sysctl.conf |grep -v ^#| wc -l` -lt 1 ]]; then
	echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.conf
    	echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.conf
    	sysctl --system
    fi
    check_docker_device_mapper_loopback
    echo -e "Done with check_docker_xxxx, going to role check ${OVERALL_RC}"
    for role in "$ROLES"
    do
        if [ "$role" != "master" -a "$role" != "slave" -a "$role" != "slave_public" -a "$role" != "minuteman" ]; then
            echo -e "${RED}FAIL Invalid role $role. Role must be one of {master,slave,slave_public}{NORMAL}"
            (( OVERALL_RC += 1 ))
        fi
    done
    echo -e "Done with role check ${OVERALL_RC}"
    return $OVERALL_RC
}

function dcos_install()
{
    # Enable errexit
    set -e

    setup_directories
    setup_dcos_roles
    configure_dcos
    setup_and_start_services

}

function usage()
{
    echo -e "${BOLD}Usage: $0 [--disable-preflight|--preflight-only] <roles>${NORMAL}"
}

function main()
{
    eval set -- "$ARGS"

    while true ; do
        case "$1" in
            -d|--disable-preflight) DISABLE_PREFLIGHT=1;  shift  ;;
            -p|--preflight-only) PREFLIGHT_ONLY=1 ; shift  ;;
            --no-block-dcos-setup) SYSTEMCTL_NO_BLOCK=1;  shift ;;
            -h|--help) usage; exit 1 ;;
            --) shift ; break ;;
            *) usage ; exit 1 ;;
        esac
    done

    if [[ $DISABLE_PREFLIGHT -eq 1 && $PREFLIGHT_ONLY -eq 1 ]]; then
        echo -e 'Both --disable-preflight and --preflight-only can not be specified'
        usage
        exit 1
    fi

    shift $(($OPTIND - 1))
    ROLES=$@

    [[ ! -f /etc/resolv.conf.preinstall ]] && cp -p /etc/resolv.conf /etc/resolv.conf.preinstall
    [[ ! -f /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7 ]] && curo -o /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7 http://dcos-bootstrap.vms.crd.ge.com:8088/RPM-GPG-KEY-EPEL-7
    pre_requisite
    if [[ $PREFLIGHT_ONLY -eq 1 ]] ; then
        check_all
    else
        if [[ -z $ROLES ]] ; then
            echo -e 'Atleast one role name must be specified'
            usage
            exit 1
        fi
        echo -e "${BOLD}Starting DC/OS Install Process${NORMAL}"
        if [[ $DISABLE_PREFLIGHT -eq 0 ]] ; then
            check_all
            RC=$?
            if [[ $RC -ne 0 ]]; then
                echo 'Preflight checks failed. Exiting installation. Please consult product documentation'
                exit $RC
            fi
        fi
        # Run actual install
        dcos_install
    fi

}

# Run it all
main
