#!/bin/sh
basedir=$(cd "$(dirname "$0")"; pwd)
input="./delegated-apnic-latest"
output="./expanded-delegated-apnic-latest"
cache="asn"

usage() {
cat << EOF
usage: $0 [-i input] [-o output] [-c cache]
	-i input
	-o output
	-c cache directory
EOF
}

while getopts ":i:o:c:" o; do
	case "${o}" in
		i)
			input="${OPTARG}"
			;;
		o)
			output="${OPTARG}"
			;;
		c)
			cache="${OPTARG}"
			;;
		*)
			usage
			exit
			;;
	esac
done
shift $((OPTIND-1))

if [ -z "${input}" -o -z "${output}" -o -z "${cache}" ]; then
	usage
	exit 1
fi

[ -r "${input}" ] \
	&& input_serial=`grep -v -E '^#' "${input}" | head -1 | awk -F'|' '{print $3}'`

[ -z "${input_serial}" ] && exit 1

[ -r "${output}" ] \
	&& output_serial=`grep -v -E '^#' "${output}" | head -1 | awk -F'|' '{print $3}'`

[ "${input_serial}" = "${output_serial}" ] \
	|| "${basedir}/expand-rir-asn.awk" -v "cache=${cache}" "${input}" \
		> "${output}" && exit 0

exit 2
