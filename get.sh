#!/bin/sh
max_retry_count=1
exit_status_modified=0
exit_status_not_modified=0

usage() {
cat << EOF
usage: $0 [-o output] [-r max retry count] <URL>
	-o output
	-r max retry count
	-m exit status of modified, default is 0. 200 is recommended.
	-n exit status of not modfied, default is 0. 204 is recommended.
EOF
}

while getopts ":o:r:m:n:" o; do
	case "${o}" in
		o)
			output="${OPTARG}"
			;;
		r)
			max_retry_count="${OPTARG}"
			;;
		m)
			exit_status_modified="${OPTARG}"
			;;
		n)
			exit_status_not_modified="${OPTARG}"
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

if [ ${exit_status_modified} -eq 1 -o ${exit_status_modified} -eq 2 -o ${exit_status_not_modified} -eq 1 -o ${exit_status_not_modified} -eq 2 ]; then
	echo 'Exit status 1 and 2 are reserved.'
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
	fresh_md5=`curl -sf "${url}.md5" | awk -F ' = ' '{print $NF}' | awk -F ' ' '{print $1}'`
	if [ ! -z "${fresh_md5}" ]; then
		[ -r "${output}" ] \
			&& cached_md5=`_md5 "${output}"` \
			&& [ "${cached_md5}" = "${fresh_md5}" ] \
			&& exit ${exit_status_not_modified}

		curl -sf -o "${output}" "${url}" \
			&& [ -r "${output}" ] \
			&& cached_md5=`_md5 "${output}"` \
			&& [ "${cached_md5}" = "${fresh_md5}" ] \
			&& exit ${exit_status_modified}
	fi
done

exit 2
