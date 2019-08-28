#####配置/etc/network/interfaces 文件信息，配置一块网卡作为内网,如图一;配置另一块网卡为provider，如图二.10.0.0.11
#####重启电脑
#####配置/etc/hosts文件如图三


function res () {
    if [ $? -eq 0 ]
    then
        echo -e "\033[32m $@ successed. \033[0m"
    else
        echo -e "\033[41;37m $@ failed. \033[0m"
        exit
    fi
}



function add_line() {
    local file_content=$2
    local add_content=$3
    local init_file=$1
echo $file_content
    local line_number=`grep -n "$file_content" $init_file`
echo $line_number
    local line_number=${line_number%%:*}
    for n in $line_number
    do
        sed -i "${n} a$add_content"  $init_file
    done
}




function pre_install() {


    HOSTNMAE=`hostname`
    var=`cat /root/openstack-s/controller_conf |grep ip`
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
echo "/etc/hosts填写成功"
    fi
echo "/etc/hosts原本就有controller"
}



function ntp_install () {
    var=`cat /root/openstack-s/controller_conf |grep ip`
    IP=${var#*=}

  apt-get update -y  >> /dev/null  
  res "更新软件包"

    apt install chrony -y >>/dev/null
    res "安装ntp软件包"
    if [ ! -f  /etc/chrony/chrony.conf.bak ]
    then
        cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak
    fi
   # sed -i "s/3.centos.pool.ntp.org/controller/g" /etc/chrony/chrony.conf
    echo server controller iburst >> /etc/chrony/chrony.conf	
    IPSEG=`echo ${IP%\`echo $IP|cut -d \. -f 4\`*}`
echo $IPSEG
   # sed -i "s/#allow 192.168.0.0\/16/allow ${IPSEG}0\/24/g" /etc/chrony.conf
    echo allow ${IPSEG}0\/16 >> /etc/chrony/chrony.conf
    service chrony restart 
    res "启动ntp服务"
}


function client_install () {
    #apt install software-properties-common
    add-apt-repository cloud-archive:stein
    apt update -y&& apt dist-upgrade -y
    apt install python-openstackclient -y >>/dev/null
    res "安装OpenStack客户端"
}




function mariadb_install () {
    var=`cat /root/openstack-s/controller_conf |grep ip`
    IP=${var#*=}

    varp=`cat /root/openstack-s/controller_conf |grep password`
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

    if [ ! -f /root/openstack-s/sql.tag ]
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
    touch /root/openstack-s/sql.tag
    fi
    res "设置数据库密码$PASS"
}




function rabbitmq_install () {
    varp=`cat /root/openstack-s/controller_conf |grep password`
    PASS=${varp#*=}

    apt install rabbitmq-server -y >>/dev/null
    res "安装消息队列软件包"

    rabbitmqctl add_user openstack $PASS >>/dev/null
    rabbitmqctl set_permissions openstack ".*" ".*" ".*" >>/dev/null
    res "设置消息队列权限"
}


function memcached_install () {
    var=`cat /root/openstack-s/controller_conf |grep ip`
    IP=${var#*=}

    apt install memcached python-memcache -y >>/dev/null
    res "安装memcached软件包"
    if [ ! -f  /etc/memcached.conf.bak ]
    then
        cp /etc/memcached.conf /etc/memcached.conf.bak
    fi
    sed -i "s/-l 127.0.0.1/-l $IP/g" /etc/memcached.conf

    service memcached restart
    res "启动memcached服务"
}




function etcd_install () {
    var=`cat /root/openstack-s/controller_conf |grep ip`
    IP=${var#*=}

    apt install etcd -y >>/dev/null
    res "安装etcd软件包"
    if [ ! -f  /etc/default/etcd.bak ]
    then
        cp /etc/default/etcd /etc/default/etcd.bak
    fi
    sed -i "s/# ETCD_NAME=\"hostname\"/ETCD_NAME=\"controller\"/g" /etc/default/etcd
    sed -i "s/# ETCD_DATA_DIR=\"\/var\/lib\/etcd\/default\"/ETCD_DATA_DIR=\"\/var\/lib\/etcd\"/g" /etc/default/etcd 
    sed -i "s/# ETCD_INITIAL_CLUSTER_STATE=\"existing\"/ETCD_INITIAL_CLUSTER_STATE=\"new\"/g" /etc/default/etcd
    sed -i "s/# ETCD_INITIAL_CLUSTER_TOKEN=\"etcd-cluster\"/ETCD_INITIAL_CLUSTER_TOKEN=\"etcd-cluster-01\"/g" /etc/default/etcd
    sed -i "s/# ETCD_INITIAL_CLUSTER=\"default=http:\/\/localhost:2380,default=http:\/\/localhost:7001\"/ETCD_INITIAL_CLUSTER=\"controller=http:\/\/$IP:2380\"/g" /etc/default/etcd
    sed -i "s/# ETCD_INITIAL_ADVERTISE_PEER_URLS=\"http:\/\/localhost:2380,http:\/\/localhost:7001\"/ETCD_INITIAL_ADVERTISE_PEER_URLS=\"http:\/\/$IP:2380\"/g" /etc/default/etcd
    sed -i "s/# ETCD_ADVERTISE_CLIENT_URLS=\"http:\/\/localhost:2379,http:\/\/localhost:4001\"/ETCD_ADVERTISE_CLIENT_URLS=\"http:\/\/$IP:2379\"/g" /etc/default/etcd
    sed -i "s/# ETCD_LISTEN_PEER_URLS=\"http:\/\/localhost:2380,http:\/\/localhost:7001\"/ETCD_LISTEN_PEER_URLS=\"http:\/\/0.0.0.0:2380\"/g" /etc/default/etcd
    sed -i "s/# ETCD_LISTEN_CLIENT_URLS=\"http:\/\/localhost:2379,http:\/\/localhost:4001\"/ETCD_LISTEN_CLIENT_URLS=\"http:\/\/$IP:2379\"/g" /etc/default/etcd


    systemctl enable etcd >>/dev/null
    systemctl start etcd >>/dev/null
    res "启动etcd服务"
}





function keystone_install () {
    varp=`cat /root/openstack-s/controller_conf |grep password`
    PASS=${varp#*=}

    mysql -uroot -p${PASS} -e "show databases;" >test
    DATABASEKEYSTONE=`cat test | grep keystone`
    rm -rf test
    if [ ${DATABASEKEYSTONE}x = keystonex ]
    then
        res "已经创建keystone数据库"
    else
        mysql -uroot -p$PASS -e "CREATE DATABASE keystone;" && mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$PASS';" 
        mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$PASS';"
        res "创建keystone数据库"
    fi

    apt install keystone apache2 libapache2-mod-wsgi-py3 -y >>/dev/null
    res "安装keystone软件包"

 if [ ! -f  /etc/keystone/keystone.conf.bak ]
 then
     cp /etc/keystone/keystone.conf /etc/keystone/keystone.conf.bak
 fi
 sed -i "s/connection = sqlite:\/\/\/\/var\/lib\/keystone\/keystone.db/connection\ =\ mysql+pymysql:\/\/keystone:$PASS@controller\/keystone/g" /etc/keystone/keystone.conf
    add_line /etc/keystone/keystone.conf "\[token\]$" "provider = fernet"

    su -s /bin/sh -c "keystone-manage db_sync" keystone >>/dev/null
    res "同步keystone数据库"

    keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone >>/dev/null
    keystone-manage credential_setup --keystone-user keystone --keystone-group keystone >>/dev/null

    keystone-manage bootstrap --bootstrap-password $PASS \
        --bootstrap-admin-url http://controller:5000/v3/ \
        --bootstrap-internal-url http://controller:5000/v3/ \
        --bootstrap-public-url http://controller:5000/v3/ \
        --bootstrap-region-id RegionOne >>/dev/null

 if [ ! -f  /etc/apache2/apache2.conf.bak ]
 then
    cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf.bak
 fi 
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
            --description "Demo Project" myproject >>/dev/null
        openstack user create --domain default \
            myuser --password $PASS >>/dev/null
        openstack role create myrole >>/dev/null
        openstack role add --project myproject --user myuser myrole >>/dev/null
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
        echo "export OS_PROJECT_NAME=myproject" >>$CONFIGFILE
        echo "export OS_USERNAME=myuser" >>$CONFIGFILE
        echo "export OS_PASSWORD=$PASS" >>$CONFIGFILE
        echo "export OS_AUTH_URL=http://controller:5000/v3" >>$CONFIGFILE
        echo "export OS_IDENTITY_API_VERSION=3" >>$CONFIGFILE
        echo "export OS_IMAGE_API_VERSION=2" >>$CONFIGFILE
    fi

    res "创建环境变量文件"
}


function placement_install () {
    varp=`cat /root/openstack-s/controller_conf |grep password`
    PASS=${varp#*=}

    mysql -uroot -p${PASS} -e "show databases;" >test
    DATABASEPLACEMENT=`cat test | grep placement`
    rm -rf test
    if [ ${DATABASEPLACEMENT}x = placementx]
    then
        res "已经创建placement数据库"
    else
        mysql -uroot -p$PASS -e "CREATE DATABASE placement;" && mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$PASS';" 
        mysql -uroot -p$PASS -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '$PASS';"
        res "创建placement数据库"
    fi
    
    . /root/admin-openrc

    USER_PLACEMENT=`openstack user list | grep placement| awk -F "|" '{print$3}' | awk -F " " '{print$1}'`
    if [ ${USER_PLACEMENT}x = placementx]
    then
        #echo "123123214000"
        echo -e "\033[32m 已经创建placement用户 sucessed. \033[0m"
    else
        openstack user create --domain default placement --password $PASS >>/dev/null
        openstack role add --project service --user placement admin
        openstack service create --name placement \
            --description "Placement API" placement>>/dev/null
        openstack endpoint create --region RegionOne \
            placement public http://controller:8778 >>/dev/null
        openstack endpoint create --region RegionOne \
            placement internal http://controller:8778  >>/dev/null
        openstack endpoint create --region RegionOne \
            placement admin http://controller:8778 >>/dev/null
        res "创建placement用户"
    fi

    apt install placement-api  -y >>/dev/null

    res "安装placement软件包"

 if [ ! -f  /etc/placement/placement.conf.bak ]
 then
     cp /etc/placement/placement.conf /etc/placement/placement.conf.bak
 fi


   # add_line /etc/glance/glance-api.conf "\[database\]" "connection\ =\ mysql+pymysql:\/\/glance:$PASS@controller\/glance"
    sed -i "s/connection\ =\ sqlite:\/\/\/\/var\/lib\/placement\/placement.sqlite/connection\ =\ mysql+pymysql:\/\/placement:$PASS@controller\/placement/g" /etc/placement/placement.conf
    add_line /etc/placement/placement.conf "\[api\]$" "auth_strategy = keystone"

    add_line /etc/placement/placement.conf "\[keystone_authtoken\]$" "auth_url = http://controller:5000/v3"
    add_line /etc/placement/placement.conf "\[keystone_authtoken\]$" "memcached_servers = controller:11211"
    add_line /etc/placement/placement.conf "\[keystone_authtoken\]$" "auth_type = password"
    add_line /etc/placement/placement.conf "\[keystone_authtoken\]$" "project_domain_name = default"
    add_line /etc/placement/placement.conf "\[keystone_authtoken\]$" "user_domain_name = default"
    add_line /etc/placement/placement.conf "\[keystone_authtoken\]$" "project_name = service"
    add_line /etc/placement/placement.conf "\[keystone_authtoken\]$" "username = placement"
    add_line /etc/placement/placement.conf "\[keystone_authtoken\]$" "password = $PASS"


    su -s /bin/sh -c "placement-manage db_sync" placement >>/dev/null
    res "同步placement数据库"

    service apache2  restart >>/dev/null
    res "启动placement服务"
}

function glance_install () {
    varp=`cat /root/openstack-s/controller_conf |grep password`
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

 if [ ! -f  /etc/glance/glance-api.conf.bak ]
 then
     cp /etc/glance/glance-api.conf /etc/glance/glance-api.conf.bak
 fi


   # add_line /etc/glance/glance-api.conf "\[database\]" "connection\ =\ mysql+pymysql:\/\/glance:$PASS@controller\/glance"
    sed -i "s/connection\ =\ sqlite:\/\/\/\/var\/lib\/glance\/glance.sqlite/connection\ =\ mysql+pymysql:\/\/glance:$PASS@controller\/glance/g" /etc/glance/glance-api.conf
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]$" "auth_uri = http://controller:5000"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]$" "auth_url = http://controller:5000"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]$" "memcached_servers = controller:11211"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]$" "auth_type = password"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]$" "project_domain_name = Default"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]$" "user_domain_name = Default"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]$" "project_name = service"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]$" "username = glance"
    add_line /etc/glance/glance-api.conf "\[keystone_authtoken\]$" "password = $PASS"


    add_line /etc/glance/glance-api.conf "\[paste_deploy\]$" "flavor = keystone"

    add_line /etc/glance/glance-api.conf "\[glance_store\]$" "stores = file,http"
    add_line /etc/glance/glance-api.conf "\[glance_store\]$" "default_store = file"
    add_line /etc/glance/glance-api.conf "\[glance_store\]$" "filesystem_store_datadir = /var/lib/glance/images/"

 if [ ! -f  /etc/glance/glance-registry.conf.bak ]
 then
    cp /etc/glance/glance-registry.conf /etc/glance/glance-registry.conf.bak
 fi


   # add_line /etc/glance/glance-registry.conf "\[database\]" "connection\ =\ mysql+pymysql:\/\/glance:$PASS@controller\/glance"
   sed -i "s/connection\ =\ sqlite:\/\/\/\/var\/lib\/glance\/glance.sqlite/connection\ =\ mysql+pymysql:\/\/glance:$PASS@controller\/glance/g" /etc/glance/glance-registry.conf 

    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]$" "auth_uri = http://controller:5000"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]$" "auth_url = http://controller:5000"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]$" "memcached_servers = controller:11211"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]$" "auth_type = password"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]$" "project_domain_name = Default"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]$" "user_domain_name = Default"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]$" "project_name = service"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]$" "username = glance"
    add_line /etc/glance/glance-registry.conf "\[keystone_authtoken\]$" "password = $PASS"


    add_line /etc/glance/glance-registry.conf "\[paste_deploy\]$" "flavor = keystone"
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

    varp=`cat /root/openstack-s/controller_conf |grep password`

    PASS=${varp#*=}



    var=`cat /root/openstack-s/controller_conf |grep ip`

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

#        openstack user create --domain default placement --password $PASS >>/dev/null

#        openstack role add --project service --user placement admin >>/dev/null

#        openstack service create --name placement --description "Placement API" placement >>/dev/null

#        openstack endpoint create --region RegionOne placement public http://controller:8778 >>/dev/null

#        openstack endpoint create --region RegionOne placement internal http://controller:8778 >>/dev/null

#        openstack endpoint create --region RegionOne placement admin http://controller:8778 >>/dev/null

        res "创建nova相关用户"

    fi



    apt install -y nova-api nova-conductor nova-consoleauth nova-novncproxy nova-scheduler 

    res "安装nova软件包"

    if [ ! -f  /etc/nova/nova.conf.bak ]
    then
        cp /etc/nova/nova.conf /etc/nova/nova.conf.bak
    fi


    sed -i "s/connection\ =\ sqlite:\/\/\/\/var\/lib\/nova\/nova_api.sqlite/connection\ =\ mysql+pymysql:\/\/nova:$PASS@controller\/nova_api/g" /etc/nova/nova.conf

    sed -i "s/connection\ =\ sqlite:\/\/\/\/var\/lib\/nova\/nova.sqlite/connection\ =\ mysql+pymysql:\/\/nova:$PASS@controller\/nova/g" /etc/nova/nova.conf

    add_line /etc/nova/nova.conf "\[DEFAULT\]$" "transport_url = rabbit://openstack:$PASS@controller"
   
    add_line /etc/nova/nova.conf "\[api\]$" "auth_strategy = keystone"

    add_line /etc/nova/nova.conf "\[keystone_authtoken\]$" "auth_url = http://controller:5000/v3"
    add_line /etc/nova/nova.conf "\[keystone_authtoken\]$" "memcached_servers = controller:11211"
    add_line /etc/nova/nova.conf "\[keystone_authtoken\]$" "auth_type = password"
    add_line /etc/nova/nova.conf "\[keystone_authtoken\]$" "project_domain_name = default"
    add_line /etc/nova/nova.conf "\[keystone_authtoken\]$" "user_domain_name = default"
    add_line /etc/nova/nova.conf "\[keystone_authtoken\]$" "project_name = service"
    add_line /etc/nova/nova.conf "\[keystone_authtoken\]$" "username = nova"
    add_line /etc/nova/nova.conf "\[keystone_authtoken\]$" "password = $PASS"

    add_line /etc/nova/nova.conf "\[DEFAULT\]$" "my_ip = $IP"
    add_line /etc/nova/nova.conf "\[DEFAULT\]$" "use_neutron = True"
    add_line /etc/nova/nova.conf "\[DEFAULT\]$" "firewall_driver = nova.virt.firewall.NoopFirewallDriver"

    add_line /etc/nova/nova.conf "\[vnc\]$" "enabled = true"
    add_line /etc/nova/nova.conf "\[vnc\]$" "server_listen = \$my_ip"
    add_line /etc/nova/nova.conf "\[vnc\]$" "server_proxyclient_address = \$my_ip" 

    add_line /etc/nova/nova.conf "\[glance\]$" "api_servers = http://controller:9292"

    add_line /etc/nova/nova.conf "\[oslo_concurrency\]$" "lock_path = /var/lib/nova/tmp"

    sed -i "/log_dir = /d" /etc/nova/nova.conf

    sed -i "s/os_region_name\ =\ openstack/region_name\ =\ RegionOne/g" /etc/nova/nova.conf
    add_line /etc/nova/nova.conf "\[placement\]$" "project_domain_name = Default"
    add_line /etc/nova/nova.conf "\[placement\]$" "project_name = service"
    add_line /etc/nova/nova.conf "\[placement\]$" "auth_type = password"
    add_line /etc/nova/nova.conf "\[placement\]$" "user_domain_name = Default"
    add_line /etc/nova/nova.conf "\[placement\]$" "auth_url = http://controller:5000/v3"
    add_line /etc/nova/nova.conf "\[placement\]$" "username = placement"
    add_line /etc/nova/nova.conf "\[placement\]$" "password = $PASS"

    su -s /bin/sh -c "nova-manage api_db sync" nova
    su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
    su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
    su -s /bin/sh -c "nova-manage db sync" nova
 

    res "导入nova相关数据库"

    add_line /etc/nova/nova.conf "\[scheduler\]$" "discover_hosts_in_cells_interval = 300"

    service nova-api restart
    service nova-consoleauth restart
    service nova-scheduler restart
    service nova-conductor restart
    service nova-novncproxy restart



    res "启动nova服务"



}


function neutron_install () {

    varp=`cat /root/openstack-s/controller_conf |grep password`

    PASS=${varp#*=}


    var=`cat /root/openstack-s/controller_conf |grep ip`

    IP=${var#*=}


    varn=`cat /root/openstack-s/controller_conf |grep net`

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


    apt install -y neutron-server neutron-plugin-ml2 \
        neutron-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent \
        neutron-metadata-agent

    res "安装neutron软件包"

    if [ ! -f  /etc/neutron/neutron.conf.bak ]
    then
        cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.bak
    fi

    sed -i "s/connection\ =\ sqlite:\/\/\/\/var\/lib\/neutron\/neutron.sqlite/connection\ =\ mysql+pymysql:\/\/neutron:$PASS@controller\/neutron/g" /etc/neutron/neutron.conf

    #add_line /etc/neutron/neutron.conf "\[DEFAULT\]$" "core_plugin = ml2"
    add_line /etc/neutron/neutron.conf "\[DEFAULT\]$" "service_plugins = router"
    add_line /etc/neutron/neutron.conf "\[DEFAULT\]$" "allow_overlapping_ips = true"
    add_line /etc/neutron/neutron.conf "\[DEFAULT\]$" "transport_url = rabbit://openstack:$PASS@controller"
    add_line /etc/neutron/neutron.conf "\[DEFAULT\]$" "auth_strategy = keystone"
    add_line /etc/neutron/neutron.conf "\[DEFAULT\]$" "notify_nova_on_port_status_changes = true"
    add_line /etc/neutron/neutron.conf "\[DEFAULT\]$" "notify_nova_on_port_data_changes = true"

    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "www_authenticate_uri = http://controller:5000"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "auth_url = http://controller:5000"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "memcached_servers = controller:11211"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "auth_type = password"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "project_domain_name = default"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "user_domain_name = default"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "project_name = service"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "username = neutron"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "password = $PASS"

    add_line /etc/neutron/neutron.conf "\[nova\]$" "auth_url = http://controller:5000"
    add_line /etc/neutron/neutron.conf "\[nova\]$" "auth_type = password"
    add_line /etc/neutron/neutron.conf "\[nova\]$" "project_domain_name = default"
    add_line /etc/neutron/neutron.conf "\[nova\]$" "user_domain_name = default"
    add_line /etc/neutron/neutron.conf "\[nova\]$" "region_name = RegionOne"
    add_line /etc/neutron/neutron.conf "\[nova\]$" "project_name = service"
    add_line /etc/neutron/neutron.conf "\[nova\]$" "username = nova"
    add_line /etc/neutron/neutron.conf "\[nova\]$" "password = $PASS"
    
    add_line /etc/neutron/neutron.conf "\[oslo_concurrency\]$" "lock_path = /var/lib/neutron/tmp"

    if [ ! -f  /etc/neutron/plugins/ml2/ml2_conf.ini.bak ]
    then
        cp /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.bak
    fi

    add_line /etc/neutron/plugins/ml2/ml2_conf.ini "\[ml2\]$" "type_drivers = flat,vlan,vxlan"
    add_line /etc/neutron/plugins/ml2/ml2_conf.ini "\[ml2\]$" "tenant_network_types = vxlan"
    add_line /etc/neutron/plugins/ml2/ml2_conf.ini "\[ml2\]$" "mechanism_drivers = linuxbridge,l2population"
    add_line /etc/neutron/plugins/ml2/ml2_conf.ini "\[ml2\]$" "extension_drivers = port_security"

    add_line /etc/neutron/plugins/ml2/ml2_conf.ini "\[ml2_type_flat\]$" "flat_networks = provider"
    add_line /etc/neutron/plugins/ml2/ml2_conf.ini "\[ml2_type_vxlan\]$" "vni_ranges = 1:1000"
    add_line /etc/neutron/plugins/ml2/ml2_conf.ini "\[securitygroup\]$" "enable_ipset = true"

    if [ ! -f   /etc/neutron/plugins/ml2/linuxbridge_agent.ini.bak ]
    then
        cp  /etc/neutron/plugins/ml2/linuxbridge_agent.ini  /etc/neutron/plugins/ml2/linuxbridge_agent.ini.bak
    fi

    add_line /etc/neutron/plugins/ml2/linuxbridge_agent.ini "\[linux_bridge\]$" "physical_interface_mappings = provider:$NET"

    add_line /etc/neutron/plugins/ml2/linuxbridge_agent.ini "\[vxlan\]$" "enable_vxlan = true"
    add_line /etc/neutron/plugins/ml2/linuxbridge_agent.ini "\[vxlan\]$" "local_ip = $IP"
    add_line /etc/neutron/plugins/ml2/linuxbridge_agent.ini "\[vxlan\]$" "l2_population = true"

    add_line /etc/neutron/plugins/ml2/linuxbridge_agent.ini "\[securitygroup\]$" "enable_security_group = true"
    add_line /etc/neutron/plugins/ml2/linuxbridge_agent.ini "\[securitygroup\]$" "firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver"

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
    if [ ! -f  /etc/neutron/l3_agent.ini.bak ]
    then
        cp /etc/neutron/l3_agent.ini /etc/neutron/l3_agent.ini.bak
    fi

    add_line /etc/neutron/l3_agent.ini "\[DEFAULT\]$" "interface_driver = linuxbridge"

    if [ ! -f  /etc/neutron/dhcp_agent.ini.bak ]
    then
        cp /etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini.bak
    fi
    add_line /etc/neutron/dhcp_agent.ini "\[DEFAULT\]$" "interface_driver = linuxbridge"
    add_line /etc/neutron/dhcp_agent.ini "\[DEFAULT\]$" "dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq"
    add_line /etc/neutron/dhcp_agent.ini "\[DEFAULT\]$" "enable_isolated_metadata = true"

    if [ ! -f  /etc/neutron/metadata_agent.ini.bak ]
    then
        cp /etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini.bak
    fi
    add_line /etc/neutron/metadata_agent.ini "\[DEFAULT\]$" "nova_metadata_host = controller"
    add_line /etc/neutron/metadata_agent.ini "\[DEFAULT\]$" "metadata_proxy_shared_secret = $PASS"

    if [ ! -f  /etc/nova/nova.conf.bak ]
    then
        cp /etc/nova/nova.conf /etc/nova/nova.conf.bak
    fi
    add_line /etc/nova/nova.conf "\[neutron\]$" "url = http://controller:9696"
    add_line /etc/nova/nova.conf "\[neutron\]$" "auth_url = http://controller:5000"
    add_line /etc/nova/nova.conf "\[neutron\]$" "auth_type = password"
    add_line /etc/nova/nova.conf "\[neutron\]$" "project_domain_name = default"
    add_line /etc/nova/nova.conf "\[neutron\]$" "user_domain_name = default"
    add_line /etc/nova/nova.conf "\[neutron\]$" "region_name = RegionOne"
    add_line /etc/nova/nova.conf "\[neutron\]$" "project_name = service"
    add_line /etc/nova/nova.conf "\[neutron\]$" "username = neutron"
    add_line /etc/nova/nova.conf "\[neutron\]$" "password = $PASS"
    add_line /etc/nova/nova.conf "\[neutron\]$" "service_metadata_proxy = true"
    add_line /etc/nova/nova.conf "\[neutron\]$" "metadata_proxy_shared_secret = $PASS"


    su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
        --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron >>/dev/null



    service nova-api restart >>/dev/null
    service neutron-server restart >>/dev/null
    service neutron-linuxbridge-agent restart >>/dev/null
    service neutron-dhcp-agent restart >>/dev/null
    service neutron-metadata-agent restart >>/dev/null
    service neutron-l3-agent restart >>/dev/null



    res "启动neutron服务"



}

function dashboard_install () {

    varp=`cat /root/openstack-s/controller_conf |grep password`

    PASS=${varp#*=}



    var=`cat /root/openstack-s/controller_conf |grep ip`

    IP=${var#*=}


    apt install openstack-dashboard -y >>/dev/null

    res "安装dashboard软件包"


   # rm -rf /etc/openstack-dashboard/local_settings >>/dev/null
    if [ ! -f  /etc/openstack-dashboard/local_settings.py.bak ]
    then
        mv /etc/openstack-dashboard/local_settings.py /etc/openstack-dashboard/local_settings.py.bak
    fi
    cp /root/openstack-s/local_settings.py /etc/openstack-dashboard/

    chown root:horizon /etc/openstack-dashboard/local_settings.py


    service apache2 reload

    res "重启httpd服务"

    echo -e "\033[32m =========================================================== \033[0m"

    echo -e "\033[32m   在浏览器输入:http://$IP/horizon 访问OpenStack!     \033[0m"

    echo -e "\033[32m   默认域: default                                     \033[0m"

    echo -e "\033[32m   用户名: admin                                       \033[0m"

    echo -e "\033[32m   密码: $PASS                                         \033[0m"

    echo -e "\033[32m =========================================================== \033[0m"

    echo -e "\033[32m                    Queens controller_compute              \033[0m"

    echo -e "\033[32m ===========================================================  \033[0m"

}

function swift_install () {

    varp=`cat /root/openstack-s/controller_conf |grep password`

    PASS=${varp#*=}


    . /root/admin-openrc


    USER_SWIFT=`openstack user list | grep swift| awk -F "|" '{print$3}' | awk -F " " '{print$1}'`

    if [ ${USER_SWIFT}x = swiftx ]

    then

        echo -e "\033[32m 已经创建swift用户 sucessed. \033[0m"

    else

        openstack user create --domain default swift --password $PASS >>/dev/null

        openstack role add --project service --user swift admin >>/dev/null

        openstack service create --name swift \
            --description "OpenStack Object Storage" object-store >>/dev/null

        openstack endpoint create --region RegionOne \
            object-store public http://controller:8080/v1/AUTH_%\(project_id\)s >>/dev/null

        openstack endpoint create --region RegionOne \
            object-store internal http://controller:8080/v1/AUTH_%\(project_id\)s >>/dev/null

        openstack endpoint create --region RegionOne \
            object-store admin http://controller:8080/v1 >>/dev/null

        res "创建swift用户"

    fi
   
    apt-get install swift swift-proxy python-swiftclient \
            python-keystoneclient python-keystonemiddleware \
            memcached
    if [ ! -d /etc/swift ];then
	mkdir /etc/swift
    fi
   #curl -o /etc/swift/proxy-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/proxy-server.conf-sample?h=stable/queens
    curl -o /etc/swift/proxy-server.conf https://opendev.org/openstack/swift/raw/branch/stable/stein/etc/proxy-server.conf-sample
    
    
    add_line /etc/swift/proxy-server.conf "\[DEFAULT\]$" "user = swift"
    add_line /etc/swift/proxy-server.conf "\[DEFAULT\]$" "swift_dir = /etc/swift"


    sed -i "s/pipeline\ =\ catch_errors\ gatekeeper\ healthcheck\ proxy-logging\ cache\ listing_formats\ container_sync\ bulk\ tempurl\ ratelimit\ tempauth\ copy\ container-quotas\ account-quotas\ slo\ dlo\ versioned_writes\ symlink\ proxy-logging\ proxy-server/pipeline\ =\ catch_errors\ gatekeeper\ healthcheck\ proxy-logging\ cache\ container_sync\ bulk\ ratelimit\ authtoken\ keystoneauth\ container-quotas\ account-quotas\ slo\ dlo\ versioned_writes\ proxy-logging\ proxy-server/g" /etc/swift/proxy-server.conf
 
    add_line /etc/swift/proxy-server.conf "\[app:proxy-server\]$" "account_autocreate = True"
    add_line /etc/swift/proxy-server.conf "\[filter:keystoneauth\]$" "use = egg:swift#keystoneauth"
    add_line /etc/swift/proxy-server.conf "\[filter:keystoneauth\]$" "operator_roles = admin,myrole"
    add_line /etc/swift/proxy-server.conf "\[filter:keystoneauth\]$" "[filter:keystoneauth]"
    add_line /etc/swift/proxy-server.conf "\[filter:authtoken\]$" "paste.filter_factory = keystonemiddleware.auth_token:filter_factory"
    add_line /etc/swift/proxy-server.conf "\[filter:authtoken\]$" "www_authenticate_uri = http://controller:5000"
    add_line /etc/swift/proxy-server.conf "\[filter:authtoken\]$" "auth_url = http://controller:5000"
    add_line /etc/swift/proxy-server.conf "\[filter:authtoken\]$" "memcached_servers = controller:11211"
    add_line /etc/swift/proxy-server.conf "\[filter:authtoken\]$" "auth_type = password"
    add_line /etc/swift/proxy-server.conf "\[filter:authtoken\]$" "project_domain_id = default"
    add_line /etc/swift/proxy-server.conf "\[filter:authtoken\]$" "user_domain_id = default"
    add_line /etc/swift/proxy-server.conf "\[filter:authtoken\]$" "project_name = service"
    add_line /etc/swift/proxy-server.conf "\[filter:authtoken\]$" "username = swift"
    add_line /etc/swift/proxy-server.conf "\[filter:authtoken\]$" "password = $PASS"
    add_line /etc/swift/proxy-server.conf "\[filter:authtoken\]$" "delay_auth_decision = True"
    add_line /etc/swift/proxy-server.conf "\[filter:autotoken\]$" "[filter:authtoken]"


    add_line /etc/swift/proxy-server.conf "\[filter:cache\]$" "memcache_servers = controller:11211" 

    echo -e "\033[32m接下来在storage节点上运行swift_install\033[0m"

}

function main(){
PS3="选择序号 : "
select i in "pre_install" "ntp_install" "client_install" "mariadb_install" "rabbitmq_install" "memcached_install" "etcd_install" "keystone_install" "placement_install" "glance_install" "nova_install" "neutron_install" "dashboard_install" "swift_install" "quit"
do
case $i in 
	pre_install   )
	pre_install
	;;
	ntp_install   )
	ntp_install
	;;
	client_install)
	client_install
	;;
	mariadb_install)
	mariadb_install
	;;
	rabbitmq_install)
	rabbitmq_install
	;;
	memcached_install)
	memcached_install
	;;
	etcd_install  )
	etcd_install
	;;
	keystone_install)
	keystone_install
	;;
	placement_install)
	placement_install
	;;
	glance_install  )
	glance_install
	;;
	nova_install  )
	nova_install
	;;
	neutron_install  )
	neutron_install
	;;
	dashboard_install  )
	dashboard_install
	;;
	swift_install	)
	swift_install
	;;
	quit	)
	exit
	;;
	*               )
	echo -e "\033[32m没有这个选项\033[0m"
	;;
esac
done
#    pre_install
#    ntp_install
#    client_install
#    mariadb_install
#    rabbitmq_install
#    memcached_install
#    etcd_install
#    keystone_install
#    glance_install
#    nova_install
#    neutron_install
#    dashboard_install
}
main


