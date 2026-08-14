################################################################################
# Strands Agent Container Repository
################################################################################

resource "aws_ecr_repository" "strands" {
  count = var.enable_strands ? 1 : 0

  name                 = "strands-weather-agent"
  force_delete         = true
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.tags, {
    Name        = "strands-weather-agent"
    Purpose     = "Strands agent container images"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}
