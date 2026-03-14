# Boomi SRE App — Phase 11: AWS Infrastructure Health Dashboard

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first to understand the current codebase:**
- `BoomiSRE/Sources/Views/Panels/CostExplorerView.swift` — existing AWS cost dashboard
- `BoomiSRE/Sources/ViewModels/CostExplorerViewModel.swift` — cost view model
- `BoomiSRE/Sources/Services/AWSCostService.swift` — AWS CLI wrapper for cost queries
- `BoomiSRE/Sources/Services/AWSAuthService.swift` — AWS CLI wrapper for auth + profile management
- `BoomiSRE/Sources/Models/AppState.swift` — global state (awsSSOProfile, favoriteAWSProfiles, awsAccountNames)
- `BoomiSRE/Sources/Models/ReportItem.swift` — ReportCatalog (currently only has `aws_cost_explorer` in the AWS section)
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar (AWS section currently has one item)
- `BoomiSRE/Sources/Views/ContentView.swift` — detail pane routing
- `BoomiSRE/Sources/Views/SettingsView.swift` — AWS settings tab

**Key constraints (same as all prior phases):**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.
- All HTTP via native URLSession. No Alamofire or similar.
- All AWS API calls go through the `aws` CLI (not boto3) since this is a Swift app. Use `Process` to run `aws` commands, just like the existing `AWSCostService` and `AWSAuthService` do.
- AWS CLI must use absolute path from `AWSAuthService.resolvedAWSPath` (PATH stripped in .app bundle).
- Always augment PATH with `/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin` in Process.environment.
- Read stdout/stderr pipes BEFORE calling `waitUntilExit()` to avoid deadlock on large responses.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600). Config in `~/.boomi_sre_config.json`.
- Claude API: `claude-sonnet-4-6` model via Anthropic Messages API v1.

**Infrastructure context — what this SRE team manages:**
- 7+ AWS accounts: Production (809167139867), Staging (566161767908), QA (680833432085), Marketing (692192551700), plus EU and other accounts
- Multi-region: us-east-1, eu-west-1, us-west-2, ap-southeast-1/2, eu-central-1
- Core services: EC2 instances in Auto Scaling Groups behind Application Load Balancers, Aurora RDS databases, Lambda functions, S3 buckets, CloudWatch monitoring, WAF/Shield DDoS protection
- Multi-tenant SaaS platform (Mashery API gateway) with 100+ customer tenants across shared ALBs/ASGs
- Profiles are configured in `~/.aws/config` (SSO) and `~/.aws/credentials` (portal creds)

---

## Design Philosophy

This AWS section is being built for SRE engineers of ALL experience levels:

- **Junior SREs** need clear, color-coded health indicators. Green = good, yellow = warning, red = bad. They shouldn't need to know AWS CLI commands or CloudWatch metric names to see that something is unhealthy.
- **Mid-level SREs** need drill-down capability. Click an unhealthy resource to see metrics, recent events, and suggested actions.
- **Senior SREs** need the raw data and AI analysis. Show them the actual CloudWatch metrics, let them query across accounts, and give them AI-powered anomaly detection.

The goal: **any SRE should be able to open this tool, pick an account, and within 5 seconds know if anything needs attention.**

---

## Implementation Plan

Work through these phases in order. Each phase should compile and run before moving to the next. After each phase, run `swift build` to verify. Commit after each phase.

---

### Phase 11A: AWS Infrastructure Service — Core CLI Wrapper

**Goal:** Create a new service that wraps AWS CLI commands for infrastructure health queries.

**Create `BoomiSRE/Sources/Services/AWSInfraService.swift`:**

This is an `actor` (like the existing AWSCostService) that runs AWS CLI commands and parses JSON output. Every method takes a `profile: String` parameter.

**Methods to implement:**

#### 1. EC2 Instances
```swift
func describeInstances(profile: String, region: String? = nil) async throws -> [EC2Instance]
```
- Command: `aws ec2 describe-instances --profile {profile} --output json --query 'Reservations[].Instances[]'`
- If region is specified: add `--region {region}`
- Parse into `EC2Instance` model: instanceId, instanceType, state (running/stopped/terminated), name (from Name tag), launchTime, privateIpAddress, publicIpAddress, availabilityZone, platform (Linux/Windows), vpcId, subnetId
- Filter out terminated instances by default

