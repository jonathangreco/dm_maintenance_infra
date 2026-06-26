resource "aws_s3_bucket" "mysql_backups" {
  bucket_prefix = "${local.name_prefix}-mysql-backups-"

  tags = {
    Name = "${local.name_prefix}-mysql-backups"
  }
}

resource "aws_s3_bucket_public_access_block" "mysql_backups" {
  bucket = aws_s3_bucket.mysql_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "mysql_backups" {
  bucket = aws_s3_bucket.mysql_backups.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mysql_backups" {
  bucket = aws_s3_bucket.mysql_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "mysql_backups" {
  bucket = aws_s3_bucket.mysql_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "mysql_backups" {
  bucket = aws_s3_bucket.mysql_backups.id

  rule {
    id     = "expire-backups-after-seven-days"
    status = "Enabled"

    filter {
      prefix = "mysql/"
    }

    expiration {
      days = var.mysql_backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.mysql_backup_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_policy" "mysql_backups" {
  bucket = aws_s3_bucket.mysql_backups.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.mysql_backups.arn,
          "${aws_s3_bucket.mysql_backups.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
