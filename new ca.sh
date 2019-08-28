#安装opensssl和apache
apt-get install apache2
apt-get install openssl
apt-get install libssl-dev
apt-get install bless

#将openssl.conf拷贝到当前目录
cp /usr/lib/ssl/openssl.cnf /root

#创建一些目录及文件
mkdir demoCA
cd demoCA
#certs:签发的证书;crl:吊销的证书;newcerts:新签发的证书;private:ca证书的私钥
mkdir certs crl newcerts private
#index.txt:跟踪以签发的证书，初始为空;serial:最后一次签发的证书的序列号，初始为01or其他数字
touch index.txt serial

#创建CA私钥以及为自己生成自签名证书，成为CA
openssl req -new -x509 -keyout /root/demoCA/private/ca.key -out /root/demoCA/ca.crt -days 365 -config /root/openssl.cnf
#(openssl genrsa -out server.key 1024 生成私钥     openssl rsa -in server.key -pubout -out server.key  生成相应的公钥)
#注意Common Name 写主机名/域名，与域名或者IP相同

#给服务器签发证书
openssl genrsa -des3 -out /root/server.key 2048
openssl req -new -key /root/server.key -out /root/server.csr -config /root/openssl.cnf
#这里面也有一个Common Name 
#如果是服务器证书，那么Common Name是域名,*.creke.net,支持*通配符
#把server.csr传给CA服务器,在CA服务器端
openssl ca -in /root/server.csr -out /root/server.crt -cert /root/demoCA/ca.crt -keyfile /root/demoCA/private/ca.key -config /root/openssl.cnf

openssl ca -extensions v3_ca -in /root/server.csr -out /root/server.crt -cert /root/demoCA/ca.crt -keyfile /root/demoCA/private/ca.key -config /root/openssl.cnf
#把生成的server.crt返回给服务器即可，在CA端的server.csr也可以删除掉，在服务器端可以将server.key和server.crt合并成一个文件
cp server.key server.pem
cat server.crt >> server.pem




#证书链的验证
#server端
#其中CAfile是服务器端所有信任的证书，以CA2(给服务端签发证书)，CA的顺序，反过来也可以。
#-cert是服务器端传给客户端的证书，直接由CA2生成，不需要添加东西(看到过说要以cert,CA2的顺序添加，实验证明不需要)
openssl s_server -CAfile CA2_all.crt -cert client.crt -key client.key -www

#client端
#其中CAfile是客户端信任的根证书,如果在/usr/local/share/ca-certificates/中添加了那么就不用了。
openssl s_client -showcerts -CAfile ca.crt -connect CCD-1:4433

#可以看出CA2_all.crt和ca_final.crt是完全一样的东西，类比到浏览器也可以理解。当客户端访问服务器，服务器传回client.crt，客户端提取该证书的签发人，查询自身信任的证书列表，追溯到根证书，然后用追溯到的根证书对服务端的信任表进行验证。客户端肯定要安装根证书列表，服务器端也要传回信任证书列表。

#还有一个命令可以验证
#openssl verify CA.crt
#openssl verify -CAfile CA.crt CA2.crt 用CA验证CA2
#openssl verify -CAfile CA.crt -untrusted CA2.crt server.crt verify命令不支持隔代验证

