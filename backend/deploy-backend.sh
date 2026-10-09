#!/usr/bin/env bash
set -euo pipefail

echo "==> Starting Backend Deployment to AWS ECS"

# 1. Check variables
REQUIRED_VARS=("TASK_NAME_BE" "CLUSTER_NAME" "SERVICE_NAME_BE" "IMAGE_NAME_BE" "AWS_REGION")
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "[-] Error: Environment variable $var is required but not set." >&2
    exit 1
  fi
done

echo "[+] Region:               $AWS_REGION"
echo "[+] Cluster Name:         $CLUSTER_NAME"
echo "[+] Service Name:         $SERVICE_NAME_BE"
echo "[+] Task Definition Name: $TASK_NAME_BE"
echo "[+] New Image URI:        $IMAGE_NAME_BE"

# 2. Get active task definition
echo "[+] Fetching current active task definition: $TASK_NAME_BE..."
CURRENT_TASK_DEF=$(aws ecs describe-task-definition \
  --task-definition "$TASK_NAME_BE" \
  --region "$AWS_REGION")

# 3. Create updated task definition JSON
NEW_CONTAINER_DEFS=$(echo "$CURRENT_TASK_DEF" | jq --arg IMAGE "$IMAGE_NAME_BE" \
  '.taskDefinition.containerDefinitions[0].image = $IMAGE | .taskDefinition.containerDefinitions')

NEW_TASK_DEF=$(echo "$CURRENT_TASK_DEF" | jq \
  --argjson CONTAINER_DEFS "$NEW_CONTAINER_DEFS" \
  '.taskDefinition 
   | .containerDefinitions = $CONTAINER_DEFS 
   | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy, .deregisteredAt)')

# 4. Register new task definition revision
echo "[+] Registering new task definition revision..."
NEW_REVISION_ARN=$(aws ecs register-task-definition \
  --region "$AWS_REGION" \
  --cli-input-json "$NEW_TASK_DEF" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "[+] Successfully registered new revision: $NEW_REVISION_ARN"

# 5. Update ECS service
echo "[+] Updating ECS service $SERVICE_NAME_BE..."
aws ecs update-service \
  --cluster "$CLUSTER_NAME" \
  --service "$SERVICE_NAME_BE" \
  --task-definition "$NEW_REVISION_ARN" \
  --force-new-deployment \
  --region "$AWS_REGION" > /dev/null

echo "[+] Waiting for service to reach steady state..."
aws ecs wait services-stable \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME_BE" \
  --region "$AWS_REGION"

echo "[✓] Backend deployment completed successfully"