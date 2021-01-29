job "jenkins-qemu-ci" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"

  #  constraint {
  #    attribute    = "${meta.virtual}"
  #    set_contains = "physical"
  #  }

  group "jenkins-qemu-ci" {
    count = 1

    constraint {
      attribute = "${node.class}"
      operator  = "set_contains"
      value     = "bigrig"
    }

    #constraint {
    #  distinct_hosts = true
    #}

    task "jenkins-slave" {
      driver = "qemu"

      resources {
        cpu    = 16000 # MHz
        memory = 32000 # MB

        network {
          port "ssh"{}
          port "https"{}
          port "node_exporter"{}
        }
      }

      template {
        data = <<EOT
NOW={{ timestamp "unix" }}
VMNAME={{ env "NOMAD_JOB_NAME" }}-{{ env "NOMAD_ALLOC_INDEX" }}
INSTANCE_ID=i-{{ env "NOMAD_ALLOC_INDEX" }}-{{ env "NOMAD_ALLOC_ID" | split "-" | index 0}}
EOT

        change_mode = "noop"
        destination = "local/host.env"
        env         = true
      }

      config {
        image_path        = "local/el7-jenkins_swarm-qemu-4.qcow2"
        accelerator       = "kvm"
        graceful_shutdown = true

        args = [
          "-m",
          "${NOMAD_MEMORY_LIMIT}M",
          "-smp",
          "4",
          "-smbios",
          "type=1,serial=ds=nocloud;h=${VMNAME}.int.xcalar.com;i=${INSTANCE_ID}",
        ]

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
        source = "http://10.10.2.136/images/el7-jenkins_swarm-qemu-4.qcow2"
      }
    }
  }
}
