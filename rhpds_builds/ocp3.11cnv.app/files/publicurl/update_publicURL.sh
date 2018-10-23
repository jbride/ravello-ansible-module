#!/bin/bash
# This script should be placed under /usr/local/bin made executable
# and ran via systemd service fixpublicurl 

function wait_for_host()
{
    count=0
    while test $count -lt 100; do
        nc -w 3 $1 22 </dev/null >/dev/null 2>&1 && break
        count=$((count+1))
        sleep 60
    done
    echo "Host $1 is up after $count attempts"
}

bastion="bastion.example.com"
ocpver="3.10"

cfg_dir="/etc/origin/master"
master_cfg="$cfg_dir/master-config.yaml"
console_cfg="$cfg_dir/webconsole-config.yaml"

myGUID=`hostname|cut -f2 -d-|cut -f1 -d.`

wait_for_host master00.example.com
masterExtIP=`ssh -oStrictHostKeyChecking=no master00.example.com curl -s http://www.opentlc.com/getip`
wait_for_host infranode00.example.com
infranodeExtIP=`ssh -oStrictHostKeyChecking=no infranode00.example.com curl -s http://www.opentlc.com/getip`

echo "Updating public URLs"

# Just a couple of functions for motd change
# could be written with 'case' or 'if's but this is easier to read and change

function dev_motd {

cp /etc/motd /etc/motd.orig
cat << EOF >/etc/motd
#####################################################################################
      Welcome to Red Hat Openshift Container Platform $ocpver Workshop On RHPDS
                              *** DEVELOPMENT MODE ***
#####################################################################################
Information about Your current environment:

OCP WEB UI access via IP: https://$masterExtIP
Wildcard FQDN for apps: *.$infranodeExtIP.xip.io


EOF
}

function prod_motd {

cp /etc/motd /etc/motd.orig
cat << EOF >/etc/motd
#####################################################################################
      Welcome to Red Hat Openshift Container Platform $ocpver Workshop On RHPDS
#####################################################################################
Information about Your current environment:

Your GUID: $myGUID
OCP WEB UI access via IP: https://master00-$myGUID.generic.opentlc.com
Wildcard FQDN for apps: *.apps-$myGUID.generic.opentlc.com


EOF
}


shopt -s nocasematch
if [ $? -ne 0 ]
then
        echo "Failed to get external IP"
        exit 1
fi

ocp_config="/root/.kube/config"
datest=`date +%Y%m%d%H%M`

rm -rf /root/.kube
scp -pr master00.example.com:.kube /root/

# Setting a router subdomain based on deployment (DEV vs. RHPDS)
echo "Master Ext IP: $masterExtIP"
echo "Infranode Ext IP: $infranodeExtIP"
echo "GUID: $myGUID"

TMP=/tmp/.cfg.$$

if [[ $myGUID == 'repl' ]]
then
  mpu="https:\/\/$masterExtIP"
  apu="https:\/\/$masterExtIP\/console\/"
  cpu=$apu
  pu=$apu
  sd="$infranodeExtIP.xip.io"
  hawk="hawkular-metrics.$sd"
  kibana="kibana.$sd"
  dev_motd
else
  mpu="https:\/\/master00-$myGUID.generic.opentlc.com"
  apu="https:\/\/master00-$myGUID.generic.opentlc.com\/console\/"
  cpu=$apu
  pu=$apu
  sd="apps-$myGUID.generic.opentlc.com"
  hawk="hawkular-metrics.$sd"
  kibana="kibana.$sd"
  prod_motd
fi

ssh master00.example.com "oc -n openshift-web-console get configmap/webconsole-config -o yaml > $console_cfg"

for CFG in $master_cfg $console_cfg;do
  scp master00.example.com:$CFG $TMP
  ssh master00.example.com cp "$CFG $CFG.$datest"
  sed -i "s/masterPublicURL: .*$/masterPublicURL: $mpu/" $TMP
  sed -i "s/assetPublicURL: .*$/assetPublicURL: $apu/" $TMP
  sed -i "s/consolePublicURL: .*$/consolePublicURL: $cpu/" $TMP
  sed -i "s/publicURL: .*$/publicURL: $pu/" $TMP
  sed -i "s/subdomain: .*$/subdomain: $sd/" $TMP
  sed -i "s/metricsPublicURL: .*$/metricsPublicURL: https:\/\/$hawk\/hawkular\/metrics/" $TMP
  sed -i "s/loggingPublicURL: .*$/loggingPublicURL: https:\/\/$kibana/" $TMP
  scp $TMP master00.example.com:$CFG
  rm -f $TMP
done

echo "Recreating openshift-web-console pod"
ssh master00.example.com "oc -n openshift-web-console replace -f $console_cfg"
ssh master00.example.com "oc -n openshift-web-console delete `oc -n openshift-web-console get pod -o name`"

echo "Updating Hawkular metrics and Kibana logging routes"
oc -n openshift-infra patch route hawkular-metrics -p '{"spec":{"host":"'"$hawk"'"}}'
oc -n openshift-logging patch route logging-kibana -p '{"spec":{"host":"'"$kibana"'"}}'

echo "Rebooting master"
ssh master00.example.com "reboot"
