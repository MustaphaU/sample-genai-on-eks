################################################################################
# RAG Storage
################################################################################

locals {
  rag_data_bucket_name   = "rag-workshop-data-${data.aws_caller_identity.current.account_id}-${local.region}"
  rag_vector_bucket_name = "rag-vectors-${data.aws_caller_identity.current.account_id}-${local.region}"
  rag_vector_index_name  = "knowledge-base"
}

resource "aws_s3_bucket" "rag_data" {
  count = var.enable_rag ? 1 : 0

  bucket        = local.rag_data_bucket_name
  force_destroy = true

  tags = merge(local.tags, {
    Name        = local.rag_data_bucket_name
    Purpose     = "RAG source documents"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "rag_data" {
  count = var.enable_rag ? 1 : 0

  bucket = aws_s3_bucket.rag_data[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "rag_data" {
  count = var.enable_rag ? 1 : 0

  bucket = aws_s3_bucket.rag_data[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3vectors_vector_bucket" "rag" {
  count = var.enable_rag ? 1 : 0

  vector_bucket_name = local.rag_vector_bucket_name
  force_destroy      = true

  tags = merge(local.tags, {
    Name        = local.rag_vector_bucket_name
    Purpose     = "RAG vector storage"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}

resource "aws_s3vectors_index" "rag" {
  count = var.enable_rag ? 1 : 0

  vector_bucket_name = aws_s3vectors_vector_bucket.rag[0].vector_bucket_name
  index_name         = local.rag_vector_index_name
  data_type          = "float32"
  dimension          = 384
  distance_metric    = "cosine"

  tags = merge(local.tags, {
    Name        = local.rag_vector_index_name
    Purpose     = "RAG semantic search index"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}

################################################################################
# RAG Workload Identity
################################################################################

resource "aws_iam_role" "rag" {
  count = var.enable_rag ? 1 : 0

  name = "genai-rag-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = merge(local.tags, {
    Name        = "genai-rag-role"
    Purpose     = "RAG workload access"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}

resource "aws_iam_policy" "rag" {
  count = var.enable_rag ? 1 : 0

  name        = "genai-rag-policy"
  description = "Access to the workshop RAG data bucket and vector index"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.rag_data[0].arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.rag_data[0].arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3vectors:PutVectors",
          "s3vectors:QueryVectors",
          "s3vectors:GetVectors",
          "s3vectors:DeleteVectors"
        ]
        Resource = aws_s3vectors_index.rag[0].index_arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3vectors:GetVectorBucket",
          "s3vectors:ListIndexes",
          "s3vectors:GetIndex"
        ]
        Resource = [
          aws_s3vectors_vector_bucket.rag[0].vector_bucket_arn,
          aws_s3vectors_index.rag[0].index_arn
        ]
      }
    ]
  })

  tags = merge(local.tags, {
    Name        = "genai-rag-policy"
    Purpose     = "RAG data access"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}

resource "aws_iam_role_policy_attachment" "rag" {
  count = var.enable_rag ? 1 : 0

  role       = aws_iam_role.rag[0].name
  policy_arn = aws_iam_policy.rag[0].arn
}

resource "kubectl_manifest" "rag_service_account" {
  count = var.enable_rag ? 1 : 0

  depends_on = [
    module.eks,
    module.eks.cluster_addons
  ]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = "s3-access-sa"
      namespace = "default"
      labels = {
        "app.kubernetes.io/name"       = "rag"
        "app.kubernetes.io/component"  = "service-account"
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }
  })
}

resource "aws_eks_pod_identity_association" "rag" {
  count = var.enable_rag ? 1 : 0

  cluster_name    = module.eks.cluster_name
  namespace       = "default"
  service_account = "s3-access-sa"
  role_arn        = aws_iam_role.rag[0].arn

  tags = merge(local.tags, {
    Name        = "rag-pod-identity"
    Purpose     = "Pod Identity association for RAG workloads"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })

  depends_on = [
    aws_iam_role_policy_attachment.rag,
    kubectl_manifest.rag_service_account,
    module.eks.cluster_addons
  ]
}
