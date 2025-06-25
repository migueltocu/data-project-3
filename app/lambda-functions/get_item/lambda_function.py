import json
import psycopg2
import os
import boto3
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    """
    Función Lambda para simular compra de producto (marcar como no disponible)
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
        
        product_id = body.get('product_id')
        
        if not product_id:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'product_id es requerido'})
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
        
        # Verificar si el producto existe y está disponible
        check_query = """
        SELECT id, name, available 
        FROM products 
        WHERE id = %s;
        """
        cursor.execute(check_query, (product_id,))
        result = cursor.fetchone()
        
        if not result:
            cursor.close()
            conn.close()
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Producto no encontrado'})
            }
        
        product_name = result[1]
        is_available = result[2]
        
        if not is_available:
            cursor.close()
            conn.close()
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': f'El producto "{product_name}" ya no está disponible'})
            }
        
        # Marcar producto como no disponible (simular compra)
        update_query = """
        UPDATE products 
        SET available = false 
        WHERE id = %s;
        """
        cursor.execute(update_query, (product_id,))
        conn.commit()
        
        cursor.close()
        conn.close()
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': f'Producto "{product_name}" comprado exitosamente',
                'product_id': product_id,
                'product_name': product_name
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