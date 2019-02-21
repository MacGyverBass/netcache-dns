#!/bin/bash
set -e
cat << 'BANNER'

_____   __    ______________            ______
___  | / /______  /__  ____/_____ _________  /______
__   |/ /_  _ \  __/  /    _  __ `/  ___/_  __ \  _ \
_  /|  / /  __/ /_ / /___  / /_/ // /__ _  / / /  __/
/_/ |_/  \___/\__/ \____/  \__,_/ \___/ /_/ /_/\___/

BANNER


# Provide Defaults
USE_GENERIC_CACHE="${USE_GENERIC_CACHE:-"false"}" #Using single IP for caching, which must be specified using LANCACHE.
ENABLE_DNSSEC_VALIDATION="${ENABLE_DNSSEC_VALIDATION:-"false"}" #Enable DNS Security Validation

# Static Entries
CACHE_DOMAINS_REPO="https://raw.githubusercontent.com/uklans/cache-domains/master/"
NAMED_OPTIONS="/etc/bind/named.conf.options"
CACHE_CONF="/etc/bind/cache.conf"
ZONEPATH="/etc/bind/cache/" #Location where the ${ServiceName}.db files will be kept.
DNSRESOLV="/etc/resolv.conf"
BindUsername="named" # "named" or "bind" depending on bind install.

# Helpful function(s)
fnSplitStrings () { # Removes comments, splits into lines from comma/space delimited strings, and removes any blank lines.
 echo "$1" |sed "s/[, ]*#.*$//;s/[, ]/\n/g" |sed "/^$/d"
}
fnReadEnvironmentVariable () { # Given a string, finds a matching environment variable value using a case-insensitive search.
 printenv "$(env |sed -n "s/^\($1\)=.*$/\1/Ip"|head -n1)" || true
}

# DNS Upstream Setup
DNS_FORWARDERS="" # Used for named.conf.options
setupDNS () { # setupDNS "Comma-Separated-IPs"
 if ! [ -z "${UPSTREAM_DNS}" ];then # String containing DNS entries, comma/space delimited.
  cat /dev/null > "${DNSRESOLV}"
  fnSplitStrings "${UPSTREAM_DNS}" |while read DNS_IP;do
   echo "+ Adding nameserver: ${DNS_IP}"
   echo "nameserver ${DNS_IP}" >> "${DNSRESOLV}"
  done
  DNS_FORWARDERS="$(fnSplitStrings "${UPSTREAM_DNS}" |paste -sd ';' - );" # Semicolon delimited DNS IPs for named.conf.options
  echo
 fi
}

# DNS Server Setup
addServiceComment () { # addServiceComment "Comment String" "TRUE if # requested"
 Comment="$1" # String
 UseHash="$2" # Use "#" for comment prefix, otherwise "//" is used.  (True/False, default is false)  NOTE: Multi-line comments will still use /* ... */ format.
 if [[ "${Comment}" == *"\n"* ]];then
  echo "/*\n${Comment}\n*/" >> "${CACHE_CONF}"
 elif [ "${UseHash^^}" == "TRUE" ];then
  echo "#${Comment}" >> "${CACHE_CONF}"
 else
  echo "//${Comment}" >> "${CACHE_CONF}"
 fi
}
addService () { # addService "Service Name" "Service-IP" "Comma-Separated-Domains"
 ServiceName="$1" # Name of the given service.
 ServiceIP="$2" # String containing the destination IP to be given back to the client PC.
 Domains="$3" # String containing domain name entries, comma/space delimited.
 
 if [ -z "${ServiceName}" ]||[ -z "${ServiceIP}" ]||[ -z "${Domains}" ];then # All fields are required.
  echo "# Error adding service \"${ServiceName}\".  All arguments are required." >&2
  return
 fi
 echo "+ Adding service \"${ServiceName}\".  Will resolve to: ${ServiceIP}"

 fnSplitStrings "${Domains}" |sed "s/^\*\.//" |sort -u |while read Domain;do
  cat << EOL >> "${CACHE_CONF}"
zone "${Domain}" in { type master; file "${ZONEPATH%/}/${ServiceName}.db";};
EOL
 done
 echo >> "${CACHE_CONF}"

 # SOA RName (Email address encoded as a name)
 SOA_RName="noreply.example.com."
 # Zone Information
 let TTL=60*10
 # Start of Authority Resource Record (SOA RR)
 let SOA_Serial=`date +%Y%m%d%H` #yyyymmddHH (year,month,day,hour)
 let SOA_Refresh=60*60*24*7
 let SOA_Retry=60*10
 let SOA_Expiry=60*10
 let SOA_TTL=60*10

 cat << EOF > "${ZONEPATH%/}/${ServiceName}.db"
\$TTL    ${TTL}
@       IN  SOA ns1 ${SOA_RName} (
                ${SOA_Serial}
                ${SOA_Refresh}
                ${SOA_Retry}
                ${SOA_Expiry}
                ${SOA_TTL}
				)
@       IN  NS  ns1
ns1     IN  A   ${ServiceIP}

@       IN  A   ${ServiceIP}
*       IN  A   ${ServiceIP}
EOF
}


# Startup Checks
if [ "${USE_GENERIC_CACHE}" == "true" ]; then # If USE_GENERIC_CACHE=true then LANCACHE_IP must be provided.
  if [ -z "${LANCACHE_IP}" ]; then
    echo "If you are using USE_GENERIC_CACHE then you must set LANCACHE_IP" >&2
    exit 1
  fi
  cat << MESSAGE

----------------------------------------------------------------------
Using Generic Server: ${LANCACHE_IP}
Make sure you are using a load balancer at ${LANCACHE_IP}
It is not recommended to use a single cache server for all services
 as you will get cache clashes.
----------------------------------------------------------------------

MESSAGE
else # If USE_GENERIC_CACHE=false then LANCACHE_IP must NOT be provided.
  if ! [ -z "${LANCACHE_IP}" ]; then
    echo "If you are using LANCACHE_IP then you must set USE_GENERIC_CACHE=true" >&2
    exit 1
  fi
fi


# Setup DNS Upstream
setupDNS

# DNS Security Validation (for named.conf.options)
DNSSEC_VALIDATION="${DNSSEC_VALIDATION:-"no"}"
if [ "${ENABLE_DNSSEC_VALIDATION}" == "true" ];then
 echo "* Enabling dnssec validation"
 DNSSEC_VALIDATION="auto"
fi

# DNS Upstream Forwarders (for named.conf.options)
NAMED_FORWARDERS="# No DNS forwarders"
if ! [ -z "${DNS_FORWARDERS}" ];then
 NAMED_FORWARDERS="forwarders { ${DNS_FORWARDERS} };"
fi

# Generate named.conf.options file
LOGGING_CHANNELS="default general database security config resolver xfer-in xfer-out notify client unmatched queries network update dispatch dnssec lame-servers"
cat << SECTION > "${NAMED_OPTIONS}"
options {
        directory "/var/cache/bind";
        dnssec-validation ${DNSSEC_VALIDATION};
        auth-nxdomain no;    # conform to RFC1035
        allow-recursion { any; };
        allow-query { any; };
        allow-query-cache { any; };
        listen-on { any; };
        listen-on-v6 { any; };
        ${NAMED_FORWARDERS}
};
SECTION
echo "logging {" >>  "${NAMED_OPTIONS}"
for channel_type in ${LOGGING_CHANNELS};do
 cat << SECTION >> "${NAMED_OPTIONS}"
    channel ${channel_type}_file {
        file "/var/log/named/${channel_type}.log" versions 3 size 5m;
        severity dynamic;
        print-time yes;
    };
SECTION
done
for channel_type in ${LOGGING_CHANNELS};do
 cat << SECTION >> "${NAMED_OPTIONS}"
    category ${channel_type} { ${channel_type}_file; };
SECTION
done
echo "};" >>  "${NAMED_OPTIONS}"

# Reset Bind Cache Configuration
rm -f "${CACHE_CONF}"
touch "${CACHE_CONF}"


## UK-LANs Cache-Domain Lists
echo "* Bootstrapping DNS from ${CACHE_DOMAINS_REPO}"
curl -s "${CACHE_DOMAINS_REPO%/}/cache_domains.json" |jq -c '.cache_domains[]' |while read obj;do
 Service_Name=`echo "${obj}"|jq -r '.name'`
 Service_Desc=`echo "${obj}"|jq -r '.description'`
 if (! (env |grep -iq "^DISABLE_${Service_Name^^}=true") && [ -z "${ONLYCACHE}" ])||[[ " ${ONLYCACHE^^} " == *" ${Service_Name^^} "* ]];then # Continue only if DISABLE_${Service} is not true and ONLYCACHE is empty.  Or continue if service is provided in the ONLYCACHE variable.  (Note that a service in ONLYCACHE will ignore the DISABLE_${Service} variable.)
  if [ -z "${LANCACHE_IP}" ]; then
   Service_IP="$(fnReadEnvironmentVariable "${Service_Name^^}CACHE_IP")"
  else
   Service_IP="${LANCACHE_IP}"
  fi
  if [ -z "${Service_IP}" ];then
   echo "# ${Service_Name^^}CACHE_IP not provided." >&2
  else
   addServiceComment "${Service_Name}"
   if ! [ -z "${Service_Desc}" ];then
    addServiceComment " ${Service_Desc}"
   fi
   echo "${obj}" |jq -r '.domain_files[]' |while read domain_file;do
    addServiceComment " (${domain_file})" "true"
    Service_Domains="$(curl -s "${CACHE_DOMAINS_REPO%/}/${domain_file}")"
    addService "${Service_Name}" "${Service_IP}" "${Service_Domains}"
   done
  fi
 fi
done


## Custom Domain Lists
if (env |grep -iq "^CUSTOMCACHE=") && ! [ -z "${CUSTOMCACHE}" ];then
 echo "* Adding custom services..."
 for Service_Name in ${CUSTOMCACHE};do
  if [ -z "${LANCACHE_IP}" ]; then
   Service_IP="$(fnReadEnvironmentVariable "${Service_Name^^}CACHE_IP")"
  else
   Service_IP="${LANCACHE_IP}"
  fi
  Service_Source="$(fnReadEnvironmentVariable "${Service_Name^^}CACHE")"
  if [ -z "${Service_IP}" ];then
   echo "# ${Service_Name^^}CACHE_IP not provided." >&2
  elif [ -z "${Service_Source}" ];then
   echo "# ${Service_Name^^}CACHE not provided." >&2
  else
   addServiceComment "${Service_Name}"
   addService "${Service_Name}" "${Service_IP}" "${Service_Source}"
  fi
 done
fi


# Test the Bind configuration
echo "* Checking Bind9 configuration"
if ! /usr/sbin/named-checkconf /etc/bind/named.conf ;then
 echo "# Problem with Bind9 configuration" >&2
 exit 1
fi

# Execute and display logs
echo "* Running Bind9 w/logging"
tail -F /var/log/named/general.log /var/log/named/default.log /var/log/named/queries.log &
/usr/sbin/named ${BindUsername:+-u ${BindUsername}} -c /etc/bind/named.conf -f
BEC=$?
if ! [ $BEC = 0 ]; then
 echo "# Bind9 exited with ${BEC}" >&2
 exit ${BEC} #exit with the same exit code as bind9
fi
