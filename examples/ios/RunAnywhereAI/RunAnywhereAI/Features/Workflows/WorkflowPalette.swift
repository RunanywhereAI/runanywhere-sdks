//
//  WorkflowPalette.swift
//  RunAnywhereAI
//
//  The left sidebar: the fixed node types, the installed packs sitting in the
//  category each one declared, the pack library, the schedules the host is
//  running, and the saved workflows.
//
//  A pack row is the same affordance as a node row — click to place, drag onto
//  the canvas — because from the user's side an installed pack *is* a node.
//

#if os(macOS)

import RunAnywhere
import SwiftUI

/// What a palette row hands to the canvas. Both arms travel as JSON through the
/// same drag representation, so the drop site resolves one type rather than
/// guessing between two.
enum WorkflowPaletteItem: Codable, Transferable, Hashable {
    case kind(WorkflowNodeKind)
    case pack(String)

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

struct WorkflowPalette: View {
    var viewModel: WorkflowEditorViewModel
    let onAdd: (WorkflowPaletteItem) -> Void
    let onLoad: (String) -> Void
    let onExport: (String) -> Void

    private var scheduler: WorkflowScheduler { WorkflowScheduler.shared }
    private var packStore: WorkflowPackStore { viewModel.packStore }

    var body: some View {
        List {
            ForEach(WorkflowNodeCategory.allCases) { category in
                categorySection(category)
            }

            ForEach(packStore.customCategories, id: \.self) { category in
                Section(category) {
                    ForEach(packStore.packs(inCategory: category), id: \.id) { pack in
                        packRow(pack)
                    }
                }
            }

            packLibrarySection

            if !scheduler.entries.isEmpty {
                Section("Scheduled") {
                    ForEach(scheduler.entries) { entry in
                        scheduleRow(entry)
                    }
                }
            }

            librarySection
        }
        .listStyle(.sidebar)
    }

    // MARK: - Nodes

    @ViewBuilder
    private func categorySection(_ category: WorkflowNodeCategory) -> some View {
        let kinds = WorkflowNodeKind.placeable.filter { $0.category == category }
        let packs = packStore.packs(inCategory: category.rawValue)
        if !kinds.isEmpty || !packs.isEmpty {
            Section(category.rawValue) {
                ForEach(kinds) { kind in
                    paletteRow(kind)
                }
                ForEach(packs, id: \.id) { pack in
                    packRow(pack)
                }
            }
        }
    }

