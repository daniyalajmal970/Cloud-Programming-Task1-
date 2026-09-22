# Task 1: Highly available web hosting on AWS (Terraform)

Cloud Programming (CSEBSEPCP01_E), IU International University.

This Terraform project deploys a "Hello World" website with the following components:

| Requirement | How it is met |
|---|---|
| **High availability** | The VPC spans 2 Availability Zones. An Application Load Balancer sits in both public subnets. An Auto Scaling Group (min 2) keeps web servers in both private subnets and replaces any instance that fails the ALB health check. |
| **Low latency worldwide** | CloudFront uses all edge locations (`PriceClass_All`) and caches the page close to visitors. HTTP/2 and HTTP/3 are enabled. |
| **Autoscaling** | Two target-tracking policies: average CPU at 50 %, and 1000 ALB requests per instance per minute. Capacity ranges from 2 to 6 instances. |
| **Security** | Web servers run in private subnets with no public IP and no internet route. The ALB accepts only the CloudFront prefix list **and** a secret `X-Origin-Verify` header. IMDSv2 is enforced. The IAM role has least privilege (SSM only), and there is no SSH. CloudFront adds security headers. The default security group is locked down. |
| **Cost** | No NAT gateway, because packages come through the free S3 gateway endpoint. Instances are t3.micro. Everything is removed with `terraform destroy`. |
| **Reproducibility** | 100 % Infrastructure as Code. Every resource carries `default_tags`. An optional S3 remote state is available with native locking. |

```
Users ──HTTPS──► CloudFront (edge cache) ──HTTP + secret header──► ALB (2 AZs) ──► EC2 ASG (private subnets, 2 AZs)
                                                                                  ▲
                                                                     CloudWatch target tracking
```

## Project structure

| File | Content |
|---|---|
| `versions.tf` | Terraform and provider versions, optional S3 backend |
| `providers.tf` | AWS provider, region, default tags |
| `variables.tf` | All configurable values, with defaults |
| `network.tf` | VPC, public and private subnets, route tables, IGW, S3 gateway endpoint, optional SSM endpoints |
| `security.tf` | Security groups, IAM role and instance profile, origin secret |
| `alb.tf` | Load balancer, target group, listener (default 403) and the rule that forwards only CloudFront traffic |
| `compute.tf` | AMI lookup, launch template, Auto Scaling Group, 2 scaling policies |
| `cdn.tf` | CloudFront distribution (plus optional, commented Route 53/ACM block) |
| `monitoring.tf` | CloudWatch alarms, dashboard, optional e-mail notifications |
| `outputs.tf` | Website URL, ALB DNS name, ASG name, dashboard link |
| `templates/user_data.sh.tftpl` | Boot script: installs nginx and writes `index.html`, `whoami.html` and `/health` |
| `scripts/` | Test scripts for failover, autoscaling and latency |

## 1. Prerequisites (one-time setup)

1. **AWS account.** Sign in to the console and set up a **billing alarm/budget**: *Billing → Budgets → Create budget*, e.g. 10 USD.
2. **IAM user for the CLI.** Go to *IAM → Users → Create user*, e.g. `terraform-admin`, and attach the `AdministratorAccess` policy (fine for a personal course account). Then go to *Security credentials → Create access key → CLI*.
3. **Install the tools:**
   - AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
   - Terraform ≥ 1.10: https://developer.hashicorp.com/terraform/install
   - Git: https://git-scm.com/downloads
   - No extra load-test tool needed (the script uses curl)
   - On Windows, run the `.sh` scripts in **Git Bash** or **WSL**.
4. **Configure the CLI:**
   ```bash
   aws configure            # enter the access key, secret, region eu-central-1, output json
   aws sts get-caller-identity   # should print your account ID
   ```

## 2. Deploy

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # optional: adjust values
terraform init        # downloads the AWS and random providers
terraform fmt -check  # code style check
terraform validate    # syntax / reference check
terraform plan -out tfplan    # review: 38 resources to add
terraform apply tfplan
```

The CloudFront distribution takes about **5–10 minutes** to deploy. When it finishes, Terraform prints something like:

```
website_url  = "https://dxxxxxxxxxxxx.cloudfront.net"
whoami_url   = "https://dxxxxxxxxxxxx.cloudfront.net/whoami.html"
alb_dns_name = "hello-web-alb-123456.eu-central-1.elb.amazonaws.com"
...
```

Open `website_url` in the browser to see the Hello World page. Opening `http://<alb_dns_name>` directly **fails to connect** on purpose: the ALB security group only accepts CloudFront's IP ranges. (Requests from CloudFront without the secret header would get a 403 from the listener rule, a second layer.)

## 3. Test the requirements

Run these from the `terraform/` folder.

| Test | Command | Expected result |
|---|---|---|
| Load balancing | open `whoami_url` and reload several times | instance ID and AZ alternate |
| High availability | `./scripts/test_failover.sh` | the site keeps answering HTTP 200 while one instance is terminated; the ASG launches a replacement |
| Autoscaling | `./scripts/load_test.sh 8 30` | desired capacity rises above 2 after a few minutes and falls back later |
| Latency / CDN | `./scripts/check_latency.sh` | `x-cache: Hit from cloudfront`, low time to first byte, `x-amz-cf-pop` shows the edge location |
| Origin protection | `curl -i --max-time 10 http://<alb_dns_name>` | connection timed out / failed to connect (blocked by the security group) |

## 4. Clean up (important, to avoid costs)

```bash
terraform destroy
```

The ALB and EC2 instances are billed per hour, so destroy the stack whenever you are not testing or taking screenshots. You can recreate it at any time with `terraform apply`.

## 5. Optional extensions

- **Remote state.** Create an S3 bucket, e.g. `aws s3 mb s3://<unique-name>-tfstate`, enable versioning, uncomment the `backend "s3"` block in `versions.tf` and run `terraform init -migrate-state`. Terraform ≥ 1.10 locks the state natively in S3 (`use_lockfile`), so the DynamoDB table planned in Phase 1 is no longer needed.
- **Custom domain.** Uncomment the Route 53/ACM block in `cdn.tf`. Note that the certificate must be in `us-east-1`.
- **Shell access.** Set `enable_ssm_endpoints = true` to use SSM Session Manager in the private subnets. This adds small hourly costs.
- **E-mail alarms.** Set `alarm_email` and confirm the subscription e-mail.

## 6. Quality checks performed

- `terraform fmt`: consistent formatting.
- `tflint` with the AWS ruleset: no issues.
- `checkov` security scan: 75 checks passed, 0 failed. 18 checks are skipped deliberately; each skip is justified inline with a `#checkov:skip` comment. Most relate to cost (WAF, access logs, flow logs) or to having no custom domain (no certificate on the ALB).

## Troubleshooting

| Problem | Fix |
|---|---|
| Targets stay *unhealthy* | Wait about 3 minutes after launch. Check *EC2 → Instance → Actions → Monitor → Get system log*, where the user-data output is visible. If `dnf` could not reach the repositories, the script falls back to Python's built-in web server, so the health check still passes. |
| CloudFront shows 403 / 502 | The distribution may still be deploying (wait). Check that the targets are healthy. |
| The load test does not scale out | Increase concurrency (`./scripts/load_test.sh 10 60`). Target tracking reacts after about 3 minutes of sustained load. |
| `terraform destroy` hangs on the ALB/ENIs | Wait a few minutes and run it again. |
