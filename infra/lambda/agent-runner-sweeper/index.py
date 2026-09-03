import os
from datetime import datetime, timezone

import boto3

ecs = boto3.client("ecs")

CLUSTER = os.environ["CLUSTER_ARN"]
MAX_MINUTES = int(os.environ["MAX_TASK_MINUTES"])


def handler(event, context):
    stopped = []
    paginator = ecs.get_paginator("list_tasks")

    for page in paginator.paginate(cluster=CLUSTER, desiredStatus="RUNNING"):
        arns = page.get("taskArns", [])
        if not arns:
            continue

        for task in ecs.describe_tasks(cluster=CLUSTER, tasks=arns).get("tasks", []):
            started_at = task.get("startedAt") or task.get("createdAt")
            if started_at is None:
                continue

            age_minutes = (datetime.now(timezone.utc) - started_at).total_seconds() / 60
            if age_minutes < MAX_MINUTES:
                continue

            ecs.stop_task(
                cluster=CLUSTER,
                task=task["taskArn"],
                reason=f"Orpheline depuis {int(age_minutes)} minutes",
            )
            stopped.append(task["taskArn"])

    return {"stopped": stopped}