    private func paletteRow(_ kind: WorkflowNodeKind) -> some View {
        Button {
            onAdd(.kind(kind))
        } label: {
            HStack(spacing: Space.sm) {
                rowIcon(kind.systemImage, tint: kind.category.accent)

                Text(kind.title)
                    .appType(.body)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(WorkflowPaletteItem.kind(kind))
        .help("Click to add, or drag onto the canvas")
    }

    private func packRow(_ pack: RANodePack) -> some View {
        Button {
            onAdd(.pack(pack.id))
        } label: {
            HStack(spacing: Space.sm) {
                rowIcon(pack.resolvedSymbol, tint: pack.accent)

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(pack.displayName)
                        .appType(.body)
                        .lineLimit(1)
                    Text(pack.subtitle)
                        .appType(.caption)
                        .foregroundStyle(AppColors.mutedForeground)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(WorkflowPaletteItem.pack(pack.id))
        .help(pack.description_p.isEmpty
            ? "Click to add, or drag onto the canvas"
            : pack.description_p)
    }

    private func rowIcon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .appType(.caption)
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(
                tint.opacity(0.14),
                in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
            )
    }

    // MARK: - Pack library

    @ViewBuilder private var packLibrarySection: some View {
        Section("Node Packs") {
            if packStore.installedPacks.isEmpty {
                Text("No packs installed")
                    .appType(.caption)
                    .foregroundStyle(AppColors.mutedForeground)
            } else {
                ForEach(packStore.installedPacks, id: \.id) { pack in
                    packLibraryRow(pack)
                }
            }
        }
    }

    private func packLibraryRow(_ pack: RANodePack) -> some View {
        HStack(spacing: Space.sm) {
            rowIcon(pack.resolvedSymbol, tint: pack.accent)

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(pack.displayName)
                    .appType(.body)
                    .lineLimit(1)
                Text(pack.subtitle)
                    .appType(.caption)
                    .foregroundStyle(AppColors.mutedForeground)
                    .lineLimit(1)
                Text(pack.paletteCategory)
                    .appType(.caption)
                    .foregroundStyle(pack.accent)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.xs)

            Button {
                Task { await viewModel.deletePack(pack) }
            } label: {
                Image(systemName: "trash")
                    .appType(.caption)
                    .foregroundStyle(AppColors.mutedForeground)
            }
            .buttonStyle(.plain)
            .help("Uninstall this pack. Nodes that use it become placeholders.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Schedules

    private func scheduleRow(_ entry: WorkflowScheduler.Entry) -> some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            HStack(spacing: Space.xs) {
                Text(entry.name)
                    .appType(.body)
                    .lineLimit(1)
                Spacer(minLength: Space.xs)
                Toggle("", isOn: Binding(
                    get: { entry.isEnabled },
                    set: { scheduler.setEnabled($0, for: entry.workflowID) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(entry.isEnabled ? "Disable this schedule" : "Enable this schedule")
            }

            Text(entry.summary)
                .appType(.caption)
                .foregroundStyle(AppColors.mutedForeground)
                .lineLimit(1)

            Text(nextFireText(entry))
                .appType(.caption)
                .foregroundStyle(nextFireColor(entry))
                .lineLimit(1)

            if let outcome = entry.lastOutcome {
                Text(outcome)
                    .appType(.caption)
                    .foregroundStyle(AppColors.mutedForeground)
                    .lineLimit(1)
            }
        }
        .contextMenu {
            Button("Open") { onLoad(entry.workflowID) }
            Button("Run Now") {
                Task { await scheduler.runNow(entry.workflowID) }
            }
        }
    }

    private func nextFireText(_ entry: WorkflowScheduler.Entry) -> String {
        guard entry.isEnabled else { return "Paused" }
        guard let next = entry.nextFireDate else { return "Not scheduled by this host" }
        return "Next " + next.formatted(date: .omitted, time: .shortened)
    }

    private func nextFireColor(_ entry: WorkflowScheduler.Entry) -> Color {
        guard entry.isEnabled else { return AppColors.mutedForeground }
        return entry.isScheduled ? AppColors.successText : AppColors.warningText
    }

    // MARK: - Saved workflows

    @ViewBuilder private var librarySection: some View {
        Section("Library") {
            if viewModel.savedWorkflows.isEmpty {
                Text("No saved workflows")
                    .appType(.caption)
                    .foregroundStyle(AppColors.mutedForeground)
            } else {
                ForEach(viewModel.savedWorkflows, id: \.id) { summary in
                    libraryRow(summary)
                }
            }
        }
    }

    private func libraryRow(_ summary: RAWorkflowSummary) -> some View {
        Button {
            onLoad(summary.id)
        } label: {
            VStack(alignment: .leading, spacing: Space.hair) {
                HStack(spacing: Space.xs) {
                    Text(summary.name)
                        .appType(.body)
                        .lineLimit(1)
                    if summary.id == viewModel.workflowID {
                        Circle()
                            .fill(AppColors.brand)
                            .frame(width: 5, height: 5)
                    }
                }
                Text(libraryMeta(summary))
                    .appType(.caption)
                    .foregroundStyle(AppColors.mutedForeground)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Export…") { onExport(summary.id) }
            Button("Delete", role: .destructive) {
                Task { await viewModel.delete(id: summary.id) }
            }
        }
    }

    private func libraryMeta(_ summary: RAWorkflowSummary) -> String {
        let updated = Date(timeIntervalSince1970: TimeInterval(summary.updatedAtMs) / 1000)
        let relative = updated.formatted(.relative(presentation: .named))
        return "\(summary.nodeCount) nodes · \(relative)"
    }
}

/// The sidebar at its real width, with an installed pack sitting in the category
/// it declared and the same pack listed in the library section below.
#Preview("Palette with packs") {
    let viewModel = WorkflowEditorViewModel()
    viewModel.packStore.seedForPreview([WorkflowPreviewFixtures.installedPack])

    return WorkflowPalette(viewModel: viewModel) { _ in
    } onLoad: { _ in
    } onExport: { _ in
    }
    .frame(width: 260, height: 720)
}

#endif
