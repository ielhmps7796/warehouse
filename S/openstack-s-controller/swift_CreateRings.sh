function res () {
    if [ $? -eq 0 ]
    then
        echo -e "\033[32m $@ sucessed. \033[0m"
    else
        echo -e "\033[41;37m $@ failed. \033[0m"
        exit
    fi
}

function rings () {
	#用storage节点的IP
	var=`cat /root/openstack-s/compute_conf|grep ip`
	IP=${var#*=}

	#create account ring
	if [ ! -d /etc/swift ]
	then
		res "/etc/swift目录不存在"
		exit
	else
		cd /etc/swift
	fi
	swift-ring-builder account.builder create 12 3 1
	for DEVICE in sdb sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm
	do
		swift-ring-builder account.builder add --region 1 --zone 1 --ip $IP --port 6202 --device $DEVICE  --weight 100
	done

	#verify the ring contents and rebalance the ring
	swift-ring-builder account.builder
	swift-ring-builder account.builder rebalance


	#create container ring
	if [ ! -d /etc/swift ]
        then
                res "/etc/swift目录不存在"
                exit
        else
		cd /etc/swift
        fi
        swift-ring-builder container.builder create 12 3 1

	for DEVICE in sdb sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm
	do
		swift-ring-builder container.builder add  --region 1 --zone 1 --ip $IP --port 6201 --device $DEVICE --weight 100
	done

	#verify the ring contents and rebalance the ring
	swift-ring-builder container.builder
	swift-ring-builder container.builder rebalance

	#create object ring
        if [ ! -d /etc/swift ]
        then
                res "/etc/swift目录不存在"
                exit
        else
                cd /etc/swift
        fi
        swift-ring-builder object.builder create 12 3 1

        for DEVICE in sdb sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm
	do
		 swift-ring-builder object.builder add --region 1 --zone 1 --ip $IP --port 6200 --device $DEVICE --weight 100
	done
	
	#verify the ring contents and rebalance the ring
	swift-ring-builder object.builder
	swift-ring-builder object.builder rebalance

######################################################################
	echo -e  "\033[323m  Copy the account.ring.gz, container.ring.gz, and object.ring.gz files to the /etc/swift directory on each storage node and any additional nodes running the proxy service.\033[0m"
	echo -e "\033[32m接下来运行finalize\033[0m"
}



function finalize () {

	curl -o /etc/swift/swift.conf https://opendev.org/openstack/swift/raw/branch/stable/stein/etc/swift.conf-sample
	
	sed -i s/swift_hash_path_suffix\ =\ changeme/swift_hash_path_suffix\ =\ hashhouzhui/g /etc/swift/swift.conf
	sed -i s/swift_hash_path_prefix\ =\ changeme/swift_hash_path_prefix\ =\ hashqianzhui/g /etc/swift/swift.conf
	
	echo -e  "\033[32m  Copy the swift.conf file to the /etc/swift directory on each storage node and any additional nodes running the proxy service \033[0m"
	echo -e "\033[32m  On all nodes, ensure proper ownership of the configuration directory: \033[0m"
	echo -e "\033[32m      chown -R root:swift /etc/swift     \033[0m"
	echo -e "\033[32m   On the controller node and any other nodes running the proxy service, restart the Object Storage proxy service including its dependencies: \033[0m "
	echo -e "\033[32m     service memcached restart   \033[0m"
	echo -e "\033[32m     service swift-proxy restart  \033[0m"
	echo -e "\033[32m   On the storage nodes   \033[0m"
	echo -e "\033[32m     swift-init all start  \033[0m"
}

function main () {

	PS3="选择序号："
	select i in "rings" "finalize" "quit"
	do
	case $i in
		rings	)
		rings
		;;
		finalize	)
		finalize
		;;
		quit	)
		exit
		;;
		*	)
		echo -e "\033[32m没有这个选项\033[0m"
		;;
	esac
	done	
	
}
main
