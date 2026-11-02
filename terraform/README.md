# Terraform deployments

One shared foundation plus four independent compute stacks. Each stack is its own root module with its own state, so any of them can be applied or destroyed without touching the others.

```
terraform/
  modules/network        VPC, public/private subnets, NAT, S3 gateway endpoint
  modules/shared_lookup  data-source lookups stacks use to find shared resources
  shared/                VPC, ECR, SSM secret, ACM cert, ALB + listeners
  ecs/                   Fargate Spot service behind the ALB    (ecs.insekure.com)
  lambda/                Container Lambda behind the ALB        (lambda.insekure.com)
  eks/                   EKS + Spot managed node group, ALB     (eks.insekure.com)
  lightsail/             Lightsail container service, own LB    (lightsail.insekure.com)
```

## Architecture

```
                    Internet
                       |
           ALB (public subnets, SG: 80/443)
           80 -> 301 https, 443 routes on Host header
    ecs.insekure.com  lambda.insekure.com  eks.insekure.com
        |              |               |
 Fargate tasks    Lambda (no VPC)   EKS nodes (NodePort 30080)
 (private subnets)                  (private subnets)
        \______________________________/
                       |
     private route table -> NAT (fck-nat t4g.nano or NAT GW)
                        -> S3 gateway endpoint (ECR layers, free)

 Lightsail container service: managed, outside the VPC, pulls from ECR
```

- One ALB is shared by ECS, Lambda and EKS through host-based routing on a single HTTPS listener. `shared` owns the listeners (default: `404 unknown host`); each stack only adds a `host_header` listener rule with its own priority (ECS 100, Lambda 110, EKS 120), so stacks never fight over ownership.
- Workloads run in private subnets with no public IPs. Task/node security groups only accept traffic from the ALB security group; the ALB only egresses to the VPC CIDR.
- TLS terminates at the ALB with `ELBSecurityPolicy-TLS13-1-2-2021-06`; HTTP redirects to HTTPS. One DNS-validated ACM cert covers all `alb_hostnames` (or pass an existing `certificate_arn`). Lightsail can't use ACM, so it gets its own DNS-validated Lightsail certificate for `lightsail.insekure.com`.
- `SECRET_WORD` is stored as an SSM SecureString via a write-only attribute, so `shared` never stores it in state. ECS injects it natively via `secrets`; Lambda, EKS (k8s Secret) and Lightsail read it from SSM at plan time, so it does appear in those stacks' state.
- Images are referenced by digest (`repo@sha256:...`), so pushing a new image and re-applying rolls out the change.

## Cost choices

Approximate us-west-2 monthly cost, idle, low traffic:

| Component | Choice | ~$/month |
|---|---|---|
| ALB | one ALB shared by 3 stacks instead of 3 | 16 + 2 public IPv4 (7) |
| NAT | fck-nat on `t4g.nano` instead of NAT Gateway (`nat_mode = "gateway"` to switch, ~33) | 3 + IPv4 (3.6) |
| ECR layer pulls | S3 gateway endpoint (free) instead of interface endpoints (~$7/each/AZ) | 0 |
| ECS | 1 × Fargate Spot, 0.25 vCPU / 0.5 GB, Container Insights off | ~3 |
| Lambda | scale to zero, ALB health checks off (they'd cost invocations), not in a VPC | ~0 (free tier) |
| EKS | control plane (fixed) + 1 × Spot `t3a/t3.small`, standard support only (avoids extended-support surcharge) | 73 + ~5 + EBS 2 |
| Lightsail | `nano` container service, includes LB + HTTPS | 7 |
| Logs | 7-day retention | ~0 |

EKS is by far the most expensive; destroy it as soon as you've captured proof.

## Prerequisites

- Terraform `1.17.1` (`.tool-versions`), AWS CLI v2, Docker with buildx
- AWS credentials with admin-ish permissions in the target account

The binaries in `bin/` are `x86_64`, so every image is built for `linux/amd64` and every compute target is x86.

## Deploy

State is local by default. For shared use, add an S3 backend block (`use_lockfile = true`) to each root's `versions.tf`.

DNS for `insekure.com` is hosted outside AWS, so certificate validation and app records are created by hand. Both certificates must be issued before they can be attached, so each of those stacks is applied in two steps.

```sh
export AWS_REGION=us-west-2
export TF_VAR_secret_word='<value from the index page>'

cd terraform/shared && terraform init
terraform apply -target=aws_acm_certificate.this
terraform output certificate_validation_records
terraform apply
terraform output alb_dns_records

cd ../.. && ./scripts/push-images.sh

cd terraform/ecs       && terraform init && terraform apply
cd ../lambda           && terraform init && terraform apply
cd ../eks              && terraform init && terraform apply

cd ../lightsail        && terraform init
terraform apply -target=aws_lightsail_certificate.this
terraform output certificate_validation_records
terraform apply
terraform output dns_record
```

1. Create the `certificate_validation_records` CNAMEs at your DNS provider after each targeted apply. The full `shared` apply waits for ACM to issue the cert. For Lightsail, wait until `aws lightsail get-certificates --certificate-name quest` shows `ISSUED` before the full apply.
2. Create `alb_dns_records` (`ecs`, `lambda`, `eks` → ALB) and the Lightsail `dns_record` as CNAMEs.
3. Keep the validation CNAMEs in place so ACM can auto-renew.

Bootstrap: you need the app running before you can read `SECRET_WORD` from `/`. Apply `shared` with any placeholder, deploy one stack, read the word, then re-apply `shared` with the real value and `-var secret_word_version=2`, and re-apply the stacks (ECS: force a new deployment, since SSM `secrets` are read at task start).

Each stack prints its `url`. Check `/`, `/docker`, `/secret_word`, `/loadbalanced`, `/tls`.

## Teardown

Destroy stacks first, `shared` last:

```sh
for s in lightsail eks lambda ecs shared; do (cd terraform/$s && terraform destroy); done
```

`shared` needs `TF_VAR_secret_word` set on destroy too (any value).

## Known gaps

- `/docker` likely fails on Lambda: it's not a Docker runtime, even though it runs an OCI image. It uses the [Lambda Web Adapter](https://github.com/awslabs/aws-lambda-web-adapter) to run the unmodified Express app.
- Single NAT (instance or gateway) in one AZ: a cost-over-HA trade-off. The fck-nat instance isn't in an ASG, so it doesn't self-heal.
- EKS uses a NodePort + ASG-attached target group instead of the AWS Load Balancer Controller. That keeps the shared ALB and skips installing Helm, but traffic can hop between nodes.
- EKS's `kubernetes` provider is configured from a cluster created in the same apply. That works on first create; for cluster replacement, apply in two steps (`-target=aws_eks_node_group.this` first).
- Lightsail deploys by tag (not digest); the digest is passed as an env var, so a new push still triggers a redeploy. `aws_ecr_repository_policy` on the `quest` repo is owned by the Lightsail stack.
- No WAF, ALB access logs, or VPC flow logs (cost).
