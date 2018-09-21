#!/usr/bin/awk -f

#
# Expands the asn records in RIRs to ipv4/ipv6 records.
#
# The RIRs: http://www.apnic.net/db/rir-stats-format.html
#

BEGIN {
	cache = cache != "" ? cache : "asn"
	debug("cache: " cache)
	system("mkdir -p '" cache "'")

	FS = "|"
	versionLineRead = 0
}

{
	debug("Processing line " NR)

	if (/^#/) {
		# The comment line
		print
	} else if (versionLineRead == 0) {
		# The version line
		versionLineRead = 1
		print
	} else if (NF == 6 && $6 == "summary") {
		# The summary line
		print
	} else if ($3 == "asn") {
		# The asn record line
		expandASNs($1, $2, $4, $5, $6, $7)
	} else {
		print
	}
}

# Expand the ASNs to ipv4/ipv6 records
function expandASNs(registry, cc, startAsn, count, date, status) {
	for (i = 0; i < count; i++) {
		expandASN(registry, cc, startAsn + i, date, status)
	}
}

# Expand the ASN record to ipv4/ipv6 records.
function expandASN(registry, cc, asn, date, status) {
	cacheFile = getCacheFile(asn)
	while ((getline line < cacheFile) > 0) {
		split(line, columns, "(:[ \t]+)|/")

		if (columns[1] == "route") {
			type = "ipv4"
			value = 2 ^ (32 - columns[3])
		} else if (columns[1] == "route6") {
			type = "ipv6"
			value = columns[3]
		} else {
			type = ""
			value = 0
		}

		if (type != "") {
			printf("%s|%s|%s|%s|%s|%s|%s\n",
				registry, cc, type, columns[2], value, date, status)
		}
	}
	close(cacheFile)
}

# Return the path of the cache file for the ASN.
# The cache will be refreshed if it is stale.
function getCacheFile(asn) {
	# command to find the cache file
	cmd = "find '" cache "' -mtime -30 -type f -name '" asn "' 2>/dev/null"
	debug(cmd)

	# finding the cache file
	hasCacheFile = cmd | getline cacheFile
	close(cmd)

	if (hasCacheFile == 0) {
		# cache file was not found

		cacheFile = cache "/" asn

		# command to query by whois and write to cache file
		cmd = "whois -h 'whois.radb.net' -- '-i origin AS" asn "' | grep -E 'route6?:' > '" cacheFile "'"
		debug(cmd)

		system(cmd)
	}

	return cacheFile
}

function debug(msg) {
	print msg | "cat >&2"
	close("cat >&2")
}
