#!/usr/bin/bash
#Source: https://catonrug.blogspot.com/2019/03/snmp-traps-zabbix-server-centos.html

###SETTINGS
SNMP_COMMUNITY=test3
###SETTINGS


#Make sure there is a firewall exception to accept traffic from UDP 162:
firewall-cmd --add-port=162/udp --permanent
firewall-cmd --reload

#Check the mode of SELinux:
getenforce

#If you have 'Enforced' then set it to 'Permissive' for a moment:
setenforce 0

#Install SNMP trap listener:
yum clean all
yum install -y net-snmp-utils net-snmp-perl net-snmp

#Enable and start the service:
systemctl enable snmptrapd
systemctl start snmptrapd

#Service must be running:
systemctl status snmptrapd

#Install 'netstat' command:
yum clean all
yum -y install net-tools

#Check if trap listener is up and listening at address '0.0.0.0':
netstat -tulpn | grep 162

#Install perl script which will transform the trap suitable for Zabbix software:
cd /usr/bin
curl "https://git.zabbix.com/projects/ZBX/repos/zabbix/raw/misc/snmptrap/zabbix_trap_receiver.pl?at=refs%2Fheads%2Fmaster" -o zabbix_trap_receiver.pl 
chmod +x zabbix_trap_receiver.pl

#Locate where the script will pass the traps further:
grep "zabbix_traps.tmp" /usr/bin/zabbix_trap_receiver.pl

#Whitelist allowed communities:
cat <<'EOF'> /etc/snmp/snmptrapd.conf
authCommunity execute $SNMP_COMMUNITY
perl do "/usr/bin/zabbix_trap_receiver.pl";
EOF

sed -i "s/\$SNMP_COMMUNITY/$SNMP_COMMUNITY/" /etc/snmp/snmptrapd.conf

#Restart SNMP trap daemon:
systemctl restart snmptrapd && systemctl status snmptrapd

#Check if '/tmp' dir does not contain 'zabbix_traps.tmp':
ls -l /tmp | grep "zabbix_traps.tmp"

#If file exists, then remove it:
rm /tmp/zabbix_traps.tmp

#Simulate test trap coming from community $SNMP_COMMUNITY:
snmptrap -v 1 -c $SNMP_COMMUNITY 127.0.0.1 '.1.3.6.1.6.3.1.1.5.3' '0.0.0.0' 6 33 '55' .1.3.6.1.6.3.1.1.5.3 s "eth0"

#Make sure the file appears:
ls -l /tmp | grep "zabbix_traps.tmp"

#Check content:
cat /tmp/zabbix_traps.tmp

#Enable Zabbix Trapper in "zabbix_server.conf":
conf=$(find / -name "zabbix_server.conf" | grep "/etc/")
echo $conf
cp $conf $conf.`date +%Y%m%d%H%M`
ls -l $conf*

grep "^StartSNMPTrapper=" $conf
if [ $? -eq 0 ]; then
sed -i "s/^StartSNMPTrapper=.*/StartSNMPTrapper=1/" $conf
else
ln=$(grep -n "StartSNMPTrapper=" $conf | egrep -o "^[0-9]+"); ln=$((ln+1))
sed -i "`echo $ln`iStartSNMPTrapper=1" $conf
fi

grep "^SNMPTrapperFile=" $conf
if [ $? -eq 0 ]; then
sed -i "s/^SNMPTrapperFile=.*/SNMPTrapperFile=\/tmp\/zabbix_traps.tmp/" $conf
else
ln=$(grep -n "SNMPTrapperFile=" $conf | egrep -o "^[0-9]+"); ln=$((ln+1))
sed -i "`echo $ln`iSNMPTrapperFile=\/tmp\/zabbix_traps.tmp" $conf
fi

grep -v "^$\|^#" $conf

#Restart Zabbix Server:
systemctl restart zabbix-server

#Check if there is any listener:
ps -aux | grep [s]nmp

#Clear logs and restart services:
> /var/log/zabbix/zabbix_server.log
systemctl restart snmptrapd
systemctl restart zabbix-server

#Check if services are up and running:
systemctl status {snmptrapd,zabbix-server}

#Ckeck if proxy trapper process is started:
grep "snmp trapper" /var/log/zabbix/zabbix_server.log

#Send a test trap:
ls -l /tmp # note down the /tmp/zabbix_traps.tmp do not exist

# send test trap
snmptrap -v 1 -c $SNMP_COMMUNITY 127.0.0.1 '.1.3.6.1.6.3.1.1.5.3' '0.0.0.0' 6 33 '55' .1.3.6.1.6.3.1.1.5.3 s "eth0"
snmptrap -v 1 -c $SNMP_COMMUNITY 127.0.0.1 'IF-MIB::linkDown' '0.0.0.0' 6 33 '55' .1.3.6.1.6.3.1.1.5.3 s "eth0"
snmptrap -v 1 -c $SNMP_COMMUNITY 127.0.0.1 'IF-MIB::linkDown' '0.0.0.0' 6 33 '55' .1.3.6.1.6.3.1.1.5.3 s "enp2s0"

# check the content
cat /tmp/zabbix_traps.tmp

# empty file it there is a lot
> /tmp/zabbix_traps.tmp

# send recovery trap
snmptrap -v 1 -c $SNMP_COMMUNITY 127.0.0.1 '.1.3.6.1.6.3.1.1.5.4' '0.0.0.0' 6 33 '55' .1.3.6.1.6.3.1.1.5.4 s "eth0"
snmptrap -v 1 -c $SNMP_COMMUNITY 127.0.0.1 'IF-MIB::linkUp' '0.0.0.0' 6 33 '55' .1.3.6.1.6.3.1.1.5.4 s "eth0"
snmptrap -v 1 -c $SNMP_COMMUNITY 127.0.0.1 'IF-MIB::linkUp' '0.0.0.0' 6 33 '55' .1.3.6.1.6.3.1.1.5.4 s "enp2s0"

# now the file must exist
ls -l /tmp/zabbix_traps.tmp

#Also the zabbix server log should contain this trap:
cat /var/log/zabbix/zabbix_server.log

#Appendix: Check SELinux errors:
grep denied /var/log/audit/audit.log

#Allow zabbix server to read the mib files:
cat << 'EOF' > /etc/snmp/snmp.conf
mibs :
mibdirs /usr/share/snmp/mibs
mibs +ALL
EOF

systemctl restart {snmptrapd,zabbix-server}

#make sure all mibs end with txt
cd /usr/share/snmp/mibs
#mv ~/mibs.tar .
#tar xvf mibs.tar
#rm mibs.tar
ls *.txt

#If trap has been tested locally as in this example there may be a situation when everything has been blocked in
#/etc/hosts.deny

#In this case we must install exception in:
#/etc/hosts.allow