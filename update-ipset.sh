#!/bin/sh
usage() {
cat << EOF
usage: $0 <-n SETNAME> [[-c cc]...] [-i input] [-g GeoIP Country CSV directory] [-l IP2Location Country CSV file] [[-a Autonomous System Number]...] [-C ASN cache directory] [[-d domain]...] [[-f file]...]
	-n SETNAME
	-c ISO 3166 2-letter code
	-i input expanded delegated apnic file
	-g GeoIP(http://www.maxmind.com) Country CSV directory
	-l IP2Location(https://lite.ip2location.com/ip2location-lite) Country CSV file
	-a Autonomous System Number
	-C ASN cache directory, the directory should exist and be writable
	-d SPF record domain name
	-f file contains ipset entries
EOF
}

while getopts ":n:c:i:g:l:a:C:d:f:" o; do
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
		g)
			geoip_country_csv="${OPTARG}"
			;;
		l)
			ip2location_country_csv="${OPTARG}"
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

if [ -z "${setname}" -o \( -n "${ccs}" -a \( ! -r "${input}" -a ! -d "${geoip_country_csv}" -a ! -r "${ip2location_country_csv}" \) \) ]; then
	usage
	exit 1
fi

update_ipset_random_setname() {
	cat /dev/urandom | env LC_CTYPE=C tr -dc 'a-zA-Z0-9' | head -c 31
}

update_ipset_ipset_list_members() {
	ipset -q list "$1" | sed -e '1,/Members:/d'
}

update_ipset_cc_ipset_rirs() {
	local cc="$1"
	local rirs="$2"
	cat "${rirs}" \
		| awk \
			-v "cc=${cc}" \
			'BEGIN { FS = "|" } $2 == cc && $3 == "ipv4" { printf("%s/%d\n", $4, 32-log($5)/log(2)) }' \
		| sed 's/\/32$//g'
}

update_ipset_cc_ipset_geo() {
	local cc="$1"
	local geoip_country_csv="$2"
	local geoname_id=`awk -v "cc=${cc}" 'BEGIN { FS = "," } $5 == cc { print $1 }' \
		"${geoip_country_csv}/GeoLite2-Country-Locations-en.csv"`
	awk \
		-v "geoname_id=${geoname_id}" \
		'BEGIN { FS = "," } $2 == geoname_id { print $1 }' \
		"${geoip_country_csv}/GeoLite2-Country-Blocks-IPv4.csv" \
	| sed 's/\/32$//g'
}

update_ipset_cc_ipset_ip2location() {
	local cc="$1"
	local ip2location_country_csv="$2"
	local setname="`update_ipset_random_setname`"
	ipset create "${setname}" hash:net maxelem 4294967295
	awk \
		-v cc="${cc}" \
		-v setname="${setname}" \
		'
		BEGIN {
			FS = ","
		}
		$3 == "\"" cc "\"" {
			cmd = "ipset -exist add \"" setname "\" \"" $1 "-" $2 "\""
			system(cmd)
		}
		' \
		"${ip2location_country_csv}"
	local ip2location_ipset="`update_ipset_ipset_list_members "${setname}"`"
	echo "${ip2location_ipset}"
	ipset destroy "${setname}"
}

update_ipset_cc_ipset() {
	local cc="$1"
	if [ -r "${input}" ]; then
		local rirs_ipset="`update_ipset_cc_ipset_rirs "${cc}" "${input}"`"
		echo "${rirs_ipset}"
	fi
	if [ -d "${geoip_country_csv}" ]; then
		local geoip_ipset="`update_ipset_cc_ipset_geo "${cc}" "${geoip_country_csv}"`"
		echo "${geoip_ipset}"
	fi
	if [ -r "${ip2location_country_csv}" ]; then
		local ip2location_ipset="`update_ipset_cc_ipset_ip2location "${cc}" "${ip2location_country_csv}"`"
		echo "${ip2location_ipset}"
	fi
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

			cmd = "dig +short \"" domain "\""
			mod = cmd "; echo \"$?\""
			while ((mod | getline line) > 0) {
				if (numLines++) {
					system("echo \"" prev "\" | grep -E \"[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+\" | xargs -I ip ipset -exist add \"" setname "\" ip/" cidr)
				}
				prev = line
			}
			status = line
			close(mod)

			if (status != 0) {
				print "ERROR: command '\''" cmd "'\'' failed" | "cat >&2"
				close("cat >&2")
				exit status
			}

		} else {
			cmd = "ipset -exist add \"" setname "\" \"" $0 "\""
			system(cmd)
		}
	}
	' \
	${files}
	files_status=$?
	files_ipset="`update_ipset_ipset_list_members "${files_setname}"`"
	ipset destroy "${files_setname}"
	if [ ${files_status} -ne 0 ]; then
		exit ${files_status}
	fi
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
