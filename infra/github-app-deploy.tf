data "aws_iam_policy_document" "github_actions_app_deploy_trust" {
  statement {
    sid     = "GithubActionsAppDeployAssumeRoleWithOidc"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::387219500605:oidc-provider/token.actions.githubusercontent.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:jonathangreco/dm_maintenance:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions_app_deploy" {
  name               = "${local.name_prefix}-github-actions-app-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_app_deploy_trust.json
  description        = "Role assume via OIDC par GitHub Actions pour deployer l'application via SSM."

  tags = {
    Name = "${local.name_prefix}-github-actions-app-deploy"
  }
}

data "aws_iam_policy_document" "github_actions_app_deploy" {
  statement {
    sid    = "FindRunningAppInstance"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "RunDeployReleaseOnAppInstance"
    effect = "Allow"
    actions = [
      "ssm:SendCommand"
    ]
    resources = [
      aws_instance.app.arn,
      "arn:aws:ssm:${var.aws_region}:*:document/AWS-RunShellScript"
    ]
  }

  statement {
    sid    = "ReadDeployCommandResult"
    effect = "Allow"
    actions = [
      "ssm:GetCommandInvocation"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_app_deploy" {
  name   = "${local.name_prefix}-github-actions-app-deploy"
  role   = aws_iam_role.github_actions_app_deploy.id
  policy = data.aws_iam_policy_document.github_actions_app_deploy.json
}
