ARG BASE
FROM $BASE

RUN apk add supervisor bash
RUN wget https://updater.swat.magento.com/launcher/launcher.linux-amd64.tar.gz && \
    tar -xf launcher.linux-amd64.tar.gz && \
    cp scheduler /usr/local/bin/ && \
    chmod 755 /usr/local/bin/scheduler
ADD ../swat-agent.ini /etc/supervisor.d/swat-agent.ini
CMD /usr/bin/supervisord
