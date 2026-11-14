#!/usr/bin/env bash
# cleanup-dev-orphans.sh
#
# Deletes the leftover "fi-project-dev-*" AWS resources that Terraform lost track of
# (that is what causes the "already exists" errors in the GitHub Actions deploy).
# After it finishes, the pipeline can create everything again from scratch.
#
# How to run (in a terminal where the AWS CLI is already logged in to the right account):
#     bash cleanup-dev-orphans.sh
# Mac / Linux: any terminal.  Windows: Git Bash or WSL (not plain PowerShell / cmd).
# If you use a named AWS profile:   AWS_PROFILE=my-profile bash cleanup-dev-orphans.sh
# The script first shows what it found and asks you to type "yes" before it deletes anything.
# It only touches names that start with "fi-project-dev" and never touches prod.

export AWS_PAGER=""
export AWS_DEFAULT_REGION="eu-north-1"
# Git Bash on Windows rewrites arguments that start with "/" (like /ecs/...) into Windows paths.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

if ! command -v aws >/dev/null 2>&1; then
  echo "The AWS CLI ('aws') was not found in this terminal."
  exit 1
fi
P="fi-project-dev"
KEEP_VPC="vpc-0d6317276aa477746"   # the NEW vpc that Terraform already tracks: never deleted
EXPECTED_ACCOUNT="624606539627"

say() { printf '\n=== %s ===\n' "$*"; }

