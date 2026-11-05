# DOCUMENTS_BUCKET de Darkmira Service : bundles livres, echanges avec le
# modele d'IA, journaux fail-safe. Conserves sans expiration.
resource "aws_s3_bucket" "documents" {
  bucket = "dm-${var.environment}-documents-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name = "dm-${var.environment}-documents-${data.aws_caller_identity.current.account_id}"
  })
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Un envoi multipart interrompu (bundle volumineux) ne laisse pas de parts.
resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Le trafic S3 de l'EC2 et des taches reste dans le VPC (point de terminaison
# gateway, gratuit).
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-endpoint"
  })
}
