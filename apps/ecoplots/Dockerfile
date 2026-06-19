FROM rocker/shiny:4.4.3

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      libcurl4-openssl-dev \
      libssl-dev \
      libxml2-dev \
      libcairo2-dev \
      libxt-dev \
      curl \
      python3 \
      python3-pip \
      pandoc \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --break-system-packages --no-cache-dir \
    matplotlib \
    numpy \
    pandas \
    pillow

RUN install2.r --error --skipinstalled \
    data.table \
    dplyr \
    DT \
    ggplot2 \
    reshape2 \
    scales \
    shiny \
    shinydashboard \
    shinyjs \
    shinyauthr \
    shinyWidgets

COPY deploy/shiny-server.conf /etc/shiny-server/shiny-server.conf
COPY EcoPlots/app.R /srv/shiny-server/EcoPlots/app.R
COPY python /opt/ecoplots/python

RUN chown -R shiny:shiny /srv/shiny-server /var/log/shiny-server

EXPOSE 3838

CMD ["/usr/bin/shiny-server"]
