import json
import pprint
import boto3
import logging
import urllib3

# Create a SSM Client to access parameter store
ssm = boto3.client('ssm')

logger = logging.getLogger()
logger.setLevel(logging.INFO)
http = urllib3.PoolManager()


class Alarm:
    def __init__(self, json_message):
        self.message = json.loads(json_message)

    @property
    def name(self):
        return self.message['AlarmName']

    @property
    def namespace(self):
        return self.message['Trigger']['Namespace']

    @property
    def metric_name(self):
        return self.message['Trigger']['MetricName']

    @property
    def dimensions(self):
        return self.message['Trigger']['Dimensions']

    @property
    def state_reason(self):
        return self.message['NewStateReason']

    @property
    def state_value(self):
        return self.message['NewStateValue']


def lambda_handler(event, context):
    alarm = Alarm(event['Records'][0]['Sns']['Message'])

    webhook_url = ssm.get_parameter(Name='/utils/slack/webhook_url', WithDecryption=True)['Parameter']['Value']

    if alarm.state_value == "ALARM":
        color = "danger"
    elif alarm.state_value == "OK":
        color = "good"

    slack_data = {'username': 'cloudwatch-alert',
                  "icon_emoji": ":slack:",
                  "attachments": [{
                      'color': color,
                      'fallback': alarm.name,
                      "title": f'Alarm: {alarm.name}',
                      "fields": [
                          {
                              "title": "Metric",
                              "value": f"{alarm.namespace}/{alarm.metric_name}"
                          },
                          {
                              "title": "Dimensions",
                              "value": f"{pprint.pformat(alarm.dimensions)}"
                          },
                          {
                              "title": "Reason",
                              "value": alarm.state_reason
                          }
                      ]
                  }]}

    response = http.request('POST', webhook_url, body=json.dumps(slack_data),
                            headers={'Content-Type': 'application/json'}, retries=False)
