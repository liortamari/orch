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

# init containers
docker-compose down -v
docker-compose build
docker-compose up -d

# wait for master
echo "===WAIT FOR MASTER==="
until run_sql_stmt mysql-master \;
do
    echo "Waiting for mysql-master database connection..."
    sleep 5
done

# test master
run_sql_stmt mysql-master "SHOW MASTER STATUS\G"

# wait for slave
echo "===WAIT FOR SLAVE==="
until run_sql_stmt mysql-slave \;
do
    echo "Waiting for mysql-slave database connection..."
    sleep 5
done

# test slave
run_sql_stmt mysql-master "SHOW MASTER STATUS\G"

# get position from master
echo "===GET POSITION==="
MS_STATUS=`docker exec mysql-master sh -c 'export MYSQL_PWD=111; mysql -u root -e "SHOW MASTER STATUS"'`
CURRENT_LOG=`echo $MS_STATUS | awk '{print $6}'`
CURRENT_POS=`echo $MS_STATUS | awk '{print $7}'`

# add replication user
echo "===MASTER+SLAVE ARE UP, ADDING REPLICATION USER==="
run_sql_file mysql-master "/repl_user.sql"

# add orch user
run_sql_file mysql-master "/orch.sql"

# configure replication
echo "===CONFIG REPLICATION==="
start_slave_stmt="CHANGE MASTER TO MASTER_HOST='mysql-master',MASTER_USER='mydb_repl_user',MASTER_PASSWORD='mydb_repl_pwd',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
run_sql_stmt mysql-slave "$start_slave_stmt"

# test replication
echo "===TEST REPLICATION==="
run_sql_stmt mysql-slave "SHOW SLAVE STATUS\G"

# test orch user
echo "===TEST ORCHESTRATOR==="
sleep 5
docker-compose exec mysql-master sh -c "export MYSQL_PWD=orc_topology_password; mysql -u orchestrator -e 'SHOW MASTER STATUS\G'"
docker-compose exec mysql-slave sh -c "export MYSQL_PWD=orc_topology_password; mysql -u orchestrator -e 'SHOW SLAVE STATUS\G'"


