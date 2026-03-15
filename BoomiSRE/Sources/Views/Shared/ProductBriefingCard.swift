import SwiftUI

struct ProductBriefingCard: View {
    let product: ProductContext
    var kbArticles: [KnowledgeBaseService.KBArticle] = []
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = true
    @State private var dismissed = false

    var body: some View {
        if dismissed || product.id == "all" {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(alignment: .top) {
                    Image(systemName: product.icon)
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Now viewing: \(product.name)")
                            .font(.callout.bold())
                        if !product.productDescription.isEmpty {
                            Text(product.productDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(isExpanded ? nil : 2)
                        }
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { dismissed = true }
                    } label: {
                        Image(systemName: "xmark").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }

                if isExpanded {
                    if !product.architectureNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Architecture", systemImage: "cpu")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            Text(product.architectureNotes)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                    }

                    if !product.keyRunbooks.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Key Runbooks", systemImage: "book.closed")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(product.keyRunbooks.prefix(4), id: \.self) { path in
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text").font(.caption2).foregroundStyle(.tertiary)
                                    Text(path.components(separatedBy: "/").last?
                                        .replacingOccurrences(of: ".md", with: "")
                                        .replacingOccurrences(of: "-", with: " ")
                                        .capitalized ?? path)
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }

                    if !kbArticles.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("From Knowledge Base", systemImage: "books.vertical")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(kbArticles.prefix(4)) { article in
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text").font(.caption2).foregroundStyle(.tertiary)
                                    Text(article.title).font(.caption).foregroundStyle(Color.accentColor).lineLimit(1)
                                }
                            }
                        }
                    }

                    if !product.commonAlertPatterns.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Common Alerts", systemImage: "bell.badge")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(product.commonAlertPatterns.prefix(3), id: \.self) { pattern in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•").font(.caption).foregroundStyle(.tertiary)
                                    Text(pattern).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }

                    if !product.escalationContacts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Escalation", systemImage: "person.2")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(product.escalationContacts, id: \.name) { contact in
                                HStack(spacing: 8) {
                                    Text(contact.name).font(.caption.bold())
                                    Text(contact.role).font(.caption).foregroundStyle(.secondary)
                                    if !contact.slackHandle.isEmpty {
                                        Text(contact.slackHandle).font(.caption).foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    }

                    Button("Show Less") {
                        withAnimation(.easeInOut(duration: 0.15)) { isExpanded = false }
                    }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                } else {
                    Button("Show More") {
                        withAnimation(.easeInOut(duration: 0.15)) { isExpanded = true }
                    }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(Color.accentColor)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.15)))
        }
    }
}
