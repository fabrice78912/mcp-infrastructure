import json
import os

def handler(event, context):
    """
    Lambda function qui sert l'interface Swagger UI.
    Retourne une page HTML statique avec Swagger UI configuré
    pour charger la spec OpenAPI depuis /swagger.json
    """

    # Récupérer l'API Gateway ID et le stage depuis les variables d'environnement
    api_id = os.environ.get('API_GATEWAY_ID', '')
    stage = os.environ.get('STAGE_NAME', 'dev')
    region = os.environ.get('AWS_REGION', 'ca-central-1')

    # URL de base de l'API
    base_url = f"https://{api_id}.execute-api.{region}.amazonaws.com/{stage}"

    # HTML avec Swagger UI
    html_content = f"""
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MCP API - Documentation Swagger</title>
    <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5.9.0/swagger-ui.css">
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
        .topbar {{
            background-color: #1b1b1b;
            padding: 10px 0;
        }}
        .topbar-wrapper {{
            max-width: 1460px;
            margin: 0 auto;
            padding: 0 20px;
        }}
        .topbar-wrapper a {{
            color: #fff;
            text-decoration: none;
            font-size: 1.5em;
            font-weight: bold;
        }}
        .info {{
            background-color: #f7f7f7;
            border-left: 4px solid #4CAF50;
            padding: 15px;
            margin: 20px;
            border-radius: 4px;
        }}
    </style>
</head>
<body>
    <div class="topbar">
        <div class="topbar-wrapper">
            <a href="#"><span>MCP API</span> - Documentation Interactive</a>
        </div>
    </div>

    <div class="info">
        <h2>🚀 Bienvenue dans la documentation de l'API MCP</h2>
        <p>
            Cette API permet de gérer les mises à jour des noms de clients dans le système MCP.
            Utilisez l'interface ci-dessous pour explorer et tester les endpoints disponibles.
        </p>
        <ul>
            <li><strong>Environnement:</strong> {stage.upper()}</li>
            <li><strong>URL de base:</strong> <code>{base_url}</code></li>
            <li><strong>Région AWS:</strong> {region}</li>
        </ul>
        <p>
            💡 <strong>Astuce:</strong> Utilisez le bouton "Try it out" pour tester les endpoints directement depuis cette interface.
        </p>
    </div>

    <div id="swagger-ui"></div>

    <script src="https://unpkg.com/swagger-ui-dist@5.9.0/swagger-ui-bundle.js"></script>
    <script src="https://unpkg.com/swagger-ui-dist@5.9.0/swagger-ui-standalone-preset.js"></script>
    <script>
        window.onload = function() {{
            const ui = SwaggerUIBundle({{
                url: "{base_url}/swagger.json",
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
                displayRequestDuration: true,
                filter: true,
                tryItOutEnabled: true,
                persistAuthorization: true
            }});

            window.ui = ui;
        }};
    </script>
</body>
</html>
    """

    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'text/html',
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Pragma': 'no-cache',
            'Expires': '0'
        },
        'body': html_content
    }