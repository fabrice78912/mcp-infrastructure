import json
import os

def handler(event, context):
    """
    Lambda handler pour servir Swagger UI
    Retourne une page HTML qui charge l'interface Swagger UI
    """

    # Récupérer l'URL de base de l'API depuis les variables d'environnement ou l'event
    api_gateway_id = os.environ.get('API_GATEWAY_ID', '')
    stage_name = os.environ.get('STAGE_NAME', 'dev')
    region = os.environ.get('AWS_REGION', 'ca-central-1')

    # Construire l'URL de base
    base_url = f"https://{api_gateway_id}.execute-api.{region}.amazonaws.com/{stage_name}"
    swagger_json_url = f"{base_url}/swagger.json"

    # HTML pour Swagger UI
    html_content = f"""
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MCP API - Swagger UI</title>
    <link rel="stylesheet" type="text/css" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.10.0/swagger-ui.css" />
    <link rel="icon" type="image/png" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.10.0/favicon-32x32.png" sizes="32x32" />
    <style>
        html {{
            box-sizing: border-box;
            overflow: -moz-scrollbars-vertical;
            overflow-y: scroll;
        }}

        *, *:before, *:after {{
            box-sizing: inherit;
        }}

        body {{
            margin: 0;
            padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        }}

        .swagger-ui .topbar {{
            background-color: #1b1b1b;
            padding: 10px 0;
        }}

        .swagger-ui .topbar .wrapper {{
            max-width: 1460px;
            margin: 0 auto;
            padding: 0 20px;
        }}

        .custom-header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px 20px;
            text-align: center;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }}

        .custom-header h1 {{
            margin: 0 0 10px 0;
            font-size: 2.5rem;
            font-weight: 700;
        }}

        .custom-header p {{
            margin: 5px 0;
            font-size: 1.1rem;
            opacity: 0.9;
        }}

        .custom-header .info-badge {{
            display: inline-block;
            background: rgba(255,255,255,0.2);
            padding: 5px 15px;
            margin: 5px;
            border-radius: 20px;
            font-size: 0.9rem;
        }}
    </style>
</head>
<body>
    <div class="custom-header">
        <h1>🚀 MCP API Documentation</h1>
        <p>API de gestion des profils clients - Documentation interactive</p>
        <div>
            <span class="info-badge">📍 Environnement: {stage_name.upper()}</span>
            <span class="info-badge">🌍 Région: {region}</span>
            <span class="info-badge">🔗 Base URL: {base_url}</span>
        </div>
    </div>

    <div id="swagger-ui"></div>

    <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.10.0/swagger-ui-bundle.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.10.0/swagger-ui-standalone-preset.js"></script>
    <script>
        window.onload = function() {{
            const ui = SwaggerUIBundle({{
                url: "{swagger_json_url}",
                dom_id: '#swagger-ui',
                deepLinking: true,
                presets: [
                    SwaggerUIBundle.presets.apis,
                    SwaggerUIStandalonePreset
                ],
                plugins: [
                    SwaggerUIBundle.plugins.DownloadUrl
                ],
                layout: "StandaloneLayout",
                defaultModelsExpandDepth: 1,
                defaultModelExpandDepth: 1,
                docExpansion: "list",
                filter: true,
                showRequestHeaders: true,
                showCommonExtensions: true,
                tryItOutEnabled: true,
                displayRequestDuration: true,
                persistAuthorization: true,
                syntaxHighlight: {{
                    activate: true,
                    theme: "monokai"
                }}
            }});

            window.ui = ui;

            // Log pour debugging
            console.log('Swagger UI initialized');
            console.log('API Spec URL:', "{swagger_json_url}");
            console.log('Base URL:', "{base_url}");
        }};
    </script>
</body>
</html>
"""

    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'text/html; charset=utf-8',
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Pragma': 'no-cache',
            'Expires': '0'
        },
        'body': html_content
    }
