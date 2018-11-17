# Expand the `asn` records into `ipv4`/`ipv6` records in RIRs

## How to use:

```sh
#!/bin/sh
cache="/var/cache"

rirs="${cache}/delegated-apnic-latest"
expanded_rirs="${cache}/expanded-delegated-apnic-latest"
asn_cache="${cache}/asn"

geoip_database="http://geolite.maxmind.com/download/geoip/database"
geoip_country_cache="${cache}/GeoIP/country"
geoip_country_csv="${geoip_country_cache}/GeoLite2-Country-CSV"
geoip_country_csv_zip="${geoip_country_csv}.zip"

mkdir -p "${asn_cache}"
mkdir -p "${geoip_country_csv}"

get.sh \
		-o "${rirs}" \
		-r 10 \
		"http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest" \
	&& expand-rir-asn.sh \
		-i "${rirs}" \
		-o "${expanded_rirs}" \
		-C "${asn_cache}" \
	&& get.sh \
		-o "${geoip_country_csv_zip}" \
		-r 10 \
		"${geoip_database}/GeoLite2-Country-CSV.zip" \
	&& unzip \
		-oqd "${geoip_country_cache}" \
		"${geoip_country_csv_zip}" \
	&& rsync \
		"${geoip_country_cache}"/*/* \
		"${geoip_country_csv}/" \
	&& rm \
		-r "${geoip_country_csv}"_* \
	&& update-ipset.sh \
		-n chnroute \
		-i "${expanded_rirs}" \
		-g "${geoip_country_csv}" \
		-c CN
```
