# Expand the `asn` records into `ipv4`/`ipv6` records in RIRs

## How to use:

```sh
#!/bin/sh
rirs="/var/cache/delegated-apnic-latest"
expanded_rirs="/var/cache/expanded-delegated-apnic-latest"
cache="/var/cache/asn"

get.sh \
		-o "${rirs}" \
		-r 10 \
		"http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest" \
	&& expand-rir-asn.sh \
		-i "${rirs}" \
		-o "${expanded_rirs}" \
		-C "${cache}" \
	&& update-ipset.sh \
		-n chnroute \
		-i "${expanded_rirs}" \
		-c CN
```
