CREATE USER 'orchestrator'@'%' IDENTIFIED BY 'orc_topology_password';
GRANT SUPER, PROCESS, REPLICATION SLAVE, REPLICATION CLIENT, RELOAD ON *.* TO 'orchestrator'@'%';
GRANT SELECT ON meta.* TO 'orchestrator'@'%';
GRANT SELECT ON performance_schema.replication_group_members TO 'orchestrator'@'%';
FLUSH PRIVILEGES;