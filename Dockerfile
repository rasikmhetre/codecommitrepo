FROM debian

ADD https://d3pxv6yz143wms.cloudfront.net/8.232.09.1/java-1.8.0-amazon-corretto-jdk_8.232.09-1_amd64.deb /opt/

RUN apt-get update && apt-get install java-common

RUN dpkg -i /opt/java-1.8.0-amazon-corretto-jdk_8.232.09-1_amd64.deb

ADD http://apachemirror.wuchna.com/tomcat/tomcat-9/v9.0.27/bin/apache-tomcat-9.0.27.tar.gz /opt/ 

RUN tar xvf /opt/apache-tomcat-9.0.27.tar.gz -C /opt/

WORKDIR /opt/apache-tomcat-9.0.27

CMD ["bin/catalina.sh","run"] 
