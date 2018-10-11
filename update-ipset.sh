#!/bin/sh
input="./expanded-delegated-apnic-latest"
files=""

usage() {
cat << EOF
usage: $0 <-n SETNAME> [-i input <-c cc>] [[-f file]...]
	-n SETNAME
	-i input expanded delegated apnic file
	-c ISO 3166 2-letter code
	-f file contains ipset entries
EOF
}

while getopts ":n:i:c:f:" o; do
	case "${o}" in
		n)
			setname="${OPTARG}"
			;;
		i)
			input="${OPTARG}"
			;;
		c)
			cc="${OPTARG}"
			;;
		f)
			if [ -z "${OPTARG}" -o ! -r "${OPTARG}" ]; then
				echo "\"${OPTARG}\" does not exist."
				usage
				exit 1
			fi
			files="${files} ${OPTARG}"
			;;
		*)
			usage
			exit
			;;
	esac
done
shift $((OPTIND-1))

if [ -z "${setname}" -o \( -n "${cc}" -a ! -r "${input}" \) ]; then
	usage
	exit 1
fi

update_ipset_random_setname() {
	cat /dev/urandom | env LC_CTYPE=C tr -dc 'a-zA-Z0-9' | head -c 31
}

update_ipset_ipset_list_members() {
	ipset -q list "$1" | sed -e '1,/Members:/d'
}

# exist ipset
exist_ipset="`update_ipset_ipset_list_members "${setname}" | sort`"

# cc
if [ -n "${cc}" ]; then
	cc_ipset="`\
		cat "${input}" \
		| awk -v "cc=${cc}" \
			'BEGIN { FS = "|" } $2 == cc && $3 == "ipv4" { printf("%s/%d\n", $4, 32-log($5)/log(2)) }' \
		| sed 's/\/32$//g' \
	`"
fi

# files
if [ -n "${files}" ]; then
	files_setname="`update_ipset_random_setname`"
	ipset create "${files_setname}" hash:net maxelem 4294967295
	awk -v setname="${files_setname}" \
	'
	{
		if (/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ || /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ || /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+/) {
			# ip | fromip-toip | ip/cidr
			cmd = "ipset -exist add " setname " " $0
			system(cmd)
		} else if (/.*(\/[0-9]+)?/) {
			# domain | domain/cidr
			cidr = "32"
			split($0, parts, "/")
			domain = parts[1]
			if (parts[2] != "") {
				cidr = parts[2]
			}
			cmd = "dig +short " domain " | grep -E \"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\" | xargs -I ip ipset -exist add " setname " ip/" cidr
			system(cmd)
		} else {
			cmd = "ipset -exist add " setname " " $0
			system(cmd)
		}
	}
	' \
	${files}
	files_ipset="`update_ipset_ipset_list_members "${files_setname}"`"
	ipset destroy "${files_setname}"
fi

# fresh ipset
fresh_ipset="${cc_ipset}
${files_ipset}"
fresh_ipset="`echo "${fresh_ipset}" | sed '/^$/d' | sort | uniq`"

# refresh
if [ "${exist_ipset}" != "${fresh_ipset}" ]; then
	fresh_count=`echo "${fresh_ipset}" | wc -l`
	fresh_setname="`update_ipset_random_setname`"
	ipset create "${fresh_setname}" hash:net maxelem ${fresh_count}
	echo "${fresh_ipset}" \
		| awk -v "setname=${fresh_setname}" '/.+/ { printf("add " setname " %s\n", $0) }' \
		| ipset -exist restore
	ipset -exist -quiet create "${setname}" hash:net
	ipset swap "${setname}" "${fresh_setname}"
	ipset destroy "${fresh_setname}"
fi
