# Firestore `admin_accounts`

Collection for registered admin logins. Sign-in still uses **Firebase Authentication**; this collection lists who is an admin.

## Document ID

From email: `optaca@gmail.com` → `optaca_at_gmail_com`

## Example document (`optaca_at_gmail_com`)

| Field | Type | Example |
|-------|------|---------|
| email | string | OPTACA@gmail.com |
| emailLower | string | optaca@gmail.com |
| password | string | admin123 |
| role | string | admin |
| active | boolean | true |
| displayName | string | Provincial Admin |
| firebaseUid | string | (Auth uid after first login) |
| createdAt | timestamp | |
| updatedAt | timestamp | |

## Create from the app

1. Sign in as admin (OPTACA@gmail.com / admin123), or  
2. Admin dashboard sidebar → **Sync admin accounts**

## Create in Firebase Console

1. Firestore → **Start collection** → `admin_accounts`
2. Document ID: `optaca_at_gmail_com`
3. Add fields from the table above
