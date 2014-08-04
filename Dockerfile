FROM debian:7.5

MAINTAINER <Mathieu>

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update
RUN apt-get -q install -y erlang make git wget

RUN useradd -d /opt/fipes fipes


ADD Makefile /opt/fipes/
ADD erlang.mk /opt/fipes/
ADD include /opt/fipes/
ADD priv /opt/fipes/
ADD public /opt/fipes/
ADD src /opt/fipes/src

RUN chown -R fipes:fipes /opt/fipes

USER fipes
RUN cd /opt/fipes && make

CMD cd /opt/fipes/ && HOME=/opt/fipes erl -sname fipes@localhost -pa ebin -pa deps/*/ebin -boot start_sasl -s fipes

EXPOSE 3473
