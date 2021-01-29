job "vsphere-graphite" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"

  group "vsphere-graphite" {
    count = 1

    restart {
      attempts = 5
      interval = "2m"
      delay    = "15s"
      mode     = "fail"
    }

    #    constraint {
    #      distinct_hosts = true
    #    }

    constraint {
      attribute    = "${meta.cluster}"
      set_contains = "newton"
    }
    task "vsphere-graphite" {
      driver = "docker"

      config {
        image = "registry.int.xcalar.com/cblomart/vsphere-graphite:latest"

        volumes = [
          "secrets/vsphere-graphite.json:/etc/vsphere-graphite.json",
        ]
      }

      vault {
        policies = ["jenkins_slave"]
      }

      template {
        data = <<EOT
{{ with secret "secret/data/infra/vsphere-graphite" }}{{ .Data.data.data }}{{ end }}
EOT

        destination = "secrets/vsphere-graphite.json"
      }

      resources {
        memory = 32
        cpu    = 4500
      }
    }
  }
}
