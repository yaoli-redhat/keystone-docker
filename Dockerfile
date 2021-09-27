FROM python:3.7.4

EXPOSE 5000
ENV KEYSTONE_VERSION 19.0.0
ENV KEYSTONE_ADMIN_PASSWORD passw0rd
ENV KEYSTONE_DB_ROOT_PASSWD passw0rd
ENV KEYSTONE_DB_PASSWD passw0rd

LABEL version="$KEYSTONE_VERSION"
LABEL description="Openstack Keystone Docker Image Supporting HTTP/HTTPS"

RUN apt-get -y update \
    && apt-get install -y apache2 libapache2-mod-wsgi-py3 git memcached\
        libffi-dev python3-dev libssl-dev default-mysql-client libldap2-dev libsasl2-dev\
    && apt-get -y clean

RUN export DEBIAN_FRONTEND="noninteractive" \
    && echo "mysql-server mysql-server/root_password password $KEYSTONE_DB_ROOT_PASSWD" | debconf-set-selections \
    && echo "mysql-server mysql-server/root_password_again password $KEYSTONE_DB_ROOT_PASSWD" | debconf-set-selections \
    && apt-get -y update && apt-get install -y default-mysql-server && apt-get -y clean

RUN git clone -b ${KEYSTONE_VERSION} https://github.com/openstack/keystone.git

WORKDIR /keystone
RUN python -m pip uninstall pip -y && wget https://bootstrap.pypa.io/pip/get-pip.py && python get-pip.py &&  pip list && pip install pbr
RUN pip install -r requirements.txt \
    && PBR_VERSION=${KEYSTONE_VERSION} python setup.py install

RUN pip install osc-lib python-openstackclient PyMySql python-memcached \
    python-ldap ldappool
RUN mkdir /etc/keystone
RUN cp -r ./etc/* /etc/keystone/

COPY ./etc/keystone.conf /etc/keystone/keystone.conf
COPY keystone.sql /keystone.sql
COPY bootstrap.sh /bootstrap.sh
COPY ./keystone.wsgi.conf /etc/apache2/sites-available/keystone.conf

WORKDIR /root
CMD bash -x /bootstrap.sh
