FROM centos:7

ENV container=docker

RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \
  rm -f /lib/systemd/system/multi-user.target.wants/*;\
  rm -f /etc/systemd/system/*.wants/*;\
  rm -f /lib/systemd/system/local-fs.target.wants/*; \
  rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
  rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
  rm -f /lib/systemd/system/basic.target.wants/*;\
  rm -f /lib/systemd/system/anaconda.target.wants/*;

RUN yum install -y epel-release curl yum-utils gcc python-pip python-devel openssl-devel openssh-server sudo python-pip git
RUN yum install -y ansible libffi-devel

RUN groupadd -r sudo && mkdir -m 0755 -p /etc/sudoers.d && echo '%sudo ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-sudo && chmod 0440 /etc/sudoers.d/99-sudo
RUN sed -i -E -e 's/Defaults\s+requiretty/Defaults\t!requiretty/g' /etc/sudoers
RUN sed -i 's/^#GSSAPIAuthentication.*$/GSSAPIAuthentication no/g' /etc/ssh/sshd_config
RUN useradd -m -s /bin/bash -G sudo,users vagrant && \
    mkdir -m 0700 -p /home/vagrant/.ssh && \
    curl -fsSL https://raw.githubusercontent.com/hashicorp/vagrant/master/keys/vagrant.pub -o /home/vagrant/.ssh/authorized_keys && \
    chmod 0600 /home/vagrant/.ssh/authorized_keys && \
    chown -R vagrant:vagrant /home/vagrant

RUN echo "localhost     ansible_connection=local" > /etc/ansible/hosts

RUN systemctl enable sshd

ENV  ANSIBLE_RETRY_FILES_ENABLED=False ANSIBLE_HOST_KEY_CHECKING=False ANSIBLE_GATHERING=explicit

EXPOSE 22 80 443

CMD ["/usr/sbin/init"]

