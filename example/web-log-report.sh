#!/usr/local/bin/sgsh -s /usr/bin/bash
#
# SYNOPSIS Web log reporting
# DESCRIPTION
# Creates a report for a fixed-size web log file read from the standard input.
# Demonstrates the processing reuse and the combined use of stores and streams.
# Used to measure throughput increase achieved through parallelism.
#
#  Copyright 2013 Diomidis Spinellis
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

# Output the top X elements of the input by the number of their occurrences
# X is the first argument
toplist()
{
	uniq -c | sort -rn | head -$1
}

# Output the argument as a section header
header()
{
	echo
	echo "$1"
	echo "$1" | sed 's/./-/g'
}

scatter |{

	# Number of transferred bytes
	-|  awk '{s += $NF} END {print s}' |store:nXBytes

	# Number of log file bytes
	-|  wc -c |store:nLogBytes

	# Host names
	-|  awk '{print $1}' |{
		# Number of accesses
		-| wc -l |store:nAccess

		# Sorted hosts
		-| sort |{

			# Unique hosts
			-| uniq |{
				# Number of hosts
				-| wc -l |store:nHosts

				# Number of TLDs
				-| awk -F. '$NF !~ /[0-9]/ {print $NF}' |
					sort -u | wc -l |store:nTLD
			|}

			# Top 10 hosts
			-| toplist 10 |>/stream/top10HostsByN
		|}

		# Top 20 TLDs
		-| awk -F. '$NF !~ /^[0-9]/ {print $NF}' |
			sort | toplist 20 |>/stream/top20TLD

		# Domains
		-| awk -F. 'BEGIN {OFS = "."}
		            $NF !~ /^[0-9]/ {$1 = ""; print}' | sort |{
			# Number of domains
			-| uniq | wc -l |store:nDomain

			# Top 10 domains
			-| toplist 10 |>/stream/top10Domain
		|}
	|}

	# Hosts by volume
	-| awk '    {bytes[$1] += $NF}
		END {for (h in bytes) print bytes[h], h}' |
		sort -rn |
		head -10 |>/stream/top10HostsByVol

	# Sorted page name requests
	-| awk '{print $7}' | sort |{

		# Top 20 area requests (input is already sorted)
		-| awk -F/ '{print $2}' | toplist 20 |>/stream/top20Area

		# Number of different pages
		-| uniq | wc -l |store:nPages

		# Top 20 requests
		-| toplist 20 |>/stream/top20Request
	|}

	# Access time: dd/mmm/yyyy:hh:mm:ss
	-| awk '{print substr($4, 2)}' |{

		# Just dates
		-| awk -F: '{print $1}' |{

			# Number of days
			-| uniq | wc -l |store:nDays

			-| uniq -c |>/stream/accessByDate

			# Accesses by day of week
			-| sed 's|/|-|g' |
				date -f - +%a |
				sort |
				uniq -c |
				sort -rn |>/stream/accessByDoW
		|}

		# Hour
		-| awk -F: '{print $2}' |
			sort |
			uniq -c |>/stream/accessByHour
	|}

|} gather |{

cat <<EOF
			WWW server statistics
			=====================

Summary
-------
Number of accesses: $(store:nAccess)
Number of Gbytes transferred: $(expr $(store:nXBytes) / 1024 / 1024 / 1024)
Number of hosts: $(store:nHosts)
Number of domains: $(store:nDomain)
Number of top level domains: $(store:nTLD)
Number of different pages: $(store:nPages)
Accesses per day: $(expr $(store:nAccess) / $(store:nDays))
MBytes per day: $(expr $(store:nXBytes) / $(store:nDays) / 1024 / 1024)
MBytes log file size: $(expr $(store:nLogBytes) / 1024 / 1024)

EOF

header 'Top 20 Requests'
cat /stream/top20Request

header 'Top 20 Area Requests'
cat /stream/top20Area

header 'Top 10 Hosts'
cat /stream/top10HostsByN

header 'Top 10 Hosts by Transfer'
cat /stream/top10HostsByVol

header 'Top 10 Domains'
cat /stream/top10Domain

header 'Top 20 Level Domain Accesses'
cat /stream/top20TLD

header 'Accesses by Day of Week'
cat /stream/accessByDoW

header 'Accesses by Local Hour'
cat /stream/accessByHour

header 'Accesses by Date'
cat /stream/accessByDate
|}
