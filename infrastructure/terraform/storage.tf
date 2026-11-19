resource "aws_s3_bucket" "data_lake" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy_bucket
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

data "aws_iam_policy_document" "deny_insecure_s3_transport" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.data_lake.arn,
      "${aws_s3_bucket.data_lake.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  policy = data.aws_iam_policy_document.deny_insecure_s3_transport.json
}

resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  depends_on = [aws_s3_bucket_versioning.data_lake]

  transition_default_minimum_object_size = "all_storage_classes_128K"

  # Large raw snapshots: tier, archive, then delete.
  rule {
    id     = "raw-large-tiering"
    status = "Enabled"

    filter {
      and {
        prefix                   = "raw/"
        object_size_greater_than = 131071
      }
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  # Small objects are not tiered because minimum-size and request charges can
  # cost more than the storage saved. They are removed after the curated copy
  # has been available for 90 days.
  rule {
    id     = "raw-small-expiration"
    status = "Enabled"

    filter {
      and {
        prefix                = "raw/"
        object_size_less_than = 131072
      }
    }

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "curated-large-tiering"
    status = "Enabled"

    filter {
      and {
        prefix                   = "curated/"
        object_size_greater_than = 131071
      }
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    expiration {
      days = 730
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "curated-small-expiration"
    status = "Enabled"

    filter {
      and {
        prefix                = "curated/"
        object_size_less_than = 131072
      }
    }

    expiration {
      days = 730
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "athena-results-expiration"
    status = "Enabled"

    filter {
      prefix = "athena-results/"
    }

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  rule {
    id     = "glue-temp-expiration"
    status = "Enabled"

    filter {
      prefix = "glue-temp/"
    }

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  rule {
    id     = "glue-assets-version-cleanup"
    status = "Enabled"

    filter {
      prefix = "glue-assets/"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "glue-assets/raw_to_curated.py"
  source = "${path.module}/../../src/glue/raw_to_curated.py"
  etag   = filemd5("${path.module}/../../src/glue/raw_to_curated.py")
}
