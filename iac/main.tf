# Generate a random suffix for the project ID
resource "random_id" "project_suffix" {
  byte_length = 2  # 2 bytes = 4 hex characters (e.g., "abcd")
}

# Create the Google Cloud project with a generated project ID
resource "google_project" "gcp_prod_project" {
  name            = "travian-prod-${random_id.project_suffix.hex}"
  project_id      = "travian-${random_id.project_suffix.hex}"
  billing_account = var.billing_account_id   
}

# Create a Google Storage Bucket within the newly created project
resource "google_storage_bucket" "static_site" {
  name          = var.bucket_name
  location      = "EU"
  force_destroy = true
  uniform_bucket_level_access = true
  project       = google_project.gcp_prod_project.project_id

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }

  cors {
    origin          = ["http://image-store.com"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
}

# Create a Service Account within the newly created project
resource "google_service_account" "gcs_deploy_sa" {
  account_id   = var.service_account_id
  display_name = "GCS Deploy Service Account"
  project      = google_project.gcp_prod_project.project_id
}

# Assign Storage Admin Role to the Service Account
resource "google_project_iam_member" "gcs_deploy_sa_storage_admin" {
  project = google_project.gcp_prod_project.project_id
  member  = "serviceAccount:${google_service_account.gcs_deploy_sa.email}"
  role    = "roles/storage.admin"
}

# Assign Object Viewer Role to Service Account (for public access)
resource "google_project_iam_member" "gcs_deploy_sa_object_viewer" {
  project = google_project.gcp_prod_project.project_id
  member  = "serviceAccount:${google_service_account.gcs_deploy_sa.email}"
  role    = "roles/storage.objectViewer"
}

# Assign Object Creator Role to Service Account for GCS
resource "google_storage_bucket_iam_member" "gcs_deploy_sa_object_creator" {
  bucket = google_storage_bucket.static_site.name
  member = "serviceAccount:${google_service_account.gcs_deploy_sa.email}"
  role   = "roles/storage.objectCreator"
}

# Make the GCS Bucket Public (allow all users to view objects)
resource "google_storage_bucket_iam_member" "gcs_public_access" {
  bucket = google_storage_bucket.static_site.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Create a Service Account Key for GitHub Actions Authentication
resource "google_service_account_key" "gcs_deploy_key" {
  service_account_id = google_service_account.gcs_deploy_sa.id
  private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
}

# Output the Service Account Key for GitHub Actions
output "gcs_deploy_sa_key" {
  value       = google_service_account_key.gcs_deploy_key.private_key
  sensitive   = true
  description = "Service account key for deploying to GCS."
}

# Grant Cloud Build permissions to the Compute Engine default service account
resource "google_project_iam_member" "cloud_build_compute_role" {
  project = google_project.gcp_prod_project.project_id
  member  = "serviceAccount:${google_project.gcp_prod_project.number}-compute@developer.gserviceaccount.com"
  role    = "roles/cloudbuild.builds.builder"
}

# Create Artifact Registry repository for Docker images
resource "google_artifact_registry_repository" "docker_repo" {
  project     = google_project.gcp_prod_project.project_id
  location    = var.region
  repository_id = "python-backend-repo"
  description = "Docker repository for Cloud Run"
  format      = "DOCKER"
}


# Assign Artifact Registry permissions to Cloud Build
resource "google_project_iam_member" "cloud_build_artifact_registry_pusher" {
  project = google_project.gcp_prod_project.project_id
  member  = "serviceAccount:${google_project.gcp_prod_project.number}@cloudbuild.gserviceaccount.com"
  role    = "roles/artifactregistry.writer"
}

# Define Cloud Run service
resource "google_cloud_run_service" "python_backend" {
  name     = "python-backend"
  project  = google_project.gcp_prod_project.project_id
  location = var.region

  template {
    spec {
      containers {
        image = "gcr.io/cloudrun/hello"  # Public Cloud Run Hello World image
        resources {
          limits = {
            memory = "512Mi"
            cpu    = "1"
          }
        }
      }
    }
  }

  autogenerate_revision_name = true

  # Optional: Allow unauthenticated access
  traffic {
    percent         = 100
    latest_revision = true
  }
}

# Allow public access to Cloud Run service
resource "google_cloud_run_service_iam_member" "invoker" {
  project        = google_project.gcp_prod_project.project_id
  location       = var.region
  service        = google_cloud_run_service.python_backend.name
  role           = "roles/run.invoker"
  member         = "allUsers"
}

# Output Cloud Run URL
output "cloud_run_url" {
  value       = google_cloud_run_service.python_backend.status[0].url
  description = "URL of the deployed Python backend on Cloud Run."
}