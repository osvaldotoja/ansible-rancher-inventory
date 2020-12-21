FROM alpine:3.11

# latest 2.9.16
ENV ANSIBLE_VERSION=2.9.11
ENV ANSIBLE_LINT_VERSION=4.2.0

RUN apk update \
  && apk add --no-cache --progress python3 openssl \
  ca-certificates git openssh sshpass \
  && apk --update add --virtual build-dependencies \
  python3-dev libffi-dev openssl-dev build-base bash \
  tar unzip \
  && rm -rf /var/cache/apk/* 

RUN pip3 install --upgrade pip \
  && pip3 install jmespath requests  ansible==${ANSIBLE_VERSION} \
  && pip3 install ansible-lint==${ANSIBLE_LINT_VERSION}

COPY ./entrypoint.sh /entrypoint.sh

ENTRYPOINT ["bash","/entrypoint.sh"]
