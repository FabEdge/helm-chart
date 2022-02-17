FROM centos:8
WORKDIR /opt/
COPY cluster/ /opt/

ENV ANSIBLE_HOST_KEY_CHECKING False
ENV ANSIBLE_SSH_ARGS '-o ControlMaster=auto -o ControlPersist=90m -o ConnectionAttempts=100 -o UserKnownHostsFile=/dev/null'
ENV ANSIBLE_TRANSFORM_INVALID_GROUP_CHARS ignore

RUN mkdir /root/.ssh/ && \
    cp /opt/.ssh/id_rsa* /root/.ssh/ && \
    chmod 600 /root/.ssh/id_rsa

RUN yum -y install epel-release && \
    yum -y update && \
    yum -y install python3-devel openssl-devel sshpass openssh-clients gcc openssl git && \
    yum clean all && \
    rm -rf /var/cache/yum/*

RUN git clone -b v2.15.0 https://github.com/kubernetes-sigs/kubespray.git

RUN ln -s /usr/bin/python3 /usr/bin/python && \
    python -m pip install pip -U && \
    python -m pip install -r kubespray/tests/requirements.txt && \
    python -m pip install -r kubespray/requirements.txt && \
    python -m pip install ansible-runner==1.4.6 && \
    mkdir /etc/ansible/

RUN ansible-galaxy collection install community.kubernetes:==1.2.1
