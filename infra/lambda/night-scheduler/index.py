import json
import os

import boto3


ec2 = boto3.client("ec2")
rds = boto3.client("rds")

APP_INSTANCE_ID = os.environ["APP_INSTANCE_ID"]
DB_IDENTIFIER = os.environ["DB_IDENTIFIER"]

EC2_STOPPABLE_STATES = {"pending", "running", "stopping"}
EC2_STARTABLE_STATES = {"stopped"}
RDS_STOPPABLE_STATES = {"available"}
RDS_STARTABLE_STATES = {"stopped"}


def ec2_state():
    response = ec2.describe_instances(InstanceIds=[APP_INSTANCE_ID])
    return response["Reservations"][0]["Instances"][0]["State"]["Name"]


def rds_state():
    response = rds.describe_db_instances(DBInstanceIdentifier=DB_IDENTIFIER)
    return response["DBInstances"][0]["DBInstanceStatus"]


def handler(event, context):
    action = event.get("action")
    result = {"action": action, "ec2": {}, "rds": {}}

    if action == "stop":
        current_ec2_state = ec2_state()
        result["ec2"]["previous_state"] = current_ec2_state
        if current_ec2_state in EC2_STOPPABLE_STATES:
            ec2.stop_instances(InstanceIds=[APP_INSTANCE_ID])
            result["ec2"]["requested"] = "stop"
        else:
            result["ec2"]["requested"] = "noop"

        current_rds_state = rds_state()
        result["rds"]["previous_state"] = current_rds_state
        if current_rds_state in RDS_STOPPABLE_STATES:
            rds.stop_db_instance(DBInstanceIdentifier=DB_IDENTIFIER)
            result["rds"]["requested"] = "stop"
        else:
            result["rds"]["requested"] = "noop"

    elif action == "start-rds":
        current_rds_state = rds_state()
        result["rds"]["previous_state"] = current_rds_state
        if current_rds_state in RDS_STARTABLE_STATES:
            rds.start_db_instance(DBInstanceIdentifier=DB_IDENTIFIER)
            result["rds"]["requested"] = "start"
        else:
            result["rds"]["requested"] = "noop"

    elif action == "start-ec2":
        current_ec2_state = ec2_state()
        result["ec2"]["previous_state"] = current_ec2_state
        if current_ec2_state in EC2_STARTABLE_STATES:
            ec2.start_instances(InstanceIds=[APP_INSTANCE_ID])
            result["ec2"]["requested"] = "start"
        else:
            result["ec2"]["requested"] = "noop"

    else:
        raise ValueError(f"Unsupported action: {action}")

    print(json.dumps(result, sort_keys=True))
    return result
