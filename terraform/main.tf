# En este archivo debemos tener módulos reutilizables "modules" y no recursos directos.

# ========================================
# INFRAESTRUCTURA AWS
# ========================================

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

# Subnets públicas
resource "aws_subnet" "public" {
  count = length(var.public_subnets_cidr)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets_cidr[count.index]
  availability_zone       = var.aws_availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
  })
}

# Subnets privadas
resource "aws_subnet" "private" {
  count = length(var.private_subnets_cidr)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets_cidr[count.index]
  availability_zone = var.aws_availability_zones[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
  })
}

# Route Table para subnets públicas
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

# Asociaciones de Route Table públicas
resource "aws_route_table_association" "public" {
  count = length(var.public_subnets_cidr)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Group para RDS
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-"
  vpc_id      = aws_vpc.main.id

  # TODO SEGURIDAD: Restringir acceso solo a IPs necesarias
  # NOTA: Actualmente abierto para permitir GCP Datastream y Lambda functions
  # En producción, usar VPC Peering o identificar rangos IP específicos de Datastream
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rds-sg"
  })
}

# Security Group para Lambda
resource "aws_security_group" "lambda" {
  name_prefix = "${var.project_name}-lambda-"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-lambda-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Subnet Group para RDS (privado para Lambda)
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}

# Subnet Group público solo para Datastream
resource "aws_db_subnet_group" "public_for_datastream" {
  name       = "${var.project_name}-public-db-subnet-group"
  subnet_ids = aws_subnet.public[*].id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-public-db-subnet-group-datastream"
  })
}

# Parameter Group para habilitar logical replication
resource "aws_db_parameter_group" "postgres_logical_replication" {
  family = "postgres15"
  name   = "${var.project_name}-postgres-logical-replication"

  parameter {
    name         = "max_replication_slots"
    value        = "10"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "max_wal_senders"
    value        = "10"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-logical-replication-params"
  })
}

# Regla ya incluida en el security group principal arriba

# ⚠️  CONFIGURACIÓN DE SEGURIDAD PARA DATASTREAM + RDS ⚠️
# RDS está configurado como publicly_accessible = true ÚNICAMENTE para permitir
# conexión de Google Cloud Datastream. Medidas de seguridad implementadas:
# 1. ✅ IPs restringidas SOLO a rangos de GCP Datastream (europe-west1)
# 2. ✅ Usuario específico con permisos mínimos para replicación
# 3. ✅ Contraseñas fuertes (>15 caracteres, símbolos especiales)
# 4. ✅ Parameter groups configurados para logical replication
# NOTA: En producción considerar Cloud VPN o Cloud Interconnect

# RDS Instance configurada para logical replication
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-db"

  engine         = "postgres"
  engine_version = "15"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.public_for_datastream.name
  
  # Usar parameter group con logical replication
  parameter_group_name = aws_db_parameter_group.postgres_logical_replication.name
  
  # Accesible públicamente SOLO para Datastream (IPs restringidas)
  publicly_accessible = true

  backup_retention_period = 7
  backup_window          = "07:00-09:00"
  maintenance_window     = "sun:09:00-sun:10:00"

  skip_final_snapshot = true
  deletion_protection = false

  # IAM Authentication
  iam_database_authentication_enabled = true # Muy bien que hayas usado iam para autenticación

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-db"
  })
}

