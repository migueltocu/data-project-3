# Variables generales del proyecto
variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "data-project-3"
}


# Variables de GCP
variable "gcp_project_id" {
  description = "ID del proyecto de GCP"
  type        = string
}

variable "gcp_region" {
  description = "Región de GCP"
  type        = string
  default     = "europe-west1"
}

variable "gcp_zone" {
  description = "Zona de GCP"
  type        = string
  default     = "europe-west1-b"
}

# Variables de AWS
variable "aws_region" {
  description = "Región de AWS"
  type        = string
  default     = "eu-central-1"
}

variable "aws_availability_zones" {
  description = "Zonas de disponibilidad de AWS"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

# Variables de base de datos
variable "db_name" {
  description = "Nombre de la base de datos"
  type        = string
  default     = "ecommerce"
}

variable "db_username" {
  description = "Usuario de la base de datos"
  type        = string
  default     = "ecommerceuser"
}

variable "db_password" {
  description = "Contraseña de la base de datos"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "Tipo de instancia de RDS"
  type        = string
  default     = "db.t3.micro"
}

# Variables de red
variable "vpc_cidr" {
  description = "CIDR block para la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnets_cidr" {
  description = "CIDR blocks para las subnets privadas"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnets_cidr" {
  description = "CIDR blocks para las subnets públicas"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

# Variables de la aplicación
variable "flask_app_port" {
  description = "Puerto de la aplicación Flask"
  type        = number
  default     = 8080
}

variable "lambda_runtime" {
  description = "Runtime para las funciones Lambda"
  type        = string
  default     = "python3.11"
}

# Tags comunes
variable "common_tags" {
  description = "Tags comunes para todos los recursos"
  type        = map(string)
  default = {
    Project   = "data-project-3"
    ManagedBy = "terraform"
  }
}