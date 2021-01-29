// Configure the Google Cloud provider
provider "google" {
  credentials = "${file("${var.gce_credentials}")}"
  project     = "${var.gce_project}"
  region      = "${var.gce_region}"
}

resource "google_compute_instance" "default" {
  name         = "test"
  machine_type = "n1-standard-1"
  zone         = "${var.gce_zone}"

  tags = ["foo", "bar"]

  disk {
    image = "debian-cloud/debian-8"
  }

  // Local SSD disk
  disk {
    type    = "local-ssd"
    scratch = true
  }

  network_interface {
    network = "default"

    access_config {
      // Ephemeral IP
    }
  }

  metadata {
    foo = "bar"
  }

  metadata_startup_script = "echo hi > /test.txt"

  service_account {
    scopes = ["userinfo-email", "compute-ro", "storage-ro"]
  }
}
