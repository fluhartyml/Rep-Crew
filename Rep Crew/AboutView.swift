//
//  AboutView.swift
//  Rep Crew
//
//  Version, build number and commit, so any copy of the app can say exactly which build it is.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rep Crew").font(AppFont.title)
                        Text("Daily accountability").font(AppFont.body)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    row("Version", version)
                    row("Build", BuildStamp.number)
                    row("Commit", BuildStamp.isStamped ? BuildStamp.commit : "not stamped")
                    row("Branch", BuildStamp.branch)
                    row("Built", BuildStamp.built)
                } header: {
                    Text("Build").font(AppFont.bodyBold).textCase(nil)
                }

                // Published contact information (App Review guideline 1.2) — his pick, 2026-10-22:
                // "make a support page on fluharty.me".
                Section {
                    Link(destination: URL(string: "https://fluharty.me/support/repcrew")!) {
                        Label("Rep Crew Support", systemImage: "questionmark.circle").font(AppFont.bodyBold)
                    }
                    Link(destination: URL(string: "mailto:michael@fluharty.com")!) {
                        Label("Email Support", systemImage: "envelope").font(AppFont.bodyBold)
                    }
                } header: {
                    Text("Need help?").font(AppFont.bodyBold).textCase(nil)
                } footer: {
                    Text("Include the build number above.").font(AppFont.body)
                }

                Section {
                    NavigationLink { AgreementReadView() } label: {
                        Label("User Agreement (EULA)", systemImage: "doc.text").font(AppFont.bodyBold)
                    }
                }

                Section {
                    Text("Rep Crew is a way to keep track of your own exercise. It is not medical advice. Check with a doctor before starting a new exercise routine, and stop if something hurts.")
                        .font(AppFont.body)
                } header: {
                    Text("Your health").font(AppFont.bodyBold).textCase(nil)
                }

                Section {
                    Text("Rep Crew is not affiliated with, endorsed by, or an official product of Apple Inc. Rep Crew uses only Apple's own frameworks and contains no third-party code.")
                        .font(AppFont.body)
                } header: {
                    Text("Credits").font(AppFont.bodyBold).textCase(nil)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(AppFont.bodyBold)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(AppFont.body)
            Spacer()
            Text(value).font(AppFont.bodyBold).monospacedDigit().textSelection(.enabled)
        }
    }
}