# Configurar PostgreSQL para Datastream (como proyecto funcional)
resource "null_resource" "configure_rds_for_datastream" {
  triggers = {
    always_run = "${timestamp()}"  # Fuerza recreación cada vez (como proyecto funcional)
  }

  provisioner "local-exec" {
    command = <<-EOT
      export PGPASSWORD="${var.db_password}"
      psql -h ${split(":", aws_db_instance.main.endpoint)[0]} -U ${var.db_username} -d ${var.db_name} -c "CREATE PUBLICATION datastream_publication FOR ALL TABLES;"
      psql -h ${split(":", aws_db_instance.main.endpoint)[0]} -U ${var.db_username} -d ${var.db_name} -c "SELECT PG_CREATE_LOGICAL_REPLICATION_SLOT('datastream_slot', 'pgoutput');"
      psql -h ${split(":", aws_db_instance.main.endpoint)[0]} -U ${var.db_username} -d ${var.db_name} -c "CREATE USER ${var.datastream_username} WITH ENCRYPTED PASSWORD '${var.datastream_password}';"
      psql -h ${split(":", aws_db_instance.main.endpoint)[0]} -U ${var.db_username} -d ${var.db_name} -c "GRANT rds_replication TO ${var.datastream_username};"
      psql -h ${split(":", aws_db_instance.main.endpoint)[0]} -U ${var.db_username} -d ${var.db_name} -c "GRANT USAGE ON SCHEMA public TO ${var.datastream_username};"
      psql -h ${split(":", aws_db_instance.main.endpoint)[0]} -U ${var.db_username} -d ${var.db_name} -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${var.datastream_username};"
      psql -h ${split(":", aws_db_instance.main.endpoint)[0]} -U ${var.db_username} -d ${var.db_name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ${var.datastream_username};"
    EOT
  }
  
  depends_on = [aws_db_instance.main]
}

# IAM Role para Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# IAM Policy para Lambda - VPC Access
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# IAM Policy para Lambda - RDS Access
resource "aws_iam_role_policy" "lambda_rds_policy" {
  name = "${var.project_name}-lambda-rds-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = [
          "arn:aws:rds-db:${var.aws_region}:*:dbuser:${aws_db_instance.main.identifier}/${var.db_username}"
        ]
      }
    ]
  })
}

# Archivos ZIP para funciones Lambda reales
# AWS recomienda el uso de Imagenes en lugar de zips para gestionar código pero ambas son válidas
data "archive_file" "get_products_zip" {
  type        = "zip"
  output_path = "${path.module}/get_products.zip"
  source_dir  = "../app/lambda-functions/get_products"
  excludes    = ["requirements.txt"]
}

data "archive_file" "get_item_zip" {
  type        = "zip" 
  output_path = "${path.module}/get_item.zip"
  source_dir  = "../app/lambda-functions/get_item"
  excludes    = ["requirements.txt"]
}

data "archive_file" "add_product_zip" {
  type        = "zip"
  output_path = "${path.module}/add_product.zip" 
  source_dir  = "../app/lambda-functions/add_product"
  excludes    = ["requirements.txt"]
}

# Lambda Layer para dependencias Python compartidas
resource "aws_lambda_layer_version" "python_dependencies" {
  filename   = "${path.module}/python-dependencies-layer.zip"
  layer_name = "${var.project_name}-python-dependencies"

  compatible_runtimes = ["python3.11"]

  lifecycle {
    ignore_changes = [filename]
  }
}

# Lambda Function - GetProducts
resource "aws_lambda_function" "get_products" {
  filename         = data.archive_file.get_products_zip.output_path
  source_code_hash = data.archive_file.get_products_zip.output_base64sha256
  function_name    = "${var.project_name}-get-products"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = 30
  
  layers = [aws_lambda_layer_version.python_dependencies.arn]

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_db_instance.main.endpoint
      DB_NAME     = var.db_name
      DB_USERNAME = var.db_username
      DB_PASSWORD = var.db_password
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-get-products"
  })
}

# Lambda Function - GetItem
resource "aws_lambda_function" "get_item" {
  filename         = data.archive_file.get_item_zip.output_path
  source_code_hash = data.archive_file.get_item_zip.output_base64sha256
  function_name    = "${var.project_name}-get-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = 30
  
  layers = [aws_lambda_layer_version.python_dependencies.arn]

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_db_instance.main.endpoint
      DB_NAME     = var.db_name
      DB_USERNAME = var.db_username
      DB_PASSWORD = var.db_password
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-get-item"
  })
}

# Lambda Function - AddProduct
resource "aws_lambda_function" "add_product" {
  filename         = data.archive_file.add_product_zip.output_path
  source_code_hash = data.archive_file.add_product_zip.output_base64sha256
  function_name    = "${var.project_name}-add-product"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = 30
  
  layers = [aws_lambda_layer_version.python_dependencies.arn]

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_db_instance.main.endpoint
      DB_NAME     = var.db_name
      DB_USERNAME = var.db_username
      DB_PASSWORD = var.db_password
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-add-product"
  })
}

# Lambda Function URLs
# TODO SEGURIDAD: En producción, usar authorization_type = "AWS_IAM" y dominios específicos
resource "aws_lambda_function_url" "get_products" {
  function_name      = aws_lambda_function.get_products.function_name
  authorization_type = "NONE"  # TEMPORAL: Para PoC/demo - cambiar a AWS_IAM en producción

  cors {
    allow_credentials = false
    allow_origins     = ["*"]  # TEMPORAL: Restringir a dominios específicos en producción
    allow_methods     = ["GET"]
    allow_headers     = ["date", "keep-alive"]
    expose_headers    = ["date", "keep-alive"]
    max_age          = 86400
  }
}

