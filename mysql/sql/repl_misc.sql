CREATE USER 'mydb_repl_misc'@'%' IDENTIFIED BY 'mydb_repl_pwd';
GRANT REPLICATION SLAVE ON *.* TO "mydb_repl_misc"@"%" IDENTIFIED BY "mydb_repl_pwd";
FLUSH PRIVILEGES;
