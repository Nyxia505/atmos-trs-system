# Deploy Firestore rules, Storage rules, and role-claim Functions (long-term admin access).
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)
firebase deploy --only firestore:rules,storage,functions:syncUserRoleClaims,functions:refreshRoleClaims --project atmos-trs-system
