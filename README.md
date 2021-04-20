Docker MySQL orchestrator
========================


```
./build.sh
```


http://localhost:3003

./resources/bin/orchestrator-client -c register-candidate -i mysql-main-3:3306 -R prefer

./resources/bin/orchestrator-client -c register-candidate -i mysql-main-2:3306 -R must_not