FROM rocker/r-ver:4.5.2
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev libssl-dev libxml2-dev libfontconfig1-dev libharfbuzz-dev libfribidi-dev \
    libfreetype6-dev libpng-dev libtiff5-dev libjpeg-dev git && rm -rf /var/lib/apt/lists/*
RUN Rscript -e 'install.packages(c("data.table","R.utils","yaml","jsonlite","digest","glmnet","xgboost","ranger","pROC","ggplot2","scales","testthat","DBI","duckdb"), repos="https://cloud.r-project.org")'
WORKDIR /work
COPY . /work
# MIMIC-IV must be mounted at /data/mimic-iv-3.1 and the DUA respected; synthetic mode needs no data
ENV MIMIC_IV_DIR=/data/mimic-iv-3.1
CMD ["Rscript", "analysis/R/00_run_all.R"]
