import json
import psycopg2
import os
import boto3
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    """
    Función Lambda para obtener todos los productos de la base de datos
    """
    
    try:
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
            db_password = os.environ.get('DB_PASSWORD')
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
        
        # Obtener todos los productos
        select_query = """
        SELECT id, name, price, description, available, created_at
        FROM products
        ORDER BY created_at DESC;
        """
        cursor.execute(select_query)
        
        # Formatear resultados
        columns = ['id', 'name', 'price', 'description', 'available', 'created_at']
        products = []
        
        for row in cursor.fetchall():
            product = {}
            for i, column in enumerate(columns):
                if column == 'price':
                    product[column] = float(row[i])
                elif column == 'created_at':
                    product[column] = row[i].isoformat() if row[i] else None
                else:
                    product[column] = row[i]
            products.append(product)
        
        cursor.close()
        conn.close()
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(products)
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