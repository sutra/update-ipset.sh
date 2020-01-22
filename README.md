# Update ipset based on RIRs and GeoIP

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

ip2location_lite_db1="https://download.ip2location.com/lite"
ip2location_lite_db1_cache="${cache}/ip2location_lite_db1"
ip2location_lite_db1_csv="${ip2location_lite_db1_cache}/IP2LOCATION-LITE-DB1.CSV"
ip2location_lite_db1_csv_zip="${ip2location_lite_db1_csv}.ZIP"

mkdir -p "${asn_cache}"
mkdir -p "${geoip_country_csv}"
mkdir -p "${ip2location_lite_db1_cache}"

get.sh \
		-o "${rirs}" \
		-r 10 \
		"http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest" \
	&& expand-rir-asn.sh \
		-i "${rirs}" \
		-o "${expanded_rirs}" \
		-C "${asn_cache}" \
	|| exit 1

get.sh \
		-o "${geoip_country_csv_zip}" \
		-r 10 \
		-m 200 \
		-n 204 \
		"${geoip_database}/GeoLite2-Country-CSV.zip"
exit_status=$?
if [ ${exit_status} -eq 200 ]; then
	unzip \
		-oqd "${geoip_country_cache}" \
		"${geoip_country_csv_zip}" \
	&& rsync \
		"${geoip_country_cache}"/*/* \
		"${geoip_country_csv}/" \
	&& rm \
		-r "${geoip_country_csv}"_*
#elif [ ${exit_status} -ne 204 ]; then
#	exit $?
fi

get.sh \
	-o "${ip2location_lite_db1_csv_zip}" \
	-r 10 \
	-m 200 \
	-n 204 \
	"${ip2location_lite_db1}/IP2LOCATION-LITE-DB1.CSV.ZIP"
exit_status=$?
if [ ${exit_status} -eq 200 ]; then
	unzip \
		-oqd "${ip2location_lite_db1_cache}" \
		"${ip2location_lite_db1_csv_zip}"
fi

update-ipset.sh \
		-n "chnroute" \
		-i "${expanded_rirs}" \
		-g "${geoip_country_csv}" \
		-l "${ip2location_lite_db1_csv}" \
		-c "CN"
```
