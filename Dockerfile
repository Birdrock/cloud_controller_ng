ARG BUILD_IMAGE=ruby:2.5.5-buster
FROM $BUILD_IMAGE
WORKDIR /cloud_controller_ng

ENV DEBIAN_FRONTEND=noninteractive
ENV BUNDLE_GEMFILE /cloud_controller_ng/Gemfile
ENV CLOUD_CONTROLLER_NG_CONFIG /config/cloud_controller_ng.yml
ENV C_INCLUDE_PATH /libpq/include
ENV DYNO #{spec.job.name}-#{spec.index}
ENV LANG en_US.UTF-8
ENV LIBRARY_PATH /libpq/lib
ENV RAILS_ENV production

RUN apt-get update && \
  apt-get install --no-install-recommends -y \
    ca-certificates \
    git \
    bash \
    build-essential \
    curl \
    libxml2-dev \
    libxslt-dev \
    libmariadb-dev \
    libssl-dev \
    tzdata \
    libpq-dev \
    tar \
    wget \
    sudo \
    jq \
    less \
    dnsutils \
    zip \
    unzip \
    libreadline-dev && \
  rm -rf /var/lib/apt/lists/*

COPY Gemfile .
COPY Gemfile.lock .

RUN gem install bundler -v 1.17.3 && \
    bundle config build.nokogiri --use-system-libraries && \
    bundle install --without test development

COPY . .

ENTRYPOINT ["/cloud_controller_ng/bin/cloud_controller", "-c", "/config/cloud_controller_ng.yml"]
