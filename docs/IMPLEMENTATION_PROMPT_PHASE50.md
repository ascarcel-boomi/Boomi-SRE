# Boomi SRE App — Phase 50: Product Knowledge Integration — AI Context on Product Switch

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. This is Phase F of the v2 evolution (see `docs/VISION_V2.md`).

**Read these files first:**
- `docs/VISION_V2.md` — the "Product Knowledge Integration" section
- `BoomiSRE/Sources/Models/ProductContext.swift` — product model with filter patterns, 6 default products
- `BoomiSRE/Sources/Models/AppState.swift` — `selectedProductId`, `products`
- `BoomiSRE/Sources/Views/DashboardView.swift` — home page where the context brief will appear
- `BoomiSRE/Sources/Services/KnowledgeBaseService.swift` — KB article fetching from GitHub repo
- `BoomiSRE/Sources/Services/ClaudeService.swift` — AI chat/analysis
- `BoomiSRE/Sources/ViewModels/ChatViewModel.swift` — copilot (system prompt injection)
- `BoomiSRE/Sources/ViewModels/OnCallViewModel.swift` — on-call data (schedules, participants)
- `BoomiSRE/Sources/ViewModels/DashboardViewModel.swift` — data fetching, alert data

---

## Goal

When an SRE switches product context (e.g., a CAM SRE starting an MFT on-call shift), the app should proactively provide everything they need to know about that product:

1. **Key runbooks and SOPs** for this product — surfaced automatically, not searched for
2. **Current alert patterns** — "MFT typically sees X type of alerts, here's what they mean"
3. **Escalation contacts** — who to call if things go wrong
4. **Architecture overview** — quick summary of what this product is and how it's structured
5. **Recent activity** — what's happened with this product recently (alerts, incidents, deployments)

The SRE shouldn't have to go hunting for information about an unfamiliar product. The app brings it to them.

---

## Implementation

### Phase 50A: Extend ProductContext with Knowledge Fields

Add new fields to `ProductContext` for knowledge and escalation info:

```swift
struct ProductContext: Identifiable, Codable, Hashable {
    // ... existing filter fields ...

    // Knowledge & Escalation (NEW)
    var description: String           // 2-3 sentence product description
    var architectureNotes: String     // brief architecture overview
    var escalationContacts: [EscalationContact]  // who to call
    var keyRunbooks: [String]         // KB article paths (e.g., "sops/update-amis-cve-remediation.md")
    var commonAlertPatterns: [String] // descriptions of typical alerts and what they mean
}

struct EscalationContact: Codable, Hashable {
    var name: String
    var role: String           // "Team Lead", "On-Call Primary", "Product Owner"
    var slackHandle: String    // e.g., "@jbeck-tibco"
    var email: String          // e.g., "james.beck@boomi.com"
}
```

Update the defaults with real product knowledge:

```swift
ProductContext(
    id: "cam-sre",
    name: "CAM SRE (Mashery)",
    shortName: "CAM",
    // ... existing filter fields ...
    description: "Cloud API Management (Mashery) — Boomi's API gateway platform. Handles API traffic management, analytics, and developer portals for enterprise customers worldwide.",
    architectureNotes: "Multi-region deployment (us-east-1, eu-west-1, us-west-2, ap-southeast). Stack: EC2 instances behind ALBs in ASGs, Aurora RDS databases, Elasticsearch clusters, Cassandra, Redis/ElastiCache. Managed via Terraform (apim-sre-terraform-iac), Ansible, and Puppet.",
    escalationContacts: [
        EscalationContact(name: "Adam Scarcella", role: "SRE Manager", slackHandle: "@ascarcel-boomi", email: "adam.scarcella@boomi.com"),
        EscalationContact(name: "James Beck", role: "Senior SRE", slackHandle: "@jbeck-tibco", email: "james.beck@boomi.com"),
    ],
    keyRunbooks: [
        "sops/creating-a-pcr.md",
        "sops/update-amis-cve-remediation.md",
        "sops/create-customer-load-balancer.md",
        "runbooks/api-v2-lb-500.md",
        "runbooks/tm-db-005-row-lock.md",
        "on-call-guide.md",
    ],
    commonAlertPatterns: [
        "ALB 5xx spikes — usually indicates backend instance health issues. Check ASG instance health and recent deployments.",
        "Aurora CPU/connection spikes — check for long-running queries, connection pool exhaustion, or traffic surge.",
        "Elasticsearch cluster red — check node health, disk space, and shard allocation.",
        "Cassandra repair failures — check disk space and compaction status.",
    ]
),
// ... similar for MFT, DI, MCS, Platform ...
```

For products you don't have detailed knowledge for yet (MFT, DI, MCS, Platform), use placeholder text:
```swift
description: "Managed File Transfer (Thru) — Boomi's secure file transfer platform including Advanced File Transfer (AFT) and File Sharing (FS).",
architectureNotes: "Architecture details to be documented. Check the Knowledge Base for available runbooks.",
escalationContacts: [],
keyRunbooks: [],
commonAlertPatterns: []
```

### Phase 50B: Create Product Briefing on Context Switch

When the SRE switches product context, show a **product briefing card** at the top of the feed (or dashboard):

Create `BoomiSRE/Sources/Views/Shared/ProductBriefingCard.swift`:

