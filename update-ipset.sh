#!/bin/sh
input="./expanded-delegated-apnic-latest"

usage() {
cat << EOF
usage: $0 [-i input] <-c cc> <-n SETNAME>
	-i input expanded delegated apnic file
	-c ISO 3166 2-letter code
	-n SETNAME
EOF
}

while getopts ":i:c:n:" o; do
	case "${o}" in
		i)
			input="${OPTARG}"
			;;
		c)
			cc="${OPTARG}"
			;;
		n)
			setname="${OPTARG}"
			;;
		*)
			usage
			exit
			;;
	esac
done
shift $((OPTIND-1))

if [ ! -r "${input}" -o "${#cc}" -ne 2 -o -z "${setname}" ]; then
	usage
	exit 1
fi

exist_ipset="`ipset -q list "${setname}" | sed -e '1,/Members:/d' | sort`"
fresh_ipset="`\
	cat "${input}" \
	| awk -v "cc=${cc}" \
		'BEGIN { FS = "|" } $2 == cc && $3 == "ipv4" { printf("%s/%d\n", $4, 32-log($5)/log(2)) }' \
	| sed 's/\/32$//g' \
	| sort \
	| uniq \
`"

if [ "${exist_ipset}" != "${fresh_ipset}" ]; then
	fresh_count=`echo "${fresh_ipset}" | wc -l`
	maxelem=`
		(ipset list -q -t "${setname}" \
			|| echo 'Header: family inet hashsize 37268 maxelem 0') \
		| grep maxelem \
		| awk '{print $7}'
	`

	fresh_setname="`cat /dev/urandom | env LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 31 | head -n 1`"
	ipset create "${fresh_setname}" hash:net maxelem ${fresh_count} \
		&& echo "${fresh_ipset}" \
			| awk -v "setname=${fresh_setname}" '/.+/ { printf("add " setname " %s\n", $0) }' \
			| ipset -exist restore \
		&& ipset -exist create "${setname}" hash:net \
		&& ipset swap "${setname}" "${fresh_setname}" \
		&& ipset destroy "${fresh_setname}"
fi
