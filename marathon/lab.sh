#!/bin/bash
function usage() {
cat <<EOF
usage: $0 options

Deploy applications on LAB using Marathon

Example:
	$0 -[l|a|d|h|g|G|D] [<app_name>]

OPTIONS:
	-h -- Display help
	-l -- List deployed applications
	-a -- Add a new application
	-d -- Delete an existing application
	-g -- List a group
	-G -- Add a new group
	-D -- Delete a group

EOF
}
while getopts "ha:lgd:G:D:" OPTION; do
case "$OPTION" in
l)
	curl  http://adminUser:topP1ssw0rd@3.39.90.170:8080/v2/apps | python -m json.tool
	;;
h)
	usage
	exit 0
	;;
a)
	curl -X POST  http://adminUser:topP1ssw0rd@3.39.90.170:8080/v2/apps -d @$2.json -H "Content-type:application/json"
	;;
G)
        curl -X POST  http://adminUser:topP1ssw0rd@3.39.90.170:8080/v2/groups -d @$2.json -H "Content-type:application/json"
        ;;
g)
        [[ $# == 1 ]] && curl -X GET  http://adminUser:topP1ssw0rd@3.39.90.170:8080/v2/groups | python -m json.tool
        [[ $# == 2 ]] && curl -X GET  http://adminUser:topP1ssw0rd@3.39.90.170:8080/v2/groups/$2 | python -m json.tool
        ;;
d)
	curl -X DELETE  http://adminUser:topP1ssw0rd@3.39.90.170:8080/v2/apps/$2
	;;
D)
        curl -X DELETE  http://adminUser:topP1ssw0rd@3.39.90.170:8080/v2/groups/$2
        ;;
\?)
        echo "Invalid option: -"$OPTARG"" >&2
        usage
        exit 1
        ;;
:)
        usage
        exit 1
        ;;
esac
done