```swift
struct ProductBriefingCard: View {
    let product: ProductContext
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = true
    @State private var dismissed = false

    var body: some View {
        if dismissed || product.id == "all" { EmptyView() }
        else {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: product.icon)
                        .font(.title3)
                        .foregroundStyle(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Now viewing: \(product.name)")
                            .font(.callout.bold())
                        Text(product.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                    }
                    Spacer()
                    Button {
                        withAnimation { dismissed = true }
                    } label: {
                        Image(systemName: "xmark").font(.caption)
                    }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
                }

                if isExpanded {
                    // Architecture overview
                    if !product.architectureNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Architecture", systemImage: "cpu")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            Text(product.architectureNotes)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                    }

                    // Key runbooks
                    if !product.keyRunbooks.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Key Runbooks", systemImage: "book.closed")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(product.keyRunbooks.prefix(4), id: \.self) { path in
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text").font(.caption2).foregroundStyle(.tertiary)
                                    Text(path.components(separatedBy: "/").last?.replacingOccurrences(of: ".md", with: "").replacingOccurrences(of: "-", with: " ").capitalized ?? path)
                                        .font(.caption)
                                        .foregroundStyle(.accentColor)
                                }
                            }
                        }
                    }

                    // Common alert patterns
                    if !product.commonAlertPatterns.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Common Alerts", systemImage: "bell.badge")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(product.commonAlertPatterns.prefix(3), id: \.self) { pattern in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•").foregroundStyle(.tertiary)
                                    Text(pattern)
                                        .font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }

                    // Escalation contacts
                    if !product.escalationContacts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Escalation", systemImage: "person.2")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(product.escalationContacts, id: \.name) { contact in
                                HStack(spacing: 8) {
                                    Text(contact.name).font(.caption.bold())
                                    Text(contact.role).font(.caption).foregroundStyle(.secondary)
                                    if !contact.slackHandle.isEmpty {
                                        Text(contact.slackHandle).font(.caption).foregroundStyle(.accentColor)
                                    }
                                }
                            }
                        }
                    }

                    // Collapse button
                    Button("Show Less") {
                        withAnimation { isExpanded = false }
                    }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                } else {
                    Button("Show More") {
                        withAnimation { isExpanded = true }
                    }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(.accentColor)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.15)))
        }
    }
}
```

### Phase 50C: Show Briefing Card on Product Switch

In `DashboardView` (or `FeedView`), show the `ProductBriefingCard` at the top when the product context changes:

```swift
// State to track when product changed
@State private var showProductBriefing = false
@State private var briefingProductId = ""

// In the body, at the top of the scroll content:
if showProductBriefing, let product = appState.selectedProduct, product.id != "all" {
    ProductBriefingCard(product: product)
        .padding(.horizontal, 20).padding(.top, 12)
}

// Trigger when product changes:
.onChange(of: appState.selectedProductId) {
    if appState.selectedProductId != "all" && appState.selectedProductId != briefingProductId {
        briefingProductId = appState.selectedProductId
        withAnimation { showProductBriefing = true }
    } else {
        showProductBriefing = false
    }
}
```

The briefing card is dismissible (X button) — once the SRE has read it, they can close it. It reappears when they switch to a different product.

### Phase 50D: Inject Product Knowledge into AI Copilot

When the SRE asks the AI copilot a question, the product context should be included in the system prompt so the AI gives product-specific answers:

In `ChatViewModel.send()`, enhance the system prompt:

```swift
// Build product context for the system prompt
var productContext = ""
if let product = appState.selectedProduct, product.id != "all" {
    productContext = """

    CURRENT PRODUCT CONTEXT: \(product.name)
    Description: \(product.description)
    Architecture: \(product.architectureNotes)
    Common alert patterns:
    \(product.commonAlertPatterns.map { "- \($0)" }.joined(separator: "\n"))
    Escalation contacts:
    \(product.escalationContacts.map { "- \($0.name) (\($0.role)) — \($0.slackHandle)" }.joined(separator: "\n"))
    Key runbooks: \(product.keyRunbooks.joined(separator: ", "))

    When answering questions, prioritize information relevant to \(product.shortName). Reference specific runbooks and alert patterns when applicable.
    """
}
```

Append `productContext` to the system prompt in the `chat()` call. This way when an SRE on MFT on-call asks "what should I check for this alert?", the AI knows MFT's architecture, common alert patterns, and relevant runbooks.

### Phase 50E: Auto-Fetch Relevant KB Articles on Product Switch

When the product context changes, automatically fetch KB articles tagged for that product and surface the top ones:

```swift
// In DashboardViewModel or a new ProductKnowledgeViewModel:
func loadProductKnowledge(product: ProductContext, appState: AppState) async {
    guard !product.kbTags.isEmpty, !appState.githubToken.isEmpty else { return }

    // Fetch KB articles and filter by product tags
    let kbService = KnowledgeBaseService()
    do {
        let allArticles = try await kbService.fetchArticles(token: appState.githubToken)
        let relevant = allArticles.filter { article in
            product.kbTags.contains { tag in
                article.path.lowercased().contains(tag.lowercased()) ||
                article.title.lowercased().contains(tag.lowercased())
            }
        }
        // Store for display in the briefing card or feed
        productRelevantArticles = Array(relevant.prefix(6))
    } catch {
        // KB fetch failure is non-critical
    }
}
```

If KB articles are found, enhance the `ProductBriefingCard` to show them with clickable links that navigate to the Knowledge Base section.

### Phase 50F: Product Configuration in Settings — Knowledge Fields

Extend the Product Settings tab (from Phase 45F) to allow editing the knowledge fields:

Add editable text fields for each product:
- Description (TextEditor, 2-3 lines)
- Architecture Notes (TextEditor, 3-4 lines)
- Escalation Contacts (add/remove rows: name, role, slack, email)
- Key Runbooks (list of paths, with a picker from discovered KB articles)
- Common Alert Patterns (add/remove text entries)

These should be pre-filled from the defaults but fully editable by the user or team lead. Persist changes to config.

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Commit with message: "Add Product Knowledge Integration — AI context and briefing on product switch"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.
