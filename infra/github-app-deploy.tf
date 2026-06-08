data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_actions_app_deploy_trust" {
  statement {
    sid     = "GithubActionsAppDeployAssumeRoleWithOidc"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github_actions.arn]
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

resource "aws_iam_policy" "github_actions_app_deploy" {
  name        = "${local.name_prefix}-github-actions-app-deploy"
  description = "Permissions pour deployer l'application sur EC2 via SSM depuis GitHub Actions."
  policy      = data.aws_iam_policy_document.github_actions_app_deploy.json

  tags = {
    Name = "${local.name_prefix}-github-actions-app-deploy"
  }
}

resource "aws_iam_role_policy_attachment" "github_actions_app_deploy" {
  role       = aws_iam_role.github_actions_app_deploy.name
  policy_arn = aws_iam_policy.github_actions_app_deploy.arn
}
