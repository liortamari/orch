FROM mysql:5.7

RUN apt-get update && \
  apt-get install -y jq curl iputils-ping telnet procps vim && \
  rm -rf /var/lib/apt/lists/*