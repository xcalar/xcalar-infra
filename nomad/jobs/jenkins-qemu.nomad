job "jenkins-el7" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"

  ##  constraint {
  ##    attribute    = "${meta.cluster}"
  ##    set_contains = "newton"
  ##  }

  group "swarm" {
    count = 1

    constraint {
      distinct_hosts = true
    }

    task "worker" {
      driver = "qemu"

      resources {
        cpu    = 16000 # MHz
        memory = 24000 # MB

        network {
          port "ssh"{}
          port "https"{}
          port "node_exporter"{}
        }
      }

      template {
        data = <<EOT
              NOW={{ timestamp "unix" }}
          EOT

        change_mode = "noop"
        env         = true
        destination = "local/tempenv"
      }

      #      template {
      #        data = <<EOT
      #VMNAME={{ env "NOMAD_JOB_NAME" }}-{{ env "NOMAD_ALLOC_INDEX" }}-{{ timestamp "unix" }}
      #NPROC={{ env "NOMAD_CPU_LIMIT" | div 2000 }}
      #INSTANCE_ID=i-{{ env "NOMAD_ALLOC_INDEX" }}-{{ env "NOMAD_ALLOC_ID" }}
      #EOT
      #
      #        destination = "local/host.env"
      #        env         = true
      #      }

      config {
        image_path        = "local/tdhtest"
        accelerator       = "kvm"
        graceful_shutdown = false

        #        -device virtio-net,netdev=user.0
        args = [
          "-m",
          "${NOMAD_MEMORY_LIMIT}M",
          "-smp",
          "8",
          "-smbios",
          "type=1,serial=ds=nocloud;h=${NOMAD_JOB_NAME}-${NOW}.int.xcalar.com;i-${NOMAD_ALLOC_INDEX}-${NOMAD_ALLOC_ID}",
        ]

        #  "-device",
        #  "virtio-net,netdev=user.0",
        #  "-netdev",
        #  "user,id=user.0,hostfwd=tcp::${NOMAD_PORT_ssh}-:22",
        #] #,hostfwd=tcp::${NOMAD_PORT_https}-:443"]

        port_map {
          ssh           = 22
          https         = 443
          node_exporter = 9100
        }
      }
      service {
        name = "node-exporter"
        port = "node_exporter"
        tags = ["prometheus"]

        check {
          name     = "HTTP metrics on port 9100"
          type     = "http"
          port     = "node_exporter"
          path     = "/metrics"
          interval = "10s"
          timeout  = "2s"
        }
      }
      artifact {
        source = "http://netstore/images/el7-jenkins_slave-qemu-3.tar.gz"
      }
    }
  }
}
