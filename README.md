# Expand the `asn` records into `ipv4`/`ipv6` records in RIRs

## How to use:

```sh
#!/bin/sh
rirs="/var/tmp/delegated-apnic-latest"
expanded_rirs="/var/tmp/expanded-delegated-apnic-latest"
cache="/var/tmp/asn"

get-delegated-apnic-latest.sh \
		-o "${rirs}" \
		-r 10 \
	&& expand-rir-asn.sh \
		-i "${rirs}" \
		-o "${expanded_rirs}" \
		-c "${cache}" \
	&& update-ipset.sh \
		-n chnroute \
		-i "${expanded_rirs}" \
		-c CN
```
