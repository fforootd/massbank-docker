FROM ubuntu:16.04

ARG MBUSERNAME=massbankuser
ARG PASSWORD=massbankpassword

RUN dpkg --add-architecture i386

RUN apt-get update

RUN apt-get install -y -q \
    libc6:i386 \
    apache2 apache2-utils libcgi-pm-perl \
    mariadb-client \
    default-jdk tomcat8 libapache2-mod-jk \
    unzip joe lynx \
    build-essential libmysqlclient-dev \
    mc xterm mysql-workbench \
    r-base-core \
    openbabel \
    ntp \
    maven \
    php php-curl php-gd \
    php-mbstring php-mysql \
    libapache2-mod-php php-mcrypt \
    php-zip php-json php-opcache php-xml \
    git \
    mcrypt

RUN git clone https://github.com/MassBank/MassBank-web

RUN cp -r /MassBank-web/* /

# Install Files Path
ARG INST_ROOT_PATH=$PWD/modules
ARG INST_HTDOCS_PATH=$INST_ROOT_PATH/apache/html
ARG INST_ERROR_PATH=$INST_ROOT_PATH/apache/error
ARG INST_CONF_PATH=$INST_ROOT_PATH/apache/conf

# Apache Path
ARG APACHE_HTDOCS_PATH=/var/www/html
ARG APACHE_ERROR_PATH=/var/www/error
ARG APACHE_CACHE_PATH=/var/cache/apache2

# Tomcat Path
ARG DEST_TOMCAT_PATH=/var/lib/tomcat8

RUN echo
RUN echo ">> service stop"
RUN service tomcat8 stop 
RUN service apache2 stop

RUN echo "apache files copy"
RUN cp -r $INST_HTDOCS_PATH/.  $APACHE_HTDOCS_PATH
RUN cp -r $INST_ERROR_PATH/. $APACHE_ERROR_PATH
RUN chown -R www-data:www-data /var/www/*

RUN echo "enable required apache modules"
RUN a2enmod rewrite
RUN a2enmod authz_groupfile
RUN a2enmod cgid
RUN a2enmod jk

RUN echo "set mbadmin username to $MBUSERNAME and password to $PASSWORD"
RUN htpasswd -b -c /etc/apache2/.htpasswd $MBUSERNAME $PASSWORD

RUN echo "enable MassBank site"
RUN install -m 644 -o root -g root $INST_CONF_PATH/010-a2site-massbank.conf /etc/apache2/sites-available
RUN a2ensite 010-a2site-massbank

RUN echo "compile and install Search.cgi"
RUN ls -latr
RUN (cd ./modules/Search.cgi/ ; make clean ; make )
RUN install -m 755 -o www-data -g www-data ./modules/Search.cgi/Search.cgi $APACHE_HTDOCS_PATH/MassBank/cgi-bin/

RUN echo "deploy permissions to apache2"
RUN chown -R www-data:www-data $APACHE_CACHE_PATH

RUN echo "compile MassBank webapp"
# set user and password in axis2.xml
RUN sed -i "s|<parameter name=\"userName\">admin</parameter>|<parameter name=\"userName\">$MBUSERNAME</parameter>|g" \
	MassBank-Project/api/conf/axis2.xml
RUN sed -i "s|<parameter name=\"password\">axis2</parameter>|<parameter name=\"password\">$PASSWORD</parameter>|g" \
	MassBank-Project/api/conf/axis2.xml
RUN (cd MassBank-Project; mvn -q install)

RUN echo "copy webapp to tomcat"
RUN cp MassBank-Project/MassBank/target/MassBank.war $DEST_TOMCAT_PATH/webapps/
RUN cp MassBank-Project/api/target/api.war $DEST_TOMCAT_PATH/webapps/
# add tomcat folders until
# https://bugs.launchpad.net/ubuntu/+source/tomcat7/+bug/1482893
# is fixed
ARG TOMCAT_SHARE_PATH=/usr/share/tomcat8
ARG TOMCAT_CACHE_PATH=/var/cache/tomcat8
RUN mkdir $TOMCAT_SHARE_PATH/common
RUN mkdir $TOMCAT_SHARE_PATH/common/classes
RUN mkdir $TOMCAT_SHARE_PATH/server
RUN mkdir $TOMCAT_SHARE_PATH/server/classes
RUN mkdir $TOMCAT_SHARE_PATH/shared
RUN mkdir $TOMCAT_SHARE_PATH/shared/classes
RUN mkdir $TOMCAT_CACHE_PATH/temp

RUN echo "increase default maximum JAVA heap size for Tomcat"
RUN sed -i 's/Xmx128m/Xmx512m/g' /usr/share/tomcat8/defaults.template
RUN sed -i 's/Xmx128m/Xmx512m/g' /etc/default/tomcat8


RUN echo "configure Tomcat if not already done"
RUN if ! grep '^<Connector port="8009" protocol="AJP/1.3" redirectPort="8443" />$' $DEST_TOMCAT_PATH/conf/server.xml ; then sed -i -e 's#<!-- Define an AJP 1.3 Connector on port 8009 -->#<!-- Define an AJP 1.3 Connector on port 8009 -->\n<Connector port="8009" protocol="AJP/1.3" redirectPort="8443" />#' $DEST_TOMCAT_PATH/conf/server.xml ; fi 


RUN echo "allow webapp write permission to apache folder"
RUN chown -R tomcat8:tomcat8 $APACHE_HTDOCS_PATH/MassBank/DB/
RUN chown -R tomcat8:tomcat8 $APACHE_HTDOCS_PATH/MassBank/massbank.conf
RUN chown -R tomcat8:tomcat8 $APACHE_HTDOCS_PATH/MassBank/svn_wc/

## This is a workaround
RUN cp -r $APACHE_HTDOCS_PATH/MassBank/massbank.conf /var/lib/tomcat8/massbank.conf

# Deploy permissions to tomcat
RUN chown -R tomcat8:tomcat8 $TOMCAT_SHARE_PATH
RUN find $TOMCAT_SHARE_PATH -type d -exec chmod 755 {} \;
RUN find $TOMCAT_SHARE_PATH -type f -exec chmod 644 {} \;
RUN find $TOMCAT_SHARE_PATH/bin -name "*.sh" -type f -exec chmod 755 {} \;
RUN chown -R tomcat8:tomcat8 $TOMCAT_CACHE_PATH/temp
RUN find $TOMCAT_CACHE_PATH -type d -exec chmod 755 {} \;

# Deploy permissions
RUN find $APACHE_HTDOCS_PATH -type d -exec chmod 755 {} \;
RUN find $APACHE_HTDOCS_PATH -type f -exec chmod 644 {} \;
RUN find $APACHE_HTDOCS_PATH/MassBank -name "*.cgi" -type f -exec chmod 755 {} \;

RUN echo "append curation scripts to crontab"
RUN IFS='<';echo $(sed '$i0 0   * * *   www-data    bash /var/www/html/MassBank/script/Sitemap.sh' /etc/crontab) > /etc/crontab
RUN IFS='<';echo $(sed '$i0 0   * * *   www-data    Rscript /var/www/html/MassBank/script/Statistics.R' /etc/crontab) > /etc/crontab 
# IFS='<';echo $(sed '$i0 0   * * *   tomcat8     rm -f /var/lib/tomcat8/webapps/MassBank/temp/*.svg' /etc/crontab) > /etc/crontab # done by tomcat filecleaner?
RUN IFS='<';echo $(sed '$i0 0   * * *   tomcat8     rm -f /var/cache/tomcat8/temp/*' /etc/crontab) > /etc/crontab

RUN echo
RUN echo
RUN echo "Done."
RUN echo
RUN echo "Please edit \"FrontServer URL\" of \""$APACHE_HTDOCS_PATH"/MassBank/massbank.conf\" appropriately."
RUN echo
RUN echo

RUN sed -i 's/127.0.0.1/db/g' /var/www/html/MassBank/cgi-bin/DB_HOST_NAME

RUN cat /var/www/html/MassBank/cgi-bin/DB_HOST_NAME