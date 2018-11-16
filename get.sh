#!/bin/sh
max_retry_count=1

usage() {
cat << EOF
usage: $0 [-o output] [-r max retry count]
	-o output
	-r max retry count
EOF
}

while getopts ":o:r:" o; do
	case "${o}" in
		o)
			output="${OPTARG}"
			;;
		r)
			max_retry_count="${OPTARG}"
			;;
		*)
			usage
			exit
			;;
	esac
done
shift $((OPTIND-1))
url=$1

if [ -z "${output}" -o -z "${url}" ]; then
	usage
	exit 1
fi

_md5() {
	if hash md5 2>/dev/null; then
		md5 "$@" | awk -F ' = ' '{print $2}'
	else
		md5sum "$@" | awk '{print $1}'
	fi
}

retried_count=0

while [ ${retried_count} -lt ${max_retry_count} ]; do
	retried_count=`expr ${retried_count} + 1`
	fresh_md5=`curl -sf "${url}.md5" | awk -F ' = ' '{print $NF}'`
	if [ ! -z "${fresh_md5}" ]; then
		[ -r "${output}" ] && cached_md5=`_md5 "${output}"` && [ "${cached_md5}" = "${fresh_md5}" ] && exit 0

		curl -sf -o "${output}" "${url}" \
			&& [ -r "${output}" ] && cached_md5=`_md5 "${output}"` && [ "${cached_md5}" = "${fresh_md5}" ] && exit 0
	fi
done

exit 2
