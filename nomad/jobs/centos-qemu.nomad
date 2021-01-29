job "centos-qemu" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"

  #  constraint {
  #    attribute    = "${meta.virtual}"
  #    set_contains = "physical"
  #  }

  group "vm" {
    count = 1

    constraint {
      distinct_hosts = true
    }

    task "centos7" {
      driver = "qemu"

      resources {
        cpu    = 2000 # MHz
        memory = 2000 # MB

        network {
          port "ssh_port" {}
        }
      }

      template {
        destination = "local/host.env"
        change_mode = "noop"
        env         = true

        data = <<EOT
NOW={{ timestamp "unix" }}
VMNAME={{ env "NOMAD_JOB_NAME" }}-{{ env "NOMAD_ALLOC_ID" }}
INSTANCE_ID=i-{{ env "NOMAD_ALLOC_ID" }}
EOT
      }

      template {
        destination = "/netstore/images/ci/meta-data"
        change_mode = "noop"

        data = <<EOD
instance-id: i-{{ env "NOMAD_ALLOC_ID" }}
hostname: {{ env "NOMAD_JOB_NAME" }}-{{ env "NOMAD_ALLOC_ID" }}.int.xcalar.com
EOD
      }

      template {
        destination = "local/meta-data"
        change_mode = "noop"

        data = <<EOD
instance-id: i-{{ env "NOMAD_ALLOC_ID" }}
hostname: {{ env "NOMAD_JOB_NAME" }}-{{ env "NOMAD_ALLOC_ID" }}.int.xcalar.com
EOD
      }

      template {
        destination = "local/user-data"
        change_mode = "noop"

        data = <<EOD
#cloud-config
disable_ec2_metadata: true
groups:
  - docker
  - sudo

users:
  - default
  - name: jenkins
    uid: 1000
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
    - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCb60/5l2c6gIHEYFB0c6dW7hHzsID3zaS3MoohI0FeyxTCkAZt38hZ+fxhxQ6FJPuJUB1TX/0KG5vnWj7L2fcOcy6yB/PqahFJEMT1LZ2LwPlKuSJ4T3lZ8d9u6bCbmAj76hyEUfQYBGdQJwnHoHR6QuGcT61BQAmu3rBsiodoGF3cP/OjMBN1VEXQ/SkLutxVEIhCr2El6Ng2AmgmZe0LMxneTdxFuVeTvpjutvrDx8Bffsvd559/zA53J3i8JkFT5HEkNlkehDlpKnvK2fGFdma
    - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDAFyv/OSGVoQ3Z7aea1HzhArTAtQJcz54dYYjoVErrzrkmFGOqAhHc/i9pPFaWERJWZzNnx4xAbLDzRF/JhZ7KgV/5pjJb3GB2k1FSCtta3XHoOCQZBIBmT1BBEo3FY/zJcg/trtVJYNSJabkTjCVI3mKn92gEpju3243z7o/3UuYWQ0QvOCN0M/4LDL5wFXKsMvN/7Sk3C6ImUBwkb4Dj7IgDJ0cEMVQVx9BGo/p4lM4ply9k/A/aQJZYUc9bGXGbxyhWVdmCPWv1CkpCqO/yMIr

ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCb60/5l2c6gIHEYFB0c6dW7hHzsID3zaS3MoohI0FeyxTCkAZt38hZ+fxhxQ6FJPuJUB1TX/0KG5vnWj7L2fcOcy6yB/PqahFJEMT1LZ2LwPlKuSJ4T3lZ8d9u6bCbmAj76hyEUfQYBGdQJwnHoHR6QuGcT61BQAmu3rBsiodoGF3cP/OjMBN1VEXQ/SkLutxVEIhCr2El6Ng2AmgmZe0LMxneTdxFuVeTvpjutvrDx8Bffsvd559/zA53J3i8JkFT5HEkNlkehDlpKnvK2fGFdma
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDAFyv/OSGVoQ3Z7aea1HzhArTAtQJcz54dYYjoVErrzrkmFGOqAhHc/i9pPFaWERJWZzNnx4xAbLDzRF/JhZ7KgV/5pjJb3GB2k1FSCtta3XHoOCQZBIBmT1BBEo3FY/zJcg/trtVJYNSJabkTjCVI3mKn92gEpju3243z7o/3UuYWQ0QvOCN0M/4LDL5wFXKsMvN/7Sk3C6ImUBwkb4Dj7IgDJ0cEMVQVx9BGo/p4lM4ply9k/A/aQJZYUc9bGXGbxyhWVdmCPWv1CkpCqO/yMIr

manage_resolv_conf: true
resolv_conf:
  nameservers: ['10.10.2.136', '10.10.1.1']
  searchdomains:
    - int.xcalar.com
  domain: int.xcalar.com

yum_repos:
    puppet6:
        baseurl: http://yum.puppetlabs.com/puppet6/el/7/$basearch
        name: Puppet 6 Repository el7
        enabled: true
        gpgcheck: true
        gpgkey: https://yum.puppetlabs.com/RPM-GPG-KEY-puppet

write_files:
  - path: /etc/facter/facts.d/role.txt
    permissions: '0644'
    owner: root:root
    content: |
        role=jenkins_slave
  - path: /etc/facter/facts.d/cluster.txt
    permissions: '0644'
    owner: root:root
    content: |
        cluster=jenkins-swarm

packages:
  - epel-release
  - puppet-agent
  - curl
  - wget

runcmd:
  - [ systemctl, daemon-reload ]
  - [ systemctl, enable, puppet.service ]
  - [ /opt/puppetlabs/bin/puppet, agent, -t, -v ]
  - [ /opt/puppetlabs/bin/puppet, agent, -t, -v ]
  - [ systemctl, start, --no-block, puppet.service ]

EOD
      }

      config {
        image_path        = "local/CentOS-7-x86_64-GenericCloud-1905.qcow2"
        accelerator       = "kvm"
        graceful_shutdown = true

        args = [
          "-m",
          "${NOMAD_MEMORY_LIMIT}M",
          "-smp",
          "4",
          "-smbios",
          "type=1,serial=ds=nocloud-net;h=${VMNAME}.int.xcalar.com;i=${INSTANCE_ID};s=http://netstore.int.xcalar.com/images/ci/",
        ]

        #"type=1,serial=ds=nocloud;h=${VMNAME}.int.xcalar.com;i=${INSTANCE_ID};s=file://./local/",

        port_map {
          ssh_port = 22
        }
      }

      service {
        name = "ssh"
        port = "ssh_port"
        tags = ["ssh"]

        check {
          name     = "ssh_port is up"
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }

      artifact {
        source = "http://netstore.int.xcalar.com/images/CentOS-7-x86_64-GenericCloud-1905.qcow2.tar.gz"

        options {
          checksum = "md5:ae8aab156b12f8689088e9b56772a560"
        }
      }
    }
  }
}
