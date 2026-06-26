import json
import os
import time

import boto3
from botocore.exceptions import ClientError


ec2 = boto3.client("ec2")
rds = boto3.client("rds")
ssm = boto3.client("ssm")

APP_INSTANCE_ID = os.environ["APP_INSTANCE_ID"]
DB_IDENTIFIER = os.environ["DB_IDENTIFIER"]
BACKUP_COMMAND_TIMEOUT_SECONDS = int(os.environ.get("BACKUP_COMMAND_TIMEOUT_SECONDS", "600"))

EC2_STOPPABLE_STATES = {"pending", "running", "stopping"}
EC2_STARTABLE_STATES = {"stopped"}
RDS_STOPPABLE_STATES = {"available"}
RDS_STARTABLE_STATES = {"stopped"}
SSM_TERMINAL_STATES = {"Success", "Cancelled", "Failed", "TimedOut", "Cancelling"}


def ec2_state():
    response = ec2.describe_instances(InstanceIds=[APP_INSTANCE_ID])
    return response["Reservations"][0]["Instances"][0]["State"]["Name"]


def rds_state():
    response = rds.describe_db_instances(DBInstanceIdentifier=DB_IDENTIFIER)
    return response["DBInstances"][0]["DBInstanceStatus"]


def run_mysql_backup():
    command = ssm.send_command(
        InstanceIds=[APP_INSTANCE_ID],
        DocumentName="AWS-RunShellScript",
        Parameters={
            "commands": ["/opt/darkmira-maintenance/backup-mysql.sh"],
            "executionTimeout": [str(BACKUP_COMMAND_TIMEOUT_SECONDS)],
        },
        Comment="Export MySQL database before nightly RDS shutdown",
    )

    command_id = command["Command"]["CommandId"]
    deadline = time.monotonic() + BACKUP_COMMAND_TIMEOUT_SECONDS
    last_status = "Pending"

    while time.monotonic() < deadline:
        try:
            invocation = ssm.get_command_invocation(
                CommandId=command_id,
                InstanceId=APP_INSTANCE_ID,
            )
        except ClientError as exc:
            error_code = exc.response.get("Error", {}).get("Code")
            if error_code != "InvocationDoesNotExist":
                raise
            time.sleep(5)
            continue

        last_status = invocation["Status"]
        if last_status in SSM_TERMINAL_STATES:
            if last_status == "Success":
                return {"command_id": command_id, "status": last_status}

            stderr = invocation.get("StandardErrorContent", "")
            stdout = invocation.get("StandardOutputContent", "")
            raise RuntimeError(
                "MySQL backup command failed "
                f"with status {last_status}: {stderr or stdout}"
            )

        time.sleep(15)

    raise TimeoutError(
        "MySQL backup command did not finish "
        f"within {BACKUP_COMMAND_TIMEOUT_SECONDS} seconds; last status: {last_status}"
    )


def handler(event, context):
    action = event.get("action")
    result = {"action": action, "ec2": {}, "rds": {}}

    if action == "stop":
        current_ec2_state = ec2_state()
        result["ec2"]["previous_state"] = current_ec2_state

        current_rds_state = rds_state()
        result["rds"]["previous_state"] = current_rds_state
        if current_rds_state in RDS_STOPPABLE_STATES:
            if current_ec2_state != "running":
                raise RuntimeError(
                    "Cannot run MySQL backup before RDS shutdown "
                    f"because EC2 state is {current_ec2_state}"
                )

            result["backup"] = run_mysql_backup()

        if current_ec2_state in EC2_STOPPABLE_STATES:
            ec2.stop_instances(InstanceIds=[APP_INSTANCE_ID])
            result["ec2"]["requested"] = "stop"
        else:
            result["ec2"]["requested"] = "noop"

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

    elif action == "refresh-app":
        current_ec2_state = ec2_state()
        result["ec2"]["previous_state"] = current_ec2_state
        if current_ec2_state != "running":
            result["ec2"]["requested"] = "noop"
            result["ssm"] = {"reason": "instance-not-running"}
        else:
            command = ssm.send_command(
                InstanceIds=[APP_INSTANCE_ID],
                DocumentName="AWS-RunShellScript",
                Parameters={
                    "commands": ["/opt/darkmira-maintenance/deploy.sh refresh"],
                    "executionTimeout": ["1800"],
                },
                Comment="Refresh Darkmira app images after nightly EC2 startup",
            )
            result["ec2"]["requested"] = "refresh-app"
            result["ssm"] = {"command_id": command["Command"]["CommandId"]}

    else:
        raise ValueError(f"Unsupported action: {action}")

    print(json.dumps(result, sort_keys=True))
    return result
