#!/usr/bin/bash

###SETTINGS
SERVER_IP=$(hostname -I)
DB_ROOT_PASSWORD=NotDefaultRootPassword1
DB_USER_PASSWORD=NotDefaultUserPassword2
###SETTINGS

#update to newest packages
yum clean all
yum update -y

#install yum utilities
yum clean all
yum install -y yum-utils

#install mariadb and check if running
yum clean all
yum install -y mariadb mariadb-server
systemctl start mariadb
systemctl enable mariadb
systemctl status mariadb

#first time setup of mariadb
mysql_secure_installation <<MYSQL_SCRIPT

y
$DB_ROOT_PASSWORD
$DB_ROOT_PASSWORD
y
y
y
y
MYSQL_SCRIPT


#Add settings to mariadb config file add restart mariadb
sed  '/\[mysqld\]/a character-set-server = utf8\ncollation-server     = utf8_bin\ninnodb_file_per_table' /etc/my.cnf.d/server.cnf
systemctl restart mariadb

#Install zabbix repo
rpm -Uvh https://repo.zabbix.com/zabbix/5.0/rhel/7/x86_64/zabbix-release-5.0-1.el7.noarch.rpm

#install zabbix server and agent
yum clean all
yum install -y zabbix-server-mysql zabbix-agent

#install centos software collection repo
yum clean all
yum install -y centos-release-scl

#enable zabbix front end repo
yum clean all
yum-config-manager --enable zabbix-frontend

#install zabbix front end packages
yum clean all
yum install -y zabbix-web-mysql-scl zabbix-apache-conf-scl

#create database for zabbix
echo "Creating MySQL user and database"
mysql -uroot -p$DB_ROOT_PASSWORD<<MYSQL_SCRIPT
create database zabbix character set utf8 collate utf8_bin;
create user zabbix@localhost identified by "$DB_USER_PASSWORD";
grant all privileges on zabbix.* to zabbix@localhost;
flush privileges;
exit
MYSQL_SCRIPT

#import base data to zabbix database
zcat /usr/share/doc/zabbix-server-mysql*/create.sql.gz | mysql -uzabbix -p$DB_USER_PASSWORD zabbix

#Set database password in zabbix config file
sed -i "s/\# DBPassword\=/DBPassword\=$DB_USER_PASSWORD/" /etc/zabbix/zabbix_server.conf

#Set japanese timezone in zabbix php conf
sed -i 's/\; php_value\[date\.timezone\] \= Europe\/Riga/php_value\[date\.timezone\] \= Asia\/Tokyo/' /etc/opt/rh/rh-php72/php-fpm.d/zabbix.conf

#restart services
systemctl restart zabbix-server zabbix-agent httpd rh-php72-php-fpm
systemctl enable zabbix-server zabbix-agent httpd rh-php72-php-fpm mariadb

#add entries to firefall
firewall-cmd --add-service=https --zone=public --permanent
firewall-cmd --add-service=http --zone=public --permanent
firewall-cmd --add-port=10050/tcp --zone=public --permanent
firewall-cmd --add-port=10051/tcp --zone=public --permanent
firewall-cmd --reload

#fix the "Zabbix server is not running" error part 1
getsebool -a | grep zabbix
setsebool -P httpd_can_connect_zabbix on
setsebool -P zabbix_can_network on
getsebool -a | grep zabbix

#fix the "Zabbix server is not running" error part 2
for run in {1..3}; do
	grep zabbix_server /var/log/audit/audit.log | audit2allow
	grep zabbix_server /var/log/audit/audit.log | audit2allow -M zabbix-policy
	semodule -i zabbix-policy.pp
	systemctl restart zabbix-server
	systemctl status  zabbix-server
	sleep 5
done

#end message for user
clear
echo "Everything finished!"
echo "Please access Zabbix at the URL below and continue with the post install setup :)"
echo "Zabbix URL: http://$SERVER_IP/zabbix"
echo ""
echo "Database password: $DB_USER_PASSWORD"
echo "Zabbix username: Admin"
echo "Zabbix password: zabbix"
echo ""
echo "DONT FORGET TO CHANGE THE DEFAULT PASSWORD!!!"