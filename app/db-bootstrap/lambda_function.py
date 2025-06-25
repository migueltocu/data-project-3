import json
import psycopg2
import os

def lambda_handler(event, context):
    """Configura PostgreSQL para Datastream desde Lambda"""
    
    try:
        # Conectar a PostgreSQL RDS
        conn = psycopg2.connect(
            host=os.environ['DB_HOST'].split(':')[0],
            database=os.environ['DB_NAME'],
            user=os.environ['DB_USERNAME'],
            password=os.environ['DB_PASSWORD'],
            port=5432,
            sslmode='require'
        )
        
        cur = conn.cursor()
        
        # Comandos de configuración para Datastream
        commands = [
            "CREATE PUBLICATION datastream_publication FOR ALL TABLES;",
            "SELECT PG_CREATE_LOGICAL_REPLICATION_SLOT('datastream_slot', 'pgoutput');",
            f"CREATE USER {os.environ['DATASTREAM_USER']} WITH ENCRYPTED PASSWORD '{os.environ['DATASTREAM_PASS']}';",
            f"GRANT rds_replication TO {os.environ['DATASTREAM_USER']};",
            f"GRANT USAGE ON SCHEMA public TO {os.environ['DATASTREAM_USER']};",
            f"GRANT SELECT ON ALL TABLES IN SCHEMA public TO {os.environ['DATASTREAM_USER']};",
            f"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO {os.environ['DATASTREAM_USER']};"
        ]
        
        results = []
        for cmd in commands:
            try:
                cur.execute(cmd)
                conn.commit()
                results.append(f"✅ Ejecutado: {cmd[:50]}...")
            except Exception as e:
                results.append(f"⚠️  Error (puede ser normal si ya existe): {str(e)}")
                conn.rollback()
        
        cur.close()
        conn.close()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Database configured successfully for Datastream',
                'results': results
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Failed to configure database: {str(e)}'
            })
        }