#### 2. Auto Scaling Groups
```swift
func describeAutoScalingGroups(profile: String, region: String? = nil) async throws -> [ASGInfo]
```
- Command: `aws autoscaling describe-auto-scaling-groups --profile {profile} --output json`
- Parse into `ASGInfo` model: name, minSize, maxSize, desiredCapacity, instances (count + health status), launchTemplate/launchConfig name, targetGroupARNs, status, createdTime
- Health: unhealthy if any instance is `Unhealthy` or if running count < desired

#### 3. Application Load Balancers + Target Group Health
```swift
func describeLoadBalancers(profile: String, region: String? = nil) async throws -> [ALBInfo]
func describeTargetHealth(profile: String, targetGroupArn: String, region: String? = nil) async throws -> [TargetHealthInfo]
```
- ALB command: `aws elbv2 describe-load-balancers --profile {profile} --output json`
- Target groups: `aws elbv2 describe-target-groups --profile {profile} --load-balancer-arn {arn} --output json`
- Target health: `aws elbv2 describe-target-health --profile {profile} --target-group-arn {arn} --output json`
- `ALBInfo` model: name, dnsName, state (active/provisioning/failed), type, scheme (internet-facing/internal), availabilityZones, targetGroupCount, createdTime
- `TargetHealthInfo` model: targetId, port, healthState (healthy/unhealthy/draining/unused), reason, description

#### 4. RDS/Aurora Instances
```swift
func describeDBInstances(profile: String, region: String? = nil) async throws -> [RDSInstance]
func describeDBClusters(profile: String, region: String? = nil) async throws -> [AuroraCluster]
```
- DB instances: `aws rds describe-db-instances --profile {profile} --output json`
- DB clusters: `aws rds describe-db-clusters --profile {profile} --output json`
- `RDSInstance` model: identifier, engine (aurora-mysql, postgres, etc.), engineVersion, instanceClass, status (available/backing-up/maintenance/etc.), multiAZ, storageType, allocatedStorage, endpoint, availabilityZone, clusterIdentifier
- `AuroraCluster` model: identifier, engine, engineVersion, status, members (count + roles: writer/reader), endpoint, readerEndpoint, storageEncrypted, backupRetentionPeriod, latestRestorableTime

#### 5. CloudWatch Alarms
```swift
func describeAlarms(profile: String, region: String? = nil, stateValue: String? = nil) async throws -> [CloudWatchAlarm]
```
- Command: `aws cloudwatch describe-alarms --profile {profile} --output json`
- If stateValue specified (e.g., "ALARM"): add `--state-value {stateValue}`
- `CloudWatchAlarm` model: alarmName, namespace, metricName, stateValue (OK/ALARM/INSUFFICIENT_DATA), stateReason, stateUpdatedTimestamp, dimensions (array of name:value), threshold, comparisonOperator, evaluationPeriods, period, statistic, actionsEnabled, alarmActions

#### 6. Lambda Functions
```swift
func listFunctions(profile: String, region: String? = nil) async throws -> [LambdaFunction]
```
- Command: `aws lambda list-functions --profile {profile} --output json`
- `LambdaFunction` model: functionName, runtime, handler, codeSize, memorySize, timeout, lastModified, state (Active/Inactive/Failed), description

#### 7. Lambda Recent Errors (CloudWatch Metrics)
```swift
func getLambdaErrors(profile: String, functionName: String, region: String? = nil) async throws -> [MetricDataPoint]
```
- Command: `aws cloudwatch get-metric-statistics --profile {profile} --namespace AWS/Lambda --metric-name Errors --dimensions Name=FunctionName,Value={functionName} --start-time {24h ago ISO} --end-time {now ISO} --period 3600 --statistics Sum --output json`
- `MetricDataPoint` model: timestamp, sum, unit

#### 8. Recent CloudTrail Events
```swift
func lookupEvents(profile: String, region: String? = nil, maxResults: Int = 25) async throws -> [CloudTrailEvent]
```
- Command: `aws cloudtrail lookup-events --profile {profile} --max-results {maxResults} --output json`
- `CloudTrailEvent` model: eventId, eventName, eventSource, eventTime, username, sourceIPAddress, resources (array of type+name)
- These show recent API calls — deployments, config changes, security events

