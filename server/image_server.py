import os
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
# from werkzeug.utils import secure_filename
from Crypto.Hash import keccak


app = Flask(__name__)
CORS(app)


@app.route('/')
def hello_world():
    return 'Hello World!\n'


@app.route('/upload', methods=['POST'])
def upload():
    img = request.files['file']
    # filename = secure_filename(img.filename)

    k = keccak.new(digest_bits=256)
    k.update(img.read())
    hashed_key = k.hexdigest()

    img.seek(0)
    img.save(os.path.join('./data', hashed_key))

    return jsonify({'hashed_key': hashed_key})


@app.route('/download', methods=['POST'])
def download():
    hashed_key = request.get_json()['hashed_key']

    return send_file(
        os.path.join('./data', hashed_key),
        as_attachment=True,
        attachment_filename=hashed_key+'.png',
        mimetype='image/png'
    )


def remove():
    pass


if __name__ == '__main__':
    if not os.path.exists('./data'):
        os.makedirs('./data')

    app.run(host='0.0.0.0', port=8327)
