# Pinned 7.4.0-SNAPSHOT
FROM knowagelabs/knowage-server-docker@sha256:da7cfedc628a35cb5d136ba4d8d369f026f8672420448582966f5915195fb5b3

#FROM knowagelabs/knowage-server-docker:7.4
#FROM knowagelabs/knowage-server-docker:7.2
#FROM knowagelabs/knowage-server-docker:8.0.0-SNAPSHOT

# Knowage home directory
ENV KNOWAGE_DIRECTORY /home/knowage

ARG METRICS_JAR="https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.15.0/jmx_prometheus_javaagent-0.15.0.jar"
# Tomcat sub-directories
ARG TOMCAT_HOME=${KNOWAGE_DIRECTORY}/apache-tomcat
ARG TOMCAT_BIN=${TOMCAT_HOME}/bin
ARG TOMCAT_CONF=${TOMCAT_HOME}/conf
ARG TOMCAT_LIB=${TOMCAT_HOME}/lib
ARG TOMCAT_WEBAPPS=${TOMCAT_HOME}/webapps
ARG TOMCAT_RESOURCES=${TOMCAT_HOME}/resources
ARG TOMCAT_LOGS=${TOMCAT_HOME}/logs

# Add OAuth support
COPY knowage/WEB-INF/lib/knowageoauth2-7.4.0-SNAPSHOT.jar ${TOMCAT_WEBAPPS}/knowage/WEB-INF/lib/

# JVM metrics exporter 
RUN wget -q -O  ${KNOWAGE_DIRECTORY}/metrics.jar ${METRICS_JAR}

# Reset JAVA_OPTS
RUN echo "" > ${TOMCAT_BIN}/setenv.sh
# We reset JAVA_OPTS to get rid of this - 
# RUN echo "export JAVA_OPTS=\"\$JAVA_OPTS -XX:+UnlockExperimentalVMOptions -XX:+UseCGroupMemoryLimitForHeap\"" >> ${TOMCAT_BIN}/setenv.sh

# Add metric agent 
RUN echo "export JAVA_OPTS=\"\$JAVA_OPTS -javaagent:${KNOWAGE_DIRECTORY}/metrics.jar=0.0.0.0:8081:${KNOWAGE_DIRECTORY}/metrics.yml\"" >> ${TOMCAT_BIN}/setenv.sh

# Expose JMX 
RUN echo "export JAVA_OPTS=\"\$JAVA_OPTS -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote=true \
 -Djava.rmi.server.hostname=127.0.0.1 -Dcom.sun.management.jmxremote.port=9999 -Dcom.sun.management.jmxremote.rmi.port=9999 \
 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false\"" >> ${TOMCAT_BIN}/setenv.sh

# Enable Security Manager
RUN echo "export JAVA_OPTS=\"\$JAVA_OPTS -Djava.security.manager -Djava.security.policy=\$CATALINA_HOME/conf/knowage-default.policy\"" >> ${TOMCAT_BIN}/setenv.sh

# Memory optimization
RUN echo "export JAVA_OPTS=\"\$JAVA_OPTS -XX:MetaspaceSize=250M -XX:InitialRAMPercentage=50.0 -XX:MinRAMPercentage=50.0  -XX:MaxRAMPercentage=90.0\"" >> ${TOMCAT_BIN}/setenv.sh

# GC logs
#RUN echo "export JAVA_OPTS=\"\$JAVA_OPTS -XX:+PrintGCDateStamps -verbose:gc -XX:+PrintGCDetails -Xloggc:${TOMCAT_LOGS}/gc.log -XX:-HeapDumpOnOutOfMemoryError\"" >> ${TOMCAT_BIN}/setenv.sh

RUN echo "" >> ${TOMCAT_WEBAPPS}/knowage/WEB-INF/classes/log4j.properties && \
    echo "log4j.logger.org.apache.coyote.http2.level=INFO, knowage" >> ${TOMCAT_WEBAPPS}/knowage/WEB-INF/classes/log4j.properties && \
    echo "log4j.logger.org.apache.tomcat.websocket.level=INFO, knowage" >> ${TOMCAT_WEBAPPS}/knowage/WEB-INF/classes/log4j.properties && \
    echo "log4j.logger.it.eng.knowage.security=INFO, knowage" >> ${TOMCAT_WEBAPPS}/knowage/WEB-INF/classes/log4j.properties && \
    echo "log4j.logger.it.eng.knowage.security.oauth2=DEBUG, knowage" >> ${TOMCAT_WEBAPPS}/knowage/WEB-INF/classes/log4j.properties

COPY metrics.yml ./

# COPY entrypoint.sh ./
COPY server.xml ${TOMCAT_CONF}/
COPY knowage/WEB-INF/web.xml ./apache-tomcat/webapps/knowage/WEB-INF/web.xml