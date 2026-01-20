import SwiftUI

// MARK: - Mind Map Data Builder
/// Builds the mind map tree structure from goals and todos
class MindMapDataBuilder {

    // MARK: - Tag Extraction from Goals

    /// Parses all goal lines and extracts tags
    /// Supports both section headers with tags and individual lines with tags
    /// Input: "**People Management** #people" or "- Hire developer #hiring"
    static func parseGoalSections(from goalsText: String) -> [GoalSectionWithTag] {
        let lines = goalsText.components(separatedBy: .newlines)
        var sectionsByTag: [String: GoalSectionWithTag] = [:]
        var currentSectionTag: String? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                continue
            }

            // Check for bold headers: **text** or **text** #tag
            if trimmed.hasPrefix("**") {
                let parsed = parseHeaderWithTag(trimmed, isBoldStyle: true)
                if let tag = parsed.tag, let title = parsed.title {
                    currentSectionTag = tag
                    if sectionsByTag[tag] == nil {
                        sectionsByTag[tag] = GoalSectionWithTag(title: title, tag: tag, items: [])
                    }
                } else {
                    currentSectionTag = nil
                }
            }
            // Also support # headers: # Header #tag
            else if trimmed.hasPrefix("#") && !trimmed.hasPrefix("##") {
                let parsed = parseHeaderWithTag(trimmed, isBoldStyle: false)
                if let tag = parsed.tag, let title = parsed.title {
                    currentSectionTag = tag
                    if sectionsByTag[tag] == nil {
                        sectionsByTag[tag] = GoalSectionWithTag(title: title, tag: tag, items: [])
                    }
                } else {
                    currentSectionTag = nil
                }
            }
            else {
                // Content line - check if it has its own tag
                var content = trimmed

                // Remove list markers
                if content.hasPrefix("- ") || content.hasPrefix("* ") {
                    content = String(content.dropFirst(2))
                } else if let match = content.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                    content = String(content[match.upperBound...])
                }

                content = content.trimmingCharacters(in: .whitespaces)

                if content.isEmpty {
                    continue
                }

                // Check if this line has its own tag
                let lineTagInfo = extractTagFromLine(content)

