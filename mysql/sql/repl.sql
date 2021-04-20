CREATE USER 'REPL_USER'@'%' IDENTIFIED BY 'mydb_repl_pwd';
GRANT REPLICATION SLAVE ON *.* TO "REPL_USER"@"%" IDENTIFIED BY "mydb_repl_pwd";
FLUSH PRIVILEGES;