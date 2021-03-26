from ubuntu:20.04

RUN apt-get update && apt-get install -y wget jq iputils-ping telnet mysql-client

RUN mkdir -p /usr/local
RUN wget https://github.com/openark/orchestrator/releases/download/v3.2.4/orchestrator-3.2.4-linux-amd64.tar.gz
RUN tar xzfv orchestrator-3.2.4-linux-amd64.tar.gz
#RUN cp /usr/local/orchestrator/orchestrator-sample-sqlite.conf.json /usr/local/orchestrator/orchestrator.conf.json

WORKDIR /usr/local/orchestrator
CMD ["/usr/local/orchestrator/orchestrator", "http"]
