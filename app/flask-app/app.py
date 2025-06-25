from flask import Flask, render_template, request, jsonify, redirect, url_for, flash
import requests
import os
import logging

app = Flask(__name__)
# TODO SEGURIDAD: Configurar SECRET_KEY como variable de entorno en producción
app.secret_key = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-production-INSECURE')

# Configurar logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# URLs de las funciones Lambda (se obtienen de variables de entorno)
LAMBDA_GET_PRODUCTS_URL = os.environ.get('GET_PRODUCTS_URL', '')
LAMBDA_GET_ITEM_URL = os.environ.get('GET_ITEM_URL', '')
LAMBDA_ADD_PRODUCT_URL = os.environ.get('ADD_PRODUCT_URL', '')

@app.route('/')
def index():
    """Página principal del ecommerce"""
    try:
        # Obtener productos de la función Lambda
        if LAMBDA_GET_PRODUCTS_URL:
            response = requests.get(LAMBDA_GET_PRODUCTS_URL, timeout=10)
            if response.status_code == 200:
                products = response.json()
            else:
                logger.error(f"Error al obtener productos: {response.status_code}")
                products = []
        else:
            logger.warning("GET_PRODUCTS_URL no configurada")
            products = []
    except Exception as e:
        logger.error(f"Error conectando con Lambda GetProducts: {str(e)}")
        products = []
    
    return render_template('index.html', products=products)

@app.route('/products')
def list_products():
    """API endpoint para listar productos"""
    try:
        if LAMBDA_GET_PRODUCTS_URL:
            response = requests.get(LAMBDA_GET_PRODUCTS_URL, timeout=10)
            if response.status_code == 200:
                return jsonify(response.json())
            else:
                return jsonify({"error": "Error al obtener productos"}), 500
        else:
            return jsonify({"error": "Configuración de Lambda no disponible"}), 500
    except Exception as e:
        logger.error(f"Error en /products: {str(e)}")
        return jsonify({"error": "Error interno del servidor"}), 500

@app.route('/buy/<int:product_id>', methods=['POST'])
def buy_product(product_id):
    """Comprar un producto (marcar como no disponible)"""
    try:
        if LAMBDA_GET_ITEM_URL:
            # Enviar request a Lambda GetItem para simular compra
            response = requests.post(LAMBDA_GET_ITEM_URL, 
                                   json={"product_id": product_id}, 
                                   timeout=10)
            if response.status_code == 200:
                result = response.json()
                if 'error' in result:
                    flash(f"Error: {result['error']}", 'error')
                else:
                    flash("¡Producto comprado con éxito!", 'success')
            else:
                flash("Error al procesar la compra", 'error')
        else:
            flash("Función de compra no disponible", 'error')
    except Exception as e:
        logger.error(f"Error en compra: {str(e)}")
        flash("Error interno al procesar la compra", 'error')
    
    return redirect(url_for('index'))

@app.route('/add-product', methods=['GET', 'POST'])
def add_product():
    """Añadir nuevo producto"""
    if request.method == 'GET':
        return render_template('add_product.html')
    
    try:
        # Obtener datos del formulario
        name = request.form.get('name')
        price = request.form.get('price')
        description = request.form.get('description', '')
        
        if not name or not price:
            flash("Nombre y precio son obligatorios", 'error')
            return redirect(url_for('add_product'))
        
        # Validar precio
        try:
            price = float(price)
            if price <= 0:
                flash("El precio debe ser mayor que 0", 'error')
                return redirect(url_for('add_product'))
        except ValueError:
            flash("Precio inválido", 'error')
            return redirect(url_for('add_product'))
        
        if LAMBDA_ADD_PRODUCT_URL:
            # Enviar a Lambda AddProduct
            product_data = {
                "name": name,
                "price": price,
                "description": description
            }
            response = requests.post(LAMBDA_ADD_PRODUCT_URL, 
                                   json=product_data, 
                                   timeout=10)
            if response.status_code in [200, 201]:
                result = response.json()
                if 'error' in result:
                    flash(f"Error: {result['error']}", 'error')
                else:
                    flash("¡Producto añadido con éxito!", 'success')
                    return redirect(url_for('index'))
            else:
                flash("Error al añadir el producto", 'error')
        else:
            flash("Función de añadir producto no disponible", 'error')
    except Exception as e:
        logger.error(f"Error añadiendo producto: {str(e)}")
        flash("Error interno al añadir producto", 'error')
    
    return redirect(url_for('add_product'))

@app.route('/health')
def health_check():
    """Health check para Cloud Run"""
    return jsonify({
        "status": "healthy",
        "lambda_urls_configured": {
            "get_products": bool(LAMBDA_GET_PRODUCTS_URL),
            "get_item": bool(LAMBDA_GET_ITEM_URL),
            "add_product": bool(LAMBDA_ADD_PRODUCT_URL)
        }
    })

@app.errorhandler(404)
def not_found(error):
    return render_template('error.html', error="Página no encontrada"), 404

@app.errorhandler(500)
def internal_error(error):
    return render_template('error.html', error="Error interno del servidor"), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)