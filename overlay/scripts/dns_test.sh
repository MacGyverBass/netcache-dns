#!/bin/bash
echo "Testing all domains found in /etc/bind/cache.conf"
echo "** THIS MAY TAKE A WHILE **"
echo
mkdir -p "/tmp/chroot_nslookup/bin"
cp -p "$(which nslookup)" "/tmp/chroot_nslookup/bin"

ldd "$(which nslookup)" |sed -n "s/^\t\(\/[^ ]*\) .*$/\1/p" |while read lib;do
 mkdir -p "/tmp/chroot_nslookup/$(dirname "${lib}")"
 cp -p "${lib}" "/tmp/chroot_nslookup${lib}"
done

let "intPass=0"
let "intFail=0"
let "intTotal=0"
Service=""
while read service_domain;do
 if [ "${Service}" != "${service_domain% *}" ];then
  Service="${service_domain% *}"
  echo "  ${Service}"
 fi
 Domain="${service_domain#* }"
 Cache_IP="$(chroot "/tmp/chroot_nslookup" "/bin/nslookup" "${Domain}" 2>&1 |sed -n "s/^Address 1: //p")"
 Actual_IP="$(nslookup "${Domain}" 2>&1 |sed -n "s/^Address 1: //p")"
 if [ "${Cache_IP}" != "${Actual_IP}" ];then
  echo -n "+ "
  let "intPass++"
 else
  echo -n "- "
  let "intFail++"
 fi
 echo -e "${Domain}"
 let "intTotal++"
done <<<$(sed -n "s/^zone \"\([^\"]*\)\" in .*\/\([^\"]*\)\.db\".*$/\2 \1/p" "/etc/bind/cache.conf")

rm -rf "/tmp/chroot_nslookup"

echo
echo -e "Passed: ${intPass}\tFailed: ${intFail}\tTotal: ${intTotal}"