                if let lineTag = lineTagInfo.tag {
                    // Line has its own tag - add to that tag's section
                    let cleanContent = lineTagInfo.content
                    if sectionsByTag[lineTag] == nil {
                        // Create orphan section for this tag
                        sectionsByTag[lineTag] = GoalSectionWithTag(title: "#\(lineTag)", tag: lineTag, items: [])
                    }
                    if !cleanContent.isEmpty {
                        sectionsByTag[lineTag]?.items.append(cleanContent)
                    }
                } else if let sectionTag = currentSectionTag {
                    // No line tag, add to current section
                    sectionsByTag[sectionTag]?.items.append(content)
                }
            }
        }

        // Return in sorted order by tag for consistent positioning
        return sectionsByTag.values.sorted { $0.tag < $1.tag }
    }

    /// Extracts a tag from the end of a line
    /// Input: "Hire new developer #hiring"
    /// Output: (content: "Hire new developer", tag: "hiring")
    private static func extractTagFromLine(_ line: String) -> (content: String, tag: String?) {
        if let tagRange = line.range(of: #"\s*#(\w+)\s*$"#, options: .regularExpression) {
            let tagMatch = line[tagRange]
            if let hashIndex = tagMatch.firstIndex(of: "#") {
                let tag = String(tagMatch[tagMatch.index(after: hashIndex)...]).trimmingCharacters(in: .whitespaces)
                let content = String(line[..<tagRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                return (content, tag)
            }
        }
        return (line, nil)
    }

    /// Parses a header line to extract title and tag
    /// Input: "**People Management** #people" or "# Project Alpha #alpha"
    /// Output: (title: "People Management", tag: "people")
    private static func parseHeaderWithTag(_ line: String, isBoldStyle: Bool) -> (title: String?, tag: String?) {
        var workingLine = line

        // Extract tag first (look for #tag at the end)
        var extractedTag: String? = nil
        if let tagRange = workingLine.range(of: #"\s+#(\w+)\s*$"#, options: .regularExpression) {
            let tagMatch = workingLine[tagRange]
            // Extract just the tag name (without # and whitespace)
            if let tagStart = tagMatch.firstIndex(of: "#") {
                extractedTag = String(tagMatch[tagMatch.index(after: tagStart)...]).trimmingCharacters(in: .whitespaces)
                workingLine = String(workingLine[..<tagRange.lowerBound])
            }
        }

        // Now extract the title
        var extractedTitle: String? = nil

        if isBoldStyle {
            // Bold style: **Title**
            if workingLine.hasPrefix("**") {
                if let endRange = workingLine.range(of: "**", range: workingLine.index(workingLine.startIndex, offsetBy: 2)..<workingLine.endIndex) {
                    let startIdx = workingLine.index(workingLine.startIndex, offsetBy: 2)
                    extractedTitle = String(workingLine[startIdx..<endRange.lowerBound])
                }
            }
        } else {
            // Markdown header style: # Title or ## Title
            var headerText = workingLine
            while headerText.hasPrefix("#") {
                headerText = String(headerText.dropFirst())
            }
            extractedTitle = headerText.trimmingCharacters(in: .whitespaces)
        }

        return (extractedTitle, extractedTag)
    }

    // MARK: - Tree Building

    /// Tags to exclude from the mind map (special tags that clutter the view)
    private static let excludedTags: Set<String> = ["today", "urgent"]

    /// Builds the complete mind map tree from goals and todos
    static func buildMindMapTree(goals: String, todos: [Todo], top5Todos: [Todo]) -> [MindMapNode] {
        // 1. Parse goal sections with tags (filter out excluded tags)
        let goalSections = parseGoalSections(from: goals)
            .filter { !excludedTags.contains($0.tag.lowercased()) }

        // 2. Combine all todos
        let allTodos = todos + top5Todos

        // 3. Get all unique tags from todos (excluding special tags)
        let allTodoTags = Set(allTodos.flatMap { $0.tags })
            .filter { !excludedTags.contains($0.lowercased()) }

        // 4. Get tags that are defined in goals
        let goalTags = Set(goalSections.map { $0.tag })

        // 5. Create root nodes for goal sections with tags
        var nodes: [MindMapNode] = goalSections.map { section in
            let matchingTodos = allTodos.filter { $0.tags.contains(section.tag) }
            let childNodes = matchingTodos.map { MindMapChildNode(from: $0) }

            // Create goal items from the section's bullet points
            let goalItems = section.items.enumerated().map { index, item in
                MindMapGoalItem(title: item, parentTag: section.tag, index: index)
            }

            return MindMapNode(
                tag: section.tag,
                title: section.title,
                nodeType: .goalSection,
                children: childNodes,
                goalItems: goalItems
            )
        }

        // 6. Create orphan nodes for tags in todos but not in goals
        let orphanTags = allTodoTags.subtracting(goalTags)
        for tag in orphanTags.sorted() {
            let matchingTodos = allTodos.filter { $0.tags.contains(tag) }
            let childNodes = matchingTodos.map { MindMapChildNode(from: $0) }

            // Only add if there are matching todos
            if !childNodes.isEmpty {
                let node = MindMapNode(
                    tag: tag,
                    title: "#\(tag)",  // Use tag as title for orphan nodes
                    nodeType: .orphanTag,
                    children: childNodes
                )
                nodes.append(node)
            }
        }

        // Filter out any nodes with no todos (goal items alone don't qualify)
        return nodes.filter { !$0.children.isEmpty }
    }

    // MARK: - Statistics

    /// Returns statistics about the mind map
    static func getStatistics(for nodes: [MindMapNode]) -> (totalNodes: Int, totalTodos: Int, goalSectionCount: Int, orphanTagCount: Int) {
        let totalTodos = nodes.reduce(0) { $0 + $1.children.count }
        let goalSectionCount = nodes.filter { $0.nodeType == .goalSection }.count
        let orphanTagCount = nodes.filter { $0.nodeType == .orphanTag }.count

        return (nodes.count, totalTodos, goalSectionCount, orphanTagCount)
    }
}
