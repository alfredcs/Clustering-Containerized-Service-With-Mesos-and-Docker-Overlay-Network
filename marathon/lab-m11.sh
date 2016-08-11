#!/bin/bash
function usage() {
cat <<EOF
usage: $0 options

Deploy applications on AWS using Marathon

Example:
	$0 -[l|a|d|h|g|A|D|L] [<app_name>]

OPTIONS:
	-h -- Display help
	-l -- List deployed applications
	-a -- Add a new application
	-g -- List a groups
	-d -- Delete an existing application
	-A -- Add a new group
	-D -- Delete a group
	-L -- Display leader

EOF
}
while getopts "ha:lLgd:A:D:" OPTION; do
case "$OPTION" in
l)
	curl -k  https://adminUser:topP1ssw0rd@3.39.90.173:8443/v2/apps/$2 | python -m json.tool
	;;
L)
	curl -k  https://adminUser:topP1ssw0rd@3.39.90.173:8443/v2/$2
	;;
h)
	usage
	exit 0
	;;
a)
	curl -k -X POST https://adminUser:topP1ssw0rd@3.39.90.173:8443/v2/apps -d @$2 -H "Content-type:application/json"
	;;
d)
	curl -k -X DELETE https://adminUser:topP1ssw0rd@3.39.90.173:8443/v2/apps/$2
	;;
A)
        curl -k -X POST  https://adminUser:topP1ssw0rd@3.39.90.173:8443/v2/groups -d @$2 -H "Content-type:application/json"
        ;;
g)
        [[ $# == 1 ]] && curl -k -X GET  https://adminUser:topP1ssw0rd@3.39.90.173:8443/v2/groups | python -m json.tool
        [[ $# == 2 ]] && curl -k -X GET  https://adminUser:topP1ssw0rd@3.39.90.173:8443/v2/groups/$2 | python -m json.tool
        ;;
D)
        curl -k -X DELETE  https://adminUser:topP1ssw0rd@3.39.90.173:8443/v2/groups/$2
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
