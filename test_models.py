import urllib.request
import json
import urllib.error

key = 'AIzaSyDFLbtaV-uTEc4WW4_Cqps_ZnlJC-rOpHg'
url = f'https://generativelanguage.googleapis.com/v1beta/models?key={key}'

try:
    with urllib.request.urlopen(url) as response:
        data = json.loads(response.read().decode())
        for model in data.get('models', []):
            if 'gemini' in model['name']:
                print(model['name'])
except urllib.error.HTTPError as e:
    print(e.read().decode())
