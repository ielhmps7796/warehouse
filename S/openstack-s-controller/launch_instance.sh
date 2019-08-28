#####在controller节点上运行

. /root/admin-openrc

openstack network create  --share --external \
  --provider-physical-network provider \
  --provider-network-type flat provider

openstack subnet create --network provider \
  --allocation-pool start=10.1.2.1,end=10.1.254.253 \
  --dns-nameserver 8.8.8.8 --gateway 10.1.254.254 \
  --subnet-range 10.1.0.0/16 provider

. /root/demo-openrc

openstack network create selfservice

openstack subnet create --network selfservice \
  --dns-nameserver 8.8.8.8 --gateway 172.16.1.1 \
  --subnet-range 172.16.1.0/24 selfservice

. /root/demo-openrc

openstack router create router

openstack router add subnet router selfservice

openstack router set router --external-gateway provider

openstack flavor create --id 0 --vcpus 1 --ram 64 --disk 1 m1.nano

. /root/demo-openrc

ssh-keygen -q -N ""

openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey

openstack security group rule create --proto icmp default

openstack security group rule create --proto tcp --dst-port 22 default

openstack server create --flavor m1.nano --image cirros \
  --nic net-id=provider --security-group default \
  --key-name mykey provider-instance

openstack server create --flavor m1.nano --image cirros \
  --nic net-id=selfservice --security-group default \
  --key-name mykey selfservice-instance
   