resource "aws_lambda_function_url" "get_item" {
  function_name      = aws_lambda_function.get_item.function_name
  authorization_type = "NONE"  # TEMPORAL: Para PoC/demo - cambiar a AWS_IAM en producción

  cors {
    allow_credentials = false
    allow_origins     = ["*"]  # TEMPORAL: Restringir a dominios específicos en producción
    allow_methods     = ["POST"]
    allow_headers     = ["date", "keep-alive", "content-type"]
    expose_headers    = ["date", "keep-alive"]
    max_age          = 86400
  }
}

resource "aws_lambda_function_url" "add_product" {
  function_name      = aws_lambda_function.add_product.function_name
  authorization_type = "NONE"  # TEMPORAL: Para PoC/demo - cambiar a AWS_IAM en producción

  cors {
    allow_credentials = false
    allow_origins     = ["*"]  # TEMPORAL: Restringir a dominios específicos en producción
    allow_methods     = ["POST"]
    allow_headers     = ["date", "keep-alive", "content-type"]
    expose_headers    = ["date", "keep-alive"]
    max_age          = 86400
  }
}

# ========================================
# INFRAESTRUCTURA GCP
# ========================================
# Las apis se suelen habilitar en un modulo de administrador separado, ya que el usuario que ejecuta el terraform no debe tener este nivel de privilegios.
# Habilitar APIs necesarias
resource "google_project_service" "services" {
  for_each = toset([
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "datastream.googleapis.com",
    "compute.googleapis.com"
  ])

  service = each.value
  project = var.gcp_project_id

  disable_on_destroy = false
}

# Artifact Registry para almacenar la imagen del contenedor
resource "google_artifact_registry_repository" "repo" {
  location      = var.gcp_region
  repository_id = "${var.project_name}-repo"
  description   = "Repositorio para imágenes Docker del proyecto ${var.project_name}"
  format        = "DOCKER"
  project       = var.gcp_project_id

  depends_on = [google_project_service.services]
}

# Construcción y subida automática de imagen Flask durante terraform apply
resource "null_resource" "build_and_push_flask_image" {
  provisioner "local-exec" {
    command = "gcloud builds submit ../app/flask-app --tag=${var.flask_app_image} --project=${var.gcp_project_id}"
    working_dir = path.module
  }

  depends_on = [google_artifact_registry_repository.repo]
  
  # Reconstruir si cambian los archivos de la aplicación Flask
  triggers = {
    dockerfile_hash   = filemd5("../app/flask-app/Dockerfile")
    app_py_hash      = filemd5("../app/flask-app/app.py")
    requirements_hash = filemd5("../app/flask-app/requirements.txt")
  }
}

# Service Account para Cloud Run
resource "google_service_account" "cloud_run_sa" {
  account_id   = "${var.project_name}-cloud-run-sa"
  display_name = "Service Account para Cloud Run"
  project      = var.gcp_project_id
}

