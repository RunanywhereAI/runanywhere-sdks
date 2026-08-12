//
//  WorkflowEditorViewModel+Selection.swift
//  RunAnywhereAI
//
//  What is selected, and nothing else. Selecting never edits the graph, which is
//  why it sits apart from the mutation and undo machinery: a marquee sweep across
//  fifty cards has to cost nothing and leave no undo step behind.
//

import Foundation

extension WorkflowEditorViewModel {
    // MARK: - Selection

    func select(_ nodeID: String, additive: Bool) {
        selectedEdgeID = nil
        if additive {
            if selectedNodeIDs.contains(nodeID) {
                selectedNodeIDs.remove(nodeID)
            } else {
                selectedNodeIDs.insert(nodeID)
            }
        } else {
            selectedNodeIDs = [nodeID]
        }
    }

    func selectEdge(_ edgeID: String) {
        selectedNodeIDs = []
        selectedEdgeID = edgeID
    }

    func clearSelection() {
        selectedNodeIDs = []
        selectedEdgeID = nil
    }

    func setMarqueeSelection(_ ids: Set<String>, base: Set<String>) {
        selectedEdgeID = nil
        selectedNodeIDs = base.union(ids)
    }
}
