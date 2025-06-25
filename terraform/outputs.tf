# ========================================
# OUTPUTS GCP
# ========================================

# URL de Cloud Run
output "cloud_run_url" {
  description = "URL de la aplicación Flask en Cloud Run"
  value       = google_cloud_run_v2_service.flask_app.uri
}

output "gcp_project_id" {
  description = "ID del proyecto de GCP"
  value       = var.gcp_project_id
}

# Información del repositorio
output "artifact_registry_repo" {
  description = "Información del repositorio de Artifact Registry"
  value = {
    name = google_artifact_registry_repository.repo.name
    url  = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.repo.repository_id}"
  }
}

# Service Account
output "service_account_email" {
  description = "Email del service account de Cloud Run"
  value       = google_service_account.cloud_run_sa.email
}

# ========================================
# OUTPUTS AWS
# ========================================

# VPC Outputs
output "vpc_id" {
  description = "ID de la VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs de las subnets públicas"
  value       = aws_subnet.public[*].id
}

# RDS Outputs
output "rds_endpoint" {
  description = "Endpoint de la instancia RDS"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "rds_port" {
  description = "Puerto de la instancia RDS"
  value       = aws_db_instance.main.port
}

# Security Group Outputs
output "security_group_id" {
  description = "ID del security group de RDS"
  value       = aws_security_group.rds.id
}

# Lambda Outputs
output "lambda_urls" {
  description = "URLs de las funciones Lambda"
  value = {
    get_products = aws_lambda_function_url.get_products.function_url
    get_item     = aws_lambda_function_url.get_item.function_url
    add_product  = aws_lambda_function_url.add_product.function_url
  }
}

output "lambda_function_names" {
  description = "Nombres de las funciones Lambda"
  value = {
    get_products = aws_lambda_function.get_products.function_name
    get_item     = aws_lambda_function.get_item.function_name
    add_product  = aws_lambda_function.add_product.function_name
  }
}

# ========================================
# OUTPUTS COMBINADOS
# ========================================

# Outputs de conexión entre servicios
output "database_connection_info" {
  description = "Información de conexión a la base de datos"
  value = {
    endpoint = aws_db_instance.main.endpoint
    port     = aws_db_instance.main.port
    database = var.db_name
    username = var.db_username
  }
  sensitive = true
}

output "service_endpoints" {
  description = "Endpoints de todos los servicios"
  value = {
    flask_app    = google_cloud_run_v2_service.flask_app.uri
    get_products = aws_lambda_function_url.get_products.function_url
    get_item     = aws_lambda_function_url.get_item.function_url
    add_product  = aws_lambda_function_url.add_product.function_url
  }
}

# ========================================
# OUTPUTS BIGQUERY Y DATASTREAM
# ========================================

# BigQuery Dataset
output "bigquery_dataset_id" {
  description = "ID del dataset de BigQuery"
  value       = google_bigquery_dataset.ecommerce_analytics.dataset_id
}

output "bigquery_dataset_url" {
  description = "URL del dataset de BigQuery en la consola"
  value       = "https://console.cloud.google.com/bigquery?project=${var.gcp_project_id}&ws=!1m4!1m3!3m2!1s${var.gcp_project_id}!2s${google_bigquery_dataset.ecommerce_analytics.dataset_id}"
}

# Datastream
output "datastream_id" {
  description = "ID del stream de Datastream"
  value       = google_datastream_stream.postgresql_to_bigquery.id
}

output "datastream_url" {
  description = "URL del stream de Datastream en la consola"
  value       = "https://console.cloud.google.com/datastream/streams/locations/${var.gcp_region}/instances/${google_datastream_stream.postgresql_to_bigquery.stream_id}?project=${var.gcp_project_id}"
}

# Analytics endpoints
output "analytics_info" {
  description = "Información de los servicios de analytics"
  value = {
    bigquery_dataset_id = google_bigquery_dataset.ecommerce_analytics.dataset_id
    bigquery_project    = var.gcp_project_id
    datastream_id       = google_datastream_stream.postgresql_to_bigquery.stream_id
    looker_dashboard    = "https://lookerstudio.google.com (configurado manualmente)"
  }
}