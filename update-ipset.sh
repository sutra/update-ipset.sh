#!/bin/sh
usage() {
cat << EOF
usage: $0 <-n SETNAME> [[-c cc]...] [-i input] [[-a Autonomous System Number]...] [-C ASN cache directory] [[-d domain]...] [[-f file]...]
	-n SETNAME
	-c ISO 3166 2-letter code
	-i input expanded delegated apnic file
	-a Autonomous System Number
	-C ASN cache directory, the directory should exist and be writable
	-d SPF record domain name
	-f file contains ipset entries
EOF
}

while getopts ":n:c:i:a:C:d:f:" o; do
	case "${o}" in
		n)
			setname="${OPTARG}"
			;;
		c)
			ccs="${ccs} ${OPTARG}"
			;;
		i)
			input="${OPTARG}"
			;;
		a)
			asns="${asns} ${OPTARG}"
			;;
		C)
			cache="${OPTARG}"
			;;
		d)
			domains="${domains} ${OPTARG}"
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

if [ -z "${setname}" -o \( -n "${ccs}" -a ! -r "${input}" \) ]; then
	usage
	exit 1
fi

update_ipset_random_setname() {
	cat /dev/urandom | env LC_CTYPE=C tr -dc 'a-zA-Z0-9' | head -c 31
}

update_ipset_ipset_list_members() {
	ipset -q list "$1" | sed -e '1,/Members:/d'
}

update_ipset_cc_ipset() {
	local cc="$1"
	cat "${input}" \
		| awk -v "cc=${cc}" \
			'BEGIN { FS = "|" } $2 == cc && $3 == "ipv4" { printf("%s/%d\n", $4, 32-log($5)/log(2)) }' \
		| sed 's/\/32$//g'
}

update_ipset_query_asn() {
	local asn="$1"
	whois -h "whois.radb.net" -- "-i origin AS${asn}" | grep -E "route6?:"
}

update_ipset_get_asn_cache_file() {
	local asn="$1"
	local cache_file=`find "${cache}" -mtime -30 -type f -name "${asn}" 2>/dev/null | head -n 1`
	if [ -z "${cache_file}" ]; then
		cache_file="${cache}/${asn}"
		update_ipset_query_asn "${asn}" > "${cache_file}"
	fi
	echo "${cache_file}"
}

update_ipset_read_asn() {
	local asn="$1"
	if [ -d "${cache}" ]; then
		cat `update_ipset_get_asn_cache_file "${asn}"`
	else
		update_ipset_query_asn "${asn}"
	fi
}

update_ipset_asn_ipset() {
	local asn="$1"
	update_ipset_read_asn "${asn}" \
		| grep '^route:' \
		| awk '{ print $2 }' \
		| sed 's/\/32$//g'
}

update_ipset_spf_ipset() {
	local spf="$1"
	dig +short "${spf}" TXT \
		| awk -F "\"" '{print $2}' \
		| sed -E -e 's/[[:blank:]]+/\n/g' \
		| grep '^include:' \
		| awk -F ':' '{print $2}' \
		| xargs -I '{}' dig +short '{}' TXT \
		| awk -F "\"" '{print $2}' \
		| sed -E -e 's/[[:blank:]]+/\n/g' \
		| grep '^ip4:' \
		| awk -F ':' '{print $2}'
}

# exist ipset
exist_ipset="`update_ipset_ipset_list_members "${setname}" | sort`"

# ccs
for cc in ${ccs}; do
	cc_ipset="`update_ipset_cc_ipset "${cc}"`"
	ccs_ipset=$(printf "${ccs_ipset}\n${cc_ipset}\n")
done

# asns
for asn in ${asns}; do
	asn_ipset="`update_ipset_asn_ipset "${asn}"`"
	asns_ipset=$(printf "${asns_ipset}\n${asn_ipset}\n")
done

# SPF record domain names
for domain in ${domains}; do
	domain_ipset="`update_ipset_spf_ipset "${domain}"`"
	domains_ipset=$(printf "${domains_ipset}\n${domain_ipset}\n")
done

# files
if [ -n "${files}" ]; then
	files_setname="`update_ipset_random_setname`"
	ipset create "${files_setname}" hash:net maxelem 4294967295
	awk -v setname="${files_setname}" \
	'
	{
		if (/^$/ || /^#/) {
			# Empty line, or line starts with #
			# Skip empty lines and comment lines
		} else if (/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ || /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ || /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+/) {
			# ip | fromip-toip | ip/cidr
			cmd = "ipset -exist add \"" setname "\" \"" $0 "\""
			system(cmd)
		} else if (/.*(\/[0-9]+)?/) {
			# domain | domain/cidr
			cidr = "32"
			split($0, parts, "/")
			domain = parts[1]
			if (parts[2] != "") {
				cidr = parts[2]
			}
			cmd = "dig +short \"" domain "\" | grep -E \"[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+\" | xargs -I ip ipset -exist add \"" setname "\" ip/" cidr
			system(cmd)
		} else {
			cmd = "ipset -exist add \"" setname "\" \"" $0 "\""
			system(cmd)
		}
	}
	' \
	${files}
	files_ipset="`update_ipset_ipset_list_members "${files_setname}"`"
	ipset destroy "${files_setname}"
fi

# fresh ipset
fresh_ipset=$(printf "${ccs_ipset}\n${asns_ipset}\n${domains_ipset}\n${files_ipset}\n")
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
