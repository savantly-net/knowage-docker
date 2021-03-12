#!/bin/bash
set -e

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

file_env "DB_USER"
file_env "DB_PASS"
file_env "DB_DB"
file_env "DB_HOST"
file_env "DB_PORT"

# Wait for MySql
./wait-for-it.sh ${DB_HOST}:${DB_PORT} -- echo "DB Server is up!"

# Placeholder created after the first boot of the container
CONTAINER_INITIALIZED_PLACEHOLDER=/.CONTAINER_INITIALIZED

# Check if this is the first boot
if [ ! -f "$CONTAINER_INITIALIZED_PLACEHOLDER" ]
then
	file_env "HMAC_KEY"
	file_env "PASSWORD_ENCRYPTION_SECRET"
	file_env "PUBLIC_ADDRESS"

	# Generate default values for the optional env vars
	if [[ -z "$PUBLIC_ADDRESS" ]]
	then
	        #get the address of container
	        #example : default via 172.17.42.1 dev eth0 172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.109
	        PUBLIC_ADDRESS=`ip route | grep src | awk '{print $9}'`
	fi
	
	if [ -z "$HMAC_KEY" ]
	then
		echo "The HMAC_KEY environment variable is needed"
		exit -1
	fi
	
	if [ -z "$PASSWORD_ENCRYPTION_SECRET" ]
	then
		echo "The PASSWORD_ENCRYPTION_SECRET environment is needed"
		exit -1
	fi

	# more JAVA_OPTS
	export CATALINA_OPTS="$CATALINA_OPTS -Djdbc.drivers=org.postgresql.Driver"
	export LOG4J_LEVEL=INFO

	# Replace the address of container inside server.xml
	sed -i "s|http:\/\/.*:8080|http:\/\/${PUBLIC_ADDRESS}:8080|g" ${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml
	sed -i "s|http:\/\/.*:8080\/knowage|http:\/\/localhost:8080\/knowage|g" ${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml
	sed -i "s|http:\/\/localhost:8080|http:\/\/${PUBLIC_ADDRESS}:8080|g" ${KNOWAGE_DIRECTORY}/apache-tomcat/webapps/knowage/WEB-INF/web.xml
	
	# Insert knowage metadata into db if it doesn't exist
	export PGPASSWORD=${DB_PASS}
	ps_command_prefix="psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_DB}"
	result=`${ps_command_prefix} -t  -c "SELECT * FROM pg_catalog.pg_tables WHERE tablename LIKE '%SBI_%';"`
	if [ -z "$result" ]; then
		eval "${ps_command_prefix} -f ${SQL_SCRIPT_DIRECTORY}/PG_create.sql"
		eval "${ps_command_prefix} -f ${SQL_SCRIPT_DIRECTORY}/PG_create_quartz_schema.sql"
	fi

	# Replace JDBC Params 
	sed -i "s|JDBC_DRIVER_CLASS|org.postgresql.Driver|g" ${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml
	sed -i "s|JDBC_URL|jdbc:postgres://${DB_HOST}:${DB_PORT}/${DB_DB}|g" ${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml
	sed -i "s|JDBC_USER|${DB_USER}|g" ${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml
	sed -i "s|JDBC_PASSWORD|${DB_PASS}|g" ${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml
	
	# Set HMAC key
	sed -i "s|__HMAC-key__|${HMAC_KEY}|" ${KNOWAGE_DIRECTORY}/apache-tomcat/conf/server.xml
	
	# Set password encryption key
	echo $PASSWORD_ENCRYPTION_SECRET > ${KNOWAGE_DIRECTORY}/apache-tomcat/conf/passwordEncryptionSecret

	# Create the placeholder to prevent multiple initializations
	touch "$CONTAINER_INITIALIZED_PLACEHOLDER"
fi

exec "$@"

