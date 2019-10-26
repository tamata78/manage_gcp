# gcp base info
provider "google" {
  credentials = "${file(var.credential.data)}"
  project     = "${lookup(var.project_name, "${terraform.workspace}")}"
  region      = "asia-northeast1"
}

# Generates an archive from content, a file, or directory of files
data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/files/functions.zip"
}

# gcs
resource "google_storage_bucket" "slack_functions_bucket" {
  name          = "${lookup(var.project_name, "${terraform.workspace}")}-scheduler-bucket"
  project       = "${lookup(var.project_name, "${terraform.workspace}")}"
  location      = "asia"
  force_destroy = true
}

# gcs obj
resource "google_storage_bucket_object" "functions_zip" {
  name   = "functions.zip"
  bucket = "${google_storage_bucket.slack_functions_bucket.name}"
  source = "${path.module}/files/functions.zip"
}

# publisher massages topic
resource "google_pubsub_topic" "slack_notify" {
  name    = "slack-notify"
  project = "${lookup(var.project_name, "${terraform.workspace}")}"
}

# clound function
resource "google_cloudfunctions_function" "slack_notification" {
  name        = "SlackNotification"
  project     = "${lookup(var.project_name, "${terraform.workspace}")}"
  region      = "asia-northeast1"
  runtime     = "go111"
  entry_point = "SlackNotification"

  # exec func bucket and path
  source_archive_bucket = "${google_storage_bucket.slack_functions_bucket.name}"
  source_archive_object = "${google_storage_bucket_object.functions_zip.name}"

  environment_variables = {
    SLACK_WEBHOOK_URL = "${var.webhook.url}"
  }

  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = "${google_pubsub_topic.slack_notify.name}"
  }
}

resource "google_cloud_scheduler_job" "slack-notify-scheduler" {
  name        = "slack-notify-daily"
  project     = "${lookup(var.project_name, "${terraform.workspace}")}"
  schedule    = "0 8 * * *"
  description = "suggesting your morning/lunch/dinner"
  time_zone   = "Asia/Tokyo"

  pubsub_target {
    topic_name = "${google_pubsub_topic.slack_notify.id}"
    data       = "${base64encode("{\"mention\":\"channel\",\"channel\":\"random\"}")}"
  }
}

