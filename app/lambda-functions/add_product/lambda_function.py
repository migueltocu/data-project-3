import json
import psycopg2
import os
import boto3
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    """
    Función Lambda para añadir un nuevo producto a la base de datos
    """
    
    try:
        # Parsear el cuerpo de la petición
        if 'body' in event:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
        else:
            body = event
        
        # Validar datos requeridos
        name = body.get('name')
        price = body.get('price')
        description = body.get('description', '')
        
        if not name or not price:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'name y price son campos requeridos'})
            }
        
        # Validar precio
        try:
            price = float(price)
            if price <= 0:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({'error': 'El precio debe ser mayor que 0'})
                }
        except (ValueError, TypeError):
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Precio inválido'})
            }
        
        # Obtener configuración de la base de datos desde variables de entorno
        db_host = os.environ.get('DB_HOST')
        db_name = os.environ.get('DB_NAME')
        db_username = os.environ.get('DB_USERNAME')
        
        if not all([db_host, db_name, db_username]):
            return {
                'statusCode': 500,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Configuración de base de datos incompleta'})
            }
        
        # Limpiar el endpoint de RDS (quitar el puerto si viene incluido)
        if ':' in db_host:
            db_host = db_host.split(':')[0]
        
        # Conectar a la base de datos usando autenticación IAM
        try:
            # Generar token de autenticación IAM
            rds_client = boto3.client('rds')
            token = rds_client.generate_db_auth_token(
                DBHostname=db_host,
                Port=5432,
                DBUsername=db_username
            )
            
            # Conectar usando el token
            conn = psycopg2.connect(
                host=db_host,
                port=5432,
                database=db_name,
                user=db_username,
                password=token,
                sslmode='require'
            )
        except Exception as e:
            print(f"Error conectando con IAM auth: {str(e)}")
            # Fallback: intentar con contraseña desde variables de entorno
            db_password = os.environ.get('DB_PASSWORD') # No es una buena práctica que si el role no funcione se use la contraseña, ya que puede ser un escalado de privilegios
            if not db_password:
                raise Exception("No se puede conectar con IAM ni con contraseña")
            
            conn = psycopg2.connect(
                host=db_host,
                port=5432,
                database=db_name,
                user=db_username,
                password=db_password,
                sslmode='require'
            )
        
        cursor = conn.cursor()
        
        # Deberías tener una lambda como la de db-bootstrap que configure la base de datos y cree las tablas necesarias. Pero para un dp me parece bien que lo hagas aquí.
        # Crear tabla si no existe
        create_table_query = """
        CREATE TABLE IF NOT EXISTS products (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            price DECIMAL(10,2) NOT NULL,
            description TEXT,
            available BOOLEAN DEFAULT true,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        """
        cursor.execute(create_table_query)
        conn.commit()
        
        # Insertar nuevo producto
        insert_query = """
        INSERT INTO products (name, price, description, available)
        VALUES (%s, %s, %s, %s)
        RETURNING id, name, price, description, available, created_at;
        """
        cursor.execute(insert_query, (name, price, description, True))
        
        # Obtener el producto insertado
        new_product = cursor.fetchone()
        conn.commit()
        
        cursor.close()
        conn.close()
        
        # Formatear respuesta
        product_data = {
            'id': new_product[0],
            'name': new_product[1],
            'price': float(new_product[2]),
            'description': new_product[3],
            'available': new_product[4],
            'created_at': new_product[5].isoformat() if new_product[5] else None
        }
        
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'Producto añadido exitosamente',
                'product': product_data
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Error interno del servidor',
                'message': str(e)
            })
        }
