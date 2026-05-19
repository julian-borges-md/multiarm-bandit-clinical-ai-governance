FROM rocker/r-ver:4.3.2

## System dependencies commonly required for R packages
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libgit2-dev \
    libglpk-dev \
    libxt-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

## Set working directory
WORKDIR /app

## Copy repository files (no data)
COPY . /app

## Install renv and restore R environment
RUN R -e "install.packages('renv', repos='https://cloud.r-project.org')"
RUN R -e "renv::restore(prompt = FALSE)"

## Default command
CMD ["R"]
