# Proyecto de Ingeniería de Datos - Arquitectura Cloud Híbrida (GCP + AWS)

## Descripción General
Este proyecto implementa una arquitectura híbrida de ingeniería de datos combinando Google Cloud Platform (GCP) y Amazon Web Services (AWS) para crear un pipeline completo de datos de ecommerce.

## Arquitectura
El sistema consta de:

1. **Frontend**: Aplicación web Flask simulando una plataforma de ecommerce
2. **Backend**: Funciones Lambda de AWS para la lógica de negocio
3. **Base de Datos**: Amazon RDS con autenticación IAM
4. **Pipeline de Analítica**: GCP Datastream → BigQuery → Looker

## Componentes

### Aplicación Web (GCP Cloud Run)
- Aplicación Flask que simula un ecommerce
- Alojada en Google Cloud Run
- Proporciona interfaz web para gestión de productos

### Capa API (AWS Lambda)
Tres funciones Lambda manejan las operaciones principales:
- **GetProducts**: Obtener todos los productos disponibles de la base de datos
- **GetItem**: Simular compra de producto (marca el artículo como no disponible)
- **AddProduct**: Añadir nuevos productos al catálogo

### Capa de Base de Datos (AWS RDS)
- Base de datos PostgreSQL en Amazon RDS
- Autenticación basada en roles IAM
- Almacena catálogo de productos y datos de transacciones

### Pipeline de Analítica (GCP)
- **Datastream**: Replicación de datos en tiempo real desde RDS a BigQuery
- **BigQuery**: Data warehouse para analítica
- **Looker**: Inteligencia de negocio y visualización

## Flujo de la Arquitectura
![Diagrama de Arquitectura](docs/arquitectura-dp3.jpg)

## Infraestructura como Código
Toda la infraestructura se gestiona usando Terraform con configuraciones separadas para:
- Recursos GCP (Cloud Run, Datastream, BigQuery)
- Recursos AWS (Lambda, RDS, IAM)
- Redes y seguridad entre clouds

## Primeros Pasos

### Despliegue de Infraestructura

Los usuarios que clonen este repositorio pueden seguir estas instrucciones:

1. **Copiar y configurar variables**:
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   ```

2. **Editar `terraform.tfvars` con sus propios valores**:
   - Configurar `gcp_project_id` con tu proyecto de GCP
   - Establecer `db_password` con una contraseña segura
   - Ajustar otras variables según sea necesario

3. **Desplegar infraestructura**:
   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

### Pasos Adicionales
1. Configurar credenciales de GCP y AWS
2. Desplegar código de aplicación

## Estructura del Proyecto
```
.
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   └── terraform.tfvars.example
├── app/
│   ├── flask-app/
│   └── lambda-functions/
├── docs/
│   └── arquitectura-dp3.jpg
├── .gitignore
└── README.md
```