# build layer
FROM golang:1.15

RUN apt-get update && \
  apt-get install -y rsync
WORKDIR /go/src/
RUN git clone https://github.com/openark/orchestrator.git
RUN cd orchestrator && ./script/build

# run layer
FROM ubuntu:20.04

RUN apt-get update && \
  apt-get install -y jq curl iputils-ping telnet && \
  rm -rf /var/lib/apt/lists/*
RUN mkdir -p /usr/local/orchestrator
COPY --from=0 /go/src/orchestrator/bin /usr/local/orchestrator/
WORKDIR /usr/local/orchestrator
CMD ["/usr/local/orchestrator/orchestrator", "http"]
