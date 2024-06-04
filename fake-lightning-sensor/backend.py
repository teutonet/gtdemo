from flask import Flask, request, send_file
from confluent_kafka import Producer
import json

producer = Producer({'bootstrap.servers': 'localhost:9092'})

app = Flask(__name__)

@app.route('/')
def serve_static_file():
    return send_file('index.html')

@app.route('/lightning', methods=['POST'])
def handle_json_request():
    producer.produce('lightning_coords', json.dumps(request.get_json()))
    producer.flush()
    return '', 204

if __name__ == '__main__':
    app.run()
