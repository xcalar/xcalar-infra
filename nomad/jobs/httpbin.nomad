job "httpbin" {
  # Run only in our datacenter. Nomad has cross-dc as 1st class concept
  datacenters = ["xcalar-sjc"]

  # Most jobs will be of type service. Meaning it'll run and stay, like
  # a systemd service
  type = "service"

  # Just to show you can place constraints at different levels
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  # This controls how the job is updated. When a new job defn comes in
  # Update 1 deployment at a time (below we specify count = 3), so the
  # service won't have an outage. It'll still be services by the other
  # 2 nodes. Once the replacement node is healthy, move on to the replacing
  # the next node
  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    healthy_deadline = "1m"
    auto_revert      = false
    canary           = 0
  }

  # All tasks in a group get scheduled on the same node. The naming doesn't
  # matter
  group "cluster" {
    # Run 3 copies
    count = 3

    # Each copy should be on its own host
    constraint {
      operator = "distinct_hosts"
      value    = "true"
    }

    # If the container fails, try restarting it a few times before
    # giving up and trying a different node.
    restart {
      attempts = 10
      interval = "5m"
      delay    = "30s"
    }

    task "httpbin" {
      # This task should use the docker driver. There are other drivers, like
      # 'raw' for just an elf (some isolation), 'raw' without isolation, 'qemu'
      # for VMs, etc.
      driver = "docker"

      # The docker configuration
      config {
        # the actual docker image. You can use local urls like registry.int.xcalar.com/...
        image      = "kennethreitz/httpbin"
        force_pull = false

        # This tells nomad that the container will bind to port 80 on its private ip
        # address. We give it a name "web"
        port_map {
          web = 80
        }
      }

      resources {
        # Give it 200Mhz of CPU and 100M of memory
        cpu    = 200
        memory = 100

        # Allocate a dynamic port on the host and map that to the "web" port inside
        # the container as specified above.
        network {
          port "web" {}
        }
      }

      # The service shall be named 'httpbin', meaning you can find it in consul with
      # that name: httpbin.service.consul. If you do a 'dig A httpbin.service.consul +short'
      # you'll get back 3 host IP addresses, because we specified count = 3 and a constraint
      # of not running on the same host
      service {
        name = "httpbin"

        # Another service running on nomad scans these tags so it knows how to redirect traffic
        # to your containers and what ports to map. Additional magic, we marked 443 as SSL and
        # configured nomad to pass a vault token to fabio, so it can dynamicallyt provision
        # very short life-time SSL certs
        tags = [
          "urlprefix-httpbin.service.consul:443/",
          "urlprefix-httpbin.service.consul:80/",
        ]

        # The service will run on the "web" port. This is ephemeral, and it is rare you
        # would ever need to know its value. High 30000's usually
        port = "web"

        # Every service registered with consul needs to have a health check. This way
        # consul only directs traffic to healthy instances and gives nomad a shot at
        # rescheduling the failed job.
        check {
          name     = "web port alive"
          type     = "http"
          path     = "/"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
