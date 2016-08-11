#!/bin/bash 
#
# Uninstall DC/OS and Docker on CentOS
#

set +e

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


if check_command_exists  docker || rpm -qa | grep -qw docker; then
	systemctl stop docker.socket
	systemctl stop docker
	yum -y remove docker-engine docker-engine-selinux
	[[ -f /etc/systemd/system/docker.service.d/override.conf ]] && rm -f /etc/systemd/system/docker.service.d/override.conf
	[[ -f /usr/lib/systemd/system/docker.socket ]] && rm -f /usr/lib/systemd/system/docker.socket
fi

if [[ ( -d /etc/systemd/system/dcos.target ) || ( -d /etc/systemd/system/dcos.target.wants ) || ( -d /opt/mesosphere ) ]]; then
        # this will print: Checking if DC/OS is already installed: FAIL (Currently installed)
        print_status 0 "${NORMAL}(Removing installed DC/OS components......)"
	for procs_i in dcos-mesos-slave dcos-minuteman dcos-epmd dcos-ddt dcos-spartan dcos-link-env dcos-setup
	do
		systemctl stop ${procs_i}
	done
        #Alfred allows idempotence
        [[ -x /opt/mesosphere/bin/pkgpanda ]] && /opt/mesosphere/bin/pkgpanda uninstall
        [[ -d /opt/mesosphere ]] && rm -rf /opt/mesosphere /etc/mesosphere /etc/systemd/system/dcos.target /etc/systemd/system/dcos.target.wants
        [[ -f /etc/resolv.conf.preinstall ]] && cp -p /etc/resolv.conf.preinstall /etc/resolv.conf
        print_status 0 "${NORMAL}(Removed existing installation!)"
fi

