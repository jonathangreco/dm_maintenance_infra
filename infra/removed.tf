# Le bucket des anciennes sauvegardes MySQL est versionne et non vide :
# AWS refuse de le supprimer. Terraform cesse de le gerer sans le detruire ;
# les dumps restent dans AWS, a vider ou supprimer a la main.
removed {
  from = aws_s3_bucket.mysql_backups
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_s3_bucket_lifecycle_configuration.mysql_backups
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_s3_bucket_ownership_controls.mysql_backups
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_s3_bucket_policy.mysql_backups
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_s3_bucket_public_access_block.mysql_backups
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_s3_bucket_server_side_encryption_configuration.mysql_backups
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_s3_bucket_versioning.mysql_backups
  lifecycle {
    destroy = false
  }
}
