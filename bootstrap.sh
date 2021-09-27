#!/usr/bin/env bash

HTTP="http"

if [ -z $KEYSTONE_DB_HOST ]; then
    KEYSTONE_DB_HOST=localhost
    # start mysql locally
    service mysql restart

    #Docker OverlayFS compatibility: implements subset POSIX standards
    #https://docs.docker.com/storage/storagedriver/overlayfs-driver/
    #ALT: attach /var/lib/mysql as a volume to avoid timeout
    if [ $? ] ; then
        find /var/lib/mysql -type f -exec touch {} \;
        service mysql restart
    fi
else
    if [ -z $KEYSTONE_DB_ROOT_PASSWD_IF_REMOTED ]; then
        echo "Your'are using Remote MySQL Database; "
        echo "Please set KEYSTONE_DB_ROOT_PASSWD_IF_REMOTED when running a container."
        exit 1;
    else
        KEYSTONE_DB_ROOT_PASSWD=$KEYSTONE_DB_ROOT_PASSWD_IF_REMOTED
    fi
fi

addgroup --system keystone >/dev/null || true
adduser --quiet --system --home /var/lib/keystone \
        --no-create-home --ingroup keystone --shell /bin/false \
        keystone || true

if [ "$(id -gn keystone)"  = "nogroup" ]
then
    usermod -g keystone keystone
fi

# create appropriate directories
mkdir -p /var/lib/keystone/ /etc/keystone/ /var/log/keystone/

# change the permissions on key directories
chown keystone:keystone -R /var/lib/keystone/ /etc/keystone/ /var/log/keystone/
chmod 0700 /var/lib/keystone/ /var/log/keystone/ /etc/keystone/

# Keystone Database and user
sed -i 's|KEYSTONE_DB_PASSWD|'"$KEYSTONE_DB_PASSWD"'|g' /keystone.sql
mysql -uroot -p$KEYSTONE_DB_ROOT_PASSWD -h $KEYSTONE_DB_HOST < /keystone.sql

# Update keystone.conf
sed -i "s/KEYSTONE_DB_PASSWORD/$KEYSTONE_DB_PASSWD/g" /etc/keystone/keystone.conf
sed -i "s/KEYSTONE_DB_HOST/$KEYSTONE_DB_HOST/g" /etc/keystone/keystone.conf

# Start memcached
/usr/bin/memcached -u root & >/dev/null || true

# Populate keystone database
su -s /bin/sh -c 'keystone-manage db_sync' keystone

# Initialize fernet
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

# Configure Apache2
echo "ServerName $HOSTNAME" >> /etc/apache2/apache2.conf

# Enable keystone service  
ln -s /etc/apache2/sites-available/keystone.conf /etc/apache2/sites-enabled/keystone.conf

# Start Apache2
service apache2 restart

# Bootstrap keystone
keystone-manage bootstrap --bootstrap-username admin \
		--bootstrap-password $KEYSTONE_ADMIN_PASSWORD \
		--bootstrap-project-name admin \
		--bootstrap-role-name admin \
		--bootstrap-service-name keystone \
		--bootstrap-admin-url "$HTTP://$HOSTNAME:35357/v3" \
		--bootstrap-public-url "$HTTP://$HOSTNAME:5000/v3" \
		--bootstrap-internal-url "$HTTP://$HOSTNAME:5000/v3"

# Write openrc to disk
cat > /root/openrc <<EOF
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=${KEYSTONE_ADMIN_PASSWORD}
export OS_AUTH_URL=$HTTP://${HOSTNAME}:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF
source /root/openrc

# Add users
for i in $(seq 1 5); do openstack user create --domain default --project admin --password redhat user$i; done

tail -f /dev/null