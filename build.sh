#!/bin/bash

function run_sql_stmt() {
  local cmd="export MYSQL_PWD=111; mysql -u root ${3} -e \"${2}\""
  docker-compose exec "${1}" sh -c "${cmd}"
}

function run_sql_stmt_quiet() {
  local cmd="export MYSQL_PWD=111; mysql -u root -e \"${2}\""
  docker-compose exec "${1}" sh -c "${cmd}" >/dev/null 2>&1
}

function run_sql_file() {
  local cmd="export MYSQL_PWD=111; mysql -u root < ${2}"
  docker-compose exec "${1}" sh -c "${cmd}"
}

function export_dump() {
  local cmd="export MYSQL_PWD=111; mysqldump --all-databases --single-transaction --triggers --routines --user=root > /dump-vol/dump-${1}.sql"
  docker-compose exec "${1}" sh -c "${cmd}" >/dev/null 2>&1
}

function import_dump() {
  run_sql_stmt "${1}" "RESET MASTER;"
  run_sql_file "${1}" "/dump-vol/dump-${2}.sql"
}

function change_master() {
  local slave_stmt="CHANGE MASTER TO MASTER_HOST='${2}',MASTER_USER='${3}',MASTER_PASSWORD='mydb_repl_pwd',MASTER_AUTO_POSITION=1; START SLAVE;"
  run_sql_stmt "${1}" "${slave_stmt}"
}

function discover() {
  local srv="ORCHESTRATOR_API=\"http://orch-1:3000/api http://orch-2:3000/api http://orch-3:3000/api\""
  local discover_cmd="${srv} /sql/orchestrator-client.sh -c discover -i ${1}"
  local register_cmd="${srv} /sql/orchestrator-client.sh -c register-candidate -i ${1} -R ${2}"
  docker-compose exec "${1}" sh -c "${discover_cmd}"
  docker-compose exec "${1}" sh -c "${register_cmd}"
}

function insert_data() {
  local insert_stmt="create table code(code int); insert into code values ${2}"
  run_sql_stmt "${1}" "${insert_stmt}" mydb
}

function compare_repl() {
  res1=$(run_sql_stmt "${1}" "SELECT * FROM code ORDER BY code" mydb)
  res2=$(run_sql_stmt "${2}" "SELECT * FROM code ORDER BY code" mydb)
  if [ "${res1}" != "${res2}" ]; then
    echo "${res1}"
    echo "${res2}"
    echo "ERRORS"
    exit 1
  fi
}

function check_exit() {
  err=$(docker-compose ps | grep Exit)
  if [ -n "$err" ]; then
    echo "ERRORS"
    exit 1
  fi
}

function wait_for() {
  echo "===WAIT FOR SERVER ${1}==="
  until run_sql_stmt_quiet "${1}" \;; do
    sleep 1
    echo -n "."
    check_exit
  done
  run_sql_stmt "${1}" "SHOW MASTER STATUS\G"
}

# prep
sed 's/REPL_USER/mydb_repl_main/g' ./mysql/sql/repl.sql > ./mysql/sql/repl_main.sql
sed 's/REPL_USER/mydb_repl_misc/g' ./mysql/sql/repl.sql > ./mysql/sql/repl_misc.sql
sed 's/SERVER_ID/100/g' ./mysql/conf/mysql.conf.cnf > ./mysql/conf/mysql_main_1.conf.cnf
sed 's/SERVER_ID/200/g' ./mysql/conf/mysql.conf.cnf > ./mysql/conf/mysql_main_2.conf.cnf
sed 's/SERVER_ID/300/g' ./mysql/conf/mysql.conf.cnf > ./mysql/conf/mysql_main_3.conf.cnf
sed 's/SERVER_ID/10/g' ./mysql/conf/mysql.conf.cnf > ./mysql/conf/mysql_misc_a.conf.cnf
sed 's/SERVER_ID/20/g' ./mysql/conf/mysql.conf.cnf > ./mysql/conf/mysql_misc_b.conf.cnf
sed 's/ORCH_ID/orch-1/g' ./orch/conf.json > ./orch/conf-1.json
sed 's/ORCH_ID/orch-2/g' ./orch/conf.json > ./orch/conf-2.json
sed 's/ORCH_ID/orch-3/g' ./orch/conf.json > ./orch/conf-3.json

# init containers
docker-compose down -v --remove-orphans
docker-compose build
docker-compose up -d

# wait for servers
wait_for mysql-main-1
wait_for mysql-main-2
wait_for mysql-main-3
wait_for mysql-misc-a
wait_for mysql-misc-b

# enable masters
run_sql_stmt mysql-main-1 "SET GLOBAL READ_ONLY=0;"
run_sql_stmt mysql-misc-a "SET GLOBAL READ_ONLY=0;"

# dump master
echo "===EXPORT DUMP MASTER==="
export_dump mysql-main-1
export_dump mysql-misc-a

# insert data
echo "===INSERT DATA==="
insert_data mysql-main-1 "(100), (200), (300)"
insert_data mysql-misc-a "(5555), (6666)"

# add replication user
echo "===ADDING REPLICATION USER==="
run_sql_file mysql-main-1 "/sql/repl_main.sql"
run_sql_file mysql-misc-a "/sql/repl_misc.sql"

# add orch user
echo "===ADDING ORCH USER==="
run_sql_file mysql-main-1 "/sql/orch.sql"
run_sql_file mysql-misc-a "/sql/orch.sql"

# restore slave
echo "===IMPORT DUMP SLAVE==="
import_dump mysql-main-2 mysql-main-1
import_dump mysql-main-3 mysql-main-1
import_dump mysql-misc-b mysql-misc-a

# configure replication
echo "===CONFIG REPLICATION==="
change_master mysql-main-2 mysql-main-1 mydb_repl_main
change_master mysql-main-3 mysql-main-1 mydb_repl_main
change_master mysql-misc-b mysql-misc-a mydb_repl_misc

# show slave
run_sql_stmt mysql-main-2 "SHOW SLAVE STATUS\G"
run_sql_stmt mysql-main-3 "SHOW SLAVE STATUS\G"
run_sql_stmt mysql-misc-b "SHOW SLAVE STATUS\G"

# check which orch is leader
echo "===FINDING ORCH LEADER==="
docker-compose logs | grep "state: Leader" | head -n1

# discover
echo "===DISCOVER==="
discover mysql-main-1 prefer
discover mysql-main-2 prefer
discover mysql-main-3 must_not
discover mysql-misc-a prefer
discover mysql-misc-b prefer

# test replication
echo "===TEST REPLICATION==="
compare_repl mysql-main-1 mysql-main-2
compare_repl mysql-main-1 mysql-main-3
compare_repl mysql-misc-a mysql-misc-b

echo "===BUILD SUCCESS==="