# get: run an aws command and print its output; print nothing if the resource does not exist
get() {
  local out
  out=$("$@" 2>/dev/null) || return 0
  out=${out//$'\r'/}          # aws.exe on Windows adds a hidden \r at the end of each line
  [ "$out" = "None" ] && out=""
  printf '%s' "$out"
}

# retry: AWS often needs a minute before a dependency is released, so try up to 30 times
retry() {
  local i out
  for i in $(seq 1 30); do
    if out=$("$@" 2>&1); then return 0; fi
    sleep 10
  done
  echo "   FAILED: $*"
  echo "   $out"
  return 1
}

# ---------------------------------------------------------------- safety checks
ACCOUNT=$(get aws sts get-caller-identity --query Account --output text)
if [ -z "$ACCOUNT" ]; then
  echo "The AWS CLI is not logged in. Check it with:  aws sts get-caller-identity"
  exit 1
fi
if [ "$ACCOUNT" != "$EXPECTED_ACCOUNT" ]; then
  echo "Wrong AWS account ($ACCOUNT). Expected $EXPECTED_ACCOUNT. Nothing was changed."
  exit 1
fi

# ---------------------------------------------------------------- what exists now
SERVICES=$(get aws ecs list-services --cluster "$P-cluster" --query 'serviceArns[]' --output text)
ALB=$(get aws elbv2 describe-load-balancers --names "$P-alb" --query 'LoadBalancers[0].LoadBalancerArn' --output text)
ALB_VPC=$(get aws elbv2 describe-load-balancers --names "$P-alb" --query 'LoadBalancers[0].VpcId' --output text)
TG_VOTE=$(get aws elbv2 describe-target-groups --names "$P-vote" --query 'TargetGroups[0].TargetGroupArn' --output text)
TG_RESULT=$(get aws elbv2 describe-target-groups --names "$P-result" --query 'TargetGroups[0].TargetGroupArn' --output text)
RDS=$(get aws rds describe-db-instances --db-instance-identifier "$P-db" --query 'DBInstances[0].DBInstanceIdentifier' --output text)
RDS_VPC=$(get aws rds describe-db-instances --db-instance-identifier "$P-db" --query 'DBInstances[0].DBSubnetGroup.VpcId' --output text)
REDIS=$(get aws elasticache describe-cache-clusters --cache-cluster-id "$P-redis" --query 'CacheClusters[0].CacheClusterId' --output text)
DB_SG=$(get aws rds describe-db-subnet-groups --db-subnet-group-name "$P-db-subnets" --query 'DBSubnetGroups[0].DBSubnetGroupName' --output text)
REDIS_SG=$(get aws elasticache describe-cache-subnet-groups --cache-subnet-group-name "$P-redis-subnets" --query 'CacheSubnetGroups[0].CacheSubnetGroupName' --output text)
SECRET=$(get aws secretsmanager describe-secret --secret-id "$P-db-password" --query Name --output text)
ROLE=$(get aws iam get-role --role-name "$P-exec" --query Role.RoleName --output text)
LOGS=$(get aws logs describe-log-groups --log-group-name-prefix "/ecs/$P-" --query 'logGroups[].logGroupName' --output text)

ALL_VPCS=$(get aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$P-vpc" --query 'Vpcs[].VpcId' --output text)
OLD_VPCS=""
for v in $ALL_VPCS; do
  if [ "$v" != "$KEEP_VPC" ]; then OLD_VPCS="$OLD_VPCS $v"; fi
done
OLD_VPCS=$(echo $OLD_VPCS)

# If the load balancer or database already live in the NEW vpc, dev was created successfully
# and deleting anything would be a mistake.
if [ "$ALB_VPC" = "$KEEP_VPC" ] || [ "$RDS_VPC" = "$KEEP_VPC" ]; then
  echo "Dev already seems to be deployed in $KEEP_VPC. Nothing was changed."
  exit 1
fi

show() { printf '  %-22s %s\n' "$1" "${2:--}"; }
say "Found in AWS (these will be deleted)"
show "ECS services"        "$SERVICES"
show "Load balancer"       "$ALB"
show "Target group vote"   "$TG_VOTE"
show "Target group result" "$TG_RESULT"
show "RDS database"        "$RDS"
show "Redis cluster"       "$REDIS"
show "DB subnet group"     "$DB_SG"
show "Redis subnet group"  "$REDIS_SG"
show "Secret"              "$SECRET"
show "IAM role"            "$ROLE"
show "Log groups"          "$LOGS"
show "Old VPC(s)"          "$OLD_VPCS"
echo
echo "  Kept (not deleted): the new VPC $KEEP_VPC, the ECS cluster, the SNS topic, prod, ECR, the S3 state bucket."

if [ -z "$SERVICES$ALB$TG_VOTE$TG_RESULT$RDS$REDIS$DB_SG$REDIS_SG$SECRET$ROLE$LOGS$OLD_VPCS" ]; then
  echo
  echo "Nothing to delete. You can re-run the GitHub Actions workflow."
  exit 0
fi

echo
read -r -p 'Type "yes" to delete everything listed above: ' ANSWER
if [ "$ANSWER" != "yes" ]; then
  echo "Cancelled. Nothing was changed."
  exit 0
fi

# ---------------------------------------------------------------- delete, in a safe order
if [ -n "$SERVICES" ]; then
  say "ECS services"
  for s in $SERVICES; do
    aws ecs delete-service --cluster "$P-cluster" --service "$s" --force >/dev/null 2>&1 && echo "   deleted $s"
  done
  aws ecs wait services-inactive --cluster "$P-cluster" --services $SERVICES 2>/dev/null
fi

if [ -n "$ALB" ]; then
  say "Load balancer"
  for l in $(get aws elbv2 describe-listeners --load-balancer-arn "$ALB" --query 'Listeners[].ListenerArn' --output text); do
    aws elbv2 delete-listener --listener-arn "$l" >/dev/null 2>&1
  done
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB" && echo "   deleting, waiting..."
  aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB"
fi

for tg in $TG_VOTE $TG_RESULT; do
  say "Target group $tg"
  retry aws elbv2 delete-target-group --target-group-arn "$tg" && echo "   deleted"
done

if [ -n "$RDS" ]; then
  say "RDS database (takes a few minutes)"
  aws rds wait db-instance-available --db-instance-identifier "$RDS" 2>/dev/null
  retry aws rds delete-db-instance --db-instance-identifier "$RDS" --skip-final-snapshot --delete-automated-backups
  aws rds wait db-instance-deleted --db-instance-identifier "$RDS" && echo "   deleted"
fi

if [ -n "$REDIS" ]; then
  say "Redis cluster (takes a few minutes)"
  aws elasticache wait cache-cluster-available --cache-cluster-id "$REDIS" 2>/dev/null
  retry aws elasticache delete-cache-cluster --cache-cluster-id "$REDIS"
  aws elasticache wait cache-cluster-deleted --cache-cluster-id "$REDIS" && echo "   deleted"
fi

if [ -n "$DB_SG" ]; then
  say "DB subnet group"
  retry aws rds delete-db-subnet-group --db-subnet-group-name "$DB_SG" && echo "   deleted"
fi

if [ -n "$REDIS_SG" ]; then
  say "Redis subnet group"
  retry aws elasticache delete-cache-subnet-group --cache-subnet-group-name "$REDIS_SG" && echo "   deleted"
fi

if [ -n "$SECRET" ]; then
  say "Secret"
  aws secretsmanager delete-secret --secret-id "$SECRET" --force-delete-without-recovery >/dev/null && echo "   deleted"
fi

if [ -n "$ROLE" ]; then
  say "IAM role"
  for a in $(get aws iam list-attached-role-policies --role-name "$ROLE" --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$a"
  done
  for n in $(get aws iam list-role-policies --role-name "$ROLE" --query 'PolicyNames[]' --output text); do
    aws iam delete-role-policy --role-name "$ROLE" --policy-name "$n"
  done
  retry aws iam delete-role --role-name "$ROLE" && echo "   deleted"
fi

if [ -n "$LOGS" ]; then
  say "Log groups"
  for g in $LOGS; do
    aws logs delete-log-group --log-group-name "$g" && echo "   deleted $g"
  done
fi

delete_vpc() {
  local v="$1" sg s rt a igw perms
  say "Old VPC $v"

  # Security groups reference each other, so remove their rules first, then delete them.
  local sgs
  sgs=$(get aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$v" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
  for sg in $sgs; do
    perms=$(get aws ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].IpPermissions' --output json)
    if [ -n "$perms" ] && [ "$perms" != "[]" ]; then
      aws ec2 revoke-security-group-ingress --group-id "$sg" --ip-permissions "$perms" >/dev/null 2>&1
    fi
  done
  for sg in $sgs; do retry aws ec2 delete-security-group --group-id "$sg"; done

  for s in $(get aws ec2 describe-subnets --filters "Name=vpc-id,Values=$v" --query 'Subnets[].SubnetId' --output text); do
    retry aws ec2 delete-subnet --subnet-id "$s"
  done

  for rt in $(get aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$v" --query 'RouteTables[?length(Associations[?Main==`true`])==`0`].RouteTableId' --output text); do
    for a in $(get aws ec2 describe-route-tables --route-table-ids "$rt" --query 'RouteTables[0].Associations[].RouteTableAssociationId' --output text); do
      aws ec2 disassociate-route-table --association-id "$a" >/dev/null 2>&1
    done
    retry aws ec2 delete-route-table --route-table-id "$rt"
  done

  for igw in $(get aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$v" --query 'InternetGateways[].InternetGatewayId' --output text); do
    aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$v" >/dev/null 2>&1
    retry aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
  done

  retry aws ec2 delete-vpc --vpc-id "$v" && echo "   deleted $v"
}

for v in $OLD_VPCS; do
  if [ "$v" != "$KEEP_VPC" ]; then delete_vpc "$v"; fi
done

say "Done"
echo "Now go to GitHub -> Actions -> open the failed run -> 'Re-run failed jobs'."
echo "The deploy takes about 15-20 minutes (RDS and ECS are slow)."
