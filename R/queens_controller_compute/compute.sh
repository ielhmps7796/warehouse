#####配置/etc/network/interfaces 文件信息，配置一块网卡作为内网,如图四，配置另一块网卡为provider，如图五.10.0.0.31
#####重启电脑
#####配置/etc/hosts文件如图六
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
    var=`cat /root/queens_controller_compute/conf_compute |grep ip`
    IP=${var#*=}

#echo $IP

#    if [ ${HOSTNAME}x != computex ]
    if [ ${HOSTNAME}x != CCD-1x ]
    then
        echo "请设置主机名为compute"
        exit
    fi

    #cat /etc/hosts |grep compute >>/dev/null
    cat /etc/hosts |grep CCD-1 >>/dev/null
    if [ $? -eq 1 ]
    then
        echo $IP computer >>/etc/hosts
echo "/etc/hosts填写成功"
    fi
echo "/etc/hosts原本就有compute"
}



function ntp_install () {
    var=`cat /root/queens_controller_compute/conf_compute |grep ip`
    IP=${var#*=}

    apt install chrony -y >>/dev/null
    res "安装ntp软件包"
    if [ ! -f  /etc/chrony/chrony.conf.bak ]
    then
        cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak
    fi
   # sed -i "s/3.centos.pool.ntp.org/controller/g" /etc/chrony/chrony.conf
    echo server controller iburst >> /etc/chrony/chrony.conf
    sed -i "/pool 2.debian.pool.ntp.org offline iburst/d" /etc/chrony/chrony.conf	
   # sed -i "s/#allow 192.168.0.0\/16/allow ${IPSEG}0\/24/g" /etc/chrony.conf
    service chrony restart 
    res "启动ntp服务"
}


function client_install () {
    apt install software-properties-common
    add-apt-repository cloud-archive:queens
    apt update -y&& apt dist-upgrade -y
    apt install python-openstackclient -y >>/dev/null
    res "安装OpenStack客户端"
}





function nova_install () {

    varp=`cat /root/queens_controller_compute/conf_compute |grep password`

    PASS=${varp#*=}



    var=`cat /root/queens_controller_compute/conf_compute |grep ip`

    IP=${var#*=}

    apt install -y nova-compute>>/dev/null

    res "安装nova软件包"
   if [ ! -f  /etc/nova/nova.conf.bak ]
    then
        cp /etc/nova/nova.conf /etc/nova/nova.conf.bak
    fi


    add_line /etc/nova/nova.conf "\[DEFAULT\]$" "transport_url = rabbit://openstack:$PASS@controller"
   
    add_line /etc/nova/nova.conf "\[api\]$" "auth_strategy = keystone"

    add_line /etc/nova/nova.conf "\[keystone_authtoken\]$" "auth_uri = http://controller:5000/v3"
    add_line /etc/nova/nova.conf "\[keystone_authtoken\]$" "auth_url = http://controller:35357/v3"
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

    add_line /etc/nova/nova.conf "\[vnc\]$" "enabled = True"
    add_line /etc/nova/nova.conf "\[vnc\]$" "server_listen = 0.0.0.0"
    add_line /etc/nova/nova.conf "\[vnc\]$" "server_proxyclient_address = \$my_ip" 
    add_line /etc/nova/nova.conf "\[vnc\]$" "novncproxy_base_url = http://controller:6080/vnc_auto.html"
    add_line /etc/nova/nova.conf "\[glance\]$" "api_servers = http://controller:9292"

    add_line /etc/nova/nova.conf "\[oslo_concurrency\]$" "lock_path = /var/lib/nova/tmp"

    sed -i "/log_dir = /d" /etc/nova/nova.conf

    sed -i "s/os_region_name\ =\ openstack/os_region_name\ =\ RegionOne/g" /etc/nova/nova.conf
    add_line /etc/nova/nova.conf "\[placement\]$" "project_domain_name = Default"
    add_line /etc/nova/nova.conf "\[placement\]$" "project_name = service"
    add_line /etc/nova/nova.conf "\[placement\]$" "auth_type = password"
    add_line /etc/nova/nova.conf "\[placement\]$" "user_domain_name = Default"
    add_line /etc/nova/nova.conf "\[placement\]$" "auth_url = http://controller:5000/v3"
    add_line /etc/nova/nova.conf "\[placement\]$" "username = placement"
    add_line /etc/nova/nova.conf "\[placement\]$" "password = $PASS"


    SUPPORTVIR=`egrep -c '(vmx|svm)' /proc/cpuinfo`

    if [ $SUPPORTVIR -eq 0 ]

    then
        sed -i "s/virt_type=kvm/virt_type\ =\ qemu/g" /etc/nova/nova-compute.conf

        res "设置软件虚拟化"

    fi


    service nova-compute restart

    res "启动nova compute服务"

}


function neutron_install () {

    varp=`cat /root/queens_controller_compute/conf_compute |grep password`

    PASS=${varp#*=}


    var=`cat /root/queens_controller_compute/conf_compute |grep ip`

    IP=${var#*=}


    varn=`cat /root/queens_controller_compute/conf_compute |grep net`

    NET=${varn#*=}

    apt install neutron-linuxbridge-agent -y >>/dev/null

    res "安装neutron软件包"
    if [ ! -f  /etc/neutron/neutron.conf.bak ]
    then
        cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.bak
    fi

    sed -i "/connection\ =\ sqlite:\/\/\/\/var\/lib\/neutron\/neutron.sqlite/d" /etc/neutron/neutron.conf

    add_line /etc/neutron/neutron.conf "\[DEFAULT\]$" "transport_url = rabbit://openstack:$PASS@controller"
    add_line /etc/neutron/neutron.conf "\[DEFAULT\]$" "auth_strategy = keystone"

    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "auth_uri = http://controller:5000"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "auth_url = http://controller:5000"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "memcached_servers = controller:11211"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "auth_type = password"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "project_domain_name = default"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "user_domain_name = default"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "project_name = service"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "username = neutron"
    add_line /etc/neutron/neutron.conf "\[keystone_authtoken\]$" "password = $PASS"
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

    service nova-compute restart >>/dev/null
    service neutron-linuxbridge-agent restart >>/dev/null

    res "启动neutron服务"



}

function main(){
PS3="请选择序号 ： "
select i in "pre_install" "ntp_install" "client_install" "nova_install" "neutron_install" "quit"
do 
case $i in

	pre_install   )
	pre_install
	;;
	ntp_install   )
	ntp_install
	;;
	client_install  )
	client_install
	;;
	nova_install  )
	nova_install
	;;
	neutron_install  )
	neutron_install
	;;
	quit	)
	exit
	;;
	*     )
	echo -e "\033[32m没有这个选项\033[0m"
	;;
esac
done
#    pre_install
#    ntp_install
#     client_install
#    nova_install
#    neutron_install
}
main

