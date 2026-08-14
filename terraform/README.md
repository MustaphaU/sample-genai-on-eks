# GenAI on EKS Workshop - Terraform Infrastructure

> Deploy the [GenAI on EKS Workshop](https://catalog.workshops.aws/genai-on-eks) infrastructure to your own AWS account using Terraform. This sets up a production-ready EKS cluster with GPU support, observability, and model storage — everything you need to run the workshop labs.

## Architecture

![GenAI on EKS Workshop Architecture](https://raw.githubusercontent.com/aws-samples/sample-genai-on-eks/main/architecture.png)

The Terraform configuration deploys:

- **Amazon EKS Auto Mode** cluster (Kubernetes 1.36) with system and general-purpose node pools
- **Amazon Managed Prometheus (AMP)** workspace for metrics collection
- **Grafana** with pre-built dashboards for vLLM, Ray Serve, and DCGM GPU metrics
- **S3 bucket** (`genai-models-<account-id>`) for model storage via Mountpoint S3 CSI driver
- **RAG storage** with an S3 data bucket, S3 vector bucket, and 384-dimension cosine index
- **Strands repository** in Amazon ECR for the workshop-built agent image
- **VPC** with public/private subnets across multiple AZs
- **IAM roles and Pod Identity** associations for secure workload access
- **kube-prometheus-stack** for cluster observability with remote write to AMP
- Optional **ElastiCache Serverless for Valkey** cache for LMCache remote cache sharing

---

## Prerequisites

| Tool      | Version | Install                                                                                |
| --------- | ------- | -------------------------------------------------------------------------------------- |
| AWS CLI   | >= 2.x  | [Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| Terraform | >= 1.3  | [Guide](https://developer.hashicorp.com/terraform/install)                             |
| kubectl   | latest  | [Guide](https://kubernetes.io/docs/tasks/tools/)                                       |

Ensure your AWS credentials are configured:

```bash
aws sts get-caller-identity
```

---

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/aws-samples/sample-genai-on-eks.git
cd sample-genai-on-eks/terraform
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Deploy the infrastructure

Deploy with the default region (`us-east-2`):

```bash
terraform apply --auto-approve
```

Or deploy to a different region:

```bash
terraform apply --auto-approve -var="region=us-west-2"
```

Valkey, RAG, and Strands infrastructure are enabled by default. Self-paced users can explicitly opt out of modules they do not plan to run:

| Variable         | Default | Resources                                                       |
| ---------------- | ------- | --------------------------------------------------------------- |
| `enable_valkey`  | `true`  | ElastiCache Serverless for the LMCache remote cache sharing lab |
| `enable_rag`     | `true`  | RAG S3 buckets, vector index, IAM role, and EKS Pod Identity    |
| `enable_strands` | `true`  | ECR repository for the Strands agent image                      |

For example, deploy without Valkey and Strands while retaining RAG:

```bash
terraform apply --auto-approve \
  -var="enable_valkey=false" \
  -var="enable_strands=false"
```

> Changing `enable_rag` or `enable_strands` from `true` to `false` force-deletes the corresponding workshop documents, vectors, or container images.

> Deployment takes approximately 20-25 minutes. Enabled optional modules can create additional billable AWS resources.

### 4. Configure kubectl

```bash
aws eks update-kubeconfig --name genai-workshop --region us-east-2
```

If you deployed to a different region, replace `us-east-2` with your chosen region.

### 5. Restrict ingress to your IP

Lock down ALB ingress to only allow traffic from your current public IP:

```bash
kubectl patch ingressclassparams alb --type=merge -p "{\"spec\":{\"inboundCIDRs\":[\"$(curl -s https://checkip.amazonaws.com | tr -d '\n')/32\"]}}"
```

### 6. (Optional) Reserve GPU capacity with an ODCR

By default, EKS Auto Mode provisions the workshop GPU node from available on-demand capacity, so an On-Demand Capacity Reservation (ODCR) is not required. Create one only if you want guaranteed GPU capacity for the session.

First, create an ODCR for GPU instances: [Create ODCR](https://catalog.workshops.aws/genai-on-eks/en-US/50-getting-started/01-self-paced)

The Terraform-managed `NodeClass/gpu` is not wired to any reservation, so patch it with your reservation ID. EKS Auto Mode then launches the GPU node from the reserved capacity:

```bash
kubectl patch nodeclass gpu --type merge \
  -p '{"spec":{"capacityReservationSelectorTerms":[{"id":"cr-0a1b2c3d4e5f67890"}]}}'
```

Confirm the reservation is attached:

```bash
kubectl get nodeclass gpu -o yaml | grep -A 3 capacityReservationSelectorTerms
```

The output should list your reservation ID under `capacityReservationSelectorTerms`.

### 7. Follow the Workshop

Follow along with the workshop labs: [Workshop Instructions](https://catalog.workshops.aws/genai-on-eks/en-US/50-getting-started/01-self-paced)

---

## Cleanup

To destroy all resources and avoid ongoing AWS charges:

```bash
terraform destroy --auto-approve
```

Or if you deployed to a custom region:

```bash
terraform destroy --auto-approve -var="region=us-west-2"
```

> The S3 model bucket, RAG data bucket, S3 vector bucket, and Strands ECR repository use force-delete settings, so Terraform removes their contents during teardown. Do not store data or images in these workshop resources that you need to retain.

---

## Troubleshooting

| Issue                   | Solution                                                               |
| ----------------------- | ---------------------------------------------------------------------- |
| Timeout during apply    | Re-run `terraform apply` — some resources take time to stabilize       |
| kubectl auth errors     | Run `aws eks update-kubeconfig` again with the correct region          |
| GPU nodes not launching | Verify your account has quota for the GPU instance type in your region |
| Grafana shows no data   | Wait 2-3 minutes for Prometheus to start scraping and remote writing   |
