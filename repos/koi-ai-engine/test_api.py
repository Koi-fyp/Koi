import os
import subprocess
import sys
import time

import httpx


BASE_URL = os.getenv('KOI_AI_ENGINE_URL', 'http://127.0.0.1:8000')


def start_server():
    env = os.environ.copy()
    process = subprocess.Popen(
        [sys.executable, '-m', 'uvicorn', 'main:app', '--host', '127.0.0.1', '--port', '8000'],
        cwd=os.path.dirname(__file__),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    time.sleep(3)
    return process


def main():
    process = start_server()
    try:
        with httpx.Client(timeout=10.0) as client:
            health = client.get(f'{BASE_URL}/health')
            assert health.status_code == 200, f'health failed: {health.status_code} {health.text}'

            warmup = client.get(f'{BASE_URL}/ai/warmup')
            assert warmup.status_code == 200, f'warmup failed: {warmup.status_code} {warmup.text}'

            unauthorized = client.post(f'{BASE_URL}/ai/inference', json={'prompt': 'hello'})
            assert unauthorized.status_code == 401, f'expected 401, got {unauthorized.status_code} {unauthorized.text}'

        print('API verification passed')
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()


if __name__ == '__main__':
    main()
