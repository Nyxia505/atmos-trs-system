# Deploy trip planner API to Google Cloud Run (same GCP project as Firebase).
# Prerequisites: gcloud CLI, billing enabled, APIs enabled (Run, Artifact Registry, Cloud Build).
#
# Usage (from trip_planner_api folder):
#   .\deploy_cloud_run.ps1
# Then paste the printed URL into main/lib/config.dart → tripPlannerApiProductionUrl

$PROJECT_ID = "atmos-trs-system"
$SERVICE = "trip-planner-api"
$REGION = "asia-southeast1"

gcloud config set project $PROJECT_ID

gcloud run deploy $SERVICE `
  --source . `
  --region $REGION `
  --platform managed `
  --allow-unauthenticated `
  --memory 512Mi `
  --min-instances 0 `
  --max-instances 10

Write-Host ""
Write-Host "Copy the Service URL above into:"
Write-Host "  main/lib/config.dart -> tripPlannerApiProductionUrl"
Write-Host ""
Write-Host "Test: curl https://YOUR-URL/health"
