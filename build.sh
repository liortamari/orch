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
sleep 10
until run_sql_stmt mysql_master \;
do
    echo "Waiting for mysql_master database connection..."
    sleep 4
done

# test master
run_sql_stmt mysql_master "SHOW MASTER STATUS\G"

# wait for slave
echo "===WAIT FOR SLAVE==="
until run_sql_stmt mysql_slave \;
do
    echo "Waiting for mysql_slave database connection..."
    sleep 4
done

# test slave
run_sql_stmt mysql_master "SHOW MASTER STATUS\G"

# get position from master
echo "===GET POSITION==="
MS_STATUS=`docker exec mysql_master sh -c 'export MYSQL_PWD=111; mysql -u root -e "SHOW MASTER STATUS"'`
CURRENT_LOG=`echo $MS_STATUS | awk '{print $6}'`
CURRENT_POS=`echo $MS_STATUS | awk '{print $7}'`

# add replication user
echo "===MASTER+SLAVE ARE UP, ADDING REPLICATION USER==="
run_sql_file mysql_master "/repl_user.sql"

# add orch user
run_sql_file mysql_master "/orch.sql"

# configure replication
echo "===CONFIG REPLICATION==="
start_slave_stmt="CHANGE MASTER TO MASTER_HOST='mysql_master',MASTER_USER='mydb_repl_user',MASTER_PASSWORD='mydb_repl_pwd',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
start_slave_cmd='export MYSQL_PWD=111; mysql -u root -e "'
start_slave_cmd+="$start_slave_stmt"
start_slave_cmd+='"'
docker-compose exec mysql_slave sh -c "$start_slave_cmd"

# test replication
echo "===TEST REPLICATION==="
run_sql_stmt mysql_slave "SHOW SLAVE STATUS\G"

# test orch user
echo "===TEST ORCHESTRATOR==="
sleep 3
docker-compose exec mysql_master sh -c "export MYSQL_PWD=orc_topology_password; mysql -u orchestrator -e 'SHOW MASTER STATUS\G'"
docker-compose exec mysql_slave sh -c "export MYSQL_PWD=orc_topology_password; mysql -u orchestrator -e 'SHOW SLAVE STATUS\G'"


