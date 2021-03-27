#!/bin/bash

run_sql_stmt () {
  local cmd='export MYSQL_PWD=111; mysql -u root -e "'
  cmd+=$2
  cmd+='"'
  docker-compose exec "$1" sh -c "$cmd"
}

run_sql_file () {
  local cmd='export MYSQL_PWD=111; mysql -u root <'
  cmd+=$2
  docker-compose exec "$1" sh -c "$cmd"
}

wait_for () {
  echo "===WAIT FOR SERVER ${1}==="
  until run_sql_stmt "${1}" \;
  do
      echo "Waiting for ${1} database connection..."
     sleep 5
  done
  run_sql_stmt "${1}" "SHOW MASTER STATUS\G"
}

# prep
sed 's/REPL_USER/mydb_repl_main/g' repl.sql  > repl_main.sql
sed 's/SERVER_ID/1/g' mysql.conf.cnf  > main-1/mysql.conf.cnf
sed 's/SERVER_ID/2/g' mysql.conf.cnf  > main-2/mysql.conf.cnf
sed 's/SERVER_ID/3/g' mysql.conf.cnf  > main-3/mysql.conf.cnf

# init containers
docker-compose down -v
docker-compose build
docker-compose up -d

# wait for servers
wait_for mysql-main-1
wait_for mysql-main-2
wait_for mysql-main-3

# get position from master
echo "===GET POSITION==="
MS_STATUS=`docker exec mysql-main-1 sh -c 'export MYSQL_PWD=111; mysql -u root -e "SHOW MASTER STATUS"'`
CURRENT_LOG=`echo $MS_STATUS | awk '{print $6}'`
CURRENT_POS=`echo $MS_STATUS | awk '{print $7}'`

# add replication user
echo "===ADDING REPLICATION USER==="
run_sql_file mysql-main-1 "/repl.sql"

# add orch user
echo "===ADDING ORCH USER==="
run_sql_file mysql-main-1 "/orch.sql"

# configure replication
echo "===CONFIG REPLICATION==="
start_slave_stmt="CHANGE MASTER TO MASTER_HOST='mysql-main-1',MASTER_USER='mydb_repl_main',MASTER_PASSWORD='mydb_repl_pwd',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
run_sql_stmt mysql-main-2 "$start_slave_stmt"
run_sql_stmt mysql-main-3 "$start_slave_stmt"

# test replication
echo "===TEST REPLICATION==="
run_sql_stmt mysql-main-2 "SHOW SLAVE STATUS\G"
run_sql_stmt mysql-main-3 "SHOW SLAVE STATUS\G"