#### 9. S3 Bucket List (lightweight)
```swift
func listBuckets(profile: String) async throws -> [S3Bucket]
```
- Command: `aws s3api list-buckets --profile {profile} --output json`
- `S3Bucket` model: name, creationDate

**Important implementation notes:**
- Every CLI call should have a 30-second timeout.
- Every CLI call should handle `ExpiredTokenException` and return a clear error that the UI can show as "Session expired — re-login required".
- Parse errors gracefully — if a field is missing from the JSON, use sensible defaults rather than crashing.
- All models should be `Sendable` and `Identifiable`.

---

### Phase 11B: AWS Health Overview — The "Account at a Glance" View

**Goal:** Create a new view that shows the health of an entire AWS account in a single scrollable dashboard.

**Create `BoomiSRE/Sources/Views/Panels/AWSHealthView.swift` and `BoomiSRE/Sources/ViewModels/AWSHealthViewModel.swift`:**

**Account Picker (top bar):**
- Horizontal row of account buttons showing the user's `favoriteAWSProfiles` (from AppState).
- Each button shows: friendly account name (from `awsAccountNames` cache) + colored dot (green if authenticated, grey if unknown).
- Clicking an account button selects it and refreshes all data.
- If no favorites are set, show all available profiles from `~/.aws/config`.
- A "Manage Accounts" link that opens Settings → AWS tab.
- The currently selected account is highlighted with accent color.

**Region Filter:**
- Below the account picker, a horizontal row of region chips: "All Regions", "us-east-1", "eu-west-1", "us-west-2", etc.
- Default to "All Regions". Selecting a region filters all data below.
- Only show regions that actually have resources (determine from the fetched data).

**Health Summary Cards (top row):**
A horizontal row of 6 summary cards, each showing a count and health status:

1. **EC2 Instances**: "23 running, 2 stopped" — green if all running instances are healthy, yellow if any stopped, red if any impaired
2. **Auto Scaling**: "5 ASGs, all healthy" — green if all ASGs have desired=running count, red if any have running < desired
3. **Load Balancers**: "8 ALBs, 1 unhealthy target" — green if all target groups healthy, red if any targets unhealthy
4. **Databases**: "3 Aurora clusters, all available" — green if status=available, yellow if maintenance/backup, red if any other status
5. **CloudWatch Alarms**: "2 in ALARM" — green if 0 alarms firing, red if any ALARM, yellow if INSUFFICIENT_DATA
6. **Lambda Functions**: "12 functions, 0 errors (24h)" — green if no errors in last 24h, yellow if <10 errors, red if >10 errors

Each card:
- Shows an SF Symbol icon, the resource type name, a count, and a one-line status
- Background color tint: green (healthy), yellow (warning), red (critical), grey (loading/unknown)
- Clickable — scrolls down to the detailed section for that resource type

**Detailed Sections (scrollable body):**
Below the summary cards, show expandable sections for each resource type. Each section has a header with the resource type name, count, and a collapse/expand toggle. Sections with issues should be expanded by default; healthy sections collapsed.

#### EC2 Instances Section:
- Table with columns: Name, Instance ID, Type, State, AZ, Private IP, Launch Time
- State column is color-coded: green "running", yellow "stopped", red "terminated/impaired"
- Sortable by any column (click header to sort)
- Search/filter field to find instances by name or ID
- Click an instance to expand and show:
  - All instance details
  - "Open in AWS Console" link (construct URL: `https://{region}.console.aws.amazon.com/ec2/home?region={region}#InstanceDetails:instanceId={id}`)

#### Auto Scaling Groups Section:
- Table: Name, Desired/Min/Max, Running Count, Health, Target Groups
- Health column: green checkmark if running==desired, red warning if running<desired
- Running count shown as "3/3" (running/desired) format
- Click to expand: instance list, recent scaling activities, target group health

#### Load Balancers Section:
- Table: Name, Scheme, State, Target Groups, Healthy/Total Targets
- Healthy/Total shown as fraction with color: "48/48" (green) or "45/48" (red)
- Click to expand: target group list, each with target health breakdown
- Unhealthy targets highlighted in red with the health check failure reason

#### Databases Section:
- Table: Cluster/Instance ID, Engine, Status, Instance Class, Multi-AZ, Storage
- Status color-coded: green "available", yellow "backing-up"/"modifying", red anything else
- Click to expand: endpoint, reader endpoint, backup retention, latest restorable time, storage encrypted badge

