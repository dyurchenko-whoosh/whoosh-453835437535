#!/usr/bin/env python3

import urllib.request
import urllib.parse
import sys
import os
import json
import logging
import argparse
import textwrap
import time
import datetime

LOGGING_LEVEL = logging.INFO
GITLAB_API_URL = 'https://gitlab.com/api/v4'


def gitlab_request(resource, data=None, headers={}, method = 'GET'):
    try:
        headers.update({
            'Content-Type': 'application/json',
        })
        if data:
            data = json.dumps(data).encode('ascii')

        req = urllib.request.Request(url=GITLAB_API_URL + '/' + resource, data=data, headers=headers, method=method)
        f = urllib.request.urlopen(req)
        response = json.loads(f.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        raise Exception('Gitlab error: code: %s %s, answer: %s' % (e.code, e.reason, e.read().decode('utf-8')))
    except Exception as e:
        raise e from e

    logging.debug(response)
    return response


def main():
    GITLAB_PROJECT =  os.environ['GITLAB_PROJECT']
    BRANCH = os.environ['BRANCH']
    ENV = os.environ['ENV']
    BUILD_USER = os.getenv('BUILD_USER', '')

    logging.basicConfig(
        stream=sys.stderr,
        format='%(asctime)s %(name)s %(levelname)s %(message)s',
        level=LOGGING_LEVEL
    )

    start_time = datetime.datetime.now()

    headers = {
        'PRIVATE-TOKEN': os.getenv('GITLAB_TOKEN')
    }
    data = {
        'ref': BRANCH,
        'variables': [
            {
                'key': 'TARGET_ENV',
                'value': ENV
            },
            {
                'key': 'WHOOSH_USER_NAME',
                'value': BUILD_USER
            }
        ]
    }

    try:
        logging.info('Pipeline to %s from branch %s in project %s started by %s' % (
            ENV,
            BRANCH,
            GITLAB_PROJECT,
            BUILD_USER
        ))

        response = gitlab_request(
            resource='projects/%s/pipeline' % urllib.parse.quote_plus(GITLAB_PROJECT),
            data=data,
            headers=headers,
            method='POST'
        )
        logging.info('Created pipeline %s in project %s' % (response['id'], GITLAB_PROJECT))
        logging.info('Pipeline %s url: %s' % (response['id'], response['web_url']))
        #print(json.dumps(response, indent=4, sort_keys=True))

        logging.info('Wait for pipeline %s to complete' % response['id'])
        while response['status'] not in ['success', 'failed', 'canceled', 'skipped']:
            response = gitlab_request(
                resource='projects/%s/pipelines/%s' % (urllib.parse.quote_plus(GITLAB_PROJECT), response['id']),
                headers=headers
            )
            logging.info('Pipeline %s status: %s' % (response['id'], response['status']))
            logging.info('Sleep 10s...')
            time.sleep(10)

        if response['status'] in ['failed', 'canceled']:
            raise Exception('Pipeline %s failed with status %s' % (response['id'], response['status']))

    except Exception as e:
        logging.error(e)
        return 1
    finally:
        logging.info('Pipeline took: %d sec' % (datetime.datetime.now() - start_time).total_seconds())


if __name__ == '__main__':
    sys.exit(main())
