#!/bin/bash -x

sudo yum update -y
sudo yum -y install wget
if [[ "$(python3 -V 2>&1)" =~ ^(Python 3.6.*) ]]; then
    sudo wget https://bootstrap.pypa.io/pip/3.6/get-pip.py -O /tmp/get-pip.py
elif [[ "$(python3 -V 2>&1)" =~ ^(Python 3.5.*) ]]; then
    sudo wget https://bootstrap.pypa.io/pip/3.5/get-pip.py -O /tmp/get-pip.py
elif [[ "$(python3 -V 2>&1)" =~ ^(Python 3.4.*) ]]; then
    sudo wget https://bootstrap.pypa.io/pip/3.4/get-pip.py -O /tmp/get-pip.py
else
    sudo wget https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py
fi
sudo python3 /tmp/get-pip.py
sudo /usr/local/bin/pip3 install botocore

# Install EFS utils but don't mount yet
sudo yum install -y amazon-efs-utils
sudo mkdir -p /mnt/efs

# Setup repositories for MongoDB and Pritunl
sudo tee /etc/yum.repos.d/mongodb-org-5.0.repo << EOF
[mongodb-org-5.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2/mongodb-org/5.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-5.0.asc
EOF
sudo tee /etc/yum.repos.d/pritunl.repo << EOF
[pritunl]
name=Pritunl Repository
baseurl=https://repo.pritunl.com/stable/yum/amazonlinux/2/
gpgcheck=1
enabled=1
EOF
sudo rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 7568D9BB55FF9E5287D586017AE645C0CF8E292A
gpg --armor --export 7568D9BB55FF9E5287D586017AE645C0CF8E292A > key.tmp;
sudo rpm --import key.tmp; rm -f key.tmp
sudo wget https://rpmfind.net/linux/epel/8/Everything/x86_64/Packages/p/pkcs11-helper-1.22-7.el8.x86_64.rpm
sudo yum install pkcs11-helper-1.22-7.el8.x86_64.rpm
sudo rm -f pkcs11-helper-1.22-7.el8.x86_64.rpm

# Install WireGuard tools (required for WireGuard VPN support in Pritunl)
sudo amazon-linux-extras install epel -y
sudo yum install -y wireguard-tools

# Install MongoDB and Pritunl (this creates mongod user)
sudo yum -y install pritunl mongodb-org-5.0.9-1.amzn2

# NOW mount EFS after mongod user exists
# Use plain NFS4 (works without EFS file system policy)
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${efs_id}.efs.ap-south-1.amazonaws.com:/ /mnt/efs
# If successful, add to fstab for persistence
if mountpoint -q /mnt/efs; then
  echo "${efs_id}.efs.ap-south-1.amazonaws.com:/ /mnt/efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0" | sudo tee -a /etc/fstab
fi
# Wait for mount to stabilize
sleep 3

# Create MongoDB data directory and set permissions (now mongod user exists)
sudo mkdir -p /mnt/efs/mongodb-data
sudo chown -R mongod:mongod /mnt/efs/mongodb-data

# Update MongoDB config to use EFS
sudo sed -i.bak "s/\/var\/lib\/mongo/\/mnt\/efs\/mongodb-data/g" /etc/mongod.conf

# Start services
sudo systemctl start mongod pritunl
sudo systemctl enable mongod pritunl
sudo pritunl set-mongodb mongodb://localhost:27017/pritunl
sudo pritunl set app.redirect_server false
sudo pritunl set app.server_ssl true
sudo pritunl set app.server_port 443
sudo pritunl set app.www_path /usr/share/pritunl/www
sudo systemctl restart pritunl