#### CloudWatch Alarms Section:
- Grouped by state: ALARM (red, always expanded), INSUFFICIENT_DATA (yellow), OK (green, collapsed by default)
- Each alarm shows: name, metric, current state, state reason (truncated), last updated
- Click to expand: full state reason, threshold, comparison, evaluation periods, dimensions, actions
- "Acknowledge" context menu item (placeholder for future functionality)

#### Lambda Functions Section:
- Table: Function Name, Runtime, Memory, Timeout, Last Modified, Errors (24h)
- Errors column: green "0", yellow "1-9", red "10+"
- Click to expand: description, handler, code size, state, error count chart (hourly bars for last 24h using Swift Charts)

#### Recent Activity Section:
- Timeline of last 25 CloudTrail events
- Each event shows: time (relative), event name, service, username, resources affected
- Color-coded by event type: red for destructive (Delete*, Terminate*), yellow for modifications (Update*, Modify*, Put*), blue for reads
- Helps junior SREs understand "what just happened" and senior SREs track deployment activity

**AI Analysis Button:**
- A floating "Analyze Infrastructure" button at the top right
- Sends all collected health data to Claude and asks for:
  - **Health Assessment**: Overall account health rating (Healthy/Warning/Critical) with reasons
  - **Issues Found**: Specific problems that need attention (unhealthy targets, alarms firing, ASG capacity mismatches)
  - **Recommendations**: Optimization and reliability suggestions
  - **Risk Assessment**: Potential issues that aren't yet problems (single-AZ databases, no alarms on critical resources, etc.)
- The analysis appears in a slide-out panel on the right

**Loading UX:**
- Show skeleton loading cards while data fetches
- Each section loads independently and in parallel (use `TaskGroup`)
- Show a progress indicator: "Loading EC2... Loading ALBs..." with checkmarks as each completes
- If a section fails (e.g., insufficient permissions), show an inline error with the specific AWS error message — don't block other sections

---

### Phase 11C: Register New AWS Views in Sidebar & Routing

**Goal:** Add the new AWS Health view to the sidebar and content routing.

**Changes to `ReportItem.swift`:**
Add a new report item to the AWS section:
```swift
ReportItem(id: "aws_health", title: "Infrastructure Health",
           description: "EC2, ALB, RDS, Lambda, CloudWatch — account health at a glance",
           section: .aws, scriptName: "", csvKeys: [], chartType: .table, icon: "heart.text.square")
```
Place it BEFORE `aws_cost_explorer` in the catalog so it appears first in the sidebar (infrastructure health is more urgent than costs).

**Changes to `ContentView.swift`:**
Add routing for the new view:
```swift
case "aws_health":
    AWSHealthView()
```

**Changes to sidebar:**
The AWS section will now show 2 items:
1. Infrastructure Health (new)
2. Cost Explorer (existing)

---

### Phase 11D: Cross-Account Health Summary

**Goal:** For senior SREs managing multiple accounts, provide a way to see health across ALL favorite accounts simultaneously.

**Implementation:**

Add a "Cross-Account" toggle at the top of `AWSHealthView`. When enabled:

1. Fetch health data from ALL accounts in `favoriteAWSProfiles` in parallel.
2. Replace the detailed per-account view with a **cross-account summary table**:
   - Rows: one per account (friendly name + account ID)
   - Columns: EC2 (count + health), ASG (count + health), ALB (count + health), RDS (count + health), Alarms (count firing), Lambda Errors (24h)
   - Each cell is color-coded: green/yellow/red
   - Click a cell to drill into that account + resource type (switches to single-account view with that account selected and scrolls to that section)

3. Show a "worst first" sorting — accounts with issues sort to the top.

4. Show an aggregate summary line at the top: "Across 5 accounts: 2 alarms firing, 1 unhealthy ALB target, all databases healthy"

**Important:** Cross-account fetching makes many CLI calls in parallel. Limit concurrent calls to 3 accounts at a time to avoid rate limiting. Show progress: "Checking account 2 of 5..."

---

### Phase 11E: AWS Resource Detail Views

**Goal:** When clicking on a specific resource (EC2 instance, ALB, RDS cluster, etc.) in the health view, show a rich detail panel rather than just expanding a table row.

