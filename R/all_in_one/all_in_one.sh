function res () {
    if [ $? -eq 0 ]
    then
        echo -e "\033[32m $@ sucessed. \033[0m"
    else
        echo -e "\033[41;37m $@ failed. \033[0m"
        exit
    fi
}



function add_line() {
    local file_content=$2
    local add_content=$3
    local init_file=$1
    local line_number=`grep -n "$file_content" $init_file`
    local line_number=${line_number%%:*}
    for n in $line_number
    do
        sed -i "${n} a$add_content"  $init_file
    done
}





function pre_install() {


    HOSTNMAE=`hostname`
    var=`cat /root/queens_all_in_one/conf |grep ip`
    IP=${var#*=}

#echo $IP

    if [ ${HOSTNAME}x != controllerx ]
    then
        echo "请设置主机名为controller"
        exit
    fi

    cat /etc/hosts |grep controller >>/dev/null
    if [ $? -eq 1 ]
    then
        echo $IP controller >>/etc/hosts
#echo "success"
    fi

}



function ntp_install () {
    var=`cat /root/queens_all_in_one/conf |grep ip`
    IP=${var#*=}

    apt install chrony -y >>/dev/null
    res "安装ntp软件包"

   # sed -i "s/3.centos.pool.ntp.org/controller/g" /etc/chrony/chrony.conf
    echo server controller iburst >> /etc/chrony/chrony.conf	
    IPSEG=`echo ${IP%\`echo $IP|cut -d \. -f 4\`*}`
echo $IPSEG
   # sed -i "s/#allow 192.168.0.0\/16/allow ${IPSEG}0\/24/g" /etc/chrony.conf
    echo allow ${IPSEG}0\/24 >> /etc/chrony/chrony.conf
    service chrony restart 
    res "启动ntp服务"
}


function client_install () {
    apt install software-properties-common
    add-apt-repository cloud-archive:queens
    apt update && apt dist-upgrade
    apt install python-openstackclient -y >>/dev/null
    res "安装OpenStack客户端"
}




function mariadb_install () {
    var=`cat /root/queens_all_in_one/conf |grep ip`
    IP=${var#*=}

    varp=`cat /root/queens_all_in_one/conf |grep password`
    PASS=${varp#*=}

    apt install mariadb-server python-pymysql -y >>/dev/null
    res "安装数据库软件包"

    if [ ! -f  /etc/mysql/mariadb.conf.d/99-openstack.cnf ]
    then
        CONFIGFILE="/etc/mysql/mariadb.conf.d/99-openstack.cnf"
        echo "[mysqld]" >>$CONFIGFILE
        echo "bind-address = ${IP}" >>$CONFIGFILE
        echo "default-storage-engine = innodb" >>$CONFIGFILE
        echo "innodb_file_per_table = on" >>$CONFIGFILE
        echo "max_connections = 4096" >>$CONFIGFILE
        echo "collation-server = utf8_general_ci" >>$CONFIGFILE
        echo "character-set-server = utf8" >>$CONFIGFILE
    fi

    service mysql restart
    res "启动数据库服务"

    if [ ! -f /root/queens_all_in_one/sql.tag ]
    then
    mysql_secure_installation <<EOF

    y
    $PASS
    $PASS
    y
    y
    y
    y
EOF
    touch /root/queens_all_in_one/sql.tag
    fi
    res "设置数据库密码$PASS"
}




function rabbitmq_install () {
    varp=`cat /root/queens_all_in_one/conf |grep password`
    PASS=${varp#*=}

    apt install rabbitmq-server -y >>/dev/null
    res "安装消息队列软件包"

    rabbitmqctl add_user openstack $PASS >>/dev/null
    rabbitmqctl set_permissions openstack ".*" ".*" ".*" >>/dev/null
    res "设置消息队列权限"
}




function memcached_install () {
    var=`cat /root/queens_all_in_one/conf |grep ip`
    IP=${var#*=}

    apt install memcached python-memcached -y >>/dev/null
    res "安装memcached软件包"

    sed -i "s/-l 127.0.0.1/-l $IP/g" /etc/memcached.conf

    service memcached restart
    res "启动memcached服务"
}




function etcd_install () {
    apt install etcd -y >>/dev/null
    res "安装etcd软件包"

    sed -i "s/# ETCD_NAME=\"hostname\"/ETCD_NAME=\"controller\"/g" /etc/default/etcd
    sed -i "s/# ETCD_DATA_DIR=\"\/var\/lib\/etcd\/default\"/ETCD_DATA_DIR=\"\/var\/lib\/etcd\"/g" /etc/default/etcd 
    sed -i "s/# ETCD_INITIAL_CLUSTER_STATE=\"existing\"/ETCD_INITIAL_CLUSTER_STATE=\"new\"/g" /etc/default/etcd
    sed -i "s/# ETCD_INITIAL_CLUSTER_TOKEN=\"etcd-cluster\"/ETCD_INITIAL_CLUSTER_TOKEN=\"etcd-cluster-01\"/g" /etc/default/etcd
    sed -i "s/# ETCD_INITIAL_CLUSTER=\"default=http:\/\/localhost:2380,default=http:\/\/localhost:7001\"/ETCD_INITIAL_CLUSTER=\"controller=http:\/\/10.0.0.5:2380\"/g" /etc/default/etcd
    sed -i "s/# ETCD_INITIAL_ADVERTISE_PEER_URLS=\"http:\/\/localhost:2380,http:\/\/localhost:7001\"/ETCD_INITIAL_ADVERTISE_PEER_URLS=\"http:\/\/10.0.0.5:2380\"/g" /etc/default/etcd
    sed -i "s/# ETCD_ADVERTISE_CLIENT_URLS=\"http:\/\/localhost:2379,http:\/\/localhost:4001\"/ETCD_ADVERTISE_CLIENT_URLS=\"http:\/\/10.0.0.5:2379\"/g" /etc/default/etcd
    sed -i "s/# ETCD_LISTEN_PEER_URLS=\"http:\/\/localhost:2380,http:\/\/localhost:7001\"/ETCD_LISTEN_PEER_URLS=\"http:\/\/0.0.0.0:2380\"/g" /etc/default/etcd
    sed -i "s/# ETCD_LISTEN_CLIENT_URLS=\"http:\/\/localhost:2379,http:\/\/localhost:4001\"/ETCD_LISTEN_CLIENT_URLS=\"http:\/\/10.0.0.5:2379\"/g" /etc/default/etcd


    systemctl enable etcd >>/dev/null
    systemctl start etcd >>/dev/null
    res "启动etcd服务"
}





function keystone_install () {
    varp=`cat /root/queens_all_in_one/conf |grep password`
    PASS=${varp#*=}

    mysql -uroot -p${PASS} -e "show databases;" >test
    DATABASEKEYSTONE=`cat test | grep keystone`
    rm -rf test
    if [ ${DATABASEKEYSTONE}x = keystonex ]
    then
        res "已经创建keystone数据库"
    else
        mysql -uroot -p$PASS -e "CREATE DATABASE keystone;" && mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$PASS';" && mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$PASS';"
        res "创建keystone数据库"
    fi

    apt install keystone apache2 libapache2-mod-wsgi -y >>/dev/null
    res "安装keystone软件包"

cp /etc/keystone/keystone.conf /etc/keystone/keystone.conf.bak

    add_line /etc/keystone/keystone.conf "\[database\]" "connection\ =\ mysql+pymysql:\/\/glance:$PASS@controller\/keystone"

    add_line /etc/keystone/keystone.conf "\[token\]" "provider = fernet"

    su -s /bin/sh -c "keystone-manage db_sync" keystone >>/dev/null
    res "同步keystone数据库"

    keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone >>/dev/null
    keystone-manage credential_setup --keystone-user keystone --keystone-group keystone >>/dev/null

    keystone-manage bootstrap --bootstrap-password $PASS \
        --bootstrap-admin-url http://controller:5000/v3/ \
        --bootstrap-internal-url http://controller:5000/v3/ \
        --bootstrap-public-url http://controller:5000/v3/ \
        --bootstrap-region-id RegionOne >>/dev/null

    echo "ServerName controller" >> /etc/apache2/apache2.conf

    service apache2 restart >>/dev/null

    res "启动Apache服务"

    export OS_USERNAME=admin
    export OS_PASSWORD=$PASS
    export OS_PROJECT_NAME=admin
    export OS_USER_DOMAIN_NAME=Default
    export OS_PROJECT_DOMAIN_NAME=Default
    export OS_AUTH_URL=http://controller:5000/v3
    export OS_IDENTITY_API_VERSION=3


    EXAMPLE_DOMAIN=`openstack domain list | grep example | awk -F "|" '{print$3}' | awk -F " " '{print$1}'`
    if [ ${EXAMPLE_DOMAIN}x = examplex ]
    then
        echo -e "\033[32m 已经创建相关用户 sucessed. \033[0m"
    else
        openstack domain create --description "An Example Domain" example >>/dev/null
        openstack project create --domain default \
            --description "Service Project" service >>/dev/null
        openstack project create --domain default \
            --description "Demo Project" demo >>/dev/null
        openstack user create --domain default \
            demo --password $PASS >>/dev/null
        openstack role create user >>/dev/null
        openstack role add --project demo --user demo user >>/dev/null
        res "创建相关用户"
    fi

    if [ ! -f  /root/admin-openrc ]
    then
        CONFIGFILE="/root/admin-openrc"
        echo "export OS_PROJECT_DOMAIN_NAME=Default" >>$CONFIGFILE
        echo "export OS_USER_DOMAIN_NAME=Default" >>$CONFIGFILE
        echo "export OS_PROJECT_NAME=admin" >>$CONFIGFILE
        echo "export OS_USERNAME=admin" >>$CONFIGFILE
        echo "export OS_PASSWORD=$PASS" >>$CONFIGFILE
        echo "export OS_AUTH_URL=http://controller:5000/v3" >>$CONFIGFILE
        echo "export OS_IDENTITY_API_VERSION=3" >>$CONFIGFILE
        echo "export OS_IMAGE_API_VERSION=2" >>$CONFIGFILE
    fi

    if [ ! -f  /root/demo-openrc ]
    then
        CONFIGFILE="/root/demo-openrc"
        echo "export OS_PROJECT_DOMAIN_NAME=Default" >>$CONFIGFILE
        echo "export OS_USER_DOMAIN_NAME=Default" >>$CONFIGFILE
        echo "export OS_PROJECT_NAME=demo" >>$CONFIGFILE
        echo "export OS_USERNAME=demo" >>$CONFIGFILE
        echo "export OS_PASSWORD=$PASS" >>$CONFIGFILE
        echo "export OS_AUTH_URL=http://controller:5000/v3" >>$CONFIGFILE
        echo "export OS_IDENTITY_API_VERSION=3" >>$CONFIGFILE
        echo "export OS_IMAGE_API_VERSION=2" >>$CONFIGFILE
    fi

    res "创建环境变量文件"
}


function glance_install () {
    varp=`cat /root/queens_all_in_one/conf |grep password`
    PASS=${varp#*=}

    mysql -uroot -p${PASS} -e "show databases ;" >test
    DATABASENAME=`cat test | grep glance`
    rm -rf test
    if [ ${DATABASENAME}x = glancex ]
    then
        mysql -uroot -p$PASS -e "drop database glance;"
    fi

    mysql -uroot -p$PASS -e "CREATE DATABASE glance;" && mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$PASS';" && mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$PASS';"
    res "创建glance数据库"

    . /root/admin-openrc

    USER_GLANCE=`openstack user list | grep glance | awk -F "|" '{print$3}' | awk -F " " '{print$1}'`
    if [ ${USER_GLANCE}x = glancex ]
    then
        #echo "123123214000"
        echo -e "\033[32m 已经创建glance用户 sucessed. \033[0m"
    else
        openstack user create --domain default glance --password $PASS >>/dev/null
        openstack role add --project service --user glance admin
        openstack service create --name glance \
            --description "OpenStack Image" image >>/dev/null
        openstack endpoint create --region RegionOne \
            image public http://controller:9292 >>/dev/null
        openstack endpoint create --region RegionOne \
            image internal http://controller:9292 >>/dev/null
        openstack endpoint create --region RegionOne \
            image admin http://controller:9292 >>/dev/null
        res "创建glance用户"
    fi

    apt install glance -y >>/dev/null
    res "安装glance软件包"
   # add_line /etc/glance/glance-api.conf "\[database\]" "connection\ =\ mysql+pymysql:\/\/glance:$PASS@controller\/glance"
    sed -i "s/connection\ =\ sqlite:\/\/\/\/var\/lib\/glance\/glance.sqlite/connection\ =\ mysql+pymysql:\/\/glance:$PASS@controller\/glance/g" /etc/glance/glance-api.conf
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]" "auth_uri = http://controller:5000"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]" "auth_url = http://controller:5000"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]" "memcached_servers = controller:11211"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]" "auth_type = password"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]" "project_domain_name = Default"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]" "user_domain_name = Default"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]" "project_name = service"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]" "username = glance"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]" "password = $Pass"


    add_line /etc/glance/glance-api.conf "\[paste_deploy\]" "flavor = keystone"

    add_line /etc/glance/glance-api.conf "\[glance_store\]" "stores = file,http"
    add_line /etc/glance/glance-api.conf "\[glance_store\]" "default_store = file"
    add_line /etc/glance/glance-api.conf "\[glance_store\]" "filesystem_store_datadir = /var/lib/glance/images/"




   # add_line /etc/glance/glance-registry.conf "\[database\]" "connection\ =\ mysql+pymysql:\/\/glance:$PASS@controller\/glance"
   sed -i "s/connection\ =\ sqlite:\/\/\/\/var\/lib\/glance\/glance.sqlite/connection\ =\ mysql+pymysql:\/\/glance:$PASS@controller\/glance/g" /etc/glance/glance-registry.conf 

    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]" "auth_uri = http://controller:5000"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]" "auth_url = http://controller:5000"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]" "memcached_servers = controller:11211"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]" "auth_type = password"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]" "project_domain_name = Default"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]" "user_domain_name = Default"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]" "project_name = service"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]" "username = glance"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]" "password = &PASS"


    add_line /etc/glance/glance-registry.conf "\[paste_deploy\]" "flavor = keystone"
    su -s /bin/sh -c "glance-manage db_sync" glance >>/dev/null
    res "同步glance数据库"

    service glance-registry restart >>/dev/null
    service glance-api restart >>/dev/null
    res "启动glance服务"

    . /root/admin-openrc

    openstack image list |grep cirros
    if [ $? -eq 1 ]
    then
        rm -rf /var/lib/glance/images/*
        wget -P /root http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img
        openstack image create "cirros" \
            --file /root/cirros-0.4.0-x86_64-disk.img \
            --disk-format qcow2 --container-format bare \
            --public >>/dev/null
        res "上传cirros镜像"
    fi

}




function nova_install () {

    varp=`cat /root/queens_all_in_one/conf |grep password`

    PASS=${varp#*=}



    var=`cat /root/queens_all_in_one/conf |grep ip`

    IP=${var#*=}



    mysql -uroot -p${PASS} -e "show databases;" >test

    DATABASENAME=`cat test | grep nova_api`

    rm -rf test

    if [ ${DATABASENAME}x = nova_apix ]

    then

        mysql -uroot -p$PASS -e "drop database nova_api;"

        mysql -uroot -p$PASS -e "drop database nova;"

        mysql -uroot -p$PASS -e "drop database nova_cell0;"

    fi



    mysql -uroot -p$PASS -e "CREATE DATABASE nova_api;" && mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$PASS';" && mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$PASS';"

    mysql -uroot -p$PASS -e "CREATE DATABASE nova;" && mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$PASS';" && mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$PASS';"

    mysql -uroot -p$PASS -e "CREATE DATABASE nova_cell0;" && mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$PASS';" && mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$PASS';"

    res "创建nova数据库"



    . /root/admin-openrc



    USER_NOVA=`openstack user list | grep nova | awk -F "|" '{print$3}' | awk -F " " '{print$1}'`

    if [ ${USER_NOVA}x = novax ]

    then

        echo -e "\033[32m 已经创建nova用户 sucessed. \033[0m"

    else

        openstack user create --domain default nova --password $PASS >>/dev/null

        openstack role add --project service --user nova admin >>/dev/null

        openstack service create --name nova \

            --description "OpenStack Compute" compute >>/dev/null

        openstack endpoint create --region RegionOne \

            compute public http://controller:8774/v2.1 >>/dev/null

        openstack endpoint create --region RegionOne \

            compute internal http://controller:8774/v2.1 >>/dev/null

        openstack endpoint create --region RegionOne \

            compute admin http://controller:8774/v2.1 >>/dev/null

        openstack user create --domain default placement --password $PASS >>/dev/null

        openstack role add --project service --user placement admin >>/dev/null

        openstack service create --name placement --description "Placement API" placement >>/dev/null

        openstack endpoint create --region RegionOne placement public http://controller:8778 >>/dev/null

        openstack endpoint create --region RegionOne placement internal http://controller:8778 >>/dev/null

        openstack endpoint create --region RegionOne placement admin http://controller:8778 >>/dev/null

        res "创建nova相关用户"

    fi



    apt install nova-api nova-conductor nova-consoleauth nova-novncproxy nova-scheduler nova-placement-api

    res "安装nova软件包"

    sed -i "s/connection\ =\ sqlite:\/\/\/\/var\/lib\/nova\/nova_api.sqlite/connection\ =\ mysql+pymysql:\/\/nova:$PASS@controller\/nova_api/g" /etc/nova/nova.conf

    sed -i "s/connection\ =\ sqlite:\/\/\/\/var\/lib\/nova\/nova.sqlite/connection\ =\ mysql+pymysql:\/\/nova:$PASS@controller\/nova/g" /etc/nova/nova.conf

    add_line /etc/nova/nova.conf "\[DEFAULT\]" "transport_url = rabbit://openstack:$PASS@controller"
   
    add_line /etc/nova/nova.conf "\[api\]" "auth_strategy = keystone"

    add_line /etc/nova/nova.conf "\[keystone_authtoken\]" "auth_url = http://controller:5000/v3"
    add_line /etc/nova/nova.conf "\[keystone_authtoken\]" "memcached_servers = controller:11211"
    add_line /etc/nova/nova.conf "\[keystone_authtoken\]" "auth_type = password"
    add_line /etc/nova/nova.conf "\[keystone_authtoken\]" "project_domain_name = default"
    add_line /etc/nova/nova.conf "\[keystone_authtoken\]" "user_domain_name = default"
    add_line /etc/nova/nova.conf "\[keystone_authtoken\]" "project_name = service"
    add_line /etc/nova/nova.conf "\[keystone_authtoken\]" "username = nova"
    add_line /etc/nova/nova.conf "\[keystone_authtoken\]" "password = $PASS"

    add_line /etc/nova/nova.conf "\[DEFAULT\]" "my_ip = $IP"
    add_line /etc/nova/nova.conf "\[DEFAULT\]" "use_neutron = True"
    add_line /etc/nova/nova.conf "\[DEFAULT\]" "firewall_driver = nova.virt.firewall.NoopFirewallDriver"

    add_line /etc/nova/nova.conf "\[vnc\]" "enabled = true"
    add_line /etc/nova/nova.conf "\[vnc\]" "server_listen = \$my_ip"
    add_line /etc/nova/nova.conf "\[vnc\]" "server_proxyclient_address = \$my_ip" 

    add_line /etc/nova/nova.conf "\[glance\]" "api_servers = http://controller:9292"

    add_line /etc/nova/nova.conf "\[oslo_concurrency\]" "lock_path = /var/lib/nova/tmp"

    sed "/log_dir = /d" /etc/nova/nova.conf

    sed -i "s/os_region_name\ =\ openstack/os_region_name\ =\ RegionOne/g" /etc/nova/nova.conf
    add_line /etc/nova/nova.conf "\[placement\]" "project_domain_name = Default"
    add_line /etc/nova/nova.conf "\[placement\]" "project_name = service"
    add_line /etc/nova/nova.conf "\[placement\]" "auth_type = password"
    add_line /etc/nova/nova.conf "\[placement\]" "user_domain_name = Default"
    add_line /etc/nova/nova.conf "\[placement\]" "auth_url = http://controller:5000/v3"
    add_line /etc/nova/nova.conf "\[placement\]" "username = placement"
    add_line /etc/nova/nova.conf "\[placement\]" "password = $PASS"

    su -s /bin/sh -c "nova-manage api_db sync" nova
    su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
    su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
    su -s /bin/sh -c "nova-manage db sync" nova
 

    res "导入nova相关数据库"


    service nova-api restart
    service nova-consoleauth restart
    service nova-scheduler restart
    service nova-conductor restart
    service nova-novncproxy restart



    res "启动nova服务"

#####################计算节点的内容

    apt install nova-compute -y >>/dev/null

    res "安装nova compute软件包"

sed -i "s/server_listen = \$my_ip/server_listen = 0.0.0.0/g" /etc/nova/nova.conf
add_line /etc/nova/nova.conf "\[vnc\]" "novncproxy_base_url = http://controller:6080/vnc_auto.html"


    SUPPORTVIR=`egrep -c '(vmx|svm)' /proc/cpuinfo`

    if [ $SUPPORTVIR -eq 0 ]

    then
        sed -i "s/virt_type=kvm/virt_type\ =\ qemu/g" /etc/nova/nova-compute.conf

        res "设置软件虚拟化"

    fi


    service nova-compute restart

    res "启动nova compute服务"



    . /root/admin-openrc

    su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova >>/dev/null

    res "发现计算节点"
#############################计算节点结束


}


function neutron_install () {

    varp=`cat /root/queens_all_in_one/conf |grep password`

    PASS=${varp#*=}



    var=`cat /root/queens_all_in_one/conf |grep ip`

    IP=${var#*=}



    varn=`cat /root/queens_all_in_one/conf |grep net`

    NET=${varn#*=}



    mysql -uroot -p${PASS} -e "show databases ;" >test

    DATABASENAME=`cat test | grep neutron`

    rm -rf test

    if [ ${DATABASENAME}x = neutronx ]

    then

        mysql -uroot -p$PASS -e "drop database neutron;"

    fi



    mysql -uroot -p$PASS -e "CREATE DATABASE neutron;" && mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$PASS';" && mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$PASS';"

    res "创建neutron数据库"



    . /root/admin-openrc



    USER_NEUTRON=`openstack user list | grep neutron | awk -F "|" '{print$3}' | awk -F " " '{print$1}'`

    if [ ${USER_NEUTRON}x = neutronx ]

    then

        echo -e "\033[32m 已经创建neutron用户 sucessed. \033[0m"

    else

        openstack user create --domain default neutron --password $PASS >>/dev/null

        openstack role add --project service --user neutron admin >>/dev/null

        openstack service create --name neutron \

            --description "OpenStack Networking" network >>/dev/null

        openstack endpoint create --region RegionOne \

            network public http://controller:9696 >>/dev/null

        openstack endpoint create --region RegionOne \

            network internal http://controller:9696 >>/dev/null

        openstack endpoint create --region RegionOne \

            network admin http://controller:9696 >>/dev/null

        res "创建neutron用户"

    fi


    apt install neutron-server neutron-plugin-ml2 \
        neutron-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent \
        neutron-metadata-agent

    res "安装neutron软件包"

    sed -i "s/connection\ =\ sqlite:\/\/\/\/var\/lib\/neutron\/neutron.sqlite/connection\ =\ mysql+pymysql:\/\/neutron:$PASS@controller\/neutron/g" /etc/neutron/neutron.conf

    add_line /etc/neutron/neutron.conf "\[DEFAULT\]" "service_plugins = router"
    add_line /etc/neutron/neutron.conf "\[DEFAULT\]" "allow_overlapping_ips = true"
    add_line /etc/neutron/neutron.conf "\[DEFAULT\]" "transport_url = rabbit://openstack:$PASS@controller"
    add_line /etc/neutron/neutron.conf "\[DEFAULT\]" "auth_strategy = keystone"
    add_line /etc/neutron/neutron.conf "\[DEFAULT\]" "notify_nova_on_port_status_changes = true"
    add_line /etc/neutron/neutron.conf "\[DEFAULT\]" "notify_nova_on_port_data_changes = true"

    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]" "auth_uri = http://controller:5000"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]" "auth_url = http://controller:5000"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]" "memcached_servers = controller:11211"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]" "auth_type = password"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]" "project_domain_name = default"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]" "user_domain_name = default"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]" "project_name = service"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]" "username = neutron"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]" "password = $PASS"

    add_line /etc/neutron/neutron.conf "\[nova\]" "http://controller:5000"
    add_line /etc/neutron/neutron.conf "\[nova\]" "auth_type = password"
    add_line /etc/neutron/neutron.conf "\[nova\]" "project_domain_name = default"
    add_line /etc/neutron/neutron.conf "\[nova\]" "user_domain_name = default"
    add_line /etc/neutron/neutron.conf "\[nova\]" "region_name = RegionOne"
    add_line /etc/neutron/neutron.conf "\[nova\]" "project_name = service"
    add_line /etc/neutron/neutron.conf "\[nova\]" "username = nova"
    add_line /etc/neutron/neutron.conf "\[nova\]" "password = $PASS"


    add_line /etc/neutron/plugins/ml2/ml2_conf.ini "\[ml2\]" "type_drivers = flat,vlan,vxlan"
    add_line /etc/neutron/plugins/ml2/ml2_conf.ini "\[ml2\]" "tenant_network_types = vxlan"
    add_line /etc/neutron/plugins/ml2/ml2_conf.ini "\[ml2\]" "mechanism_drivers = linuxbridge,l2population"
    add_line /etc/neutron/plugins/ml2/ml2_conf.ini "\[ml2\]" "extension_drivers = port_security"

    add_line /etc/neutron/plugins/ml2/ml2_conf.ini "\[ml2_type_flat\]" "flat_networks = provider"
    add_line /etc/neutron/plugins/ml2/ml2_conf.ini "\[ml2_type_flat\]" "vni_ranges = 1:1000"
    add_line /etc/neutron/plugins/ml2/ml2_conf.ini "\[securitygroup\]" "enable_ipset = true"

    add_line /etc/neutron/plugins/ml2/linuxbridge_agent.ini "\[linux_bridge\]" "physical_interface_mappings = provider:$NET"

    add_line /etc/neutron/plugins/ml2/linuxbridge_agent.ini "\[vxlan\]" "enable_vxlan = true"
    add_line /etc/neutron/plugins/ml2/linuxbridge_agent.ini "\[vxlan\]" "local_ip = $IP"
    add_line /etc/neutron/plugins/ml2/linuxbridge_agent.ini "\[vxlan\]" "l2_population = true"

    add_line /etc/neutron/plugins/ml2/linuxbridge_agent.ini "\[securitygroup\]" "enable_security_group = true"
    add_line /etc/neutron/plugins/ml2/linuxbridge_agent.ini "\[securitygroup\]" "firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver"

    cat /etc/sysctl.conf |grep iptables >>/dev/null

    if [ $? -eq 1 ]

    then

        echo "net.bridge.bridge-nf-call-iptables=1" >>/etc/sysctl.conf

        echo "net.bridge.bridge-nf-call-ip6tables=1" >>/etc/sysctl.conf



    fi

#    modprobe br_netfilter

#    res "载入br_netfilter模块"



#    sysctl -p >>/dev/null

    res "加载内核模块"


    add_line /etc/neutron/l3_agent.ini "\[DEFAULT\]" "interface_driver = linuxbridge"

    add_line /etc/neutron/dhcp_agent.ini "\[DEFAULT\]" "interface_driver = linuxbridge"
    add_line /etc/neutron/dhcp_agent.ini "\[DEFAULT\]" "dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq"
    add_line /etc/neutron/dhcp_agent.ini "\[DEFAULT\]" "enable_isolated_metadata = true"

    add_line /etc/neutron/metadata_agent.ini "\[DEFAULT\]" "nova_metadata_host = controller"
    add_line /etc/neutron/metadata_agent.ini "\[DEFAULT\]" "metadata_proxy_shared_secret = $PASS"

    add_line /etc/nova/nova.conf "\[neutron\]" "url = http://controller:9696"
    add_line /etc/nova/nova.conf "\[neutron\]" "auth_url = http://controller:5000"
    add_line /etc/nova/nova.conf "\[neutron\]" "auth_type = password"
    add_line /etc/nova/nova.conf "\[neutron\]" "project_domain_name = default"
    add_line /etc/nova/nova.conf "\[neutron\]" "user_domain_name = default"
    add_line /etc/nova/nova.conf "\[neutron\]" "region_name = RegionOne"
    add_line /etc/nova/nova.conf "\[neutron\]" "project_name = service"
    add_line /etc/nova/nova.conf "\[neutron\]" "username = neutron"
    add_line /etc/nova/nova.conf "\[neutron\]" "password = $PASS"
    add_line /etc/nova/nova.conf "\[neutron\]" "service_metadata_proxy = true"
    add_line /etc/nova/nova.conf "\[neutron\]" "metadata_proxy_shared_secret = $PASS"


    su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \

        --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron >>/dev/null



    service nova-api restart >>/dev/null
    service neutron-server restart >>/dev/null
    service neutron-linuxbridge-agent restart >>/dev/null
    service neutron-dhcp-agent restart >>/dev/null
    service neutron-metadata-agent restart >>/dev/null
    service neutron-l3-agent restart >>/dev/null



    res "启动neutron服务"



######################计算节点部分###############################
    apt install neutron-linuxbridge-agent -y >>/dev/null

    res "安装neutron软件包"



    service nova-compute restart >>/dev/null

    service neutron-linuxbridge-agent restart >>/dev/null

#####################计算节点部分结束###########################
}

function dashboard_install () {

    varp=`cat /root/queens_all_in_one/conf |grep password`

    PASS=${varp#*=}



    var=`cat /root/queens_all_in_one/conf |grep ip`

    IP=${var#*=}



    apt install openstack-dashboard -y >>/dev/null

    res "安装dashboard软件包"



    rm -rf /etc/openstack-dashboard/local_settings >>/dev/null

    cp /root/queens_all_in_one/local_settings /etc/openstack-dashboard/

    chown root:apache /etc/openstack-dashboard/local_settings



    service apache2 reload

    res "重启httpd服务"

    echo -e "\033[32m =========================================================== \033[0m"

    echo -e "\033[32m   在浏览器输入:http://$IP/horizon 访问OpenStack!     \033[0m"

    echo -e "\033[32m   默认域: default                                     \033[0m"

    echo -e "\033[32m   用户名: admin                                       \033[0m"

    echo -e "\033[32m   密码: $PASS                                         \033[0m"

    echo -e "\033[32m =========================================================== \033[0m"

    echo -e "\033[32m                    Queens all_in_one              \033[0m"

    echo -e "\033[32m ===========================================================  \033[0m"

}









function main(){

#    pre_install
#    ntp_install
#    client_install
#    mariadb_install
#    rabbitmq_install
#    memcached_install
    etcd_install
}
main

