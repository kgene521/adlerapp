# Adler CRM — TestFlight Setup Guide (Developer)

## Prerequisites

- Mac with Xcode installed
- Apple Developer Program membership ($99/year) — enroll at https://developer.apple.com/programs/
- Your Adler CRM Xcode project building successfully on a simulator or device

## One-Time Setup

### 1. Create an App ID

1. Go to https://developer.apple.com/account
2. Click **Certificates, Identifiers & Profiles**
3. Click **Identifiers** in the left sidebar
4. Click the **+** button
5. Select **App IDs** → Continue
6. Select **App** → Continue
7. Fill in:
   - Description: `Adler CRM`
   - Bundle ID: Select **Explicit** and enter `com.adlerresources.crm` (must match your Xcode project)
8. Scroll down, check any capabilities your app uses (Push Notifications if you plan to add them later)
9. Click **Continue** → **Register**

### 2. Create the App in App Store Connect

1. Go to https://appstoreconnect.apple.com
2. Click **My Apps**
3. Click the **+** button → **New App**
4. Fill in:
   - Platform: **iOS**
   - Name: `Adler CRM`
   - Primary Language: English (U.S.)
   - Bundle ID: Select `com.adlerresources.crm` (the one you just created)
   - SKU: `adler-crm` (any unique string)
5. Click **Create**

### 3. Configure Xcode Project

1. Open your project in Xcode
2. Click the project name in the navigator (blue icon at top)
3. Select the **AdlerCRM** target
4. Go to the **General** tab:
   - Bundle Identifier: `com.adlerresources.crm`
   - Version: `1.0.0`
   - Build: `1` (increment this each time you upload)
5. Go to the **Signing & Capabilities** tab:
   - Check **Automatically manage signing**
   - Team: Select your Apple Developer team
   - If no team appears, go to Xcode → Settings → Accounts → add your Apple ID

## Uploading a Build

Do this every time you want to send an update to your testers.

### Step 1: Set the Build Number

Each upload needs a unique build number. In Xcode:

1. Click project → target **AdlerCRM** → **General** tab
2. Increment the **Build** number (e.g., 1 → 2 → 3)
3. The **Version** stays the same unless you're releasing a new version (e.g., 1.0.0 → 1.1.0)

### Step 2: Archive

1. In the top toolbar, set the device to **Any iOS Device (arm64)** — not a simulator
2. Go to **Product** → **Archive**
3. Wait for the build to complete (may take a few minutes)
4. The **Organizer** window opens automatically when done

### Step 3: Upload

1. In the Organizer, select your latest archive
2. Click **Distribute App**
3. Select **TestFlight & App Store** → Next
4. Select **Upload** → Next
5. Leave all options at their defaults (Manage Version and Build Number, Upload Symbols)
6. Click **Next** → review the summary → click **Upload**
7. Wait for the upload to complete (a few minutes depending on your internet)

### Step 4: Wait for Processing

1. Go to https://appstoreconnect.apple.com → My Apps → Adler CRM
2. Click **TestFlight** tab
3. Your new build will show **Processing** — this takes 5–30 minutes
4. Once it shows a green **Ready to Test**, you can proceed

## Adding Testers

### Internal Testers (Recommended for Employees)

Internal testers are people with access to your App Store Connect account. Limit: 100 testers.

1. In App Store Connect, go to **Users and Access**
2. Click **+** to add a user
3. Fill in their name and email (this is the email they use with their Apple ID)
4. Role: Select **App Manager** or **Developer** or **Marketing** (any role works for testing)
5. Click **Invite**
6. Go back to your app → **TestFlight** tab
7. Under **Internal Testing**, click **+** next to **App Store Connect Users**
8. Check the boxes next to the people you want as testers
9. Click **Add**

They'll receive an email invitation immediately.

### External Testers (Alternative — No App Store Connect Account Needed)

Use this if you don't want to create App Store Connect accounts for employees.

1. In your app's **TestFlight** tab, click **+** next to **External Testing** to create a group
2. Name it (e.g., "Adler Team")
3. Click the group → **+** next to Testers
4. Add testers by email address
5. Click the **Builds** tab within the group → click **+** → select your build
6. First time only: Apple does a brief review (usually 24–48 hours)
7. After approval, testers get an email invitation

## Sending Updates

When you make changes to the app:

1. Increment the Build number in Xcode
2. Product → Archive
3. Distribute App → Upload
4. Wait for processing in App Store Connect
5. Internal testers are notified automatically
6. External testers: you may need to add the new build to their group

## Troubleshooting

**"No accounts with App Store Connect access" error**
→ Make sure your Apple ID is enrolled in the Apple Developer Program, not just a free account

**Archive option is grayed out**
→ Make sure the device selector says "Any iOS Device" — you cannot archive when a simulator is selected

**Upload fails with signing error**
→ Go to Signing & Capabilities, uncheck and recheck "Automatically manage signing", make sure the correct team is selected

**Build stuck on "Processing"**
→ Usually resolves within 30 minutes. If longer than an hour, try uploading again with an incremented build number

**"Missing Compliance" warning in TestFlight**
→ Click Manage next to the build, answer the encryption question: if you only use HTTPS (which you do), select "Yes" → uses exempt encryption → provide the exemption (select "Qualifies for the exemption provided in Category 5, Part 2") → Save