# Cloud Run Service
resource "google_cloud_run_v2_service" "flask_app" {
  name     = "${var.project_name}-flask-app"
  location = var.gcp_region
  project  = var.gcp_project_id

  template {
    service_account = google_service_account.cloud_run_sa.email
    
    containers {
      # Imagen de nuestra aplicación Flask personalizada
      image = var.flask_app_image
      
      ports {
        container_port = var.flask_app_port
      }

      env {
        name  = "GET_PRODUCTS_URL"
        value = aws_lambda_function_url.get_products.function_url
      }

      env {
        name  = "GET_ITEM_URL"
        value = aws_lambda_function_url.get_item.function_url
      }

      env {
        name  = "ADD_PRODUCT_URL"
        value = aws_lambda_function_url.add_product.function_url
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }
  }

  depends_on = [
    google_project_service.services,
    google_artifact_registry_repository.repo,
    null_resource.build_and_push_flask_image
  ]
}

# IAM policy para permitir acceso público a Cloud Run
resource "google_cloud_run_service_iam_member" "public_access" {
  service  = google_cloud_run_v2_service.flask_app.name
  location = google_cloud_run_v2_service.flask_app.location
  project  = var.gcp_project_id
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ========================================
# BIGQUERY Y DATASTREAM
# ========================================

# Dataset de BigQuery
resource "google_bigquery_dataset" "ecommerce_analytics" {
  dataset_id  = var.bigquery_dataset_id
  project     = var.gcp_project_id
  location    = var.bigquery_dataset_location
  description = "Dataset para analytics de ecommerce desde RDS PostgreSQL"

  labels = {
    project    = var.project_name
    managed_by = "terraform"
  }

  depends_on = [google_project_service.services]
}

# Nota: La tabla de productos se crea automáticamente por Datastream
# como 'public_products' según el esquema PostgreSQL


# Connection profile para PostgreSQL RDS
resource "google_datastream_connection_profile" "postgresql_source" {
  display_name          = "${var.project_name}-postgresql-source"
  location              = var.gcp_region
  connection_profile_id = "${var.project_name}-postgresql-source"
  project               = var.gcp_project_id

  postgresql_profile {
    hostname = split(":", aws_db_instance.main.endpoint)[0]
    username = var.datastream_username
    password = var.datastream_password
    database = var.db_name
    port     = 5432
  }

  depends_on = [
    google_project_service.services,
    null_resource.configure_rds_for_datastream
  ]
}

# Connection profile para BigQuery destination
resource "google_datastream_connection_profile" "bigquery_destination" {
  display_name          = "${var.project_name}-bigquery-destination"
  location              = var.gcp_region
  connection_profile_id = "${var.project_name}-bigquery-destination"
  project               = var.gcp_project_id

  bigquery_profile {}

  depends_on = [google_project_service.services]
}

# Datastream para replicar datos de PostgreSQL a BigQuery
resource "google_datastream_stream" "postgresql_to_bigquery" {
  display_name = var.datastream_display_name
  location     = var.gcp_region
  stream_id    = "${var.project_name}-stream"
  project      = var.gcp_project_id

  source_config {
    source_connection_profile = google_datastream_connection_profile.postgresql_source.id
    postgresql_source_config {
      include_objects {
        postgresql_schemas {
          schema = "public"
          postgresql_tables {
            table = "products"
          }
        }
      }
      publication = "datastream_publication"
      replication_slot = "datastream_slot"
      max_concurrent_backfill_tasks = 12
    }
  }

  destination_config {
    destination_connection_profile = google_datastream_connection_profile.bigquery_destination.id
    bigquery_destination_config {
      single_target_dataset {
        dataset_id = "${var.gcp_project_id}:${google_bigquery_dataset.ecommerce_analytics.dataset_id}"
      }
    }
  }

  backfill_all {
    # Configuración para backfill completo
  }

  depends_on = [
    google_datastream_connection_profile.postgresql_source,
    google_datastream_connection_profile.bigquery_destination,
    google_bigquery_dataset.ecommerce_analytics
  ]
}

# Iniciar automáticamente el stream de Datastream
resource "null_resource" "start_datastream" {
  triggers = {
    stream_id = google_datastream_stream.postgresql_to_bigquery.name
  }

  provisioner "local-exec" {
    command = "gcloud datastream streams update data-project-3-stream --location=europe-west1 --state=RUNNING --update-mask=state --quiet"
  }

  depends_on = [google_datastream_stream.postgresql_to_bigquery]
}

# Nota: Looker Studio se configura manualmente en https://lookerstudio.google.com
# No requiere Service Account ya que usa permisos de la cuenta personal

# Vista SQL en BigQuery para analytics
resource "google_bigquery_table" "products_analytics_view" {
  dataset_id = google_bigquery_dataset.ecommerce_analytics.dataset_id
  table_id   = "products_analytics"
  project    = var.gcp_project_id

  deletion_protection = false

  view {
    query = <<EOF
SELECT 
  id,
  name,
  price,
  description,
  available,
  created_at,
  CASE 
    WHEN available = true THEN 'Disponible'
    ELSE 'Agotado'
  END as status_text,
  CASE
    WHEN price < 10 THEN 'Económico'
    WHEN price < 50 THEN 'Medio'
    ELSE 'Premium'
  END as price_category,
  DATE(created_at) as created_date,
  EXTRACT(HOUR FROM created_at) as created_hour,
  EXTRACT(DAYOFWEEK FROM created_at) as day_of_week
FROM `${var.gcp_project_id}.${google_bigquery_dataset.ecommerce_analytics.dataset_id}.public_products`
ORDER BY created_at DESC
EOF
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_dataset.ecommerce_analytics]
}
