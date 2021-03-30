#!/bin/bash

function run_sql_stmt () {
  local cmd="export MYSQL_PWD=111; mysql -u root ${3} -e \"${2}\""
  docker-compose exec "${1}" sh -c "${cmd}"
}

function run_sql_stmt_quiet () {
  local cmd="export MYSQL_PWD=111; mysql -u root -e \"${2}\""
  docker-compose exec "${1}" sh -c "${cmd}" > /dev/null 2>&1
}

function run_sql_file () {
  local cmd="export MYSQL_PWD=111; mysql -u root < ${2}"
  docker-compose exec "${1}" sh -c "${cmd}"
}

function export_dump() {
  local cmd="export MYSQL_PWD=111; mysqldump --all-databases --single-transaction --triggers --routines --user=root > /dump-vol/dump-${1}.sql"
  docker-compose exec "${1}" sh -c "${cmd}" > /dev/null 2>&1
}

function import_dump() {
  run_sql_stmt "${1}" "RESET MASTER;"
  run_sql_file "${1}" "/dump-vol/dump-${2}.sql"
}

function check_exit() {
  err=$(docker-compose ps | grep Exit)
  if [ -n "$err" ]
  then
    echo "ERRORS"
    exit 1
  fi
}

function wait_for () {
  echo "===WAIT FOR SERVER ${1}==="
  until run_sql_stmt_quiet "${1}" \;
  do
    sleep 1
    echo -n "."
    check_exit
  done
  run_sql_stmt "${1}" "SHOW MASTER STATUS\G"
}

# prep
sed 's/REPL_USER/mydb_repl_main/g' repl.sql  > repl_main.sql
sed 's/REPL_USER/mydb_repl_misc/g' repl.sql  > repl_misc.sql
sed 's/SERVER_ID/100/g' mysql.conf.cnf  > main-1/mysql.conf.cnf
sed 's/SERVER_ID/200/g' mysql.conf.cnf  > main-2/mysql.conf.cnf
sed 's/SERVER_ID/300/g' mysql.conf.cnf  > main-3/mysql.conf.cnf
sed 's/SERVER_ID/10/g' mysql.conf.cnf  > misc-a/mysql.conf.cnf
sed 's/SERVER_ID/20/g' mysql.conf.cnf  > misc-b/mysql.conf.cnf

# init containers
docker-compose down -v
docker-compose build
docker-compose up -d

# wait for servers
wait_for mysql-main-1
wait_for mysql-main-2
wait_for mysql-main-3
wait_for mysql-misc-a
wait_for mysql-misc-b

# get position from master
echo "===GET POSITION==="
MAIN_STATUS=`docker exec mysql-main-1 sh -c 'export MYSQL_PWD=111; mysql -u root -e "SHOW MASTER STATUS"'`
MAIN_CURRENT_LOG=`echo $MAIN_STATUS | awk '{print $6}'`
MAIN_CURRENT_POS=`echo $MAIN_STATUS | awk '{print $7}'`
MISC_STATUS=`docker exec mysql-misc-a sh -c 'export MYSQL_PWD=111; mysql -u root -e "SHOW MASTER STATUS"'`
MISC_CURRENT_LOG=`echo $MISC_STATUS | awk '{print $6}'`
MISC_CURRENT_POS=`echo $MISC_STATUS | awk '{print $7}'`

# dump master
echo "===EXPORT DUMP MASTER==="
export_dump mysql-main-1
export_dump mysql-misc-a

# insert data
echo "===INSERT DATA==="
main_insert_stmt='create table code(code int); insert into code values (100), (200), (300)'
run_sql_stmt mysql-main-1 "${main_insert_stmt}" mydb
misc_insert_stmt='create table code(code int); insert into code values (5555), (6666)'
run_sql_stmt mysql-misc-a "${misc_insert_stmt}" mydb

# add replication user
echo "===ADDING REPLICATION USER==="
run_sql_file mysql-main-1 "/repl.sql"
run_sql_file mysql-misc-a "/repl.sql"

# add orch user
echo "===ADDING ORCH USER==="
run_sql_file mysql-main-1 "/orch.sql"
run_sql_file mysql-misc-a "/orch.sql"

# restore slave
echo "===IMPORT DUMP SLAVE==="
import_dump mysql-main-2 mysql-main-1
import_dump mysql-main-3 mysql-main-1
import_dump mysql-misc-b mysql-misc-a

# configure replication
echo "===CONFIG REPLICATION==="
main_slave_stmt="CHANGE MASTER TO MASTER_HOST='mysql-main-1',MASTER_USER='mydb_repl_main',MASTER_PASSWORD='mydb_repl_pwd',MASTER_LOG_FILE='${MAIN_CURRENT_LOG}',MASTER_LOG_POS=${MAIN_CURRENT_POS}; START SLAVE;"
run_sql_stmt mysql-main-2 "${main_slave_stmt}"
run_sql_stmt mysql-main-3 "${main_slave_stmt}"
misc_slave_stmt="CHANGE MASTER TO MASTER_HOST='mysql-misc-a',MASTER_USER='mydb_repl_misc',MASTER_PASSWORD='mydb_repl_pwd',MASTER_LOG_FILE='${MISC_CURRENT_LOG}',MASTER_LOG_POS=${MISC_CURRENT_POS}; START SLAVE;"
run_sql_stmt mysql-misc-b "${misc_slave_stmt}"

# test replication
echo "===TEST REPLICATION==="
run_sql_stmt mysql-main-2 "SHOW SLAVE STATUS\G"
run_sql_stmt mysql-main-3 "SHOW SLAVE STATUS\G"
run_sql_stmt mysql-misc-b "SHOW SLAVE STATUS\G"