**Implementation:**

Create `BoomiSRE/Sources/Views/Panels/AWSResourceDetailView.swift`:

This is a reusable view that accepts a resource type + identifier and shows detailed information. It appears as a slide-over panel from the right (or replaces the right portion of the view in an HSplitView).

**For EC2 instances — fetch additional data:**
- `aws ec2 describe-instance-status --instance-ids {id}` → system/instance status checks
- Recent CloudWatch metrics (CPUUtilization, NetworkIn/Out, StatusCheckFailed) for the last 6 hours
- Show metrics as small sparkline charts (Swift Charts)
- Actions section: "Open in Console" link, "Copy Instance ID" button

**For ALBs — fetch additional data:**
- Target group health (already fetched)
- CloudWatch metrics: RequestCount, HTTPCode_Target_5XX_Count, TargetResponseTime for last 6 hours
- Show metrics as sparklines
- List all target groups with their health breakdown

**For RDS/Aurora — fetch additional data:**
- `aws cloudwatch get-metric-statistics` for: CPUUtilization, FreeableMemory, ReadIOPS, WriteIOPS, DatabaseConnections for last 6 hours
- Show as sparkline charts
- Show endpoint (copyable), reader endpoint, engine version, backup window

**For Lambda — fetch additional data:**
- Invocations, Errors, Duration, Throttles metrics for last 24h
- Show as sparkline charts
- Show function configuration: runtime, memory, timeout, handler, environment variable count (not values)

**For CloudWatch Alarms — show:**
- Full alarm configuration (metric, threshold, period, evaluation)
- Alarm history: `aws cloudwatch describe-alarm-history --alarm-name {name} --max-records 10`
- Actions configured (SNS topics, etc.)

---

### Phase 11F: AI Infrastructure Copilot

**Goal:** Add AI-powered analysis capabilities throughout the AWS section.

**Implementation:**

1. **Per-resource AI analysis:** On every resource detail view (Phase 11E), add an "Analyze with AI" button. Send the resource's metadata + recent metrics to Claude and ask for:
   - Is this resource healthy? Why/why not?
   - Is it right-sized? (over/under provisioned based on metrics)
   - What risks exist? (single AZ, no backups, stale launch config, etc.)
   - What should an SRE check next?

2. **Alarm triage AI:** On the CloudWatch Alarms section, add an "AI Triage" button that sends all active alarms to Claude and asks:
   - Which alarms are most urgent?
   - Are any alarms likely related (same root cause)?
   - What's the likely blast radius?
   - Suggested investigation steps for each alarm

3. **Natural language infrastructure queries:** At the top of AWSHealthView, add a text field: "Ask about your infrastructure..." where the user can type questions like:
   - "Which instances are using the most CPU?"
   - "Are there any single-AZ databases?"
   - "Show me all resources in us-east-1 that are unhealthy"
   - "What changed in the last hour?"
   The query goes to Claude with the current infrastructure context, and Claude returns a formatted answer.

4. **"Explain this to me" button** on every section header — geared toward junior SREs. Sends the section's data to Claude with the prompt: "Explain what these resources are, why they matter for reliability, and what this SRE should pay attention to. Assume the reader is a junior SRE who is learning. Be encouraging and educational."

---

## General Guidelines

- **Compile after each sub-phase.** Run `swift build` and fix any errors before moving on.
- **Don't break existing features.** The existing Cost Explorer must continue to work exactly as-is.
- **AWS CLI error handling:** Every CLI call can fail with ExpiredTokenException (session expired), AccessDeniedException (insufficient permissions), or throttling. Handle each gracefully:
  - Expired: show "Session expired" banner with "Re-login" button
  - Access denied: show "Insufficient permissions for {resource}" but don't block other sections
  - Throttling: add a 1-second delay and retry once
- **Performance:** AWS CLI calls are slow (1-3 seconds each). Fetch all sections in parallel. Show each section as it loads — don't wait for all to complete. Use `TaskGroup` for concurrency.
- **Region handling:** Most AWS commands need `--region`. If the profile has a default region in `~/.aws/config`, use that. Otherwise default to `us-east-1`. The region filter in the UI should override this.
- **Dark mode:** All views must support both light and dark macOS appearances.
- **Commit after each phase** (11A, 11B, 11C, 11D, 11E, 11F) with a descriptive commit message.
